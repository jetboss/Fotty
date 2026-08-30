"use client";

import Image from "next/image";
import { Shield } from "lucide-react";
import {
  FOOTBALL_LEAGUE_TABS,
  footballLeagueBadgeUrl,
  footballLeagueLabel,
  footballLeagueShortLabel,
  type FootballLeagueTab,
} from "@/lib/football-leagues";
import { cn } from "@/lib/utils";

interface FootballLeagueBarProps {
  selected: FootballLeagueTab;
  onSelect: (tab: FootballLeagueTab) => void;
  className?: string;
  tabs?: FootballLeagueTab[];
  variant?: "classic" | "v2";
}

export function FootballLeagueBar({
  selected,
  onSelect,
  className,
  tabs = FOOTBALL_LEAGUE_TABS,
  variant = "classic",
}: FootballLeagueBarProps) {
  const isV2 = variant === "v2";
  return (
    <div
      className={cn("no-scrollbar flex gap-1.5 overflow-x-auto sm:gap-2", className)}
      role="tablist"
      aria-label="Football leagues"
    >
      {tabs.map((tab) => {
        const badge = footballLeagueBadgeUrl(tab);
        const active = selected === tab;
        const fullLabel = footballLeagueLabel(tab);

        return (
          <button
            key={tab}
            type="button"
            role="tab"
            aria-selected={active}
            aria-label={fullLabel}
            onClick={() => onSelect(tab)}
            className={cn(
              "inline-flex shrink-0 items-center gap-1 rounded-full border px-2 py-1 text-[11px] font-bold transition-colors sm:gap-2 sm:px-3.5 sm:py-2 sm:text-xs",
              active
                ? isV2
                  ? "border-white/20 bg-white/10 text-white"
                  : "border-accent/45 bg-accent/10 text-white shadow-[inset_0_0_0_1px_rgba(224,31,71,0.08)]"
                : isV2
                  ? "border-white/10 bg-white/[0.03] text-text-secondary hover:bg-white/[0.06] hover:text-white"
                  : "border-white/10 bg-surface text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
            )}
          >
            {badge ? (
              <Image
                src={badge}
                alt=""
                width={14}
                height={14}
                className="h-3 w-3 rounded-sm object-contain sm:h-3.5 sm:w-3.5"
              />
            ) : (
              <Shield
                size={11}
                className={cn("hidden sm:block", active ? (isV2 ? "text-white" : "text-accent") : "text-text-tertiary")}
              />
            )}
            <span className="sm:hidden">{footballLeagueShortLabel(tab)}</span>
            <span className="hidden sm:inline">{fullLabel}</span>
          </button>
        );
      })}
    </div>
  );
}
