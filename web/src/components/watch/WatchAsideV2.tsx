"use client";

import Link from "next/link";
import { Compass, Radio } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import type { StreamSource } from "@/lib/stream-guide/types";
import { buildWatchHref, formatKickoff, isMatchLiveNow, matchKey } from "@/lib/live";
import { fixtureTeamLabels } from "@/lib/fixture-normalization";
import { v2AppPath } from "@/lib/v2/preview";
import { TeamBadge } from "@/components/TeamBadge";
import { WatchFeedChips } from "@/components/watch/WatchFeedChips";

interface WatchAsideV2Props {
  title: string;
  subtitle?: string;
  sources?: StreamSource[];
  selectedIndex?: number;
  onSelectFeed?: (index: number) => void;
  relatedMatches?: ScrapedMatch[];
  returnTo?: string;
  hideScores?: boolean;
}

export function WatchAsideV2({
  title,
  subtitle,
  sources = [],
  selectedIndex = 0,
  onSelectFeed,
  relatedMatches = [],
  returnTo = "/",
  hideScores = false,
}: WatchAsideV2Props) {
  const isFixtureAside = sources.length > 0 || relatedMatches.length > 0;

  return (
    <aside className="flex min-h-0 w-full flex-col border-white/[0.06] bg-[var(--v2-background)] lg:border-l">
      <div className="min-h-0 flex-1 overflow-y-auto p-4">
        {!isFixtureAside ? (
          <div className="mb-4">
            <span className="inline-flex items-center gap-1 rounded-full bg-white/10 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white">
              <Radio size={10} className="animate-pulse" />
              Live
            </span>
            <h2 className="mt-3 line-clamp-4 text-lg font-bold leading-snug text-white">{title}</h2>
            {subtitle ? <p className="mt-2 text-sm text-text-tertiary">{subtitle}</p> : null}
          </div>
        ) : null}

        {sources.length > 1 ? (
          <div className="space-y-2">
            <p className="text-[11px] font-medium uppercase tracking-wide text-text-tertiary">Feeds</p>
            <WatchFeedChips
              sources={sources}
              selectedIndex={selectedIndex}
              onSelect={onSelectFeed}
              layout="stack"
            />
          </div>
        ) : null}

        {relatedMatches.length > 0 ? (
          <div className="mt-5 space-y-2">
            <p className="text-[11px] font-medium uppercase tracking-wide text-text-tertiary">Same competition</p>
            <div className="space-y-2">
              {relatedMatches.map((match) => (
                <RelatedMatchRow key={matchKey(match)} match={match} returnTo={returnTo} hideScores={hideScores} />
              ))}
            </div>
          </div>
        ) : null}
      </div>

      <div className="shrink-0 border-t border-white/[0.06] p-4">
        <Link
          href={v2AppPath("/search")}
          className="inline-flex w-full items-center justify-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-4 py-2.5 text-xs font-semibold text-white transition hover:bg-white/10"
        >
          <Compass size={14} />
          Discover more
        </Link>
      </div>
    </aside>
  );
}

function RelatedMatchRow({
  match,
  returnTo,
  hideScores,
}: {
  match: ScrapedMatch;
  returnTo: string;
  hideScores: boolean;
}) {
  const labels = fixtureTeamLabels(match);
  const live = isMatchLiveNow(match);
  const score =
    match.score && !hideScores && live ? `${match.score.home}–${match.score.away}` : formatKickoff(match.startsAt) || "Soon";

  return (
    <Link
      href={buildWatchHref(match, returnTo)}
      className="flex items-center gap-3 rounded-xl border border-white/[0.06] bg-white/[0.03] px-3 py-2.5 transition hover:bg-white/[0.06]"
    >
      <div className="flex min-w-0 flex-1 items-center gap-2">
        <TeamBadge name={labels.home} badge={labels.homeBadge} size={28} />
        <span className="truncate text-[11px] font-medium text-text-tertiary">vs</span>
        <TeamBadge name={labels.away} badge={labels.awayBadge} size={28} />
        <span className="min-w-0 truncate text-xs font-semibold text-white">
          {labels.home} v {labels.away}
        </span>
      </div>
      <span className="shrink-0 text-xs font-bold tabular-nums text-text-secondary">{score}</span>
    </Link>
  );
}
