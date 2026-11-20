"""Trailing-window features per minute. Vols are in ticks per 24h."""

from __future__ import annotations

import numpy as np
import pandas as pd

from ..constants import LN_TICK, MINUTES_PER_DAY

RETURN_WINDOWS = (1, 5, 15, 60, 240, 1440)
REALIZED_WINDOWS = (15, 60, 360, 1440, 10080)
PARKINSON_WINDOWS = (60, 360, 1440)
ONCHAIN_COLUMNS = ("onchain_swaps_per_min", "onchain_mean_abs_tick_move")

# minutes before the first complete row (7d vol)
WARMUP = max(REALIZED_WINDOWS)

_DAY_SCALE = np.sqrt(MINUTES_PER_DAY) / LN_TICK  # per-minute log-return std → ticks per 24h


def feature_names() -> list[str]:
    names = [f"ret_{w}m" for w in RETURN_WINDOWS]
    names += [f"rv_{w}m" for w in REALIZED_WINDOWS]
    names += [f"pk_{w}m" for w in PARKINSON_WINDOWS]
    names += ["log_rv_1440m", "rv_ratio_60_1440", "rv_ratio_1440_10080"]
    names += ["vol_z_1d", "vol_z_7d"]
    names += ["hour_sin", "hour_cos", "dow_sin", "dow_cos"]
    names += list(ONCHAIN_COLUMNS)
    return names


def extract(candles: pd.DataFrame, onchain: pd.DataFrame | None = None) -> pd.DataFrame:
    """Feature frame indexed like `candles`. Rows before WARMUP contain NaNs."""
    c = candles
    logp = np.log(c["close"])
    r1 = logp.diff()
    out: dict[str, pd.Series] = {}

    for w in RETURN_WINDOWS:
        out[f"ret_{w}m"] = (logp - logp.shift(w)) / LN_TICK

    for w in REALIZED_WINDOWS:
        out[f"rv_{w}m"] = r1.rolling(w, min_periods=w).std(ddof=0) * _DAY_SCALE

    hl2 = np.log(c["high"] / c["low"]) ** 2
    for w in PARKINSON_WINDOWS:
        out[f"pk_{w}m"] = np.sqrt(hl2.rolling(w, min_periods=w).mean() / (4 * np.log(2))) * _DAY_SCALE

    eps = 1e-9
    out["log_rv_1440m"] = np.log(out["rv_1440m"] + eps)
    out["rv_ratio_60_1440"] = out["rv_60m"] / (out["rv_1440m"] + eps)
    out["rv_ratio_1440_10080"] = out["rv_1440m"] / (out["rv_10080m"] + eps)

    vol = np.log1p(c["volume"])
    for name, w in (("vol_z_1d", MINUTES_PER_DAY), ("vol_z_7d", 7 * MINUTES_PER_DAY)):
        m = vol.rolling(w, min_periods=w).mean()
        s = vol.rolling(w, min_periods=w).std(ddof=0)
        out[name] = (vol - m) / (s + eps)

    idx = c.index
    hour = idx.hour + idx.minute / 60
    out["hour_sin"] = pd.Series(np.sin(2 * np.pi * hour / 24), index=idx)
    out["hour_cos"] = pd.Series(np.cos(2 * np.pi * hour / 24), index=idx)
    out["dow_sin"] = pd.Series(np.sin(2 * np.pi * idx.day_of_week / 7), index=idx)
    out["dow_cos"] = pd.Series(np.cos(2 * np.pi * idx.day_of_week / 7), index=idx)

    for col in ONCHAIN_COLUMNS:  # live only; zero-filled in training
        if onchain is not None and col in onchain:
            out[col] = onchain[col].reindex(idx).fillna(0.0)
        else:
            out[col] = pd.Series(0.0, index=idx)

    df = pd.DataFrame(out, index=idx)[feature_names()]
    return df.astype(np.float32)
