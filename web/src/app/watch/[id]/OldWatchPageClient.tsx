"use client";

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { PlaybackWarmup } from '@/components/PlaybackWarmup';
import { VideoPlayer } from '@/components/VideoPlayer';
import Link from 'next/link';
import { Activity, ArrowLeft, Bell, BellOff, Tv, X } from 'lucide-react';
import { AnimatePresence } from 'framer-motion';
import { FottyAPI, SwarmStatus } from '@/lib/api';
import { MatchHeaderOverlay } from '@/components/MatchHeaderOverlay';
import { MatchTimeline } from '@/components/MatchTimeline';
import { recordRecentMatch, updateUserPreferences } from '@/lib/storage';
import { useReminderToggle } from '@/lib/user-experience';

export default function WatchPage() {
  const { id } = useParams();
  const router = useRouter();
  const searchParams = useSearchParams();
  const title = searchParams.get('title') || "Live Stream";
  const league = searchParams.get('league') || undefined;
  const sport = searchParams.get('sport') || league?.split(" · ")[0] || undefined;
  const eventSourceCode = searchParams.get('source') || undefined;
  const eventSourceId = searchParams.get('eventId') || undefined;
  const rawReturnTo = searchParams.get('returnTo') || "/";
  const returnTo = rawReturnTo.startsWith("/") ? rawReturnTo : "/";
  const matchId = searchParams.get('matchId') || (Array.isArray(id) ? id[0] : id || title);
  const startsAt = searchParams.get('startsAt') || undefined;
  const isEventPlayback = Boolean(eventSourceCode && eventSourceId);
  const eventStreamKey = eventSourceCode && eventSourceId ? `${eventSourceCode}:${eventSourceId}` : undefined;
  const [isWarming, setIsWarming] = useState(() => !isEventPlayback);
  const [eventStreamState, setEventStreamState] = useState<{
    key?: string;
    embedURL?: string;
    error?: string;
  }>({});
  const [showTelemetry, setShowTelemetry] = useState(false);
  const [currentTime, setCurrentTime] = useState(() => Date.now());
  const [telemetry, setTelemetry] = useState<SwarmStatus>({
    peerCount: 0,
    downloadSpeedKbps: 0,
    bufferSeconds: 0,
    readySegmentCount: 0,
    firstSegmentReady: false,
    error: "Initializing..."
  });
  const reminderEntry = useMemo(() => {
    if (!startsAt) return null;
    const kickoff = new Date(startsAt).getTime();
    if (!Number.isFinite(kickoff) || kickoff <= currentTime) return null;

    return {
      id: matchId,
      cid: Array.isArray(id) ? id[0] : id || matchId,
      title,
      league,
      sport,
      startsAt,
      href: typeof window !== "undefined" ? `${window.location.pathname}${window.location.search}` : `/watch/${encodeURIComponent(Array.isArray(id) ? id[0] : id || "")}`,
    };
  }, [currentTime, id, league, matchId, sport, startsAt, title]);
  const { reminded, toggleReminder } = useReminderToggle(reminderEntry);

  const closePlayer = useCallback(() => {
    router.replace(returnTo);
  }, [returnTo, router]);

  useEffect(() => {
    if (!id) return;
    const cid = Array.isArray(id) ? id[0] : id;
    recordRecentMatch({ cid, title, league });
  }, [id, title, league]);

  useEffect(() => {
    if (!eventSourceCode || !eventSourceId || !eventStreamKey) return;

    let isMounted = true;

    FottyAPI.fetchEventStreams(eventSourceCode, eventSourceId)
      .then((streams) => {
        if (!isMounted) return;
        const stream = streams[0];
        if (stream?.embedUrl) {
          setEventStreamState({ key: eventStreamKey, embedURL: stream.embedUrl });
        } else {
          setEventStreamState({ key: eventStreamKey, error: "No direct stream is ready for this match." });
        }
      })
      .catch((error: unknown) => {
        if (!isMounted) return;
        const message =
          error instanceof Error && error.message.trim()
            ? error.message
            : "Fotty could not verify this watch path. Try again from Home.";
        setEventStreamState({ key: eventStreamKey, error: message });
      });

    return () => {
      isMounted = false;
    };
  }, [eventSourceCode, eventSourceId, eventStreamKey]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      setCurrentTime(Date.now());
    }, 60_000);

    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!id || isEventPlayback) return;
    const cid = Array.isArray(id) ? id[0] : id;

    const poll = async () => {
      try {
        const status = await FottyAPI.getSwarmStatus(cid);
        setTelemetry(status);
        
        // If we have peers and segments are ready, stop warming
        if (
          (status.peerCount > 0 && (status.readySegmentCount > 0 || status.firstSegmentReady)) ||
          ((status.status === "active" || status.isLive) && !status.error)
        ) {
          setIsWarming(false);
        }
      } catch (e) {
        console.error("Poll error", e);
      }
    };

    const interval = setInterval(poll, 2000);
    poll();
    const fallback = window.setTimeout(() => setIsWarming(false), 55000);

    return () => {
      clearInterval(interval);
      window.clearTimeout(fallback);
    };
  }, [id, isEventPlayback]);

  const streamURL = FottyAPI.getStreamURL(Array.isArray(id) ? id[0] : id || "");
  const isEventStreamLoading = Boolean(isEventPlayback && eventStreamState.key !== eventStreamKey);
  const eventEmbedURL = eventStreamState.key === eventStreamKey ? eventStreamState.embedURL || null : null;
  const eventStreamError = eventStreamState.key === eventStreamKey ? eventStreamState.error || null : null;
  const hasP2PTelemetry = telemetry.peerCount > 0 || telemetry.downloadSpeedKbps > 0 || telemetry.readySegmentCount > 0;
  const isP2PActive = telemetry.status === "active" || telemetry.isLive;
  const sourceSummary = isEventPlayback
    ? `${(eventSourceCode || "direct").toUpperCase()} source`
    : isP2PActive
      ? "P2P session active"
      : hasP2PTelemetry
        ? "P2P session warming"
        : "Waiting for swarm telemetry";

  const titleParts = title.split(/\s+vs\.?\s+|\s+v\s+/i);
  const homeName = titleParts[0] || title;
  const awayName = titleParts[1] || "Away";
  const isFixtureTitle = titleParts.length >= 2;

  return (
    <div className="flex min-h-dvh flex-col overflow-hidden bg-background text-text-primary">
      <AnimatePresence mode="wait">
        {!isEventPlayback && isWarming ? (
          <div key="warmup" className="fixed inset-0 z-50">
            <PlaybackWarmup 
              title={title}
              peerCount={telemetry.peerCount || 0}
              speedKbps={isNaN(telemetry.downloadSpeedKbps) ? 0 : telemetry.downloadSpeedKbps}
              bufferSeconds={telemetry.bufferSeconds || 0}
              readySegments={telemetry.readySegmentCount || 0}
              statusMessage={telemetry.error || (telemetry.peerCount > 0 ? "Building Swarm..." : "Searching for Peers...")}
              onCancel={closePlayer}
              onSkip={() => setIsWarming(false)}
            />
          </div>
        ) : (
          <div key="player" className="flex h-dvh min-h-dvh flex-col animate-in fade-in duration-500">
            {/* Video Player Section (iOS Parity) */}
            <div className="relative aspect-video w-full shrink-0 bg-black">
              {isEventPlayback ? (
                <DirectEventPlayer
                  title={title}
                  embedURL={eventEmbedURL}
                  isLoading={isEventStreamLoading}
                  error={eventStreamError}
                  returnTo={returnTo}
                />
              ) : (
                <VideoPlayer 
                  src={streamURL}
                  title={title}
                />
              )}
              
              {/* Match/Channel Header Overlay (Top Center) */}
              <div className="pointer-events-none absolute left-1/2 top-[calc(0.75rem+env(safe-area-inset-top))] z-30 max-w-[calc(100vw-7rem)] -translate-x-1/2 sm:top-6">
                {isFixtureTitle ? (
                  <MatchHeaderOverlay
                    home={{ name: homeName, badge: "" }}
                    away={{ name: awayName, badge: "" }}
                  />
                ) : (
                  <div className="flex max-w-[70vw] items-center gap-2 rounded-full border border-white/10 bg-black/50 px-4 py-2 text-white backdrop-blur-md">
                    <Tv size={16} className="shrink-0 text-accent" />
                    <span className="truncate text-xs font-black">{title}</span>
                  </div>
                )}
              </div>

              {/* Close Button (Left) */}
              <button 
                type="button"
                aria-label="Close player"
                onClick={closePlayer}
                className="absolute left-3 top-[calc(0.75rem+env(safe-area-inset-top))] z-40 flex h-10 w-10 items-center justify-center rounded-full border border-white/10 bg-black/55 backdrop-blur-md transition-transform active:scale-90 sm:left-6 sm:top-6"
                  >
                    <X size={18} className="text-white" />
                  </button>
            </div>

            <div className="border-b border-white/5 bg-surface px-md py-3">
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-[10px] font-bold uppercase text-text-tertiary">Now Playing</p>
                  <div className="mt-1 flex min-w-0 items-center gap-2">
                    {isEventPlayback ? <Tv size={15} className="shrink-0 text-accent" /> : <Activity size={15} className="shrink-0 text-accent" />}
                    <p className="truncate text-sm font-bold text-text-primary">{sourceSummary}</p>
                  </div>
                </div>

                <div className="flex shrink-0 items-center gap-2">
                  {reminderEntry && (
                    <button
                      type="button"
                      aria-pressed={reminded}
                      onClick={() => {
                        const active = toggleReminder();
                        if (active) {
                          updateUserPreferences({ matchReminders: true });
                        }
                      }}
                      className={reminded
                        ? "rounded-full bg-accent px-3 py-2 text-[11px] font-bold text-white"
                        : "rounded-full border border-white/10 bg-white/5 px-3 py-2 text-[11px] font-bold text-text-secondary"}
                    >
                      <span className="inline-flex items-center gap-2">
                        {reminded ? <BellOff size={13} /> : <Bell size={13} />}
                        {reminded ? "Reminder saved" : "Remind me"}
                      </span>
                    </button>
                  )}
                  {!isEventPlayback && (
                    <button
                      type="button"
                      aria-pressed={showTelemetry}
                      onClick={() => setShowTelemetry(!showTelemetry)}
                      className={showTelemetry
                        ? "rounded-full bg-accent px-3 py-2 text-[11px] font-bold text-white"
                        : "rounded-full border border-white/10 bg-white/5 px-3 py-2 text-[11px] font-bold text-text-secondary"}
                    >
                      {showTelemetry ? "Hide Pulse" : "Pulse"}
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={closePlayer}
                    className="rounded-full border border-white/10 bg-white/5 px-3 py-2 text-[11px] font-bold text-text-primary"
                  >
                    Home
                  </button>
                </div>
              </div>
            </div>

            {!isEventPlayback && showTelemetry && (
              <div className="border-b border-white/5 bg-surface-elevated/40 px-md py-3">
                <div className="grid grid-cols-3 gap-2">
                  <TelemetryCard label="Peers" value={telemetry.peerCount > 0 ? `${telemetry.peerCount}` : isP2PActive ? "Active" : "Warming"} />
                  <TelemetryCard label="Speed" value={telemetry.downloadSpeedKbps > 0 ? `${(telemetry.downloadSpeedKbps / 1024).toFixed(1)} Mbps` : isP2PActive ? "HLS" : "Waiting"} />
                  <TelemetryCard label="Segments" value={telemetry.readySegmentCount > 0 ? `${telemetry.readySegmentCount}` : telemetry.firstSegmentReady ? "Ready" : "Building"} />
                </div>
                {telemetry.error && (
                  <p className="mt-3 text-xs font-medium leading-5 text-text-tertiary">{telemetry.error}</p>
                )}
              </div>
            )}

            <div className="min-h-0 flex-1 overflow-hidden bg-background">
              <MatchTimeline
                title={title}
                league={league}
                sport={sport}
                isP2PPlayback={!isEventPlayback}
                telemetry={telemetry}
              />
            </div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}

function DirectEventPlayer({
  title,
  embedURL,
  isLoading,
  error,
  returnTo,
}: {
  title: string;
  embedURL: string | null;
  isLoading: boolean;
  error: string | null;
  returnTo?: string;
}) {
  if (isLoading) {
    return (
      <div className="grid h-full w-full place-items-center bg-black">
        <div className="flex flex-col items-center gap-3">
          <div className="h-9 w-9 animate-spin rounded-full border-4 border-accent border-t-transparent" />
          <p className="text-xs font-bold text-white/70">Loading match stream</p>
        </div>
      </div>
    );
  }

  if (error || !embedURL) {
    return (
      <div className="grid h-full w-full place-items-center bg-black px-6 text-center">
        <div className="max-w-xs space-y-4">
          <p className="text-sm font-black text-white">Stream unavailable</p>
          <p className="text-xs font-medium text-white/60">{error || "This source did not return a playable stream."}</p>
          <Link
            href={returnTo || "/"}
            className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-xs font-bold text-white"
          >
            <ArrowLeft size={14} />
            Back to Live
          </Link>
        </div>
      </div>
    );
  }

  return (
    <iframe
      title={title}
      src={embedURL}
      className="h-full w-full border-0 bg-black"
      allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
      allowFullScreen
      referrerPolicy="origin"
    />
  );
}

function TelemetryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-white/5 bg-surface px-3 py-3">
      <p className="text-[10px] font-bold uppercase text-text-tertiary">{label}</p>
      <p className="mt-1 truncate text-sm font-black text-text-primary">{value}</p>
    </div>
  );
}
