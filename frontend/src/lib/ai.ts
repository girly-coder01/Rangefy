export const AI_API_URL = (process.env.NEXT_PUBLIC_AI_API_URL || "").replace(/\/$/, "");

export async function aiGet<T>(path: string, params?: Record<string, string | number>): Promise<T> {
  if (!AI_API_URL) throw new Error("AI API not configured");
  const qs = params ? `?${new URLSearchParams(Object.entries(params).map(([k, v]) => [k, String(v)]))}` : "";
  const res = await fetch(`${AI_API_URL}${path}${qs}`, { signal: AbortSignal.timeout(6000) });
  if (!res.ok) throw new Error(`${path}: ${res.status}`);
  return res.json() as Promise<T>;
}

export type SignalPoint = {
  ts: number;
  sigma_ticks: number;
  drift_ticks: number;
  regime: number;
  regime_name: string;
  confidence_bps: number;
  model_version: string;
  posted: boolean;
  reason: string;
  tx_hash: string | null;
};

export type ForecastResponse = {
  timestamp: string;
  price: number;
  models: {
    ewma: { sigma_ticks: number };
    random_forest: { sigma_ticks: number; drift_ticks: number };
    transformer: { sigma_ticks: number; drift_ticks: number };
    ensemble: { sigma_ticks: number; drift_ticks: number; regime: string; confidence_bps: number };
  };
  weights: { w_rf: number } | null;
  regime_edges: number[] | null;
  model_version: string;
};

export type BacktestResult = {
  name: string;
  return_pct: number;
  hodl_return_pct: number;
  alpha_vs_hodl_pct: number;
  fees_usd: number;
  rebalance_cost_usd: number;
  rebalances: number;
  time_in_range_pct: number;
};

export type ModelMetrics = Record<string, { mae_ticks: number; qlike: number; regime_accuracy: number }>;

export type BacktestResponse = {
  backtest: { period: { start: string; end: string; minutes: number }; results: BacktestResult[] };
  metrics: { sigma: ModelMetrics; ensemble_beats_ewma: boolean } | null;
  model_version: string | null;
};

export type MirrorStatus = {
  real_price: number;
  testnet_price: number;
  deviation_bps: number;
  updated_at: number;
  last_mirror_tx: { tx_hash: string; ts: number } | null;
};

export type Health = { status: string; model_version: string | null; trained_on: { source: string } | null };
