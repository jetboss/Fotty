"use client";

import React from "react";
import type { LucideIcon } from "lucide-react";
import { Activity, Clock3, Radio, ShieldCheck, Signal, Tv, Wifi } from "lucide-react";
import type { SwarmStatus } from "@/lib/api";
import { isP2PSessionActive } from "@/lib/p2p-session";
import { cn } from "@/lib/utils";

interface MatchTimelineProps {
  title: string;
  league?: string;
  sport?: string;
  isP2PPlayback: boolean;
  telemetry?: SwarmStatus;
  p2pFeedConnected?: boolean;
  compact?: boolean;
  v2?: boolean;
}

interface StatusRow {
  icon: LucideIcon;
  label: string;
  value: string;
  tone?: "accent" | "success" | "muted" | "live";
}

export function MatchTimeline({
  title,
  league,
  sport,
  isP2PPlayback,
  telemetry,
  p2pFeedConnected = false,
  compact = false,
  v2 = false,
}: MatchTimelineProps) {
  const peerCount = Math.max(0, Number(telemetry?.peerCount || 0));
  const readySegments = Math.max(0, Number(telemetry?.readySegmentCount || 0));
  const bufferSeconds = Math.max(0, Number(telemetry?.bufferSeconds || 0));
  const speedMbps = Math.max(0, Number(telemetry?.downloadSpeedKbps || 0)) / 1024;
  const hasP2PSignal = peerCount > 0 || readySegments > 0 || telemetry?.firstSegmentReady;
  const isP2PActive = isP2PSessionActive(telemetry);
  const sportLabel = sport || league?.split(" · ")[0] || "Live Sports";

  const rows: StatusRow[] = isP2PPlayback
    ? [
        {
          icon: Wifi,
          label: "Peers",
          value: peerCount > 0 ? peerCount.toString() : isP2PActive ? "Active" : "Warming",
          tone: hasP2PSignal || isP2PActive ? "success" : "muted",
        },
        {
          icon: Activity,
          label: "Speed",
          value: speedMbps > 0 ? `${speedMbps.toFixed(1)} Mbps` : isP2PActive ? "HLS" : "Waiting",
          tone: speedMbps > 0 || isP2PActive ? "accent" : "muted",
        },
        {
          icon: Signal,
          label: "Segments",
          value: readySegments > 0 ? readySegments.toString() : telemetry?.firstSegmentReady || isP2PActive ? "Ready" : "Building",
          tone: readySegments > 0 || telemetry?.firstSegmentReady || isP2PActive ? "success" : "muted",
        },
        {
          icon: Clock3,
          label: "Buffer",
          value: bufferSeconds > 0 ? `${Math.round(bufferSeconds)}s` : "Pending",
          tone: bufferSeconds > 0 ? "live" : "muted",
        },
      ]
    : [
        {
          icon: Tv,
          label: "Playback",
          value: "Fotty Live",
          tone: "accent",
        },
        {
          icon: Radio,
          label: "Status",
          value: "Live",
          tone: "live",
        },
        {
          icon: ShieldCheck,
          label: "Feed",
          value: "Direct",
          tone: "success",
        },
      ];

  return (
    <div className={`flex flex-col h-full ${v2 ? "bg-[var(--v2-background)]" : "bg-background"}`}>
      <div className={cn(
        "flex items-center justify-between border-b border-white/5 px-md",
        v2 ? "bg-[var(--v2-surface)]" : "bg-surface-elevated/50",
        compact ? "py-2" : "py-3"
      )}>
        <h3 className={cn("font-black uppercase text-text-secondary", compact ? "text-xs" : "text-sm")}>
          {v2 ? "Event" : "Match Center"}
        </h3>
        <div className={cn("flex items-center gap-1 text-[10px] font-bold", v2 ? "text-white/70" : "text-accent")}>
          <div className={cn("h-1 w-1 rounded-full animate-pulse", v2 ? "bg-white/70" : "bg-accent")} /> LIVE
        </div>
      </div>

      <div className={cn("flex-1 overflow-y-auto", compact ? "p-3" : "p-md")}>
        <div className={compact ? "space-y-3" : "space-y-4"}>
          <div className={cn("rounded-lg border border-white/5 bg-surface", compact ? "p-3" : "p-4")}>
            <div className="flex items-center gap-2 text-[11px] font-bold uppercase text-text-tertiary">
              <Radio size={13} className={v2 ? "text-white/60" : "text-accent"} />
              <span>{sportLabel}</span>
            </div>
            <h2 className={cn("mt-2 line-clamp-2 font-black text-text-primary", compact ? "text-base" : "text-xl")}>{title}</h2>
            {league && <p className="mt-1 text-xs font-medium text-text-secondary">{league}</p>}
          </div>

          <div className={cn("grid grid-cols-2", compact ? "gap-2" : "gap-3")}>
            {rows.map((row) => (
              <StatusCard key={row.label} {...row} compact={compact} />
            ))}
          </div>

          <div className={cn("rounded-lg border border-white/5 bg-surface/70", compact ? "p-3" : "p-4")}>
            <div className="flex items-start gap-3">
              <div className={cn("grid shrink-0 place-items-center rounded-md bg-white/5 text-text-secondary", compact ? "h-7 w-7" : "h-8 w-8")}>
                <Clock3 size={compact ? 14 : 15} />
              </div>
              <div className="min-w-0 space-y-1">
                <p className={cn("font-black text-text-primary", compact ? "text-xs" : "text-sm")}>
                  {isP2PPlayback ? "P2P session status" : "Live event feed"}
                </p>
                <p className="text-xs leading-5 text-text-secondary">
                  {isP2PPlayback
                    ? telemetry?.error ||
                      (p2pFeedConnected
                        ? "P2P broker is serving segments. Peer counts may stay at zero on some channels."
                        : hasP2PSignal
                          ? "Swarm telemetry is active for this stream."
                          : isP2PActive
                            ? "P2P session is active; segment delivery is in progress."
                            : "Warming P2P peers and buffer…")
                    : "Verified play-by-play is not available for this event yet."}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function StatusCard({ icon: Icon, label, value, tone = "muted", compact = false }: StatusRow & { compact?: boolean }) {
  const toneClass = cn({
    "text-accent": tone === "accent",
    "text-success": tone === "success",
    "text-live": tone === "live",
    "text-text-secondary": tone === "muted",
  });

  return (
    <div className={cn("min-w-0 rounded-lg border border-white/5 bg-surface", compact ? "p-2.5" : "p-3")}>
      <div className="flex items-center gap-2 text-[10px] font-bold uppercase text-text-tertiary">
        <Icon size={12} className={toneClass} />
        <span className="truncate">{label}</span>
      </div>
      <div className={cn("truncate font-black text-text-primary tabular-nums", compact ? "mt-1.5 text-sm" : "mt-2 text-base")}>{value}</div>
    </div>
  );
}
