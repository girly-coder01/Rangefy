import httpx
import numpy as np
import pandas as pd

from src.constants import LN_TICK, MAX_DRIFT_TICKS
from src.data import candles
from src.data.dataset import chronological_split, sample_positions
from src.data.labeler import make_labels, regime_edges, to_regime
from tests.conftest import gbm


def test_normalize_fills_gaps_and_dedupes():
    idx = pd.to_datetime(["2024-01-01 00:00", "2024-01-01 00:01", "2024-01-01 00:01", "2024-01-01 00:04"], utc=True)
    df = pd.DataFrame({"open": [1, 2, 2.5, 4], "high": [1, 2, 2.5, 4], "low": [1, 2, 2.5, 4],
                       "close": [1, 2, 2.5, 4], "volume": [5, 5, 6, 5]}, index=idx)
    out = candles.normalize(df)
    assert len(out) == 5
    assert out["close"].tolist() == [1, 2.5, 2.5, 2.5, 4]
    assert out["volume"].tolist() == [5, 6, 0, 0, 5]


def test_coinbase_parsing_and_paging():
    calls = []

    def handler(req: httpx.Request) -> httpx.Response:
        calls.append(dict(req.url.params))
        start = pd.Timestamp(req.url.params["start"]).timestamp()
        # newest-first, [time, low, high, open, close, volume]
        rows = [[int(start) + 60 * i, 9, 11, 10, 10.5, 2] for i in range(300)][::-1]
        return httpx.Response(200, json=rows)

    client = httpx.Client(transport=httpx.MockTransport(handler))
    start = pd.Timestamp("2024-01-01", tz="UTC").to_pydatetime()
    end = pd.Timestamp("2024-01-01 10:00", tz="UTC").to_pydatetime()
    df = candles.fetch_coinbase(start, end, client=client, pause=0)
    assert len(calls) == 2  # 600 minutes / 300 per call
    assert df.index.is_monotonic_increasing
    assert df.iloc[0].tolist() == [10, 11, 9, 10.5, 2]


def test_binance_parsing():
    def handler(req: httpx.Request) -> httpx.Response:
        s = int(req.url.params["startTime"])
        e = int(req.url.params["endTime"])
        n = min(1000, (e - s) // 60_000)
        return httpx.Response(200, json=[[s + 60_000 * i, "1", "2", "0.5", "1.5", "7", 0] for i in range(n)])

    client = httpx.Client(transport=httpx.MockTransport(handler))
    start = pd.Timestamp("2024-01-01", tz="UTC").to_pydatetime()
    end = pd.Timestamp("2024-01-02", tz="UTC").to_pydatetime()
    df = candles.fetch_binance(start, end, client=client, pause=0)
    assert len(df) == 1440
    assert df["close"].iloc[0] == 1.5


def test_labels_convert_to_ticks():
    df = gbm(10 * 1440, sigma_day=0.04, seed=1)
    lab = make_labels(df).dropna()
    # true 24h sigma = 4% → 0.04 / ln(1.0001) ≈ 400 ticks
    assert abs(lab["sigma_ticks"].median() - 0.04 / LN_TICK) < 25


def test_labels_use_only_future():
    df = gbm(4 * 1440, sigma_day=0.03, seed=2)
    lab = make_labels(df)
    t = 1440
    df2 = df.copy()
    df2.iloc[: t - 1, df2.columns.get_loc("close")] *= 1.5  # change the past only
    lab2 = make_labels(df2)
    assert np.isclose(lab.iloc[t]["sigma_ticks"], lab2.iloc[t]["sigma_ticks"])
    assert np.isclose(lab.iloc[t]["drift_ticks"], lab2.iloc[t]["drift_ticks"])
    assert lab.iloc[-1:].isna().all().all()  # no future window at the end


def test_drift_clipped():
    df = gbm(3 * 1440, sigma_day=0.001, drift_day=0.5)
    assert make_labels(df)["drift_ticks"].dropna().max() == MAX_DRIFT_TICKS


def test_regime_edges_monotonic_and_hook_rule():
    e = regime_edges(np.random.default_rng(0).lognormal(6, 0.5, 5000))
    assert e[0] < e[1] < e[2]
    # Same as RangefyHook.regimeForSigma: sigma < th0 → Calm; sigma == th0 → Normal
    assert to_regime(e[0] - 1, e) == 0
    assert to_regime(e[0], e) == 1
    assert to_regime(e[2], e) == 3
    assert regime_edges(np.full(100, 300.0)) == (300.0, 301.0, 302.0)  # degenerate → strictly increasing


def test_chronological_split_has_embargo():
    pos = sample_positions(100_000, np.ones(100_000, bool), stride=10)
    s = chronological_split(pos, embargo=1440)
    assert s.train.max() + 1440 <= s.val.min()
    assert s.val.max() + 1440 <= s.test.min()
    assert set(s.train).isdisjoint(s.val) and set(s.val).isdisjoint(s.test)
