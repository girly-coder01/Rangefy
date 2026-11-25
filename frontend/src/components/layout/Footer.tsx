import Link from "next/link";
import { Logo } from "./Logo";
import { addresses } from "@/config/addresses";
import { activeChain, explorerAddress } from "@/config/chains";

const REPO = "https://github.com/girly-coder01/Rangefy";

const COLS = [
  {
    title: "Product",
    links: [
      { label: "Vaults", href: "/vaults" },
      { label: "Curate", href: "/curate" },
      { label: "Leaderboard", href: "/curators" },
      { label: "AI signal", href: "/ai" },
    ],
  },
  {
    title: "Tools",
    links: [
      { label: "Swap", href: "/swap" },
      { label: "Faucet", href: "/faucet" },
      { label: "Portfolio", href: "/portfolio" },
    ],
  },
  {
    title: "Developers",
    links: [
      { label: "GitHub", href: REPO },
      { label: "Docs", href: `${REPO}/blob/main/docs/Rangefy.md` },
      { label: "Hook contract", href: explorerAddress(addresses.hook) ?? REPO },
    ],
  },
];

export function Footer() {
  return (
    <footer className="mt-24 border-t border-border">
      <div className="mx-auto grid max-w-[1200px] gap-10 px-4 py-12 md:grid-cols-[1.5fr_1fr_1fr_1fr]">
        <div>
          <Logo />
          <p className="mt-3 max-w-xs text-sm text-muted">AI-curated liquidity vaults on Uniswap v4.</p>
          <span className="mt-4 inline-flex items-center gap-2 rounded-full border border-border px-3 py-1 text-xs text-muted">
            <span className="h-1.5 w-1.5 rounded-full bg-range" /> {activeChain.name}
          </span>
        </div>
        {COLS.map((c) => (
          <div key={c.title}>
            <div className="text-sm font-semibold">{c.title}</div>
            <ul className="mt-3 space-y-2 text-sm text-muted">
              {c.links.map((l) => (
                <li key={l.label}>
                  {l.href.startsWith("http") ? (
                    <a href={l.href} target="_blank" rel="noreferrer" className="hover:text-foreground">{l.label}</a>
                  ) : (
                    <Link href={l.href} className="hover:text-foreground">{l.label}</Link>
                  )}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="border-t border-border py-5 text-center text-xs text-muted">
        Built for the Uniswap Hook Incubator Hookathon · Testnet only, unaudited
      </div>
    </footer>
  );
}
