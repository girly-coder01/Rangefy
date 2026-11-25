import { PRESETS, profileName, targetRange } from "@/lib/strategy";

describe("targetRange (mirrors RangeMath.computeRange)", () => {
  it("matches contract cases", () => {
    // RangeVault.t.sol: σ 299, Balanced, EMA 0 → [-600, 600]
    expect(targetRange(0, 299, 0, PRESETS.Balanced)).toMatchObject({ lower: -600, upper: 600 });
    // σ 1000 → hw 2040
    expect(targetRange(0, 1000, 0, PRESETS.Balanced)).toMatchObject({ lower: -2040, upper: 2040 });
    // drift 2000 at 20% → bias 400
    expect(targetRange(0, 1000, 2000, PRESETS.Balanced)).toMatchObject({ lower: -1680, upper: 2460 });
  });

  it("clamps half-width and bias", () => {
    expect(targetRange(0, 20, 0, PRESETS.Balanced).halfWidth).toBe(300);
    expect(targetRange(0, 5000, 0, PRESETS.Balanced).halfWidth).toBe(6000);
    const r = targetRange(0, 100, 2000, { ...PRESETS.Aggressive, driftWeightBps: 5000 });
    expect(r.halfWidth).toBe(120);
    expect(r.lower).toBe(-60); // bias capped at hw/2 = 60
  });

  it("names presets", () => {
    expect(profileName(PRESETS.Conservative)).toBe("Conservative");
    expect(profileName({ ...PRESETS.Balanced, performanceFeeBps: 900 })).toBe("Custom");
  });
});
