"""Forecast metrics: MAE in ticks, QLIKE on variance, regime accuracy, drift skill."""

from __future__ import annotations

import numpy as np

from ..data.labeler import to_regime


def qlike(sigma_pred: np.ndarray, sigma_true: np.ndarray) -> float:
    """QLIKE loss on variances: mean(r/h − ln(r/h) − 1); 0 for a perfect forecast."""
    h = np.asarray(sigma_pred, float) ** 2
    r = np.asarray(sigma_true, float) ** 2
    ratio = r / h
    return float(np.mean(ratio - np.log(ratio) - 1))


def sigma_metrics(sigma_pred, sigma_true, edges) -> dict:
    sp, st = np.asarray(sigma_pred, float), np.asarray(sigma_true, float)
    return {
        "mae_ticks": float(np.mean(np.abs(sp - st))),
        "mape": float(np.mean(np.abs(sp - st) / st)),
        "qlike": qlike(sp, st),
        "regime_accuracy": float(np.mean(to_regime(sp, edges) == to_regime(st, edges))),
        "bias_ticks": float(np.mean(sp - st)),
    }


def drift_metrics(drift_pred, drift_true) -> dict:
    dp, dt = np.asarray(drift_pred, float), np.asarray(drift_true, float)
    mask = dt != 0
    return {
        "mae_ticks": float(np.mean(np.abs(dp - dt))),
        "mae_zero_baseline": float(np.mean(np.abs(dt))),
        "direction_hit_rate": float(np.mean(np.sign(dp[mask]) == np.sign(dt[mask]))) if mask.any() else 0.0,
    }
