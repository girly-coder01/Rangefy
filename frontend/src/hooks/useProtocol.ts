"use client";

import { useReadContract } from "wagmi";
import type { Address } from "viem";
import { addresses, isDeployed, pool } from "@/config/addresses";
import { RangefyLensAbi } from "@/config/abis";
import { sqrtToUsd } from "@/lib/pool";

export const REFRESH_MS = 4000;
export const REGIMES = ["Calm", "Normal", "High", "Extreme"] as const;
export const REASONS = ["None", "Out of range", "Near edge", "Width drift", "Initial", "Idle capital"] as const;

export function usePool() {
  const q = useReadContract({
    address: addresses.lens,
    abi: RangefyLensAbi,
    functionName: "getPool",
    args: [pool.key],
    query: { enabled: isDeployed, refetchInterval: REFRESH_MS },
  });
  const p = q.data;
  return {
    ...q,
    pool: p,
    ethUsd: p ? sqrtToUsd(p.sqrtPriceX96) : undefined,
    regime: p ? REGIMES[p.regime] : undefined,
  };
}

export function useVaults() {
  return useReadContract({
    address: addresses.lens,
    abi: RangefyLensAbi,
    functionName: "getAllVaults",
    query: { enabled: isDeployed, refetchInterval: REFRESH_MS },
  });
}

export function useVault(vault?: Address) {
  return useReadContract({
    address: addresses.lens,
    abi: RangefyLensAbi,
    functionName: "getVault",
    args: vault ? [vault] : undefined,
    query: { enabled: isDeployed && !!vault, refetchInterval: REFRESH_MS },
  });
}

export function useUserPositions(user?: Address) {
  return useReadContract({
    address: addresses.lens,
    abi: RangefyLensAbi,
    functionName: "getUserPositions",
    args: user ? [user] : undefined,
    query: { enabled: isDeployed && !!user, refetchInterval: REFRESH_MS },
  });
}

export type VaultView = NonNullable<ReturnType<typeof useVault>["data"]>;
export type PoolView = NonNullable<ReturnType<typeof usePool>["pool"]>;
