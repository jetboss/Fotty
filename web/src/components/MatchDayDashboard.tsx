"use client";

import Link from "next/link";
import { memo, useCallback, useMemo } from "react";
import { ArrowRight, CalendarClock, Radio, Search, ShieldCheck, Sparkles, Zap } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import { footballLeagueLabel } from "@/lib/football-leagues";
import { footballLeaguePersonalizationHint } from "@/lib/football-personalization";
import type { TrackedTeamEntry } from "@/lib/storage";
import { FootballLeagueBar } from "@/components/FootballLeagueBar";
import { FeedUpdatedBanner } from "@/components/FeedUpdatedBanner";
import { FeaturedMatchHero } from "@/components/FeaturedMatchHero";
import { HomeSearchCard } from "@/components/HomeSearchCard";
import { HomeFixtureList } from "@/components/home/HomeFixtureList";
import { DataRefreshState } from "@/components/FallbackState";
import { HomeHeadlinesPanel } from "@/components/home/HomeHeadlinesPanel";
import { LazyLeagueStatsColumn } from "@/components/home/LazyLeagueStatsColumn";
import { MatchScoreboardCard } from "@/components/MatchScoreboardCard";
import { buildWatchHref, canOpenBroadcast, formatKickoff, isMatchLiveNow } from "@/lib/live";
import { cn } from "@/lib/utils";
import { fottyFeedCountShort } from "@/lib/watch-stream-display";

interface MatchDayDashboardProps {
  featuredMatch: ScrapedMatch | null;
  fixtureList: ScrapedMatch[];
  selectedLeague: FootballLeagueTab;
  leagueTabs: FootballLeagueTab[];
  trackedTeams: TrackedTeamEntry[];
  onSelectLeague: (league: FootballLeagueTab) => void;
  lastUpdated?: Date | null;
  highlightTeam?: string | null;
  onTeamHighlight?: (teamName: string) => void;
}

function MatchDayDashboardComponent({
  featuredMatch,
  fixtureList,
  selectedLeague,
  leagueTabs,
  trackedTeams,
  onSelectLeague,
  lastUpdated = null,
  highlightTeam = null,
  onTeamHighlight,
}: MatchDayDashboardProps) {
  const leagueHint = footballLeaguePersonalizationHint(trackedTeams);
  const boardStats = useMemo(() => buildBoardStats(fixtureList, featuredMatch), [featuredMatch, fixtureList]);
  const queueMatches = useMemo(() => fixtureList.slice(0, 4), [fixtureList]);
  const homePreviewMatches = useMemo(() => {
    const prioritized = fixtureList
      .filter((match) => match !== featuredMatch)
      .sort((left, right) => {
        return new Date(left.startsAt || 0).getTime() - new Date(right.startsAt || 0).getTime();
      });
    return prioritized.slice(0, 6);
  }, [featuredMatch, fixtureList]);
  const featuredTitle = featuredMatch?.displayTitle || featuredMatch?.title || "Match day is loading";
  const featuredKickoff = featuredMatch ? formatKickoff(featuredMatch.startsAt) : "";
  const featuredFeeds = featuredMatch ? fottyFeedCountShort(featuredMatch.sourceCount || featuredMatch.alternateCount || 0) : null;
  const featuredOpen = featuredMatch ? canOpenBroadcast(featuredMatch) : false;
  const handleClearHighlight = useCallback(() => {
    onTeamHighlight?.("");
  }, [onTeamHighlight]);

  return (
    <div className="mx-auto max-w-[1560px] space-y-5 px-md pb-6 pt-3 sm:pb-8 sm:pt-4">
      <section className="relative isolate overflow-hidden rounded-[2rem] border border-white/10 bg-background shadow-[0_30px_110px_rgba(0,0,0,0.7)]">
        <div className="absolute inset-0 -z-10 bg-[linear-gradient(115deg,rgba(224,31,71,0.26),transparent_28%,rgba(94,106,210,0.18)_62%,transparent)]" />
        <div className="absolute inset-0 -z-10 opacity-35 [background-image:linear-gradient(rgba(255,255,255,0.045)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.035)_1px,transparent_1px)] [background-size:72px_72px]" />
        <div className="fotty-cinema-sweep absolute inset-y-0 -left-1/3 -z-10 w-1/2 bg-gradient-to-r from-transparent via-white/10 to-transparent blur-2xl" />

        <div className="grid lg:min-h-[440px] lg:grid-cols-[minmax(0,0.88fr)_minmax(460px,1.12fr)]">
          <div className="relative flex flex-col justify-between p-5 sm:p-7 lg:min-h-[440px] lg:p-7">
            <div>
              <div className="mb-3 flex flex-wrap items-center gap-2">
                <span className="inline-flex items-center gap-2 rounded-full border border-amber-300/25 bg-amber-300/10 px-3 py-1.5 text-[10px] font-black uppercase tracking-wide text-amber-200 shadow-[0_0_24px_rgba(255,179,38,0.12)]">
                  <Radio size={13} className="animate-live-pulse" />
                  Fotty Match Hub
                </span>
                <span className="rounded-full border border-white/10 bg-white/[0.04] px-3 py-1.5 text-[10px] font-bold uppercase tracking-wide text-text-secondary backdrop-blur">
                  {footballLeagueLabel(selectedLeague)}
                </span>
                <FeedUpdatedBanner lastUpdated={lastUpdated} className="hidden sm:block" />
              </div>

              <p className="text-[10px] font-black uppercase tracking-[0.28em] text-[#8ea0ff] sm:text-[11px]">Live match operating system</p>
              <h1 className="mt-3 max-w-xl text-[2.55rem] font-black leading-[0.94] text-white sm:text-6xl lg:text-[3.8rem] xl:text-[4.15rem]">
                Stop searching. Start watching.
              </h1>
              <p className="mt-3 max-w-lg text-sm font-medium leading-6 text-[#a4abb8] sm:text-[15px] sm:leading-6">
                Fotty keeps live fixtures, backup feeds, reminders, and match-day updates in one clean sports hub.
              </p>

              <div className="mt-4 flex flex-col gap-3 sm:mt-5 sm:flex-row">
                <Link
                  href="/search"
                  className="group inline-flex min-h-11 items-center justify-center gap-3 rounded-full bg-gradient-to-r from-accent to-rose-600 px-5 text-sm font-black text-white shadow-[0_20px_60px_rgba(224,31,71,0.32)] transition duration-300 hover:-translate-y-1 sm:min-h-12 sm:px-6"
                >
                  <span className="grid h-7 w-7 place-items-center rounded-full bg-white/18 sm:h-8 sm:w-8">
                    <Zap size={17} />
                  </span>
                  Discover matches
                  <ArrowRight size={18} className="transition group-hover:translate-x-1" />
                </Link>
                <Link
                  href="/schedule"
                  className="inline-flex min-h-11 items-center justify-center gap-2 rounded-full border border-white/12 bg-white/[0.05] px-5 text-sm font-black text-white backdrop-blur transition duration-300 hover:-translate-y-1 hover:border-white/22 hover:bg-white/[0.08] sm:min-h-12 sm:px-6"
                >
                  <CalendarClock size={18} />
                  View schedule
                </Link>
              </div>
            </div>

            <div className="mt-5 space-y-3 lg:mt-0">
              <div className="hidden grid-cols-2 gap-2 sm:grid sm:grid-cols-4">
                {boardStats.map((stat) => (
                  <BoardStat key={stat.label} {...stat} compact />
                ))}
              </div>

              <div className="hidden overflow-hidden rounded-2xl border border-white/8 bg-black/25 py-2 sm:block">
                <div className="fotty-match-ticker flex w-max gap-2 px-2">
                  {[...queueMatches, ...queueMatches].map((match, index) => (
                    <TickerPill key={`${match.id || match.cid}-${index}`} match={match} />
                  ))}
                </div>
              </div>
            </div>
          </div>

          <div className="relative flex min-h-[340px] flex-col border-t border-white/8 bg-background sm:min-h-[390px] lg:border-l lg:border-t-0">
            {featuredMatch ? (
              <>
                <FeaturedMatchHero match={featuredMatch} title={featuredTitle} className="absolute inset-0 min-h-full opacity-85" />
                <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(5,5,6,0.22),rgba(5,5,6,0.05)_42%,rgba(5,5,6,0.82)),linear-gradient(0deg,rgba(5,5,6,0.92),transparent_58%)]" />
                <div className="relative z-10 flex items-center justify-between gap-3 p-5">
                  <span className="rounded-full border border-white/12 bg-black/35 px-3 py-1.5 text-[10px] font-black uppercase tracking-wide text-white backdrop-blur">
                    Featured feed
                  </span>
                  <span className="rounded-full border border-amber-300/25 bg-amber-300/10 px-3 py-1.5 text-[10px] font-black uppercase tracking-wide text-amber-200 backdrop-blur">
                    {featuredFeeds || "Fotty Live"}
                  </span>
                </div>
                <div className="relative z-10 mt-auto p-5 sm:p-6">
                  <div className="max-w-xl">
                    <p className="text-[11px] font-black uppercase tracking-[0.24em] text-text-secondary">{featuredKickoff || featuredMatch.sport || "Ready"}</p>
                    <h2 className="mt-2 max-w-[82%] text-3xl font-black leading-[0.96] text-white sm:max-w-lg sm:text-4xl lg:text-[2.8rem]">{featuredTitle}</h2>
                  </div>
                  <div className="mt-3 grid gap-3 lg:grid-cols-[minmax(0,1fr)_150px] lg:items-end">
                    <MatchScoreboardCard match={featuredMatch} returnTo="/" layout="hero" actionLabel={featuredOpen ? "Watch" : "Open"} />
                    <div className="grid grid-cols-2 gap-2 lg:grid-cols-1">
                      <Link href="/search" className="rounded-2xl border border-white/10 bg-black/35 px-4 py-3 text-sm font-black text-white backdrop-blur transition hover:bg-white/10">
                        Discover
                      </Link>
                      <Link href="/schedule" className="rounded-2xl border border-accent/30 bg-accent/15 px-4 py-3 text-sm font-black text-accent backdrop-blur transition hover:bg-accent/20">
                        Schedule
                      </Link>
                    </div>
                  </div>
                </div>
              </>
            ) : (
              <div className="grid min-h-[420px] place-items-center p-5">
                <DataRefreshState
                  title="Live coverage is updating"
                  message="Fotty is refreshing the match board. Check Discover or Schedule for fixtures."
                  primaryAction={{ label: "Discover", href: "/search" }}
                  secondaryAction={{ label: "Schedule", href: "/schedule" }}
                  compact
                  className="w-full max-w-md bg-black/25"
                />
              </div>
            )}
          </div>
        </div>
      </section>

      <section>
        <aside className="rounded-[1.4rem] border border-white/10 bg-background/80 p-3 shadow-xl backdrop-blur">
          <div className="mb-2 flex items-center justify-between">
            <p className="text-[10px] font-black uppercase tracking-[0.18em] text-text-tertiary">Watch queue</p>
            <Sparkles size={14} className="text-accent" />
          </div>
          <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
            {queueMatches.length > 0 ? queueMatches.map((match) => (
              <QueueRow key={match.id || match.cid} match={match} />
            )) : (
              <div className="sm:col-span-2 xl:col-span-4">
                <DataRefreshState
                  title="Watch queue is quiet"
                  message="No verified fixtures match this filter right now. Widen the league filter or open Schedule."
                  primaryAction={{ label: "Schedule", href: "/schedule" }}
                  compact
                  inline
                />
              </div>
            )}
          </div>
        </aside>
      </section>

      <div className="xl:hidden">
        <HomeSearchCard />
      </div>

      <div className="rounded-2xl border border-white/10 bg-surface p-3">
        <div className="mb-2 flex items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-2">
            <Search size={14} className="shrink-0 text-text-tertiary" />
            <div className="min-w-0">
              <p className="text-[10px] font-black uppercase tracking-wide text-text-tertiary sm:text-[11px]">Competition lens</p>
              {leagueHint ? <p className="truncate text-[10px] font-medium text-text-tertiary">{leagueHint}</p> : null}
            </div>
          </div>
          <FeedUpdatedBanner lastUpdated={lastUpdated} className="sm:hidden" />
        </div>
        <FootballLeagueBar selected={selectedLeague} onSelect={onSelectLeague} tabs={leagueTabs} />
      </div>

      {highlightTeam ? (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-accent/25 bg-accent/10 px-3 py-2">
          <p className="text-xs font-medium text-text-primary">
            Showing fixtures for <span className="font-black text-white">{highlightTeam}</span>
          </p>
          <button type="button" onClick={handleClearHighlight} className="text-[10px] font-bold text-accent">
            Clear filter
          </button>
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-[minmax(0,300px)_minmax(0,1fr)_minmax(0,340px)]">
        <main className="order-1 min-w-0 space-y-4 md:col-span-2 xl:col-span-1 xl:col-start-2">
          <section>
            <div className="mb-3 flex items-end justify-between gap-3">
              <div>
                <h2 className="text-sm font-black uppercase tracking-wide text-text-primary">On the radar</h2>
                <p className="text-xs font-medium text-text-secondary">A short preview. Full list lives on Schedule.</p>
              </div>
              <Link href="/schedule" className="shrink-0 rounded-full border border-white/10 bg-white/[0.04] px-3 py-2 text-xs font-black text-text-secondary hover:text-white">
                View all
              </Link>
            </div>
            <HomeFixtureList
              matches={homePreviewMatches}
              emptyMessage="No priority fixtures in this filter."
              returnTo="/"
              highlightTeam={highlightTeam}
              onTeamClick={onTeamHighlight}
              layout="grid"
            />
          </section>
        </main>

        <aside className="order-2 space-y-4 md:col-span-1 xl:col-span-1 xl:col-start-1 xl:row-start-1">
          <HomeHeadlinesPanel trackedTeams={trackedTeams} />
          <div className="hidden xl:block">
            <HomeSearchCard />
          </div>
        </aside>

        <aside className="order-3 space-y-4 md:col-span-2 md:grid md:grid-cols-2 md:gap-4 md:space-y-0 xl:col-span-1 xl:col-start-3 xl:block xl:space-y-4">
          <LazyLeagueStatsColumn
            league={selectedLeague}
            highlightTeam={highlightTeam}
            onTeamClick={onTeamHighlight}
          />
        </aside>
      </div>
    </div>
  );
}

export const MatchDayDashboard = memo(MatchDayDashboardComponent);

function buildBoardStats(fixtures: ScrapedMatch[], featuredMatch: ScrapedMatch | null) {
  const matches = [featuredMatch, ...fixtures].filter(Boolean) as ScrapedMatch[];
  const now = Date.now();
  const live = matches.filter((match) => isMatchLiveNow(match, now)).length;
  const watchReady = matches.filter(canOpenBroadcast).length;
  const soon = matches.filter((match) => {
    if (!match.startsAt || isMatchLiveNow(match, now)) return false;
    const start = new Date(match.startsAt).getTime();
    return Number.isFinite(start) && start > now && start - now <= 2 * 60 * 60 * 1000;
  }).length;
  const feeds = matches.reduce((total, match) => total + Math.max(0, match.sourceCount || match.alternateCount || 0), 0);

  return [
    { label: "Live now", value: live, detail: "ready to watch", icon: Radio, tone: "live" as const },
    { label: "Watch-ready", value: watchReady, detail: "inside window", icon: ShieldCheck, tone: "ok" as const },
    { label: "Starting soon", value: soon, detail: "next 2 hours", icon: CalendarClock, tone: "soon" as const },
    { label: "Fotty feeds", value: feeds, detail: "available today", icon: Sparkles, tone: "accent" as const },
  ];
}

function BoardStat({
  label,
  value,
  detail,
  icon: Icon,
  tone,
  compact = false,
}: {
  label: string;
  value: number;
  detail: string;
  icon: typeof Radio;
  tone: "live" | "ok" | "soon" | "accent";
  compact?: boolean;
}) {
  return (
    <div className={cn("rounded-xl border border-white/8 bg-black/18", compact ? "px-2.5 py-2" : "px-3 py-2.5 sm:py-3")}>
      <div className="flex items-center justify-between gap-3">
        <p className="min-w-0 truncate text-[9px] font-black uppercase tracking-wide text-text-tertiary sm:text-[10px]">{label}</p>
        <span
          className={cn(
            "grid h-6 w-6 shrink-0 place-items-center rounded-full border sm:h-7 sm:w-7",
            tone === "live" && "border-live/25 bg-live/10 text-live",
            tone === "ok" && "border-emerald-400/25 bg-emerald-400/10 text-emerald-300",
            tone === "soon" && "border-amber-300/25 bg-amber-300/10 text-amber-300",
            tone === "accent" && "border-accent/25 bg-accent/10 text-accent"
          )}
        >
          <Icon size={13} />
        </span>
      </div>
      <div className="mt-1.5 flex items-baseline gap-1.5">
        <span className={cn("font-black tabular-nums text-white", compact ? "text-xl" : "text-xl sm:text-2xl")}>{value}</span>
        <span className={cn("min-w-0 font-bold text-text-tertiary", compact ? "hidden text-[11px] min-[420px]:block min-[420px]:truncate" : "truncate text-[11px] sm:text-xs")}>
          {detail}
        </span>
      </div>
    </div>
  );
}

function TickerPill({ match }: { match: ScrapedMatch }) {
  const live = isMatchLiveNow(match);
  const title = match.displayTitle || match.title;
  const meta = live ? "Live" : formatKickoff(match.startsAt);

  return (
    <span className="inline-flex h-9 min-w-[220px] items-center gap-2 rounded-full border border-white/8 bg-white/[0.04] px-3 text-[11px] font-black text-white">
      <span className={cn("h-2 w-2 rounded-full", live ? "animate-live-pulse bg-live" : "bg-accent")} />
      <span className="truncate">{title}</span>
      {meta ? <span className="ml-auto shrink-0 text-text-tertiary">{meta}</span> : null}
    </span>
  );
}

function QueueRow({ match }: { match: ScrapedMatch }) {
  const canOpen = canOpenBroadcast(match);
  const live = isMatchLiveNow(match);
  const title = match.displayTitle || match.title;
  const feedLabel = fottyFeedCountShort(match.sourceCount || match.alternateCount || 0);
  const meta = [live ? "Live" : formatKickoff(match.startsAt), feedLabel || match.sport || match.league].filter(Boolean).join(" / ");
  const body = (
    <>
      <span
        className={cn(
          "grid h-7 w-7 shrink-0 place-items-center rounded-full border",
          live ? "border-amber-300/25 bg-amber-300/10 text-amber-300" : "border-white/10 bg-white/[0.03] text-text-tertiary"
        )}
      >
        {live ? <Zap size={13} /> : <CalendarClock size={13} />}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-xs font-black text-white">{title}</span>
        <span className="mt-0.5 block truncate text-[10px] font-bold text-text-tertiary">{meta || "Fixture"}</span>
      </span>
      <ArrowRight size={14} className="shrink-0 text-text-tertiary" />
    </>
  );

  if (!canOpen) {
    return (
      <div className="flex items-center gap-2 rounded-lg border border-white/6 bg-black/20 px-2.5 py-2 opacity-70">
        {body}
      </div>
    );
  }

  return (
    <Link
      href={buildWatchHref(match, "/")}
      className="flex items-center gap-2 rounded-lg border border-white/6 bg-black/25 px-2.5 py-2 transition hover:border-accent/35 hover:bg-accent/10"
    >
      {body}
    </Link>
  );
}
