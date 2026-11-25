"use client";

import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { getAbiItem, type Address, type PublicClient } from "viem";
import { addresses, isDeployed } from "@/config/addresses";
import { RangeVaultAbi, RangefyHookAbi } from "@/config/abis";
import { blockClock } from "@/lib/pool";
import type { FeeEvent, PriceSample, RangeSegment, Snapshot } from "@/lib/performance";

const CHUNK = 10_000n;

const ev = {
  snapshot: getAbiItem({ abi: RangeVaultAbi, name: "Snapshot" }),
  rebalanced: getAbiItem({ abi: RangeVaultAbi, name: "Rebalanced" }),
  fees: getAbiItem({ abi: RangeVaultAbi, name: "FeesCollected" }),
  deposit: getAbiItem({ abi: RangeVaultAbi, name: "Deposit" }),
  withdraw: getAbiItem({ abi: RangeVaultAbi, name: "Withdraw" }),
  poolState: getAbiItem({ abi: RangefyHookAbi, name: "PoolStateUpdated" }),
};
type EventKey = keyof typeof ev;

type Cached = { toBlock: bigint; logs: unknown[] };
const cache = new Map<string, Cached>();

// incremental, chunked; halves the chunk if the RPC refuses
async function fetchLogs(client: PublicClient, key: EventKey, address: Address | Address[]) {
  const id = `${client.chain?.id}:${key}:${[address].flat().join(",")}`;
  const latest = await client.getBlockNumber();
  const prev = cache.get(id);
  let from = prev ? prev.toBlock + 1n : BigInt(addresses.deployBlock);
  const logs = prev ? [...prev.logs] : [];
  let step = CHUNK;
  while (from <= latest) {
    const to = from + step - 1n > latest ? latest : from + step - 1n;
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const chunk = await client.getLogs({ address, event: ev[key] as any, fromBlock: from, toBlock: to });
      logs.push(...chunk);
      from = to + 1n;
    } catch (e) {
      if (step <= 500n) throw e;
      step /= 2n;
    }
  }
  cache.set(id, { toBlock: latest, logs });
  return logs as Array<{ args: Record<string, unknown>; blockNumber: bigint; address: Address; transactionHash: `0x${string}` }>;
}

async function clock(client: PublicClient) {
  const [first, last] = await Promise.all([
    client.getBlock({ blockNumber: BigInt(addresses.deployBlock) }),
    client.getBlock(),
  ]);
  return blockClock({ block: first.number, ts: Number(first.timestamp) }, { block: last.number, ts: Number(last.timestamp) });
}

export type RebalanceRow = {
  ts: number;
  reason: number;
  oldLower: number;
  oldUpper: number;
  newLower: number;
  newUpper: number;
  sigma: number;
  fromSignal: boolean;
  spotTick: number;
  tx: `0x${string}`;
};

export type VaultHistory = {
  snapshots: Snapshot[];
  rebalances: RebalanceRow[];
  fees: FeeEvent[];
  ranges: RangeSegment[];
  flows: { ts: number; kind: "deposit" | "withdraw"; amount0: bigint; amount1: bigint; tx: `0x${string}` }[];
};

export async function loadVaultHistory(
  client: PublicClient,
  vault: Address,
  current: { tickLower: number; tickUpper: number },
): Promise<VaultHistory> {
  const [toTs, snaps, rbs, fees, deps, wds] = await Promise.all([
    clock(client),
    fetchLogs(client, "snapshot", vault),
    fetchLogs(client, "rebalanced", vault),
    fetchLogs(client, "fees", vault),
    fetchLogs(client, "deposit", vault),
    fetchLogs(client, "withdraw", vault),
  ]);

  const snapshots: Snapshot[] = snaps.map((l) => ({
    total0: l.args.total0 as bigint,
    total1: l.args.total1 as bigint,
    totalSupply: l.args.totalSupply as bigint,
    emaTick: Number(l.args.emaTick),
    timestamp: Number(l.args.timestamp),
  }));

  const rebalances: RebalanceRow[] = rbs.map((l) => ({
    ts: toTs(l.blockNumber),
    reason: Number(l.args.reason),
    oldLower: Number(l.args.oldLower),
    oldUpper: Number(l.args.oldUpper),
    newLower: Number(l.args.newLower),
    newUpper: Number(l.args.newUpper),
    sigma: Number(l.args.sigmaUsed),
    fromSignal: Boolean(l.args.fromSignal),
    spotTick: Number(l.args.spotTick),
    tx: l.transactionHash,
  }));

  const flows = [
    ...deps.map((l) => ({ kind: "deposit" as const, l })),
    ...wds.map((l) => ({ kind: "withdraw" as const, l })),
  ]
    .map(({ kind, l }) => ({
      ts: toTs(l.blockNumber),
      kind,
      amount0: l.args.amount0 as bigint,
      amount1: l.args.amount1 as bigint,
      tx: l.transactionHash,
    }))
    .sort((a, b) => a.ts - b.ts);

  // first range = first rebalance's old range, else current
  const start = snapshots[0]?.timestamp ?? flows[0]?.ts ?? Date.now() / 1000;
  const ranges: RangeSegment[] = [];
  if (rebalances.length) {
    ranges.push({ from: start, lower: rebalances[0].oldLower, upper: rebalances[0].oldUpper });
    for (const r of rebalances) ranges.push({ from: r.ts, lower: r.newLower, upper: r.newUpper });
  } else if (current.tickLower < current.tickUpper) {
    ranges.push({ from: start, lower: current.tickLower, upper: current.tickUpper });
  }

  return {
    snapshots,
    rebalances,
    fees: fees.map((l) => ({
      fees0: l.args.fees0 as bigint,
      fees1: l.args.fees1 as bigint,
      curatorFee0: l.args.curatorFee0 as bigint,
      curatorFee1: l.args.curatorFee1 as bigint,
      ts: toTs(l.blockNumber),
    })),
    ranges,
    flows,
  };
}

export function useVaultHistory(vault?: Address, current?: { tickLower: number; tickUpper: number }) {
  const client = usePublicClient();
  return useQuery({
    queryKey: ["vaultHistory", vault],
    enabled: isDeployed && !!client && !!vault && !!current,
    refetchInterval: 15_000,
    queryFn: () => loadVaultHistory(client as PublicClient, vault!, current!),
  });
}

export function usePoolHistory() {
  const client = usePublicClient();
  return useQuery({
    queryKey: ["poolHistory"],
    enabled: isDeployed && !!client,
    refetchInterval: 15_000,
    queryFn: async (): Promise<(PriceSample & { fee: number; regime: number; sigma: number })[]> => {
      const c = client as PublicClient;
      const [toTs, logs] = await Promise.all([clock(c), fetchLogs(c, "poolState", addresses.hook)]);
      return logs.map((l) => ({
        ts: toTs(l.blockNumber),
        tick: Number(l.args.tick),
        fee: Number(l.args.fee),
        regime: Number(l.args.regime),
        sigma: Number(l.args.sigmaTicks),
      }));
    },
  });
}

export function useAllVaultHistories(vaults?: readonly { vault: Address; tickLower: number; tickUpper: number }[]) {
  const client = usePublicClient();
  return useQuery({
    queryKey: ["allVaultHistories", vaults?.map((v) => v.vault).join(",")],
    enabled: isDeployed && !!client && !!vaults?.length,
    refetchInterval: 30_000,
    queryFn: async () => {
      const entries = await Promise.all(
        vaults!.map(async (v) => [v.vault, await loadVaultHistory(client as PublicClient, v.vault, v)] as const),
      );
      return Object.fromEntries(entries) as Record<Address, VaultHistory>;
    },
  });
}
