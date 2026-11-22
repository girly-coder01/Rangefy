"""Keeper jobs. Vaults pick ranges on-chain; jobs only trigger allowed actions and never raise."""

from __future__ import annotations

import random
import threading
import time
from dataclasses import dataclass

import structlog

from ..chain.client import RangefyChain
from ..chain.tx import TxResult, TxSender
from ..config import Settings
from ..data.collector import CandleCache, fetch_spot
from ..inference.forecaster import Forecaster
from ..inference.signal_mapper import OnchainSignal, should_post, to_onchain
from ..store.db import Store

log = structlog.get_logger()
MAX_UINT = 2**256 - 1


class VaultLocks:
    """One in-flight tx per vault."""

    def __init__(self) -> None:
        self._busy: set[str] = set()
        self._lock = threading.Lock()

    def acquire(self, vault: str) -> bool:
        with self._lock:
            if vault in self._busy:
                return False
            self._busy.add(vault)
            return True

    def release(self, vault: str) -> None:
        with self._lock:
            self._busy.discard(vault)


def _status(r: TxResult) -> str:
    return "ok" if r.ok else ("reverted" if r.reverted else "failed")


@dataclass
class SignalJob:
    chain: RangefyChain
    sender: TxSender
    store: Store
    forecaster: Forecaster
    cache: CandleCache
    name: str = "signal"

    def __call__(self) -> str:
        df = self.cache.refresh()
        f = self.forecaster.forecast(df)
        sig = to_onchain(f, base_is_token0=self.chain.priced.weth_is_token0)
        pool_id = "0x" + self.chain.key.pool_id.hex()

        last_row = self.store.last_posted_signal(pool_id)
        last = None
        age = None
        if last_row:
            last = OnchainSignal(last_row["sigma_ticks"], last_row["drift_ticks"], last_row["regime"],
                                 last_row["confidence_bps"], last_row["model_version"].encode())
            age = time.time() - last_row["ts"]
        post, reason = should_post(sig, last, age)

        tx = None
        if post:
            tx = self.sender.send(self.chain.oracle.functions.postSignal(self.chain.key.pool_id, *sig.as_args()),
                                  label="postSignal")
        self.store.add_signal(
            pool_id, sig.sigma_ticks, sig.drift_ticks, sig.regime, sig.confidence_bps, f.model_version,
            posted=bool(tx and tx.ok), reason=reason, tx_hash=tx.tx_hash if tx else None,
            error=tx.error if tx and not tx.ok else None, breakdown=f.to_dict(),
        )
        return f"sigma={sig.sigma_ticks} regime={sig.regime} {reason}{' posted' if tx and tx.ok else ''}"


@dataclass
class RebalanceJob:
    chain: RangefyChain
    sender: TxSender
    store: Store
    locks: VaultLocks
    name: str = "rebalance"

    def __call__(self) -> str:
        done = 0
        for v in self.chain.all_vaults():
            needed, reason = self.chain.needs_rebalance(v)
            if not needed or not self.locks.acquire(v):
                continue
            try:
                r = self.sender.send(self.chain.vault(v).functions.rebalance(), label=f"rebalance {v[:8]}")
                self.store.add_keeper_event(self.name, v, "rebalance", _status(r), reason, r.tx_hash, r.gas_used,
                                            r.error)
                done += int(r.ok)
            finally:
                self.locks.release(v)
        return f"rebalanced {done}"


@dataclass
class HarvestJob:
    chain: RangefyChain
    sender: TxSender
    store: Store
    locks: VaultLocks
    min_idle_s: int = 3600
    name: str = "harvest"

    def __call__(self) -> str:
        done = 0
        now = self.chain.block_timestamp()
        for v in self.chain.all_vaults():
            if self.chain.vault_liquidity(v) == 0 or now - self.chain.last_rebalance(v) < self.min_idle_s:
                continue
            if not self.locks.acquire(v):
                continue
            try:
                r = self.sender.send(self.chain.vault(v).functions.harvest(), label=f"harvest {v[:8]}")
                self.store.add_keeper_event(self.name, v, "harvest", _status(r), None, r.tx_hash, r.gas_used, r.error)
                done += int(r.ok)
            finally:
                self.locks.release(v)
        return f"harvested {done}"


def ensure_allowance(chain: RangefyChain, sender: TxSender, token: str, spender: str) -> None:
    t = chain.token(token)
    if t.functions.allowance(sender.address, spender).call() < MAX_UINT // 2:
        sender.send(t.functions.approve(spender, MAX_UINT), label="approve")


@dataclass
class MirrorJob:
    """Keeps the testnet pool tracking the real ETH/USD price."""

    chain: RangefyChain
    sender: TxSender
    store: Store
    settings: Settings
    spot=staticmethod(fetch_spot)
    name: str = "mirror"

    def plan(self, real: float, sqrt_price: int) -> tuple[bool, int, str, int, float, float]:
        """→ (act, target_sqrt, input_token, max_in, pool_price, deviation_bps)."""
        priced = self.chain.priced
        pool_price = priced.eth_usd(sqrt_price)
        dev_bps = abs(pool_price / real - 1) * 10_000
        target = priced.sqrt_price_x96(real)
        zero_for_one = target < sqrt_price
        token_in = priced.key.currency0 if zero_for_one else priced.key.currency1
        is_weth = token_in.lower() == priced.weth.lower()
        max_in = self.settings.mirror_max_in_token0 if is_weth else self.settings.mirror_max_in_usdc
        return dev_bps > self.settings.mirror_deviation_bps, target, token_in, max_in, pool_price, dev_bps

    def __call__(self) -> str:
        real = self.spot(self.settings.price_source)
        state = self.chain.pool_state()
        act, target, token_in, max_in, pool_price, dev = self.plan(real, state.sqrt_price_x96)
        if not act:
            self.store.add_mirror(real, pool_price, dev, "none")
            return f"in sync ({dev:.0f} bps)"
        ensure_allowance(self.chain, self.sender, token_in, self.chain.router.address)
        r = self.sender.send(
            self.chain.router.functions.swapToPrice(self.chain.key.as_tuple(), target, max_in, self.sender.address),
            label="mirror",
        )
        self.store.add_mirror(real, pool_price, dev, "swap", r.tx_hash, r.error)
        return f"swapped toward {real:.2f} ({dev:.0f} bps)"


@dataclass
class NoiseJob:
    """Small random swaps in both directions to generate fee volume for the demo (optional)."""

    chain: RangefyChain
    sender: TxSender
    store: Store
    rng: random.Random
    name: str = "noise"

    def __call__(self) -> str:
        priced = self.chain.priced
        weth_in = self.rng.random() < 0.5
        weth_amt = self.rng.uniform(0.01, 0.2)
        state = self.chain.pool_state()
        price = priced.eth_usd(state.sqrt_price_x96)
        key = self.chain.key
        if weth_in:
            token_in, amount = priced.weth, int(weth_amt * 1e18)
        else:
            token_in = key.currency1 if key.currency0.lower() == priced.weth.lower() else key.currency0
            amount = int(weth_amt * price * 1e6)
        zero_for_one = token_in.lower() == key.currency0.lower()
        ensure_allowance(self.chain, self.sender, token_in, self.chain.router.address)
        deadline = self.chain.block_timestamp() + 300
        r = self.sender.send(
            self.chain.router.functions.swapExactIn(key.as_tuple(), zero_for_one, amount, 0, self.sender.address,
                                                    deadline),
            label="noise",
        )
        self.store.add_keeper_event(self.name, None, "swap", _status(r), "weth_in" if weth_in else "usdc_in",
                                    r.tx_hash, r.gas_used, r.error)
        return f"noise swap {'mWETH' if weth_in else 'mUSDC'} in"
