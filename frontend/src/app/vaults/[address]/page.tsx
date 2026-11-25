"use client";

import { useMemo } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useAccount, useReadContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { ArrowLeft, ExternalLink } from "lucide-react";
import { Button, Card, CardTitle, Empty, Skeleton, Stat } from "@/components/ui";
import { RangeBadge, RegimeBadge, SignalBadge } from "@/components/badges";
import { RangeChart } from "@/components/RangeChart";
import { DepositWithdraw } from "@/components/DepositWithdraw";
import { REASONS, REFRESH_MS, usePool, useVault } from "@/hooks/useProtocol";
import { usePoolHistory, useVaultHistory } from "@/hooks/useHistory";
import { useTx } from "@/hooks/useTx";
import { useNow } from "@/hooks/useNow";
import { RangeVaultAbi } from "@/config/abis";
import { explorerAddress, explorerTx } from "@/config/chains";
import { feeApr, returns, timeInRange, tvlUsd } from "@/lib/performance";
import { rangeUsd, toWethUsdc, usdValue } from "@/lib/pool";
import { fmtBps, fmtDuration, fmtPct, fmtToken, fmtUsd, shortAddr, timeAgo } from "@/lib/format";
import { profileName } from "@/lib/strategy";

export default function VaultPage() {
  const { address: raw } = useParams<{ address: string }>();
  const address = isAddress(raw) ? (raw as Address) : undefined;
  const { data: v, isLoading } = useVault(address);
  const { pool, ethUsd } = usePool();
  const poolHistory = usePoolHistory();
  const history = useVaultHistory(address, v ? { tickLower: v.tickLower, tickUpper: v.tickUpper } : undefined);
  const { address: user } = useAccount();
  const { send, pending } = useTx();
  const now = useNow();

  const target = useReadContract({
    address,
    abi: RangeVaultAbi,
    functionName: "targetRange",
    query: { enabled: !!address && !!v, refetchInterval: REFRESH_MS },
  });
  const mine = useReadContract({
    address,
    abi: RangeVaultAbi,
    functionName: "balanceOf",
    args: [user as Address],
    query: { enabled: !!address && !!user, refetchInterval: REFRESH_MS },
  });
  const myPreview = useReadContract({
    address,
    abi: RangeVaultAbi,
    functionName: "previewWithdraw",
    args: [mine.data ?? 0n],
    query: { enabled: !!mine.data, refetchInterval: REFRESH_MS },
  });

  const stats = useMemo(() => {
    if (!v || !ethUsd) return null;
    const h = history.data;
    const r = h ? returns(h.snapshots) : null;
    return {
      tvl: tvlUsd(v.total0, v.total1, ethUsd),
      alpha: r?.alpha,
      vaultReturn: r?.vaultReturn,
      apr: h ? feeApr(h.fees, h.snapshots, ethUsd) : undefined,
      inRange: h && poolHistory.data ? timeInRange(poolHistory.data, h.ranges, now) : undefined,
    };
  }, [v, ethUsd, history.data, poolHistory.data, now]);

  if (!address) return <Empty>Invalid vault address.</Empty>;
  if (isLoading || !v) return <Skeleton className="h-96" />;

  const [lo, hi] = rangeUsd(v.tickLower, v.tickUpper);
  const [tLo, tHi] = target.data ? rangeUsd(target.data[0], target.data[1]) : [undefined, undefined];
  const p = v.params;
  const myAmounts = myPreview.data ? toWethUsdc(myPreview.data[0], myPreview.data[1]) : null;
  const cooldownLeft = Number(v.lastRebalance) + p.minRebalanceInterval - now;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link href="/vaults" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-foreground">
            <ArrowLeft size={14} /> Vaults
          </Link>
          <h1 className="text-2xl font-bold">{v.name}</h1>
          <div className="text-sm text-muted">
            <Link href={`/curators/${v.curator}`} className="hover:text-foreground">{v.curatorName}</Link> · {profileName(p)} · mWETH/mUSDC
            {explorerAddress(v.vault) && (
              <a href={explorerAddress(v.vault)} target="_blank" rel="noreferrer" className="ml-2 inline-flex items-center gap-1 hover:text-foreground">
                {shortAddr(v.vault)} <ExternalLink size={12} />
              </a>
            )}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <RangeBadge inRange={v.inRange} liquidity={v.liquidity} />
          <RegimeBadge regime={pool?.regime} />
          <SignalBadge fresh={pool?.signalFresh} />
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
        <div className="min-w-0 space-y-6">
          <Card>
            <RangeChart
              samples={poolHistory.data ?? []}
              ranges={history.data?.ranges ?? []}
              rebalances={history.data?.rebalances ?? []}
              spotTick={pool?.tick}
            />
          </Card>

          <Card className="grid grid-cols-2 gap-5 sm:grid-cols-3">
            <Stat label="TVL" value={fmtUsd(stats?.tvl)} />
            <Stat label="Alpha vs HODL" value={fmtPct(stats?.alpha, 2, true)} />
            <Stat label="Fee APR" value={fmtPct(stats?.apr, 1)} />
            <Stat label="Share price change" value={fmtPct(stats?.vaultReturn, 2, true)} />
            <Stat label="Time in range" value={fmtPct(stats?.inRange, 0)} />
            <Stat label="Rebalances" value={Number(v.rebalanceCount)} />
          </Card>

          <Card>
            <CardTitle
              right={
                <Button
                  variant="secondary"
                  disabled={!v.needsRebalance}
                  loading={pending === "Rebalance"}
                  onClick={() => send("Rebalance", { address: v.vault, abi: RangeVaultAbi, functionName: "rebalance" })}
                  title={v.needsRebalance ? REASONS[v.reason] : "Nothing to do"}
                >
                  {v.needsRebalance ? `Rebalance now · ${REASONS[v.reason]}` : "No rebalance needed"}
                </Button>
              }
            >
              Rebalance history
            </CardTitle>
            {history.data?.rebalances.length ? (
              <div className="overflow-x-auto">
                <table className="num w-full text-sm">
                  <thead className="text-left text-xs text-muted">
                    <tr><th className="pb-2">When</th><th>Reason</th><th>Old range</th><th>New range</th><th>σ</th><th /></tr>
                  </thead>
                  <tbody>
                    {[...history.data.rebalances].reverse().map((r) => {
                      const [ol, oh] = rangeUsd(r.oldLower, r.oldUpper);
                      const [nl, nh] = rangeUsd(r.newLower, r.newUpper);
                      return (
                        <tr key={r.tx} className="border-t border-border">
                          <td className="py-2">{timeAgo(r.ts)}</td>
                          <td>{REASONS[r.reason]}</td>
                          <td>{r.oldLower < r.oldUpper ? `${fmtUsd(ol, 0)}–${fmtUsd(oh, 0)}` : "—"}</td>
                          <td>{fmtUsd(nl, 0)}–{fmtUsd(nh, 0)}</td>
                          <td>{r.sigma}{r.fromSignal ? " AI" : ""}</td>
                          <td className="text-right">
                            {explorerTx(r.tx) && <a href={explorerTx(r.tx)} target="_blank" rel="noreferrer" className="text-muted hover:text-foreground"><ExternalLink size={12} /></a>}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            ) : (
              <p className="text-sm text-muted">No rebalances yet. The keeper rebalances automatically when the rules allow it; anyone can press the button too.</p>
            )}
          </Card>
        </div>

        <div className="space-y-6">
          <DepositWithdraw v={v} ethUsd={ethUsd} />

          {myAmounts && mine.data ? (
            <Card>
              <CardTitle>Your position</CardTitle>
              <div className="num text-sm">
                {fmtToken(myAmounts.weth, 18)} mWETH + {fmtToken(myAmounts.usdc, 6, 2)} mUSDC
              </div>
              <div className="num mt-1 text-lg font-semibold">{ethUsd ? fmtUsd(usdValue(myAmounts.weth, myAmounts.usdc, ethUsd)) : "—"}</div>
            </Card>
          ) : null}

          <Card>
            <CardTitle>Strategy</CardTitle>
            <dl className="num grid grid-cols-2 gap-y-2 text-sm">
              <dt className="text-muted">Width</dt><dd>{(p.widthMultiplierBps / 10_000).toFixed(1)}σ</dd>
              <dt className="text-muted">Half-width bounds</dt><dd>{p.minHalfWidth}–{p.maxHalfWidth} ticks</dd>
              <dt className="text-muted">Drift weight</dt><dd>{fmtBps(p.driftWeightBps)}</dd>
              <dt className="text-muted">Cooldown</dt><dd>{fmtDuration(p.minRebalanceInterval)}{cooldownLeft > 0 ? ` (${fmtDuration(cooldownLeft)} left)` : ""}</dd>
              <dt className="text-muted">EMA guard</dt><dd>±{p.maxEmaDeviation} ticks</dd>
              <dt className="text-muted">Performance fee</dt><dd>{fmtBps(p.performanceFeeBps)}</dd>
              <dt className="text-muted">Current range</dt><dd>{v.liquidity > 0n ? `${fmtUsd(lo, 0)}–${fmtUsd(hi, 0)}` : "—"}</dd>
              <dt className="text-muted">Next target</dt><dd>{tLo ? `${fmtUsd(tLo, 0)}–${fmtUsd(tHi, 0)}` : "—"}</dd>
              <dt className="text-muted">Sized by</dt><dd>{target.data ? `σ ${target.data[2]} · ${target.data[3] ? "AI signal" : "on-chain"}` : "—"}</dd>
            </dl>
          </Card>
        </div>
      </div>
    </div>
  );
}
