"use client";

import type { StreamSource } from "@/lib/stream-guide/types";
import { formatStreamFeedLabel } from "@/lib/stream-guide/feed-label";
import { cn } from "@/lib/utils";

interface WatchFeedChipsProps {
  sources: StreamSource[];
  selectedIndex: number;
  onSelect?: (index: number) => void;
  layout?: "row" | "stack";
  className?: string;
}

export function WatchFeedChips({
  sources,
  selectedIndex,
  onSelect,
  layout = "row",
  className,
}: WatchFeedChipsProps) {
  if (sources.length === 0) return null;

  const isRow = layout === "row";

  return (
    <div
      className={cn(
        isRow ? "flex gap-2 overflow-x-auto pb-0.5 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden" : "grid gap-2",
        className
      )}
    >
      {sources.map((source, index) => {
        const active = source.eventIndex === selectedIndex;
        const disabled = source.status === "offline" || source.eventIndex === undefined;
        const label = formatStreamFeedLabel(source, index);

        return (
          <button
            key={source.id}
            type="button"
            disabled={disabled}
            aria-pressed={active}
            aria-label={`Broadcast ${index + 1}: ${label}${active ? ", selected" : ""}`}
            onClick={() => {
              if (source.eventIndex !== undefined) onSelect?.(source.eventIndex);
            }}
            className={cn(
              "text-left transition disabled:cursor-not-allowed disabled:opacity-50",
              isRow ? "shrink-0 rounded-full px-3.5 py-2 text-xs font-semibold" : "rounded-xl border px-3 py-2.5",
              active
                ? isRow
                  ? "bg-white text-zinc-950"
                  : "border-white/20 bg-white/[0.06] text-white"
                : isRow
                  ? "border border-white/10 bg-white/5 text-white/80 hover:bg-white/10"
                  : "border-white/10 bg-white/[0.03] text-text-secondary hover:bg-white/[0.06] hover:text-white"
            )}
          >
            <span className={cn("block truncate", !isRow && "text-sm font-semibold")}>{label}</span>
            {!isRow ? (
              <span className="mt-0.5 block text-[11px] text-text-tertiary">
                {source.isRecommended ? "Recommended" : `Option ${index + 1}`}
                {source.quality ? ` · ${source.quality}` : ""}
              </span>
            ) : (
              <span aria-hidden="true" className="sr-only">{source.displayName}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}
