import type { ScrapedMatch } from "@/lib/api";
import { teamNamesMatch } from "@/lib/team-name-match";

const KICKOFF_WINDOW_MS = 90 * 60 * 1000;

function kickoffMillis(match: ScrapedMatch) {
  return match.startsAt ? new Date(match.startsAt).getTime() : NaN;
}

function teamsAlign(left: ScrapedMatch, right: ScrapedMatch) {
  const lHome = left.teams?.home.name;
  const lAway = left.teams?.away.name;
  const rHome = right.teams?.home.name;
  const rAway = right.teams?.away.name;
  if (!lHome || !lAway || !rHome || !rAway) return false;
  return (
    (teamNamesMatch(lHome, rHome) && teamNamesMatch(lAway, rAway)) ||
    (teamNamesMatch(lHome, rAway) && teamNamesMatch(lAway, rHome))
  );
}

/** Prefer an existing poster, otherwise borrow one from a matching kickoff/team row. */
export function findPosterForMatch(match: ScrapedMatch, sources: ScrapedMatch[]) {
  const existing = match.poster?.trim();
  if (existing) return existing;

  const kickoff = kickoffMillis(match);
  if (!Number.isFinite(kickoff) || !match.teams) return undefined;

  for (const source of sources) {
    const poster = source.poster?.trim();
    if (!poster || !source.teams) continue;
    const sourceKickoff = kickoffMillis(source);
    if (!Number.isFinite(sourceKickoff) || Math.abs(sourceKickoff - kickoff) > KICKOFF_WINDOW_MS) continue;
    if (teamsAlign(match, source)) return poster;
  }

  return undefined;
}

export function enrichMatchPoster(match: ScrapedMatch, sources: ScrapedMatch[]) {
  const poster = findPosterForMatch(match, sources);
  return poster ? { ...match, poster } : match;
}

export function enrichMatchesWithPosters(matches: ScrapedMatch[], sources: ScrapedMatch[]) {
  if (!sources.some((match) => match.poster?.trim())) return matches;
  return matches.map((match) => enrichMatchPoster(match, sources));
}
