"use client";

import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { FootballLeagueBar } from "@/components/FootballLeagueBar";
import { LeagueStatsColumn } from "@/components/home/LeagueStatsColumn";
import { useFootballLeaguePreference } from "@/hooks/use-football-league-preference";
import { footballLeaguePersonalizationHint } from "@/lib/football-personalization";
import { useTrackedTeams } from "@/lib/user-experience";
import { cn } from "@/lib/utils";
import { V2PageHeader, V2PageShell, v2PanelClass } from "@/components/v2/V2PageShell";

export default function TablesPageClient({
  backHref = "/",
  variant = "classic",
}: {
  backHref?: string;
  variant?: "classic" | "v2";
}) {
  const isV2 = variant === "v2";
  const { trackedTeams } = useTrackedTeams();
  const [selectedLeague, setSelectedLeague, leagueTabs] = useFootballLeaguePreference(trackedTeams);
  const leagueHint = footballLeaguePersonalizationHint(trackedTeams);

  const tablesContent = (
    <>
      <Link
        href={backHref}
        className="inline-flex items-center gap-2 text-xs font-medium text-text-tertiary transition-colors hover:text-white"
      >
        <ArrowLeft size={14} />
        {isV2 ? "Back to home" : "Back to scores"}
      </Link>

      {isV2 ? (
        <V2PageHeader
          title="League tables"
          subtitle="Live standings and top scorers for Europe's major competitions."
        />
      ) : (
        <header className="space-y-1">
          <h1 className="text-2xl font-black text-white">League tables</h1>
          <p className="text-sm font-medium text-text-secondary">
            Live standings and top scorers for Europe&apos;s major competitions.
          </p>
        </header>
      )}

      <div className={cn(isV2 ? `${v2PanelClass} p-3` : "sm:rounded-xl sm:border sm:border-white/5 sm:bg-surface sm:p-3")}>
        <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-text-tertiary sm:mb-2 sm:text-[11px]">
          Competition
        </p>
        {leagueHint ? (
          <p className="mb-1.5 line-clamp-1 text-[10px] font-medium text-text-tertiary sm:mb-2 sm:line-clamp-none">
            {leagueHint}
          </p>
        ) : null}
        <FootballLeagueBar
          selected={selectedLeague}
          onSelect={setSelectedLeague}
          tabs={leagueTabs}
          variant={variant}
        />
      </div>

      <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1.25fr)_minmax(0,0.75fr)]">
        <LeagueStatsColumn league={selectedLeague} maxStandingsRows={20} showFullTableLink={false} variant={variant} />
      </div>
    </>
  );

  if (isV2) {
    return (
      <V2PageShell innerClassName="max-w-5xl space-y-5">
        {tablesContent}
      </V2PageShell>
    );
  }

  return (
    <div className="min-h-dvh bg-background text-text-primary">
      <div className="mx-auto max-w-3xl space-y-5 px-md py-6 lg:max-w-5xl">
        {tablesContent}
      </div>
    </div>
  );
}
