import type { ScrapedMatch } from "@/lib/api";
import { canOpenBroadcast, hasStreameXPlayback } from "@/lib/live";
import { isMatchLive } from "@/lib/v2/match-priority";
import { isFixtureTeamsTbd } from "@/lib/fixture-normalization";

export type FixtureCardPhase = "live" | "watch" | "starting" | "soon" | "finished";

/** Consistent league / competition line for hero, cards, and watch chrome. */
export function fixtureLeagueLine(match: ScrapedMatch): string {
  const league = match.league?.trim();
  if (league && league.toLowerCase() !== "football" && league.toLowerCase() !== "soccer") {
    return league;
  }

  return match.subtitle?.trim() || match.sport?.trim() || "Football";
}

export function fixtureCardPhase(match: ScrapedMatch): FixtureCardPhase {
  if (match.status === "Live" || isMatchLive(match)) return "live";
  if (match.status === "Finished") return "finished";

  if (canOpenBroadcast(match) && hasStreameXPlayback(match)) return "watch";
  if (match.status === "Starting Soon") return "starting";
  return "soon";
}

export function fixtureCardIsClickable(match: ScrapedMatch) {
  if (!hasStreameXPlayback(match)) return false;
  const phase = fixtureCardPhase(match);
  return phase === "live" || phase === "watch" || phase === "starting";
}

export function fixtureCardBadgeLabel(phase: FixtureCardPhase): string {
  switch (phase) {
    case "live":
      return "Live";
    case "watch":
      return "Watch";
    case "starting":
      return "Starting soon";
    case "finished":
      return "Full time";
    default:
      return "Soon";
  }
}

/** Human label for non-team event streams (sport field is often "Other"). */
export function eventSportLabel(match: ScrapedMatch): string {
  const sport = match.sport?.trim();
  if (sport && sport.toLowerCase() !== "other") return sport;
  const title = (match.displayTitle || match.title || "").toLowerCase();
  if (/tour de france|cycling|\buci\b/.test(title)) return "Cycling";
  if (/wimbledon|tennis|roland garros|australian open|us open/.test(title)) return "Tennis";
  if (/formula|grand prix|motogp|nascar|indy|\bf1\b/.test(title)) return "Motorsport";
  if (/cricket|t20|test match|\bodi\b/.test(title)) return "Cricket";
  if (/ufc|boxing|mma|fight night/.test(title)) return "Combat";
  const league = match.league?.trim();
  if (league && league.toLowerCase() !== "other") return league;
  return "Live event";
}

/** Headline for knockout slots before teams are known (API sends Home/Away placeholders). */
export function fixtureTbdHeadline(match: ScrapedMatch): string {
  const league = match.league?.trim();
  if (league && !/^(home|away)\s+vs/i.test(league)) return league;
  return match.subtitle?.trim() || "Fixture TBD";
}

export function fixtureTbdSubline(_match?: ScrapedMatch): string {
  return "Teams to be confirmed";
}

export function partitionFixturesByTeams(matches: ScrapedMatch[]) {
  const confirmed: ScrapedMatch[] = [];
  const tbd: ScrapedMatch[] = [];
  for (const match of matches) {
    if (isFixtureTeamsTbd(match)) tbd.push(match);
    else confirmed.push(match);
  }
  return { confirmed, tbd };
}
