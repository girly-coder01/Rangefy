import { NextResponse, type NextRequest } from "next/server";
import { unstable_cache } from "next/cache";
import { createPublicClient, http, isAddress, type Address } from "viem";
import { addresses } from "@/config/addresses";
import { activeChain } from "@/config/chains";
import { VaultFactoryAbi } from "@/config/abis";

export const maxDuration = 60;

const EXPLORER = process.env.EXPLORER_API || "https://unichain-sepolia.blockscout.com/api";
const STEP = 1000n; // public Unichain RPC getLogs limit
const PARALLEL = 8;

type RawLog = { topics: (string | null)[]; data: string; blockNumber: string; transactionHash: string; address: string };

const client = createPublicClient({ chain: activeChain, transport: http(process.env.KEEPER_RPC_URL || activeChain.rpcUrls.default.http[0]) });

async function fromExplorer(address: string): Promise<RawLog[]> {
  const out: RawLog[] = [];
  let from = String(addresses.deployBlock);
  for (let i = 0; i < 50; i++) {
    const qs = new URLSearchParams({ module: "logs", action: "getLogs", fromBlock: from, toBlock: "latest", address });
    if (process.env.BLOCKSCOUT_API_KEY) qs.set("apikey", process.env.BLOCKSCOUT_API_KEY);
    const res = await fetch(`${EXPLORER}?${qs}`, { next: { revalidate: 15 }, signal: AbortSignal.timeout(10_000) });
    const body = (await res.json()) as { message: string; result: RawLog[] | null };
    if (!Array.isArray(body.result)) {
      if (body.message?.toLowerCase().includes("no logs")) break;
      throw new Error(body.message);
    }
    out.push(...body.result);
    if (body.result.length < 1000) break;
    from = String(BigInt(body.result[body.result.length - 1].blockNumber) + 1n);
  }
  return out;
}

async function rpcChunk(addrs: string[], from: string, to: string): Promise<RawLog[]> {
  for (let attempt = 0; ; attempt++) {
    try {
      const logs = await client.getLogs({ address: addrs as Address[], fromBlock: BigInt(from), toBlock: BigInt(to) });
      return logs.map((l) => ({
        topics: l.topics,
        data: l.data,
        blockNumber: `0x${l.blockNumber!.toString(16)}`,
        transactionHash: l.transactionHash!,
        address: l.address,
      }));
    } catch (e) {
      if (attempt >= 3) throw e;
      await new Promise((r) => setTimeout(r, 600 * 2 ** attempt));
    }
  }
}

// Finished chunks never change, so they're cached forever (across requests and deployments).
const cachedChunk = unstable_cache(rpcChunk, ["rpc-logs-v2"], { revalidate: false });

const protocolAddresses = unstable_cache(
  async () => {
    const vaults = await client.readContract({ address: addresses.vaultFactory, abi: VaultFactoryAbi, functionName: "allVaults" });
    return [addresses.hook, addresses.signalOracle, ...vaults].map((a) => a.toLowerCase()).sort();
  },
  ["protocol-addresses"],
  { revalidate: 60 },
);

// One scan covers every protocol contract; concurrent requests share it.
let scan: { at: number; p: Promise<RawLog[]> } | null = null;

async function scanAll(): Promise<RawLog[]> {
  const addrs = await protocolAddresses();
  const latest = await client.getBlockNumber();
  const ranges: [bigint, bigint][] = [];
  for (let a = BigInt(addresses.deployBlock); a <= latest; a += STEP) ranges.push([a, a + STEP - 1n]);
  const out: RawLog[] = [];
  for (let i = 0; i < ranges.length; i += PARALLEL) {
    const batch = await Promise.all(
      ranges.slice(i, i + PARALLEL).map(([a, b]) =>
        b <= latest ? cachedChunk(addrs, String(a), String(b)) : rpcChunk(addrs, String(a), String(latest)),
      ),
    );
    for (const b of batch) out.push(...b);
  }
  return out;
}

async function fromRpc(address: string): Promise<RawLog[]> {
  if (!scan || Date.now() - scan.at > 10_000) {
    const p = scanAll();
    scan = { at: Date.now(), p };
    p.catch(() => (scan = null));
  }
  const all = await scan.p;
  const a = address.toLowerCase();
  return all.filter((l) => l.address.toLowerCase() === a);
}

// All logs for one contract since deployment.
export async function GET(req: NextRequest) {
  const address = req.nextUrl.searchParams.get("address") ?? "";
  if (!isAddress(address)) return NextResponse.json({ error: "bad address" }, { status: 400 });
  let logs: RawLog[];
  let source = "explorer";
  try {
    logs = await fromExplorer(address);
  } catch {
    source = "rpc";
    try {
      logs = await fromRpc(address);
    } catch (e) {
      return NextResponse.json({ error: (e as Error).message.split("\n")[0] }, { status: 502 });
    }
  }
  return NextResponse.json(
    { source, logs: logs.map(({ topics, data, blockNumber, transactionHash, address }) => ({ topics, data, blockNumber, transactionHash, address })) },
    { headers: { "Cache-Control": "public, s-maxage=15, stale-while-revalidate=30" } },
  );
}
