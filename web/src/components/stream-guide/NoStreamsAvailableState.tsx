"use client";

import { RefreshCw, Radio } from "lucide-react";
import { STREAM_GUIDE_COPY } from "@/lib/stream-guide/copy";

export function NoStreamsAvailableState({
  onRefresh,
  lastCheckedAt,
}: {
  onRefresh?: () => void;
  lastCheckedAt?: string;
}) {
  return (
    <div className="rounded-2xl border border-dashed border-white/10 bg-surface/60 px-5 py-8 text-center">
      <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full border border-white/10 bg-black/30">
        <Radio size={20} className="text-text-tertiary" />
      </div>
      <p className="mt-4 text-sm font-black text-text-primary">{STREAM_GUIDE_COPY.noStreamsTitle}</p>
      <p className="mx-auto mt-2 max-w-sm text-xs font-medium leading-5 text-text-secondary">
        {STREAM_GUIDE_COPY.noStreamsBody}
      </p>
      {lastCheckedAt ? (
        <p className="mt-2 text-[11px] font-medium text-text-tertiary">Last checked {lastCheckedAt}</p>
      ) : null}
      {onRefresh ? (
        <button
          type="button"
          onClick={onRefresh}
          className="mt-4 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-xs font-bold text-text-primary"
        >
          <RefreshCw size={13} />
          Refresh
        </button>
      ) : null}
    </div>
  );
}
