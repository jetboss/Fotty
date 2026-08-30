"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { Bell, CalendarDays, Play, Radio } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { buildWatchHref, canOpenBroadcast, formatKickoff } from "@/lib/live";
import { estimateMatchClock } from "@/lib/match-clock";
import { fixtureDisplayTitle, fixtureTeamLabels } from "@/lib/fixture-normalization";
import { isOptimizedImageSrc } from "@/lib/image-hosts";
import { v2AppPath, v2HomePath } from "@/lib/v2/preview";
import { fixtureLeagueLine } from "@/lib/v2/fixture-display";
import { isMatchLive } from "@/lib/v2/match-priority";
import { ReminderButton } from "@/components/ReminderButton";
import { resolveTeamColor } from "@/lib/v2/team-colors";
import { TeamFlagSquircle } from "@/components/v2/TeamFlagSquircle";
import { cn } from "@/lib/utils";

interface HeroMatchProps {
  match: ScrapedMatch;
  returnTo?: string;
  badge?: string;
  className?: string;
}

export function HeroMatch({ match, returnTo, badge, className }: HeroMatchProps) {
  const watchReturnTo = returnTo ?? v2HomePath();
  const labels = fixtureTeamLabels(match);
  const title = fixtureDisplayTitle(match);
  const poster = match.poster?.trim();
  const isLive = isMatchLive(match);
  const canWatch = canOpenBroadcast(match);
  const kickoff = formatKickoff(match.startsAt);
  const league = fixtureLeagueLine(match);
  const hasTeams = !labels.isUpdating;
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(id);
  }, []);

  const clock = estimateMatchClock({
    startsAt: match.startsAt,
    sport: match.sport,
    apiStatus: match.status,
    now,
  });

  const homeColor = resolveTeamColor(labels.home);
  const awayColor = resolveTeamColor(labels.away);

  return (
    <section className={cn("relative overflow-x-clip", className)}>
      <div className="relative min-h-[min(50vh,480px)] w-full lg:min-h-[min(46vh,440px)]">
      {/* ── Layer 0: Deep base ── */}
        <div className="absolute inset-0 z-0" style={{ background: "#07070a" }} />

        {/* ── Layer 1: Team-color cinematic split-lighting ── */}
        <div
          className="absolute inset-0 z-[1] pointer-events-none"
          style={{
            background: [
              homeColor ? `radial-gradient(ellipse 55% 80% at 15% 50%, ${homeColor}3a 0%, transparent 65%)` : "",
              awayColor ? `radial-gradient(ellipse 55% 80% at 85% 50%, ${awayColor}3a 0%, transparent 65%)` : "",
              homeColor ? `radial-gradient(ellipse 30% 40% at 0% 100%, ${homeColor}25 0%, transparent 50%)` : "",
              awayColor ? `radial-gradient(ellipse 30% 40% at 100% 100%, ${awayColor}25 0%, transparent 50%)` : "",
            ].filter(Boolean).join(", "),
          }}
        />

        {/* ── Layer 3: Vignette & gradient overlays ── */}
        <div className="absolute inset-0 z-[3] pointer-events-none" style={{
          background: "radial-gradient(ellipse 100% 100% at 50% 50%, transparent 20%, rgba(0,0,0,0.7) 100%)"
        }} />
        <div className="absolute inset-0 z-[3] bg-gradient-to-r from-black/80 via-black/40 to-black/60 pointer-events-none" />
        <div className="absolute inset-0 z-[3] bg-gradient-to-t from-[var(--v2-background)] via-transparent to-black/30 pointer-events-none" />

        <div className="relative z-[10] mx-auto flex h-full max-w-[1440px] flex-col justify-end gap-6 px-4 pb-8 pt-20 lg:flex-row lg:items-end lg:gap-10 lg:px-8 lg:pb-10 lg:pt-24">


          <div className="min-w-0 flex-1 space-y-5">
            <div className="flex flex-wrap items-center gap-2">
              {badge ? (
                <span className="rounded-full bg-white/12 px-3 py-1 text-[11px] font-semibold tracking-wide text-white">
                  {badge}
                </span>
              ) : null}
              {isLive ? (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-1 text-[11px] font-bold text-zinc-950">
                  <Radio size={12} className="animate-pulse" />
                  Live now
                </span>
              ) : match.status === "Finished" && match.score ? (
                <span className="rounded-full border border-white/12 bg-white/5 px-3 py-1 text-[11px] font-semibold text-white/90">
                  Full time
                </span>
              ) : kickoff ? (
                <span suppressHydrationWarning className="rounded-full border border-white/12 bg-white/5 px-3 py-1 text-[11px] font-medium text-white/90">
                  {kickoff}
                </span>
              ) : null}
              {clock && isLive ? (
                <span suppressHydrationWarning className="rounded-full border border-white/10 px-3 py-1 text-[11px] font-semibold tabular-nums text-white/90">
                  {clock}
                </span>
              ) : null}
            </div>

            {hasTeams ? (
              <div className="space-y-3">
                <div className="flex max-w-xl items-end justify-center gap-3 sm:gap-5">
                  <div className="flex w-[110px] flex-col items-center gap-2.5">
                    <p className="w-full truncate text-center text-xs font-bold tracking-tight text-white sm:text-sm" title={labels.home}>
                      {labels.home}
                    </p>
                    <TeamFlagSquircle
                      name={labels.home}
                      badge={labels.homeBadge}
                      size={96}
                      radiusClass="rounded-[22px]"
                      borderWidth={2.5}
                    />
                  </div>

                  <div className="flex shrink-0 flex-col items-center gap-2 pb-1">
                    {match.score && (isLive || match.status === "Finished") ? (
                      <div
                        className="flex h-14 w-14 items-center justify-center rounded-2xl border border-white/12 text-lg font-black tabular-nums text-white sm:h-16 sm:w-16 sm:text-xl"
                        style={{ background: "linear-gradient(160deg, #1e3a5f, #0f1f3d)" }}
                      >
                        {match.score.home}
                        <span className="mx-1 text-white/35">–</span>
                        {match.score.away}
                      </div>
                    ) : (
                      <div
                        className="flex h-14 w-14 items-center justify-center rounded-2xl border border-blue-500/25 text-sm font-black uppercase tracking-[0.18em] text-white/75 sm:h-16 sm:w-16 sm:text-base"
                        style={{ background: "linear-gradient(160deg, #1e3a5f, #0f1f3d)" }}
                      >
                        vs
                      </div>
                    )}
                    <p className="max-w-[9rem] text-center text-[11px] font-medium leading-snug text-white/45">
                      {league}
                    </p>
                  </div>

                  <div className="flex w-[110px] flex-col items-center gap-2.5">
                    <p className="w-full truncate text-center text-xs font-bold tracking-tight text-white sm:text-sm" title={labels.away}>
                      {labels.away}
                    </p>
                    <TeamFlagSquircle
                      name={labels.away}
                      badge={labels.awayBadge}
                      size={96}
                      radiusClass="rounded-[22px]"
                      borderWidth={2.5}
                    />
                  </div>
                </div>
              </div>
            ) : null}

            <div className="space-y-2">
              <h1 className="max-w-3xl text-2xl font-semibold leading-tight tracking-tight text-white sm:text-3xl lg:text-[2.35rem]">
                {hasTeams ? (
                  <>
                    {labels.home} <span className="text-white/35">v</span> {labels.away}
                  </>
                ) : (
                  title
                )}
              </h1>
              {!hasTeams ? <p className="text-sm font-medium text-text-tertiary">{league}</p> : null}
            </div>

            <div className="flex flex-wrap gap-2.5 pt-1">
              {canWatch ? (
                <Link
                  href={buildWatchHref(match, watchReturnTo)}
                  className="inline-flex items-center gap-2 rounded-full bg-white px-5 py-2.5 text-sm font-semibold shadow-sm transition hover:bg-zinc-100"
                  style={{ color: "#09090b" }}
                >
                  <Play size={16} fill="currentColor" style={{ color: "#09090b" }} />
                  <span style={{ color: "#09090b" }}>{isLive ? "Watch live" : "Watch"}</span>
                </Link>
              ) : isLive ? (
                <Link
                  href={v2AppPath("/search")}
                  className="inline-flex items-center gap-2 rounded-full bg-white px-5 py-2.5 text-sm font-semibold shadow-sm transition hover:bg-zinc-100"
                  style={{ color: "#09090b" }}
                >
                  <Play size={16} fill="currentColor" style={{ color: "#09090b" }} />
                  <span style={{ color: "#09090b" }}>Find matches</span>
                </Link>
              ) : (
                <ReminderButton match={match} returnTo={watchReturnTo} />
              )}
              <Link
                href={v2AppPath("/schedule")}
                className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-white/10"
              >
                <CalendarDays size={16} />
                Schedule
              </Link>
            </div>
          </div>

        </div>
      </div>
    </section>
  );
}

export function HeroEmpty({ trackedCount }: { trackedCount: number }) {
  return (
    <section className="border-b border-white/[0.06] px-4 py-16 lg:px-8">
      <div className="mx-auto max-w-xl space-y-4 text-center">
        <Bell className="mx-auto text-text-tertiary" size={28} />
        <h1 className="text-2xl font-semibold text-white">Nothing live right now</h1>
        <p className="text-sm leading-relaxed text-text-secondary">
          {trackedCount > 0
            ? "Fotty will surface your teams when a match is ready to watch."
            : "Track teams to personalize home, or open the schedule for upcoming kickoffs."}
        </p>
        <div className="flex flex-wrap justify-center gap-2 pt-2">
          <Link
            href={v2AppPath("/teams")}
            className="fotty-v2-primary-cta rounded-full bg-white px-4 py-2 text-sm font-semibold shadow-sm transition hover:bg-zinc-100"
            style={{ color: "#09090b" }}
          >
            {trackedCount > 0 ? "Manage teams" : "Add teams"}
          </Link>
          <Link
            href={v2AppPath("/schedule")}
            className="rounded-full border border-white/15 px-4 py-2 text-sm font-medium text-white"
          >
            Open schedule
          </Link>
        </div>
      </div>
    </section>
  );
}
