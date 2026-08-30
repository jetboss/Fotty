"use client";

import Link from "next/link";
import Image from "next/image";
import { Trophy } from "lucide-react";
import { isOptimizedImageSrc } from "@/lib/image-hosts";
import type { FootballLeagueTab } from "@/lib/football-leagues";
import {
  standingsDisplayLabel,
  standingsSupportsLeague,
  type StandingsRow,
} from "@/lib/football-standings";
import { standingZone } from "@/lib/football-standings-zones";
import { teamNamesMatch } from "@/lib/team-name-match";
import { cn } from "@/lib/utils";
import { v2HomePath, v2TablesPath } from "@/lib/v2/preview";
import { DataRefreshState } from "@/components/FallbackState";
import {
  useLeagueFootballData,
  type LeagueFootballDataState,
} from "@/lib/use-league-football-data";

interface LeagueStandingsPanelProps {
  league: FootballLeagueTab;
  maxRows?: number;
  showFullTableLink?: boolean;
  data?: LeagueFootballDataState;
  highlightTeam?: string | null;
  onTeamClick?: (teamName: string) => void;
  variant?: "classic" | "v2";
}

export function LeagueStandingsPanel(props: LeagueStandingsPanelProps) {
  if (props.data) {
    return <LeagueStandingsPanelInner {...props} data={props.data} />;
  }
  return <LeagueStandingsPanelFetcher {...props} />;
}

function LeagueStandingsPanelFetcher(props: Omit<LeagueStandingsPanelProps, "data">) {
  const data = useLeagueFootballData(props.league, true);
  return <LeagueStandingsPanelInner {...props} data={data} />;
}

function LeagueStandingsPanelInner({
  league,
  maxRows = 8,
  showFullTableLink = true,
  data,
  highlightTeam = null,
  onTeamClick,
  variant = "classic",
}: LeagueStandingsPanelProps & { data: LeagueFootballDataState }) {
  const isV2 = variant === "v2";
  const rows = (data.standings ?? []).slice(0, maxRows);
  const label = standingsDisplayLabel(league);

  const emptyMessage =
    data.error ??
    data.message ??
    (!standingsSupportsLeague(league)
      ? "Choose a supported league for standings."
      : "No standings for this competition.");

  return (
    <section className={cn("rounded-xl p-4", isV2 ? "bg-white/[0.02] ring-1 ring-white/[0.06]" : "border border-white/5 bg-surface")}>
      <div className="mb-3 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Trophy size={16} className="text-live" />
          <div>
            <h2 className={cn("text-xs uppercase tracking-wide text-text-primary", isV2 ? "font-semibold" : "font-black")}>
              {label} table
            </h2>
          </div>
        </div>
        {showFullTableLink ? (
          <Link
            href={isV2 ? v2TablesPath() : "/tables"}
            className={cn("text-[10px] font-bold hover:underline", isV2 ? "text-text-secondary hover:text-white" : "text-accent")}
          >
            Full table
          </Link>
        ) : null}
      </div>

      {data.loading ? (
        <StandingsSkeleton />
      ) : rows.length === 0 ? (
        <DataRefreshState
          title="Tables are being refreshed"
          message={
            emptyMessage ||
            "League standings and top scorers are being prepared. Match fixtures remain available while tables update."
          }
          primaryAction={{ label: isV2 ? "Back to home" : "Back to Fixtures", href: isV2 ? v2HomePath() : "/" }}
          compact
          inline
          variant={variant}
        />
      ) : (
        <StandingsTable
          rows={rows}
          league={league}
          compact={maxRows <= 10}
          highlightTeam={highlightTeam}
          onTeamClick={onTeamClick}
          variant={variant}
        />
      )}
    </section>
  );
}

export function StandingsTable({
  rows,
  league,
  compact,
  highlightTeam = null,
  onTeamClick,
  variant = "classic",
}: {
  rows: StandingsRow[];
  league: FootballLeagueTab;
  compact?: boolean;
  highlightTeam?: string | null;
  onTeamClick?: (teamName: string) => void;
  variant?: "classic" | "v2";
}) {
  const isV2 = variant === "v2";
  const totalTeams = rows.length > 0 ? Math.max(...rows.map((row) => row.position)) : 0;

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[280px] text-left text-[11px]">
        <thead>
          <tr className="text-text-tertiary">
            <th className="pb-2 pr-2 font-bold">#</th>
            <th className="pb-2 font-bold">Team</th>
            <th className="pb-2 px-1 text-center font-bold">P</th>
            <th className="pb-2 px-1 text-center font-bold">Pts</th>
            {!compact ? <th className="hidden pb-2 px-1 text-center font-bold sm:table-cell">GD</th> : null}
            <th className="pb-2 pl-1 text-right font-bold">Form</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            const zone = standingZone(row.position, totalTeams, league);
            const highlighted = highlightTeam ? teamNamesMatch(row.teamName, highlightTeam) : false;
            return (
              <tr
                key={`${row.position}-${row.teamName}`}
                className={cn(
                  "border-t border-white/5",
                  zone === "champions" && "bg-success/5",
                  zone === "relegation" && "bg-error/5",
                  highlighted && (isV2 ? "bg-white/[0.06]" : "bg-accent/10")
                )}
              >
                <td className={cn("py-2 pr-2 text-text-secondary", isV2 ? "font-semibold" : "font-black")}>{row.position}</td>
                <td className="py-2">
                  <div className="flex min-w-0 items-center gap-2">
                    {row.teamCrest ? (
                      <Image
                        src={row.teamCrest}
                        alt=""
                        width={18}
                        height={18}
                        unoptimized={!isOptimizedImageSrc(row.teamCrest)}
                        className="h-[18px] w-[18px] shrink-0 object-contain"
                      />
                    ) : null}
                    {onTeamClick ? (
                      <button
                        type="button"
                        onClick={() => onTeamClick(row.teamName)}
                        className={cn(
                          "truncate text-left font-semibold text-text-primary",
                          isV2 ? "hover:text-white" : "hover:text-accent"
                        )}
                      >
                        {row.teamName}
                      </button>
                    ) : (
                      <span className="truncate font-semibold text-text-primary">{row.teamName}</span>
                    )}
                  </div>
                </td>
                <td className="py-2 px-1 text-center text-text-secondary">{row.played}</td>
                <td className={cn("py-2 px-1 text-center text-text-primary", isV2 ? "font-semibold" : "font-black")}>{row.points}</td>
                {!compact ? (
                  <td className="hidden py-2 px-1 text-center text-text-secondary sm:table-cell">
                    {row.goalDifference != null
                      ? row.goalDifference > 0
                        ? `+${row.goalDifference}`
                        : row.goalDifference
                      : "—"}
                  </td>
                ) : null}
                <td className="py-2 pl-1 text-right">
                  <FormDots form={row.form} />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {!compact && rows.length > 0 ? (
        <p className="mt-2 text-[10px] text-text-tertiary">
          <span className="mr-1 inline-block h-2 w-2 rounded-full bg-success/40 align-middle" />
          Top places ·
          <span className="mx-1 inline-block h-2 w-2 rounded-full bg-error/40 align-middle" />
          Relegation zone
        </p>
      ) : null}
    </div>
  );
}

function StandingsSkeleton() {
  return (
    <div className="space-y-2">
      {[0, 1, 2, 3, 4].map((i) => (
        <div key={i} className="h-8 animate-pulse rounded bg-white/5" />
      ))}
    </div>
  );
}

function FormDots({ form }: { form?: string }) {
  if (!form) return <span className="text-text-tertiary">—</span>;
  const chars = form.replace(/,/g, "").slice(-5).split("");
  return (
    <span className="inline-flex justify-end gap-0.5">
      {chars.map((char, index) => (
        <span
          key={`${char}-${index}`}
          className={
            char === "W"
              ? "inline-flex h-4 w-4 items-center justify-center rounded-full bg-success/20 text-[9px] font-black text-success"
              : char === "L"
                ? "inline-flex h-4 w-4 items-center justify-center rounded-full bg-error/20 text-[9px] font-black text-error"
                : "inline-flex h-4 w-4 items-center justify-center rounded-full bg-white/10 text-[9px] font-black text-text-secondary"
          }
        >
          {char}
        </span>
      ))}
    </span>
  );
}
