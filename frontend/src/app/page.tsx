"use client";

import Link from "next/link";
import {
  Activity,
  ArrowRight,
  Brain,
  Gauge,
  Layers,
  LineChart,
  Lock,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  Users,
  Wallet,
} from "lucide-react";
import { Button, Card } from "@/components/ui";
import { RegimeBadge, SignalBadge } from "@/components/badges";
import { VaultCard } from "@/components/VaultCard";
import { usePool } from "@/hooks/useProtocol";
import { useRankedVaults } from "@/hooks/useLeaderboard";
import { fmtFeePips, fmtUsd } from "@/lib/format";
import { cn } from "@/lib/cn";

export default function Home() {
  const { pool, ethUsd } = usePool();
  const { ranked } = useRankedVaults();
  const tvl = ranked.reduce((a, r) => a + r.tvl, 0);
  const curators = new Set(ranked.map((r) => r.v.curator)).size;
  const top = [...ranked].sort((a, b) => b.tvl - a.tvl).slice(0, 3);

  return (
    <div className="space-y-28 pb-8">
      <Hero regime={pool?.regime} fresh={pool?.signalFresh} />

      <section className="fade-up delay-3 grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-border bg-border md:grid-cols-5">
        {[
          { label: "Total value locked", value: fmtUsd(tvl, 0) },
          { label: "Live vaults", value: String(ranked.length) },
          { label: "Curators", value: String(curators) },
          { label: "Swap fee now", value: pool ? fmtFeePips(pool.fee) : "—" },
          { label: "ETH price", value: fmtUsd(ethUsd) },
        ].map((s) => (
          <div key={s.label} className="bg-card p-6 last:col-span-2 md:last:col-span-1">
            <div className="text-xs uppercase tracking-wide text-muted">{s.label}</div>
            <div className="num mt-2 text-2xl font-bold sm:text-3xl">{s.value}</div>
          </div>
        ))}
      </section>

      <HowItWorks />
      <Bento />

      <section>
        <SectionHead eyebrow="Live on Unichain Sepolia" title="Pick a strategy" />
        <div className="grid gap-4 md:grid-cols-3">
          {top.map((r) => (
            <VaultCard key={r.v.vault} v={r.v} tvl={r.tvl} perf={r.perf} />
          ))}
        </div>
        <div className="mt-6 text-center">
          <Link href="/vaults" className="inline-flex items-center gap-1 text-sm text-muted hover:text-foreground">
            All vaults <ArrowRight size={14} />
          </Link>
        </div>
      </section>

      <Audiences />
      <BuiltOn />
      <FinalCta />
    </div>
  );
}

function Hero({ regime, fresh }: { regime?: number; fresh?: boolean }) {
  return (
    <section className="relative grid items-center gap-10 pt-10 lg:grid-cols-2">
      <div className="grid-glow pointer-events-none absolute -inset-x-4 -top-8 bottom-0 -z-10 [mask-image:radial-gradient(ellipse_at_top_left,black,transparent_70%)]" />
      <div>
        <div className="fade-up mb-5 flex flex-wrap gap-2">
          <RegimeBadge regime={regime} />
          <SignalBadge fresh={fresh} />
        </div>
        <h1 className="fade-up delay-1 text-5xl font-bold leading-[1.05] tracking-tight sm:text-6xl">
          Liquidity that stays in <span className="text-range">range</span>.
        </h1>
        <p className="fade-up delay-2 mt-5 max-w-lg text-lg text-muted">
          AI-sized ranges, curator strategies and a Uniswap v4 hook that guards every rebalance.
        </p>
        <div className="fade-up delay-3 mt-8 flex flex-wrap gap-3">
          <Link href="/vaults">
            <Button className="px-6 py-3 text-base">
              Start earning <ArrowRight size={18} />
            </Button>
          </Link>
          <Link href="/curate">
            <Button variant="secondary" className="px-6 py-3 text-base">
              Launch a vault
            </Button>
          </Link>
        </div>
      </div>
      <HeroVisual />
    </section>
  );
}

function HeroVisual() {
  return (
    <div className="fade-up delay-2 float relative mx-auto w-full max-w-lg">
      <Card className="relative overflow-hidden p-6">
        <div className="mb-4 flex items-center justify-between text-xs text-muted">
          <span className="flex items-center gap-2">
            <span className="relative flex h-2 w-2">
              <span className="ping-soft absolute inline-flex h-full w-full rounded-full bg-range" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-range" />
            </span>
            In range
          </span>
          <span className="num">mWETH / mUSDC</span>
        </div>
        <svg viewBox="0 0 400 200" className="h-56 w-full" aria-hidden>
          <g className="band">
            <rect x="0" y="55" width="400" height="90" rx="10" className="fill-range/15" />
            <line x1="0" x2="400" y1="55" y2="55" className="stroke-range" strokeWidth="2" strokeDasharray="4 6" />
            <line x1="0" x2="400" y1="145" y2="145" className="stroke-range" strokeWidth="2" strokeDasharray="4 6" />
          </g>
          <path
            className="draw stroke-accent"
            d="M0 120 C 40 110, 60 80, 100 95 S 160 130, 200 100 S 260 60, 300 85 S 360 110, 400 90"
            fill="none"
            strokeWidth="4"
            strokeLinecap="round"
          />
          <circle cx="400" cy="90" r="6" className="fill-accent" />
        </svg>
        <div className="mt-4 grid grid-cols-3 gap-3 text-center">
          {[
            { k: "Width", v: "2σ" },
            { k: "Sized by", v: "AI" },
            { k: "Guard", v: "EMA" },
          ].map((x) => (
            <div key={x.k} className="rounded-lg bg-background py-2">
              <div className="text-[11px] uppercase tracking-wide text-muted">{x.k}</div>
              <div className="num font-semibold">{x.v}</div>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

function SectionHead({ eyebrow, title }: { eyebrow: string; title: string }) {
  return (
    <div className="mb-10 text-center">
      <div className="text-sm font-semibold uppercase tracking-widest text-accent">{eyebrow}</div>
      <h2 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{title}</h2>
    </div>
  );
}

function HowItWorks() {
  const steps = [
    { icon: Wallet, title: "Deposit", body: "Pick a curator's vault and deposit both tokens." },
    { icon: Brain, title: "AI sizes the range", body: "Forecast volatility sets how wide the position sits." },
    { icon: RefreshCw, title: "Vault rebalances", body: "On-chain rules re-centre it when price drifts." },
  ];
  return (
    <section>
      <SectionHead eyebrow="How it works" title="Three steps, zero babysitting" />
      <div className="relative grid gap-6 md:grid-cols-3">
        <div className="absolute left-[16%] right-[16%] top-8 hidden h-px bg-gradient-to-r from-transparent via-border to-transparent md:block" />
        {steps.map(({ icon: Icon, title, body }, i) => (
          <div key={title} className="relative text-center">
            <div className="relative mx-auto flex h-16 w-16 items-center justify-center rounded-2xl border border-border bg-card">
              <Icon className="text-accent" size={26} />
              <span className="num absolute -right-2 -top-2 flex h-6 w-6 items-center justify-center rounded-full bg-accent text-xs font-bold text-white">
                {i + 1}
              </span>
            </div>
            <h3 className="mt-5 text-lg font-semibold">{title}</h3>
            <p className="mx-auto mt-2 max-w-xs text-sm text-muted">{body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

const FEES = [
  { name: "Calm", fee: "0.05%", h: "h-6", cls: "bg-regime-calm" },
  { name: "Normal", fee: "0.30%", h: "h-12", cls: "bg-regime-normal" },
  { name: "High", fee: "0.75%", h: "h-20", cls: "bg-regime-high" },
  { name: "Extreme", fee: "1.50%", h: "h-28", cls: "bg-regime-extreme" },
];

function Bento() {
  return (
    <section>
      <SectionHead eyebrow="Why Rangefy" title="Built for LPs, enforced by code" />
      <div className="grid gap-4 md:grid-cols-6">
        <Card className="md:col-span-4">
          <Icon icon={Sparkles} />
          <h3 className="mt-4 text-xl font-semibold">AI volatility signal</h3>
          <p className="mt-1 text-sm text-muted">Transformer + Random Forest forecast, posted on-chain every minute.</p>
          <svg viewBox="0 0 300 60" preserveAspectRatio="none" className="mt-6 h-20 w-full" aria-hidden>
            <polyline
              className="draw stroke-range"
              fill="none"
              strokeWidth="3"
              strokeLinecap="round"
              strokeLinejoin="round"
              points="0,45 30,40 60,42 90,30 120,34 150,18 180,26 210,14 240,22 270,10 300,16"
            />
          </svg>
        </Card>

        <Card className="md:col-span-2">
          <Icon icon={Gauge} />
          <h3 className="mt-4 text-xl font-semibold">Dynamic fees</h3>
          <div className="mt-6 flex h-32 items-end justify-between gap-2">
            {FEES.map((f) => (
              <div key={f.name} className="flex flex-1 flex-col items-center gap-1.5">
                <span className="num text-xs font-semibold">{f.fee}</span>
                <div className={cn("w-full rounded-md opacity-80", f.h, f.cls)} />
                <span className="text-[10px] text-muted">{f.name}</span>
              </div>
            ))}
          </div>
        </Card>

        <Card className="md:col-span-2">
          <Icon icon={ShieldCheck} />
          <h3 className="mt-4 text-xl font-semibold">Manipulation-proof</h3>
          <ul className="mt-4 space-y-2 text-sm">
            {["EMA price guard", "Rebalance cooldowns", "Bounded, expiring signals"].map((x) => (
              <li key={x} className="flex items-center gap-2">
                <Lock size={14} className="text-range" /> {x}
              </li>
            ))}
          </ul>
        </Card>

        <Card className="md:col-span-2">
          <Icon icon={Users} />
          <h3 className="mt-4 text-xl font-semibold">Curator marketplace</h3>
          <p className="mt-1 text-sm text-muted">Anyone can launch a strategy. The leaderboard ranks them against HODL.</p>
        </Card>

        <Card className="md:col-span-2">
          <Icon icon={Activity} />
          <h3 className="mt-4 text-xl font-semibold">Permissionless</h3>
          <p className="mt-1 text-sm text-muted">If the keeper stops, anyone can rebalance. Same rules, same range.</p>
        </Card>
      </div>
    </section>
  );
}

function Icon({ icon: I }: { icon: typeof Brain }) {
  return (
    <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-accent/10">
      <I className="text-accent" size={22} />
    </div>
  );
}

function Audiences() {
  const cols = [
    {
      icon: LineChart,
      tag: "For LPs",
      title: "Earn fees without managing ranges",
      points: ["Deposit and withdraw anytime", "Ranges resize with volatility", "Track alpha vs HODL"],
      cta: { href: "/vaults", label: "Browse vaults" },
      tone: "range",
    },
    {
      icon: Layers,
      tag: "For curators",
      title: "Turn your strategy into a vault",
      points: ["Set width, drift and cooldown", "Earn up to 20% performance fee", "Never custody LP funds"],
      cta: { href: "/curate", label: "Become a curator" },
      tone: "accent",
    },
  ] as const;
  return (
    <section className="grid gap-4 md:grid-cols-2">
      {cols.map(({ icon: I, tag, title, points, cta, tone }) => (
        <div
          key={tag}
          className={cn(
            "rounded-2xl border p-8",
            tone === "range" ? "border-range/30 bg-range/5" : "border-accent/30 bg-accent/5",
          )}
        >
          <I className={tone === "range" ? "text-range" : "text-accent"} size={28} />
          <div className="mt-5 text-sm font-semibold uppercase tracking-wide text-muted">{tag}</div>
          <h3 className="mt-1 text-2xl font-bold">{title}</h3>
          <ul className="mt-5 space-y-2.5">
            {points.map((p) => (
              <li key={p} className="flex items-center gap-2.5">
                <span className={cn("h-1.5 w-1.5 rounded-full", tone === "range" ? "bg-range" : "bg-accent")} />
                {p}
              </li>
            ))}
          </ul>
          <Link href={cta.href} className="mt-7 inline-block">
            <Button variant={tone === "range" ? "secondary" : "primary"}>
              {cta.label} <ArrowRight size={16} />
            </Button>
          </Link>
        </div>
      ))}
    </section>
  );
}

function BuiltOn() {
  return (
    <section className="text-center">
      <div className="text-sm text-muted">Built on</div>
      <div className="mt-4 flex flex-wrap justify-center gap-3">
        {["Uniswap v4", "Unichain", "PyTorch", "scikit-learn", "Foundry", "Next.js"].map((t) => (
          <span key={t} className="rounded-full border border-border px-4 py-2 text-sm font-medium">
            {t}
          </span>
        ))}
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="relative overflow-hidden rounded-3xl border border-border bg-card px-6 py-16 text-center">
      <div className="grid-glow pointer-events-none absolute inset-0 opacity-60" />
      <div className="relative">
        <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">Ready to stay in range?</h2>
        <p className="mt-3 text-muted">Grab test tokens and deposit in under a minute.</p>
        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Link href="/faucet">
            <Button className="px-6 py-3 text-base">Get test tokens</Button>
          </Link>
          <Link href="/ai">
            <Button variant="secondary" className="px-6 py-3 text-base">
              See the AI signal
            </Button>
          </Link>
        </div>
      </div>
    </section>
  );
}
