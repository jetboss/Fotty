"use client";

import React from "react";
import Image from "next/image";
import type { ScrapedMatch } from "@/lib/api";
import { TeamBadge } from "@/components/TeamBadge";
import { isOptimizedImageSrc } from "@/lib/image-hosts";
import { cn } from "@/lib/utils";

/** Streamed.pk proxy posters are ~444×250; avoid upscaling past native width. */
const POSTER_NATIVE_MAX_PX = 444;

interface FeaturedMatchHeroProps {
  match: ScrapedMatch;
  title: string;
  className?: string;
}

export function FeaturedMatchHero({ match, title, className }: FeaturedMatchHeroProps) {
  const poster = match.poster?.trim();
  const hasTeams = Boolean(match.teams?.home?.name && match.teams?.away?.name);

  return (
    <div
      className={cn(
        "relative w-full overflow-hidden bg-background",
        "aspect-[16/9] min-h-[170px] max-h-[min(48vh,440px)]",
        "sm:aspect-[2/1] lg:aspect-[21/9]",
        className
      )}
    >
      {poster ? <PosterHero poster={poster} title={title} /> : hasTeams ? <BadgeHero match={match} /> : <GradientHero />}

      <div
        className="pointer-events-none absolute inset-0 bg-gradient-to-t from-background via-background/75 to-black/15"
        aria-hidden
      />
    </div>
  );
}

function PosterHero({ poster, title }: { poster: string; title: string }) {
  const unoptimized = !isOptimizedImageSrc(poster);

  return (
    <>
      <Image
        src={poster}
        alt=""
        aria-hidden
        fill
        sizes="100vw"
        priority
        unoptimized={unoptimized}
        className="scale-110 object-cover opacity-55 blur-2xl saturate-125"
      />
      <div className="absolute inset-0 flex items-center justify-center px-4">
        <Image
          src={poster}
          alt={title}
          width={POSTER_NATIVE_MAX_PX}
          height={250}
          priority
          unoptimized={unoptimized}
          className="h-auto max-h-[88%] w-full max-w-[min(100%,444px)] object-contain drop-shadow-[0_18px_48px_rgba(0,0,0,0.55)]"
        />
      </div>
    </>
  );
}

function BadgeHero({ match }: { match: ScrapedMatch }) {
  const home = match.teams!.home;
  const away = match.teams!.away;

  return (
    <div className="absolute inset-0">
      <div className="h-full w-full bg-[radial-gradient(ellipse_at_top,#2e394f_0%,#141a24_42%,#0a0d14_100%)]" />
      <div className="absolute inset-0 bg-gradient-to-br from-accent/25 via-transparent to-transparent" />
      <div className="absolute inset-x-0 top-[10%] flex items-center justify-center gap-5 px-6 sm:top-[12%] sm:gap-10">
        <TeamBadge name={home.name} badge={home.badge} size={64} />
        <span className="text-sm font-black uppercase tracking-[0.2em] text-white/35 sm:text-base">vs</span>
        <TeamBadge name={away.name} badge={away.badge} size={64} />
      </div>
    </div>
  );
}

function GradientHero() {
  return (
    <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,#2e394f_0%,#141a24_45%,#0a0d14_100%)]">
      <div className="absolute inset-0 bg-gradient-to-br from-accent/20 via-transparent to-transparent" />
    </div>
  );
}
