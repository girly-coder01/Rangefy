"use client";

import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Brain, CircleDot, ExternalLink } from "lucide-react";
import { Badge, Card, CardTitle, PageHeader, Stat } from "@/components/ui";
import { RegimeBadge, SignalBadge } from "@/components/badges";
import { REGIMES, usePool } from "@/hooks/useProtocol";
import { useOnchainSignals, usePoolHistory } from "@/hooks/useHistory";
import { useBacktest, useForecast } from "@/hooks/useAI";
import { explorerTx } from "@/config/chains";
import staticBacktest from "@/config/ai-backtest.json";
import type { BacktestResponse } from "@/lib/ai";
import { fmtBps, fmtFeePips, fmtPct, fmtUsd, timeAgo } from "@/lib/format";

const tickPct = (t?: number) => (t == null || !Number.isFinite(t) ? "—" : `${(t / 100).toFixed(2)}%`);
const MODEL_LABEL: Record<string, string> = {
  ewma_baseline: "EWMA baseline",
  random_forest: "Random Forest",
  transformer: "Transformer",
  ensemble: "Ensemble",
};

export default function AIPage() {
  const { pool } = usePool();
  const forecast = useForecast();
  const apiBacktest = useBacktest();
  const onchain = usePoolHistory();
  const signals = useOnchainSignals();

  const bt = (apiBacktest.data ?? staticBacktest) as BacktestResponse;
  const live = !!pool?.signalFresh;
  const series = [
    ...(onchain.data ?? []).slice(-400).map((p) => ({ ts: p.ts, onchain: p.sigma })),
    ...(signals.data ?? []).map((s) => ({ ts: s.ts, ai: s.sigma })),
  ].sort((a, b) => a.ts - b.ts);

  return (
    <div className="space-y-6">
      <PageHeader
        title="AI signal"
        subtitle="Forecast 24h volatility, posted on-chain as a bounded, expiring signal. The hook never trusts it blindly."
        right={<div className="flex gap-2"><RegimeBadge regime={pool?.regime} /><SignalBadge fresh={pool?.signalFresh} /></div>}
      />

      <Card className="grid grid-cols-2 gap-5 sm:grid-cols-4">
        <Stat label="σ used for ranges (24h)" value={tickPct(pool?.sigma)} sub={pool ? `${pool.sigma} ticks · ${live ? "AI signal" : "on-chain"}` : undefined} />
        <Stat label="On-chain realized σ" value={tickPct(pool?.onchainSigma)} />
        <Stat label="Regime" value={pool ? REGIMES[pool.regime] : "—"} />
        <Stat label="Swap fee now" value={pool ? fmtFeePips(pool.fee) : "—"} sub={live ? `confidence ${fmtBps(pool!.confidenceBps)}` : undefined} />
      </Card>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_380px]">
        <Card className="min-w-0">
          <CardTitle>Volatility: on-chain vs AI signals</CardTitle>
          <div className="h-64">
            {series.length < 2 ? (
              <div className="flex h-full items-center justify-center text-sm text-muted">Waiting for swaps…</div>
            ) : (
              <ResponsiveContainer>
                <LineChart data={series}>
                  <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" />
                  <XAxis dataKey="ts" type="number" domain={["dataMin", "dataMax"]} tickFormatter={(t) => new Date(t * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} stroke="var(--muted)" fontSize={11} />
                  <YAxis stroke="var(--muted)" fontSize={11} tickFormatter={(v) => `${(v / 100).toFixed(1)}%`} />
                  <Tooltip contentStyle={{ background: "var(--card)", border: "1px solid var(--border)" }} labelFormatter={(t) => new Date(Number(t) * 1000).toLocaleString()} formatter={(v, n) => [tickPct(Number(v)), n === "ai" ? "AI signal" : "On-chain"]} />
                  <Line dataKey="onchain" stroke="var(--range)" dot={false} strokeWidth={1.5} connectNulls />
                  <Line dataKey="ai" stroke="var(--accent)" dot={{ r: 3 }} strokeWidth={0} connectNulls={false} />
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>
        </Card>

        <Card>
          <CardTitle right={<Badge tone={forecast.data ? "accent" : "warning"}>{forecast.data ? "Live" : "Paused"}</Badge>}>Model</CardTitle>
          {forecast.data ? (
            <ul className="num space-y-2 text-sm">
              <li className="flex justify-between"><span className="font-sans">Random Forest</span>{tickPct(forecast.data.models.random_forest.sigma_ticks)}</li>
              <li className="flex justify-between"><span className="font-sans">Transformer</span>{tickPct(forecast.data.models.transformer.sigma_ticks)}</li>
              <li className="flex justify-between font-semibold"><span className="font-sans">Ensemble</span>{tickPct(forecast.data.models.ensemble.sigma_ticks)}</li>
              <li className="pt-2 text-xs text-muted">ETH {fmtUsd(forecast.data.price)} · {forecast.data.model_version}</li>
            </ul>
          ) : (
            <div className="space-y-4 text-sm">
              <div className="flex gap-3">
                <Brain className="mt-0.5 shrink-0 text-accent" size={18} />
                <p className="text-muted">
                  The Transformer + Random Forest ensemble is trained and backtested, but the live feed is paused while we retrain on real ETH candles.
                </p>
              </div>
              <div className="flex gap-3">
                <CircleDot className="mt-0.5 shrink-0 text-range" size={18} />
                <p className="text-muted">
                  Until then, ranges and fees use the hook&apos;s on-chain volatility: the built-in fallback, no trust required.
                </p>
              </div>
              <div className="rounded-lg bg-background p-3 text-xs text-muted">
                Model <span className="num text-foreground">{bt.model_version}</span> · ensemble beats EWMA:{" "}
                <span className="text-foreground">{bt.metrics?.ensemble_beats_ewma ? "yes" : "no"}</span>
              </div>
            </div>
          )}
        </Card>
      </div>

      <Card>
        <CardTitle right={<span className="text-xs text-muted">synthetic ETH-like data, test split</span>}>Backtest: AI-sized ranges vs fixed</CardTitle>
        <div className="overflow-x-auto">
          <table className="num w-full text-sm">
            <thead className="text-left text-xs text-muted">
              <tr><th className="pb-2">Strategy</th><th>Return</th><th>vs HODL</th><th>Fees</th><th>Rebalance cost</th><th>Rebalances</th></tr>
            </thead>
            <tbody>
              {bt.backtest.results.map((r) => (
                <tr key={r.name} className="border-t border-border">
                  <td className="py-2 font-sans">{r.name}</td>
                  <td>{fmtPct(r.return_pct / 100, 2, true)}</td>
                  <td className={r.alpha_vs_hodl_pct >= Math.max(...bt.backtest.results.map((x) => x.alpha_vs_hodl_pct)) ? "text-success" : "text-muted"}>
                    {fmtPct(r.alpha_vs_hodl_pct / 100, 2, true)}
                  </td>
                  <td>{fmtUsd(r.fees_usd, 0)}</td>
                  <td>{fmtUsd(r.rebalance_cost_usd, 0)}</td>
                  <td>{r.rebalances}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {bt.metrics && (
          <div className="mt-5 grid grid-cols-2 gap-4 sm:grid-cols-4">
            {Object.entries(bt.metrics.sigma).map(([k, m]) => (
              <Stat key={k} label={MODEL_LABEL[k] ?? k} value={`${m.mae_ticks.toFixed(0)} ticks`} sub={`MAE · regime acc ${fmtPct(m.regime_accuracy, 0)}`} />
            ))}
          </div>
        )}
      </Card>

      <Card>
        <CardTitle>On-chain signal feed</CardTitle>
        {signals.data?.length ? (
          <ul className="num space-y-2 text-sm">
            {[...signals.data].reverse().slice(0, 12).map((s) => (
              <li key={s.tx + s.ts} className="flex flex-wrap items-center justify-between gap-2 border-b border-border pb-2 last:border-0">
                <span className="text-muted">{timeAgo(s.ts)}</span>
                <span>σ {tickPct(s.sigma)} · drift {tickPct(s.drift)} · {REGIMES[s.regime]}</span>
                <span className="flex items-center gap-2 text-muted">
                  {s.version}
                  {explorerTx(s.tx) && (
                    <a href={explorerTx(s.tx)} target="_blank" rel="noreferrer" className="hover:text-foreground"><ExternalLink size={12} /></a>
                  )}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-muted">No signals posted yet.</p>
        )}
      </Card>
    </div>
  );
}
