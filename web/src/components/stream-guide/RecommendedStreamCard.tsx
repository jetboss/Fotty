"use client";

import { CheckCircle2, Play, Radio, RotateCcw } from "lucide-react";
import { presentStreamHealth } from "@/lib/stream-guide/health";
import { STREAM_GUIDE_COPY } from "@/lib/stream-guide/copy";
import type { StreamSource } from "@/lib/stream-guide/types";
import { StreamHealthBadge } from "./StreamHealthBadge";
import { cn } from "@/lib/utils";

function RecommendedStreamSkeleton({ className }: { className?: string }) {
  return (
    <div className={cn("rounded-2xl border border-white/10 bg-surface-elevated/80 p-4", className)}>
      <p className="text-[10px] font-bold uppercase tracking-wide text-text-tertiary">Checking stream health</p>
      <div className="mt-3 h-5 w-40 animate-pulse rounded bg-white/10" />
      <div className="mt-4 h-10 w-full animate-pulse rounded-xl bg-white/10" />
    </div>
  );
}

export function RecommendedStreamCard({
  source,
  isActive,
  isLoading,
  onWatch,
  className,
  v2 = false,
}: {
  source: StreamSource | null;
  isActive?: boolean;
  isLoading?: boolean;
  onWatch?: () => void;
  className?: string;
  v2?: boolean;
}) {
  if (isLoading) {
    return <RecommendedStreamSkeleton className={className} />;
  }

  if (!source) {
    return null;
  }

  const health = presentStreamHealth(source.status, source.healthScore, { inferred: source.inferredHealth });
  const canWatch = source.status !== "offline";

  return (
    <section
      className={cn(
        "relative overflow-hidden rounded-xl border bg-surface p-3 shadow-[0_12px_40px_rgba(0,0,0,0.22)]",
        isActive
          ? v2
            ? "border-white/20 bg-white/[0.04] ring-1 ring-white/10"
            : "border-accent/55 bg-accent/[0.06] ring-1 ring-accent/20"
          : "border-white/10",
        className
      )}
    >
      <div className="relative">
        <div className="flex items-start justify-between gap-3 sm:items-center">
          <div className="min-w-0 sm:flex sm:flex-1 sm:items-center sm:gap-3">
            <div className="min-w-0">
              <p className={cn(
                "inline-flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.14em] sm:tracking-wide",
                v2 ? "text-white/70" : "text-accent"
              )}>
                {isActive ? <CheckCircle2 size={12} /> : <Radio size={12} />}
                {isActive ? "Current stream" : STREAM_GUIDE_COPY.recommendedTitle}
              </p>
              <h3 className="mt-1 truncate text-lg font-black leading-tight text-text-primary sm:text-base">{source.displayName}</h3>
            </div>
            <div className="mt-2 flex flex-wrap items-center gap-2 sm:mt-0 sm:shrink-0">
              <StreamHealthBadge state={source.status} score={source.healthScore} inferred={source.inferredHealth} />
              <span className="rounded-full border border-white/10 bg-black/20 px-2.5 py-1 text-[10px] font-bold text-text-secondary">
                {source.quality}
              </span>
              <span className="rounded-full border border-white/10 bg-black/20 px-2.5 py-1 text-[10px] font-bold text-text-secondary">
                {source.requiresP2P ? "P2P" : source.streamType === "backup" ? "Backup" : "Direct"}
              </span>
            </div>
          </div>
          {onWatch ? (
            <button
              type="button"
              disabled={!canWatch}
              onClick={onWatch}
              className={cn(
                "inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-full px-4 py-2 text-sm font-black transition-transform active:scale-[0.98]",
                canWatch
                  ? v2
                    ? "bg-white text-zinc-950 shadow-lg shadow-black/20"
                    : "bg-accent text-white shadow-lg shadow-accent/25"
                  : "cursor-not-allowed bg-white/10 text-text-tertiary"
              )}
            >
              {canWatch ? <Play size={14} fill="currentColor" /> : <Radio size={14} />}
              {canWatch ? (isActive ? "Playing" : "Watch") : "Off"}
            </button>
          ) : null}
        </div>
        <p className="mt-2 max-w-3xl text-xs font-medium leading-5 text-text-secondary">
          {source.inferredHealth && !source.requiresP2P
            ? "This is an estimated best feed. If the provider video fails, use another backup below."
            : health.userMessage}
        </p>
        {source.whyThis ? (
          <p className="mt-1 hidden truncate text-[11px] font-medium text-text-tertiary sm:block">
            {source.inferredHealth && !source.requiresP2P
              ? "Estimated from feed signals. Provider playback can still fail."
              : health.userMessage}
          </p>
        ) : null}
        {!canWatch ? (
          <div className="mt-3 inline-flex items-center gap-2 rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-[11px] font-bold text-text-tertiary">
            <RotateCcw size={13} />
            Pick another source below
          </div>
        ) : null}
      </div>
    </section>
  );
}
