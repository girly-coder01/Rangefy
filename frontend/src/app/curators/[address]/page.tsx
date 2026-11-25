"use client";

import { useParams } from "next/navigation";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { isAddress, type Address } from "viem";
import { Button, Card, CardTitle, Empty, PageHeader, Stat } from "@/components/ui";
import { VaultCard } from "@/components/VaultCard";
import { addresses, isDeployed, tokens } from "@/config/addresses";
import { CuratorRegistryAbi, RangeVaultAbi } from "@/config/abis";
import { useRankedVaults } from "@/hooks/useLeaderboard";
import { usePool } from "@/hooks/useProtocol";
import { useTx } from "@/hooks/useTx";
import { toWethUsdc, usdValue } from "@/lib/pool";
import { fmtPct, fmtToken, fmtUsd, shortAddr } from "@/lib/format";

function bioOf(uri?: string) {
  if (!uri?.startsWith("data:application/json,")) return "";
  try {
    return JSON.parse(decodeURIComponent(uri.slice(22))).bio ?? "";
  } catch {
    return "";
  }
}

export default function CuratorPage() {
  const { address: raw } = useParams<{ address: string }>();
  const curator = isAddress(raw) ? (raw as Address) : undefined;
  const { address: me } = useAccount();
  const { ethUsd } = usePool();
  const { ranked } = useRankedVaults();
  const { send, pending } = useTx();

  const info = useReadContract({
    address: addresses.curatorRegistry,
    abi: CuratorRegistryAbi,
    functionName: "getCurator",
    args: [curator!],
    query: { enabled: isDeployed && !!curator },
  });

  const mine = ranked.filter((r) => r.v.curator.toLowerCase() === curator?.toLowerCase());
  const owed = useReadContracts({
    contracts: mine.flatMap((r) => [
      { address: r.v.vault, abi: RangeVaultAbi, functionName: "curatorOwed0" },
      { address: r.v.vault, abi: RangeVaultAbi, functionName: "curatorOwed1" },
    ]),
    query: { enabled: mine.length > 0, refetchInterval: 10_000 },
  });

  if (!curator) return <Empty>Invalid address.</Empty>;
  const tvl = mine.reduce((a, r) => a + r.tvl, 0);
  const avgAlpha = mine.length ? mine.reduce((a, r) => a + r.perf.alpha, 0) / mine.length : undefined;
  const isMe = me?.toLowerCase() === curator.toLowerCase();

  return (
    <div className="space-y-6">
      <PageHeader title={info.data?.name || shortAddr(curator)} subtitle={bioOf(info.data?.metadataURI) || shortAddr(curator)} />
      <Card className="grid grid-cols-3 gap-5">
        <Stat label="Vaults" value={mine.length} />
        <Stat label="Combined TVL" value={fmtUsd(tvl)} />
        <Stat label="Average alpha" value={fmtPct(avgAlpha, 2, true)} />
      </Card>
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {mine.map((r) => <VaultCard key={r.v.vault} v={r.v} tvl={r.tvl} perf={r.perf} />)}
      </div>
      {mine.length > 0 && (
        <Card>
          <CardTitle>Curator fees</CardTitle>
          <div className="space-y-3">
            {mine.map((r, i) => {
              const o0 = (owed.data?.[2 * i]?.result as bigint | undefined) ?? 0n;
              const o1 = (owed.data?.[2 * i + 1]?.result as bigint | undefined) ?? 0n;
              const { weth, usdc } = toWethUsdc(o0, o1);
              return (
                <div key={r.v.vault} className="flex flex-wrap items-center justify-between gap-3 text-sm">
                  <span>{r.v.name}</span>
                  <span className="num text-muted">
                    {fmtToken(weth, tokens.mWETH.decimals)} mWETH + {fmtToken(usdc, tokens.mUSDC.decimals, 2)} mUSDC
                    {ethUsd ? ` · ${fmtUsd(usdValue(weth, usdc, ethUsd))}` : ""}
                  </span>
                  {isMe && (
                    <Button
                      variant="secondary"
                      disabled={o0 === 0n && o1 === 0n}
                      loading={pending === `Claim ${r.v.symbol}`}
                      onClick={() => send(`Claim ${r.v.symbol}`, { address: r.v.vault, abi: RangeVaultAbi, functionName: "claimCuratorFees", args: [curator] })}
                    >
                      Claim
                    </Button>
                  )}
                </div>
              );
            })}
          </div>
        </Card>
      )}
    </div>
  );
}
