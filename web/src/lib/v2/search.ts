import type { ScrapedMatch } from "@/lib/api";
import { fixtureDisplayPriority } from "@/lib/v2/match-priority";

export function buildMatchSearchText(match: ScrapedMatch) {
  return [
    match.title,
    match.displayTitle,
    match.subtitle,
    match.league,
    match.sport,
    match.region,
    match.network,
    match.teams?.home.name,
    match.teams?.away.name,
    ...(match.categories || []),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

export function normalizeSearch(value: string) {
  return value
    .normalize("NFD")
    .replace(/[øØ]/g, "o")
    .replace(/[æÆ]/g, "ae")
    .replace(/[åÅ]/g, "a")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function scoreMatch(match: ScrapedMatch, query: string) {
  const title = normalizeSearch(match.displayTitle || match.title);
  const home = normalizeSearch(match.teams?.home.name || "");
  const away = normalizeSearch(match.teams?.away.name || "");
  const league = normalizeSearch(match.league || "");
  const sport = normalizeSearch(match.sport || "");
  const fullText = normalizeSearch(buildMatchSearchText(match));
  const tokens = query.split(" ").filter(Boolean);
  let score = 0;

  if (home === query || away === query) score += 1000;
  if (title === query) score += 900;
  if (home.includes(query) || away.includes(query)) score += 650;
  if (title.includes(query)) score += 500;
  if (league.includes(query)) score += 220;
  if (sport.includes(query)) score += 120;
  if (fullText.includes(query)) score += 80;

  for (const token of tokens) {
    if (home.includes(token) || away.includes(token)) score += 80;
    if (title.includes(token)) score += 55;
    if (league.includes(token)) score += 25;
  }

  if (match.kind === "fixture") score += 75;
  if (match.status === "Live") score += 200;
  if (match.status === "Starting Soon") score += 120;
  if (match.sport === "Football") score += 15;
  score += Math.min(match.rank || 0, 1000) / 100;

  return score;
}

export function dedupeMatches(matches: ScrapedMatch[]) {
  const seen = new Set<string>();

  return matches.filter((match) => {
    const key =
      (match.eventSource && `${match.eventSource.source}:${match.eventSource.id}`) ||
      match.id ||
      `${match.kind || "match"}:${match.cid}:${match.title}`;

    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function searchMatches(index: ScrapedMatch[], query: string, limit = 24) {
  const trimmed = normalizeSearch(query);
  if (!trimmed) return [];

  return index
    .map((match) => ({ match, score: scoreMatch(match, trimmed) }))
    .filter((result) => result.score > 0)
    .sort((left, right) => {
      const scoreDiff = right.score - left.score;
      if (scoreDiff !== 0) return scoreDiff;
      const priority = fixtureDisplayPriority(left.match) - fixtureDisplayPriority(right.match);
      if (priority !== 0) return priority;
      const leftKickoff = left.match.startsAt ? new Date(left.match.startsAt).getTime() : Number.MAX_SAFE_INTEGER;
      const rightKickoff = right.match.startsAt ? new Date(right.match.startsAt).getTime() : Number.MAX_SAFE_INTEGER;
      return leftKickoff - rightKickoff;
    })
    .map((result) => result.match)
    .slice(0, limit);
}
