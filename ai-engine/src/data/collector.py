"""Live candles for the forecaster and spot price for the mirror."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

import httpx
import pandas as pd

from . import candles

SPOT_URLS = {
    "coinbase": "https://api.exchange.coinbase.com/products/ETH-USD/ticker",
    "binance": "https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT",
}


class CandleCache:
    """Rolling candle window; backfills once, then fetches only the tail."""

    def __init__(self, source: str, keep_minutes: int, fetch=candles.fetch) -> None:
        self.source = source
        self.keep = keep_minutes
        self._fetch = fetch
        self._df: pd.DataFrame | None = None
        self._lock = threading.Lock()

    def refresh(self, now: datetime | None = None) -> pd.DataFrame:
        now = (now or datetime.now(UTC)).replace(second=0, microsecond=0)
        with self._lock:
            if self._df is None or self._df.empty:
                start = now - timedelta(minutes=self.keep)
            else:
                start = self._df.index[-1].to_pydatetime() - timedelta(minutes=5)  # re-fetch a small overlap
            new = self._fetch(self.source, start, now)
            df = new if self._df is None else pd.concat([self._df, new])
            df = candles.normalize(df)
            self._df = df.iloc[-self.keep :]
            return self._df

    @property
    def frame(self) -> pd.DataFrame | None:
        return self._df


def fetch_spot(source: str, client: httpx.Client | None = None) -> float:
    own = client is None
    client = client or httpx.Client(timeout=10.0, headers={"User-Agent": candles.USER_AGENT})
    try:
        r = client.get(SPOT_URLS[source])
        r.raise_for_status()
        d = r.json()
        return float(d["price"])
    finally:
        if own:
            client.close()
