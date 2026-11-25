import { displayPrice, priceFromSqrtX96, rangeToPrices, tickFromDisplayPrice, tickFromPrice, priceFromTick } from "@/lib/math";

// mWETH 18 dec, mUSDC 6 dec, ETH = 3000 USDC
const WETH = 18;
const USDC = 6;

describe("tick/price math", () => {
  it("round-trips tick ↔ price", () => {
    for (const t of [-200_000, -1, 0, 1, 12_345, 200_000]) {
      expect(tickFromPrice(priceFromTick(t, WETH, USDC), WETH, USDC)).toBeCloseTo(t, 6);
    }
  });

  it("shows mUSDC per mWETH when mWETH is token0", () => {
    const tick = tickFromDisplayPrice(3000, WETH, USDC, true);
    expect(displayPrice(tick, WETH, USDC, true)).toBeCloseTo(3000, 6);
    expect(tick).toBeLessThan(0); // 3000e6 / 1e18 < 1
  });

  it("shows mUSDC per mWETH when mUSDC is token0 (inverted)", () => {
    const tick = tickFromDisplayPrice(3000, USDC, WETH, false);
    expect(displayPrice(tick, USDC, WETH, false)).toBeCloseTo(3000, 6);
    expect(tick).toBeGreaterThan(0);
  });

  it("orders range prices low→high in both orderings", () => {
    const [lo, hi] = rangeToPrices(195_000, 196_000, USDC, WETH, false);
    expect(lo).toBeLessThan(hi);
    const [lo2, hi2] = rangeToPrices(-196_000, -195_000, WETH, USDC, true);
    expect(lo2).toBeLessThan(hi2);
  });

  it("converts sqrtPriceX96 to price", () => {
    const q96 = 2n ** 96n;
    expect(priceFromSqrtX96(q96, 18, 18)).toBeCloseTo(1, 12);
    expect(priceFromSqrtX96(q96 * 2n, 18, 18)).toBeCloseTo(4, 12);
  });
});
