"""Training pipeline: features, labels, RF + Transformer, ensemble, eval, backtest."""

from __future__ import annotations

import hashlib
import json
import time
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
import pandas as pd
import structlog
import torch
from torch import nn

from ..data.dataset import (
    SEQ_LEN,
    SequenceSource,
    chronological_split,
    sample_positions,
    tabular,
    tabular_names,
    valid_mask,
)
from ..data.labeler import make_labels, regime_edges
from ..features.extractor import extract, feature_names
from ..features.preprocessor import Standardizer
from ..models.ensemble import confidence_bps, fit_weights
from ..models.ewma_baseline import ewma_sigma_ticks
from ..models.random_forest import DRIFT_SCALE, RandomForestForecaster
from ..models.transformer import VolTransformer
from . import backtest_lp
from .evaluate import drift_metrics, sigma_metrics

log = structlog.get_logger()


@dataclass
class TrainConfig:
    stride: int = 30  # minutes between samples
    seq_len: int = SEQ_LEN
    rf_trees: int = 300
    rf_depth: int = 12
    rf_max_samples: int = 60_000
    epochs: int = 20
    batch_size: int = 256
    lr: float = 1e-3
    weight_decay: float = 1e-4
    patience: int = 3
    seed: int = 42
    data_source: str = "unknown"
    device: str = "auto"  # auto → mps (Apple GPU) if available, else cpu


def _device(name: str) -> torch.device:
    if name == "auto":
        return torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    return torch.device(name)


def _version(cfg: TrainConfig, start: str, end: str) -> str:
    """8-char model version (fits the oracle's bytes8)."""
    h = hashlib.sha256(json.dumps([asdict(cfg), start, end, time.time()]).encode()).hexdigest()
    return "rfy" + h[:5]


def _train_transformer(src: SequenceSource, y: np.ndarray, train_pos, val_pos, cfg: TrainConfig,
                       n_features: int) -> tuple[VolTransformer, list[dict]]:
    torch.manual_seed(cfg.seed)
    dev = _device(cfg.device)
    model = VolTransformer(n_features=n_features, seq_len=cfg.seq_len)
    # start calibrated at the training means
    with torch.no_grad():
        model.head[-1].bias.copy_(torch.from_numpy(y[train_pos].mean(axis=0)))
    model.to(dev)
    log.info("transformer.device", device=str(dev))
    opt = torch.optim.AdamW(model.parameters(), lr=cfg.lr, weight_decay=cfg.weight_decay)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=max(1, cfg.epochs))
    loss_fn = nn.HuberLoss(delta=1.0)
    rng = np.random.default_rng(cfg.seed)

    def evaluate(pos) -> float:
        model.eval()
        total, n = 0.0, 0
        with torch.no_grad():
            for i in range(0, len(pos), 1024):
                p = pos[i : i + 1024]
                out = model(torch.from_numpy(src.batch(p)).to(dev))
                total += float(loss_fn(out, torch.from_numpy(y[p]).to(dev))) * len(p)
                n += len(p)
        return total / max(n, 1)

    best, best_state, bad, history = np.inf, None, 0, []
    for epoch in range(cfg.epochs):
        model.train()
        order = rng.permutation(train_pos)
        t0 = time.time()
        for i in range(0, len(order), cfg.batch_size):
            p = np.sort(order[i : i + cfg.batch_size])
            xb = torch.from_numpy(src.batch(p)).to(dev)
            yb = torch.from_numpy(y[p]).to(dev)
            opt.zero_grad()
            loss = loss_fn(model(xb), yb)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
        sched.step()
        tr, va = evaluate(train_pos[:: max(1, len(train_pos) // 5000)]), evaluate(val_pos)
        history.append({"epoch": epoch + 1, "train_loss": tr, "val_loss": va, "seconds": round(time.time() - t0, 1)})
        log.info("transformer.epoch", **history[-1])
        if va < best - 1e-5:
            best, bad = va, 0
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
        else:
            bad += 1
            if bad >= cfg.patience:
                break
    model.to("cpu")
    if best_state is not None:
        model.load_state_dict(best_state)
    model.eval()
    return model, history


def train(candles: pd.DataFrame, model_dir: Path, cfg: TrainConfig | None = None) -> dict:
    cfg = cfg or TrainConfig()
    model_dir.mkdir(parents=True, exist_ok=True)
    np.random.seed(cfg.seed)

    log.info("train.features", rows=len(candles))
    feats = extract(candles)
    labels = make_labels(candles)
    cols = feature_names()

    mask = valid_mask(feats, labels)
    pos = sample_positions(len(feats), mask, cfg.stride, cfg.seq_len)
    split = chronological_split(pos)
    if min(len(split.train), len(split.val), len(split.test)) == 0:
        raise ValueError("not enough data: need at least ~4 weeks of 1m candles")
    log.info("train.split", train=len(split.train), val=len(split.val), test=len(split.test))

    raw = feats.to_numpy(np.float32)
    scaler = Standardizer.fit(raw[split.train])
    matrix = scaler.transform(raw)
    src = SequenceSource(matrix, cfg.seq_len)

    sigma = labels["sigma_ticks"].to_numpy()
    drift = labels["drift_ticks"].to_numpy()
    edges = regime_edges(sigma[split.train])

    # ── Random Forest ──
    rf_train = split.train
    if len(rf_train) > cfg.rf_max_samples:
        rf_train = np.sort(np.random.default_rng(cfg.seed).choice(rf_train, cfg.rf_max_samples, replace=False))
    rf = RandomForestForecaster(cfg.rf_trees, cfg.rf_depth, random_state=cfg.seed)
    t0 = time.time()
    rf.fit(tabular(matrix, cols, rf_train, cfg.seq_len), sigma[rf_train], drift[rf_train])
    log.info("train.rf", seconds=round(time.time() - t0, 1))

    # ── Transformer ──
    y = np.column_stack([np.log(sigma), drift / DRIFT_SCALE]).astype(np.float32)
    tf, history = _train_transformer(src, y, split.train, split.val, cfg, len(cols))

    # ── Ensemble weights on validation ──
    def both(p):
        s_rf, d_rf = rf.predict(tabular(matrix, cols, p, cfg.seq_len))
        s_tf, d_tf = tf.predict(src.batch(p))
        return s_rf, d_rf, s_tf, d_tf

    vs_rf, _, vs_tf, _ = both(split.val)
    weights = fit_weights(vs_rf, vs_tf, sigma[split.val])

    # ── Test metrics ──
    ts_rf, td_rf, ts_tf, td_tf = both(split.test)
    ts_en, td_en = weights.combine(ts_rf, td_rf, ts_tf, td_tf)
    ewma = ewma_sigma_ticks(candles).to_numpy()
    st, dt = sigma[split.test], drift[split.test]
    ew = ewma[split.test]
    ok = np.isfinite(ew)

    metrics = {
        "sigma": {
            "ewma_baseline": sigma_metrics(ew[ok], st[ok], edges),
            "random_forest": sigma_metrics(ts_rf, st, edges),
            "transformer": sigma_metrics(ts_tf, st, edges),
            "ensemble": sigma_metrics(ts_en, st, edges),
        },
        "drift": {
            "random_forest": drift_metrics(td_rf, dt),
            "transformer": drift_metrics(td_tf, dt),
            "ensemble": drift_metrics(td_en, dt),
        },
        "confidence_bps_mean": float(np.mean(confidence_bps(ts_rf, ts_tf, ts_en))),
    }
    beats = metrics["sigma"]["ensemble"]["mae_ticks"] < metrics["sigma"]["ewma_baseline"]["mae_ticks"]
    metrics["ensemble_beats_ewma"] = bool(beats)
    log.info("train.metrics", ensemble_mae=metrics["sigma"]["ensemble"]["mae_ticks"],
             ewma_mae=metrics["sigma"]["ewma_baseline"]["mae_ticks"], beats_ewma=beats)

    # ── LP backtest on the test period ──
    idx = feats.index
    test_close = candles["close"].iloc[split.test[0] : split.test[-1] + 1]
    bt = backtest_lp.run(
        test_close,
        sigma_ai=pd.Series(ts_en, index=idx[split.test]),
        drift_ai=pd.Series(td_en, index=idx[split.test]),
        sigma_ewma=pd.Series(ewma, index=idx).iloc[split.test[0] : split.test[-1] + 1],
    )

    # ── Save ──
    start, end = str(idx[0]), str(idx[-1])
    version = _version(cfg, start, end)
    rf.save(model_dir / "rf.joblib")
    tf.save(model_dir / "transformer.pt")
    scaler.save(model_dir / "scaler.json")
    meta = {
        "model_version": version,
        "trained_at": datetime.now(UTC).isoformat(),
        "data": {"source": cfg.data_source, "start": start, "end": end, "rows": int(len(candles))},
        "config": asdict(cfg),
        "features": cols,
        "tabular_features": tabular_names(cols),
        "regime_edges": list(edges),
        "ensemble": weights.to_dict(),
        "samples": {"train": int(len(split.train)), "val": int(len(split.val)), "test": int(len(split.test))},
        "metrics": metrics,
        "transformer_history": history,
    }
    (model_dir / "meta.json").write_text(json.dumps(meta, indent=2))
    (model_dir / "backtest.json").write_text(json.dumps(bt, indent=2))
    log.info("train.saved", model_dir=str(model_dir), version=version)
    return {"meta": meta, "backtest": bt}
