"use client";

import { CalendarClock, Trophy } from "lucide-react";
import type { ScrapedMatch } from "@/lib/api";
import { formatKickoff } from "@/lib/live";
import {
  fixtureLeagueLine,
  fixtureTbdHeadline,
  fixtureTbdSubline,
} from "@/lib/v2/fixture-display";
import { isKnockoutBracketTbd } from "@/lib/fixture-normalization";
import { cn } from "@/lib/utils";

interface TbdBracketCardProps {
  match: ScrapedMatch;
  layout?: "rail" | "fill";
  className?: string;
}

export function TbdBracketCard({ match, layout = "fill", className }: TbdBracketCardProps) {
  const headline = fixtureTbdHeadline(match);
  const subline = isKnockoutBracketTbd(match)
    ? fixtureTbdSubline(match)
    : "Participants to be confirmed";
  const kickoff = formatKickoff(match.startsAt);
  const chip = fixtureLeagueLine(match);

  return (
    <article
      className={cn(
        "select-none",
        layout === "fill" ? "w-full" : "w-[280px] shrink-0 snap-start sm:w-[300px]",
        className
      )}
    >
      <div className="flex h-full min-h-[168px] flex-col justify-between rounded-2xl border border-dashed border-white/10 bg-white/[0.02] px-4 py-4 ring-1 ring-white/[0.04] sm:min-h-[176px] sm:px-5 sm:py-5">
        <div className="flex items-start justify-between gap-2">
          <span className="text-[7.5px] font-bold uppercase tracking-[0.13em] text-white/25">{chip}</span>
          <span className="shrink-0 rounded-md border border-white/10 bg-white/[0.04] px-1.5 py-0.5 text-[7.5px] font-bold uppercase tracking-wide text-white/35">
            TBD
          </span>
        </div>

        <div className="flex flex-col items-center gap-2 py-2 text-center">
          <div className="grid h-12 w-12 place-items-center rounded-2xl border border-white/10 bg-white/[0.04] text-white/45">
            <Trophy size={20} strokeWidth={1.75} />
          </div>
          <div className="space-y-1">
            <p className="text-[15px] font-semibold tracking-tight text-white/85">{headline}</p>
            <p className="max-w-[16rem] text-[11px] leading-snug text-text-tertiary">{subline}</p>
          </div>
        </div>

        {kickoff ? (
          <div className="flex items-center justify-center gap-1.5 border-t border-white/[0.06] pt-3 text-[11px] font-medium text-text-tertiary">
            <CalendarClock size={12} className="shrink-0 opacity-70" />
            <span>{kickoff}</span>
          </div>
        ) : null}
      </div>
    </article>
  );
}
