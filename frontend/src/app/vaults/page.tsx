"use client";

import { useState } from "react";
import Link from "next/link";
import { Button, Empty, PageHeader, Skeleton, Tabs } from "@/components/ui";
import { VaultCard } from "@/components/VaultCard";
import { useRankedVaults } from "@/hooks/useLeaderboard";
import { profileName } from "@/lib/strategy";

const PROFILES = ["All", "Aggressive", "Balanced", "Conservative", "Custom"] as const;
const SORTS = [
  { value: "alpha", label: "Alpha" },
  { value: "tvl", label: "TVL" },
  { value: "apr", label: "Fee APR" },
] as const;

export default function VaultsPage() {
  const { ranked, isLoading } = useRankedVaults();
  const [profile, setProfile] = useState<(typeof PROFILES)[number]>("All");
  const [sort, setSort] = useState<(typeof SORTS)[number]["value"]>("tvl");

  const list = ranked
    .filter((r) => profile === "All" || profileName(r.v.params) === profile)
    .sort((a, b) => (sort === "tvl" ? b.tvl - a.tvl : sort === "apr" ? b.perf.feeApr - a.perf.feeApr : b.perf.alpha - a.perf.alpha));

  return (
    <div>
      <PageHeader
        title="Vaults"
        subtitle="Pick a curator's strategy, deposit both tokens, earn fees while the vault keeps your range current."
        right={<Link href="/curate"><Button variant="secondary">Launch a vault</Button></Link>}
      />
      <div className="mb-6 flex flex-wrap items-center gap-3">
        <div className="flex flex-wrap gap-1">
          {PROFILES.map((p) => (
            <button
              key={p}
              onClick={() => setProfile(p)}
              className={`rounded-full border px-3 py-1 text-sm ${profile === p ? "border-accent text-accent" : "border-border text-muted"}`}
            >
              {p}
            </button>
          ))}
        </div>
        <div className="ml-auto flex items-center gap-2 text-sm text-muted">
          Sort <Tabs value={sort} options={SORTS} onChange={setSort} />
        </div>
      </div>
      {isLoading ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {[0, 1, 2].map((i) => <Skeleton key={i} className="h-44" />)}
        </div>
      ) : list.length ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {list.map((r) => <VaultCard key={r.v.vault} v={r.v} tvl={r.tvl} perf={r.perf} />)}
        </div>
      ) : (
        <Empty>No vaults match.</Empty>
      )}
    </div>
  );
}
