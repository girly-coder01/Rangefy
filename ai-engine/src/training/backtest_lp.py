"""LP backtest: fixed ±600 vs EWMA-sized vs AI-sized ranges (Balanced profile rules)."""

from __future__ import annotations

from dataclasses import asdict, dataclass

import numpy as np
import pandas as pd

from ..constants import LN_TICK

SPACING = 60


@dataclass
class Profile:
    """Mirrors VaultFactory's Balanced preset."""
    width_multiplier: float = 2.0
    min_half_width: int = 300
    max_half_width: int = 6000
    drift_weight: float = 0.2
    cooldown_min: int = 15
    edge_buffer: float = 0.10
    width_drift: float = 0.30


@dataclass
class Assumptions:
    fee_rate: float = 0.003
    daily_volume_usd: float = 5_000_000.0
    pool_liquidity: float = 3e6  # active liquidity of the pool (L units, ≈ $30M in a ±20% band at $3000)
    capital_usd: float = 10_000.0


def _floor(x: float, s: int = SPACING) -> int:
    return int(np.floor(x / s) * s)


def _ceil(x: float, s: int = SPACING) -> int:
    return int(np.ceil(x / s) * s)


def _amounts(L: float, sp: float, sa: float, sb: float) -> tuple[float, float]:
    if sp <= sa:
        return L * (sb - sa) / (sa * sb), 0.0
    if sp >= sb:
        return 0.0, L * (sb - sa)
    return L * (sb - sp) / (sp * sb), L * (sp - sa)


def _liquidity_for_value(value1: float, p: float, sa: float, sb: float) -> float:
    """Liquidity whose position is worth `value1` (in token1) at price p."""
    x, y = _amounts(1.0, np.sqrt(p), sa, sb)
    return value1 / (x * p + y)


@dataclass
class Result:
    name: str
    final_value: float
    return_pct: float
    hodl_return_pct: float
    alpha_vs_hodl_pct: float
    fees_usd: float
    rebalance_cost_usd: float
    rebalances: int
    time_in_range_pct: float

    def to_dict(self) -> dict:
        return asdict(self)


def simulate(close: pd.Series, half_width_fn, drift_fn=None, name: str = "", profile: Profile | None = None,
             a: Assumptions | None = None) -> Result:
    profile = profile or Profile()
    a = a or Assumptions()
    prices = close.to_numpy(float)
    ticks = np.log(prices) / LN_TICK
    minute_vol = a.daily_volume_usd / 1440

    p0 = prices[0]
    hodl0, hodl1 = a.capital_usd / 2 / p0, a.capital_usd / 2

    def target(i: int) -> tuple[int, int, int]:
        hw = half_width_fn(i)
        bias = 0.0
        if drift_fn is not None:
            bias = float(np.clip(drift_fn(i) * profile.drift_weight, -hw / 2, hw / 2))
        center = ticks[i] + bias
        return _floor(center - hw), _ceil(center + hw), hw

    lo, hi, _ = target(0)
    sa, sb = 1.0001 ** (lo / 2), 1.0001 ** (hi / 2)
    L = _liquidity_for_value(a.capital_usd, p0, sa, sb)
    fees = cost = 0.0
    last_rb = 0
    n_rb = 0
    in_range = 0

    for i in range(1, len(prices)):
        p = prices[i]
        t = ticks[i]
        if lo <= t < hi:
            in_range += 1
            fees += a.fee_rate * minute_vol * L / a.pool_liquidity

        if i - last_rb < profile.cooldown_min:
            continue
        w = hi - lo
        buf = w * profile.edge_buffer
        tlo, thi, thw = target(i)
        reason = (
            t < lo or t >= hi
            or t < lo + buf or t >= hi - buf
            or abs(thw - w / 2) >= (w / 2) * profile.width_drift
        )
        if not reason:
            continue

        sp = np.sqrt(p)
        x0, y0 = _amounts(L, sp, sa, sb)
        value = x0 * p + y0
        nsa, nsb = 1.0001 ** (tlo / 2), 1.0001 ** (thi / 2)
        xu, yu = _amounts(1.0, sp, nsa, nsb)
        target_x = value * xu / (xu * p + yu)
        swap_cost = a.fee_rate * abs(target_x - x0) * p
        cost += swap_cost
        L = _liquidity_for_value(value - swap_cost, p, nsa, nsb)
        lo, hi, sa, sb = tlo, thi, nsa, nsb
        last_rb = i
        n_rb += 1

    pN = prices[-1]
    x, y = _amounts(L, np.sqrt(pN), sa, sb)
    final = x * pN + y + fees
    hodl = hodl0 * pN + hodl1
    ret = final / a.capital_usd - 1
    hret = hodl / a.capital_usd - 1
    return Result(name, final, 100 * ret, 100 * hret, 100 * (ret - hret), fees, cost, n_rb,
                  100 * in_range / max(1, len(prices) - 1))


def _clamp_hw(sigma: float, p: Profile) -> int:
    return int(np.clip(_ceil(sigma * p.width_multiplier), p.min_half_width, p.max_half_width))


def run(close: pd.Series, sigma_ai: pd.Series, drift_ai: pd.Series, sigma_ewma: pd.Series,
        profile: Profile | None = None, a: Assumptions | None = None) -> dict:
    profile = profile or Profile()
    s_ai = sigma_ai.reindex(close.index).ffill().bfill().to_numpy()
    d_ai = drift_ai.reindex(close.index).ffill().fillna(0).to_numpy()
    s_ew = sigma_ewma.reindex(close.index).ffill().bfill().to_numpy()

    results = [
        simulate(close, lambda i: 600, name="fixed ±600", profile=profile, a=a),
        simulate(close, lambda i: _clamp_hw(s_ew[i], profile), name="EWMA-sized", profile=profile, a=a),
        simulate(close, lambda i: _clamp_hw(s_ai[i], profile), lambda i: d_ai[i], name="AI-sized (Balanced)",
                 profile=profile, a=a),
    ]
    return {
        "period": {"start": str(close.index[0]), "end": str(close.index[-1]), "minutes": int(len(close))},
        "assumptions": asdict(a or Assumptions()),
        "profile": asdict(profile),
        "results": [r.to_dict() for r in results],
    }
