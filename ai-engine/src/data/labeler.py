"""Forward 24h sigma and drift labels, in ticks."""

from __future__ import annotations

import numpy as np
import pandas as pd

from ..constants import LN_TICK, MAX_DRIFT_TICKS, MINUTES_PER_DAY, REGIME_QUANTILES

HORIZON = MINUTES_PER_DAY


def make_labels(candles: pd.DataFrame, horizon: int = HORIZON) -> pd.DataFrame:
    logp = np.log(candles["close"])
    r1 = logp.diff()
    # rolling std at t+h covers (t, t+h]
    fwd_std = r1.rolling(horizon, min_periods=horizon).std(ddof=0).shift(-horizon)
    sigma = fwd_std * np.sqrt(horizon) / LN_TICK
    drift = ((logp.shift(-horizon) - logp) / LN_TICK).clip(-MAX_DRIFT_TICKS, MAX_DRIFT_TICKS)
    return pd.DataFrame({"sigma_ticks": sigma, "drift_ticks": drift}, index=candles.index)


def regime_edges(sigma_ticks: np.ndarray) -> tuple[float, float, float]:
    """Calm < 30th pct ≤ Normal < 70th ≤ High < 95th ≤ Extreme, from training labels."""
    q = np.nanquantile(np.asarray(sigma_ticks, dtype=float), REGIME_QUANTILES)
    e0, e1, e2 = (float(x) for x in q)
    # strictly increasing, as the hook requires
    e1 = max(e1, e0 + 1)
    e2 = max(e2, e1 + 1)
    return e0, e1, e2


def to_regime(sigma_ticks: np.ndarray | float, edges: tuple[float, float, float]) -> np.ndarray:
    """Same rule as RangefyHook.regimeForSigma."""
    return np.searchsorted(np.asarray(edges), np.asarray(sigma_ticks, dtype=float), side="right")
