"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Bell } from "lucide-react";
import { FottyAPI, ScrapedMatch } from "@/lib/api";
import { useMatchFeedPoll } from "@/hooks/use-match-feed-poll";
import { formatKickoff, hasStreameXPlayback, isMatchLiveNow, matchKey } from "@/lib/live";
import { matchFeedSignature, mergeFreshMatchFeed } from "@/lib/match-feed-signature";
import { buildReminderCalendarURL } from "@/lib/storage";
import { matchIncludesTeam, teamNamesMatch } from "@/lib/team-name-match";
import { useReminders, useTrackedTeams, useUserPreferences } from "@/lib/user-experience";
import { ErrorState, UpdatingState } from "@/components/FallbackState";
import { HomeArenaCard } from "./HomeArenaCard";
import { ReminderButton } from "./ReminderButton";
import { HomeSkeleton } from "./Skeleton";
import { SectionHeader } from "./SectionHeader";
import { FeedStatusBanner } from "./FeedStatusBanner";
import { clearFootballLeagueIndex, filterMatchesByLeagueTab } from "@/lib/football-league-index";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import { useFootballLeaguePreference } from "@/hooks/use-football-league-preference";
import { MatchDayDashboard } from "@/components/MatchDayDashboard";
import { PullToRefresh } from "@/components/PullToRefresh";
import { useLoadingTimeout } from "@/hooks/use-loading-timeout";
interface HomeViewProps {
  initialMatches?: ScrapedMatch[];
}

export function HomeView({ initialMatches }: HomeViewProps) {
  const router = useRouter();
  const { preferences } = useUserPreferences();
  const { reminders } = useReminders();
  const { trackedTeams } = useTrackedTeams();
  const hasInitialMatches = initialMatches !== undefined;
  const [matches, setMatches] = useState<ScrapedMatch[]>(() => initialMatches ?? []);
  const [currentTime, setCurrentTime] = useState(() => Date.now());
  const [selectedFootballLeague, setSelectedFootballLeague, footballLeagueTabs] =
    useFootballLeaguePreference(trackedTeams, "all");
  const [highlightTeam, setHighlightTeam] = useState<string | null>(null);
  const [isPrimaryLoading, setIsPrimaryLoading] = useState(!hasInitialMatches);
  const [matchesLoaded, setMatchesLoaded] = useState(hasInitialMatches);
  const [feedStatus, setFeedStatus] = useState<"ok" | "stale" | "error">("ok");
  const loadingTimedOut = useLoadingTimeout(isPrimaryLoading, 12_000);

  const applyMatches = useCallback((matchData: ScrapedMatch[]): boolean => {
    let changed = false;
    setMatches((prev) => {
      const merged = mergeFreshMatchFeed(prev, matchData);
      if (matchFeedSignature(prev) === matchFeedSignature(merged)) return prev;
      changed = true;
      clearFootballLeagueIndex();
      return merged;
    });
    if (changed) {
      setFeedStatus(matchData.length === 0 ? "error" : "ok");
    }
    setMatchesLoaded(true);
    return changed;
  }, []);

  const reloadMatches = useCallback(() => {
    setIsPrimaryLoading(true);
    setFeedStatus("ok");
    return FottyAPI.fetchMatches()
      .then(applyMatches)
      .catch(() => setFeedStatus((initialMatches?.length ?? 0) > 0 ? "stale" : "error"))
      .finally(() => setIsPrimaryLoading(false));
  }, [applyMatches, initialMatches?.length]);

  const silentRefresh = useCallback((): Promise<boolean> => {
    return FottyAPI.fetchMatchesFresh()
      .then((matchData) => {
        const changed = applyMatches(matchData);
        if (matchData.length === 0) setFeedStatus("error");
        else setFeedStatus((status) => (status === "ok" ? status : "ok"));
        return changed;
      })
      .catch(() => {
        setFeedStatus((initialMatches?.length ?? 0) > 0 ? "stale" : "error");
        return false;
      });
  }, [applyMatches, initialMatches?.length]);

  const { lastUpdated, markUpdated } = useMatchFeedPoll(silentRefresh, 120_000, matchesLoaded);

  const refreshFromGesture = useCallback(async () => {
    await reloadMatches();
    markUpdated();
  }, [markUpdated, reloadMatches]);

  useEffect(() => {
    if (hasInitialMatches) {
      return;
    }

    let isMounted = true;
    FottyAPI.fetchMatches()
      .then((matchData) => {
        if (!isMounted) return;
        if (applyMatches(matchData)) markUpdated();
      })
      .catch(() => {
        if (!isMounted) return;
        setMatchesLoaded(false);
        setFeedStatus("error");
      })
      .finally(() => {
        if (isMounted) setIsPrimaryLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [applyMatches, hasInitialMatches, markUpdated]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      setCurrentTime(Date.now());
    }, 60_000);

    return () => window.clearInterval(interval);
  }, []);

  const leagueFilteredMatches = useMemo(
    () => filterMatchesByLeagueTab(matches, selectedFootballLeague),
    [matches, selectedFootballLeague]
  );

  const featuredMatch = useMemo(() => pickFeaturedMatch(leagueFilteredMatches), [leagueFilteredMatches]);
  const featuredKey = featuredMatch ? matchKey(featuredMatch) : null;

  const dashboardFixtures = useMemo(
    () =>
      orderFootballFirst(leagueFilteredMatches)
        .filter((match) => match.kind === "fixture" && matchKey(match) !== featuredKey)
        .slice(0, 12),
    [featuredKey, leagueFilteredMatches]
  );

  const visibleFixtures = useMemo(() => {
    if (!highlightTeam) return dashboardFixtures;
    return dashboardFixtures.filter((match) => matchIncludesTeam(match, highlightTeam));
  }, [dashboardFixtures, highlightTeam]);

  const trackedTeamMatches = useMemo(
    () =>
      orderFootballFirst(leagueFilteredMatches)
        .filter((match) => match.kind === "fixture" && matchKey(match) !== featuredKey && isTrackedTeamMatch(match, trackedTeams))
        .slice(0, 8),
    [featuredKey, leagueFilteredMatches, trackedTeams]
  );

  const reminderFocus = useMemo(() => {
    if (!preferences.matchReminders) return null;
    return (
      reminders.find((reminder) => {
        const kickoff = new Date(reminder.startsAt).getTime();
        return Number.isFinite(kickoff) && kickoff - currentTime <= 12 * 60 * 60 * 1000;
      }) || null
    );
  }, [currentTime, preferences.matchReminders, reminders]);

  const handleTeamHighlight = useCallback((teamName: string) => {
    if (!teamName.trim()) {
      setHighlightTeam(null);
      return;
    }
    setHighlightTeam((prev) => (prev && teamNamesMatch(prev, teamName) ? null : teamName));
  }, []);

  const handleSelectLeague = useCallback((league: FootballLeagueTab) => {
    setSelectedFootballLeague(league);
    setHighlightTeam(null);
  }, [setSelectedFootballLeague]);

  if (isPrimaryLoading && !loadingTimedOut) return <HomeSkeleton />;

  if (isPrimaryLoading && loadingTimedOut) {
    return (
      <div className="min-h-dvh bg-background p-md text-text-primary">
        <UpdatingState
          title="Match board is updating"
          message="Fotty is refreshing live fixtures and watch paths. Pull to refresh or try again in a moment."
          primaryAction={{ label: "Open Home", href: "/" }}
          secondaryAction={{ label: "Try Again", onClick: reloadMatches }}
          className="min-h-[60vh]"
        />
      </div>
    );
  }

  if (!matchesLoaded) {
    return (
      <div className="min-h-dvh bg-background text-text-primary">
        <ErrorState
          title="Match board is updating"
          message="Fotty could not refresh live fixtures from this device. Try again in a moment."
          primaryAction={{ label: "Retry", onClick: reloadMatches }}
          secondaryAction={{ label: "Discover", href: "/search" }}
          className="min-h-dvh"
        />
      </div>
    );
  }

  return (
    <PullToRefresh onRefresh={refreshFromGesture} className="min-h-dvh w-full min-w-0 overflow-x-hidden bg-background text-text-primary">
      {feedStatus !== "ok" && matchesLoaded && (
        <div className="px-md pt-4">
          <FeedStatusBanner
            tone={feedStatus === "error" ? "error" : "warning"}
            title={feedStatus === "error" ? "Match board unavailable" : "Showing last loaded fixtures"}
            message={
              feedStatus === "error"
                ? "Fotty could not load live fixtures. Check your connection and try again."
                : "A fresh refresh failed, so these cards may be out of date."
            }
            onRetry={reloadMatches}
          />
        </div>
      )}

      <MatchDayDashboard
        featuredMatch={featuredMatch}
        fixtureList={visibleFixtures}
        selectedLeague={selectedFootballLeague}
        leagueTabs={footballLeagueTabs}
        trackedTeams={trackedTeams}
        onSelectLeague={handleSelectLeague}
        lastUpdated={lastUpdated}
        highlightTeam={highlightTeam}
        onTeamHighlight={handleTeamHighlight}
      />

      <div className="space-y-xxl py-lg">
        {trackedTeams.length > 0 && (
          <section className="space-y-4">
            <SectionHeader
              title="For Your Teams"
              subtitle={trackedTeamMatches.length > 0 ? "Tracked clubs on the board" : "No tracked-team fixtures found yet"}
              onSeeAll={() => router.push("/teams")}
            />
            {trackedTeamMatches.length > 0 ? (
              <div className="no-scrollbar flex gap-md overflow-x-auto px-md">
                {trackedTeamMatches.map((match) => (
                  <div key={matchKey(match)} className="fotty-compact-stack w-[292px] shrink-0 space-y-3">
                    <HomeArenaCard match={match} returnTo="/" />
                    <ReminderButton match={match} returnTo="/" />
                  </div>
                ))}
              </div>
            ) : (
              <div className="px-md">
                <Link
                  href="/teams"
                  className="mx-auto flex max-w-5xl items-center justify-between gap-4 rounded-lg border border-white/5 bg-surface px-4 py-4 transition-colors hover:bg-surface-elevated"
                >
                  <div className="min-w-0">
                    <p className="text-sm font-black text-text-primary">
                      Tracking {trackedTeams.length} team{trackedTeams.length === 1 ? "" : "s"}
                    </p>
                    <p className="truncate text-xs font-medium text-text-secondary">
                      Fotty will surface their fixtures here when they appear.
                    </p>
                  </div>
                  <div className="shrink-0 rounded-full bg-white/5 px-3 py-2 text-xs font-black text-accent">Manage</div>
                </Link>
              </div>
            )}
          </section>
        )}

        {reminderFocus && (
          <section className="px-md">
            <div className="rounded-xl border border-live/20 bg-live/10 p-4">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="space-y-1">
                  <div className="inline-flex items-center gap-2 rounded-full border border-live/20 bg-live/10 px-3 py-1 text-[11px] font-bold text-live">
                    <Bell size={12} />
                    Reminder
                  </div>
                  <p className="pt-2 text-sm font-bold text-text-primary">{reminderFocus.title}</p>
                  <p className="text-xs font-medium leading-5 text-text-secondary">
                    {[reminderFocus.sport || reminderFocus.league || "Match day", formatKickoff(reminderFocus.startsAt)]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Link
                    href={reminderFocus.href}
                    className="inline-flex items-center rounded-full bg-white/5 px-4 py-2 text-xs font-bold text-text-primary"
                  >
                    Open match
                  </Link>
                  <a
                    href={buildReminderCalendarURL(reminderFocus)}
                    download={`${reminderFocus.title.replace(/[^a-z0-9]+/gi, "-").toLowerCase() || "fotty-reminder"}.ics`}
                    className="inline-flex items-center rounded-full border border-white/10 px-4 py-2 text-xs font-bold text-text-secondary"
                  >
                    Add to calendar
                  </a>
                </div>
              </div>
            </div>
          </section>
        )}
      </div>
    </PullToRefresh>
  );
}

function pickFeaturedMatch(matches: ScrapedMatch[]) {
  const fixtures = orderFootballFirst(matches.filter((match) => match.kind === "fixture"));
  const footballFixtures = fixtures.filter((match) => isFootballMatch(match));
  const liveFootball = footballFixtures.filter((match) => isMatchLiveNow(match) && hasStreameXPlayback(match));

  if (liveFootball.length) {
    return [...liveFootball].sort((left, right) => (left.startsAt || "").localeCompare(right.startsAt || ""))[0];
  }

  const watchableFootball = footballFixtures.filter((match) => hasStreameXPlayback(match));
  return (
    watchableFootball.find((match) => Boolean(match.poster || match.teams)) ||
    watchableFootball[0] ||
    footballFixtures.find((match) => Boolean(match.poster || match.teams)) ||
    footballFixtures[0] ||
    fixtures.find((match) => match.status === "Live" && Boolean(match.poster || match.teams)) ||
    fixtures.find((match) => Boolean(match.poster || match.teams)) ||
    fixtures[0] ||
    matches[0]
  );
}

function isFootballMatch(match: ScrapedMatch) {
  return match.sport === "Football" || match.categories?.includes("football");
}

function orderFootballFirst(matches: ScrapedMatch[]) {
  return [...matches].sort((left, right) => {
    const leftFootball = isFootballMatch(left) ? 1 : 0;
    const rightFootball = isFootballMatch(right) ? 1 : 0;
    if (leftFootball !== rightFootball) return rightFootball - leftFootball;
    return (right.rank || 0) - (left.rank || 0);
  });
}

function normalizedTeamName(value: string) {
  return value
    .normalize("NFD")
    .replace(/[øØ]/g, "o")
    .replace(/[æÆ]/g, "ae")
    .replace(/[åÅ]/g, "a")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function isTrackedTeamMatch(match: ScrapedMatch, trackedTeams: Array<{ name: string }>) {
  if (!match.teams || trackedTeams.length === 0) return false;
  const fixtureTeams = [match.teams.home.name, match.teams.away.name].map(normalizedTeamName);

  return trackedTeams.some((team) => {
    const trackedName = normalizedTeamName(team.name);
    if (!trackedName) return false;
    return fixtureTeams.some((fixtureName) => fixtureName === trackedName || fixtureName.includes(trackedName) || trackedName.includes(fixtureName));
  });
}
