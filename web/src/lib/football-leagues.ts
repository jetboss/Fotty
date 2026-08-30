import type { ScrapedMatch } from "@/lib/api";
import {
  isCurrentCompetitionPair,
  type CurrentFootballCompetitionId,
} from "@/lib/football-competition-catalog.generated";

export type FootballLeagueTab =
  | "all"
  | "premierLeague"
  | "championsLeague"
  | "laLiga"
  | "serieA"
  | "bundesliga"
  | "ligue1"
  | "other";

export const FOOTBALL_LEAGUE_TABS: FootballLeagueTab[] = [
  "all",
  "premierLeague",
  "championsLeague",
  "laLiga",
  "serieA",
  "bundesliga",
  "ligue1",
  "other",
];

const LEAGUE_LABELS: Record<FootballLeagueTab, string> = {
  all: "All Football",
  premierLeague: "Premier League",
  championsLeague: "Champions League",
  laLiga: "La Liga",
  serieA: "Serie A",
  bundesliga: "Bundesliga",
  ligue1: "Ligue 1",
  other: "Other Leagues",
};

/** Short labels for compact mobile league pills (desktop uses full names). */
const LEAGUE_SHORT_LABELS: Record<FootballLeagueTab, string> = {
  all: "All",
  premierLeague: "PL",
  championsLeague: "UCL",
  laLiga: "La Liga",
  serieA: "Serie A",
  bundesliga: "BL",
  ligue1: "L1",
  other: "More",
};

const LEAGUE_BADGES: Partial<Record<FootballLeagueTab, string>> = {
  premierLeague: "https://media.api-sports.io/football/leagues/39.png",
  championsLeague: "https://media.api-sports.io/football/leagues/2.png",
  laLiga: "https://media.api-sports.io/football/leagues/140.png",
  serieA: "https://media.api-sports.io/football/leagues/135.png",
  bundesliga: "https://media.api-sports.io/football/leagues/78.png",
  ligue1: "https://media.api-sports.io/football/leagues/61.png",
};

export function footballLeagueLabel(tab: FootballLeagueTab) {
  return LEAGUE_LABELS[tab];
}

export function footballLeagueShortLabel(tab: FootballLeagueTab) {
  return LEAGUE_SHORT_LABELS[tab];
}

export function footballLeagueBadgeUrl(tab: FootballLeagueTab) {
  return LEAGUE_BADGES[tab];
}

export function isFootballSport(match: ScrapedMatch) {
  const sport = (match.sport || "").toLowerCase();
  const league = (match.league || "").toLowerCase();
  if (sport.includes("football") && !sport.includes("american")) return true;
  if (league.includes("football") && !league.includes("american")) return true;
  return match.categories?.some((category) => category.toLowerCase().includes("football")) ?? false;
}

function teamNames(match: ScrapedMatch) {
  if (match.teams) {
    return {
      home: match.teams.home.name.trim(),
      away: match.teams.away.name.trim(),
    };
  }

  const title = match.displayTitle || match.title;
  for (const separator of [" vs ", " v ", " @ ", " - "]) {
    const parts = title.split(separator);
    if (parts.length === 2) {
      return {
        home: parts[0].trim(),
        away: parts[1].trim(),
      };
    }
  }

  return { home: "", away: "" };
}

function containsAny(haystack: string, terms: string[]) {
  return terms.some((term) => haystack.includes(term));
}

function hasNonDomesticCompetitionMarker(text: string) {
  return containsAny(text, [
    "premier league 2", "premier-league-2", "premier league cup", "premier-league-cup",
    "fa cup", "fa-cup", "efl cup", "efl-cup", "league cup", "carabao",
    "community shield", "championship", "league one", "league-one", "league two",
    "league-two", "bundesliga 2", "2. bundesliga", "copa del rey", "coppa italia", "dfb pokal", "coupe de france",
    "europa league", "conference league", "friendly", " u18", " u19", " u21", " u23",
    "women", "ladies", "youth", "academy", "reserves",
  ]);
}

function inferFromMetadata(match: ScrapedMatch): FootballLeagueTab | null {
  const haystack = [match.league, match.subtitle, match.displayTitle].filter(Boolean).join(" ").toLowerCase();
  if (!haystack) return null;

  if (containsAny(haystack, ["champions league", "uefa champions", "ucl"])) return "championsLeague";
  const { home, away } = teamNames(match);
  const domesticMetadata: Array<[FootballLeagueTab, CurrentFootballCompetitionId, string[]]> = [
    ["premierLeague", "premierLeague", ["premier league", "english premier", "epl"]],
    ["laLiga", "laLiga", ["la liga", "laliga"]],
    ["serieA", "serieA", ["serie a"]],
    ["bundesliga", "bundesliga", ["bundesliga"]],
    ["ligue1", "ligue1", ["ligue 1", "ligue1"]],
  ];
  for (const [tab, competition, markers] of domesticMetadata) {
    if (containsAny(haystack, markers)) {
      return isCurrentCompetitionPair(competition, home, away) && !hasNonDomesticCompetitionMarker(haystack)
        ? tab
        : "other";
    }
  }

  return null;
}

/** Mirrors iOS `AnalyticalDataEngine.footballLeagueTab(for:)`. */
export function inferFootballLeagueTab(match: ScrapedMatch): FootballLeagueTab {
  const fromMetadata = inferFromMetadata(match);
  if (fromMetadata) return fromMetadata;

  const haystack = `${match.id || ""} ${match.cid || ""} ${match.title} ${match.displayTitle || ""}`.toLowerCase();
  const { home, away } = teamNames(match);

  if (containsAny(haystack, ["champions league", "uefa champions", "champions-league", "ucl"])) {
    return "championsLeague";
  }
  if (hasNonDomesticCompetitionMarker(haystack)) return "other";

  if (isCurrentCompetitionPair("premierLeague", home, away)) return "premierLeague";
  if (isCurrentCompetitionPair("laLiga", home, away)) return "laLiga";
  if (isCurrentCompetitionPair("serieA", home, away)) return "serieA";
  if (isCurrentCompetitionPair("bundesliga", home, away)) return "bundesliga";
  if (isCurrentCompetitionPair("ligue1", home, away)) return "ligue1";

  return "other";
}

export function matchFootballLeagueTab(match: ScrapedMatch, tab: FootballLeagueTab) {
  if (tab === "all") return true;
  if (!isFootballSport(match)) return false;
  return inferFootballLeagueTab(match) === tab;
}

export function filterFootballByLeague(matches: ScrapedMatch[], tab: FootballLeagueTab) {
  if (tab === "all") return matches;
  return matches.filter((match) => matchFootballLeagueTab(match, tab));
}
