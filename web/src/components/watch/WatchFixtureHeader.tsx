"use client";

import type { WatchMatchContext } from "@/lib/stream-guide/match-context";
import type { ScrapedMatch } from "@/lib/api";
import { estimateMatchClock } from "@/lib/match-clock";
import { fixtureTeamLabels } from "@/lib/fixture-normalization";
import { TeamBadge } from "@/components/TeamBadge";
import { cn } from "@/lib/utils";

interface WatchFixtureHeaderProps {
  match?: ScrapedMatch | null;
  context: WatchMatchContext;
  hideScores?: boolean;
  className?: string;
  now?: number;
}

export function WatchFixtureHeader({ match, context, hideScores = false, className, now }: WatchFixtureHeaderProps) {
  const labels = match ? fixtureTeamLabels(match) : { home: context.homeName, away: context.awayName, homeBadge: undefined, awayBadge: undefined, isUpdating: false };
  const clock = estimateMatchClock({
    startsAt: match?.startsAt || undefined,
    sport: context.sport || match?.sport,
    apiStatus: match?.status,
    now,
  });
  const showScore = context.score && !hideScores && (context.status === "live" || context.status === "finished");
  const scoreText = showScore ? `${context.score!.home} – ${context.score!.away}` : "vs";
  const meta = [context.league, clock || context.kickoffLabel, context.statusLabel]
    .filter(Boolean)
    .join(" · ");

  return (
    <section className={cn("border-b border-white/[0.06] bg-[var(--v2-background)] px-4 py-4", className)}>
      <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3">
        <TeamBlock name={labels.home} badge={labels.homeBadge} align="left" />
        <div className="min-w-[4.5rem] text-center">
          <p className="text-2xl font-bold tabular-nums text-white">{scoreText}</p>
          {meta ? <p className="mt-1 line-clamp-2 text-[10px] font-medium text-text-tertiary">{meta}</p> : null}
        </div>
        <TeamBlock name={labels.away} badge={labels.awayBadge} align="right" />
      </div>
    </section>
  );
}

function TeamBlock({
  name,
  badge,
  align,
}: {
  name: string;
  badge?: string;
  align: "left" | "right";
}) {
  return (
    <div className={cn("flex min-w-0 flex-col gap-2", align === "right" ? "items-end text-right" : "items-start")}>
      <TeamBadge name={name} badge={badge} size={40} />
      <span className="line-clamp-2 text-xs font-semibold leading-snug text-white">{name}</span>
    </div>
  );
}
