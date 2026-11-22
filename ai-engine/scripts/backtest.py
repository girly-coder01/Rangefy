"""Print the saved LP backtest (data/models/backtest.json) as a table."""

import json

import _bootstrap  # noqa: F401

from src.config import get_settings


def main() -> None:
    bt = json.loads((get_settings().model_dir / "backtest.json").read_text())
    p = bt["period"]
    print(f"period {p['start']} → {p['end']} ({p['minutes']:,} min)")
    for r in bt["results"]:
        print(f"  {r['name']:<22} return {r['return_pct']:+7.2f}%  HODL {r['hodl_return_pct']:+7.2f}%  "
              f"alpha {r['alpha_vs_hodl_pct']:+6.2f}%  fees ${r['fees_usd']:,.0f}  "
              f"cost ${r['rebalance_cost_usd']:,.0f}  in-range {r['time_in_range_pct']:.0f}%  "
              f"rebalances {r['rebalances']}")


if __name__ == "__main__":
    main()
