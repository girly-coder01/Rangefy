import numpy as np
import pandas as pd
import pytest

from src.data.synthetic import generate


def gbm(minutes: int, sigma_day: float, seed: int = 0, drift_day: float = 0.0) -> pd.DataFrame:
    """Constant-vol geometric Brownian motion candles (known true sigma)."""
    rng = np.random.default_rng(seed)
    step = sigma_day / np.sqrt(1440)
    r = rng.normal(drift_day / 1440, step, minutes)
    close = 3000 * np.exp(np.cumsum(r))
    idx = pd.date_range("2024-01-01", periods=minutes, freq="1min", tz="UTC")
    open_ = np.concatenate([[3000], close[:-1]])
    return pd.DataFrame({"open": open_, "high": np.maximum(open_, close), "low": np.minimum(open_, close),
                         "close": close, "volume": np.ones(minutes)}, index=idx)


@pytest.fixture(scope="session")
def synth_30d() -> pd.DataFrame:
    return generate(30 * 1440, seed=3)


@pytest.fixture(scope="session")
def trained(tmp_path_factory, synth_30d):
    from src.training.train import TrainConfig, train

    out = tmp_path_factory.mktemp("models")
    report = train(synth_30d, out, TrainConfig(epochs=1, rf_trees=10, stride=60, device="cpu", data_source="test"))
    return out, report
