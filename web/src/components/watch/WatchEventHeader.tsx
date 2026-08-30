"use client";

import type { WatchMatchContext } from "@/lib/stream-guide/match-context";
import { eventSportLabel } from "@/lib/v2/fixture-display";
import { watchCompetitionSubtitle } from "@/lib/v2/watch-related-matches";
import type { ScrapedMatch } from "@/lib/api";
import { cn } from "@/lib/utils";

interface WatchEventHeaderProps {
  title: string;
  sport?: string;
  league?: string;
  match?: ScrapedMatch | null;
  context: WatchMatchContext;
  className?: string;
}

export function WatchEventHeader({
  title,
  sport,
  league,
  match,
  context,
  className,
}: WatchEventHeaderProps) {
  const sportLine = match ? eventSportLabel(match) : sport && sport.toLowerCase() !== "other" ? sport : "Live event";
  const meta = [sportLine, context.kickoffLabel, context.statusLabel].filter(Boolean).join(" · ");
  const competitionLine = watchCompetitionSubtitle(match, league);

  return (
    <section className={cn("border-b border-white/[0.06] bg-[var(--v2-background)] px-4 py-4", className)}>
      <div className="mx-auto max-w-3xl space-y-2 text-center">
        <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-text-tertiary">{sportLine}</p>
        <h2 className="text-lg font-semibold leading-snug tracking-tight text-white sm:text-xl">{title}</h2>
        {meta ? <p className="text-[11px] font-medium text-text-tertiary">{meta}</p> : null}
        {competitionLine ? <p className="text-[10px] text-text-tertiary">{competitionLine}</p> : null}
      </div>
    </section>
  );
}
