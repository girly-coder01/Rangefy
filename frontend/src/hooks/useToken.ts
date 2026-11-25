"use client";

import { useAccount, useReadContracts } from "wagmi";
import { maxUint256, type Address } from "viem";
import { tokens } from "@/config/addresses";
import { MockERC20Abi } from "@/config/abis";
import { REFRESH_MS } from "./useProtocol";
import { useTx } from "./useTx";

// Balances of both tokens plus allowances to `spender`.
export function useTokens(spender?: Address) {
  const { address } = useAccount();
  const list = [tokens.mWETH, tokens.mUSDC];
  const q = useReadContracts({
    contracts: list.flatMap((t) => [
      { address: t.address, abi: MockERC20Abi, functionName: "balanceOf", args: [address!] },
      { address: t.address, abi: MockERC20Abi, functionName: "allowance", args: [address!, spender!] },
      { address: t.address, abi: MockERC20Abi, functionName: "faucetAvailableIn", args: [address!] },
    ]),
    query: { enabled: !!address, refetchInterval: REFRESH_MS },
  });
  const r = (i: number) => (q.data?.[i]?.result as bigint | undefined) ?? 0n;
  return {
    ...q,
    weth: { balance: r(0), allowance: spender ? r(1) : 0n, faucetIn: Number(r(2)) },
    usdc: { balance: r(3), allowance: spender ? r(4) : 0n, faucetIn: Number(r(5)) },
  };
}

export function useApprove() {
  const { send, pending } = useTx();
  const approve = (token: { address: Address; symbol: string }, spender: Address) =>
    send(`Approve ${token.symbol}`, {
      address: token.address,
      abi: MockERC20Abi,
      functionName: "approve",
      args: [spender, maxUint256],
    });
  return { approve, pending };
}
