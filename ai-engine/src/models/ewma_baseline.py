"""RiskMetrics EWMA (lambda 0.94, hourly returns). The baseline to beat."""

from __future__ import annotations

import numpy as np
import pandas as pd

from ..constants import LN_TICK

LAMBDA = 0.94


def ewma_sigma_ticks(candles: pd.DataFrame, lam: float = LAMBDA) -> pd.Series:
    logp = np.log(candles["close"].to_numpy())
    r60 = np.full_like(logp, np.nan)
    r60[60:] = logp[60:] - logp[:-60]
    out = np.full_like(logp, np.nan)
    for phase in range(60):
        sl = slice(60 + phase, None, 60)
        sq = pd.Series(r60[sl] ** 2)
        out[sl] = np.sqrt(sq.ewm(alpha=1 - lam, adjust=False).mean().to_numpy() * 24) / LN_TICK
    return pd.Series(out, index=candles.index, name="ewma_sigma_ticks")
