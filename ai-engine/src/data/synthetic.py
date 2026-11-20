"""Synthetic ETH-like candles (regime-switching GARCH) for offline dev and tests."""

from __future__ import annotations

from datetime import UTC, datetime

import numpy as np
import pandas as pd

from .candles import normalize


def generate(minutes: int, seed: int = 7, start_price: float = 3000.0,
             start: datetime = datetime(2024, 1, 1, tzinfo=UTC)) -> pd.DataFrame:
    rng = np.random.default_rng(seed)

    # daily vol regimes ~1%..6%
    regime_levels = np.array([0.01, 0.02, 0.035, 0.06]) / np.sqrt(1440)
    P = np.array([[0.9995, 0.0004, 0.0001, 0.0],
                  [0.0002, 0.9995, 0.0002, 0.0001],
                  [0.0001, 0.0003, 0.9993, 0.0003],
                  [0.0, 0.0002, 0.0008, 0.999]])
    state = 1
    alpha, beta = 0.08, 0.90  # GARCH persistence 0.98

    t = np.arange(minutes)
    hour = (t // 60) % 24
    season = 1.0 + 0.35 * np.sin(2 * np.pi * (hour - 14) / 24)  # busier around US open
    z = rng.standard_t(df=5, size=minutes) / np.sqrt(5 / 3)  # unit-variance fat tails
    u = rng.random(minutes)

    rets = np.empty(minutes)
    var = regime_levels[state] ** 2
    for i in range(minutes):
        if u[i] > P[state, state]:  # switch: pick among the *other* regimes
            q = P[state].copy()
            q[state] = 0.0
            state = int(rng.choice(4, p=q / q.sum()))
        target = regime_levels[state] ** 2
        shock = np.sqrt(var) * z[i]  # de-seasonalized: keeps GARCH persistence at alpha + beta < 1
        rets[i] = shock * season[i]
        var = target * (1 - alpha - beta) + alpha * shock * shock + beta * var
        var = 0.97 * var + 0.03 * target  # pull toward the regime level

    close = start_price * np.exp(np.cumsum(rets))
    open_ = np.concatenate([[start_price], close[:-1]])
    wick = np.abs(rng.normal(0, 1, (2, minutes))) * np.sqrt(np.maximum(var, 1e-12)) * 0.5
    high = np.maximum(open_, close) * np.exp(wick[0])
    low = np.minimum(open_, close) * np.exp(-wick[1])
    volume = np.exp(rng.normal(3.0, 0.6, minutes)) * season * (1 + 40 * np.abs(rets))

    idx = pd.date_range(start, periods=minutes, freq="1min", tz=UTC)
    df = pd.DataFrame({"open": open_, "high": high, "low": low, "close": close, "volume": volume}, index=idx)
    df.index.name = "ts"
    return normalize(df)
