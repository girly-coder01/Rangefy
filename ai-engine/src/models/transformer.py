"""Transformer over 240 minutes of features -> (log sigma, drift / 1000)."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import torch
from torch import nn

from .random_forest import DRIFT_SCALE


class PositionalEncoding(nn.Module):
    def __init__(self, d_model: int, max_len: int) -> None:
        super().__init__()
        self.pe = nn.Parameter(torch.randn(1, max_len, d_model) * 0.02)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x + self.pe[:, : x.size(1)]


class VolTransformer(nn.Module):
    def __init__(self, n_features: int, seq_len: int = 240, d_model: int = 64, n_heads: int = 4,
                 n_layers: int = 2, ff_dim: int = 128, dropout: float = 0.1) -> None:
        super().__init__()
        self.config = dict(n_features=n_features, seq_len=seq_len, d_model=d_model, n_heads=n_heads,
                           n_layers=n_layers, ff_dim=ff_dim, dropout=dropout)
        self.input_proj = nn.Linear(n_features, d_model)
        self.pos = PositionalEncoding(d_model, seq_len)
        layer = nn.TransformerEncoderLayer(d_model, n_heads, ff_dim, dropout, batch_first=True)
        self.encoder = nn.TransformerEncoder(layer, n_layers, enable_nested_tensor=False)
        self.head = nn.Sequential(nn.Linear(d_model, 32), nn.GELU(), nn.Dropout(dropout), nn.Linear(32, 2))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h = self.encoder(self.pos(self.input_proj(x)))
        return self.head(h.mean(dim=1))

    @torch.no_grad()
    def predict(self, windows: np.ndarray, batch_size: int = 512) -> tuple[np.ndarray, np.ndarray]:
        """windows: (n, seq, F) or (seq, F) → (sigma_ticks, drift_ticks)."""
        self.eval()
        if windows.ndim == 2:
            windows = windows[None]
        outs = []
        for i in range(0, len(windows), batch_size):
            outs.append(self(torch.from_numpy(np.ascontiguousarray(windows[i : i + batch_size]))).numpy())
        y = np.concatenate(outs)
        return np.exp(y[:, 0]), y[:, 1] * DRIFT_SCALE

    def save(self, path: Path) -> None:
        torch.save({"config": self.config, "state": self.state_dict()}, path)

    @classmethod
    def load(cls, path: Path) -> VolTransformer:
        blob = torch.load(path, map_location="cpu", weights_only=True)
        m = cls(**blob["config"])
        m.load_state_dict(blob["state"])
        m.eval()
        return m
