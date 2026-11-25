"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAccount, useReadContract } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Button, Card, CardTitle, Input, PageHeader } from "@/components/ui";
import { addresses, isDeployed, pool } from "@/config/addresses";
import { CuratorRegistryAbi, VaultFactoryAbi } from "@/config/abis";
import { usePool } from "@/hooks/useProtocol";
import { useTx } from "@/hooks/useTx";
import { BOUNDS, PRESETS, PROFILE_INDEX, targetRange, type Params } from "@/lib/strategy";
import { rangeUsd } from "@/lib/pool";
import { fmtBps, fmtDuration, fmtUsd } from "@/lib/format";

type ProfileName = keyof typeof PROFILE_INDEX;

const toMeta = (bio: string) => `data:application/json,${encodeURIComponent(JSON.stringify({ bio }))}`;

export default function CuratePage() {
  const { address } = useAccount();
  const router = useRouter();
  const { pool: pv } = usePool();
  const { send, pending } = useTx();

  const curator = useReadContract({
    address: addresses.curatorRegistry,
    abi: CuratorRegistryAbi,
    functionName: "getCurator",
    args: [address!],
    query: { enabled: isDeployed && !!address },
  });
  const registered = !!curator.data?.active;

  const [name, setName] = useState("");
  const [bio, setBio] = useState("");
  const [profile, setProfile] = useState<ProfileName>("Balanced");
  const [params, setParams] = useState<Params>(PRESETS.Balanced);
  const [vaultName, setVaultName] = useState("");
  const [symbol, setSymbol] = useState("");

  const pick = (p: ProfileName) => {
    setProfile(p);
    if (p !== "Custom") setParams(PRESETS[p]);
  };
  const set = (k: keyof Params, v: number) => {
    setProfile("Custom");
    setParams((s) => ({ ...s, [k]: v }));
  };

  const preview = useMemo(() => {
    if (!pv) return null;
    const r = targetRange(pv.emaTick, pv.sigma, pv.drift, params);
    const [lo, hi] = rangeUsd(r.lower, r.upper);
    return { ...r, lo, hi };
  }, [pv, params]);

  const register = () =>
    send("Register curator", {
      address: addresses.curatorRegistry,
      abi: CuratorRegistryAbi,
      functionName: "register",
      args: [name.trim(), toMeta(bio)],
    }).then(() => curator.refetch());

  const create = async () => {
    const ok = await send("Create vault", {
      address: addresses.vaultFactory,
      abi: VaultFactoryAbi,
      functionName: "createVault",
      args: [pool.key, PROFILE_INDEX[profile], params, vaultName.trim(), symbol.trim()],
    });
    if (ok) router.push("/vaults");
  };

  if (!address) {
    return (
      <div>
        <PageHeader title="Curate" subtitle="Register as a curator and launch a vault with your strategy." />
        <Card className="flex flex-col items-center gap-3 py-10 text-muted">Connect a wallet to start.<ConnectButton /></Card>
      </div>
    );
  }

  return (
    <div>
      <PageHeader title="Curate" subtitle="You set the strategy. The vault and hook enforce it on-chain; you never hold LP funds." />
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div className="space-y-6">
          <Card>
            <CardTitle>1 · Curator profile</CardTitle>
            {registered ? (
              <p className="text-sm">Registered as <span className="font-semibold">{curator.data?.name}</span>.</p>
            ) : (
              <div className="space-y-3">
                <Input placeholder="Name (3–32 chars)" value={name} onChange={(e) => setName(e.target.value)} className="font-sans" />
                <Input placeholder="Short bio" value={bio} onChange={(e) => setBio(e.target.value)} className="font-sans" />
                <Button onClick={register} disabled={name.trim().length < 3} loading={pending === "Register curator"}>Register</Button>
              </div>
            )}
          </Card>

          <Card>
            <CardTitle>2 · Strategy</CardTitle>
            <div className="mb-5 flex flex-wrap gap-2">
              {(Object.keys(PROFILE_INDEX) as ProfileName[]).map((p) => (
                <button
                  key={p}
                  onClick={() => pick(p)}
                  className={`rounded-full border px-3 py-1.5 text-sm ${profile === p ? "border-accent bg-accent/10 text-accent" : "border-border text-muted"}`}
                >
                  {p}
                </button>
              ))}
            </div>
            <div className="grid gap-5 sm:grid-cols-2">
              <Slider label="Width multiplier" value={params.widthMultiplierBps} k="widthMultiplierBps" step={500} fmt={(v) => `${(v / 10_000).toFixed(1)}σ`} onChange={set} />
              <Slider label="Drift weight" value={params.driftWeightBps} k="driftWeightBps" step={250} fmt={fmtBps} onChange={set} />
              <Slider label="Min half-width" value={params.minHalfWidth} k="minHalfWidth" step={60} fmt={(v) => `${v} ticks`} onChange={(k, v) => set(k, Math.min(v, params.maxHalfWidth))} />
              <Slider label="Max half-width" value={params.maxHalfWidth} k="maxHalfWidth" step={60} fmt={(v) => `${v} ticks`} onChange={(k, v) => set(k, Math.max(v, params.minHalfWidth))} />
              <Slider label="Cooldown" value={params.minRebalanceInterval} k="minRebalanceInterval" step={60} fmt={fmtDuration} onChange={set} />
              <Slider label="EMA guard" value={params.maxEmaDeviation} k="maxEmaDeviation" step={10} fmt={(v) => `±${v} ticks`} onChange={set} />
              <Slider label="Performance fee" value={params.performanceFeeBps} k="performanceFeeBps" step={50} fmt={fmtBps} onChange={set} />
            </div>
          </Card>

          <Card>
            <CardTitle>3 · Name & launch</CardTitle>
            <div className="grid gap-3 sm:grid-cols-2">
              <Input placeholder="Vault name, e.g. Harbor Balanced" value={vaultName} onChange={(e) => setVaultName(e.target.value)} className="font-sans" />
              <Input placeholder="Symbol, e.g. rfHRB" value={symbol} onChange={(e) => setSymbol(e.target.value)} className="font-sans" />
            </div>
            <Button className="mt-4" onClick={create} disabled={!registered || !vaultName.trim() || !symbol.trim()} loading={pending === "Create vault"}>
              Create vault
            </Button>
            {!registered && <p className="mt-2 text-xs text-muted">Register as a curator first.</p>}
          </Card>
        </div>

        <Card className="h-fit">
          <CardTitle>Live range preview</CardTitle>
          {preview && pv ? (
            <div className="space-y-3 text-sm">
              <p className="text-muted">If created now, your vault would open this range:</p>
              <div className="num text-2xl font-bold text-range">{fmtUsd(preview.lo, 0)} – {fmtUsd(preview.hi, 0)}</div>
              <dl className="num grid grid-cols-2 gap-y-1.5">
                <dt className="text-muted">Half-width</dt><dd>{preview.halfWidth} ticks (±{(preview.halfWidth / 100).toFixed(1)}%)</dd>
                <dt className="text-muted">Volatility σ</dt><dd>{pv.sigma} ticks · {pv.signalFresh ? "AI" : "on-chain"}</dd>
                <dt className="text-muted">AI drift</dt><dd>{pv.drift} ticks</dd>
              </dl>
            </div>
          ) : (
            <p className="text-sm text-muted">Waiting for pool data…</p>
          )}
        </Card>
      </div>
    </div>
  );
}

function Slider({ label, value, k, step, fmt, onChange }: { label: string; value: number; k: keyof Params; step: number; fmt: (v: number) => string; onChange: (k: keyof Params, v: number) => void }) {
  const [min, max] = BOUNDS[k];
  return (
    <label className="block">
      <div className="mb-1 flex justify-between text-sm">
        <span className="text-muted">{label}</span>
        <span className="num font-semibold">{fmt(value)}</span>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(k, Number(e.target.value))}
        className="w-full accent-[var(--accent)]"
      />
    </label>
  );
}
