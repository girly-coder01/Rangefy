jest.mock("@/config/addresses", () => ({
  pool: { wethIsToken0: true, token0: { decimals: 18 }, token1: { decimals: 6 } },
}));

import { returns, timeInRange } from "@/lib/performance";
import { tickFromDisplayPrice } from "@/lib/math";

const tickAt = (usd: number) => Math.round(tickFromDisplayPrice(usd, 18, 6, true));

describe("performance", () => {
  it("vault return vs HODL", () => {
    const s0 = { total0: 10n ** 18n, total1: 3000n * 10n ** 6n, totalSupply: 1000n, emaTick: tickAt(3000), timestamp: 0 };
    // price unchanged, vault gained 1% in token1 → alpha ≈ +1% of NAV / 2
    const s1 = { ...s0, total1: 3060n * 10n ** 6n, timestamp: 100 };
    const r = returns([s0, s1]);
    expect(r.hodlReturn).toBeCloseTo(0, 3);
    expect(r.vaultReturn).toBeCloseTo(0.01, 3);
    expect(r.alpha).toBeCloseTo(0.01, 3);
  });

  it("time in range", () => {
    const ranges = [{ from: 0, lower: -100, upper: 100 }];
    const samples = [
      { ts: 0, tick: 0 },
      { ts: 50, tick: 500 },
      { ts: 75, tick: 0 },
    ];
    expect(timeInRange(samples, ranges, 100)).toBeCloseTo(0.75, 5);
  });
});
