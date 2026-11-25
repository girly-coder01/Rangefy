import { pool } from "@/config/addresses";
import { displayPrice, priceFromSqrtX96, rangeToPrices } from "./math";

const d0 = pool.token0.decimals;
const d1 = pool.token1.decimals;

/** USD per mWETH at a pool tick. */
export const tickToUsd = (tick: number) => displayPrice(tick, d0, d1, pool.wethIsToken0);

export function sqrtToUsd(sqrtPriceX96: bigint): number {
  const p = priceFromSqrtX96(sqrtPriceX96, d0, d1);
  return pool.wethIsToken0 ? p : 1 / p;
}

export const rangeUsd = (lower: number, upper: number) => rangeToPrices(lower, upper, d0, d1, pool.wethIsToken0);

/** Contract (amount0, amount1) ↔ (mWETH, mUSDC). */
export const toWethUsdc = (a0: bigint, a1: bigint) => (pool.wethIsToken0 ? { weth: a0, usdc: a1 } : { weth: a1, usdc: a0 });
export const fromWethUsdc = (weth: bigint, usdc: bigint): [bigint, bigint] =>
  pool.wethIsToken0 ? [weth, usdc] : [usdc, weth];

export function usdValue(weth: bigint, usdc: bigint, ethUsd: number): number {
  return (Number(weth) / 1e18) * ethUsd + Number(usdc) / 1e6;
}

// block -> timestamp, linear between two known blocks
export function blockClock(a: { block: bigint; ts: number }, b: { block: bigint; ts: number }) {
  const span = Number(b.block - a.block);
  const rate = span > 0 ? (b.ts - a.ts) / span : 1;
  return (block: bigint) => a.ts + Number(block - a.block) * rate;
}
