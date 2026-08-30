import type { ScrapedMatch } from "@/lib/api";

const SPOTLIGHT_PATTERN =
  /uefa|champions league|europa league|euro 20|copa america|nations league|international friendly/i;

export function isSpotlightFixture(match: ScrapedMatch) {
  if (match.kind !== "fixture") return false;
  const text = [match.title, match.displayTitle, match.league, match.subtitle, match.sport].filter(Boolean).join(" ");
  return SPOTLIGHT_PATTERN.test(text);
}

export function pickSpotlightFixtures(matches: ScrapedMatch[], limit = 8) {
  return matches.filter(isSpotlightFixture).slice(0, limit);
}
