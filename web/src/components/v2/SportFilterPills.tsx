"use client";

import { SPORT_FILTER_PILLS, type SportFilterId } from "@/lib/v2/sport-filter";
import { cn } from "@/lib/utils";

interface SportFilterPillsProps {
  selectedSport: string;
  onSelectSport: (sport: SportFilterId) => void;
  className?: string;
}

export function SportFilterPills({
  selectedSport,
  onSelectSport,
  className,
}: SportFilterPillsProps) {
  return (
    <div
      className={cn(
        "flex items-center gap-2 overflow-x-auto no-scrollbar scroll-smooth py-1 px-4 lg:px-6",
        className
      )}
    >
      {SPORT_FILTER_PILLS.map((pill) => {
        const isActive = (selectedSport || "all") === pill.id;
        return (
          <button
            key={pill.id}
            type="button"
            onClick={() => onSelectSport(pill.id)}
            className={cn(
              "flex shrink-0 items-center gap-1.5 rounded-full px-3.5 py-1.5 text-xs font-semibold transition-all select-none active:scale-95",
              isActive
                ? "bg-white text-zinc-950 shadow-md shadow-white/10"
                : "border border-white/[0.08] bg-white/[0.04] text-white/70 hover:bg-white/[0.08] hover:text-white"
            )}
          >
            <span>{pill.emoji}</span>
            <span>{pill.label}</span>
          </button>
        );
      })}
    </div>
  );
}
