"""FastAPI read API for the frontend. Reads the keeper's SQLite store and model files."""

from __future__ import annotations

import json
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from ..config import Settings, get_settings
from ..constants import REGIMES
from ..store.db import Store


def _json(path: Path) -> dict | None:
    return json.loads(path.read_text()) if path.exists() else None


def create_app(settings: Settings | None = None, store: Store | None = None) -> FastAPI:
    s = settings or get_settings()
    db = store or Store(s.db_path)
    app = FastAPI(title="Rangefy AI Engine", version="0.1.0")
    app.add_middleware(CORSMiddleware, allow_origins=s.api_cors_origins, allow_methods=["GET"], allow_headers=["*"])

    def meta() -> dict | None:
        return _json(s.model_dir / "meta.json")

    @app.get("/health")
    def health() -> dict:
        m = meta()
        return {
            "status": "ok",
            "model_version": m["model_version"] if m else None,
            "trained_on": m["data"] if m else None,
            "jobs": db.job_runs(),
            "time": time.time(),
        }

    @app.get("/signal/latest")
    def signal_latest(poolId: str | None = Query(None)) -> dict:  # noqa: N803 (query name from spec)
        row = db.latest_signal(poolId)
        if not row:
            raise HTTPException(404, "no signal yet")
        return _signal_out(row)

    @app.get("/signal/history")
    def signal_history(poolId: str | None = Query(None), hours: float = Query(24, gt=0, le=24 * 30)) -> dict:  # noqa: N803
        rows = db.signal_history(poolId, time.time() - hours * 3600)
        return {"points": [_signal_out(r, breakdown=False) for r in rows]}

    @app.get("/forecast")
    def forecast() -> dict:
        row = db.latest_signal()
        if not row or not row.get("breakdown"):
            raise HTTPException(404, "no forecast yet")
        b = row["breakdown"]
        m = meta() or {}
        return {
            "timestamp": b["timestamp"],
            "price": b["price"],
            "models": {
                "ewma": {"sigma_ticks": b["ewma_sigma"]},
                "random_forest": {"sigma_ticks": b["rf_sigma"], "drift_ticks": b["rf_drift"]},
                "transformer": {"sigma_ticks": b["tf_sigma"], "drift_ticks": b["tf_drift"]},
                "ensemble": {"sigma_ticks": b["sigma_ticks"], "drift_ticks": b["drift_ticks"],
                             "regime": b["regime_name"], "confidence_bps": b["confidence_bps"]},
            },
            "weights": m.get("ensemble"),
            "regime_edges": m.get("regime_edges"),
            "model_version": b["model_version"],
        }

    @app.get("/keeper/status")
    def keeper_status(limit: int = Query(50, gt=0, le=500)) -> dict:
        events = db.keeper_events(limit)
        return {
            "jobs": db.job_runs(),
            "rebalances": [e for e in events if e["action"] == "rebalance"],
            "harvests": [e for e in events if e["action"] == "harvest"],
            "failures": [e for e in events if e["status"] == "failed"],
        }

    @app.get("/mirror/status")
    def mirror_status() -> dict:
        rows = db.mirror_latest(50)
        if not rows:
            raise HTTPException(404, "mirror has not run yet")
        last_tx = next((r for r in rows if r["tx_hash"]), None)
        return {
            "real_price": rows[0]["real_price"],
            "testnet_price": rows[0]["pool_price"],
            "deviation_bps": rows[0]["deviation_bps"],
            "updated_at": rows[0]["ts"],
            "last_mirror_tx": last_tx,
        }

    @app.get("/model/backtest")
    def model_backtest() -> dict:
        bt = _json(s.model_dir / "backtest.json")
        if bt is None:
            raise HTTPException(404, "no backtest; run scripts/train_model.py")
        m = meta() or {}
        return {"backtest": bt, "metrics": m.get("metrics"), "model_version": m.get("model_version")}

    return app


def _signal_out(row: dict, breakdown: bool = True) -> dict:
    out = {
        "ts": row["ts"], "pool_id": row["pool_id"], "sigma_ticks": row["sigma_ticks"],
        "drift_ticks": row["drift_ticks"], "regime": row["regime"], "regime_name": REGIMES[row["regime"]],
        "confidence_bps": row["confidence_bps"], "model_version": row["model_version"],
        "posted": bool(row["posted"]), "reason": row["reason"], "tx_hash": row["tx_hash"],
    }
    if breakdown:
        out["breakdown"] = row.get("breakdown")
    return out


def __getattr__(name: str):  # lazy `app` so importing the module doesn't touch the DB (uvicorn src.server.app:app)
    if name == "app":
        return create_app()
    raise AttributeError(name)
