import type { ScrapedMatch } from "@/lib/api";
import { normalizeTeamName, teamNamesMatch } from "@/lib/team-name-match";
import {
  FOOTBALL_COMPETITIONS,
  type CurrentFootballCompetitionId,
} from "@/lib/football-competition-catalog.generated";

export interface TeamSuggestion {
  name: string;
  league?: string;
  sport?: string;
}

/** Season-labelled domestic clubs searched on Team Alerts. */
const DOMESTIC_COMPETITIONS: CurrentFootballCompetitionId[] = [
  "premierLeague", "laLiga", "serieA", "bundesliga", "ligue1",
];
const KNOWN_FOOTBALL_TEAMS: TeamSuggestion[] = DOMESTIC_COMPETITIONS.flatMap((id) => {
  const competition = FOOTBALL_COMPETITIONS[id];
  return competition.clubs.map((club) => ({
    name: club.name,
    league: competition.displayName,
    sport: "Football",
  }));
});

function suggestionKey(suggestion: TeamSuggestion) {
  return normalizeTeamName(suggestion.name);
}

export function buildTeamCatalogFromMatches(matches: ScrapedMatch[]): TeamSuggestion[] {
  const map = new Map<string, TeamSuggestion>();

  for (const known of KNOWN_FOOTBALL_TEAMS) {
    map.set(suggestionKey(known), known);
  }

  for (const match of matches) {
    if (!match.teams) continue;
    for (const side of [match.teams.home, match.teams.away]) {
      const name = side.name?.trim();
      if (!name) continue;
      const key = normalizeTeamName(name);
      if (!key || map.has(key)) continue;
      map.set(key, {
        name,
        league: match.league || match.subtitle,
        sport: match.sport || "Football",
      });
    }
  }

  return [...map.values()].sort((left, right) => left.name.localeCompare(right.name));
}

function scoreTeamSuggestion(suggestion: TeamSuggestion, query: string) {
  const name = normalizeTeamName(suggestion.name);
  const league = normalizeTeamName(suggestion.league || "");
  const tokens = query.split(" ").filter(Boolean);
  let score = 0;

  if (name === query) score += 1000;
  if (name.startsWith(query)) score += 700;
  if (name.includes(query)) score += 500;
  if (league.includes(query)) score += 120;

  for (const token of tokens) {
    if (name.startsWith(token)) score += 180;
    else if (name.includes(token)) score += 90;
    if (league.includes(token)) score += 40;
  }

  return score;
}

export function searchTeamSuggestions(query: string, catalog: TeamSuggestion[], limit = 8) {
  const normalized = normalizeTeamName(query);
  if (normalized.length < 2) return [];

  return catalog
    .map((suggestion) => ({ suggestion, score: scoreTeamSuggestion(suggestion, normalized) }))
    .filter((entry) => entry.score > 0)
    .sort((left, right) => right.score - left.score || left.suggestion.name.localeCompare(right.suggestion.name))
    .slice(0, limit)
    .map((entry) => entry.suggestion);
}

export function findSuggestionMatch(query: string, catalog: TeamSuggestion[]) {
  const normalized = normalizeTeamName(query);
  if (!normalized) return null;

  return (
    catalog.find((suggestion) => normalizeTeamName(suggestion.name) === normalized) ||
    catalog.find((suggestion) => teamNamesMatch(suggestion.name, query)) ||
    null
  );
}
