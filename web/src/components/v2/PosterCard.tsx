"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { Radio } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { buildWatchHref, formatKickoff } from "@/lib/live";
import { estimateMatchClock } from "@/lib/match-clock";
import { fixtureTeamLabels, isEventFixture, isKnockoutBracketTbd } from "@/lib/fixture-normalization";
import { isOptimizedImageSrc } from "@/lib/image-hosts";
import { cn } from "@/lib/utils";
import {
  fixtureCardBadgeLabel,
  fixtureCardIsClickable,
  fixtureCardPhase,
  fixtureLeagueLine,
} from "@/lib/v2/fixture-display";
import { v2HomePath } from "@/lib/v2/preview";
import { resolveTeamColor } from "@/lib/v2/team-colors";
import { TeamFlagSquircle } from "@/components/v2/TeamFlagSquircle";
import { EventPosterCard } from "@/components/v2/EventPosterCard";
import { TbdBracketCard } from "@/components/v2/TbdBracketCard";

interface PosterCardProps {
  match: ScrapedMatch;
  returnTo?: string;
  className?: string;
  onHover?: (hovered: boolean) => void;
  /** `rail` = fixed width for horizontal scroll; `fill` = full grid cell width */
  layout?: "rail" | "fill";
}

export function PosterCard(props: PosterCardProps) {
  const { match, returnTo, className, onHover, layout = "rail" } = props;
  if (isKnockoutBracketTbd(match)) {
    return <TbdBracketCard match={match} layout={layout} className={className} />;
  }

  if (isEventFixture(match)) {
    return (
      <EventPosterCard
        match={match}
        returnTo={returnTo}
        className={className}
        onHover={onHover}
        layout={layout}
      />
    );
  }

  return <FixturePosterCard {...props} />;
}

function FixturePosterCard({ match, returnTo, className, onHover, layout = "rail" }: PosterCardProps) {
  const watchReturnTo = returnTo ?? v2HomePath();
  const labels = fixtureTeamLabels(match);
  const poster = match.poster?.trim();
  const phase = fixtureCardPhase(match);
  const isLive = phase === "live";
  const isClickable = fixtureCardIsClickable(match);
  const showScore = isLive && match.score;
  const leagueLine = fixtureLeagueLine(match);
  const badgeLabel = fixtureCardBadgeLabel(phase);

  const homeColor = resolveTeamColor(labels.home);
  const awayColor = resolveTeamColor(labels.away);
  const glowColor = homeColor ?? awayColor ?? null;
  const flagSize = layout === "fill" ? 92 : 76;

  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!isLive) return;
    const id = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(id);
  }, [isLive]);

  const clock = estimateMatchClock({
    startsAt: match.startsAt,
    sport: match.sport,
    apiStatus: match.status,
    now,
  });

  const competitionChip = match.league ?? match.sport ?? "";

  // Short kickoff label for center column between team names
  const kickoffLabel = formatKickoff(match.startsAt) ?? "";
  const centerMeta = isLive ? (clock || "Live now") : kickoffLabel;

  const [posterError, setPosterError] = useState(false);

  const card = (
    <article
      className={cn(
        "group select-none",
        layout === "fill" ? "w-full" : "w-[280px] sm:w-[300px] shrink-0 snap-start",
        isClickable && "cursor-pointer",
        className
      )}
      onMouseEnter={() => onHover?.(true)}
      onMouseLeave={() => onHover?.(false)}
    >
      {/* Outer glow container */}
      <div
        className="relative w-full rounded-2xl transition-all duration-300"
        style={
          glowColor
            ? {
                boxShadow: isLive
                  ? `0 0 0 1px rgba(255,255,255,0.14), 0 0 32px -12px ${glowColor}44, 0 20px 60px -15px rgba(0,0,0,0.85)`
                  : `0 0 0 1px ${glowColor}22, 0 20px 60px -15px rgba(0,0,0,0.85)`,
              }
            : { boxShadow: "0 20px 60px -15px rgba(0,0,0,0.85)" }
        }
      >
        <div
          className={cn(
            "relative w-full overflow-hidden rounded-2xl bg-[#0d0d10] border p-4 flex flex-col gap-3.5 transition-all duration-300 sm:p-5 sm:gap-4",
            isLive ? "border-white/14 group-hover:border-white/20" : "border-white/[0.08] group-hover:border-white/15"
          )}
          style={
            glowColor
              ? { boxShadow: `inset 0 0 40px -20px ${glowColor}33` }
              : undefined
          }
        >
          {/* ── Row 1: Compact header — just group label + watch/live badge ── */}
          <div className="relative z-10 flex items-center justify-between gap-2">
            <span className="text-[7.5px] font-bold uppercase tracking-[0.13em] text-white/25 truncate">
              {competitionChip}
            </span>
            {isLive ? (
              <span className="inline-flex shrink-0 items-center gap-1 rounded-md bg-red-500/15 px-1.5 py-0.5 text-[7.5px] font-bold text-red-400 ring-1 ring-red-500/30">
                <Radio size={7} className="animate-pulse" />
                {isClickable ? "Watch live" : badgeLabel}
              </span>
            ) : (
              <span
                className={cn(
                  "shrink-0 rounded-md px-1.5 py-0.5 text-[7.5px] font-bold",
                  phase === "watch" && "bg-white",
                  phase === "starting" && "bg-amber-400/15 text-amber-300 border border-amber-400/25",
                  phase === "soon" && "bg-white/5 text-white/30 border border-white/[0.06]",
                  phase === "finished" && "bg-white/5 text-white/25 border border-white/[0.06]"
                )}
                style={phase === "watch" ? { color: "#09090b" } : undefined}
              >
                {badgeLabel}
              </span>
            )}
          </div>

          {/* ── Row 2: Team names + centered kickoff info ── */}
          <div className="relative z-10 grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-2">
            <span className="truncate text-[13px] font-bold text-white leading-tight" title={labels.home}>
              {labels.home}
            </span>

            <div className="flex min-w-[4rem] flex-col items-center gap-0.5 px-1">
              <span
                suppressHydrationWarning
                className={cn(
                  "text-[9px] font-semibold text-center leading-snug",
                  isLive ? "text-emerald-400 font-bold tabular-nums" : "text-white/40"
                )}
              >
                {centerMeta}
              </span>
              <span className="text-[7.5px] font-medium text-white/25 text-center leading-snug truncate max-w-[80px]">
                {leagueLine}
              </span>
            </div>

            <span className="truncate text-right text-[13px] font-bold text-white leading-tight" title={labels.away}>
              {labels.away}
            </span>
          </div>

          {/* ── Row 3: Big flags + VS badge (the hero row, matching mockup) ── */}
          <div className="relative z-10 flex items-center justify-center gap-2">
            <TeamFlagSquircle name={labels.home} badge={labels.homeBadge} size={flagSize} />

            <div className="flex shrink-0 flex-col items-center gap-1.5">
              {showScore ? (
                <div
                  className="flex h-12 w-12 items-center justify-center rounded-2xl border border-white/10 text-[15px] font-black tabular-nums text-white sm:h-14 sm:w-14 sm:text-[16px]"
                  style={{ background: "linear-gradient(160deg, #1e3a5f, #0f1f3d)" }}
                >
                  {match.score!.home}–{match.score!.away}
                </div>
              ) : (
                <div
                  className="flex h-12 w-12 items-center justify-center rounded-2xl border border-blue-500/20 text-[14px] font-black text-white/70 sm:h-14 sm:w-14 sm:text-[15px]"
                  style={{ background: "linear-gradient(160deg, #1e3a5f, #0f1f3d)" }}
                >
                  VS
                </div>
              )}
              <span className="text-[8px] font-medium text-white/30 text-center">
                {isLive ? (
                  <span className="font-semibold uppercase tracking-wide text-white/50">On Fotty now</span>
                ) : (
                  "Fixture"
                )}
              </span>
            </div>

            <TeamFlagSquircle name={labels.away} badge={labels.awayBadge} size={flagSize} />
          </div>

          {/* ── Bottom border — clean finish like the mockup ── */}
          <div className="relative z-10 border-t border-white/[0.05] pt-3 flex items-center justify-between">
            <span className="text-[7px] font-medium text-white/20 uppercase tracking-widest truncate pr-2">
              {leagueLine}
            </span>
            {isLive ? (
              <span className="inline-flex shrink-0 items-center gap-1 text-[7.5px] font-bold text-white/60">
                <Radio size={7} className="animate-pulse" />
                Live
              </span>
            ) : phase === "watch" ? (
              <span className="text-[7.5px] font-bold text-white/70">Ready to watch</span>
            ) : null}
          </div>
        </div>
      </div>
    </article>
  );

  if (!isClickable) return card;
  return (
    <Link
      href={buildWatchHref(match, watchReturnTo)}
      aria-label={`Watch ${labels.home} vs ${labels.away} — ${badgeLabel}`}
    >
      {card}
    </Link>
  );
}
