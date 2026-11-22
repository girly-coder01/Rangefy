import asyncio
import math
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from src.chain.pool import Q96, PoolKey, PricedPool
from src.chain.tx import TxResult
from src.config import Settings
from src.inference.forecaster import Forecast
from src.keeper import jobs as J
from src.keeper.scheduler import Scheduled, fixed, run
from src.server.app import create_app
from src.store.db import Store

WETH = "0x00000000000000000000000000000000000000aa"
USDC = "0x00000000000000000000000000000000000000bb"
HOOK = "0x00000000000000000000000000000000000020c0"


class FakeSender:
    address = "0x000000000000000000000000000000000000dEaD"

    def __init__(self, results=None):
        self.sent = []
        self.results = list(results or [])

    def send(self, fn, label=""):
        self.sent.append((fn, label))
        return self.results.pop(0) if self.results else TxResult(True, "0xabc", 100_000)


class Fn:
    """Stands in for a bound contract function; records the call."""

    def __init__(self, name, args):
        self.name, self.args = name, args

    def call(self):
        return 0


class Functions:
    def __getattr__(self, name):
        return lambda *args: Fn(name, args)


class FakeChain:
    def __init__(self, vaults=(), needs=None, liquidity=1, last_rebalance=0, now=10_000, sqrt_price=None):
        self.key = PoolKey.build(WETH, USDC, HOOK)
        self.priced = PricedPool(self.key, WETH)
        self._vaults = list(vaults)
        self._needs = needs or {}
        self._liq, self._last, self._now = liquidity, last_rebalance, now
        self._sqrt = sqrt_price or self.priced.sqrt_price_x96(3000.0)
        self.oracle = self.router = SimpleNamespace(functions=Functions(), address="0x" + "11" * 20)

    def all_vaults(self):
        return self._vaults

    def needs_rebalance(self, v):
        return self._needs.get(v, (False, "None"))

    def vault(self, v):
        return SimpleNamespace(functions=Functions())

    def token(self, t):
        return SimpleNamespace(functions=SimpleNamespace(allowance=lambda a, b: Fn("allowance", ()),
                                                         approve=lambda s, a: Fn("approve", (s, a))))

    def vault_liquidity(self, v):
        return self._liq

    def last_rebalance(self, v):
        return self._last

    def block_timestamp(self):
        return self._now

    def pool_state(self):
        return SimpleNamespace(sqrt_price_x96=self._sqrt)


@pytest.fixture
def store():
    return Store(":memory:")


def test_pool_id_and_price_math():
    k = PoolKey.build(USDC, WETH, HOOK)
    assert k.currency0 == PoolKey.build(WETH, USDC, HOOK).currency0  # sorted
    assert len(k.pool_id) == 32
    p = PricedPool(k, WETH)
    assert p.weth_is_token0
    assert math.isclose(p.eth_usd(p.sqrt_price_x96(3123.45)), 3123.45, rel_tol=1e-9)
    # inverted orientation round-trips too
    k2 = PoolKey(USDC, WETH, k.fee, 60, HOOK)
    p2 = PricedPool(k2, WETH)
    assert not p2.weth_is_token0
    assert math.isclose(p2.eth_usd(p2.sqrt_price_x96(2999.0)), 2999.0, rel_tol=1e-9)
    assert p.sqrt_price_x96(3000) < Q96  # 3000e6/1e18 < 1


def test_rebalance_sends_only_when_needed(store):
    chain = FakeChain(vaults=["0xA", "0xB"], needs={"0xA": (True, "NearEdge")})
    sender = FakeSender()
    out = J.RebalanceJob(chain, sender, store, J.VaultLocks())()
    assert out == "rebalanced 1"
    assert [fn.name for fn, _ in sender.sent] == ["rebalance"]
    ev = store.keeper_events()
    assert ev[0]["vault"] == "0xA" and ev[0]["reason"] == "NearEdge" and ev[0]["status"] == "ok"


def test_rebalance_revert_is_logged_not_raised(store):
    chain = FakeChain(vaults=["0xA"], needs={"0xA": (True, "OutOfRange")})
    sender = FakeSender([TxResult(False, None, error="estimate reverted: Cooldown()", reverted=True)])
    assert J.RebalanceJob(chain, sender, store, J.VaultLocks())() == "rebalanced 0"
    assert store.keeper_events()[0]["status"] == "reverted"


def test_rebalance_skips_locked_vault(store):
    chain = FakeChain(vaults=["0xA"], needs={"0xA": (True, "OutOfRange")})
    locks = J.VaultLocks()
    assert locks.acquire("0xA")
    sender = FakeSender()
    J.RebalanceJob(chain, sender, store, locks)()
    assert sender.sent == []


def test_harvest_rules(store):
    sender = FakeSender()
    J.HarvestJob(FakeChain(vaults=["0xA"], liquidity=0), sender, store, J.VaultLocks())()
    J.HarvestJob(FakeChain(vaults=["0xA"], last_rebalance=9_000, now=10_000), sender, store, J.VaultLocks())()
    assert sender.sent == []  # no liquidity / rebalanced < 1h ago
    J.HarvestJob(FakeChain(vaults=["0xA"], last_rebalance=0, now=10_000), sender, store, J.VaultLocks())()
    assert [fn.name for fn, _ in sender.sent] == ["harvest"]


@pytest.mark.parametrize("real,expect_zero_for_one", [(3100.0, False), (2900.0, True)])
def test_mirror_direction_and_limit(store, real, expect_zero_for_one):
    chain = FakeChain()  # pool at 3000, mWETH is token0
    s = Settings(_env_file=None)
    job = J.MirrorJob(chain, FakeSender(), store, s)
    act, target, token_in, max_in, pool_price, dev = job.plan(real, chain._sqrt)
    assert act and math.isclose(pool_price, 3000.0, rel_tol=1e-9)
    assert math.isclose(chain.priced.eth_usd(target), real, rel_tol=1e-9)
    assert (target < chain._sqrt) == expect_zero_for_one
    # price down → sell mWETH (token0) with the mWETH budget; price up → sell mUSDC with the mUSDC budget
    assert token_in == (chain.key.currency0 if expect_zero_for_one else chain.key.currency1)
    assert max_in == (s.mirror_max_in_token0 if expect_zero_for_one else s.mirror_max_in_usdc)


def test_mirror_no_action_inside_band(store):
    chain = FakeChain()
    job = J.MirrorJob(chain, FakeSender(), store, Settings(_env_file=None))
    job.spot = lambda src: 3005.0  # 16.7 bps < 30 bps
    assert job().startswith("in sync")
    assert store.mirror_latest()[0]["action"] == "none"


def test_mirror_swaps_outside_band(store):
    chain = FakeChain()
    sender = FakeSender()
    job = J.MirrorJob(chain, sender, store, Settings(_env_file=None))
    job.spot = lambda src: 3100.0
    job()
    names = [fn.name for fn, _ in sender.sent]
    assert names[-1] == "swapToPrice"
    assert store.mirror_latest()[0]["action"] == "swap"


def _forecast(sigma=420.0, regime=1):
    return Forecast("2026-01-01", sigma, 50.0, regime, "Normal", 9000, "rfytest1", 400, 440, 410, 40, 60, 3000)


def test_signal_job_posts_then_waits(store):
    chain = FakeChain()
    sender = FakeSender()
    fc = SimpleNamespace(forecast=lambda df: _forecast())
    cache = SimpleNamespace(refresh=lambda: None)
    job = J.SignalJob(chain, sender, store, fc, cache)
    assert "posted" in job()
    assert "unchanged" in job()  # same signal again → no post
    assert [fn.name for fn, _ in sender.sent] == ["postSignal"]
    fn, _ = sender.sent[0]
    assert fn.args[0] == chain.key.pool_id and fn.args[1] == 420 and fn.args[2] == 50  # mWETH token0: no flip
    latest = store.latest_signal()
    assert latest["breakdown"]["tf_sigma"] == 440


def test_scheduler_survives_failing_job(store):
    calls = {"n": 0}

    def boom():
        calls["n"] += 1
        raise RuntimeError("rpc down")

    async def main():
        stop = asyncio.Event()
        task = asyncio.create_task(run([Scheduled(boom, "boom", fixed(0.01))], store, stop))
        await asyncio.sleep(0.1)
        stop.set()
        await task

    asyncio.run(main())
    assert calls["n"] >= 2
    assert store.job_runs()["boom"]["ok"] == 0


def test_api_endpoints(store, tmp_path):
    (tmp_path / "meta.json").write_text('{"model_version":"rfytest1","data":{"source":"test"},'
                                        '"ensemble":{"w_rf":0.4},"regime_edges":[300,500,900],"metrics":{}}')
    (tmp_path / "backtest.json").write_text('{"results":[]}')
    s = Settings(_env_file=None, model_dir=tmp_path)
    client = TestClient(create_app(s, store))

    assert client.get("/signal/latest").status_code == 404
    assert client.get("/mirror/status").status_code == 404

    f = _forecast()
    store.add_signal("0xpool", 420, 50, 1, 9000, "rfytest1", True, "first", "0xtx", breakdown=f.to_dict())
    store.add_mirror(3001.0, 3000.0, 3.3, "none")
    store.add_keeper_event("rebalance", "0xA", "rebalance", "ok", "NearEdge", "0xt", 1)

    h = client.get("/health").json()
    assert h["model_version"] == "rfytest1"
    sig = client.get("/signal/latest", params={"poolId": "0xpool"}).json()
    assert sig["regime_name"] == "Normal" and sig["posted"] is True
    assert len(client.get("/signal/history", params={"hours": 1}).json()["points"]) == 1
    fc = client.get("/forecast").json()
    assert set(fc["models"]) == {"ewma", "random_forest", "transformer", "ensemble"}
    assert fc["weights"] == {"w_rf": 0.4}
    assert client.get("/keeper/status").json()["rebalances"][0]["reason"] == "NearEdge"
    assert client.get("/mirror/status").json()["deviation_bps"] == 3.3
    assert client.get("/model/backtest").json()["model_version"] == "rfytest1"
