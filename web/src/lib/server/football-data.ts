import {
  competitionCodeForLeague,
  FOOTBALL_STANDINGS_REVALIDATE_SEC,
  type ScorerRow,
  type StandingsRow,
} from "@/lib/football-standings";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import {
  buildFootballMatchesUpstreamUrl,
  type FootballMatchesQuery,
} from "@/lib/server/football-matches-url";

export type { FootballMatchesQuery };
export { buildFootballMatchesUpstreamUrl };

const FOOTBALL_DATA_BASE = "https://api.football-data.org/v4";

export function getFootballDataToken() {
  return process.env.FOOTBALL_DATA_API_KEY?.trim() || "";
}

type StandingsApiTable = {
  position: number;
  team: { name: string; crest?: string };
  playedGames: number;
  won: number;
  draw: number;
  lost: number;
  points: number;
  goalsFor?: number;
  goalsAgainst?: number;
  goalDifference?: number;
  form?: string | null;
};

export function parseStandingsPayload(json: {
  standings?: Array<{
    type?: string;
    table?: StandingsApiTable[];
  }>;
}): StandingsRow[] {
  const blocks = json.standings ?? [];
  const total =
    blocks.find((block) => block.type === "TOTAL" && (block.table?.length ?? 0) > 0) ??
    blocks.find((block) => (block.table?.length ?? 0) > 0);

  return (total?.table ?? []).map((row) => ({
    position: row.position,
    teamName: row.team.name,
    teamCrest: row.team.crest,
    played: row.playedGames,
    won: row.won,
    draw: row.draw,
    lost: row.lost,
    points: row.points,
    goalsFor: row.goalsFor,
    goalsAgainst: row.goalsAgainst,
    goalDifference: row.goalDifference,
    form: row.form ?? undefined,
  }));
}

export async function fetchCompetitionStandings(code: string): Promise<StandingsRow[]> {
  const token = getFootballDataToken();
  if (!token) return [];

  const response = await fetch(`${FOOTBALL_DATA_BASE}/competitions/${code}/standings`, {
    headers: { "X-Auth-Token": token },
    next: { revalidate: FOOTBALL_STANDINGS_REVALIDATE_SEC },
  });

  if (!response.ok) {
    throw new Error(`standings HTTP ${response.status}`);
  }

  const json = (await response.json()) as Parameters<typeof parseStandingsPayload>[0];
  return parseStandingsPayload(json);
}

export async function fetchCompetitionScorers(code: string, limit = 10): Promise<ScorerRow[]> {
  const token = getFootballDataToken();
  if (!token) return [];

  const response = await fetch(`${FOOTBALL_DATA_BASE}/competitions/${code}/scorers?limit=${limit}`, {
    headers: { "X-Auth-Token": token },
    next: { revalidate: FOOTBALL_STANDINGS_REVALIDATE_SEC },
  });

  if (!response.ok) {
    return [];
  }

  const json = (await response.json()) as {
    scorers?: Array<{
      player: { name: string };
      team: { name: string };
      goals: number;
    }>;
  };

  return (json.scorers ?? []).slice(0, limit).map((row) => ({
    playerName: row.player.name,
    teamName: row.team.name,
    goals: row.goals,
  }));
}

const MATCHES_REVALIDATE_SEC = 15 * 60;

/** Proxies football-data.org match feeds so mobile clients can drop the API key. */
export async function fetchFootballDataMatches(query: FootballMatchesQuery) {
  const token = getFootballDataToken();
  if (!token) {
    return {
      configured: false as const,
      matches: [] as unknown[],
      message:
        process.env.NODE_ENV === "production"
          ? "Match schedule is temporarily unavailable."
          : "Set FOOTBALL_DATA_API_KEY in web/.env.local for live schedules.",
    };
  }

  const built = buildFootballMatchesUpstreamUrl(query);
  if (built.error || !built.url) {
    return {
      configured: true as const,
      matches: [] as unknown[],
      error: built.error || "Invalid query",
    };
  }
  const url = built.url;

  try {
    const response = await fetch(url, {
      headers: { "X-Auth-Token": token, Accept: "application/json" },
      next: { revalidate: MATCHES_REVALIDATE_SEC },
    });

    if (!response.ok) {
      return {
        configured: true as const,
        matches: [] as unknown[],
        error: `matches HTTP ${response.status}`,
      };
    }

    const json = (await response.json()) as { matches?: unknown[] };
    return {
      configured: true as const,
      matches: Array.isArray(json.matches) ? json.matches : [],
      resultSet: (json as { resultSet?: unknown }).resultSet,
      filters: (json as { filters?: unknown }).filters,
    };
  } catch (error) {
    return {
      configured: true as const,
      matches: [] as unknown[],
      error: error instanceof Error ? error.message : "matches fetch failed",
    };
  }
}

export async function fetchLeagueFootballData(league: FootballLeagueTab, includeScorers: boolean) {
  const code = competitionCodeForLeague(league);
  const token = getFootballDataToken();

  if (!token) {
    return {
      configured: false as const,
      league,
      competitionCode: code,
      standings: [] as StandingsRow[],
      scorers: [] as ScorerRow[],
      message:
        process.env.NODE_ENV === "production"
          ? "League tables are temporarily unavailable."
          : "Set FOOTBALL_DATA_API_KEY in web/.env.local for live tables.",
    };
  }

  if (!code) {
    return {
      configured: true as const,
      league,
      competitionCode: null,
      standings: [] as StandingsRow[],
      scorers: [] as ScorerRow[],
      message: "Choose a league above to load a table.",
    };
  }

  try {
    const standings = await fetchCompetitionStandings(code);
    const scorers = includeScorers ? await fetchCompetitionScorers(code) : [];

    return {
      configured: true as const,
      league,
      competitionCode: code,
      standings,
      scorers,
    };
  } catch (error) {
    return {
      configured: true as const,
      league,
      competitionCode: code,
      standings: [] as StandingsRow[],
      scorers: [] as ScorerRow[],
      error: error instanceof Error ? error.message : "standings fetch failed",
    };
  }
}
