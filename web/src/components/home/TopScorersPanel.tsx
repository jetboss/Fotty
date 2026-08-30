"use client";

import { Target } from "lucide-react";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import { standingsDisplayLabel, standingsSupportsLeague } from "@/lib/football-standings";
import { cn } from "@/lib/utils";
import { v2HomePath } from "@/lib/v2/preview";
import { DataRefreshState } from "@/components/FallbackState";
import {
  useLeagueFootballData,
  type LeagueFootballDataState,
} from "@/lib/use-league-football-data";

interface TopScorersPanelProps {
  league: FootballLeagueTab;
  maxRows?: number;
  data?: LeagueFootballDataState;
  variant?: "classic" | "v2";
}

export function TopScorersPanel(props: TopScorersPanelProps) {
  if (props.data) {
    return <TopScorersPanelInner {...props} data={props.data} />;
  }
  return <TopScorersPanelFetcher {...props} />;
}

function TopScorersPanelFetcher(props: Omit<TopScorersPanelProps, "data">) {
  const data = useLeagueFootballData(props.league, true);
  return <TopScorersPanelInner {...props} data={data} />;
}

function TopScorersPanelInner({
  league,
  maxRows = 5,
  data,
  variant = "classic",
}: TopScorersPanelProps & { data: LeagueFootballDataState }) {
  const isV2 = variant === "v2";
  const scorers = (data.scorers ?? []).slice(0, maxRows);
  const label = standingsDisplayLabel(league);

  return (
    <section className={cn("rounded-xl p-4", isV2 ? "bg-white/[0.02] ring-1 ring-white/[0.06]" : "border border-white/5 bg-surface")}>
      <div className="mb-3 flex items-center gap-2">
        <Target size={16} className={isV2 ? "text-white/70" : "text-accent"} />
        <h2 className={cn("text-xs uppercase tracking-wide text-text-primary", isV2 ? "font-semibold" : "font-black")}>
          Top scorers · {label}
        </h2>
      </div>

      {data.loading ? (
        <div className="space-y-2">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-10 animate-pulse rounded bg-white/5" />
          ))}
        </div>
      ) : scorers.length === 0 ? (
        <DataRefreshState
          title="Scorers are being refreshed"
          message={
            !standingsSupportsLeague(league) || data.error
              ? "Player stats for this competition are being prepared. Match fixtures remain available while the table feed updates."
              : "Top scorer data is being prepared. Match fixtures remain available while tables update."
          }
          primaryAction={{ label: isV2 ? "Back to home" : "Back to Fixtures", href: isV2 ? v2HomePath() : "/" }}
          compact
          inline
          variant={variant}
        />
      ) : (
        <ul className="space-y-2">
          {scorers.map((row, index) => (
            <li
              key={`${row.playerName}-${row.teamName}`}
              className={cn(
                "flex items-center justify-between gap-2 rounded-lg px-3 py-2",
                isV2 ? "bg-white/[0.02] ring-1 ring-white/[0.05]" : "border border-white/5 bg-white/[0.02]"
              )}
            >
              <div className="min-w-0">
                <p className="truncate text-xs font-semibold text-text-primary">{row.playerName}</p>
                <p className="truncate text-[10px] text-text-tertiary">{row.teamName}</p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <span className={cn("text-[10px] text-text-tertiary", isV2 ? "font-semibold" : "font-black")}>#{index + 1}</span>
                <span className={cn("text-sm tabular-nums text-live", isV2 ? "font-semibold" : "font-black")}>{row.goals}</span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
