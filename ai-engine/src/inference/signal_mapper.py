"""Forecast -> SignalOracle args, and when to post."""

from __future__ import annotations

from dataclasses import dataclass

from ..constants import MAX_CONFIDENCE_BPS, MAX_DRIFT_TICKS, MAX_SIGMA_TICKS, MIN_SIGMA_TICKS
from .forecaster import Forecast

SIGMA_CHANGE_THRESHOLD = 0.10
HEARTBEAT_S = 10 * 60


@dataclass(frozen=True)
class OnchainSignal:
    sigma_ticks: int
    drift_ticks: int
    regime: int
    confidence_bps: int
    model_version: bytes  # exactly 8 bytes

    def as_args(self) -> tuple:
        return (self.sigma_ticks, self.drift_ticks, self.regime, self.confidence_bps, self.model_version)


def model_version_bytes8(version: str) -> bytes:
    raw = version.encode()[:8]
    return raw.ljust(8, b"\0")


def to_onchain(f: Forecast, base_is_token0: bool) -> OnchainSignal:
    """`base_is_token0`: True when mWETH (the priced asset) sorts as currency0."""
    sigma = int(round(min(max(f.sigma_ticks, MIN_SIGMA_TICKS), MAX_SIGMA_TICKS)))
    drift = f.drift_ticks if base_is_token0 else -f.drift_ticks
    drift = int(round(min(max(drift, -MAX_DRIFT_TICKS), MAX_DRIFT_TICKS)))
    conf = int(min(max(f.confidence_bps, 0), MAX_CONFIDENCE_BPS))
    regime = int(min(max(f.regime, 0), 3))
    return OnchainSignal(sigma, drift, regime, conf, model_version_bytes8(f.model_version))


def should_post(new: OnchainSignal, last: OnchainSignal | None, seconds_since_last: float | None) -> tuple[bool, str]:
    """Post on first run, ≥10% sigma change, regime change, or the 10-minute heartbeat."""
    if last is None or seconds_since_last is None:
        return True, "first"
    if new.regime != last.regime:
        return True, "regime_change"
    if abs(new.sigma_ticks - last.sigma_ticks) >= SIGMA_CHANGE_THRESHOLD * last.sigma_ticks:
        return True, "sigma_change"
    if seconds_since_last >= HEARTBEAT_S:
        return True, "heartbeat"
    return False, "unchanged"
