"use client";

import { useEffect, useState } from "react";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import {
  FOOTBALL_STANDINGS_CACHE_MS,
  type ScorerRow,
  type StandingsRow,
} from "@/lib/football-standings";

export interface LeagueFootballDataState {
  standings: StandingsRow[];
  scorers: ScorerRow[];
  loading: boolean;
  configured: boolean;
  message: string | null;
  error: string | null;
}

type CacheEntry = LeagueFootballDataState & { fetchedAt: number };

const cache = new Map<string, CacheEntry>();

function cacheKey(league: FootballLeagueTab, includeScorers: boolean) {
  return `${league}:${includeScorers ? "1" : "0"}`;
}

function readCache(league: FootballLeagueTab, includeScorers: boolean): LeagueFootballDataState | null {
  const entry = cache.get(cacheKey(league, includeScorers));
  if (!entry) return null;
  if (Date.now() - entry.fetchedAt > FOOTBALL_STANDINGS_CACHE_MS) return null;
  const { fetchedAt: _f, ...state } = entry;
  return state;
}

function writeCache(league: FootballLeagueTab, includeScorers: boolean, state: LeagueFootballDataState) {
  cache.set(cacheKey(league, includeScorers), { ...state, fetchedAt: Date.now() });
}

function useDebouncedValue<T>(value: T, delayMs: number) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = window.setTimeout(() => setDebounced(value), delayMs);
    return () => window.clearTimeout(id);
  }, [value, delayMs]);
  return debounced;
}

export function useLeagueFootballData(league: FootballLeagueTab, includeScorers = true) {
  const debouncedLeague = useDebouncedValue(league, 280);
  const [state, setState] = useState<LeagueFootballDataState>(() => {
    const cached = readCache(debouncedLeague, includeScorers);
    return (
      cached ?? {
        standings: [],
        scorers: [],
        loading: true,
        configured: false,
        message: null,
        error: null,
      }
    );
  });

  useEffect(() => {
    let cancelled = false;
    const cached = readCache(debouncedLeague, includeScorers);
    if (cached) {
      setState(cached);
      return;
    }

    setState((prev) => ({ ...prev, loading: true, error: null }));

    const query = includeScorers ? "&scorers=1" : "";
    fetch(`/api/football/standings?league=${encodeURIComponent(debouncedLeague)}${query}`)
      .then((res) => res.json())
      .then(
        (data: {
          standings?: StandingsRow[];
          scorers?: ScorerRow[];
          message?: string;
          error?: string;
          configured?: boolean;
        }) => {
          if (cancelled) return;
          const next: LeagueFootballDataState = {
            standings: data.standings ?? [],
            scorers: data.scorers ?? [],
            loading: false,
            configured: data.configured ?? false,
            message: !data.configured
              ? (data.message ?? "Add FOOTBALL_DATA_API_KEY for live tables.")
              : data.error
                ? null
                : (data.message ?? null),
            error: data.error ?? null,
          };
          writeCache(debouncedLeague, includeScorers, next);
          setState(next);
        }
      )
      .catch(() => {
        if (cancelled) return;
        setState({
          standings: [],
          scorers: [],
          loading: false,
          configured: false,
          message: "Standings unavailable",
          error: null,
        });
      });

    return () => {
      cancelled = true;
    };
  }, [debouncedLeague, includeScorers]);

  return state;
}
