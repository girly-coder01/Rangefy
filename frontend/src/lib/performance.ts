import { tickToUsd, toWethUsdc, usdValue } from "./pool";

export type Snapshot = { total0: bigint; total1: bigint; totalSupply: bigint; emaTick: number; timestamp: number };
export type FeeEvent = { fees0: bigint; fees1: bigint; curatorFee0: bigint; curatorFee1: bigint; ts: number };
export type RangeSegment = { from: number; lower: number; upper: number };
export type PriceSample = { ts: number; tick: number };

export type Performance = {
  vaultReturn: number;
  hodlReturn: number;
  alpha: number;
  feeApr: number;
  timeInRange: number;
  tvlUsd: number;
};

function navUsd(s: Snapshot) {
  const { weth, usdc } = toWethUsdc(s.total0, s.total1);
  return usdValue(weth, usdc, tickToUsd(s.emaTick));
}

// Vault vs holding the first depositor's per-share basket (docs §7.8).
export function returns(snaps: Snapshot[]) {
  const live = snaps.filter((s) => s.totalSupply > 0n);
  if (live.length < 2) return { vaultReturn: 0, hodlReturn: 0, alpha: 0 };
  const first = live[0];
  const last = live[live.length - 1];
  const ps0 = navUsd(first) / Number(first.totalSupply);
  const ps1 = navUsd(last) / Number(last.totalSupply);

  const { weth, usdc } = toWethUsdc(first.total0, first.total1);
  const basket = (ethUsd: number) => (Number(weth) / 1e18) * ethUsd + Number(usdc) / 1e6;
  const hodlThen = basket(tickToUsd(first.emaTick));
  const hodlNow = basket(tickToUsd(last.emaTick));

  const vaultReturn = ps0 > 0 ? ps1 / ps0 - 1 : 0;
  const hodlReturn = hodlThen > 0 ? hodlNow / hodlThen - 1 : 0;
  return { vaultReturn, hodlReturn, alpha: vaultReturn - hodlReturn };
}

export function feeApr(fees: FeeEvent[], snaps: Snapshot[], ethUsd: number): number {
  const live = snaps.filter((s) => s.totalSupply > 0n);
  if (!live.length || !fees.length) return 0;
  const start = live[0].timestamp;
  const end = Math.max(live[live.length - 1].timestamp, fees[fees.length - 1].ts);
  const years = Math.max(end - start, 86_400) / (365 * 86_400); // at least a day so young vaults don't annualize noise
  let earned = 0;
  for (const f of fees) {
    const { weth, usdc } = toWethUsdc(f.fees0 - f.curatorFee0, f.fees1 - f.curatorFee1);
    earned += usdValue(weth, usdc, ethUsd);
  }
  const avgTvl = live.reduce((a, s) => a + navUsd(s), 0) / live.length;
  return avgTvl > 0 ? earned / avgTvl / years : 0;
}


export function timeInRange(samples: PriceSample[], ranges: RangeSegment[], now: number): number {
  if (!ranges.length) return 0;
  const ticks = [...samples].sort((a, b) => a.ts - b.ts);
  const segs = [...ranges].sort((a, b) => a.from - b.from);
  const start = segs[0].from;
  let inside = 0;
  let total = 0;
  let tick = ticks.filter((s) => s.ts <= start).at(-1)?.tick ?? ticks[0]?.tick;
  if (tick == null) return 0;
  const points = [...new Set([start, ...ticks.map((t) => t.ts).filter((t) => t > start), ...segs.map((s) => s.from), now])]
    .filter((t) => t >= start && t <= now)
    .sort((a, b) => a - b);
  for (let i = 0; i < points.length - 1; i++) {
    const t = points[i];
    const dt = points[i + 1] - t;
    tick = ticks.filter((s) => s.ts <= t).at(-1)?.tick ?? tick;
    const seg = segs.filter((s) => s.from <= t).at(-1)!;
    if (tick >= seg.lower && tick < seg.upper) inside += dt;
    total += dt;
  }
  return total > 0 ? inside / total : 0;
}

export function tvlUsd(total0: bigint, total1: bigint, ethUsd: number) {
  const { weth, usdc } = toWethUsdc(total0, total1);
  return usdValue(weth, usdc, ethUsd);
}
