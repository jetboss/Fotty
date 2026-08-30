import type { ScrapedMatch } from "@/lib/api";
import { matchKey } from "@/lib/live";
import {
  type FootballLeagueTab,
  inferFootballLeagueTab,
  isFootballSport,
} from "@/lib/football-leagues";

const tabByMatchKey = new Map<string, FootballLeagueTab>();

export function clearFootballLeagueIndex() {
  tabByMatchKey.clear();
}

export function getMatchLeagueTab(match: ScrapedMatch): FootballLeagueTab {
  const key = matchKey(match);
  const cached = tabByMatchKey.get(key);
  if (cached) return cached;
  const tab = inferFootballLeagueTab(match);
  tabByMatchKey.set(key, tab);
  return tab;
}

export function filterMatchesByLeagueTab(matches: ScrapedMatch[], tab: FootballLeagueTab) {
  if (tab === "all") return matches.filter(isFootballSport);
  return matches.filter((match) => isFootballSport(match) && getMatchLeagueTab(match) === tab);
}
