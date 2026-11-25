"use client";

import { useMemo } from "react";
import type { Address } from "viem";
import { usePool, useVaults, type VaultView } from "./useProtocol";
import { useAllVaultHistories, usePoolHistory } from "./useHistory";
import { useNow } from "./useNow";
import { feeApr, returns, timeInRange, tvlUsd, type Performance } from "@/lib/performance";

export type Ranked = { v: VaultView; tvl: number; perf: Performance };

export function useRankedVaults() {
  const vaults = useVaults();
  const { ethUsd } = usePool();
  const list = vaults.data;
  const histories = useAllVaultHistories(list);
  const poolHistory = usePoolHistory();
  const now = useNow();

  const ranked = useMemo<Ranked[]>(() => {
    if (!list || !ethUsd) return [];
    return list.map((v) => {
      const tvl = tvlUsd(v.total0, v.total1, ethUsd);
      const h = histories.data?.[v.vault as Address];
      const r = h ? returns(h.snapshots) : { vaultReturn: 0, hodlReturn: 0, alpha: 0 };
      return {
        v,
        tvl,
        perf: {
          ...r,
          feeApr: h ? feeApr(h.fees, h.snapshots, ethUsd) : 0,
          timeInRange: h && poolHistory.data ? timeInRange(poolHistory.data, h.ranges, now) : v.inRange ? 1 : 0,
          tvlUsd: tvl,
        },
      };
    });
  }, [list, ethUsd, histories.data, poolHistory.data, now]);

  return { ranked, isLoading: vaults.isLoading, ethUsd, histories: histories.data };
}
