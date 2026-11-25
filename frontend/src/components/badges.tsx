import { Badge } from "./ui";
import { REGIMES } from "@/hooks/useProtocol";

const REGIME_STYLE = ["text-regime-calm border-regime-calm/40 bg-regime-calm/10", "text-regime-normal border-regime-normal/40 bg-regime-normal/10", "text-regime-high border-regime-high/40 bg-regime-high/10", "text-regime-extreme border-regime-extreme/40 bg-regime-extreme/10"];

export function RegimeBadge({ regime }: { regime?: number }) {
  if (regime == null) return <Badge>Regime —</Badge>;
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium ${REGIME_STYLE[regime]}`}>
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {REGIMES[regime]}
    </span>
  );
}

export function RangeBadge({ inRange, liquidity }: { inRange: boolean; liquidity: bigint }) {
  if (liquidity === 0n) return <Badge tone="warning">Awaiting deposit</Badge>;
  return inRange ? (
    <Badge tone="range">
      <span className="h-1.5 w-1.5 rounded-full bg-current" /> In range
    </Badge>
  ) : (
    <Badge tone="danger">Out of range</Badge>
  );
}

export function SignalBadge({ fresh }: { fresh?: boolean }) {
  if (fresh == null) return null;
  return fresh ? <Badge tone="accent">AI signal live</Badge> : <Badge tone="warning">Signal stale · on-chain fallback</Badge>;
}
