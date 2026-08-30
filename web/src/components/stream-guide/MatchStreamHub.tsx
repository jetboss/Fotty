"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, CheckCircle2, RefreshCw, Route, ShieldCheck, Tv } from "lucide-react";
import type { EventStreamVariant, ScrapedMatch, SwarmStatus } from "@/lib/api";
import { buildWatchHref, FOTTY_LOCALE, FOTTY_TIME_ZONE } from "@/lib/live";
import {
  buildP2PStreamGuide,
  logStreamDiagnostic,
  pickBackupAfterFailure,
  rankEventStreamGuide,
  STREAM_GUIDE_COPY,
  type EventStreamVariantWithSignals,
  type WatchMatchContext,
} from "@/lib/stream-guide";
import { fottyFeedCountLabel } from "@/lib/watch-stream-display";
import { MatchHeroHeader } from "./MatchHeroHeader";
import { NoStreamsAvailableState } from "./NoStreamsAvailableState";
import { PlaybackErrorPanel } from "./PlaybackErrorPanel";
import { RecommendedStreamCard } from "./RecommendedStreamCard";
import { StreamGuidePanel } from "./StreamGuidePanel";
import { StreamSourceCard } from "./StreamSourceCard";

const AUTO_REFRESH_MS = 45_000;

export function MatchStreamHub({
  mode,
  matchId,
  matchContext,
  eventStreams,
  selectedEventIndex,
  isLoading,
  loadError,
  telemetry,
  isP2PWarming,
  isP2PActive,
  cid,
  p2pHealth,
  p2pAlternates,
  playbackError,
  lastCheckedAt,
  failedEventSourceIds,
  onSelectEventStream,
  onTryNextEventStream,
  onBrowseLive,
  onRefreshEventStreams,
  onRetryPlayback,
  v2 = false,
  watchReturnTo = "/",
}: {
  mode: "event" | "p2p";
  matchId?: string;
  matchContext?: WatchMatchContext;
  eventStreams?: EventStreamVariant[];
  selectedEventIndex?: number;
  isLoading?: boolean;
  loadError?: string | null;
  telemetry?: SwarmStatus;
  isP2PWarming?: boolean;
  isP2PActive?: boolean;
  cid?: string;
  p2pHealth?: ScrapedMatch["p2pHealth"];
  p2pAlternates?: ScrapedMatch[];
  playbackError?: string | null;
  lastCheckedAt?: string;
  failedEventSourceIds?: string[];
  onSelectEventStream?: (index: number) => void;
  onTryNextEventStream?: () => void;
  onBrowseLive?: () => void;
  onRefreshEventStreams?: () => void;
  onRetryPlayback?: () => void;
  v2?: boolean;
  watchReturnTo?: string;
}) {
  const [autoChecking, setAutoChecking] = useState(false);

  const guide = useMemo(() => {
    if (mode === "event") {
      return rankEventStreamGuide((eventStreams || []) as EventStreamVariantWithSignals[], matchId);
    }
    if (!cid || !telemetry) return null;
    return buildP2PStreamGuide({
      cid,
      matchId,
      telemetry,
      isWarming: Boolean(isP2PWarming),
      isActive: Boolean(isP2PActive),
      p2pHealth,
    });
  }, [cid, eventStreams, isP2PActive, isP2PWarming, matchId, mode, p2pHealth, telemetry]);

  useEffect(() => {
    if (!guide) return;
    logStreamDiagnostic("stream_guide_view", {
      matchId,
      playbackMode: mode,
      sourceId: guide.recommended?.diagnosticsSafeId,
      healthState: guide.recommended?.status,
    });
  }, [guide, matchId, mode]);

  useEffect(() => {
    if (mode !== "event" || isLoading || loadError) return;
    if ((eventStreams?.length || 0) > 0) return;
    if (!onRefreshEventStreams) return;

    setAutoChecking(true);
    const timer = window.setInterval(() => {
      logStreamDiagnostic("stream_health_refresh", { matchId, playbackMode: "event" });
      onRefreshEventStreams();
    }, AUTO_REFRESH_MS);

    return () => {
      window.clearInterval(timer);
      setAutoChecking(false);
    };
  }, [eventStreams?.length, isLoading, loadError, matchId, mode, onRefreshEventStreams]);

  const failedSource =
    mode === "event" && guide
      ? guide.all.find((source) => source.eventIndex === selectedEventIndex)
      : guide?.recommended;

  const backup =
    guide && playbackError
      ? pickBackupAfterFailure(guide, failedSource?.id, failedEventSourceIds)
      : null;

  const checkedLabel = lastCheckedAt || p2pHealth?.checkedAt || guide?.recommended?.lastCheckedAt;

  if (mode === "event" && !isLoading && !loadError && (eventStreams?.length || 0) === 0) {
    return (
      <section className={`border-b border-white/5 px-md py-4 ${v2 ? "bg-[var(--v2-background)]" : "bg-background"}`}>
        {matchContext ? <MatchHeroHeader className="mb-4" context={matchContext} streamHealth="checking" inferredHealth v2={v2} /> : null}
        <HubHeader feedLabel="0 feeds" mode={mode} autoChecking={autoChecking} />
        <NoStreamsAvailableState onRefresh={onRefreshEventStreams} lastCheckedAt={formatCheckedAt(checkedLabel)} />
      </section>
    );
  }

  return (
    <section className={`border-b border-white/5 px-md py-3 lg:py-3 ${v2 ? "bg-[var(--v2-background)]" : "bg-background"}`}>
      {matchContext && guide?.recommended ? (
        <>
          <MobileMatchSummary context={matchContext} feedLabel={mode === "event" ? fottyFeedCountLabel(eventStreams?.length || 0) : "P2P HLS"} />
          <MatchHeroHeader
            className="mb-3 hidden sm:block"
            context={matchContext}
            streamHealth={guide.recommended.status}
            streamHealthScore={guide.recommended.healthScore}
            inferredHealth={guide.recommended.inferredHealth}
            v2={v2}
          />
        </>
      ) : null}

      <HubHeader
        feedLabel={mode === "event" ? fottyFeedCountLabel(eventStreams?.length || 0) : "P2P HLS"}
        mode={mode}
        autoChecking={autoChecking}
      />

      <SourceReadinessStrip
        mode={mode}
        feedCount={mode === "event" ? eventStreams?.length || 0 : 1}
        hasP2PAlternates={Boolean(p2pAlternates?.length)}
        playbackError={playbackError || loadError}
        isLoading={Boolean(isLoading)}
        isActive={Boolean(mode === "p2p" ? isP2PActive : guide?.recommended)}
        onRefresh={mode === "event" ? onRefreshEventStreams : onRetryPlayback}
      />

      {mode === "event" && (eventStreams?.length || 0) > 1 ? (
        <EventRecoveryBar
          guide={guide}
          selectedEventIndex={selectedEventIndex ?? 0}
          matchId={matchId}
          failedEventSourceIds={failedEventSourceIds}
          onSelect={onSelectEventStream}
          onTryNext={onTryNextEventStream}
          onBrowseLive={onBrowseLive}
          v2={v2}
        />
      ) : null}

      {loadError ? <p className="mb-3 text-xs font-medium text-text-tertiary">{loadError}</p> : null}

      {playbackError ? (
        <div className="mb-3">
          <PlaybackErrorPanel
            message={playbackError}
            backup={backup}
            onRetry={mode === "p2p" ? onRetryPlayback : onTryNextEventStream}
            onTryBackup={
              backup?.eventIndex !== undefined
                ? onTryNextEventStream ??
                  (() => {
                    logStreamDiagnostic("fallback_used", {
                      matchId,
                      sourceId: backup.diagnosticsSafeId,
                      playbackMode: mode,
                    });
                    onSelectEventStream?.(backup.eventIndex!);
                  })
                : undefined
            }
          />
        </div>
      ) : null}

      <RecommendedStreamCard
        source={guide?.recommended ?? null}
        isLoading={isLoading}
        isActive
        className="mb-2"
        v2={v2}
        onWatch={
          mode === "event" && guide?.recommended?.eventIndex !== undefined
            ? () => onSelectEventStream?.(guide.recommended!.eventIndex!)
            : undefined
        }
      />

      {guide?.recommended?.latencyMs ? (
        <p className="mb-3 text-[11px] font-medium text-text-tertiary">
          Estimated latency {Math.round(guide.recommended.latencyMs)}ms
          {checkedLabel ? ` · checked ${formatCheckedAt(checkedLabel)}` : ""}
        </p>
      ) : checkedLabel ? (
        <p className="mb-3 text-[11px] font-medium text-text-tertiary">Last checked {formatCheckedAt(checkedLabel)}</p>
      ) : null}

      {mode === "p2p" ? (
        <div className="mb-4 flex flex-wrap gap-2">
          <StreamGuidePanel showP2P />
          {onBrowseLive ? (
            <button
              type="button"
              onClick={onBrowseLive}
              className="inline-flex min-h-10 items-center justify-center gap-2 rounded-full border border-white/10 bg-surface px-4 text-xs font-black text-text-primary transition-colors hover:bg-surface-elevated"
            >
              <Tv size={14} />
              Browse schedule
            </button>
          ) : null}
        </div>
      ) : null}

      {mode === "event" && p2pAlternates && p2pAlternates.length > 0 ? (
        <P2PAlternateSources channels={p2pAlternates} matchId={matchId} watchReturnTo={watchReturnTo} />
      ) : null}

      {mode === "event" && guide ? (
        <EventStreamGroups
          guide={guide}
          selectedEventIndex={selectedEventIndex ?? 0}
          isLoading={isLoading}
          matchId={matchId}
          onSelect={onSelectEventStream}
        />
      ) : null}
    </section>
  );
}

function EventRecoveryBar({
  guide,
  selectedEventIndex,
  matchId,
  failedEventSourceIds,
  onSelect,
  onTryNext,
  onBrowseLive,
  v2 = false,
}: {
  guide: ReturnType<typeof rankEventStreamGuide> | null;
  selectedEventIndex: number;
  matchId?: string;
  failedEventSourceIds?: string[];
  onSelect?: (index: number) => void;
  onTryNext?: () => void;
  onBrowseLive?: () => void;
  v2?: boolean;
}) {
  const current = guide?.all.find((source) => source.eventIndex === selectedEventIndex);
  const next = guide ? pickBackupAfterFailure(guide, current?.id, failedEventSourceIds) : null;

  return (
    <div className="mb-3 rounded-xl border border-amber-300/20 bg-amber-300/[0.06] px-3 py-3">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <p className="inline-flex items-start gap-2 text-[11px] font-bold leading-5 text-text-secondary">
          <AlertTriangle size={14} className="mt-0.5 shrink-0 text-amber-300" />
          Feed failed or stalled? Fotty will try the next direct stream automatically, or pick one below.
        </p>
        <div className="flex shrink-0 flex-wrap gap-2">
          {next?.eventIndex !== undefined ? (
            <button
              type="button"
              onClick={() => {
                if (onTryNext) {
                  onTryNext();
                  return;
                }
                logStreamDiagnostic("fallback_used", {
                  matchId,
                  sourceId: next.diagnosticsSafeId,
                  playbackMode: "event",
                  reason: "manual_provider_error",
                });
                onSelect?.(next.eventIndex!);
              }}
              className={`inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-[11px] font-black ${
                v2 ? "bg-white text-zinc-950" : "bg-accent text-white"
              }`}
            >
              <RefreshCw size={13} />
              Try next feed
            </button>
          ) : null}
          {onBrowseLive ? (
            <button
              type="button"
              onClick={onBrowseLive}
              className="rounded-full border border-white/10 bg-background px-3 py-2 text-[11px] font-black text-text-primary"
            >
              Home
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function formatCheckedAt(value?: string) {
  if (!value) return undefined;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(FOTTY_LOCALE, {
    timeZone: FOTTY_TIME_ZONE,
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function HubHeader({
  feedLabel,
  mode,
  autoChecking,
}: {
  feedLabel: string;
  mode: "event" | "p2p";
  autoChecking?: boolean;
}) {
  return (
    <div className="mb-2.5 flex items-center justify-between gap-3">
      <div className="min-w-0">
        <p className="text-base font-black text-text-primary sm:text-sm lg:text-xs">{STREAM_GUIDE_COPY.hubTitle}</p>
        <p className="mt-0.5 hidden truncate text-[11px] font-medium text-text-tertiary sm:block lg:hidden">
          {mode === "event" ? "Best feed first, backups directly below." : "Broker-backed channel feed."}
        </p>
      </div>
      <div className="flex shrink-0 flex-col items-end gap-1">
        <span className="rounded-full border border-white/10 bg-surface px-3 py-1 text-[11px] font-bold text-text-secondary">
          {feedLabel}
        </span>
        {autoChecking ? (
          <span className="text-[10px] font-bold text-accent">{STREAM_GUIDE_COPY.fottyChecking}</span>
        ) : null}
      </div>
    </div>
  );
}

function SourceReadinessStrip({
  mode,
  feedCount,
  hasP2PAlternates,
  playbackError,
  isLoading,
  isActive,
  onRefresh,
}: {
  mode: "event" | "p2p";
  feedCount: number;
  hasP2PAlternates: boolean;
  playbackError?: string | null;
  isLoading: boolean;
  isActive: boolean;
  onRefresh?: () => void;
}) {
  const status = playbackError ? "Needs attention" : isLoading ? "Checking" : isActive ? "Ready" : "Waiting";
  const tone = playbackError ? "warn" : isLoading ? "checking" : isActive ? "ready" : "idle";

  return (
    <div className="mb-3 grid grid-cols-3 gap-2">
      <ReadinessPill icon={tone === "warn" ? AlertTriangle : tone === "ready" ? CheckCircle2 : RefreshCw} label={status} tone={tone} />
      <ReadinessPill icon={ShieldCheck} label={`${feedCount} feed${feedCount === 1 ? "" : "s"}`} tone="idle" />
      {hasP2PAlternates ? (
        <ReadinessPill icon={Route} label="P2P ready" tone="ready" />
      ) : (
        <ReadinessPill icon={mode === "p2p" ? Route : Tv} label={mode === "p2p" ? "P2P" : "Direct"} tone="idle" />
      )}
      {playbackError && onRefresh ? (
        <button
          type="button"
          onClick={onRefresh}
          className="col-span-3 inline-flex min-h-10 items-center justify-center gap-2 rounded-full border border-accent/35 bg-accent/10 px-4 text-xs font-black text-accent"
        >
          <RefreshCw size={14} />
          Refresh sources
        </button>
      ) : null}
    </div>
  );
}

function ReadinessPill({
  icon: Icon,
  label,
  tone,
}: {
  icon: typeof AlertTriangle;
  label: string;
  tone: "ready" | "warn" | "checking" | "idle";
}) {
  return (
    <div
      className={[
        "flex min-h-10 items-center justify-center gap-1.5 rounded-full border px-2 text-[11px] font-black",
        tone === "ready" ? "border-emerald-400/25 bg-emerald-400/10 text-emerald-300" : "",
        tone === "warn" ? "border-amber-300/25 bg-amber-300/10 text-amber-300" : "",
        tone === "checking" ? "border-accent/25 bg-accent/10 text-accent" : "",
        tone === "idle" ? "border-white/10 bg-surface text-text-secondary" : "",
      ].join(" ")}
    >
      <Icon size={13} className={tone === "checking" ? "animate-spin" : ""} />
      <span className="truncate">{label}</span>
    </div>
  );
}

function MobileMatchSummary({ context, feedLabel }: { context: WatchMatchContext; feedLabel: string }) {
  return (
    <div className="mb-3 rounded-lg border border-white/10 bg-surface px-3 py-2.5 sm:hidden">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-[10px] font-black uppercase text-text-tertiary">
            {[context.league, context.kickoffLabel].filter(Boolean).join(" · ") || "Match"}
          </p>
          <p className="mt-1 truncate text-sm font-black text-white">
            {context.homeName} <span className="text-text-tertiary">v</span> {context.awayName}
          </p>
        </div>
        <div className="shrink-0 text-right">
          <span className="rounded-full border border-live/35 bg-live/10 px-2.5 py-1 text-[10px] font-black uppercase text-live">
            {context.statusLabel}
          </span>
          <p className="mt-1 text-[10px] font-bold text-text-tertiary">{feedLabel}</p>
        </div>
      </div>
    </div>
  );
}

function P2PAlternateSources({ channels, matchId, watchReturnTo }: { channels: ScrapedMatch[]; matchId?: string; watchReturnTo: string }) {
  return (
    <div className="mt-4 rounded-xl border border-emerald-400/20 bg-emerald-400/[0.05] p-3">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="inline-flex items-center gap-2 text-xs font-black text-text-primary">
            <Route size={14} className="text-emerald-300" />
            Same-match P2P <span className="font-bold text-text-tertiary">({channels.length})</span>
          </p>
          <p className="mt-0.5 text-[11px] font-medium leading-5 text-text-tertiary">
            Broker-backed channel feeds if the direct player stalls.
          </p>
        </div>
        <span className="shrink-0 rounded-full border border-live/25 bg-live/10 px-2 py-1 text-[10px] font-black text-live">
          P2P
        </span>
      </div>
      <div className="grid gap-2 sm:grid-cols-2">
        {channels.map((channel) => {
          const health = channel.p2pHealth?.playable ? "Checked" : channel.p2pHealth ? "Retry" : "Ready";
          return (
            <Link
              key={`${channel.cid}:${channel.title}`}
              href={buildWatchHref({ ...channel, eventSource: undefined, playbackType: "p2p", id: matchId || channel.id }, watchReturnTo)}
              className="rounded-lg border border-white/10 bg-background px-3 py-3 transition-colors hover:border-emerald-300/35 hover:bg-surface-elevated"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate text-xs font-black text-text-primary">{channel.displayTitle || channel.title}</p>
                  <p className="mt-1 truncate text-[11px] font-bold text-text-tertiary">
                    {[channel.network || channel.region, channel.quality, channel.alternateCount ? `${channel.alternateCount} feeds` : "P2P"].filter(Boolean).join(" · ")}
                  </p>
                </div>
                <span className="shrink-0 rounded-full border border-white/10 px-2 py-1 text-[10px] font-black text-text-secondary">
                  {health}
                </span>
              </div>
            </Link>
          );
        })}
      </div>
    </div>
  );
}

function EventStreamGroups({
  guide,
  selectedEventIndex,
  isLoading,
  matchId,
  onSelect,
}: {
  guide: NonNullable<ReturnType<typeof rankEventStreamGuide>>;
  selectedEventIndex: number;
  isLoading?: boolean;
  matchId?: string;
  onSelect?: (index: number) => void;
}) {
  const backupGroups = guide.groups.filter((group) => group.id !== "recommended");

  if (isLoading) {
    return <p className="text-xs font-bold text-text-tertiary">Finding Fotty feeds…</p>;
  }

  if (backupGroups.length === 0) {
    return null;
  }

  return (
    <div className="space-y-3">
      {backupGroups.map((group) => (
        <div key={group.id}>
          <div className="mb-2">
            <p className="text-xs font-black text-text-primary">
              {group.title} <span className="font-bold text-text-tertiary">({group.sources.length})</span>
            </p>
            {group.description ? (
              <p className="mt-0.5 text-[11px] font-medium text-text-tertiary">{group.description}</p>
            ) : null}
          </div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-3">
            {group.sources.map((source) => (
              <StreamSourceCard
                key={source.id}
                source={source}
                active={source.eventIndex === selectedEventIndex}
                className="min-w-0"
                compactMobile
                onSelect={() => {
                  if (source.eventIndex !== undefined) {
                    logStreamDiagnostic("stream_switch", {
                      matchId,
                      sourceId: source.diagnosticsSafeId,
                      healthState: source.status,
                      reason: "manual",
                    });
                    onSelect?.(source.eventIndex);
                  }
                }}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
