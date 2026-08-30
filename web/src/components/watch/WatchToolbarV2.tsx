"use client";

import { Bell, BellOff, ChevronLeft, Info, PictureInPicture2, Radio, Volume2 } from "lucide-react";
import { cn } from "@/lib/utils";

type StatusTone = "live" | "upcoming" | "finished" | "neutral";

interface WatchToolbarV2Props {
  title: string;
  subtitle?: string;
  feedCount?: number;
  statusLabel: string;
  statusTone?: StatusTone;
  streamHealthLine?: string;
  showReminder?: boolean;
  reminded?: boolean;
  onToggleReminder?: () => void;
  showDiagnostics?: boolean;
  onToggleDiagnostics?: () => void;
  showPiP?: boolean;
  onTogglePiP?: () => void;
  onBack?: () => void;
  onUnmute?: () => void;
  playbackHint?: string;
  /** When true, title row is hidden (fixture header shows teams instead). */
  hideTitle?: boolean;
}

function statusClass(tone: StatusTone) {
  switch (tone) {
    case "live":
      return "bg-white/10 text-white";
    case "upcoming":
      return "border border-sky-400/25 bg-sky-500/10 text-sky-200";
    case "finished":
      return "border border-white/10 bg-white/5 text-text-tertiary";
    default:
      return "border border-white/10 bg-white/5 text-text-secondary";
  }
}

export function WatchToolbarV2({
  title,
  subtitle,
  feedCount = 0,
  statusLabel,
  statusTone = "neutral",
  streamHealthLine,
  showReminder = false,
  reminded = false,
  onToggleReminder,
  showDiagnostics = false,
  onToggleDiagnostics,
  showPiP = false,
  onTogglePiP,
  onBack,
  onUnmute,
  playbackHint,
  hideTitle = false,
}: WatchToolbarV2Props) {
  const feedLabel = feedCount > 0 ? `${feedCount} feed${feedCount === 1 ? "" : "s"}` : "Checking";

  return (
    <div className="shrink-0 border-b border-white/[0.06] bg-[var(--v2-surface)] px-4 py-3">
      {onBack ? (
        <button
          type="button"
          onClick={onBack}
          className="mb-3 inline-flex items-center gap-1 rounded-full py-1 text-sm font-medium text-text-secondary transition hover:text-white"
        >
          <ChevronLeft size={18} />
          Back
        </button>
      ) : null}
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span
              className={cn(
                "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide",
                statusClass(statusTone)
              )}
            >
              {statusTone === "live" ? <Radio size={10} className="animate-pulse" /> : null}
              {statusLabel}
            </span>
            <span className="rounded-full border border-white/10 px-2 py-0.5 text-[10px] font-medium text-text-tertiary">
              {feedLabel}
            </span>
            {streamHealthLine ? (
              <span className="hidden text-[10px] text-text-tertiary sm:inline">{streamHealthLine}</span>
            ) : null}
            {playbackHint ? (
              <span className="text-[10px] text-text-tertiary sm:hidden">{playbackHint}</span>
            ) : null}
          </div>
          {!hideTitle ? (
            <>
              <h1 className="mt-2 line-clamp-2 text-base font-bold leading-snug text-white">{title}</h1>
              {subtitle ? <p className="mt-1 line-clamp-1 text-xs text-text-tertiary">{subtitle}</p> : null}
            </>
          ) : null}
        </div>

        <div className="flex shrink-0 items-center gap-1.5">
          {onUnmute ? (
            <button
              type="button"
              onClick={onUnmute}
              className="inline-flex h-9 items-center gap-1.5 rounded-full border border-white/10 bg-white/5 px-3 text-[11px] font-bold uppercase tracking-wide text-text-secondary transition hover:text-white"
              aria-label="Unmute stream"
              title="Unmute stream"
            >
              <Volume2 size={15} />
              Unmute
            </button>
          ) : null}
          {showPiP && onTogglePiP ? (
            <button
              type="button"
              onClick={onTogglePiP}
              className="grid h-9 w-9 place-items-center rounded-full border border-white/10 bg-white/5 text-text-secondary transition hover:text-white"
              aria-label="Picture in picture"
              title="Picture in picture (P)"
            >
              <PictureInPicture2 size={15} />
            </button>
          ) : null}
          {showReminder ? (
            <button
              type="button"
              aria-pressed={reminded}
              onClick={onToggleReminder}
              className={cn(
                "grid h-9 w-9 place-items-center rounded-full transition",
                reminded ? "bg-white text-zinc-950" : "border border-white/10 bg-white/5 text-text-secondary hover:text-white"
              )}
              aria-label={reminded ? "Reminder saved" : "Remind me"}
            >
              {reminded ? <BellOff size={15} /> : <Bell size={15} />}
            </button>
          ) : null}
          {onToggleDiagnostics ? (
            <button
              type="button"
              aria-pressed={showDiagnostics}
              onClick={onToggleDiagnostics}
              className={cn(
                "grid h-9 w-9 place-items-center rounded-full transition",
                showDiagnostics ? "bg-white text-zinc-950" : "border border-white/10 bg-white/5 text-text-secondary hover:text-white"
              )}
              aria-label="Stream status"
            >
              <Info size={15} />
            </button>
          ) : null}
        </div>
      </div>
      {playbackHint ? (
        <p className="mt-2 hidden text-xs leading-relaxed text-text-tertiary sm:block">{playbackHint}</p>
      ) : null}
    </div>
  );
}
