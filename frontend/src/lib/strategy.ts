export type Params = {
  widthMultiplierBps: number;
  minHalfWidth: number;
  maxHalfWidth: number;
  driftWeightBps: number;
  minRebalanceInterval: number;
  maxEmaDeviation: number;
  performanceFeeBps: number;
};

// Mirrors VaultFactory.presetParams
export const PRESETS: Record<"Aggressive" | "Balanced" | "Conservative", Params> = {
  Aggressive: { widthMultiplierBps: 10_000, minHalfWidth: 120, maxHalfWidth: 3000, driftWeightBps: 3000, minRebalanceInterval: 300, maxEmaDeviation: 60, performanceFeeBps: 1500 },
  Balanced: { widthMultiplierBps: 20_000, minHalfWidth: 300, maxHalfWidth: 6000, driftWeightBps: 2000, minRebalanceInterval: 900, maxEmaDeviation: 90, performanceFeeBps: 1000 },
  Conservative: { widthMultiplierBps: 35_000, minHalfWidth: 600, maxHalfWidth: 12_000, driftWeightBps: 1000, minRebalanceInterval: 3600, maxEmaDeviation: 120, performanceFeeBps: 500 },
};

export const PROFILE_INDEX = { Aggressive: 0, Balanced: 1, Conservative: 2, Custom: 3 } as const;

export const BOUNDS = {
  widthMultiplierBps: [5000, 50_000],
  minHalfWidth: [60, 40_000],
  maxHalfWidth: [60, 40_000],
  driftWeightBps: [0, 5000],
  minRebalanceInterval: [60, 86_400],
  maxEmaDeviation: [1, 500],
  performanceFeeBps: [0, 2000],
} as const;

export function profileName(p: Params): string {
  for (const [name, preset] of Object.entries(PRESETS)) {
    if ((Object.keys(preset) as (keyof Params)[]).every((k) => Number(preset[k]) === Number(p[k]))) return name;
  }
  return "Custom";
}

const ceilTo = (x: number, s: number) => Math.ceil(x / s) * s;
const floorTo = (x: number, s: number) => Math.floor(x / s) * s;

// Same as RangeMath.computeRange
export function targetRange(ema: number, sigma: number, drift: number, p: Params, spacing = 60) {
  let hw = ceilTo((sigma * p.widthMultiplierBps) / 10_000, spacing);
  hw = Math.min(Math.max(hw, p.minHalfWidth), p.maxHalfWidth);
  const bias = Math.max(-hw / 2, Math.min(hw / 2, Math.trunc((drift * p.driftWeightBps) / 10_000)));
  const c = ema + bias;
  return { lower: floorTo(c - hw, spacing), upper: ceilTo(c + hw, spacing), halfWidth: hw };
}
