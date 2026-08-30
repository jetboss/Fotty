"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import {
  defaultLeagueTabForUser,
  orderedFootballLeagueTabs,
} from "@/lib/football-personalization";
import {
  readFootballLeaguePreference,
  writeFootballLeaguePreference,
} from "@/lib/football-league-preference";
import { getTrackedTeams, subscribeToStorage, TRACKED_TEAMS_KEY, type TrackedTeamEntry } from "@/lib/storage";

export function useFootballLeaguePreference(
  trackedTeams: TrackedTeamEntry[] = [],
  fallback: FootballLeagueTab = "premierLeague"
) {
  const defaultTab = useMemo(
    () => defaultLeagueTabForUser(trackedTeams, fallback),
    [trackedTeams, fallback]
  );
  const orderedTabs = useMemo(() => orderedFootballLeagueTabs(trackedTeams), [trackedTeams]);

  const [league, setLeagueState] = useState<FootballLeagueTab>(
    () => readFootballLeaguePreference() ?? defaultLeagueTabForUser(trackedTeams, fallback)
  );

  useEffect(() => {
    if (readFootballLeaguePreference() !== null) return;
    setLeagueState(defaultTab);
  }, [defaultTab]);

  useEffect(() => {
    return subscribeToStorage((key) => {
      if (key !== TRACKED_TEAMS_KEY) return;
      const saved = readFootballLeaguePreference();
      if (saved !== null) {
        setLeagueState(saved);
        return;
      }
      setLeagueState(defaultLeagueTabForUser(getTrackedTeams(), fallback));
    });
  }, [fallback]);

  const setLeague = useCallback((next: FootballLeagueTab) => {
    setLeagueState(next);
    writeFootballLeaguePreference(next);
  }, []);

  return [league, setLeague, orderedTabs] as const;
}
