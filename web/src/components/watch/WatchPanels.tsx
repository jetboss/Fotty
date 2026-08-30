"use client";

import React, { forwardRef } from "react";
import type { SwarmStatus } from "@/lib/api";
import { MatchTimeline } from "@/components/MatchTimeline";
import { SponsoredSlot } from "@/components/SponsoredSlot";

export const WatchVideoStage = forwardRef<HTMLDivElement, { children: React.ReactNode; v2?: boolean }>(
  function WatchVideoStage({ children, v2 = false }, ref) {
  return (
    <div ref={ref} className="relative flex w-full shrink-0 flex-col bg-black">
      <div
        className={
          v2
            ? "relative h-[48svh] min-h-[240px] max-h-[480px] w-full overflow-hidden sm:aspect-video sm:h-auto sm:min-h-[280px] sm:max-h-[min(62svh,600px)] lg:aspect-auto lg:h-[min(68svh,860px)] lg:max-h-[78svh] lg:min-h-[400px]"
            : "relative h-[42svh] min-h-[220px] max-h-[430px] w-full overflow-hidden sm:aspect-video sm:h-auto sm:min-h-[260px] sm:max-h-[min(58svh,560px)] md:aspect-auto md:h-[min(62svh,820px)] md:max-h-[75svh] md:min-h-[360px]"
        }
        data-pull-refresh-ignore
      >
        {children}
      </div>
    </div>
  );
});

export function TelemetryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-white/5 bg-surface px-3 py-3">
      <p className="text-[10px] font-bold uppercase text-text-tertiary">{label}</p>
      <p className="mt-1 truncate text-sm font-black text-text-primary">{value}</p>
    </div>
  );
}

export function TelemetryGrid({ telemetry, isP2PActive }: { telemetry: SwarmStatus; isP2PActive: boolean }) {
  return (
    <>
      <div className="grid grid-cols-3 gap-2">
        <TelemetryCard label="Peers" value={telemetry.peerCount > 0 ? `${telemetry.peerCount}` : isP2PActive ? "Active" : "Warming"} />
        <TelemetryCard label="Speed" value={telemetry.downloadSpeedKbps > 0 ? `${(telemetry.downloadSpeedKbps / 1024).toFixed(1)} Mbps` : isP2PActive ? "HLS" : "Waiting"} />
        <TelemetryCard label="Segments" value={telemetry.readySegmentCount > 0 ? `${telemetry.readySegmentCount}` : telemetry.firstSegmentReady ? "Ready" : "Building"} />
      </div>
      {telemetry.error && (
        <p className="mt-2 text-xs font-medium leading-5 text-text-tertiary">Live signal telemetry is updating.</p>
      )}
    </>
  );
}

export function WatchDetailsPanel({
  className,
  isEventPlayback,
  showTelemetry,
  telemetry,
  isP2PActive,
  p2pFeedConnected,
  title,
  league,
  sport,
}: {
  className?: string;
  isEventPlayback: boolean;
  showTelemetry: boolean;
  telemetry: SwarmStatus;
  isP2PActive: boolean;
  p2pFeedConnected: boolean;
  title: string;
  league?: string;
  sport?: string;
}) {
  return (
    <div className={className}>
      <div className="border-b border-white/5 bg-background px-md py-2">
        <SponsoredSlot placement="watch" compact />
      </div>
      {!isEventPlayback && showTelemetry && (
        <div className="border-b border-white/5 bg-surface-elevated/40 px-md py-2">
          <TelemetryGrid telemetry={telemetry} isP2PActive={isP2PActive} />
        </div>
      )}
      <div className="min-h-0 flex-1 overflow-visible bg-background lg:overflow-hidden">
        <MatchTimeline
          title={title}
          league={league}
          sport={sport}
          isP2PPlayback={!isEventPlayback}
          telemetry={telemetry}
          p2pFeedConnected={p2pFeedConnected}
          compact
        />
      </div>
    </div>
  );
}

export function StreamDiagnosticsPanel({
  mode,
  access,
  lookup,
  feeds,
  selected,
  frameState,
  lastCheckedAt,
  error,
}: {
  mode: string;
  access?: string;
  lookup: string;
  feeds: number;
  selected: string;
  frameState?: string;
  lastCheckedAt?: string;
  error?: string | null;
}) {
  const checkedAt = lastCheckedAt ? new Date(lastCheckedAt) : null;
  const checkedLabel =
    checkedAt && !Number.isNaN(checkedAt.getTime())
      ? checkedAt.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
      : lastCheckedAt;

  return (
    <div className="shrink-0 border-b border-white/5 bg-surface-elevated/40 px-md py-3">
      <div className="grid grid-cols-2 gap-2 text-[11px] sm:grid-cols-4">
        <TelemetryCard label="Mode" value={mode} />
        <TelemetryCard label="Access" value={access || "Allowed"} />
        <TelemetryCard label="Lookup" value={lookup} />
        <TelemetryCard label="Feeds" value={`${feeds}`} />
        <TelemetryCard label="Selected" value={selected} />
        {frameState ? <TelemetryCard label="Frame" value={frameState} /> : null}
        {checkedLabel ? <TelemetryCard label="Checked" value={checkedLabel} /> : null}
      </div>
      {error ? <p className="mt-2 text-xs font-medium leading-5 text-text-tertiary">{error}</p> : null}
    </div>
  );
}
