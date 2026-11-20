"""1m OHLCV candles from Coinbase/Binance, gap-filled, UTC minute index."""

from __future__ import annotations

import time
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import pandas as pd
import structlog

log = structlog.get_logger()

COLUMNS = ["open", "high", "low", "close", "volume"]
USER_AGENT = "rangefy-ai/0.1"

COINBASE_URL = "https://api.exchange.coinbase.com/products/{product}/candles"
COINBASE_MAX = 300
BINANCE_URL = "https://api.binance.com/api/v3/klines"
BINANCE_MAX = 1000


def _client() -> httpx.Client:
    return httpx.Client(timeout=20.0, headers={"User-Agent": USER_AGENT})


def _retry(fn: Callable[[], httpx.Response], attempts: int = 5) -> httpx.Response:
    delay = 1.0
    for i in range(attempts):
        try:
            r = fn()
            if r.status_code == 429 or r.status_code >= 500:
                raise httpx.HTTPStatusError("retryable", request=r.request, response=r)
            r.raise_for_status()
            return r
        except (httpx.TransportError, httpx.HTTPStatusError) as e:
            if i == attempts - 1:
                raise
            log.warning("candles.retry", attempt=i + 1, error=str(e))
            time.sleep(delay)
            delay *= 2
    raise RuntimeError("unreachable")


def fetch_coinbase(start: datetime, end: datetime, product: str = "ETH-USD", client: httpx.Client | None = None,
                   pause: float = 0.12) -> pd.DataFrame:
    """Page through Coinbase Exchange candles (max 300 per call, newest-first responses)."""
    rows: list[list[float]] = []
    own = client is None
    client = client or _client()
    try:
        cursor = start
        while cursor < end:
            chunk_end = min(cursor + timedelta(minutes=COINBASE_MAX), end)
            params = {"granularity": 60, "start": cursor.isoformat(), "end": chunk_end.isoformat()}
            r = _retry(lambda p=params: client.get(COINBASE_URL.format(product=product), params=p))
            # [time, low, high, open, close, volume]
            for t, lo, hi, op, cl, vol in r.json():
                rows.append([t, op, hi, lo, cl, vol])
            cursor = chunk_end
            time.sleep(pause)
    finally:
        if own:
            client.close()
    df = pd.DataFrame(rows, columns=["ts", *COLUMNS])
    df["ts"] = pd.to_datetime(df["ts"], unit="s", utc=True)
    return normalize(df.set_index("ts"))


def fetch_binance(start: datetime, end: datetime, symbol: str = "ETHUSDT", client: httpx.Client | None = None,
                  pause: float = 0.05) -> pd.DataFrame:
    """Page through Binance klines (max 1000 per call)."""
    rows: list[list[float]] = []
    own = client is None
    client = client or _client()
    try:
        cursor = int(start.timestamp() * 1000)
        end_ms = int(end.timestamp() * 1000)
        while cursor < end_ms:
            params = {"symbol": symbol, "interval": "1m", "startTime": cursor, "endTime": end_ms, "limit": BINANCE_MAX}
            data = _retry(lambda p=params: client.get(BINANCE_URL, params=p)).json()
            if not data:
                break
            for k in data:
                rows.append([k[0] / 1000, float(k[1]), float(k[2]), float(k[3]), float(k[4]), float(k[5])])
            cursor = int(data[-1][0]) + 60_000
            time.sleep(pause)
    finally:
        if own:
            client.close()
    df = pd.DataFrame(rows, columns=["ts", *COLUMNS])
    df["ts"] = pd.to_datetime(df["ts"], unit="s", utc=True)
    return normalize(df.set_index("ts"))


def fetch(source: str, start: datetime, end: datetime) -> pd.DataFrame:
    if source == "coinbase":
        return fetch_coinbase(start, end)
    if source == "binance":
        return fetch_binance(start, end)
    raise ValueError(f"unknown price source {source!r}")


def fetch_recent(source: str, minutes: int) -> pd.DataFrame:
    end = datetime.now(UTC).replace(second=0, microsecond=0)
    return fetch(source, end - timedelta(minutes=minutes), end)


def normalize(df: pd.DataFrame) -> pd.DataFrame:
    """Sort, dedupe, fill gaps with flat zero-volume candles."""
    if df.empty:
        return df[COLUMNS].astype(float)
    df = df[COLUMNS].astype(float)
    df = df[~df.index.duplicated(keep="last")].sort_index()
    full = pd.date_range(df.index[0], df.index[-1], freq="1min", tz=UTC)
    df = df.reindex(full)
    close = df["close"].ffill()
    for c in ("open", "high", "low"):
        df[c] = df[c].fillna(close)
    df["close"] = close
    df["volume"] = df["volume"].fillna(0.0)
    df.index.name = "ts"
    return df


def save(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(path)


def load(path: Path) -> pd.DataFrame:
    return normalize(pd.read_parquet(path))
