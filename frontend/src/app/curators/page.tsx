"use client";

import { useState } from "react";
import Link from "next/link";
import { Card, Empty, PageHeader, Skeleton } from "@/components/ui";
import { useRankedVaults } from "@/hooks/useLeaderboard";
import { fmtPct, fmtUsd } from "@/lib/format";
import { profileName } from "@/lib/strategy";

const COLS = [
  { key: "alpha", label: "Alpha vs HODL" },
  { key: "feeApr", label: "Fee APR" },
  { key: "tvl", label: "TVL" },
  { key: "timeInRange", label: "In range" },
  { key: "rebalances", label: "Rebalances" },
] as const;
type Col = (typeof COLS)[number]["key"];

export default function LeaderboardPage() {
  const { ranked, isLoading } = useRankedVaults();
  const [sort, setSort] = useState<Col>("alpha");

  const val = (r: (typeof ranked)[number], c: Col) =>
    c === "tvl" ? r.tvl : c === "rebalances" ? Number(r.v.rebalanceCount) : r.perf[c];
  const rows = [...ranked].sort((a, b) => val(b, sort) - val(a, sort));

  return (
    <div>
      <PageHeader title="Curator leaderboard" subtitle="Ranked by share-price growth versus simply holding the deposited tokens." />
      {isLoading ? (
        <Skeleton className="h-64" />
      ) : !rows.length ? (
        <Empty>No vaults yet.</Empty>
      ) : (
        <Card className="overflow-x-auto p-0">
          <table className="num w-full text-sm">
            <thead className="border-b border-border text-left text-xs text-muted">
              <tr>
                <th className="p-4">#</th>
                <th>Vault</th>
                {COLS.map((c) => (
                  <th key={c.key} className="cursor-pointer whitespace-nowrap pr-4" onClick={() => setSort(c.key)} aria-sort={sort === c.key ? "descending" : "none"}>
                    {c.label}{sort === c.key ? " ↓" : ""}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={r.v.vault} className="border-b border-border last:border-0 hover:bg-background/50">
                  <td className="p-4 text-muted">{i + 1}</td>
                  <td className="py-3 pr-4 font-sans">
                    <Link href={`/vaults/${r.v.vault}`} className="font-semibold hover:text-accent">{r.v.name}</Link>
                    <div className="text-xs text-muted">
                      <Link href={`/curators/${r.v.curator}`} className="hover:text-foreground">{r.v.curatorName}</Link> · {profileName(r.v.params)}
                    </div>
                  </td>
                  <td className={`pr-4 ${r.perf.alpha >= 0 ? "text-success" : "text-danger"}`}>{fmtPct(r.perf.alpha, 2, true)}</td>
                  <td className="pr-4">{fmtPct(r.perf.feeApr, 1)}</td>
                  <td className="pr-4">{fmtUsd(r.tvl)}</td>
                  <td className="pr-4">{fmtPct(r.perf.timeInRange, 0)}</td>
                  <td className="pr-4">{Number(r.v.rebalanceCount)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </div>
  );
}
