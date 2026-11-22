"""Loads trained models and forecasts from recent candles."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
import pandas as pd

from ..constants import REGIMES
from ..data.dataset import tabular
from ..data.labeler import to_regime
from ..features.extractor import WARMUP, extract
from ..features.preprocessor import Standardizer
from ..models.ensemble import EnsembleWeights, confidence_bps
from ..models.ewma_baseline import ewma_sigma_ticks
from ..models.random_forest import RandomForestForecaster
from ..models.transformer import VolTransformer


@dataclass
class Forecast:
    timestamp: str
    sigma_ticks: float
    drift_ticks: float  # in ETH/USD direction (positive = ETH up)
    regime: int
    regime_name: str
    confidence_bps: int
    model_version: str
    rf_sigma: float
    tf_sigma: float
    ewma_sigma: float
    rf_drift: float
    tf_drift: float
    price: float

    def to_dict(self) -> dict:
        return asdict(self)


class Forecaster:
    def __init__(self, model_dir: Path) -> None:
        self.dir = model_dir
        self.meta = json.loads((model_dir / "meta.json").read_text())
        self.rf = RandomForestForecaster.load(model_dir / "rf.joblib")
        self.tf = VolTransformer.load(model_dir / "transformer.pt")
        self.scaler = Standardizer.load(model_dir / "scaler.json")
        self.weights = EnsembleWeights(**self.meta["ensemble"])
        self.edges = tuple(self.meta["regime_edges"])
        self.seq_len = int(self.meta["config"]["seq_len"])
        self.columns: list[str] = self.meta["features"]

    @property
    def version(self) -> str:
        return self.meta["model_version"]

    @property
    def min_history(self) -> int:
        return WARMUP + self.seq_len

    def forecast(self, candles: pd.DataFrame, onchain: pd.DataFrame | None = None) -> Forecast:
        if len(candles) < self.min_history:
            raise ValueError(f"need ≥ {self.min_history} minutes of candles, got {len(candles)}")
        feats = extract(candles, onchain)[self.columns]
        matrix = self.scaler.transform(feats.to_numpy(np.float32))
        end = np.array([len(matrix) - 1])

        s_rf, d_rf = self.rf.predict(tabular(matrix, self.columns, end, self.seq_len))
        s_tf, d_tf = self.tf.predict(matrix[-self.seq_len :])
        s, d = self.weights.combine(s_rf, d_rf, s_tf, d_tf)
        regime = int(to_regime(s, self.edges)[0])
        ewma = float(ewma_sigma_ticks(candles.iloc[-(WARMUP + 60) :]).iloc[-1])

        return Forecast(
            timestamp=str(candles.index[-1]),
            sigma_ticks=float(s[0]),
            drift_ticks=float(d[0]),
            regime=regime,
            regime_name=REGIMES[regime],
            confidence_bps=int(confidence_bps(s_rf, s_tf, s)[0]),
            model_version=self.version,
            rf_sigma=float(s_rf[0]),
            tf_sigma=float(s_tf[0]),
            ewma_sigma=ewma,
            rf_drift=float(d_rf[0]),
            tf_drift=float(d_tf[0]),
            price=float(candles["close"].iloc[-1]),
        )
