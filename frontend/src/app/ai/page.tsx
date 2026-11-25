"use client";

import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Card, CardTitle, Empty, PageHeader, Stat } from "@/components/ui";
import { RegimeBadge, SignalBadge } from "@/components/badges";
import { usePool } from "@/hooks/useProtocol";
import { usePoolHistory } from "@/hooks/useHistory";
import { useAIHealth, useBacktest, useForecast, useSignalHistory } from "@/hooks/useAI";
import { AI_API_URL } from "@/lib/ai";
import { fmtBps, fmtFeePips, fmtPct, fmtUsd, timeAgo } from "@/lib/format";

const tickPct = (t?: number) => (t == null ? "—" : `${(t / 100).toFixed(2)}%`);

export default function AIPage() {
  const { pool } = usePool();
  const health = useAIHealth();
  const forecast = useForecast();
  const history = useSignalHistory(24);
  const backtest = useBacktest();
  const onchain = usePoolHistory();

  const realized = (onchain.data ?? []).slice(-300).map((p) => ({ ts: p.ts, onchain: p.sigma }));
  const signals = (history.data?.points ?? []).map((p) => ({ ts: p.ts, ai: p.sigma_ticks }));
  const series = [...realized, ...signals].sort((a, b) => a.ts - b.ts);

  return (
    <div className="space-y-6">
      <PageHeader
        title="AI signal"
        subtitle="Forecast 24h volatility and drift, posted on-chain as a bounded, expiring signal. The hook never trusts it blindly."
        right={<div className="flex gap-2"><RegimeBadge regime={pool?.regime} /><SignalBadge fresh={pool?.signalFresh} /></div>}
      />

      <Card className="grid grid-cols-2 gap-5 sm:grid-cols-4">
        <Stat label="σ used on-chain (24h)" value={tickPct(pool?.sigma)} sub={pool ? `${pool.sigma} ticks · ${pool.signalFresh ? "AI" : "on-chain fallback"}` : undefined} />
        <Stat label="On-chain realized σ" value={tickPct(pool?.onchainSigma)} />
        <Stat label="Forecast drift" value={tickPct(pool?.drift)} />
        <Stat label="Fee now" value={pool ? fmtFeePips(pool.fee) : "—"} sub={pool?.signalFresh ? `confidence ${fmtBps(pool.confidenceBps)}` : undefined} />
      </Card>

      {!AI_API_URL && <Empty>AI API not configured (NEXT_PUBLIC_AI_API_URL). Showing on-chain data only.</Empty>}

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardTitle>Volatility: AI forecast vs on-chain</CardTitle>
          <div className="h-64">
            {series.length < 2 ? (
              <div className="flex h-full items-center justify-center text-sm text-muted">Waiting for data…</div>
            ) : (
              <ResponsiveContainer>
                <LineChart data={series}>
                  <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" />
                  <XAxis dataKey="ts" type="number" domain={["dataMin", "dataMax"]} tickFormatter={(t) => new Date(t * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} stroke="var(--muted)" fontSize={11} />
                  <YAxis stroke="var(--muted)" fontSize={11} tickFormatter={(v) => `${(v / 100).toFixed(1)}%`} />
                  <Tooltip contentStyle={{ background: "var(--card)", border: "1px solid var(--border)" }} labelFormatter={(t) => new Date(Number(t) * 1000).toLocaleString()} formatter={(v, n) => [tickPct(Number(v)), n === "ai" ? "AI forecast" : "On-chain"]} />
                  <Line dataKey="ai" stroke="var(--accent)" dot={false} strokeWidth={2} connectNulls />
                  <Line dataKey="onchain" stroke="var(--range)" dot={false} strokeWidth={1.5} connectNulls />
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>
        </Card>

        <Card>
          <CardTitle right={health.data?.model_version && <span className="num text-xs text-muted">{health.data.model_version}</span>}>Model breakdown</CardTitle>
          {forecast.data ? (
            <table className="num w-full text-sm">
              <thead className="text-left text-xs text-muted"><tr><th className="pb-2">Model</th><th>σ 24h</th><th>Drift</th></tr></thead>
              <tbody>
                {[
                  ["EWMA baseline", forecast.data.models.ewma.sigma_ticks, null],
                  ["Random Forest", forecast.data.models.random_forest.sigma_ticks, forecast.data.models.random_forest.drift_ticks],
                  ["Transformer", forecast.data.models.transformer.sigma_ticks, forecast.data.models.transformer.drift_ticks],
                  ["Ensemble", forecast.data.models.ensemble.sigma_ticks, forecast.data.models.ensemble.drift_ticks],
                ].map(([n, s, d]) => (
                  <tr key={String(n)} className="border-t border-border">
                    <td className="py-2 font-sans">{n}</td>
                    <td>{tickPct(Number(s))}</td>
                    <td>{d == null ? "—" : tickPct(Number(d))}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-muted">{forecast.isError ? "AI engine unreachable." : "Loading…"}</p>
          )}
          {forecast.data && (
            <p className="mt-3 text-xs text-muted">
              Regime {forecast.data.models.ensemble.regime} · confidence {fmtBps(forecast.data.models.ensemble.confidence_bps)} · RF weight {forecast.data.weights?.w_rf ?? "—"} · ETH {fmtUsd(forecast.data.price)}
            </p>
          )}
        </Card>
      </div>

      <Card>
        <CardTitle>Backtest: AI-sized ranges vs fixed</CardTitle>
        {backtest.data ? (
          <div className="space-y-4">
            <div className="overflow-x-auto">
              <table className="num w-full text-sm">
                <thead className="text-left text-xs text-muted">
                  <tr><th className="pb-2">Strategy</th><th>Return</th><th>vs HODL</th><th>Fees</th><th>Rebalance cost</th><th>Rebalances</th></tr>
                </thead>
                <tbody>
                  {backtest.data.backtest.results.map((r) => (
                    <tr key={r.name} className="border-t border-border">
                      <td className="py-2 font-sans">{r.name}</td>
                      <td>{fmtPct(r.return_pct / 100, 2, true)}</td>
                      <td className={r.alpha_vs_hodl_pct >= 0 ? "text-success" : "text-danger"}>{fmtPct(r.alpha_vs_hodl_pct / 100, 2, true)}</td>
                      <td>{fmtUsd(r.fees_usd, 0)}</td>
                      <td>{fmtUsd(r.rebalance_cost_usd, 0)}</td>
                      <td>{r.rebalances}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {backtest.data.metrics && (
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                {Object.entries(backtest.data.metrics.sigma).map(([k, m]) => (
                  <Stat key={k} label={k.replace("_", " ")} value={`${m.mae_ticks.toFixed(0)} ticks MAE`} sub={`regime acc ${fmtPct(m.regime_accuracy, 0)}`} />
                ))}
              </div>
            )}
          </div>
        ) : (
          <p className="text-sm text-muted">{AI_API_URL ? "Loading…" : "Connect the AI API to show the backtest."}</p>
        )}
      </Card>

      <Card>
        <CardTitle>Signal feed</CardTitle>
        {history.data?.points.length ? (
          <ul className="num space-y-2 text-sm">
            {[...history.data.points].reverse().slice(0, 15).map((p) => (
              <li key={p.ts} className="flex flex-wrap justify-between gap-2 border-b border-border pb-2 last:border-0">
                <span className="text-muted">{timeAgo(p.ts)}</span>
                <span>σ {tickPct(p.sigma_ticks)} · drift {tickPct(p.drift_ticks)} · {p.regime_name}</span>
                <span className={p.posted ? "text-accent" : "text-muted"}>{p.posted ? "posted" : p.reason}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-muted">No signals yet.</p>
        )}
      </Card>
    </div>
  );
}
