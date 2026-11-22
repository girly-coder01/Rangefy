"""SQLite history for signals, keeper actions and the market mirror."""

from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

SCHEMA = """
CREATE TABLE IF NOT EXISTS signals (
  id INTEGER PRIMARY KEY, ts REAL NOT NULL, pool_id TEXT NOT NULL,
  sigma_ticks INTEGER, drift_ticks INTEGER, regime INTEGER, confidence_bps INTEGER, model_version TEXT,
  posted INTEGER NOT NULL, reason TEXT, tx_hash TEXT, error TEXT, breakdown TEXT
);
CREATE INDEX IF NOT EXISTS signals_pool_ts ON signals(pool_id, ts);
CREATE TABLE IF NOT EXISTS keeper_events (
  id INTEGER PRIMARY KEY, ts REAL NOT NULL, job TEXT NOT NULL, vault TEXT, action TEXT,
  reason TEXT, status TEXT NOT NULL, tx_hash TEXT, gas_used INTEGER, error TEXT
);
CREATE INDEX IF NOT EXISTS keeper_ts ON keeper_events(ts);
CREATE TABLE IF NOT EXISTS mirror (
  id INTEGER PRIMARY KEY, ts REAL NOT NULL, real_price REAL, pool_price REAL, deviation_bps REAL,
  action TEXT, tx_hash TEXT, error TEXT
);
CREATE TABLE IF NOT EXISTS job_runs (job TEXT PRIMARY KEY, ts REAL NOT NULL, ok INTEGER NOT NULL, detail TEXT);
"""


class Store:
    def __init__(self, path: Path | str) -> None:
        if str(path) != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        with self._lock:
            self._conn.executescript(SCHEMA)
            self._conn.commit()

    def _exec(self, sql: str, args: tuple = ()) -> None:
        with self._lock:
            self._conn.execute(sql, args)
            self._conn.commit()

    def _rows(self, sql: str, args: tuple = ()) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(r) for r in self._conn.execute(sql, args).fetchall()]

    # ── writes ──
    def add_signal(self, pool_id: str, sigma: int, drift: int, regime: int, confidence: int, version: str,
                   posted: bool, reason: str, tx_hash: str | None = None, error: str | None = None,
                   breakdown: dict | None = None, ts: float | None = None) -> None:
        self._exec(
            "INSERT INTO signals (ts,pool_id,sigma_ticks,drift_ticks,regime,confidence_bps,model_version,posted,"
            "reason,tx_hash,error,breakdown) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (ts or time.time(), pool_id, sigma, drift, regime, confidence, version, int(posted), reason, tx_hash,
             error, json.dumps(breakdown) if breakdown else None),
        )

    def add_keeper_event(self, job: str, vault: str | None, action: str, status: str, reason: str | None = None,
                         tx_hash: str | None = None, gas_used: int | None = None, error: str | None = None) -> None:
        self._exec(
            "INSERT INTO keeper_events (ts,job,vault,action,reason,status,tx_hash,gas_used,error) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            (time.time(), job, vault, action, reason, status, tx_hash, gas_used, error),
        )

    def add_mirror(self, real: float, pool: float, dev_bps: float, action: str, tx_hash: str | None = None,
                   error: str | None = None) -> None:
        self._exec("INSERT INTO mirror (ts,real_price,pool_price,deviation_bps,action,tx_hash,error) "
                   "VALUES (?,?,?,?,?,?,?)", (time.time(), real, pool, dev_bps, action, tx_hash, error))

    def record_run(self, job: str, ok: bool, detail: str = "") -> None:
        self._exec("INSERT INTO job_runs (job,ts,ok,detail) VALUES (?,?,?,?) "
                   "ON CONFLICT(job) DO UPDATE SET ts=excluded.ts, ok=excluded.ok, detail=excluded.detail",
                   (job, time.time(), int(ok), detail[:500]))

    # ── reads ──
    def last_posted_signal(self, pool_id: str) -> dict | None:
        r = self._rows("SELECT * FROM signals WHERE pool_id=? AND posted=1 ORDER BY ts DESC LIMIT 1", (pool_id,))
        return r[0] if r else None

    def latest_signal(self, pool_id: str | None = None) -> dict | None:
        if pool_id:
            r = self._rows("SELECT * FROM signals WHERE pool_id=? ORDER BY ts DESC LIMIT 1", (pool_id,))
        else:
            r = self._rows("SELECT * FROM signals ORDER BY ts DESC LIMIT 1")
        return _decode(r[0]) if r else None

    def signal_history(self, pool_id: str | None, since: float) -> list[dict]:
        if pool_id:
            rows = self._rows("SELECT * FROM signals WHERE pool_id=? AND ts>=? ORDER BY ts", (pool_id, since))
        else:
            rows = self._rows("SELECT * FROM signals WHERE ts>=? ORDER BY ts", (since,))
        return [_decode(r) for r in rows]

    def keeper_events(self, limit: int = 50, job: str | None = None) -> list[dict]:
        if job:
            return self._rows("SELECT * FROM keeper_events WHERE job=? ORDER BY ts DESC LIMIT ?", (job, limit))
        return self._rows("SELECT * FROM keeper_events ORDER BY ts DESC LIMIT ?", (limit,))

    def mirror_latest(self, limit: int = 20) -> list[dict]:
        return self._rows("SELECT * FROM mirror ORDER BY ts DESC LIMIT ?", (limit,))

    def job_runs(self) -> dict[str, dict]:
        return {r["job"]: r for r in self._rows("SELECT * FROM job_runs")}


def _decode(row: dict) -> dict:
    if row.get("breakdown"):
        row["breakdown"] = json.loads(row["breakdown"])
    return row
