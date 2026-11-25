"""One round of every keeper job against the configured chain, with explorer links.

  python scripts/smoke_onchain.py [--rounds 3] [--no-signal]

The signal step posts 24h realized vol from CoinGecko 5m prices (model version cgrv0001),
for when the trained model or minute candles aren't available.
"""

import argparse
import math
import random
from types import SimpleNamespace

import _bootstrap  # noqa: F401
import httpx

from src.chain.client import RangefyChain
from src.chain.tx import TxSender
from src.config import get_settings
from src.constants import LN_TICK
from src.data.labeler import to_regime
from src.inference.forecaster import Forecast
from src.keeper import jobs as J
from src.store.db import Store

EXPLORER = "https://sepolia.uniscan.xyz/tx/"
EDGES = (188, 321, 548)


def realized_vol_forecast() -> Forecast:
    r = httpx.get(
        "https://api.coingecko.com/api/v3/coins/ethereum/market_chart",
        params={"vs_currency": "usd", "days": 1},
        timeout=15,
    )
    r.raise_for_status()
    prices = [p for _, p in r.json()["prices"]]
    rets = [math.log(b / a) for a, b in zip(prices, prices[1:], strict=False)]
    mean = sum(rets) / len(rets)
    var = sum((x - mean) ** 2 for x in rets) / len(rets)
    sigma = math.sqrt(var * len(rets)) / LN_TICK  # ~24h of samples
    regime = int(to_regime(sigma, EDGES))
    return Forecast(
        timestamp="now", sigma_ticks=sigma, drift_ticks=0.0, regime=regime,
        regime_name=("Calm", "Normal", "High", "Extreme")[regime], confidence_bps=5000, model_version="cgrv0001",
        rf_sigma=sigma, tf_sigma=sigma, ewma_sigma=sigma, rf_drift=0.0, tf_drift=0.0, price=prices[-1],
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=1)
    ap.add_argument("--no-signal", action="store_true")
    args = ap.parse_args()

    s = get_settings()
    chain = RangefyChain(s)
    store = Store(s.db_path)
    keeper = TxSender(chain.w3, s.keeper_key)
    mirror = TxSender(chain.w3, s.mirror_key)
    updater = TxSender(chain.w3, s.signal_updater_key)
    locks = J.VaultLocks()
    rng = random.Random()

    def show(name: str, out: str) -> None:
        print(f"{name:<10} {out}")

    if not args.no_signal:
        f = realized_vol_forecast()
        fc = SimpleNamespace(forecast=lambda df: f)
        job = J.SignalJob(chain, updater, store, fc, SimpleNamespace(refresh=lambda: None))
        show("signal", job())

    for _ in range(args.rounds):
        show("mirror", J.MirrorJob(chain, mirror, store, s)())
        show("noise", J.NoiseJob(chain, mirror, store, rng)())
        show("rebalance", J.RebalanceJob(chain, keeper, store, locks)())

    for v in chain.all_vaults():
        needed, reason = chain.needs_rebalance(v)
        vault = chain.vault(v)
        print(f"vault {v} rebalances={vault.functions.rebalanceCount().call()} needs={needed}:{reason}")

    p = chain.pool_state()
    print(f"pool ${chain.priced.eth_usd(p.sqrt_price_x96):,.2f} sigma={p.sigma} fresh={p.signal_fresh} fee={p.fee}")
    for e in store.keeper_events(10):
        if e["tx_hash"]:
            print(f"  {e['job']:<9} {e['status']:<8} {EXPLORER}0x{e['tx_hash'].removeprefix('0x')}")
    for m in store.mirror_latest(3):
        if m["tx_hash"]:
            print(f"  mirror    {EXPLORER}0x{m['tx_hash'].removeprefix('0x')}")


if __name__ == "__main__":
    main()
