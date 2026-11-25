"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useAccount, useConfig } from "wagmi";
import { simulateContract, waitForTransactionReceipt, writeContract } from "wagmi/actions";
import { toast } from "sonner";
import { explorerTx } from "@/config/chains";
import { humanError } from "@/lib/errors";

type Request = Parameters<typeof simulateContract>[1];

// simulate → write → wait → toast → refresh reads
export function useTx() {
  const config = useConfig();
  const qc = useQueryClient();
  const { address } = useAccount();
  const [pending, setPending] = useState<string | null>(null);

  async function send(label: string, request: Request): Promise<boolean> {
    if (!address) {
      toast.error("Connect a wallet first.");
      return false;
    }
    setPending(label);
    const id = toast.loading(`${label}…`);
    try {
      const { request: req } = await simulateContract(config, { ...request, account: address } as Request);
      const hash = await writeContract(config, req as Parameters<typeof writeContract>[1]);
      toast.loading(`${label}: waiting for confirmation…`, { id });
      const receipt = await waitForTransactionReceipt(config, { hash });
      if (receipt.status !== "success") throw new Error("Transaction reverted");
      const url = explorerTx(hash);
      toast.success(label, {
        id,
        description: url ? "View on Uniscan" : hash.slice(0, 18),
        action: url ? { label: "Open", onClick: () => window.open(url, "_blank") } : undefined,
      });
      await qc.invalidateQueries();
      return true;
    } catch (e) {
      toast.error(humanError(e), { id });
      return false;
    } finally {
      setPending(null);
    }
  }

  return { send, pending };
}
