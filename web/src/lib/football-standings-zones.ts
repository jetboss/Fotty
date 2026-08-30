import type { FootballLeagueTab } from "@/lib/football-leagues";

export type StandingZone = "champions" | "relegation" | null;

/** Simple zone tint for domestic leagues and UCL league phase. */
export function standingZone(
  position: number,
  totalTeams: number,
  league: FootballLeagueTab
): StandingZone {
  if (totalTeams < 4) return null;

  if (league === "championsLeague") {
    if (position <= 8) return "champions";
    return null;
  }

  if (league === "premierLeague" || league === "laLiga" || league === "serieA" || league === "bundesliga") {
    if (position <= 4) return "champions";
    if (position >= totalTeams - 2) return "relegation";
    return null;
  }

  if (league === "ligue1") {
    if (position <= 3) return "champions";
    if (position >= totalTeams - 2) return "relegation";
    return null;
  }

  if (position <= 4) return "champions";
  if (position >= totalTeams - 2) return "relegation";
  return null;
}
