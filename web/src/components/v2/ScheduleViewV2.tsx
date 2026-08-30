"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { FottyAPI, type ScrapedMatch } from "@/lib/api";
import { matchKey } from "@/lib/live";
import { isMatchLive, sortFixturesForDisplay } from "@/lib/v2/match-priority";
import { groupFixturesByDay } from "@/lib/v2/schedule-calendar";
import { enrichMatchesWithPosters } from "@/lib/v2/match-posters";
import { PullToRefresh } from "@/components/PullToRefresh";
import { HorizontalRail } from "@/components/v2/HorizontalRail";
import { PosterCard } from "@/components/v2/PosterCard";
import { TbdBracketCard } from "@/components/v2/TbdBracketCard";
import { V2PageHeader, V2PageShell, V2Section, v2ListRowClass, v2SurfaceClass } from "@/components/v2/V2PageShell";
import { isFixtureTeamsTbd } from "@/lib/fixture-normalization";
import { cn } from "@/lib/utils";

import { v2SchedulePath } from "@/lib/v2/preview";

function todayKey() {
  return new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function dayChipLabel(bucket: { key: string; label: string; weekday: string }) {
  if (bucket.key === todayKey()) return "Today";
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowKey = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(tomorrow);
  if (bucket.key === tomorrowKey) return "Tomorrow";
  return bucket.weekday.slice(0, 3);
}

import { SportFilterPills } from "@/components/v2/SportFilterPills";
import { matchMatchesSport, type SportFilterId } from "@/lib/v2/sport-filter";

export function ScheduleViewV2({ initialMatches = [] }: { initialMatches?: ScrapedMatch[] }) {
  const returnTo = v2SchedulePath();
  const [selectedSport, setSelectedSport] = useState<SportFilterId>("all");
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [matches, setMatches] = useState(initialMatches);

  const reload = useCallback(async () => {
    const data = await FottyAPI.fetchMatchesFresh();
    setMatches(data);
  }, []);

  useEffect(() => {
    if (initialMatches.length > 0) return;
    void reload();
  }, [initialMatches.length, reload]);

  const boardMatches = useMemo(() => {
    const posterSources = matches.filter((match) => Boolean(match.poster?.trim()));
    return enrichMatchesWithPosters(matches, posterSources);
  }, [matches]);

  const filteredMatches = useMemo(() => {
    if (selectedSport === "all") return boardMatches;
    return boardMatches.filter((match) => matchMatchesSport(match, selectedSport));
  }, [boardMatches, selectedSport]);

  const dayBuckets = useMemo(() => groupFixturesByDay(filteredMatches), [filteredMatches]);
  const bucketByKey = useMemo(() => new Map(dayBuckets.map((b) => [b.key, b])), [dayBuckets]);

  const liveMatches = useMemo(
    () => sortFixturesForDisplay(filteredMatches.filter((match) => isMatchLive(match))),
    [filteredMatches]
  );

  useEffect(() => {
    if (selectedKey && bucketByKey.has(selectedKey)) return;
    const today = todayKey();
    if (bucketByKey.has(today)) {
      setSelectedKey(today);
      return;
    }
    if (dayBuckets[0]) setSelectedKey(dayBuckets[0].key);
  }, [bucketByKey, dayBuckets, selectedKey]);

  const selectedDay = selectedKey ? bucketByKey.get(selectedKey) : undefined;
  const dayMatches = useMemo(
    () => (selectedDay ? sortFixturesForDisplay(selectedDay.matches) : []),
    [selectedDay]
  );

  return (
    <PullToRefresh onRefresh={reload}>
      <V2PageShell innerClassName="space-y-8">
        <div className="space-y-4">
          <V2PageHeader
            title="Schedule"
            subtitle="Upcoming kickoffs — watchable matches first"
          />
          <SportFilterPills
            selectedSport={selectedSport}
            onSelectSport={setSelectedSport}
            className="px-0 lg:px-0"
          />
        </div>

        {liveMatches.length > 0 ? (
          <HorizontalRail title="Live now" subtitle="Streaming now on Fotty">
            {liveMatches.map((match) => (
              <PosterCard key={`live-${matchKey(match)}`} match={match} returnTo={returnTo} />
            ))}
          </HorizontalRail>
        ) : null}

        {dayBuckets.length > 0 ? (
          <>
            <section className="space-y-3">
              <div className="no-scrollbar flex gap-2 overflow-x-auto pb-1">
                {dayBuckets.map((bucket) => {
                  const active = bucket.key === selectedKey;
                  return (
                    <button
                      key={bucket.key}
                      type="button"
                      onClick={() => setSelectedKey(bucket.key)}
                      className={cn(
                        "flex shrink-0 flex-col items-center rounded-xl px-4 py-2.5 text-left transition",
                        active
                          ? "bg-white text-zinc-950 shadow-[0_0_24px_-8px_rgba(255,255,255,0.35)]"
                          : cn(v2SurfaceClass, "text-white hover:border-white/12 hover:bg-[#111114]")
                      )}
                    >
                      <span className="text-xs font-semibold">{dayChipLabel(bucket)}</span>
                      <span className={cn("text-[10px]", active ? "text-zinc-600" : "text-text-tertiary")}>
                        {bucket.label}
                      </span>
                      <span
                        className={cn(
                          "mt-1 text-[10px] font-medium",
                          active ? "text-zinc-700" : "text-text-tertiary"
                        )}
                      >
                        {bucket.matches.length} {bucket.matches.length === 1 ? "match" : "matches"}
                      </span>
                    </button>
                  );
                })}
              </div>
            </section>

            <V2Section title={selectedDay ? `${selectedDay.weekday} · ${selectedDay.label}` : "Fixtures"}>
              {dayMatches.length > 0 ? (
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 2xl:grid-cols-3">
                  {dayMatches.map((match) =>
                    isFixtureTeamsTbd(match) ? (
                      <TbdBracketCard key={matchKey(match)} match={match} layout="fill" />
                    ) : (
                      <PosterCard
                        key={matchKey(match)}
                        match={match}
                        returnTo={returnTo}
                        layout="fill"
                      />
                    )
                  )}
                </div>
              ) : (
                <p className={cn(v2ListRowClass, "px-4 py-8 text-center text-sm text-text-tertiary")}>
                  No fixtures on this day in the Fotty feed.
                </p>
              )}
            </V2Section>
          </>
        ) : (
          <p className={cn(v2ListRowClass, "px-4 py-12 text-center text-sm text-text-tertiary")}>
            No upcoming fixtures in the feed right now. Check home for live matches.
          </p>
        )}
      </V2PageShell>
    </PullToRefresh>
  );
}
