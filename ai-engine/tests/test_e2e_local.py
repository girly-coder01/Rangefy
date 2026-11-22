"""Keeper E2E against scripts/local-stack.sh. Skipped when no local chain is running."""

from pathlib import Path
from types import SimpleNamespace

import pytest
from web3 import Web3

from src.chain.client import RangefyChain
from src.chain.tx import TxSender
from src.config import ROOT, Settings
from src.keeper import jobs as J
from src.store.db import Store

ENV = ROOT / ".env.local"


def _settings() -> Settings | None:
    if not ENV.exists():
        return None
    s = Settings(_env_file=(ENV,))
    try:
        if Web3(Web3.HTTPProvider(s.rpc_url, request_kwargs={"timeout": 2})).eth.chain_id not in (31337, 31338):
            return None
    except Exception:  # noqa: BLE001
        return None
    return s


S = _settings()
pytestmark = pytest.mark.skipif(S is None, reason="local anvil stack not running (scripts/local-stack.sh)")


@pytest.fixture(scope="module")
def env(tmp_path_factory):
    chain = RangefyChain(S)
    store = Store(Path(tmp_path_factory.mktemp("db")) / "e2e.db")
    return SimpleNamespace(
        chain=chain, store=store, locks=J.VaultLocks(),
        keeper=TxSender(chain.w3, S.keeper_key), mirror=TxSender(chain.w3, S.mirror_key),
        updater=TxSender(chain.w3, S.signal_updater_key),
    )


def _warp(w3: Web3, seconds: int) -> None:
    w3.provider.make_request("evm_increaseTime", [seconds])
    w3.provider.make_request("evm_mine", [])


def test_stack_is_deployed(env):
    vaults = env.chain.all_vaults()
    assert len(vaults) == 3
    price = env.chain.priced.eth_usd(env.chain.pool_state().sqrt_price_x96)
    assert 2000 < price < 4500  # seeded at ETH_PRICE_USD=3000; earlier runs on the same chain move it


def test_mirror_moves_pool_toward_real_price(env):
    job = J.MirrorJob(env.chain, env.mirror, env.store, S)
    before = env.chain.priced.eth_usd(env.chain.pool_state().sqrt_price_x96)
    job.spot = lambda src: before * 1.02
    assert job().startswith("swapped")
    after = env.chain.priced.eth_usd(env.chain.pool_state().sqrt_price_x96)
    assert after > before * 1.005
    assert env.store.mirror_latest()[0]["tx_hash"]


def test_noise_swap_mines(env):
    import random

    J.NoiseJob(env.chain, env.mirror, env.store, random.Random(1))()
    assert env.store.keeper_events(job="noise")[0]["status"] == "ok"


def test_signal_job_posts_and_changes_fee(env):
    from src.inference.forecaster import Forecast

    f = Forecast("now", 1200.0, 100.0, 3, "Extreme", 9000, "rfye2e00", 1200, 1200, 900, 100, 100, 3000)
    job = J.SignalJob(env.chain, env.updater, env.store, SimpleNamespace(forecast=lambda df: f),
                      SimpleNamespace(refresh=lambda: None))
    assert "posted" in job()
    sig, fresh = env.chain.oracle.functions.getSignal(env.chain.key.pool_id).call()
    assert fresh and sig[0] == 1200
    assert sig[1] == (100 if env.chain.priced.weth_is_token0 else -100)  # drift in pool-tick direction
    assert env.chain.hook.functions.currentFee(env.chain.key.pool_id).call() == 15_000  # Extreme fee


def test_keeper_rebalances_after_cooldown(env):
    # σ jumped from ~300 to 1200 → every vault's target width drifts ≥ 30%; wait out the longest cooldown (1h)
    _warp(env.chain.w3, 3601)
    # refresh the signal (it expired during the warp) so sizing still uses σ = 1200
    from src.inference.forecaster import Forecast

    f = Forecast("now", 1200.0, 0.0, 3, "Extreme", 9000, "rfye2e01", 1200, 1200, 900, 0, 0, 3000)
    env.store.add_signal("x", 0, 0, 0, 0, "", False, "reset")  # force a re-post regardless of history
    J.SignalJob(env.chain, env.updater, Store(":memory:"), SimpleNamespace(forecast=lambda df: f),
                SimpleNamespace(refresh=lambda: None))()

    needs = {v: env.chain.needs_rebalance(v) for v in env.chain.all_vaults()}
    assert any(n for n, _ in needs.values()), needs
    out = J.RebalanceJob(env.chain, env.keeper, env.store, env.locks)()
    assert out != "rebalanced 0"
    for v, (needed, _) in needs.items():
        if needed:
            assert env.chain.vault(v).functions.rebalanceCount().call() >= 1
    ok = [e for e in env.store.keeper_events(job="rebalance") if e["status"] == "ok"]
    assert ok and all(e["tx_hash"] for e in ok)


def test_keeper_harvests_idle_vaults(env):
    _warp(env.chain.w3, 3601)
    out = J.HarvestJob(env.chain, env.keeper, env.store, env.locks)()
    assert out == "harvested 3"
