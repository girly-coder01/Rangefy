import { NextResponse, type NextRequest } from "next/server";
import { createPublicClient, createWalletClient, http, maxUint256, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { activeChain } from "@/config/chains";
import { addresses, pool } from "@/config/addresses";
import { MockERC20Abi, RangeVaultAbi, RangefyLensAbi, SimpleSwapRouterAbi, VaultFactoryAbi } from "@/config/abis";
import { sqrtToUsd } from "@/lib/pool";
import { ethUsd } from "@/lib/server/market";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const REASONS = ["None", "OutOfRange", "NearEdge", "WidthDrift", "Initial", "IdleExcess"];
const MIRROR_DEVIATION_BPS = 30;
const MIRROR_MAX_WETH = 2n * 10n ** 18n;
const MIRROR_MAX_USDC = 6_000n * 10n ** 6n;

const rpc = process.env.KEEPER_RPC_URL || activeChain.rpcUrls.default.http[0];
const publicClient = createPublicClient({ chain: activeChain, transport: http(rpc) });

function authorized(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  return req.headers.get("authorization") === `Bearer ${secret}` || req.nextUrl.searchParams.get("secret") === secret;
}

function wallet(envKey: string) {
  const key = process.env[envKey];
  if (!key) return null;
  const account = privateKeyToAccount((key.startsWith("0x") ? key : `0x${key}`) as Hex);
  return createWalletClient({ account, chain: activeChain, transport: http(rpc) });
}

type Wallet = NonNullable<ReturnType<typeof wallet>>;

async function send(w: Wallet, req: Parameters<typeof publicClient.simulateContract>[0]) {
  const { request } = await publicClient.simulateContract({ ...req, account: w.account });
  const hash = await w.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash, timeout: 30_000 });
  return { hash, ok: receipt.status === "success" };
}

async function rebalanceAndHarvest(w: Wallet) {
  const out: unknown[] = [];
  const vaults = (await publicClient.readContract({
    address: addresses.vaultFactory,
    abi: VaultFactoryAbi,
    functionName: "allVaults",
  })) as Address[];
  const now = Math.floor(Date.now() / 1000);
  const harvestWindow = new Date().getUTCMinutes() < 2; // roughly hourly with a per-minute cron

  for (const v of vaults) {
    try {
      const [needed, reason] = await publicClient.readContract({ address: v, abi: RangeVaultAbi, functionName: "needsRebalance" });
      if (needed) {
        const tx = await send(w, { address: v, abi: RangeVaultAbi, functionName: "rebalance" });
        out.push({ vault: v, action: "rebalance", reason: REASONS[reason], ...tx });
        continue;
      }
      if (!harvestWindow) continue;
      const [liq] = await publicClient.readContract({ address: v, abi: RangeVaultAbi, functionName: "getPosition" });
      const last = await publicClient.readContract({ address: v, abi: RangeVaultAbi, functionName: "lastRebalance" });
      if (liq > 0n && now - Number(last) > 3600) {
        const tx = await send(w, { address: v, abi: RangeVaultAbi, functionName: "harvest" });
        out.push({ vault: v, action: "harvest", ...tx });
      }
    } catch (e) {
      out.push({ vault: v, error: (e as Error).message.split("\n")[0] });
    }
  }
  return out;
}

async function mirror(w: Wallet) {
  const real = await ethUsd();
  const p = await publicClient.readContract({ address: addresses.lens, abi: RangefyLensAbi, functionName: "getPool", args: [pool.key] });
  const testnet = sqrtToUsd(p.sqrtPriceX96);
  const deviationBps = Math.abs(testnet / real - 1) * 10_000;
  if (deviationBps <= MIRROR_DEVIATION_BPS) return { real, testnet, deviationBps, action: "none" };

  // raw token1/token0 price in smallest units → sqrtPriceX96
  const raw = pool.wethIsToken0 ? real * 10 ** (6 - 18) : (1 / real) * 10 ** (18 - 6);
  const target = BigInt(Math.floor(Math.sqrt(raw) * 2 ** 96));
  const zeroForOne = target < p.sqrtPriceX96;
  const tokenIn = zeroForOne ? pool.token0 : pool.token1;
  const maxIn = tokenIn.symbol === "mWETH" ? MIRROR_MAX_WETH : MIRROR_MAX_USDC;

  const allowance = await publicClient.readContract({
    address: tokenIn.address,
    abi: MockERC20Abi,
    functionName: "allowance",
    args: [w.account.address, addresses.router],
  });
  if (allowance < maxIn) {
    await send(w, { address: tokenIn.address, abi: MockERC20Abi, functionName: "approve", args: [addresses.router, maxUint256] });
  }
  const swap = () =>
    send(w, { address: addresses.router, abi: SimpleSwapRouterAbi, functionName: "swapToPrice", args: [pool.key, target, maxIn, w.account.address] });
  // public RPC nodes can lag a block behind a fresh approve
  const tx = await swap().catch(async () => {
    await new Promise((r) => setTimeout(r, 2500));
    return swap();
  });
  return { real, testnet, deviationBps, action: "swap", tokenIn: tokenIn.symbol, ...tx };
}

export async function GET(req: NextRequest) {
  if (!authorized(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const keeper = wallet("KEEPER_PRIVATE_KEY");
  const mirrorWallet = wallet("MIRROR_PRIVATE_KEY");
  const result: Record<string, unknown> = { at: new Date().toISOString() };

  if (mirrorWallet) {
    try {
      result.mirror = await mirror(mirrorWallet);
    } catch (e) {
      result.mirror = { error: (e as Error).message.split("\n")[0] };
    }
  }
  if (keeper) result.vaults = await rebalanceAndHarvest(keeper);
  if (!keeper && !mirrorWallet) result.note = "set KEEPER_PRIVATE_KEY and/or MIRROR_PRIVATE_KEY";

  return NextResponse.json(result);
}

export const POST = GET;

