"use client";

import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { parseUnits, type Address } from "viem";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Button, Card, Input, Tabs } from "./ui";
import { tokens } from "@/config/addresses";
import { RangeVaultAbi } from "@/config/abis";
import { useApprove, useTokens } from "@/hooks/useToken";
import { useTx } from "@/hooks/useTx";
import { REFRESH_MS, type VaultView } from "@/hooks/useProtocol";
import { fromWethUsdc, toWethUsdc, usdValue } from "@/lib/pool";
import { fmtToken, fmtUsd, toFloat } from "@/lib/format";

const parse = (v: string, d: number) => {
  try {
    return v ? parseUnits(v as `${number}`, d) : 0n;
  } catch {
    return 0n;
  }
};
const SLIPPAGE = 99n; // percent kept

export function DepositWithdraw({ v, ethUsd }: { v: VaultView; ethUsd?: number }) {
  const [tab, setTab] = useState<"deposit" | "withdraw">("deposit");
  const { address } = useAccount();
  return (
    <Card>
      <div className="mb-4">
        <Tabs
          value={tab}
          onChange={setTab}
          options={[
            { value: "deposit", label: "Deposit" },
            { value: "withdraw", label: "Withdraw" },
          ]}
        />
      </div>
      {!address ? (
        <div className="flex flex-col items-center gap-3 py-6 text-sm text-muted">
          Connect a wallet to {tab}.
          <ConnectButton />
        </div>
      ) : tab === "deposit" ? (
        <DepositForm v={v} ethUsd={ethUsd} />
      ) : (
        <WithdrawForm v={v} ethUsd={ethUsd} />
      )}
    </Card>
  );
}

function DepositForm({ v, ethUsd }: { v: VaultView; ethUsd?: number }) {
  const [weth, setWeth] = useState("");
  const [usdc, setUsdc] = useState("");
  const t = useTokens(v.vault);
  const { approve, pending: approving } = useApprove();
  const { send, pending } = useTx();
  const { address } = useAccount();

  const w = parse(weth, 18);
  const u = parse(usdc, 6);
  const [a0, a1] = fromWethUsdc(w, u);

  const preview = useReadContract({
    address: v.vault,
    abi: RangeVaultAbi,
    functionName: "previewDeposit",
    args: [a0, a1],
    query: { enabled: w > 0n || u > 0n, refetchInterval: REFRESH_MS },
  });
  const [shares, used0, used1] = preview.data ?? [0n, 0n, 0n];
  const used = toWethUsdc(used0, used1);

  const autofill = (side: "weth" | "usdc", value: string) => {
    if (side === "weth") setWeth(value);
    else setUsdc(value);
    if (!ethUsd || !value) return;
    const n = Number(value);
    if (!Number.isFinite(n)) return;
    // mirror the vault's current composition when we know it
    const total = toWethUsdc(v.total0, v.total1);
    const ratio = total.weth > 0n ? toFloat(total.usdc, 6) / toFloat(total.weth, 18) : ethUsd;
    if (side === "weth") setUsdc((n * ratio * 1.02).toFixed(2));
    else setWeth((n / (ratio || ethUsd) * 1.02).toFixed(6));
  };

  const needWeth = w > 0n && t.weth.allowance < w;
  const needUsdc = u > 0n && t.usdc.allowance < u;
  const tooMuch = w > t.weth.balance || u > t.usdc.balance;

  const deposit = () =>
    send("Deposit", {
      address: v.vault,
      abi: RangeVaultAbi,
      functionName: "deposit",
      args: [a0, a1, (shares * SLIPPAGE) / 100n, address as Address],
    }).then((ok) => ok && (setWeth(""), setUsdc("")));

  return (
    <div className="space-y-3">
      <AmountRow symbol="mWETH" value={weth} onChange={(x) => autofill("weth", x)} balance={t.weth.balance} decimals={18} />
      <AmountRow symbol="mUSDC" value={usdc} onChange={(x) => autofill("usdc", x)} balance={t.usdc.balance} decimals={6} />
      <div className="space-y-1 rounded-lg bg-background p-3 text-sm">
        <Row label="You receive" value={`${fmtToken(shares, 18, 6)} ${v.symbol}`} />
        <Row label="Uses" value={`${fmtToken(used.weth, 18)} mWETH + ${fmtToken(used.usdc, 6, 2)} mUSDC`} />
        <Row label="Value" value={ethUsd ? fmtUsd(usdValue(used.weth, used.usdc, ethUsd)) : "—"} />
      </div>
      {v.depositsPaused ? (
        <Button className="w-full" disabled>Deposits paused by curator</Button>
      ) : needWeth ? (
        <Button className="w-full" loading={!!approving} onClick={() => approve(tokens.mWETH, v.vault)}>Approve mWETH</Button>
      ) : needUsdc ? (
        <Button className="w-full" loading={!!approving} onClick={() => approve(tokens.mUSDC, v.vault)}>Approve mUSDC</Button>
      ) : (
        <Button className="w-full" disabled={shares === 0n || tooMuch} loading={!!pending} onClick={deposit}>
          {tooMuch ? "Insufficient balance" : "Deposit"}
        </Button>
      )}
      <p className="text-xs text-muted">Leftover tokens stay in your wallet. Slippage limit 1%.</p>
    </div>
  );
}

function WithdrawForm({ v, ethUsd }: { v: VaultView; ethUsd?: number }) {
  const { address } = useAccount();
  const [pct, setPct] = useState(100);
  const { send, pending } = useTx();
  const bal = useReadContract({
    address: v.vault,
    abi: RangeVaultAbi,
    functionName: "balanceOf",
    args: [address as Address],
    query: { enabled: !!address, refetchInterval: REFRESH_MS },
  });
  const shares = ((bal.data ?? 0n) * BigInt(pct)) / 100n;
  const preview = useReadContract({
    address: v.vault,
    abi: RangeVaultAbi,
    functionName: "previewWithdraw",
    args: [shares],
    query: { enabled: shares > 0n, refetchInterval: REFRESH_MS },
  });
  const [o0, o1] = preview.data ?? [0n, 0n];
  const out = toWethUsdc(o0, o1);

  return (
    <div className="space-y-4">
      <div>
        <div className="mb-2 flex justify-between text-sm">
          <span className="text-muted">Amount</span>
          <span className="num font-semibold">{pct}%</span>
        </div>
        <input type="range" min={1} max={100} value={pct} onChange={(e) => setPct(Number(e.target.value))} className="w-full accent-[var(--accent)]" />
        <div className="mt-2 flex gap-2">
          {[25, 50, 75, 100].map((p) => (
            <button key={p} onClick={() => setPct(p)} className="flex-1 rounded-md border border-border py-1 text-xs hover:border-accent">
              {p}%
            </button>
          ))}
        </div>
      </div>
      <div className="space-y-1 rounded-lg bg-background p-3 text-sm">
        <Row label="Your shares" value={`${fmtToken(bal.data, 18, 6)} ${v.symbol}`} />
        <Row label="You receive" value={`${fmtToken(out.weth, 18)} mWETH + ${fmtToken(out.usdc, 6, 2)} mUSDC`} />
        <Row label="Value" value={ethUsd ? fmtUsd(usdValue(out.weth, out.usdc, ethUsd)) : "—"} />
      </div>
      <Button
        className="w-full"
        disabled={shares === 0n}
        loading={!!pending}
        onClick={() =>
          send("Withdraw", {
            address: v.vault,
            abi: RangeVaultAbi,
            functionName: "withdraw",
            args: [shares, (o0 * SLIPPAGE) / 100n, (o1 * SLIPPAGE) / 100n, address as Address],
          })
        }
      >
        Withdraw
      </Button>
      <p className="text-xs text-muted">Withdrawals are never paused and have no price guard.</p>
    </div>
  );
}

function AmountRow({ symbol, value, onChange, balance, decimals }: { symbol: string; value: string; onChange: (v: string) => void; balance: bigint; decimals: number }) {
  return (
    <div>
      <div className="mb-1 flex justify-between text-xs text-muted">
        <span>{symbol}</span>
        <button onClick={() => onChange(String(toFloat(balance, decimals)))} className="hover:text-foreground">
          Balance {fmtToken(balance, decimals)} · MAX
        </button>
      </div>
      <Input inputMode="decimal" placeholder="0.0" value={value} onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ""))} />
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-muted">{label}</span>
      <span className="num text-right">{value}</span>
    </div>
  );
}
