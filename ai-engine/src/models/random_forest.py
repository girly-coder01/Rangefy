"""Random Forest on tabular features → (log sigma, drift)."""

from __future__ import annotations

from pathlib import Path

import joblib
import numpy as np
from sklearn.ensemble import RandomForestRegressor

DRIFT_SCALE = 1000.0  # drift is learned in thousands of ticks so both targets have similar scale


class RandomForestForecaster:
    def __init__(self, n_estimators: int = 300, max_depth: int = 12, min_samples_leaf: int = 20,
                 random_state: int = 42, n_jobs: int = -1) -> None:
        self.model = RandomForestRegressor(
            n_estimators=n_estimators, max_depth=max_depth, min_samples_leaf=min_samples_leaf,
            max_features=0.5, random_state=random_state, n_jobs=n_jobs,
        )
        self.fitted = False

    def fit(self, x: np.ndarray, sigma_ticks: np.ndarray, drift_ticks: np.ndarray) -> None:
        y = np.column_stack([np.log(sigma_ticks), drift_ticks / DRIFT_SCALE])
        self.model.fit(x, y)
        self.fitted = True

    def predict(self, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Returns (sigma_ticks, drift_ticks)."""
        y = self.model.predict(np.atleast_2d(x))
        return np.exp(y[:, 0]), y[:, 1] * DRIFT_SCALE

    def save(self, path: Path) -> None:
        joblib.dump(self.model, path, compress=3)

    @classmethod
    def load(cls, path: Path) -> RandomForestForecaster:
        m = cls()
        m.model = joblib.load(path)
        m.fitted = True
        return m
