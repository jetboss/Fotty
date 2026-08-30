"use client";

import { RefreshCw } from "lucide-react";
import { STREAM_GUIDE_COPY } from "@/lib/stream-guide/copy";
import type { StreamSource } from "@/lib/stream-guide/types";

export function PlaybackErrorPanel({
  message,
  backup,
  onRetry,
  onTryBackup,
}: {
  message?: string;
  backup?: StreamSource | null;
  onRetry?: () => void;
  onTryBackup?: () => void;
}) {
  return (
    <div className="rounded-xl border border-orange-400/20 bg-orange-500/10 px-4 py-3">
      <p className="text-sm font-black text-text-primary">{STREAM_GUIDE_COPY.playbackFailed}</p>
      <p className="mt-1 text-xs font-medium leading-5 text-text-secondary">
        {message || "Try a backup stream or wait a moment while Fotty rechecks this feed."}
      </p>
      {backup ? (
        <p className="mt-2 text-xs font-medium text-text-tertiary">
          <span className="font-bold text-text-secondary">{backup.displayName}</span> looks healthier right now.
        </p>
      ) : null}
      <div className="mt-3 flex flex-wrap gap-2">
        {onRetry ? (
          <button
            type="button"
            onClick={onRetry}
            className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-surface px-3 py-2 text-xs font-bold text-text-primary"
          >
            <RefreshCw size={13} />
            Retry
          </button>
        ) : null}
        {backup && onTryBackup ? (
          <button
            type="button"
            onClick={onTryBackup}
            className="inline-flex items-center gap-2 rounded-full bg-accent px-3 py-2 text-xs font-bold text-white"
          >
            {STREAM_GUIDE_COPY.tryBackup}
          </button>
        ) : null}
      </div>
    </div>
  );
}
