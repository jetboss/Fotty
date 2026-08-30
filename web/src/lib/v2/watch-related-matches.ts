import type { ScrapedMatch } from "@/lib/api";
import { canOpenBroadcast, matchKey } from "@/lib/live";

const GENERIC_COMPETITION_LABELS = new Set([
  "football",
  "soccer",
  "sport",
  "sports",
  "live",
  "other",
  "international",
  "fotty live",
]);

function isGenericCompetitionLabel(value?: string | null) {
  if (!value?.trim()) return true;
  return GENERIC_COMPETITION_LABELS.has(value.trim().toLowerCase());
}

/** Subtitle under event watch headers — prefer real competition labels over generic sport. */
export function watchCompetitionSubtitle(
  match: ScrapedMatch | null | undefined,
  leagueFromUrl?: string
): string | undefined {
  for (const candidate of [match?.subtitle, match?.league, leagueFromUrl]) {
    const value = candidate?.trim();
    if (!value || isGenericCompetitionLabel(value)) continue;
    if (/^group\s+[a-l]$/i.test(value)) continue;
    return value;
  }

  return undefined;
}

/** Related fixtures for the watch aside — same competition, not every "Football" match. */
export function relatedWatchMatches(
  boardMatches: ScrapedMatch[],
  current: ScrapedMatch | null | undefined,
  options: { matchId?: string; cid?: string; league?: string }
): ScrapedMatch[] {
  const currentKey = current?.id || options.matchId || options.cid || "";

  const competition = current?.subtitle?.trim() || current?.league?.trim() || options.league?.trim();
  if (!competition || isGenericCompetitionLabel(competition)) return [];

  return boardMatches
    .filter((match) => {
      if (matchKey(match) === currentKey) return false;
      if (!canOpenBroadcast(match)) return false;
      const matchCompetition = match.subtitle?.trim() || match.league?.trim();
      return matchCompetition === competition;
    })
    .slice(0, 4);
}
