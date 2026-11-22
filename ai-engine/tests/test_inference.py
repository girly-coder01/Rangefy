import json

import pytest

from src.constants import MAX_DRIFT_TICKS, MAX_SIGMA_TICKS, MIN_SIGMA_TICKS
from src.inference.forecaster import Forecast, Forecaster
from src.inference.signal_mapper import OnchainSignal, model_version_bytes8, should_post, to_onchain


def _f(**kw) -> Forecast:
    base = dict(timestamp="t", sigma_ticks=400.0, drift_ticks=120.0, regime=1, regime_name="Normal",
                confidence_bps=8000, model_version="rfyabcde", rf_sigma=400, tf_sigma=400, ewma_sigma=400,
                rf_drift=0, tf_drift=0, price=3000)
    base.update(kw)
    return Forecast(**base)


def test_mapper_clamps_to_contract_bounds():
    s = to_onchain(_f(sigma_ticks=5.0, drift_ticks=9999.0, confidence_bps=12_000, regime=7), True)
    assert s.sigma_ticks == MIN_SIGMA_TICKS
    assert s.drift_ticks == MAX_DRIFT_TICKS
    assert s.confidence_bps == 10_000
    assert s.regime == 3
    assert to_onchain(_f(sigma_ticks=1e9), True).sigma_ticks == MAX_SIGMA_TICKS


def test_mapper_flips_drift_when_usdc_is_token0():
    assert to_onchain(_f(drift_ticks=120.0), base_is_token0=True).drift_ticks == 120
    assert to_onchain(_f(drift_ticks=120.0), base_is_token0=False).drift_ticks == -120


def test_model_version_is_bytes8():
    assert model_version_bytes8("rfyabcde") == b"rfyabcde"
    assert model_version_bytes8("v1") == b"v1\0\0\0\0\0\0"
    assert len(model_version_bytes8("much-too-long-version")) == 8


def test_should_post_rules():
    a = OnchainSignal(400, 0, 1, 8000, b"rfyabcde")
    assert should_post(a, None, None) == (True, "first")
    assert should_post(OnchainSignal(430, 0, 1, 8000, b""), a, 60) == (False, "unchanged")
    assert should_post(OnchainSignal(440, 0, 1, 8000, b""), a, 60) == (True, "sigma_change")
    assert should_post(OnchainSignal(400, 0, 2, 8000, b""), a, 60) == (True, "regime_change")
    assert should_post(a, a, 600) == (True, "heartbeat")


def test_train_writes_artifacts(trained):
    out, report = trained
    for f in ("rf.joblib", "transformer.pt", "scaler.json", "meta.json", "backtest.json"):
        assert (out / f).exists(), f
    meta = json.loads((out / "meta.json").read_text())
    assert len(meta["model_version"]) == 8
    e = meta["regime_edges"]
    assert e[0] < e[1] < e[2]
    assert {"ewma_baseline", "random_forest", "transformer", "ensemble"} <= set(meta["metrics"]["sigma"])
    assert [r["name"] for r in report["backtest"]["results"]] == ["fixed ±600", "EWMA-sized", "AI-sized (Balanced)"]


def test_forecaster_on_trained_artifacts(trained, synth_30d):
    out, _ = trained
    fc = Forecaster(out)
    f = fc.forecast(synth_30d.iloc[-fc.min_history :])
    assert f.sigma_ticks > 0
    assert 0 <= f.regime <= 3
    assert 0 <= f.confidence_bps <= 10_000
    assert f.model_version == fc.version
    with pytest.raises(ValueError):
        fc.forecast(synth_30d.iloc[-100:])
