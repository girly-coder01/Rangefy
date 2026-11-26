"use client";

import Link from "next/link";
import { useAccount, useChainId, useSwitchChain } from "wagmi";
import { isDeployed } from "@/config/addresses";
import { activeChain } from "@/config/chains";
import { usePool } from "@/hooks/useProtocol";
import { useLiveEvents } from "@/hooks/useLiveEvents";

export function Banners() {
  useLiveEvents();
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const { pool } = usePool();

  if (!isDeployed) {
    return <Bar tone="warning">Contracts are not deployed on {activeChain.name} yet. Run the deploy scripts and sync addresses.</Bar>;
  }
  if (isConnected && chainId !== activeChain.id) {
    return (
      <Bar tone="warning">
        Wrong network.{" "}
        <button className="font-semibold underline" onClick={() => switchChain({ chainId: activeChain.id })}>
          Switch to {activeChain.name}
        </button>
      </Bar>
    );
  }
  if (pool && !pool.signalFresh) {
    return (
      <Bar tone="neutral">
        AI signal paused (stale). Ranges and fees use the hook&apos;s on-chain volatility.{" "}
        <Link href="/ai" className="underline">Details</Link>
      </Bar>
    );
  }
  return null;
}

function Bar({ tone, children }: { tone: "warning" | "neutral"; children: React.ReactNode }) {
  const cls = tone === "warning" ? "bg-warning/15 text-warning" : "bg-border/40 text-muted";
  return <div className={`px-4 py-2 text-center text-sm ${cls}`}>{children}</div>;
}
