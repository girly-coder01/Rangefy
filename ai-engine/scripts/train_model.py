"""Train and save models. --synthetic DAYS trains on generated candles."""

import argparse
import json
from pathlib import Path

import _bootstrap  # noqa: F401
from _bootstrap import ROOT

from src.config import get_settings
from src.data import candles, synthetic
from src.training.train import TrainConfig, train


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(ROOT / "data" / "raw" / "ethusd_1m.parquet"))
    ap.add_argument("--synthetic", type=int, metavar="DAYS", help="train on synthetic candles instead")
    ap.add_argument("--out", default=None, help="model dir (default: MODEL_DIR)")
    ap.add_argument("--epochs", type=int, default=20)
    ap.add_argument("--stride", type=int, default=30)
    ap.add_argument("--rf-trees", type=int, default=300)
    args = ap.parse_args()

    if args.synthetic:
        df, source = synthetic.generate(args.synthetic * 1440), f"synthetic-{args.synthetic}d"
    else:
        df, source = candles.load(Path(args.data)), Path(args.data).name

    out = Path(args.out) if args.out else get_settings().model_dir
    cfg = TrainConfig(epochs=args.epochs, stride=args.stride, rf_trees=args.rf_trees, data_source=source)
    report = train(df, out, cfg)

    m = report["meta"]["metrics"]["sigma"]
    print(f"\nmodel {report['meta']['model_version']} → {out}")
    print(f"{'model':<16}{'MAE ticks':>12}{'QLIKE':>10}{'regime acc':>12}")
    for name, v in m.items():
        print(f"{name:<16}{v['mae_ticks']:>12.1f}{v['qlike']:>10.4f}{v['regime_accuracy']:>12.1%}")
    print(f"ensemble beats EWMA: {report['meta']['metrics']['ensemble_beats_ewma']}")
    print(f"regime edges (hook thresholds): {[round(e) for e in report['meta']['regime_edges']]}")
    print("\nLP backtest (test period):")
    for r in report["backtest"]["results"]:
        print(f"  {r['name']:<22} return {r['return_pct']:+7.2f}%  alpha vs HODL {r['alpha_vs_hodl_pct']:+6.2f}%  "
              f"fees ${r['fees_usd']:,.0f}  in-range {r['time_in_range_pct']:.0f}%  rebalances {r['rebalances']}")
    print(json.dumps({"ensemble_weights": report["meta"]["ensemble"]}))


if __name__ == "__main__":
    main()
