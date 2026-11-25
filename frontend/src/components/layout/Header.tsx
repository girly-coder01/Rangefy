"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { Logo } from "./Logo";
import { cn } from "@/lib/cn";

const NAV = [
  { href: "/vaults", label: "Vaults" },
  { href: "/curate", label: "Curate" },
  { href: "/curators", label: "Leaderboard" },
  { href: "/ai", label: "AI Signal" },
  { href: "/swap", label: "Swap" },
  { href: "/faucet", label: "Faucet" },
  { href: "/portfolio", label: "Portfolio" },
];

export function Header() {
  const pathname = usePathname();
  const { resolvedTheme, setTheme } = useTheme();

  return (
    <header className="sticky top-0 z-40 border-b border-border bg-background/80 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-[1200px] items-center gap-6 px-4">
        <Link href="/" aria-label="Rangefy home">
          <Logo />
        </Link>
        <nav className="hidden flex-1 items-center gap-1 lg:flex" aria-label="Main">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              className={cn(
                "rounded-md px-3 py-2 text-sm text-muted transition-colors hover:text-foreground",
                pathname.startsWith(n.href) && "text-foreground",
              )}
            >
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <button
            type="button"
            aria-label="Toggle theme"
            onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
            className="rounded-md p-2 text-muted hover:text-foreground"
          >
            <Sun size={18} className="hidden dark:block" />
            <Moon size={18} className="dark:hidden" />
          </button>
          <ConnectButton chainStatus="icon" showBalance={false} />
        </div>
      </div>
      <nav className="flex gap-1 overflow-x-auto px-4 pb-2 lg:hidden" aria-label="Main mobile">
        {NAV.map((n) => (
          <Link
            key={n.href}
            href={n.href}
            className={cn("whitespace-nowrap rounded-md px-3 py-1.5 text-sm text-muted", pathname.startsWith(n.href) && "text-foreground")}
          >
            {n.label}
          </Link>
        ))}
      </nav>
    </header>
  );
}
