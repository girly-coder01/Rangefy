import { formatUnits } from "viem";

const nf = (max: number, min = 0) =>
  new Intl.NumberFormat("en-US", { maximumFractionDigits: max, minimumFractionDigits: min });

export function fmtNum(n: number | undefined | null, digits = 2): string {
  if (n == null || !Number.isFinite(n)) return "—";
  const a = Math.abs(n);
  if (a >= 1e9) return `${nf(2).format(n / 1e9)}B`;
  if (a >= 1e6) return `${nf(2).format(n / 1e6)}M`;
  if (a >= 1e4) return `${nf(1).format(n / 1e3)}k`;
  if (a > 0 && a < 1 / 10 ** digits) return n.toExponential(1);
  return nf(digits).format(n);
}

export function fmtUsd(n: number | undefined | null, digits = 2): string {
  if (n == null || !Number.isFinite(n)) return "—";
  const a = Math.abs(n);
  if (a >= 1e4) return `$${fmtNum(n)}`;
  return `$${nf(digits, digits).format(n)}`;
}

export function fmtPct(n: number | undefined | null, digits = 2, signed = false): string {
  if (n == null || !Number.isFinite(n)) return "—";
  const s = `${nf(digits, digits).format(n * 100)}%`;
  return signed && n > 0 ? `+${s}` : s;
}

export function fmtToken(raw: bigint | undefined, decimals: number, digits = 4): string {
  if (raw == null) return "—";
  return fmtNum(Number(formatUnits(raw, decimals)), digits);
}

export const toFloat = (raw: bigint | undefined, decimals: number) =>
  raw == null ? 0 : Number(formatUnits(raw, decimals));

export const shortAddr = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");

export function fmtDuration(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)}h`;
  return `${Math.round(seconds / 86400)}d`;
}

export function timeAgo(ts: number): string {
  const s = Date.now() / 1000 - ts;
  return s < 5 ? "just now" : `${fmtDuration(s)} ago`;
}

export const fmtFeePips = (pips: number) => `${(pips / 10_000).toFixed(2)}%`;
export const fmtBps = (bps: number) => `${(bps / 100).toFixed(bps % 100 ? 1 : 0)}%`;
