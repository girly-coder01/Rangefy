"""Feature standardization fitted on the training split only; stored as JSON (no pickle)."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class Standardizer:
    mean: np.ndarray
    std: np.ndarray
    clip: float = 8.0

    @classmethod
    def fit(cls, x: np.ndarray) -> Standardizer:
        mean = np.nanmean(x, axis=0)
        std = np.nanstd(x, axis=0)
        std = np.where(std < 1e-8, 1.0, std)
        return cls(mean.astype(np.float32), std.astype(np.float32))

    def transform(self, x: np.ndarray) -> np.ndarray:
        z = (x - self.mean) / self.std
        return np.clip(np.nan_to_num(z, nan=0.0), -self.clip, self.clip).astype(np.float32)

    def save(self, path: Path) -> None:
        path.write_text(json.dumps({"mean": self.mean.tolist(), "std": self.std.tolist(), "clip": self.clip}))

    @classmethod
    def load(cls, path: Path) -> Standardizer:
        d = json.loads(path.read_text())
        return cls(np.asarray(d["mean"], np.float32), np.asarray(d["std"], np.float32), d["clip"])
