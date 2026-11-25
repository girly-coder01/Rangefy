"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useWatchContractEvent } from "wagmi";
import { toast } from "sonner";
import { addresses, isDeployed } from "@/config/addresses";
import { RangefyHookAbi, SignalOracleAbi, VaultFactoryAbi } from "@/config/abis";

// Refresh on-chain reads as soon as something relevant happens.
export function useLiveEvents() {
  const qc = useQueryClient();
  const refresh = () => qc.invalidateQueries({ predicate: (q) => q.queryKey[0] !== "ai" });

  useWatchContractEvent({
    address: addresses.hook,
    abi: RangefyHookAbi,
    eventName: "PoolStateUpdated",
    enabled: isDeployed,
    onLogs: refresh,
  });
  useWatchContractEvent({
    address: addresses.signalOracle,
    abi: SignalOracleAbi,
    eventName: "SignalPosted",
    enabled: isDeployed,
    onLogs: () => {
      refresh();
      toast("New AI volatility signal posted on-chain");
    },
  });
  useWatchContractEvent({
    address: addresses.vaultFactory,
    abi: VaultFactoryAbi,
    eventName: "VaultCreated",
    enabled: isDeployed,
    onLogs: (logs) => {
      refresh();
      for (const l of logs) toast.success(`New vault: ${l.args.name}`);
    },
  });
}
