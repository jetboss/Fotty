"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Search, X } from "lucide-react";
import { FottyAPI, type ScrapedMatch } from "@/lib/api";
import { buildWatchHref, canOpenBroadcast, formatKickoff, matchKey } from "@/lib/live";
import { fixtureDisplayTitle } from "@/lib/fixture-normalization";
import { fottyFeedCountShort } from "@/lib/watch-stream-display";
import {
  discoverLiveRail,
  discoverSportRails,
  discoverStartingSoonRail,
  discoverUpcomingRail,
} from "@/lib/v2/discover-feed";
import { enrichMatchesWithPosters } from "@/lib/v2/match-posters";
import { dedupeMatches, searchMatches } from "@/lib/v2/search";
import { PullToRefresh } from "@/components/PullToRefresh";
import { TeamBadge } from "@/components/TeamBadge";
import { HorizontalRail } from "@/components/v2/HorizontalRail";
import { PosterCard } from "@/components/v2/PosterCard";
import { V2PageShell } from "@/components/v2/V2PageShell";
import { cn } from "@/lib/utils";

import { v2SchedulePath, v2SearchPath } from "@/lib/v2/preview";

import { SPORT_FILTER_PILLS, matchMatchesSport, type SportFilterId } from "@/lib/v2/sport-filter";

function fixturesOnly(matches: ScrapedMatch[]) {
  return matches.filter((match) => match.kind === "fixture" || Boolean(match.teams || match.eventSource));
}

interface DiscoverViewV2Props {
  initialIndex?: ScrapedMatch[];
}

export function DiscoverViewV2({ initialIndex = [] }: DiscoverViewV2Props) {
  const returnTo = v2SearchPath();
  const [query, setQuery] = useState("");
  const [selectedSport, setSelectedSport] = useState<SportFilterId>("all");
  const [index, setIndex] = useState(() => dedupeMatches(fixturesOnly(initialIndex)));
  const [loading, setLoading] = useState(initialIndex.length === 0);

  const reload = useCallback(async () => {
    try {
      const matches = await FottyAPI.fetchMatchesFresh();
      if (matches.length > 0) {
        setIndex(dedupeMatches(fixturesOnly(matches)));
      }
    } catch {
      // Keep existing index on transient error
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (initialIndex.length === 0) {
      void reload();
    }
    const interval = setInterval(() => {
      void reload();
    }, 45_000);
    return () => clearInterval(interval);
  }, [initialIndex.length, reload]);

  const posterSources = useMemo(
    () => index.filter((match) => Boolean(match.poster?.trim())),
    [index]
  );

  const browseIndex = useMemo(
    () => enrichMatchesWithPosters(index, posterSources),
    [index, posterSources]
  );

  const trimmed = query.trim();
  const filteredIndex = useMemo(() => {
    if (selectedSport === "all") return browseIndex;
    return browseIndex.filter((m) => matchMatchesSport(m, selectedSport));
  }, [browseIndex, selectedSport]);

  const searchResults = useMemo(() => searchMatches(filteredIndex, trimmed), [filteredIndex, trimmed]);
  const fixtureResults = searchResults.filter(
    (match) => match.kind === "fixture" || Boolean(match.teams || match.eventSource)
  );

  const liveRail = useMemo(() => discoverLiveRail(filteredIndex), [filteredIndex]);
  const liveKeys = useMemo(() => new Set(liveRail.map(matchKey)), [liveRail]);
  const startingSoonRail = useMemo(
    () => discoverStartingSoonRail(filteredIndex, liveKeys),
    [filteredIndex, liveKeys]
  );
  const startingSoonKeys = useMemo(() => {
    const keys = new Set(liveKeys);
    for (const match of startingSoonRail) keys.add(matchKey(match));
    return keys;
  }, [liveKeys, startingSoonRail]);
  const upcomingRail = useMemo(
    () => discoverUpcomingRail(filteredIndex, startingSoonKeys),
    [filteredIndex, startingSoonKeys]
  );
  const upcomingKeys = useMemo(() => {
    const keys = new Set(startingSoonKeys);
    for (const match of upcomingRail) keys.add(matchKey(match));
    return keys;
  }, [startingSoonKeys, upcomingRail]);
  const sportRails = useMemo(
    () => discoverSportRails(filteredIndex, upcomingKeys),
    [filteredIndex, upcomingKeys]
  );

  return (
    <PullToRefresh onRefresh={reload}>
      <V2PageShell fullBleed>
        <div className="sticky top-11 z-20 border-b border-white/[0.06] bg-[var(--v2-background)]/90 px-4 py-3 backdrop-blur-xl lg:top-0">
          <div className="mx-auto flex max-w-[1440px] flex-col gap-2.5">
            <div className="flex min-w-0 flex-1 items-center gap-3 rounded-full border border-white/10 bg-white/[0.04] px-4 py-2.5">
              <Search size={18} className="shrink-0 text-text-tertiary" />
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Teams, leagues, fixtures…"
                className="min-w-0 flex-1 bg-transparent text-sm text-white outline-none placeholder:text-text-tertiary"
                aria-label="Search Fotty"
              />
              {query ? (
                <button
                  type="button"
                  onClick={() => setQuery("")}
                  className="text-text-tertiary hover:text-white"
                  aria-label="Clear search"
                >
                  <X size={16} />
                </button>
              ) : null}
            </div>

            {/* Quick Sport Filter Pills */}
            <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5 scrollbar-none">
              {SPORT_FILTER_PILLS.map((pill) => {
                const isActive = selectedSport === pill.id;
                return (
                  <button
                    key={pill.id}
                    type="button"
                    onClick={() => setSelectedSport(pill.id)}
                    className={cn(
                      "inline-flex shrink-0 items-center gap-1 rounded-full px-3.5 py-1 text-xs font-bold transition",
                      isActive
                        ? "bg-white text-black shadow-sm"
                        : "border border-white/10 bg-white/[0.04] text-zinc-400 hover:border-white/20 hover:text-white"
                    )}
                  >
                    <span>{pill.emoji}</span>
                    <span>{pill.label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        <div className="mx-auto max-w-[1440px] space-y-10 py-8">
          {trimmed ? (
            <div className="space-y-8 px-4 lg:px-6">
              {fixtureResults.length > 0 ? (
                <section className="space-y-3">
                  <h2 className="text-lg font-semibold text-white">Matches</h2>
                  <ul className="space-y-2">
                    {fixtureResults.map((match) => (
                      <DiscoverRow key={matchKey(match)} match={match} returnTo={returnTo} />
                    ))}
                  </ul>
                </section>
              ) : (
                <p className="rounded-2xl border border-dashed border-white/10 px-6 py-12 text-center text-sm text-text-tertiary">
                  No results for &ldquo;{trimmed}&rdquo;. Try a team or league name.
                </p>
              )}
            </div>
          ) : loading && index.length === 0 ? (
            <div className="flex justify-center py-20">
              <div className="h-8 w-8 animate-spin rounded-full border-2 border-white/20 border-t-white" />
            </div>
          ) : (
            <>
              {liveRail.length > 0 ? (
                <HorizontalRail title="Live now" subtitle="Matches in play right now">
                  {liveRail.map((match) => (
                    <PosterCard key={matchKey(match)} match={match} returnTo={returnTo} />
                  ))}
                </HorizontalRail>
              ) : null}

              {startingSoonRail.length > 0 ? (
                <HorizontalRail title="Starting soon" subtitle="Next few hours" href={v2SchedulePath()} actionLabel="Calendar">
                  {startingSoonRail.map((match) => (
                    <PosterCard key={matchKey(match)} match={match} returnTo={returnTo} />
                  ))}
                </HorizontalRail>
              ) : null}

              {upcomingRail.length > 0 ? (
                <HorizontalRail title="Coming up" subtitle="Next 48 hours" href={v2SchedulePath()} actionLabel="Calendar">
                  {upcomingRail.map((match) => (
                    <PosterCard key={matchKey(match)} match={match} returnTo={returnTo} />
                  ))}
                </HorizontalRail>
              ) : null}

              {selectedSport === "all" && sportRails.map((rail) => (
                <HorizontalRail key={rail.sport} title={rail.sport}>
                  {rail.matches.map((match) => (
                    <PosterCard key={matchKey(match)} match={match} returnTo={returnTo} />
                  ))}
                </HorizontalRail>
              ))}

              {selectedSport !== "all" && filteredIndex.length > 0 && liveRail.length === 0 && startingSoonRail.length === 0 && upcomingRail.length === 0 ? (
                <div className="space-y-4 px-4 lg:px-6">
                  <h2 className="text-lg font-semibold text-white">All Fixtures</h2>
                  <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
                    {filteredIndex.map((match) => (
                      <PosterCard key={matchKey(match)} match={match} returnTo={returnTo} />
                    ))}
                  </div>
                </div>
              ) : null}
            </>
          )}
        </div>
      </V2PageShell>
    </PullToRefresh>
  );
}

function DiscoverRow({ match, returnTo }: { match: ScrapedMatch; returnTo: string }) {
  const watchHref = buildWatchHref(match, returnTo);
  const canWatch = canOpenBroadcast(match);
  const home = match.teams?.home?.name;
  const away = match.teams?.away?.name;
  const subtitle = [match.sport || match.league, formatKickoff(match.startsAt), fottyFeedCountShort(match.sourceCount || match.sourceIds?.length || 1)]
    .filter(Boolean)
    .join(" · ");

  return (
    <li>
      <Link
        href={watchHref}
        className={cn(
          "flex items-center justify-between gap-4 rounded-2xl border border-white/[0.06] bg-white/[0.02] p-4 transition-colors hover:border-white/15 hover:bg-white/[0.05]",
          !canWatch && "opacity-80"
        )}
      >
        <div className="flex min-w-0 items-center gap-3">
          {home && away ? (
            <div className="flex -space-x-2">
              <TeamBadge name={home} badge={match.teams?.home?.badge} size={36} />
              <TeamBadge name={away} badge={match.teams?.away?.badge} size={36} />
            </div>
          ) : (
            <div className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-white/10 text-xs font-bold text-white">
              {(match.title || "FT").slice(0, 2).toUpperCase()}
            </div>
          )}
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">{fixtureDisplayTitle(match)}</p>
            <p suppressHydrationWarning className="truncate text-xs text-text-tertiary">{subtitle}</p>
          </div>
        </div>
        <span
          className={cn(
            "shrink-0 rounded-full px-3 py-1 text-xs font-bold",
            match.status === "Live"
              ? "bg-red-500/20 text-red-400"
              : canWatch
                ? "bg-white/10 text-white"
                : "text-text-tertiary"
          )}
        >
          {match.status === "Live" ? "Live" : "Watch"}
        </span>
      </Link>
    </li>
  );
}
