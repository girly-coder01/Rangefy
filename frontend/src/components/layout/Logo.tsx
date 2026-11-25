import { cn } from "@/lib/cn";


export function Logo({ className, markOnly = false }: { className?: string; markOnly?: boolean }) {
  return (
    <span className={cn("inline-flex items-center gap-3", className)}>
      <svg viewBox="0 0 64 64" className="h-8 w-8" role="img" aria-label="Rangefy">
        <rect x="8" y="14" width="8" height="40" rx="4" className="fill-range" />
        <rect x="48" y="10" width="8" height="40" rx="4" className="fill-range" />
        <path
          d="M4 40 C 16 40, 22 30, 32 30 S 48 22, 60 22"
          fill="none"
          className="stroke-accent"
          strokeWidth="4"
          strokeLinecap="round"
        />
        <circle cx="32" cy="30" r="5" className="fill-accent" />
      </svg>
      {!markOnly && (
        <span className="text-xl font-bold tracking-[-0.02em]">
          Range<span className="text-accent">fy</span>
        </span>
      )}
    </span>
  );
}
