import numpy as np

from src.constants import LN_TICK
from src.features.extractor import WARMUP, extract, feature_names
from src.features.preprocessor import Standardizer
from src.models.ensemble import EnsembleWeights, confidence_bps, fit_weights
from src.models.ewma_baseline import ewma_sigma_ticks
from src.models.random_forest import RandomForestForecaster
from src.models.transformer import VolTransformer
from src.training.backtest_lp import simulate
from src.training.evaluate import qlike
from tests.conftest import gbm


def test_feature_shape_and_warmup(synth_30d):
    f = extract(synth_30d)
    assert list(f.columns) == feature_names()
    assert len(f) == len(synth_30d)
    assert f.iloc[WARMUP:].notna().all().all()
    assert f.iloc[: WARMUP - 1]["rv_10080m"].isna().all()


def test_features_have_no_lookahead(synth_30d):
    t = WARMUP + 500
    base = extract(synth_30d).iloc[t]
    future = synth_30d.copy()
    future.iloc[t + 1 :, :4] *= 2.0  # wreck the future
    future.iloc[t + 1 :, 4] *= 10.0
    assert np.allclose(base.to_numpy(), extract(future).iloc[t].to_numpy(), equal_nan=True)


def test_realized_vol_in_ticks():
    f = extract(gbm(9 * 1440, sigma_day=0.05, seed=4))
    assert abs(f["rv_1440m"].iloc[-1] - 0.05 / LN_TICK) < 40


def test_ewma_baseline_tracks_constant_vol():
    s = ewma_sigma_ticks(gbm(20 * 1440, sigma_day=0.03, seed=5)).dropna()
    assert abs(s.iloc[-5000:].median() - 0.03 / LN_TICK) < 40


def test_standardizer_roundtrip(tmp_path):
    x = np.random.default_rng(0).normal(5, 2, (500, 3)).astype(np.float32)
    x[:, 2] = 1.0  # constant column must not divide by zero
    s = Standardizer.fit(x)
    s.save(tmp_path / "s.json")
    s2 = Standardizer.load(tmp_path / "s.json")
    assert np.allclose(s.transform(x), s2.transform(x))
    assert np.isfinite(s.transform(np.full((1, 3), np.nan))).all()


def test_rf_save_load(tmp_path):
    rng = np.random.default_rng(0)
    x = rng.normal(size=(300, 4))
    sigma = np.exp(5 + x[:, 0] * 0.3)
    rf = RandomForestForecaster(n_estimators=10, max_depth=4)
    rf.fit(x, sigma, x[:, 1] * 100)
    rf.save(tmp_path / "rf.joblib")
    rf2 = RandomForestForecaster.load(tmp_path / "rf.joblib")
    assert np.allclose(rf.predict(x[:5])[0], rf2.predict(x[:5])[0])


def test_transformer_save_load(tmp_path):
    m = VolTransformer(n_features=6, seq_len=16)
    x = np.random.default_rng(0).normal(size=(3, 16, 6)).astype(np.float32)
    m.save(tmp_path / "tf.pt")
    m2 = VolTransformer.load(tmp_path / "tf.pt")
    assert np.allclose(m.predict(x)[0], m2.predict(x)[0], rtol=1e-5)
    s, d = m.predict(x[0])
    assert s.shape == (1,) and (s > 0).all()


def test_ensemble_weights_and_confidence():
    true = np.full(100, 400.0)
    w = fit_weights(np.full(100, 400.0), np.full(100, 800.0), true)
    assert w.w_rf == 1.0
    s, d = EnsembleWeights(0.5).combine(np.array([100.0]), np.array([10.0]), np.array([400.0]), np.array([30.0]))
    assert np.isclose(s[0], 200.0)  # geometric mean
    assert np.isclose(d[0], 20.0)
    assert confidence_bps([400], [400], [400])[0] == 10_000
    assert confidence_bps([100], [900], [300])[0] == 0


def test_qlike_zero_for_perfect():
    assert qlike(np.array([300.0, 500.0]), np.array([300.0, 500.0])) == 0.0
    assert qlike(np.array([300.0]), np.array([600.0])) > 0


def test_backtest_flat_price_earns_fees_only():
    import pandas as pd

    close = pd.Series(np.full(2000, 3000.0), index=pd.date_range("2024-01-01", periods=2000, freq="1min"))
    r = simulate(close, lambda i: 600, name="flat")
    assert r.rebalances == 0
    assert r.time_in_range_pct == 100.0
    assert np.isclose(r.final_value - 10_000, r.fees_usd, rtol=1e-6)
    assert r.hodl_return_pct == 0.0
