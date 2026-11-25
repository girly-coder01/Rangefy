import Link from "next/link";
import { Card, Stat } from "./ui";
import { RangeBadge } from "./badges";
import type { VaultView } from "@/hooks/useProtocol";
import type { Performance } from "@/lib/performance";
import { fmtBps, fmtPct, fmtUsd } from "@/lib/format";
import { rangeUsd } from "@/lib/pool";
import { profileName } from "@/lib/strategy";

export function VaultCard({ v, tvl, perf }: { v: VaultView; tvl?: number; perf?: Partial<Performance> }) {
  const [lo, hi] = rangeUsd(v.tickLower, v.tickUpper);
  return (
    <Link href={`/vaults/${v.vault}`} className="block focus-visible:outline-none">
      <Card className="h-full transition-colors hover:border-accent/50">
        <div className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="truncate font-semibold">{v.name}</div>
            <div className="text-sm text-muted">
              {v.curatorName} · {profileName(v.params)}
            </div>
          </div>
          <RangeBadge inRange={v.inRange} liquidity={v.liquidity} />
        </div>
        <div className="grid grid-cols-3 gap-3">
          <Stat label="TVL" value={fmtUsd(tvl)} />
          <Stat label="Alpha vs HODL" value={fmtPct(perf?.alpha, 2, true)} />
          <Stat label="Fee APR" value={fmtPct(perf?.feeApr, 1)} />
        </div>
        <div className="mt-4 flex justify-between text-xs text-muted">
          <span className="num">
            {v.liquidity > 0n ? `${fmtUsd(lo, 0)} – ${fmtUsd(hi, 0)}` : "No position yet"}
          </span>
          <span>
            {Number(v.rebalanceCount)} rebalances · {fmtBps(v.params.performanceFeeBps)} fee
          </span>
        </div>
      </Card>
    </Link>
  );
}
