"""RF + Transformer ensemble: log-space sigma blend, linear drift blend."""

from __future__ import annotations

from dataclasses import asdict, dataclass

import numpy as np

from ..data.labeler import to_regime


@dataclass
class EnsembleWeights:
    w_rf: float = 0.5  # transformer gets 1 − w_rf

    def combine(self, s_rf: np.ndarray, d_rf: np.ndarray, s_tf: np.ndarray, d_tf: np.ndarray):
        w = self.w_rf
        sigma = np.exp(w * np.log(s_rf) + (1 - w) * np.log(s_tf))
        drift = w * d_rf + (1 - w) * d_tf
        return sigma, drift

    def to_dict(self) -> dict:
        return asdict(self)


def fit_weights(s_rf, s_tf, sigma_true, step: float = 0.05) -> EnsembleWeights:
    """Grid-search the RF weight minimizing validation MAE (ticks) of sigma."""
    best_w, best = 0.5, np.inf
    for w in np.arange(0.0, 1.0 + 1e-9, step):
        s = np.exp(w * np.log(s_rf) + (1 - w) * np.log(s_tf))
        mae = float(np.mean(np.abs(s - sigma_true)))
        if mae < best:
            best_w, best = float(round(w, 4)), mae
    return EnsembleWeights(best_w)


def confidence_bps(s_rf, s_tf, s_ens) -> np.ndarray:
    dis = np.clip(np.abs(np.asarray(s_rf) - np.asarray(s_tf)) / np.asarray(s_ens), 0.0, 1.0)
    return np.round(10_000 * (1 - dis)).astype(int)


def regimes(sigma, edges) -> np.ndarray:
    return to_regime(sigma, edges)
