const FOOTBALL_DATA_BASE = "https://api.football-data.org/v4";

export type FootballMatchesQuery = {
  dateFrom?: string;
  dateTo?: string;
  status?: string;
  limit?: string;
  competition?: string;
  season?: string;
};

export function isSafeFootballQueryValue(value: string) {
  return /^[A-Za-z0-9_,.-]+$/.test(value);
}

/** Builds the upstream football-data.org matches URL (no network). */
export function buildFootballMatchesUpstreamUrl(query: FootballMatchesQuery): {
  url?: string;
  error?: string;
} {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (!value?.trim()) continue;
    if (!isSafeFootballQueryValue(value.trim())) {
      return { error: `Invalid ${key}` };
    }
    if (key === "competition") continue;
    params.set(key, value.trim());
  }

  const competition = query.competition?.trim().toUpperCase();
  const path = competition
    ? `${FOOTBALL_DATA_BASE}/competitions/${encodeURIComponent(competition)}/matches`
    : `${FOOTBALL_DATA_BASE}/matches`;
  return { url: params.size > 0 ? `${path}?${params.toString()}` : path };
}
