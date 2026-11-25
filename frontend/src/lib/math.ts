// tick/price helpers; the UI shows mUSDC per mWETH

export const TICK_BASE = 1.0001;

export function priceFromTick(tick: number, dec0: number, dec1: number): number {
  return TICK_BASE ** tick * 10 ** (dec0 - dec1);
}

export function tickFromPrice(price: number, dec0: number, dec1: number): number {
  return Math.log(price / 10 ** (dec0 - dec1)) / Math.log(TICK_BASE);
}

/**
 * Display price (quote per base, e.g. mUSDC per mWETH) for a pool tick.
 * `baseIsToken0` = true when mWETH sorts as currency0.
 */
export function displayPrice(tick: number, dec0: number, dec1: number, baseIsToken0: boolean): number {
  const p = priceFromTick(tick, dec0, dec1);
  return baseIsToken0 ? p : 1 / p;
}

/** Pool tick for a display price (inverse of displayPrice). */
export function tickFromDisplayPrice(price: number, dec0: number, dec1: number, baseIsToken0: boolean): number {
  return tickFromPrice(baseIsToken0 ? price : 1 / price, dec0, dec1);
}

export function rangeToPrices(
  tickLower: number,
  tickUpper: number,
  dec0: number,
  dec1: number,
  baseIsToken0: boolean,
): [number, number] {
  const a = displayPrice(tickLower, dec0, dec1, baseIsToken0);
  const b = displayPrice(tickUpper, dec0, dec1, baseIsToken0);
  return a <= b ? [a, b] : [b, a];
}

export function priceFromSqrtX96(sqrtPriceX96: bigint, dec0: number, dec1: number): number {
  const sqrt = Number(sqrtPriceX96) / 2 ** 96;
  return sqrt * sqrt * 10 ** (dec0 - dec1);
}
