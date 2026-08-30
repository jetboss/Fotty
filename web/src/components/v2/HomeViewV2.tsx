"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { FottyAPI, type ScrapedMatch } from "@/lib/api";
import { useMatchFeedPoll } from "@/hooks/use-match-feed-poll";
import { matchKey } from "@/lib/live";
import { matchFeedSignature, mergeFreshMatchFeed } from "@/lib/match-feed-signature";
import {
  liveNowRail,
  matchdayKickoffRail,
  myTeamsRail,
  pickHeroMatch,
  tonightRail,
} from "@/lib/v2/home-feed";
import { enrichMatchesWithPosters } from "@/lib/v2/match-posters";
import { v2AppPath, v2HomePath } from "@/lib/v2/preview";
import { useTrackedTeams } from "@/lib/user-experience";
import { fixtureTeamLabels } from "@/lib/fixture-normalization";
import { PullToRefresh } from "@/components/PullToRefresh";
import { FeedStatusBanner } from "@/components/FeedStatusBanner";
import { HeroEmpty, HeroMatch } from "@/components/v2/HeroMatch";
import { HorizontalRail } from "@/components/v2/HorizontalRail";
import { OnNowGlance } from "@/components/v2/OnNowGlance";
import { PosterCard } from "@/components/v2/PosterCard";
import { V2PageShell } from "@/components/v2/V2PageShell";

import { SportFilterPills } from "@/components/v2/SportFilterPills";
import { matchMatchesSport, type SportFilterId } from "@/lib/v2/sport-filter";

interface HomeViewV2Props {
  initialMatches?: ScrapedMatch[];
}

export function HomeViewV2({ initialMatches = [] }: HomeViewV2Props) {
  const homeReturn = v2HomePath();
  const { trackedTeams } = useTrackedTeams();
  const [matches, setMatches] = useState(initialMatches);
  const [selectedSport, setSelectedSport] = useState<SportFilterId>("all");
  const [loading, setLoading] = useState(initialMatches.length === 0);
  const [feedStatus, setFeedStatus] = useState<"ok" | "stale" | "error">("ok");
  const [hoveredMatch, setHoveredMatch] = useState<ScrapedMatch | null>(null);

  const posterSources = useMemo(
    () => matches.filter((match) => Boolean(match.poster?.trim())),
    [matches]
  );

  const boardMatches = useMemo(
    () => enrichMatchesWithPosters(matches, posterSources),
    [matches, posterSources]
  );

  const filteredMatches = useMemo(() => {
    if (selectedSport === "all") return boardMatches;
    return boardMatches.filter((match) => matchMatchesSport(match, selectedSport));
  }, [boardMatches, selectedSport]);

  const applyMatches = useCallback((data: ScrapedMatch[]) => {
    let changed = false;
    setMatches((prev) => {
      const merged = mergeFreshMatchFeed(prev, data);
      if (matchFeedSignature(prev) === matchFeedSignature(merged)) return prev;
      changed = true;
      setFeedStatus("ok");
      return merged;
    });
    return changed;
  }, []);

  const silentRefresh = useCallback(async () => {
    try {
      const data = await FottyAPI.fetchMatchesFresh();
      if (data.length > 0) {
        return applyMatches(data);
      }
      setFeedStatus((prev) => (prev === "ok" ? "stale" : prev));
      return false;
    } catch {
      setFeedStatus((prev) => (prev === "ok" ? "stale" : "error"));
      return false;
    }
  }, [applyMatches]);

  const { markUpdated } = useMatchFeedPoll(silentRefresh, 45_000, true);

  useEffect(() => {
    if (initialMatches.length > 0) {
      setLoading(false);
      return;
    }
    setLoading(true);
    FottyAPI.fetchMatchesFresh()
      .then((data) => {
        if (data.length > 0) {
          applyMatches(data);
        } else {
          setFeedStatus("stale");
        }
      })
      .catch(() => setFeedStatus("error"))
      .finally(() => setLoading(false));
  }, [applyMatches, initialMatches.length]);

  const hero = useMemo(
    () => pickHeroMatch(filteredMatches, trackedTeams),
    [filteredMatches, trackedTeams]
  );
  const heroKey = hero ? matchKey(hero) : null;

  const liveRail = useMemo(() => liveNowRail(filteredMatches, heroKey), [filteredMatches, heroKey]);
  const teamsRail = useMemo(
    () => myTeamsRail(filteredMatches, trackedTeams, heroKey),
    [filteredMatches, heroKey, trackedTeams]
  );
  const tonight = useMemo(() => tonightRail(filteredMatches, heroKey), [filteredMatches, heroKey]);

  const matchdayRail = useMemo(() => {
    const exclude = new Set<string>();
    for (const match of [...liveRail, ...teamsRail, ...tonight]) {
      exclude.add(matchKey(match));
    }
    const thinBoard = liveRail.length === 0 && teamsRail.length === 0 && tonight.length < 4;
    if (!thinBoard) return [];
    return matchdayKickoffRail(filteredMatches, heroKey, exclude);
  }, [filteredMatches, heroKey, liveRail, teamsRail, tonight]);

  const glowMatch = hoveredMatch || hero;
  const glowMatchLabels = useMemo(() => {
    if (!glowMatch) return null;
    return fixtureTeamLabels(glowMatch);
  }, [glowMatch]);

  if (loading) {
    return (
      <V2PageShell fullBleed>
        <div className="relative z-10 mx-auto max-w-[1440px] px-4 py-6 space-y-8 lg:px-6">
          <div className="animate-pulse bg-white/[0.07] h-64 w-full rounded-2xl sm:h-80" />
          <div className="animate-pulse bg-white/[0.07] h-14 w-full rounded-xl" />
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
            {[0, 1, 2, 3].map((item) => (
              <div key={item} className="animate-pulse bg-white/[0.07] h-48 w-full rounded-xl" />
            ))}
          </div>
        </div>
      </V2PageShell>
    );
  }

  return (
    <PullToRefresh
      onRefresh={async () => {
        await silentRefresh();
        markUpdated();
      }}
    >
      <V2PageShell
        fullBleed
        glowHome={glowMatchLabels?.home}
        glowAway={glowMatchLabels?.away}
      >
        {feedStatus === "error" ? (
          <div className="relative z-20 px-4 lg:px-6">
            <FeedStatusBanner
              tone="error"
              title="Match feed unavailable"
              message="Fotty could not refresh live fixtures. Pull to refresh, or open the iOS app for the fullest match-day experience."
              onRetry={() => {
                setFeedStatus("ok");
                void silentRefresh();
              }}
            />
          </div>
        ) : feedStatus === "stale" ? (
          <div className="relative z-20 px-4 lg:px-6">
            <FeedStatusBanner
              tone="warning"
              title="Showing last loaded fixtures"
              message="A fresh refresh failed, so kickoff times and live badges may be out of date."
              onRetry={() => {
                setFeedStatus("ok");
                void silentRefresh();
              }}
            />
          </div>
        ) : null}

        {hero ? (
          <HeroMatch match={hero} returnTo={homeReturn} />
        ) : (
          <HeroEmpty trackedCount={trackedTeams.length} />
        )}

        <div className="relative z-20 mx-auto max-w-[1440px] pt-4 space-y-3">
          <SportFilterPills
            selectedSport={selectedSport}
            onSelectSport={setSelectedSport}
          />
          <OnNowGlance matches={filteredMatches} trackedTeams={trackedTeams} returnTo={homeReturn} />
        </div>

        <div className="relative z-10 mx-auto max-w-[1440px] -mt-2 space-y-8 py-6">
          {liveRail.length === 0 && teamsRail.length === 0 && tonight.length === 0 && matchdayRail.length === 0 ? (
            <div className="px-4 py-12 text-center">
              <p className="text-base font-semibold text-white">No fixtures found for this sport right now.</p>
              <p className="mt-1 text-xs text-text-tertiary">Switch to All Sports or check the Schedule for upcoming games.</p>
              <button
                type="button"
                onClick={() => setSelectedSport("all")}
                className="mt-4 rounded-full bg-white px-4 py-2 text-xs font-bold text-zinc-950 transition hover:bg-white/90"
              >
                View all sports
              </button>
            </div>
          ) : null}

          {liveRail.length > 0 ? (
            <HorizontalRail title="Live now" subtitle="Streaming now on Fotty">
              {liveRail.map((match) => (
                <PosterCard
                  key={matchKey(match)}
                  match={match}
                  returnTo={homeReturn}
                  onHover={(hovered) => setHoveredMatch(hovered ? match : null)}
                />
              ))}
            </HorizontalRail>
          ) : null}

          {teamsRail.length > 0 ? (
            <HorizontalRail
              title="Your teams"
              subtitle="Watchable matches for clubs you follow"
              href={v2AppPath("/teams")}
            >
              {teamsRail.map((match) => (
                <PosterCard
                  key={matchKey(match)}
                  match={match}
                  returnTo={homeReturn}
                  onHover={(hovered) => setHoveredMatch(hovered ? match : null)}
                />
              ))}
            </HorizontalRail>
          ) : null}

          {tonight.length > 0 ? (
            <HorizontalRail
              title="Tonight"
              subtitle="Kickoffs in the next 24 hours"
              href={v2AppPath("/schedule")}
              actionLabel="Full calendar"
            >
              {tonight.map((match) => (
                <PosterCard
                  key={matchKey(match)}
                  match={match}
                  returnTo={homeReturn}
                  onHover={(hovered) => setHoveredMatch(hovered ? match : null)}
                />
              ))}
            </HorizontalRail>
          ) : null}

          {matchdayRail.length > 0 ? (
            <HorizontalRail
              title="Matchday"
              subtitle="More kickoffs today"
              href={v2AppPath("/schedule")}
              actionLabel="Schedule"
            >
              {matchdayRail.map((match) => (
                <PosterCard
                  key={matchKey(match)}
                  match={match}
                  returnTo={homeReturn}
                  onHover={(hovered) => setHoveredMatch(hovered ? match : null)}
                />
              ))}
            </HorizontalRail>
          ) : null}
        </div>
      </V2PageShell>
    </PullToRefresh>
  );
}
