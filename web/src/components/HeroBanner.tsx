"use client";

import React from "react";
import { Info, Play, Star } from "lucide-react";

interface HeroBannerProps {
  title: string;
  overview: string;
  backdrop?: string;
  year?: string;
  rating?: number;
  mediaType?: string;
  onPlay?: () => void;
  onDetail?: () => void;
}

export function HeroBanner({ title, overview, backdrop, year, rating, mediaType, onPlay, onDetail }: HeroBannerProps) {
  return (
    <section className="relative min-h-[470px] w-full overflow-hidden">
      <div className="absolute inset-0">
        {backdrop ? (
          <img src={backdrop} alt={title} className="h-full w-full object-cover" />
        ) : (
          <div className="h-full w-full bg-surface" />
        )}
        <div className="absolute inset-0 bg-gradient-to-b from-black/10 via-background/35 to-background" />
      </div>

      <div className="relative z-10 flex min-h-[470px] flex-col justify-end px-md pb-lg pt-24">
        <div className="max-w-[680px] space-y-4">
          <div className="flex flex-wrap items-center gap-2 text-xs font-semibold text-text-secondary">
            {mediaType && <span className="rounded-full bg-white/10 px-3 py-1">{mediaType}</span>}
            {year && <span>{year}</span>}
            {typeof rating === "number" && rating > 0 && (
              <span className="flex items-center gap-1 text-live">
                <Star size={13} className="fill-current" />
                {rating.toFixed(1)}
              </span>
            )}
          </div>

          <div className="space-y-3">
            <h1 className="max-w-[12ch] text-4xl font-black uppercase leading-none text-white drop-shadow-2xl md:text-6xl">
              {title}
            </h1>
            {overview && (
              <p className="line-clamp-3 max-w-[620px] text-sm font-medium leading-6 text-text-secondary md:text-base">
                {overview}
              </p>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={onPlay}
              className="flex h-12 min-w-36 items-center justify-center gap-2 rounded-full accent-gradient px-6 text-sm font-bold text-white transition-transform active:scale-95"
            >
              <Play size={16} className="fill-current" />
              Play
            </button>
            <button
              onClick={onDetail}
              className="grid h-12 w-12 place-items-center rounded-full glass border border-white/10 text-white transition-colors hover:text-accent"
              aria-label="Open details"
            >
              <Info size={20} />
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
