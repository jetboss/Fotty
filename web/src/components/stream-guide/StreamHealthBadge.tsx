"use client";

import { presentStreamHealth } from "@/lib/stream-guide/health";
import type { StreamHealthState } from "@/lib/stream-guide/types";
import { cn } from "@/lib/utils";

const STATE_STYLES: Record<StreamHealthState, string> = {
  excellent: "border-emerald-400/40 bg-emerald-500/15 text-emerald-200",
  good: "border-sky-400/40 bg-sky-500/15 text-sky-200",
  fair: "border-amber-400/40 bg-amber-500/15 text-amber-100",
  unstable: "border-orange-400/40 bg-orange-500/15 text-orange-100",
  offline: "border-white/10 bg-white/5 text-text-tertiary",
  checking: "border-accent/30 bg-accent/10 text-accent",
  unknown: "border-white/10 bg-white/5 text-text-secondary",
};

export function StreamHealthBadge({
  state,
  score,
  inferred,
  compact,
  className,
}: {
  state: StreamHealthState;
  score?: number | null;
  inferred?: boolean;
  compact?: boolean;
  className?: string;
}) {
  const health = presentStreamHealth(state, score ?? null, { inferred });
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full border font-bold uppercase tracking-wide",
        compact ? "px-2 py-0.5 text-[9px]" : "px-2.5 py-1 text-[10px]",
        STATE_STYLES[state],
        className
      )}
      title={health.userMessage}
    >
      {health.label}
      {inferred && !compact ? <span className="font-medium normal-case opacity-80">· est.</span> : null}
    </span>
  );
}
