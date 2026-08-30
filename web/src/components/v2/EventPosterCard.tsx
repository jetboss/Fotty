"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { Play, Radio } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { buildWatchHref, formatKickoff } from "@/lib/live";
import { fixtureDisplayTitle } from "@/lib/fixture-normalization";
import { isOptimizedImageSrc } from "@/lib/image-hosts";
import {
  eventSportLabel,
  fixtureCardBadgeLabel,
  fixtureCardIsClickable,
  fixtureCardPhase,
} from "@/lib/v2/fixture-display";
import { v2HomePath } from "@/lib/v2/preview";
import { cn } from "@/lib/utils";

interface EventPosterCardProps {
  match: ScrapedMatch;
  returnTo?: string;
  className?: string;
  onHover?: (hovered: boolean) => void;
  layout?: "rail" | "fill";
}

export function EventPosterCard({
  match,
  returnTo,
  className,
  onHover,
  layout = "rail",
}: EventPosterCardProps) {
  const watchReturnTo = returnTo ?? v2HomePath();
  const title = fixtureDisplayTitle(match);
  const poster = match.poster?.trim();
  const phase = fixtureCardPhase(match);
  const isLive = phase === "live";
  const isClickable = fixtureCardIsClickable(match);
  const badgeLabel = fixtureCardBadgeLabel(phase);
  const sportLabel = eventSportLabel(match);
  const kickoff = formatKickoff(match.startsAt);

  const [posterError, setPosterError] = useState(false);

  const card = (
    <article
      className={cn(
        "group select-none",
        layout === "fill" ? "w-full" : "w-[280px] shrink-0 snap-start sm:w-[300px]",
        isClickable && "cursor-pointer",
        className
      )}
      onMouseEnter={() => onHover?.(true)}
      onMouseLeave={() => onHover?.(false)}
    >
      <div className="relative w-full rounded-2xl transition-all duration-300 shadow-[0_20px_60px_-15px_rgba(0,0,0,0.85)]">
        <div
          className={cn(
            "relative flex min-h-[168px] w-full flex-col justify-between overflow-hidden rounded-2xl border bg-[#0d0d10] p-4 transition-all duration-300 sm:min-h-[176px] sm:p-5",
            isLive ? "border-white/14 group-hover:border-white/20" : "border-white/[0.08] group-hover:border-white/15"
          )}
        >
          <div className="relative z-10 flex items-start justify-between gap-2">
            <span className="text-[7.5px] font-bold uppercase tracking-[0.13em] text-white/25 truncate">
              {sportLabel}
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
                  phase === "watch" && "bg-white text-zinc-950",
                  phase === "starting" && "bg-amber-400/15 text-amber-300 border border-amber-400/25",
                  phase === "soon" && "bg-white/5 text-white/30 border border-white/[0.06]"
                )}
              >
                {badgeLabel}
              </span>
            )}
          </div>

          <div className="relative z-10 flex flex-1 flex-col items-center justify-center gap-3 py-3 text-center">
            <div className="grid h-14 w-14 place-items-center rounded-2xl border border-white/10 bg-white/[0.05] text-white/80">
              <Play size={22} fill="currentColor" className={isLive ? "text-white" : "text-white/70"} />
            </div>
            <div className="space-y-1">
              <p className="line-clamp-3 text-[15px] font-semibold leading-snug tracking-tight text-white">
                {title}
              </p>
              {kickoff ? <p suppressHydrationWarning className="text-[11px] font-medium text-text-tertiary">{kickoff}</p> : null}
            </div>
          </div>

          <div className="relative z-10 border-t border-white/[0.05] pt-3 text-center">
            <span className="text-[7.5px] font-semibold uppercase tracking-[0.14em] text-white/35">
              {isClickable ? (isLive ? "Tap to watch" : "Ready to watch") : "Stream info updating"}
            </span>
          </div>
        </div>
      </div>
    </article>
  );

  if (!isClickable) return card;
  return <Link href={buildWatchHref(match, watchReturnTo)}>{card}</Link>;
}
