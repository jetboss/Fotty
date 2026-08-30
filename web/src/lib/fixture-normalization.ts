import type { ScrapedMatch, TeamReference } from "@/lib/api";

const PLACEHOLDER_TEAM_RE = /^(home|away|team|team\s*\d+|tbd|to be decided|unknown|fixture|club)$/i;
const TEAM_SEPARATOR_RE = /\s+(?:vs\.?|v|@)\s+/i;
const ROUGH_PROVIDER_TOKEN_RE = /^[A-Z0-9]{1,3}$/;
const KNOWN_PUBLIC_SHORT_NAMES = new Set([
  "AEK",
  "AZ",
  "BVB",
  "LAFC",
  "NYCFC",
  "NYRB",
  "PSG",
  "PSV",
  "QPR",
  "UAE",
  "USA",
]);
export const TEAM_UPDATING_LABEL = "Team updating";
export const FIXTURE_UPDATING_TITLE = "Fixture details updating";

export interface FixtureTeamLabels {
  home: string;
  away: string;
  homeBadge?: string;
  awayBadge?: string;
  isUpdating: boolean;
}

export function cleanFixtureTitle(value?: string) {
  return (value || "")
    .replace(/\s+/g, " ")
    .replace(/\s+vs\s+/i, " vs. ")
    .replace(/\s+v\s+/i, " vs. ")
    .trim();
}

export function isPlaceholderTeamName(value?: string) {
  const name = value?.trim();
  if (!name) return true;
  return PLACEHOLDER_TEAM_RE.test(name);
}

export function isRoughProviderTeamName(value?: string) {
  const name = cleanFixtureTitle(value).replace(/\./g, "").trim();
  if (!name) return true;
  const compact = name.replace(/\s+/g, "");
  if (KNOWN_PUBLIC_SHORT_NAMES.has(compact.toUpperCase())) return false;
  return ROUGH_PROVIDER_TOKEN_RE.test(compact);
}

export function isPublicFixtureTeamName(value?: string) {
  return !isPlaceholderTeamName(value) && !isRoughProviderTeamName(value);
}

export function splitFixtureTitle(value?: string) {
  const title = cleanFixtureTitle(value);
  const parts = title.split(TEAM_SEPARATOR_RE).map((part) => part.trim()).filter(Boolean);
  if (parts.length < 2) return undefined;

  const [home, ...awayParts] = parts;
  const away = awayParts.join(" vs. ");
  if (!isPublicFixtureTeamName(home) || !isPublicFixtureTeamName(away)) return undefined;
  return { home, away };
}

function validTeam(team?: TeamReference) {
  if (!team || !isPublicFixtureTeamName(team.name)) return undefined;
  return team;
}

function teamFromName(name?: string, fallbackBadge?: string): TeamReference | undefined {
  const cleaned = cleanFixtureTitle(name);
  if (!isPublicFixtureTeamName(cleaned)) return undefined;
  return {
    name: cleaned,
    badge: fallbackBadge || name?.slice(0, 2).toUpperCase(),
  };
}

export function normalizeFixtureMatch(match: ScrapedMatch): ScrapedMatch {
  if (match.kind !== "fixture") {
    return {
      ...match,
      displayTitle: cleanFixtureTitle(match.displayTitle || match.title) || match.displayTitle || match.title,
    };
  }

  const parsed = splitFixtureTitle(match.displayTitle || match.title);
  const existingHome = validTeam(match.teams?.home);
  const existingAway = validTeam(match.teams?.away);
  const home = existingHome || teamFromName(parsed?.home, match.teams?.home?.badge);
  const away = existingAway || teamFromName(parsed?.away, match.teams?.away?.badge);
  const hasTeams = Boolean(home && away);
  const cleanedTitle = cleanFixtureTitle(match.displayTitle || match.title);
  // Non-team events (motorsport races, fight cards, etc.) keep their real
  // title; the placeholder is only for empty or junk provider titles.
  const displayTitle = hasTeams
    ? `${home!.name} vs. ${away!.name}`
    : cleanedTitle && !isPlaceholderTeamName(cleanedTitle)
      ? cleanedTitle
      : FIXTURE_UPDATING_TITLE;

  return {
    ...match,
    title: cleanFixtureTitle(match.title) || match.title,
    displayTitle,
    teams: hasTeams ? { home: home!, away: away! } : undefined,
  };
}

export function fixtureDisplayTitle(match: ScrapedMatch) {
  return cleanFixtureTitle(match.displayTitle || match.title) || FIXTURE_UPDATING_TITLE;
}

export function isFixtureTeamsTbd(match: ScrapedMatch) {
  return isKnockoutBracketTbd(match);
}

/** Knockout slots waiting on prior results — API sends Home/Away placeholders. */
export function isKnockoutBracketTbd(match: ScrapedMatch) {
  if (match.kind !== "fixture") return false;

  const normalized = normalizeFixtureMatch(match);
  const home = normalized.teams?.home?.name?.trim();
  const away = normalized.teams?.away?.name?.trim();
  if (home || away) {
    return isPlaceholderTeamName(home) || isPlaceholderTeamName(away);
  }

  const title = cleanFixtureTitle(match.displayTitle || match.title);
  const parts = title.split(TEAM_SEPARATOR_RE).map((part) => part.trim()).filter(Boolean);
  if (parts.length >= 2) {
    return isPlaceholderTeamName(parts[0]) || isPlaceholderTeamName(parts[1]);
  }

  return isPlaceholderTeamName(title);
}

/** Live streams and PPV events without a home/away pair (cycling, tennis, etc.). */
export function isEventFixture(match: ScrapedMatch) {
  if (match.kind !== "fixture" || isKnockoutBracketTbd(match)) return false;
  const labels = fixtureTeamLabels(match);
  if (!labels.isUpdating) return false;
  const title = cleanFixtureTitle(match.displayTitle || match.title);
  return Boolean(title && title !== FIXTURE_UPDATING_TITLE);
}

export function fixtureTeamLabels(match: ScrapedMatch): FixtureTeamLabels {
  const normalized = normalizeFixtureMatch(match);
  const parsed = splitFixtureTitle(normalized.displayTitle || normalized.title);
  const home = validTeam(normalized.teams?.home) || teamFromName(parsed?.home, normalized.teams?.home?.badge);
  const away = validTeam(normalized.teams?.away) || teamFromName(parsed?.away, normalized.teams?.away?.badge);

  return {
    home: home?.name || TEAM_UPDATING_LABEL,
    away: away?.name || TEAM_UPDATING_LABEL,
    homeBadge: home?.badge,
    awayBadge: away?.badge,
    isUpdating: !home || !away,
  };
}
