"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowLeft, Radio, Search, Tv2, X } from "lucide-react";
import { FottyAPI, ScrapedMatch } from "@/lib/api";
import { buildWatchHref, canOpenBroadcast, matchKey } from "@/lib/live";
import { fottyFeedCountShort } from "@/lib/watch-stream-display";
import { EmptyState } from "@/components/EmptyState";
import { FeedStatusBanner } from "@/components/FeedStatusBanner";
import { PullToRefresh } from "@/components/PullToRefresh";
import { SectionHeader } from "@/components/SectionHeader";
import { TeamBadge } from "@/components/TeamBadge";

interface SearchPageClientProps {
  initialIndex?: ScrapedMatch[];
}

export default function SearchPageClient({ initialIndex }: SearchPageClientProps) {
  const router = useRouter();
  const hasInitialIndex = initialIndex !== undefined && initialIndex.length > 0;
  const [query, setQuery] = useState("");
  const [liveIndex, setLiveIndex] = useState<ScrapedMatch[]>(() => initialIndex ?? []);
  const [isIndexLoading, setIsIndexLoading] = useState(initialIndex === undefined);
  const [indexStatus, setIndexStatus] = useState<"ok" | "stale" | "error">(hasInitialIndex ? "ok" : "ok");
  const [hasSearched, setHasSearched] = useState(false);

  const reloadIndex = useCallback(() => {
    setIsIndexLoading(true);
    setIndexStatus("ok");
    return FottyAPI.fetchMatches()
      .then((matches) => {
        const next = dedupeMatches(matches);
        setLiveIndex(next);
        setIndexStatus(next.length === 0 ? "error" : "ok");
      })
      .catch(() => setIndexStatus(liveIndex.length > 0 ? "stale" : "error"))
      .finally(() => setIsIndexLoading(false));
  }, [liveIndex.length]);

  useEffect(() => {
    let isMounted = true;

    async function loadIndex() {
      setIsIndexLoading(true);

      try {
        const matches = await FottyAPI.fetchMatches();

        if (!isMounted) return;
        const next = dedupeMatches(matches);
        setLiveIndex(next);
        if (next.length === 0 && (initialIndex?.length || 0) > 0) {
          setIndexStatus("stale");
        } else if (next.length === 0) {
          setIndexStatus("error");
        } else {
          setIndexStatus("ok");
        }
      } catch {
        if (!isMounted) return;
        setIndexStatus((initialIndex?.length || 0) > 0 ? "stale" : "error");
      } finally {
        if (isMounted) setIsIndexLoading(false);
      }
    }

    loadIndex();
    return () => {
      isMounted = false;
    };
  }, [initialIndex?.length]);

  const liveResults = useMemo(() => {
    const trimmed = normalizeSearch(query);
    if (!trimmed) return [];

    return liveIndex
      .map((match) => ({ match, score: scoreMatch(match, trimmed) }))
      .filter((result) => result.score > 0)
      .sort((left, right) => right.score - left.score)
      .map((result) => result.match)
      .slice(0, 24);
  }, [liveIndex, query]);

  const fixtureResults = liveResults.filter((match) => match.kind === "fixture");
  const channelResults = liveResults.filter((match) => match.kind !== "fixture");
  const browseNow = useMemo(() => liveIndex.filter((match) => match.kind === "fixture").slice(0, 8), [liveIndex]);

  const showEmpty = hasSearched && fixtureResults.length === 0 && channelResults.length === 0;

  return (
    <PullToRefresh onRefresh={reloadIndex} className="min-h-dvh bg-background text-text-primary">
      <main>
      <header className="sticky top-0 z-20 border-b border-white/5 bg-background/90 px-md py-4 backdrop-blur" data-pull-refresh-ignore>
        <div className="flex items-center gap-3">
          <button
            onClick={() => router.back()}
            className="grid h-10 w-10 place-items-center rounded-full bg-surface text-text-primary"
            aria-label="Back"
          >
            <ArrowLeft size={18} />
          </button>

          <div className="flex min-w-0 flex-1 items-center gap-3 rounded-xl border border-white/5 bg-surface px-4 py-3">
            <Search size={18} className="shrink-0 text-text-tertiary" />
            <input
              autoFocus
              value={query}
              onChange={(event) => {
                const nextQuery = event.target.value;
                const trimmed = nextQuery.trim();
                setQuery(nextQuery);
                setHasSearched(Boolean(trimmed));
              }}
              placeholder="Teams, leagues, channels…"
              className="min-w-0 flex-1 bg-transparent text-sm font-medium text-text-primary outline-none placeholder:text-text-tertiary"
            />
            {query && (
              <button
                onClick={() => {
                  setQuery("");
                  setHasSearched(false);
                }}
                className="text-text-tertiary"
                aria-label="Clear search"
              >
                <X size={16} />
              </button>
            )}
          </div>
        </div>
      </header>

      {indexStatus !== "ok" && !isIndexLoading && (
        <div className="pb-4">
          <FeedStatusBanner
            tone={indexStatus === "error" ? "error" : "warning"}
            title={indexStatus === "error" ? "Search index unavailable" : "Showing last loaded index"}
            message={
              indexStatus === "error"
                ? "Fotty could not load the live search index. Check your connection and try again."
                : "A fresh refresh failed, so search results may be out of date."
            }
            onRetry={reloadIndex}
          />
        </div>
      )}

      {query.trim().length === 0 ? (
        <div className="space-y-6 py-lg">
          {isIndexLoading ? (
            <div className="flex justify-center py-12">
              <div className="h-9 w-9 animate-spin rounded-full border-4 border-accent border-t-transparent" />
            </div>
          ) : browseNow.length > 0 ? (
            <section className="space-y-4">
              <SectionHeader title="Popular Right Now" subtitle="Live fixtures people are opening first" />
              <div className="space-y-3 px-md">
                {browseNow.map((match) => (
                  <SearchMatchRow key={matchKey(match)} match={match} />
                ))}
              </div>
            </section>
          ) : (
            <EmptyState icon={Search} title="Search Fotty" message="Find matches and channels from the live board." />
          )}
        </div>
      ) : (
        <div className="space-y-6 py-lg">
          {fixtureResults.length > 0 && (
            <SearchSection title="Live & Matches" subtitle={`${fixtureResults.length} results`}>
              {fixtureResults.map((match) => (
                <SearchMatchRow key={matchKey(match)} match={match} />
              ))}
            </SearchSection>
          )}

          {channelResults.length > 0 && (
            <SearchSection title="Channels" subtitle={`${channelResults.length} results`}>
              {channelResults.map((match) => (
                <SearchMatchRow key={matchKey(match)} match={match} />
              ))}
            </SearchSection>
          )}

          {showEmpty && (
            <EmptyState
              icon={Search}
              title="No results found"
              message="Try a team name, league, or channel from the live listings."
            />
          )}
        </div>
      )}
      </main>
    </PullToRefresh>
  );
}

function SearchSection({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="space-y-4">
      <SectionHeader title={title} subtitle={subtitle} />
      <div className="space-y-3 px-md">{children}</div>
    </section>
  );
}

function SearchMatchRow({ match }: { match: ScrapedMatch }) {
  const teams = match.teams;
  const isFixture = match.kind === "fixture" && Boolean(teams);
  const title = match.displayTitle || match.title;
  const canOpen = canOpenBroadcast(match);
  const href = canOpen ? watchHref(match) : "/search";

  const row = (
    <>
      {isFixture && teams ? (
        <div className="flex shrink-0 items-center gap-2">
          <TeamBadge name={teams.home.name} badge={teams.home.badge} size={40} />
          <TeamBadge name={teams.away.name} badge={teams.away.badge} size={40} />
        </div>
      ) : (
        <div className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-white/5 text-accent">
          <Tv2 size={18} />
        </div>
      )}

      <div className="min-w-0 flex-1 space-y-1">
        <h2 className="line-clamp-2 text-sm font-semibold text-text-primary">{title}</h2>
        <div className="flex flex-wrap items-center gap-2 text-xs text-text-tertiary">
          <span className="font-semibold text-accent">{match.league || match.sport || "Live"}</span>
          {match.status && (
            <span className={match.status === "Live" ? "flex items-center gap-1 text-live" : "text-text-secondary"}>
              {match.status === "Live" && <Radio size={10} className="animate-pulse" />}
              {match.status}
            </span>
          )}
          {typeof match.sourceCount === "number" && match.sourceCount > 0 && (
            <span>{fottyFeedCountShort(match.sourceCount)}</span>
          )}
        </div>
        {match.subtitle && <p className="line-clamp-1 text-xs text-text-secondary">{match.subtitle}</p>}
      </div>

      <span className="shrink-0 rounded-full border border-white/10 px-3 py-1 text-xs font-bold text-text-secondary">
        {canOpen ? "Watch" : "Schedule"}
      </span>
    </>
  );

  if (!canOpen) {
    return <div className="flex items-center gap-4 rounded-xl border border-white/5 bg-surface p-3 opacity-80">{row}</div>;
  }

  return (
    <Link
      href={href}
      className="flex items-center gap-4 rounded-xl border border-white/5 bg-surface p-3 transition-colors hover:bg-surface-elevated"
    >
      {row}
    </Link>
  );
}

function buildMatchSearchText(match: ScrapedMatch) {
  return [
    match.title,
    match.displayTitle,
    match.subtitle,
    match.league,
    match.sport,
    match.region,
    match.network,
    match.teams?.home.name,
    match.teams?.away.name,
    ...(match.categories || []),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function normalizeSearch(value: string) {
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

function scoreMatch(match: ScrapedMatch, query: string) {
  const title = normalizeSearch(match.displayTitle || match.title);
  const home = normalizeSearch(match.teams?.home.name || "");
  const away = normalizeSearch(match.teams?.away.name || "");
  const league = normalizeSearch(match.league || "");
  const sport = normalizeSearch(match.sport || "");
  const fullText = normalizeSearch(buildMatchSearchText(match));
  const tokens = query.split(" ").filter(Boolean);
  let score = 0;

  if (home === query || away === query) score += 1000;
  if (title === query) score += 900;
  if (home.includes(query) || away.includes(query)) score += 650;
  if (title.includes(query)) score += 500;
  if (league.includes(query)) score += 220;
  if (sport.includes(query)) score += 120;
  if (fullText.includes(query)) score += 80;

  for (const token of tokens) {
    if (home.includes(token) || away.includes(token)) score += 80;
    if (title.includes(token)) score += 55;
    if (league.includes(token)) score += 25;
  }

  if (match.kind === "fixture") score += 75;
  if (match.status === "Live") score += 55;
  if (match.sport === "Football") score += 45;
  score += Math.min(match.rank || 0, 1000) / 100;

  return score;
}

function dedupeMatches(matches: ScrapedMatch[]) {
  const seen = new Set<string>();

  return matches.filter((match) => {
    const key =
      (match.eventSource && `${match.eventSource.source}:${match.eventSource.id}`) ||
      match.id ||
      `${match.kind || "match"}:${match.cid}:${match.title}`;

    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function watchHref(match: ScrapedMatch) {
  return buildWatchHref(match, "/search");
}
