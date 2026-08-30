"use client";

import { Radio } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { MatchScoreboardCard } from "@/components/MatchScoreboardCard";
import { TrackTeamButton } from "@/components/TrackTeamButton";
import { FeaturedMatchHero } from "@/components/FeaturedMatchHero";
import { formatKickoff, isMatchLiveNow } from "@/lib/live";
import { fottyFeedCountShort } from "@/lib/watch-stream-display";

interface MatchDayLiveHeroProps {
  match: ScrapedMatch;
}

export function MatchDayLiveHero({ match }: MatchDayLiveHeroProps) {
  const isLive = isMatchLiveNow(match);
  const title = match.displayTitle || match.title;
  const feedLabel = fottyFeedCountShort(match.sourceCount || match.alternateCount || 0) || "Fotty Live";
  const kickoff = formatKickoff(match.startsAt);

  return (
    <section className="overflow-hidden rounded-2xl border border-white/10 bg-[#0c1119] shadow-2xl">
      <div className="relative">
        <FeaturedMatchHero match={match} title={title} className="min-h-[230px] sm:min-h-[320px] lg:min-h-[360px]" />
        <div className="absolute inset-x-0 bottom-0 p-4 sm:p-5">
          <div className="max-w-3xl">
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <span className="inline-flex items-center gap-1.5 rounded-full border border-live/25 bg-black/45 px-2.5 py-1 text-[10px] font-black uppercase tracking-wide text-live backdrop-blur">
                <Radio size={12} className={isLive ? "animate-pulse" : ""} />
                {isLive ? "Live now" : "Featured"}
              </span>
              <span className="rounded-full border border-white/10 bg-black/35 px-2.5 py-1 text-[10px] font-black uppercase tracking-wide text-text-secondary backdrop-blur">
                {match.sport || match.league || "Live sport"}
              </span>
              <span className="rounded-full border border-white/10 bg-black/35 px-2.5 py-1 text-[10px] font-black uppercase tracking-wide text-text-secondary backdrop-blur">
                {feedLabel}
              </span>
            </div>
            <h2 className="text-3xl font-black leading-tight text-white sm:text-4xl lg:text-5xl">{title}</h2>
            <p className="mt-2 text-sm font-bold text-text-secondary">{kickoff || match.subtitle || "Ready when the stream is"}</p>
          </div>
        </div>
      </div>

      <div className="border-t border-white/5 p-3 sm:p-4">
        <MatchScoreboardCard match={match} returnTo="/" layout="hero" actionLabel={isLive ? "Watch live" : "Open"} />
      </div>

      {match.teams && (
        <div className="grid gap-2 border-t border-white/5 p-3 sm:grid-cols-2 sm:p-4">
          <TrackTeamButton name={match.teams.home.name} sport={match.sport} league={match.league} className="w-full" />
          <TrackTeamButton name={match.teams.away.name} sport={match.sport} league={match.league} className="w-full" />
        </div>
      )}
    </section>
  );
}
