"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { parseUnits, type Address } from "viem";
import { ArrowDownUp } from "lucide-react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Button, Card, Input, PageHeader } from "@/components/ui";
import { RegimeBadge } from "@/components/badges";
import { addresses, pool, tokens } from "@/config/addresses";
import { SimpleSwapRouterAbi } from "@/config/abis";
import { usePool } from "@/hooks/useProtocol";
import { useApprove, useTokens } from "@/hooks/useToken";
import { useTx } from "@/hooks/useTx";
import { fmtFeePips, fmtNum, fmtToken, fmtUsd, toFloat } from "@/lib/format";

export default function SwapPage() {
  const { address } = useAccount();
  const { pool: pv, ethUsd } = usePool();
  const [sellWeth, setSellWeth] = useState(true);
  const [amount, setAmount] = useState("");
  const t = useTokens(addresses.router);
  const { approve, pending: approving } = useApprove();
  const { send, pending } = useTx();

  const tin = sellWeth ? tokens.mWETH : tokens.mUSDC;
  const tout = sellWeth ? tokens.mUSDC : tokens.mWETH;
  const bal = sellWeth ? t.weth : t.usdc;
  let raw = 0n;
  try {
    raw = amount ? parseUnits(amount as `${number}`, tin.decimals) : 0n;
  } catch {}
  const zeroForOne = tin.address.toLowerCase() === pool.key.currency0.toLowerCase();
  const n = Number(amount) || 0;
  const feeRate = pv ? pv.fee / 1e6 : 0;
  const estOut = ethUsd ? (sellWeth ? n * ethUsd : n / ethUsd) * (1 - feeRate) : 0;
  const minOut = parseUnits((estOut * 0.98).toFixed(tout.decimals) as `${number}`, tout.decimals);

  const swap = () =>
    send(`Swap ${tin.symbol} → ${tout.symbol}`, {
      address: addresses.router,
      abi: SimpleSwapRouterAbi,
      functionName: "swapExactIn",
      args: [pool.key, zeroForOne, raw, minOut, address as Address, BigInt(Math.floor(Date.now() / 1000) + 600)],
    }).then((ok) => ok && setAmount(""));

  return (
    <div className="mx-auto max-w-md">
      <PageHeader title="Swap" subtitle="Trade on the Rangefy pool. Every swap pays the hook's live regime fee." />
      <Card className="space-y-4">
        <div className="flex items-center justify-between text-sm">
          <RegimeBadge regime={pv?.regime} />
          <span className="text-muted">Fee <span className="num font-semibold text-foreground">{pv ? fmtFeePips(pv.fee) : "—"}</span></span>
        </div>
        <div>
          <div className="mb-1 flex justify-between text-xs text-muted">
            <span>You pay · {tin.symbol}</span>
            <button onClick={() => setAmount(String(toFloat(bal.balance, tin.decimals)))}>Balance {fmtToken(bal.balance, tin.decimals)}</button>
          </div>
          <Input inputMode="decimal" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
        </div>
        <div className="flex justify-center">
          <button aria-label="Flip direction" onClick={() => { setSellWeth(!sellWeth); setAmount(""); }} className="rounded-full border border-border p-2 hover:border-accent">
            <ArrowDownUp size={16} />
          </button>
        </div>
        <div className="rounded-lg bg-background p-3">
          <div className="text-xs text-muted">You receive (est.) · {tout.symbol}</div>
          <div className="num mt-1 text-lg font-semibold">{fmtNum(estOut, sellWeth ? 2 : 6)}</div>
          <div className="text-xs text-muted">Pool price {fmtUsd(ethUsd)} · min received with 2% slippage</div>
        </div>
        {!address ? (
          <div className="flex justify-center"><ConnectButton /></div>
        ) : bal.allowance < raw ? (
          <Button className="w-full" loading={!!approving} onClick={() => approve(tin, addresses.router)}>Approve {tin.symbol}</Button>
        ) : (
          <Button className="w-full" disabled={raw === 0n || raw > bal.balance} loading={!!pending} onClick={swap}>
            {raw > bal.balance ? "Insufficient balance" : "Swap"}
          </Button>
        )}
        <p className="text-xs text-muted">Push the price to see vaults hit their edge and the keeper rebalance them.</p>
      </Card>
    </div>
  );
}
