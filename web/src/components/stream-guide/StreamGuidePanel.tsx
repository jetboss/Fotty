"use client";

import { Info } from "lucide-react";
import { P2P_GUIDE_COPY } from "@/lib/stream-guide/copy";

export function StreamGuidePanel({ showP2P }: { showP2P?: boolean }) {
  if (!showP2P) return null;

  return (
    <aside className="min-w-[min(100%,18rem)] flex-1 rounded-xl border border-white/5 bg-surface/80 px-4 py-3 backdrop-blur-sm">
      <div className="flex items-center gap-2">
        <Info size={14} className="shrink-0 text-accent" />
        <p className="text-xs font-black text-text-primary">{P2P_GUIDE_COPY.title}</p>
      </div>
      <p className="mt-2 text-xs font-medium leading-5 text-text-secondary">{P2P_GUIDE_COPY.body}</p>
    </aside>
  );
}
