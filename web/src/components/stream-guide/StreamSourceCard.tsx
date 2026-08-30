"use client";

import { Check, HelpCircle, Radio } from "lucide-react";
import { presentStreamHealth } from "@/lib/stream-guide/health";
import type { StreamSource } from "@/lib/stream-guide/types";
import { StreamHealthBadge } from "./StreamHealthBadge";
import { cn } from "@/lib/utils";

export function StreamSourceCard({
  source,
  active,
  onSelect,
  className,
  compactMobile = false,
}: {
  source: StreamSource;
  active?: boolean;
  onSelect?: () => void;
  className?: string;
  compactMobile?: boolean;
}) {
  const health = presentStreamHealth(source.status, source.healthScore, { inferred: source.inferredHealth });
  const disabled = source.status === "offline";

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onSelect}
      className={cn(
        "min-w-[168px] rounded-xl border px-3 py-3 text-left transition-colors sm:min-w-0 sm:rounded-lg sm:px-3 sm:py-2 lg:min-w-0",
        compactMobile && "max-sm:rounded-lg max-sm:px-3 max-sm:py-2",
        active
          ? "border-accent/50 bg-accent/15"
          : "border-white/10 bg-surface hover:bg-surface-elevated",
        disabled && "cursor-not-allowed opacity-60",
        className
      )}
    >
      <div className="flex items-start justify-between gap-2 sm:items-center">
        <div className={cn("min-w-0 sm:flex sm:min-w-0 sm:flex-1 sm:items-center sm:gap-2", compactMobile && "max-sm:flex max-sm:min-w-0 max-sm:flex-1 max-sm:items-center max-sm:gap-2")}>
          <p className={cn("truncate text-xs font-black", active ? "text-white" : "text-text-primary")}>
            {source.displayName}
          </p>
          <div className={cn("mt-2 flex flex-wrap items-center gap-1.5 sm:mt-0", compactMobile && "max-sm:mt-0")}>
            <StreamHealthBadge state={source.status} score={source.healthScore} inferred={source.inferredHealth} compact />
          </div>
        </div>
        {active ? <Check size={14} className="shrink-0 text-accent" /> : <Radio size={13} className="shrink-0 text-text-tertiary" />}
      </div>
      <p className={cn("mt-2 truncate text-[11px] font-medium text-text-tertiary sm:mt-1", compactMobile && "max-sm:mt-1")}>
        {[source.quality, source.requiresP2P ? "P2P" : "Direct", source.language || "Live", source.viewers ? `${source.viewers} viewers` : undefined]
          .filter(Boolean)
          .join(" · ")}
      </p>
      {source.whyThis ? (
        <p className={cn("mt-2 flex items-start gap-1 text-[10px] font-medium leading-4 text-text-tertiary sm:hidden", compactMobile && "max-sm:hidden")} title={source.whyThis}>
          <HelpCircle size={11} className="mt-0.5 shrink-0" />
          <span className="line-clamp-2">{health.userMessage}</span>
        </p>
      ) : null}
    </button>
  );
}
