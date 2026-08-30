import type { FootballLeagueTab } from "@/lib/football-leagues";
import { footballLeagueLabel } from "@/lib/football-leagues";

/** Standings/scorers move on match days, not live — avoid hammering football-data.org. */
export const FOOTBALL_STANDINGS_CACHE_MS = 6 * 60 * 60 * 1000;
export const FOOTBALL_STANDINGS_REVALIDATE_SEC = 6 * 60 * 60;

/** football-data.org v4 competition codes */
export const FOOTBALL_DATA_COMPETITION: Partial<Record<FootballLeagueTab, string>> = {
  premierLeague: "PL",
  championsLeague: "CL",
  laLiga: "PD",
  serieA: "SA",
  bundesliga: "BL1",
  ligue1: "FL1",
};

/** Home + live board league picker (fixtures and table stay in sync). */
export const FOOTBALL_HOME_LEAGUE_TABS: FootballLeagueTab[] = [
  "premierLeague",
  "championsLeague",
  "laLiga",
  "serieA",
  "bundesliga",
  "ligue1",
];

/** Leagues that have a football-data.org table (excludes all / other). */
export const FOOTBALL_STANDINGS_TABS: FootballLeagueTab[] = [
  "premierLeague",
  "championsLeague",
  "laLiga",
  "serieA",
  "bundesliga",
  "ligue1",
];

export interface StandingsRow {
  position: number;
  teamName: string;
  teamCrest?: string;
  played: number;
  won: number;
  draw: number;
  lost: number;
  points: number;
  goalsFor?: number;
  goalsAgainst?: number;
  goalDifference?: number;
  form?: string;
}

export interface ScorerRow {
  playerName: string;
  teamName: string;
  goals: number;
}

export function competitionCodeForLeague(tab: FootballLeagueTab): string | null {
  if (tab === "other" || tab === "all") return null;
  return FOOTBALL_DATA_COMPETITION[tab] ?? null;
}

export function standingsDisplayLabel(tab: FootballLeagueTab) {
  return footballLeagueLabel(tab);
}

export function standingsSupportsLeague(tab: FootballLeagueTab) {
  return FOOTBALL_STANDINGS_TABS.includes(tab);
}
