"use client";

import Link from "next/link";
import { ArrowRight, Brain, Gauge, ShieldCheck } from "lucide-react";
import { Button, Card, Stat } from "@/components/ui";
import { RegimeBadge, SignalBadge } from "@/components/badges";
import { VaultCard } from "@/components/VaultCard";
import { usePool } from "@/hooks/useProtocol";
import { useRankedVaults } from "@/hooks/useLeaderboard";
import { useMirror } from "@/hooks/useAI";
import { fmtFeePips, fmtUsd } from "@/lib/format";

export default function Home() {
  const { pool, ethUsd } = usePool();
  const { ranked } = useRankedVaults();
  const mirror = useMirror();
  const tvl = ranked.reduce((a, r) => a + r.tvl, 0);
  const curators = new Set(ranked.map((r) => r.v.curator)).size;
  const top = [...ranked].sort((a, b) => b.perf.alpha - a.perf.alpha).slice(0, 3);

  return (
    <div className="space-y-12">
      <section className="flex flex-col items-start gap-6 pt-8">
        <div className="flex flex-wrap gap-2">
          <RegimeBadge regime={pool?.regime} />
          <SignalBadge fresh={pool?.signalFresh} />
        </div>
        <h1 className="max-w-3xl text-4xl font-bold tracking-tight sm:text-5xl">
          Liquidity that stays in <span className="text-range">range</span>.
        </h1>
        <p className="max-w-2xl text-lg text-muted">
          Curators define the strategy. An AI volatility model sizes the range. A Uniswap v4 hook prices risk and
          guards every rebalance on-chain.
        </p>
        <div className="flex flex-wrap gap-3">
          <Link href="/vaults"><Button>Explore vaults <ArrowRight size={16} /></Button></Link>
          <Link href="/faucet"><Button variant="secondary">Get test tokens</Button></Link>
        </div>
      </section>

      <Card className="grid grid-cols-2 gap-6 sm:grid-cols-3 lg:grid-cols-6">
        <Stat label="Total value locked" value={fmtUsd(tvl)} />
        <Stat label="Vaults" value={ranked.length} />
        <Stat label="Curators" value={curators} />
        <Stat label="Swap fee now" value={pool ? fmtFeePips(pool.fee) : "—"} />
        <Stat label="Testnet ETH" value={fmtUsd(ethUsd)} />
        <Stat label="Real ETH" value={fmtUsd(mirror.data?.real_price)} sub={mirror.data ? `${mirror.data.deviation_bps.toFixed(0)} bps apart` : "mirror offline"} />
      </Card>

      <section className="grid gap-4 md:grid-cols-3">
        {[
          { icon: Brain, title: "AI sizes the range", body: "A Transformer + Random Forest ensemble forecasts 24h volatility and posts it on-chain. Ranges widen before storms and tighten in calm markets." },
          { icon: Gauge, title: "Hook prices the risk", body: "The hook tracks an EMA price and realized volatility on every swap and charges a higher fee when the market is dangerous for LPs." },
          { icon: ShieldCheck, title: "Rules, not trust", body: "Vaults compute every range on-chain. Anyone can trigger a rebalance, and curators can never touch LP funds." },
        ].map(({ icon: Icon, title, body }) => (
          <Card key={title}>
            <Icon className="mb-3 text-accent" size={22} />
            <h3 className="font-semibold">{title}</h3>
            <p className="mt-2 text-sm text-muted">{body}</p>
          </Card>
        ))}
      </section>

      <section>
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-xl font-bold">Top vaults</h2>
          <Link href="/curators" className="text-sm text-muted hover:text-foreground">Leaderboard →</Link>
        </div>
        <div className="grid gap-4 md:grid-cols-3">
          {top.map((r) => (
            <VaultCard key={r.v.vault} v={r.v} tvl={r.tvl} perf={r.perf} />
          ))}
        </div>
      </section>
    </div>
  );
}
