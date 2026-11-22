"""Contract handles and reads. ABIs come from scripts/sync-abis.sh."""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

from web3 import Web3

from ..config import ZERO, Settings
from .pool import PoolKey, PricedPool

ABI_DIR = Path(__file__).parent / "abis"
REASONS = ("None", "OutOfRange", "NearEdge", "WidthDrift", "Initial", "IdleExcess")


def load_abi(name: str) -> list:
    return json.loads((ABI_DIR / f"{name}.json").read_text())


@dataclass
class PoolState:
    sqrt_price_x96: int
    tick: int
    ema_tick: int
    sigma: int
    drift: int
    signal_fresh: bool
    regime: int
    fee: int
    onchain_sigma: int


class RangefyChain:
    """Read helpers and contract handles. Writes go through TxSender with these handles."""

    def __init__(self, settings: Settings, w3: Web3 | None = None) -> None:
        self.s = settings
        self.w3 = w3 or Web3(Web3.HTTPProvider(settings.rpc_url, request_kwargs={"timeout": 20}))
        missing = [n for n in ("hook", "factory", "lens", "signal_oracle", "router", "token0", "token1")
                   if getattr(settings, n) == ZERO]
        if missing:
            raise ValueError(f"missing contract addresses in env: {', '.join(missing)} (run scripts/sync-abis.sh)")

    def _c(self, address: str, abi: str):
        return self.w3.eth.contract(address=Web3.to_checksum_address(address), abi=load_abi(abi))

    @cached_property
    def hook(self):
        return self._c(self.s.hook, "RangefyHook")

    @cached_property
    def factory(self):
        return self._c(self.s.factory, "VaultFactory")

    @cached_property
    def lens(self):
        return self._c(self.s.lens, "RangefyLens")

    @cached_property
    def oracle(self):
        return self._c(self.s.signal_oracle, "SignalOracle")

    @cached_property
    def router(self):
        return self._c(self.s.router, "SimpleSwapRouter")

    def vault(self, address: str):
        return self._c(address, "RangeVault")

    def token(self, address: str):
        return self._c(address, "MockERC20")

    @cached_property
    def key(self) -> PoolKey:
        return PoolKey.build(self.s.token0, self.s.token1, self.s.hook, self.s.pool_tick_spacing)

    @cached_property
    def weth(self) -> str:
        """The 18-decimal token of the pair."""
        for t in (self.key.currency0, self.key.currency1):
            if self.token(t).functions.decimals().call() == 18:
                return t
        raise ValueError("no 18-decimal token in the pool")

    @cached_property
    def priced(self) -> PricedPool:
        return PricedPool(self.key, self.weth)

    # reads

    def pool_state(self) -> PoolState:
        p = self.lens.functions.getPool(self.key.as_tuple()).call()
        # RangefyLens.PoolView field order
        return PoolState(p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[10])

    def all_vaults(self) -> list[str]:
        return list(self.factory.functions.allVaults().call())

    def needs_rebalance(self, vault: str) -> tuple[bool, str]:
        needed, reason = self.vault(vault).functions.needsRebalance().call()
        return bool(needed), REASONS[reason] if reason < len(REASONS) else str(reason)

    def vault_liquidity(self, vault: str) -> int:
        return int(self.vault(vault).functions.getPosition().call()[0])

    def last_rebalance(self, vault: str) -> int:
        return int(self.vault(vault).functions.lastRebalance().call())

    def block_timestamp(self) -> int:
        return int(self.w3.eth.get_block("latest")["timestamp"])
