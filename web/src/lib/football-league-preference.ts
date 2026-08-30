"use client";

import type { FootballLeagueTab } from "@/lib/football-leagues";

const STORAGE_KEY = "fotty.web.footballLeague.v1";
const VALID: FootballLeagueTab[] = [
  "premierLeague",
  "championsLeague",
  "laLiga",
  "serieA",
  "bundesliga",
  "ligue1",
  "all",
  "other",
];

function isFootballLeagueTab(value: string): value is FootballLeagueTab {
  return (VALID as string[]).includes(value);
}

export function readFootballLeaguePreference(): FootballLeagueTab | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.sessionStorage.getItem(STORAGE_KEY);
    return raw && isFootballLeagueTab(raw) ? raw : null;
  } catch {
    return null;
  }
}

export function writeFootballLeaguePreference(league: FootballLeagueTab) {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(STORAGE_KEY, league);
  } catch {
    // Ignore quota / private mode.
  }
}
