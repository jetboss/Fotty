"use client";

import { AlertTriangle, RefreshCw } from "lucide-react";
import type { EventStreamVariant } from "@/lib/api";
import {
  logStreamDiagnostic,
  pickBackupAfterFailure,
  rankEventStreamGuide,
} from "@/lib/stream-guide";
import { fottyFeedCountLabel } from "@/lib/watch-stream-display";
import { formatStreamFeedLabel } from "@/lib/stream-guide/feed-label";
import { WatchFeedChips } from "@/components/watch/WatchFeedChips";
import { NoStreamsAvailableState } from "./NoStreamsAvailableState";
import { PlaybackErrorPanel } from "./PlaybackErrorPanel";

interface MatchStreamHubV2Props {
  mode: "event" | "p2p";
  matchId?: string;
  eventStreams?: EventStreamVariant[];
  selectedEventIndex?: number;
  isLoading?: boolean;
  loadError?: string | null;
  playbackError?: string | null;
  lastCheckedAt?: string;
  failedEventSourceIds?: string[];
  onSelectEventStream?: (index: number) => void;
  onTryNextEventStream?: () => void;
  onBrowseLive?: () => void;
  onRefreshEventStreams?: () => void;
}

export function MatchStreamHubV2({
  mode,
  matchId,
  eventStreams,
  selectedEventIndex = 0,
  isLoading,
  loadError,
  playbackError,
  lastCheckedAt,
  failedEventSourceIds,
  onSelectEventStream,
  onTryNextEventStream,
  onBrowseLive,
  onRefreshEventStreams,
}: MatchStreamHubV2Props) {
  const guide =
    mode === "event" ? rankEventStreamGuide(eventStreams || [], matchId) : null;
  const feedCount = mode === "event" ? eventStreams?.length || 0 : 1;
  const hasMultipleFeeds = feedCount > 1;
  const showRecovery =
    Boolean(playbackError) || Boolean(failedEventSourceIds?.length) || Boolean(loadError);

  const failedSource = guide?.all.find((source) => source.eventIndex === selectedEventIndex);
  const backup =
    guide && playbackError
      ? pickBackupAfterFailure(guide, failedSource?.id, failedEventSourceIds)
      : null;

  if (mode === "event" && !isLoading && !loadError && feedCount === 0) {
    return (
      <section className="bg-[var(--v2-background)] px-4 py-4">
        <NoStreamsAvailableState onRefresh={onRefreshEventStreams} lastCheckedAt={lastCheckedAt} />
      </section>
    );
  }

  return (
    <section className="space-y-3 bg-[var(--v2-background)] px-4 py-4">
      {isLoading ? (
        <p className="text-xs text-text-tertiary">Finding streams…</p>
      ) : hasMultipleFeeds && guide ? (
        <div className="space-y-2 lg:hidden">
          <p className="text-[11px] font-medium uppercase tracking-wide text-text-tertiary">Switch feed</p>
          <WatchFeedChips
            sources={guide.all}
            selectedIndex={selectedEventIndex}
            onSelect={(index) => {
              logStreamDiagnostic("stream_switch", {
                matchId,
                playbackMode: "event",
                reason: "manual_chip",
              });
              onSelectEventStream?.(index);
            }}
          />
        </div>
      ) : guide?.recommended ? (
        <p className="text-xs text-text-tertiary">
          {fottyFeedCountLabel(feedCount)} · {formatStreamFeedLabel(guide.recommended, selectedEventIndex)}
        </p>
      ) : null}

      {showRecovery ? (
        <div className="rounded-xl border border-amber-300/15 bg-amber-300/[0.04] px-3 py-3">
          <p className="flex items-start gap-2 text-xs leading-5 text-text-secondary">
            <AlertTriangle size={14} className="mt-0.5 shrink-0 text-amber-300" />
            {playbackError || loadError || "This feed may be stalling. Try another source below."}
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {onTryNextEventStream && hasMultipleFeeds ? (
              <button
                type="button"
                onClick={onTryNextEventStream}
                className="inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-2 text-[11px] font-semibold text-zinc-950"
              >
                <RefreshCw size={13} />
                Try next feed
              </button>
            ) : null}
            {onRefreshEventStreams ? (
              <button
                type="button"
                onClick={onRefreshEventStreams}
                className="rounded-full border border-white/10 px-3 py-2 text-[11px] font-medium text-text-primary"
              >
                Refresh
              </button>
            ) : null}
            {onBrowseLive ? (
              <button
                type="button"
                onClick={onBrowseLive}
                className="rounded-full border border-white/10 px-3 py-2 text-[11px] font-medium text-text-primary"
              >
                Back
              </button>
            ) : null}
          </div>
        </div>
      ) : null}

      {playbackError && backup ? (
        <PlaybackErrorPanel
          message={playbackError}
          backup={backup}
          onRetry={onTryNextEventStream}
          onTryBackup={
            backup.eventIndex !== undefined
              ? onTryNextEventStream ??
                (() => {
                  onSelectEventStream?.(backup.eventIndex!);
                })
              : undefined
          }
        />
      ) : null}
    </section>
  );
}
