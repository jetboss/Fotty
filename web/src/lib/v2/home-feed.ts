import type { ScrapedMatch } from "@/lib/api";
import { hasStreameXPlayback, matchKey } from "@/lib/live";
import { matchIncludesTeam } from "@/lib/team-name-match";
import { isMatchLive } from "@/lib/v2/match-priority";
import { isKnockoutBracketTbd } from "@/lib/fixture-normalization";
import type { TrackedTeamEntry } from "@/lib/storage";

function isFixture(match: ScrapedMatch) {
  return match.kind === "fixture";
}

function kickoffTime(match: ScrapedMatch) {
  return match.startsAt ? new Date(match.startsAt).getTime() : Number.MAX_SAFE_INTEGER;
}

function isFootballFixture(match: ScrapedMatch) {
  return isFixture(match) && (match.sport === "Football" || match.categories?.includes("football"));
}

/**
 * Popularity score for hero selection — higher is better.
 * Mirrors the homelab's rank-first ordering (orderFootballFirst uses rank desc),
 * with league/sport text as a secondary signal for matches without rank data.
 */
function heroPopularityScore(match: ScrapedMatch): number {
  let score = 0;

  // ── Server-supplied signals (dominant, like homelab's rank-based sort) ────
  // Rank is the primary signal — the server knows what's high profile
  score += (match.rank ?? 0) * 10;

  if (match.isPopular) score += 3000;

  // Source count — more streams = more demand
  score += Math.min((match.sourceCount ?? 0) * 15, 500);

  // Has teams/poster = more structured, higher quality fixture data
  if (match.teams) score += 200;
  if (match.poster) score += 100;

  const text = [
    match.title,
    match.displayTitle,
    match.league,
    match.subtitle,
    match.sport,
    match.region,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  // ── Fotty Core: Football Priority ──────────────────────────────────────────
  if (isFootballFixture(match)) score += 2500;

  // ── Tier 1: Global blue-chip competitions ────────────────────────────────
  if (/champions league|ucl/i.test(text)) score += 2500;
  if (/premier league/i.test(text)) score += 2200;
  if (/europa league|uel/i.test(text)) score += 1600;
  if (/la liga|laliga/i.test(text)) score += 1600;
  if (/serie a/i.test(text)) score += 1400;
  if (/bundesliga/i.test(text)) score += 1350;
  if (/ligue 1/i.test(text)) score += 1200;
  if (/copa america|euro 20|nations league|international friendly/i.test(text)) score += 1600;

  // ── Tier 2: High-profile international cricket & major other sports ───────
  if (/cricket/i.test(text)) {
    score += 600;
    // Full internationals are very high profile globally
    if (/england|india|australia|new zealand|south africa|pakistan|west indies|sri lanka|bangladesh/i.test(text)) {
      score += 1000;
    }
  }

  // Major US sports
  if (/nba finals|super bowl|mlb world series|stanley cup/i.test(text)) score += 1500;
  if (/\bnba\b|\bnfl\b|\bnhl\b|\bmlb\b/i.test(text)) score += 600;

  // ── Tier 3: Well-known domestic cups & leagues ───────────────────────────
  if (/fa cup|efl cup|carabao|community shield/i.test(text)) score += 800;
  if (/eredivisie|scottish premiership|mls|a-league|j1 league/i.test(text)) score += 400;

  // ── Penalty: low-profile regional leagues ────────────────────────────────
  if (/maltese|armenian|moldovan|faroese|azerbaijani|kazakhstani|albanian superliga/i.test(text)) score -= 1200;
  if (/\bqualifier\b|qualifying round|preliminary round/i.test(text)) score -= 400;

  return score;
}

function pickBestByScore(matches: ScrapedMatch[]): ScrapedMatch | null {
  if (matches.length === 0) return null;
  return matches.reduce((best, curr) =>
    heroPopularityScore(curr) > heroPopularityScore(best) ? curr : best
  );
}

function isFinishedFixture(match: ScrapedMatch) {
  return match.status === "Finished";
}

export function pickHeroMatch(matches: ScrapedMatch[], trackedTeams: TrackedTeamEntry[] = []) {
  // All fixtures with playback — not football-only, matching homelab behavior
  const withPlayback = matches.filter(
    (match) => match.kind === "fixture" && hasStreameXPlayback(match)
  );

  // 1. Live tracked-team match (user's personal relevance)
  const trackedLive = withPlayback.filter(
    (match) => isMatchLive(match) && trackedTeams.some((team) => matchIncludesTeam(match, team.name))
  );
  const trackedHero = pickBestByScore(trackedLive);
  if (trackedHero) return trackedHero;

  // 2. Best live watchable match by popularity — rank-first, like the homelab
  const allLive = matches.filter(
    (match) => hasStreameXPlayback(match) && isMatchLive(match)
  );
  const liveHero = pickBestByScore(allLive);
  if (liveHero) return liveHero;

  // 3. A live fixture still outranks every finished/upcoming fixture even when
  // its provider mapping is briefly unavailable.
  const anyLiveHero = pickBestByScore(matches.filter(isMatchLive));
  if (anyLiveHero) return anyLiveHero;

  // 4. Best upcoming watchable match by popularity
  const upcoming = withPlayback
    .filter((match) => {
      if (isFinishedFixture(match)) return false;
      const t = kickoffTime(match);
      return Number.isFinite(t) && t > Date.now();
    })
    .sort((a, b) => heroPopularityScore(b) - heroPopularityScore(a));
  if (upcoming.length) return upcoming[0];

  const activePlayback = withPlayback.filter((match) => !isFinishedFixture(match));
  if (activePlayback[0]) return activePlayback[0];

  // 5. Any live or watchable match as last resort
  const anyWatchable = matches
    .filter((match) => hasStreameXPlayback(match) && !isFinishedFixture(match))
    .sort((a, b) => heroPopularityScore(b) - heroPopularityScore(a));
  if (anyWatchable.length) return anyWatchable[0];

  return (
    matches.find((match) => isFootballFixture(match) && !isFinishedFixture(match)) ??
    matches.find((match) => !isFinishedFixture(match)) ??
    null
  );
}

export function liveNowRail(matches: ScrapedMatch[], heroKey?: string | null) {
  return matches
    .filter(
      (match) =>
        isFixture(match) &&
        hasStreameXPlayback(match) &&
        isMatchLive(match) &&
        !isKnockoutBracketTbd(match)
    )
    .filter((match) => matchKey(match) !== heroKey)
    .sort((a, b) => kickoffTime(a) - kickoffTime(b))
    .slice(0, 12);
}

export function myTeamsRail(matches: ScrapedMatch[], trackedTeams: TrackedTeamEntry[], heroKey?: string | null) {
  if (trackedTeams.length === 0) return [];

  return matches
    .filter(
      (match) =>
        isFixture(match) &&
        hasStreameXPlayback(match) &&
        matchKey(match) !== heroKey &&
        trackedTeams.some((team) => matchIncludesTeam(match, team.name))
    )
    .sort((a, b) => kickoffTime(a) - kickoffTime(b))
    .slice(0, 12);
}

export function tonightRail(matches: ScrapedMatch[], heroKey?: string | null, excludeKeys: Set<string> = new Set(), now = Date.now()) {
  const end = now + 24 * 60 * 60 * 1000;
  return matches
    .filter((match) => {
      if (!isFixture(match)) return false;
      const key = matchKey(match);
      if (key === heroKey || excludeKeys.has(key)) return false;
      const t = kickoffTime(match);
      return Number.isFinite(t) && t >= now && t <= end;
    })
    .sort((a, b) => kickoffTime(a) - kickoffTime(b))
    .slice(0, 16);
}

/** Next kickoffs when primary rails are thin — fills match-day gaps on home. */
export function matchdayKickoffRail(
  matches: ScrapedMatch[],
  heroKey?: string | null,
  excludeKeys: Set<string> = new Set(),
  now = Date.now(),
  limit = 10
) {
  const end = now + 24 * 60 * 60 * 1000;
  return matches
    .filter((match) => {
      if (!isFixture(match)) return false;
      const key = matchKey(match);
      if (key === heroKey || excludeKeys.has(key)) return false;
      const t = kickoffTime(match);
      return Number.isFinite(t) && t >= now && t <= end;
    })
    .sort((a, b) => kickoffTime(a) - kickoffTime(b))
    .slice(0, limit);
}
