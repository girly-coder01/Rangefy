"use client";

import { useMemo, useState } from "react";
import { Area, ComposedChart, Line, ReferenceDot, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Tabs } from "./ui";
import { tickToUsd } from "@/lib/pool";
import { fmtUsd } from "@/lib/format";
import type { PriceSample, RangeSegment } from "@/lib/performance";
import type { RebalanceRow } from "@/hooks/useHistory";
import { REASONS } from "@/hooks/useProtocol";
import { useNow } from "@/hooks/useNow";

const WINDOWS = [
  { value: "1h", label: "1h" },
  { value: "24h", label: "24h" },
  { value: "all", label: "All" },
] as const;
type Win = (typeof WINDOWS)[number]["value"];
const SPAN: Record<Win, number> = { "1h": 3600, "24h": 86_400, all: Infinity };

type Point = { ts: number; price: number; band: [number, number] | null };

export function RangeChart({
  samples,
  ranges,
  rebalances,
  spotTick,
}: {
  samples: PriceSample[];
  ranges: RangeSegment[];
  rebalances: RebalanceRow[];
  spotTick?: number;
}) {
  const [win, setWin] = useState<Win>("24h");
  const now = useNow();

  const data = useMemo<Point[]>(() => {
    const from = now - SPAN[win];
    const pts = [...samples, ...(spotTick != null ? [{ ts: now, tick: spotTick }] : [])]
      .filter((s) => s.ts >= from)
      .sort((a, b) => a.ts - b.ts);
    const segs = [...ranges].sort((a, b) => a.from - b.from);
    return pts.map((s) => {
      const seg = segs.filter((r) => r.from <= s.ts).at(-1);
      const band = seg ? ([tickToUsd(seg.lower), tickToUsd(seg.upper)].sort((a, b) => a - b) as [number, number]) : null;
      return { ts: s.ts, price: tickToUsd(s.tick), band };
    });
  }, [samples, ranges, spotTick, win, now]);

  const markers = rebalances
    .map((r) => ({ ts: r.ts, price: tickToUsd(r.spotTick), reason: REASONS[r.reason] }))
    .filter((m) => data.length && m.ts >= data[0].ts);

  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
          <span className="flex items-center gap-1.5"><span className="h-0.5 w-4 bg-accent" />Pool price</span>
          <span className="flex items-center gap-1.5"><span className="h-3 w-4 rounded-sm bg-range/25" />Vault range</span>
          <span className="flex items-center gap-1.5"><span className="h-2 w-2 rotate-45 bg-foreground" />Rebalance</span>
        </div>
        <Tabs value={win} options={WINDOWS} onChange={setWin} />
      </div>
      <div className="h-72">
        {data.length < 2 ? (
          <div className="flex h-full items-center justify-center text-sm text-muted">Waiting for swaps…</div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
              <XAxis
                dataKey="ts"
                type="number"
                domain={["dataMin", "dataMax"]}
                tickFormatter={(t) => new Date(t * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                stroke="var(--muted)"
                fontSize={11}
              />
              <YAxis domain={["auto", "auto"]} tickFormatter={(v) => fmtUsd(v, 0)} stroke="var(--muted)" fontSize={11} width={70} />
              <Tooltip
                contentStyle={{ background: "var(--card)", border: "1px solid var(--border)", borderRadius: 8 }}
                labelFormatter={(t) => new Date(Number(t) * 1000).toLocaleString()}
                formatter={(v, name) =>
                  Array.isArray(v) ? [`${fmtUsd(v[0], 0)} – ${fmtUsd(v[1], 0)}`, "Range"] : [fmtUsd(Number(v)), name === "price" ? "Price" : String(name)]
                }
              />
              <Area dataKey="band" type="stepAfter" stroke="var(--range)" fill="var(--range)" fillOpacity={0.18} isAnimationActive animationDuration={400} />
              <Line dataKey="price" type="monotone" stroke="var(--accent)" strokeWidth={2} dot={false} isAnimationActive={false} />
              {markers.map((m) => (
                <ReferenceDot key={m.ts} x={m.ts} y={m.price} r={4} fill="var(--foreground)" stroke="none" />
              ))}
            </ComposedChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
