"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Card, Empty, PageHeader, Stat } from "@/components/ui";
import { usePool, useUserPositions } from "@/hooks/useProtocol";
import { useRankedVaults } from "@/hooks/useLeaderboard";
import { toWethUsdc, usdValue } from "@/lib/pool";
import { fmtPct, fmtToken, fmtUsd } from "@/lib/format";

export default function PortfolioPage() {
  const { address } = useAccount();
  const { ethUsd } = usePool();
  const { data } = useUserPositions(address);
  const { ranked } = useRankedVaults();

  if (!address) {
    return (
      <div>
        <PageHeader title="Portfolio" />
        <Card className="flex flex-col items-center gap-3 py-10 text-muted">Connect a wallet to see your positions.<ConnectButton /></Card>
      </div>
    );
  }

  const [vaults = [], , a0 = [], a1 = []] = data ?? [];
  const rows = vaults.map((v, i) => {
    const { weth, usdc } = toWethUsdc(a0[i], a1[i]);
    const r = ranked.find((x) => x.v.vault === v);
    return { vault: v, name: r?.v.name ?? v, weth, usdc, usd: ethUsd ? usdValue(weth, usdc, ethUsd) : 0, alpha: r?.perf.alpha };
  });
  const total = rows.reduce((a, r) => a + r.usd, 0);

  return (
    <div className="space-y-6">
      <PageHeader title="Portfolio" />
      <Card className="grid grid-cols-2 gap-5">
        <Stat label="Total value" value={fmtUsd(total)} />
        <Stat label="Positions" value={rows.length} />
      </Card>
      {rows.length ? (
        <Card className="overflow-x-auto p-0">
          <table className="num w-full text-sm">
            <thead className="border-b border-border text-left text-xs text-muted">
              <tr><th className="p-4">Vault</th><th>mWETH</th><th>mUSDC</th><th>Value</th><th className="pr-4">Vault alpha</th></tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.vault} className="border-b border-border last:border-0">
                  <td className="p-4 font-sans"><Link href={`/vaults/${r.vault}`} className="font-semibold hover:text-accent">{r.name}</Link></td>
                  <td>{fmtToken(r.weth, 18)}</td>
                  <td>{fmtToken(r.usdc, 6, 2)}</td>
                  <td>{fmtUsd(r.usd)}</td>
                  <td className="pr-4">{fmtPct(r.alpha, 2, true)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      ) : (
        <Empty>No positions yet. <Link href="/vaults" className="text-accent">Browse vaults</Link></Empty>
      )}
    </div>
  );
}
