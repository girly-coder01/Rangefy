"""Download 1m ETH-USD candles: python scripts/fetch_history.py --days 730 [--source binance]"""

import argparse
from datetime import UTC, datetime, timedelta

import _bootstrap  # noqa: F401
from _bootstrap import ROOT

from src.data import candles


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=730)
    ap.add_argument("--source", choices=["coinbase", "binance"], default="coinbase")
    ap.add_argument("--out", default=str(ROOT / "data" / "raw" / "ethusd_1m.parquet"))
    args = ap.parse_args()

    end = datetime.now(UTC).replace(second=0, microsecond=0)
    start = end - timedelta(days=args.days)
    print(f"fetching {args.days}d of 1m candles from {args.source} ({start:%Y-%m-%d} → {end:%Y-%m-%d}) …")
    df = candles.fetch(args.source, start, end)
    candles.save(df, __import__("pathlib").Path(args.out))
    print(f"saved {len(df):,} rows → {args.out}")


if __name__ == "__main__":
    main()
