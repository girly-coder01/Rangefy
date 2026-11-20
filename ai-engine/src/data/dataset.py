"""Chronological 70/15/15 split with a 1-day embargo; sequences are sliced lazily."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd

from ..features.extractor import WARMUP
from .labeler import HORIZON

SEQ_LEN = 240
SPLITS = (0.70, 0.15, 0.15)

# summarized over the window for the RF
SUMMARY_COLUMNS = ("ret_1m", "rv_60m", "pk_60m", "vol_z_1d")


@dataclass
class Split:
    train: np.ndarray
    val: np.ndarray
    test: np.ndarray


def sample_positions(n_rows: int, valid: np.ndarray, stride: int, seq_len: int = SEQ_LEN) -> np.ndarray:
    """Row positions usable as sample ends: past warm-up, full sequence, finite features and labels."""
    start = max(WARMUP, seq_len - 1)
    pos = np.arange(start, n_rows, stride)
    return pos[valid[pos]]


def chronological_split(pos: np.ndarray, embargo: int = HORIZON, splits: tuple = SPLITS) -> Split:
    lo, hi = int(pos.min()), int(pos.max())
    span = hi - lo
    b1 = lo + int(span * splits[0])
    b2 = lo + int(span * (splits[0] + splits[1]))
    train = pos[pos < b1 - embargo]
    val = pos[(pos >= b1) & (pos < b2 - embargo)]
    test = pos[pos >= b2]
    return Split(train, val, test)


def valid_mask(features: pd.DataFrame, labels: pd.DataFrame | None) -> np.ndarray:
    ok = np.isfinite(features.to_numpy()).all(axis=1)
    if labels is not None:
        ok &= np.isfinite(labels.to_numpy()).all(axis=1)
    return ok


class SequenceSource:
    """Windows of `seq_len` standardized feature rows ending at a given row position."""

    def __init__(self, matrix: np.ndarray, seq_len: int = SEQ_LEN) -> None:
        self.m = matrix
        self.seq_len = seq_len

    def window(self, end: int) -> np.ndarray:
        return self.m[end - self.seq_len + 1 : end + 1]

    def batch(self, ends: np.ndarray) -> np.ndarray:
        offsets = np.arange(-self.seq_len + 1, 1)
        return self.m[ends[:, None] + offsets[None, :]]


def tabular(matrix: np.ndarray, columns: list[str], ends: np.ndarray, seq_len: int = SEQ_LEN) -> np.ndarray:
    """Latest feature row + mean/std/min/max of a few key columns over the trailing window."""
    latest = matrix[ends]
    idx = [columns.index(c) for c in SUMMARY_COLUMNS]
    win = SequenceSource(matrix[:, idx], seq_len).batch(ends)
    stats = [win.mean(axis=1), win.std(axis=1), win.min(axis=1), win.max(axis=1)]
    return np.concatenate([latest, *stats], axis=1).astype(np.float32)


def tabular_names(columns: list[str]) -> list[str]:
    names = list(columns)
    for stat in ("mean", "std", "min", "max"):
        names += [f"{c}_{stat}" for c in SUMMARY_COLUMNS]
    return names
