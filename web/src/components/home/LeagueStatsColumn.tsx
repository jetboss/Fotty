"use client";

import type { FootballLeagueTab } from "@/lib/football-leagues";
import { standingsSupportsLeague } from "@/lib/football-standings";
import { useLeagueFootballData } from "@/lib/use-league-football-data";
import { LeagueStandingsPanel } from "@/components/home/LeagueStandingsPanel";
import { TopScorersPanel } from "@/components/home/TopScorersPanel";

interface LeagueStatsColumnProps {
  league: FootballLeagueTab;
  maxStandingsRows?: number;
  showFullTableLink?: boolean;
  highlightTeam?: string | null;
  onTeamClick?: (teamName: string) => void;
  variant?: "classic" | "v2";
}

/** Standings + scorers with a single football-data.org fetch. */
export function LeagueStatsColumn({
  league,
  maxStandingsRows = 8,
  showFullTableLink = true,
  highlightTeam = null,
  onTeamClick,
  variant = "classic",
}: LeagueStatsColumnProps) {
  const tableLeague: FootballLeagueTab = standingsSupportsLeague(league) ? league : "premierLeague";
  const data = useLeagueFootballData(tableLeague, true);

  return (
    <>
      <LeagueStandingsPanel
        league={tableLeague}
        maxRows={maxStandingsRows}
        showFullTableLink={showFullTableLink}
        data={data}
        highlightTeam={highlightTeam}
        onTeamClick={onTeamClick}
        variant={variant}
      />
      <TopScorersPanel league={tableLeague} data={data} variant={variant} />
    </>
  );
}
