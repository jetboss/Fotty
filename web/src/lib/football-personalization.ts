import type { ScrapedMatch } from "@/lib/api";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import { footballLeagueLabel, inferFootballLeagueTab } from "@/lib/football-leagues";
import { FOOTBALL_HOME_LEAGUE_TABS } from "@/lib/football-standings";
import type { TrackedTeamEntry } from "@/lib/storage";

const LEAGUE_STRING_TO_TAB: Record<string, FootballLeagueTab> = {
  "premier league": "premierLeague",
  "english premier": "premierLeague",
  epl: "premierLeague",
  "la liga": "laLiga",
  laliga: "laLiga",
  "serie a": "serieA",
  bundesliga: "bundesliga",
  "ligue 1": "ligue1",
  ligue1: "ligue1",
  "champions league": "championsLeague",
  "uefa champions": "championsLeague",
};

const TOP_DOMESTIC_LEAGUES = new Set<FootballLeagueTab>([
  "premierLeague",
  "laLiga",
  "serieA",
  "bundesliga",
  "ligue1",
]);

function leagueStringToTab(league?: string): FootballLeagueTab | null {
  if (!league?.trim()) return null;
  const key = league.toLowerCase().trim();
  return LEAGUE_STRING_TO_TAB[key] ?? null;
}

function inferLeagueTabFromTeamName(name: string): FootballLeagueTab | null {
  const stub: ScrapedMatch = {
    title: name,
    cid: name,
    availability: 0,
    teams: { home: { name }, away: { name: "Away" } },
  };
  const tab = inferFootballLeagueTab(stub);
  if (tab === "all" || tab === "other") return null;
  return tab;
}

function domesticLeagueTabForTeam(team: TrackedTeamEntry): FootballLeagueTab | null {
  const fromLeague = leagueStringToTab(team.league);
  if (fromLeague && fromLeague !== "championsLeague") return fromLeague;
  return inferLeagueTabFromTeamName(team.name);
}

/** Leagues implied by tracked clubs, in follow order, with UCL after the first top-league domestic pick. */
function collectPreferredLeagueTabs(trackedTeams: TrackedTeamEntry[]): FootballLeagueTab[] {
  const order: FootballLeagueTab[] = [];
  const seen = new Set<FootballLeagueTab>();

  for (const team of trackedTeams) {
    const domestic = domesticLeagueTabForTeam(team);
    if (!domestic || seen.has(domestic)) continue;
    seen.add(domestic);
    order.push(domestic);
  }

  if (order.some((tab) => TOP_DOMESTIC_LEAGUES.has(tab)) && !seen.has("championsLeague")) {
    order.push("championsLeague");
  }

  return order;
}

export function orderedFootballLeagueTabs(
  trackedTeams: TrackedTeamEntry[],
  baseTabs: FootballLeagueTab[] = FOOTBALL_HOME_LEAGUE_TABS
): FootballLeagueTab[] {
  const preferred = collectPreferredLeagueTabs(trackedTeams);
  const rest = baseTabs.filter((tab) => !preferred.includes(tab));
  return [...preferred, ...rest];
}

export function defaultLeagueTabForUser(
  trackedTeams: TrackedTeamEntry[],
  fallback: FootballLeagueTab = "premierLeague"
): FootballLeagueTab {
  return collectPreferredLeagueTabs(trackedTeams)[0] ?? fallback;
}

export function footballLeaguePersonalizationHint(trackedTeams: TrackedTeamEntry[]): string | null {
  if (trackedTeams.length === 0) return null;
  const tabs = collectPreferredLeagueTabs(trackedTeams);
  if (tabs.length === 0) return "Based on teams you follow";
  if (tabs.length === 1) return `Based on ${footballLeagueLabel(tabs[0])}`;
  return `Based on ${tabs.slice(0, 2).map(footballLeagueLabel).join(" & ")}`;
}
