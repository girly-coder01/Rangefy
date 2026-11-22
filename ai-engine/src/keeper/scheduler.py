"""Runs each job on its interval in a worker thread. Failures are logged, never fatal."""

from __future__ import annotations

import asyncio
import random
from collections.abc import Callable
from dataclasses import dataclass

import structlog

from ..store.db import Store

log = structlog.get_logger()


@dataclass
class Scheduled:
    job: Callable[[], str]
    name: str
    interval: Callable[[], float]  # seconds until next run


async def _loop(s: Scheduled, store: Store, stop: asyncio.Event) -> None:
    while not stop.is_set():
        try:
            detail = await asyncio.to_thread(s.job)
            store.record_run(s.name, True, detail)
            log.info("job.ok", job=s.name, detail=detail)
        except Exception as e:  # noqa: BLE001 — a job must never kill the keeper
            store.record_run(s.name, False, f"{type(e).__name__}: {e}")
            log.error("job.failed", job=s.name, error=str(e))
        try:
            await asyncio.wait_for(stop.wait(), timeout=s.interval())
        except TimeoutError:
            pass


async def run(jobs: list[Scheduled], store: Store, stop: asyncio.Event | None = None) -> None:
    stop = stop or asyncio.Event()
    await asyncio.gather(*(_loop(j, store, stop) for j in jobs))


def fixed(seconds: float) -> Callable[[], float]:
    return lambda: seconds


def jitter(lo: float, hi: float, rng: random.Random | None = None) -> Callable[[], float]:
    r = rng or random.Random()
    return lambda: r.uniform(lo, hi)
