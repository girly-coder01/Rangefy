"""Run keeper jobs. Jobs without a configured key are skipped."""

import asyncio
import random

import _bootstrap  # noqa: F401
import structlog

from src.chain.client import RangefyChain
from src.chain.tx import TxSender
from src.config import get_settings
from src.data.collector import CandleCache
from src.inference.forecaster import Forecaster
from src.keeper import jobs as J
from src.keeper.scheduler import Scheduled, fixed, jitter, run
from src.store.db import Store

log = structlog.get_logger()


def main() -> None:
    s = get_settings()
    chain = RangefyChain(s)
    store = Store(s.db_path)
    locks = J.VaultLocks()
    tasks: list[Scheduled] = []

    if s.signal_updater_key and (s.model_dir / "meta.json").exists():
        fc = Forecaster(s.model_dir)
        cache = CandleCache(s.price_source, keep_minutes=fc.min_history + 60)
        signal = J.SignalJob(chain, TxSender(chain.w3, s.signal_updater_key), store, fc, cache)
        tasks.append(Scheduled(signal, "signal", fixed(s.signal_interval_s)))
    else:
        log.warning("keeper.skip", job="signal", why="SIGNAL_UPDATER_KEY or trained model missing")

    if s.keeper_key:
        keeper = TxSender(chain.w3, s.keeper_key)
        tasks.append(Scheduled(J.RebalanceJob(chain, keeper, store, locks), "rebalance", fixed(s.rebalance_interval_s)))
        tasks.append(Scheduled(J.HarvestJob(chain, keeper, store, locks), "harvest", fixed(s.harvest_interval_s)))
    else:
        log.warning("keeper.skip", job="rebalance/harvest", why="KEEPER_KEY missing")

    if s.mirror_key:
        mirror = TxSender(chain.w3, s.mirror_key)
        tasks.append(Scheduled(J.MirrorJob(chain, mirror, store, s), "mirror", fixed(s.mirror_interval_s)))
        if s.enable_noise:
            rng = random.Random()
            tasks.append(Scheduled(J.NoiseJob(chain, mirror, store, rng), "noise", jitter(30, 90, rng)))
    else:
        log.warning("keeper.skip", job="mirror/noise", why="MIRROR_KEY missing")

    if not tasks:
        raise SystemExit("nothing to run: configure SIGNAL_UPDATER_KEY / KEEPER_KEY / MIRROR_KEY")
    log.info("keeper.start", jobs=[t.name for t in tasks])
    asyncio.run(run(tasks, store))


if __name__ == "__main__":
    main()
