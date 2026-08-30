import { canonicalFootballClubId, canonicalFootballTeamKey } from "@/lib/football-competition-catalog.generated";

/** Normalize club names for filter / highlight matching. */
export function normalizeTeamName(value: string) {
  return canonicalFootballTeamKey(value);
}

export function teamNamesMatch(left: string, right: string) {
  const knownLeft = canonicalFootballClubId(left);
  const knownRight = canonicalFootballClubId(right);
  if (knownLeft || knownRight) return knownLeft !== undefined && knownLeft === knownRight;
  const a = normalizeTeamName(left);
  const b = normalizeTeamName(right);
  if (!a || !b) return false;
  return a === b;
}

export function matchIncludesTeam(
  match: { teams?: { home: { name: string }; away: { name: string } } },
  teamName: string
) {
  if (!match.teams || !teamName.trim()) return false;
  return (
    teamNamesMatch(match.teams.home.name, teamName) || teamNamesMatch(match.teams.away.name, teamName)
  );
}
