"use client";

import type { WatchMatchContext } from "@/lib/stream-guide/match-context";
import { StreamHealthBadge } from "./StreamHealthBadge";
import type { StreamHealthState } from "@/lib/stream-guide/types";
import { cn } from "@/lib/utils";

export function MatchHeroHeader({
  context,
  streamHealth,
  streamHealthScore,
  inferredHealth,
  className,
  v2 = false,
}: {
  context: WatchMatchContext;
  streamHealth?: StreamHealthState;
  streamHealthScore?: number | null;
  inferredHealth?: boolean;
  className?: string;
  v2?: boolean;
}) {
  const showScore = context.score && context.status === "live";

  return (
    <section
      className={cn(
        "relative overflow-hidden rounded-lg border px-3 py-2.5 sm:rounded-2xl sm:px-4 sm:py-4",
        v2
          ? "border-white/[0.08] bg-[var(--v2-surface)]"
          : "border-white/10 bg-gradient-to-br from-[#12151f] via-surface to-background",
        className
      )}
    >
      {!v2 ? <HeroGlow /> : null}
      <div className="relative sm:hidden">
        <div className="flex items-center justify-between gap-2">
          <MetaRow context={context} compact />
          {streamHealth ? (
            <StreamHealthBadge state={streamHealth} score={streamHealthScore} inferred={inferredHealth} />
          ) : null}
        </div>
        <p className="mt-2 truncate text-sm font-black text-white">
          {context.homeName} <span className="text-text-tertiary">v</span> {context.awayName}
        </p>
      </div>

      <div className="relative hidden flex-col gap-3 sm:flex sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0 flex-1">
          <MetaRow context={context} />
          <div className="mt-3 flex items-center justify-start gap-4">
            <TeamBlock name={context.homeName} align="left" />
            <ScoreBlock showScore={Boolean(showScore)} score={context.score} statusLabel={context.statusLabel} />
            <TeamBlock name={context.awayName} align="right" />
          </div>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-2">
          {streamHealth ? (
            <StreamHealthBadge state={streamHealth} score={streamHealthScore} inferred={inferredHealth} />
          ) : null}
          <p className="text-[11px] font-medium text-text-tertiary">{context.streamAvailabilityLabel}</p>
        </div>
      </div>
    </section>
  );
}

function HeroGlow() {
  return <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(255,179,38,0.12),transparent_55%)]" />;
}

function MetaRow({ context, compact = false }: { context: WatchMatchContext; compact?: boolean }) {
  return (
    <div className="flex min-w-0 flex-wrap items-center gap-2">
      {context.league ? (
        <span className={cn(
          "rounded-full border border-white/10 bg-black/25 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-text-secondary",
          compact && "max-w-[12rem] truncate"
        )}>
          {context.league}
        </span>
      ) : null}
      <StatusPill status={context.status} label={context.statusLabel} />
      {context.kickoffLabel && !compact ? (
        <span className="text-[11px] font-medium text-text-tertiary">{context.kickoffLabel}</span>
      ) : null}
    </div>
  );
}

function StatusPill({ status, label }: { status: WatchMatchContext["status"]; label: string }) {
  const styles =
    status === "live"
      ? "border-live/40 bg-live/15 text-live"
      : status === "upcoming"
        ? "border-sky-400/30 bg-sky-500/10 text-sky-200"
        : status === "finished"
          ? "border-white/10 bg-white/5 text-text-tertiary"
          : "border-white/10 bg-white/5 text-text-secondary";

  return (
    <span className={cn("rounded-full border px-2.5 py-1 text-[10px] font-black uppercase tracking-wide", styles)}>
      {label}
    </span>
  );
}

function TeamBlock({ name, align }: { name: string; align: "left" | "right" }) {
  const code = name.substring(0, 3).toUpperCase();
  return (
    <div className={cn("min-w-0", align === "right" ? "text-right" : "text-left")}>
      <div
        className={cn(
          "mx-auto flex h-10 w-10 items-center justify-center rounded-full border border-white/10 bg-white/5 text-[10px] font-black text-white",
          align === "right" ? "sm:ml-auto" : "sm:mr-auto"
        )}
      >
        {code}
      </div>
      <p className="mt-2 max-w-[120px] truncate text-xs font-black text-text-primary">{name}</p>
    </div>
  );
}

function ScoreBlock({
  showScore,
  score,
  statusLabel,
}: {
  showScore: boolean;
  score?: { home: number; away: number };
  statusLabel: string;
}) {
  if (showScore && score) {
    return (
      <div className="text-center">
        <p className="text-2xl font-black tabular-nums text-text-primary">
          {score.home}
          <span className="mx-2 text-text-tertiary">-</span>
          {score.away}
        </p>
        <p className="mt-1 text-[10px] font-bold uppercase tracking-wide text-live">{statusLabel}</p>
      </div>
    );
  }

  return (
    <div className="text-center">
      <p className="text-sm font-black uppercase tracking-[0.2em] text-text-tertiary">vs</p>
      <p className="mt-1 text-[10px] font-bold uppercase text-text-secondary">{statusLabel}</p>
    </div>
  );
}
