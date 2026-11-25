"use client";

import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Droplets, ExternalLink } from "lucide-react";
import { Button, Card, PageHeader } from "@/components/ui";
import { tokens } from "@/config/addresses";
import { activeChain } from "@/config/chains";
import { MockERC20Abi } from "@/config/abis";
import { useTokens } from "@/hooks/useToken";
import { useTx } from "@/hooks/useTx";
import { fmtDuration, fmtToken } from "@/lib/format";

const DRIP = { mWETH: "5 mWETH", mUSDC: "20,000 mUSDC" } as const;

export default function FaucetPage() {
  const { address } = useAccount();
  const t = useTokens();
  const { send, pending } = useTx();

  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader title="Faucet" subtitle="Test tokens for the Rangefy pool. Once every 24 hours per wallet." />
      <div className="grid gap-4 sm:grid-cols-2">
        {(["mWETH", "mUSDC"] as const).map((sym) => {
          const tok = tokens[sym];
          const s = sym === "mWETH" ? t.weth : t.usdc;
          return (
            <Card key={sym} className="space-y-3">
              <div className="flex items-center gap-2 font-semibold"><Droplets size={18} className="text-accent" />{sym}</div>
              <div className="text-sm text-muted">Balance <span className="num text-foreground">{fmtToken(s.balance, tok.decimals)}</span></div>
              {!address ? (
                <ConnectButton />
              ) : (
                <Button
                  className="w-full"
                  disabled={s.faucetIn > 0}
                  loading={pending === `Claim ${sym}`}
                  onClick={() => send(`Claim ${sym}`, { address: tok.address, abi: MockERC20Abi, functionName: "faucet" })}
                >
                  {s.faucetIn > 0 ? `Available in ${fmtDuration(s.faucetIn)}` : `Claim ${DRIP[sym]}`}
                </Button>
              )}
            </Card>
          );
        })}
      </div>
      {activeChain.id === 1301 && (
        <Card className="mt-4 text-sm text-muted">
          Need gas? Get Unichain Sepolia ETH from a faucet listed in the{" "}
          <a href="https://docs.unichain.org/docs/tools/faucets" target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-foreground underline">
            Unichain docs <ExternalLink size={12} />
          </a>
          .
        </Card>
      )}
    </div>
  );
}
