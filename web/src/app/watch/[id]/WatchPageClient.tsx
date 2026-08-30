"use client";

import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { PlaybackWarmup } from '@/components/PlaybackWarmup';
import { VideoPlayer } from '@/components/VideoPlayer';
import { Activity, Bell, BellOff, Info, Tv, X } from 'lucide-react';
import { AnimatePresence } from 'framer-motion';
import { FottyAPI, ScrapedMatch } from '@/lib/api';
import { trackEvent } from '@/lib/analytics';
import { buildWatchMatchContext, findWatchMatch, logStreamDiagnostic, pickBackupAfterFailure, rankEventStreamGuide } from '@/lib/stream-guide';
import { MatchHeaderOverlay } from '@/components/MatchHeaderOverlay';
import { MatchTimeline } from '@/components/MatchTimeline';
import { SponsoredSlot } from '@/components/SponsoredSlot';
import { recordRecentMatch, updateUserPreferences } from '@/lib/storage';
import { useReminderToggle } from '@/lib/user-experience';
import { useAuth } from '@/components/AuthProvider';
import { useEntitlement } from '@/components/EntitlementProvider';
import { WatchAccessGate } from '@/components/WatchAccessGate';
import { isAccountsEnabled } from '@/lib/accounts';
import { getWatchAccess } from '@/lib/watch-access';
import { isP2PContentId, resolveWatchRouteId, buildWatchPageHref } from '@/lib/watch-session';
import { isP2PSessionActive } from '@/lib/p2p-session';
import { FOTTY_LIVE_LABEL } from '@/lib/watch-stream-display';
import { MatchStreamHub } from '@/components/stream-guide/MatchStreamHub';
import { buildWatchHref, hasStreameXPlayback } from '@/lib/live';
import { buildDirectEmbedUrl } from '@/lib/stream-guide/embed-url';
import { isV2WatchMode } from '@/lib/v2/watch-context';
import { v2AppPath, v2HomePath } from '@/lib/v2/preview';
import { relatedWatchMatches } from '@/lib/v2/watch-related-matches';
import { formatStreamFeedLabel } from '@/lib/stream-guide/feed-label';
import { useMatchFeedPoll } from '@/hooks/use-match-feed-poll';
import { useWatchKeyboard } from '@/hooks/use-watch-keyboard';
import { requestWatchPictureInPicture } from '@/lib/watch-pip';
import { fixtureTeamLabels, isEventFixture } from "@/lib/fixture-normalization";
import { WatchFixtureHeader } from '@/components/watch/WatchFixtureHeader';
import { WatchEventHeader } from '@/components/watch/WatchEventHeader';
import { useP2PBrokerSession } from './useP2PBrokerSession';
import { useEventStreams } from './useEventStreams';
import { useEventPlaybackRecovery } from './useEventPlaybackRecovery';
import { usePlaybackController } from './usePlaybackController';
import { resolveEventBackupIndex } from '@/lib/watch-event-recovery';
import { classifyPlaybackFault } from '@/lib/playback-controller';
import { decodeWatchEventSources, dedupeWatchEventSources, watchEventSourcesKey } from '@/lib/watch-event-sources';
import {
  StreamDiagnosticsPanel,
  TelemetryGrid,
  WatchDetailsPanel,
  WatchVideoStage,
} from '@/components/watch/WatchPanels';
import { WatchToolbarV2 } from '@/components/watch/WatchToolbarV2';
import { WatchAsideV2 } from '@/components/watch/WatchAsideV2';
import { MatchStreamHubV2 } from '@/components/stream-guide/MatchStreamHubV2';
import { DirectEventPlayer, type DirectEventPlayerHandle, UnavailablePlayer, watchUnavailableTitle } from '@/components/watch/WatchPlayers';

const MAX_P2P_SESSION_RECOVERIES = 2;
const EVENT_IFRAME_LOAD_TIMEOUT_MS = 20_000;
const EMBED_PLAYBACK_RECOVERY_MS = 20_000;
const DIRECT_P2P_ROUTE_VALUES = new Set(["direct", "simple", "straight", "native", "edge", "app"]);

export default function WatchPageClient() {
  const { id } = useParams();
  const router = useRouter();
  const searchParams = useSearchParams();
  const routeId = resolveWatchRouteId(id, searchParams);
  const { session, isReady: authReady } = useAuth();
  const entitlement = useEntitlement();
  const watchAccess = !isAccountsEnabled()
    ? { allowed: true as const, reason: null }
    : authReady
      ? getWatchAccess(session, entitlement)
      : { allowed: false, reason: null };
  const title = searchParams.get('title') || "Live Stream";
  const league = searchParams.get('league') || undefined;
  const sport = searchParams.get('sport') || league?.split(" · ")[0] || undefined;
  const eventSourceCode = searchParams.get('source') || undefined;
  const eventSourceId = searchParams.get('eventId') || undefined;
  const eventSourcesParam = searchParams.get('sources') || undefined;
  const p2pRoute = (searchParams.get('p2pRoute') || "").trim().toLowerCase();
  const useDirectP2PRoute = DIRECT_P2P_ROUTE_VALUES.has(p2pRoute);
  const defaultReturn = v2HomePath();
  const rawReturnTo = searchParams.get('returnTo') || defaultReturn;
  const returnTo = rawReturnTo.startsWith("/") ? rawReturnTo : defaultReturn;
  const v2Watch = isV2WatchMode(returnTo);
  const homeReturnTo = v2Watch ? v2HomePath() : returnTo;
  const matchId = searchParams.get('matchId') || routeId || title;
  const cidValue = routeId || "";
  const startsAt = searchParams.get('startsAt') || undefined;
  const isEventPlayback = Boolean(eventSourceCode && eventSourceId);
  const eventSources = useMemo(() => {
    const primary = eventSourceCode && eventSourceId ? [{ source: eventSourceCode, id: eventSourceId }] : [];
    return dedupeWatchEventSources([...primary, ...decodeWatchEventSources(eventSourcesParam)]);
  }, [eventSourceCode, eventSourceId, eventSourcesParam]);
  const eventStreamKey = eventSources.length > 0 ? watchEventSourcesKey(eventSources) : undefined;

  const [showTelemetry, setShowTelemetry] = useState(false);
  const [showDiagnostics, setShowDiagnostics] = useState(false);
  const [autoFailoverMessage, setAutoFailoverMessage] = useState<string | null>(null);
  const [currentTime, setCurrentTime] = useState(() => Date.now());
  const [matchRecord, setMatchRecord] = useState<ScrapedMatch | null>(null);
  const [boardMatches, setBoardMatches] = useState<ScrapedMatch[]>([]);
  const [matchLookupDone, setMatchLookupDone] = useState(false);
  const videoStageRef = useRef<HTMLDivElement>(null);
  const directEventPlayerRef = useRef<DirectEventPlayerHandle>(null);
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const failedEventSourceIdsRef = useRef<Set<string>>(new Set());
  const currentEventEmbedURLRef = useRef<string | null>(null);
  const embedPlaybackStartedRef = useRef(false);
  const [failedEventSourceIds, setFailedEventSourceIds] = useState<string[]>([]);

  useEffect(() => {
    // Block unwanted popups and click-jacking redirects triggered by third-party embed scripts
    const origOpen = window.open;
    window.open = function (...args) {
      console.warn("[Fotty Guard] Blocked popup window:", args[0]);
      return null;
    };
    return () => {
      window.open = origOpen;
    };
  }, []);
  const {
    state: playbackState,
    startAttempt,
    reportFrameReady,
    reportDecodedProgress,
    reportFault,
    commitRecovery,
    advanceAttempt,
  } = usePlaybackController();

  const p2pCid = useMemo(() => {
    if (isP2PContentId(matchRecord?.cid)) return matchRecord.cid;
    if (!isEventPlayback && isP2PContentId(cidValue)) return cidValue;
    return "";
  }, [cidValue, isEventPlayback, matchRecord?.cid]);

  const isP2PChannelWatch =
    matchRecord?.kind === "channel" ||
    searchParams.get("kind") === "channel" ||
    (isP2PContentId(cidValue) && !startsAt && !isEventPlayback);
  const blockedFixturePlayback =
    watchAccess.allowed &&
    authReady &&
    matchLookupDone &&
    !isEventPlayback &&
    !isP2PChannelWatch &&
    !(matchRecord && hasStreameXPlayback(matchRecord));

  const useEventEmbed = isEventPlayback;
  const useP2PPlayback = isP2PChannelWatch;

  const {
    brokerPlaybackState,
    brokerWarmMessage,
    brokerSessionId,
    brokerWarmStartedAt,
    playerGeneration,
    telemetry,
    p2pHealth,
    retryBrokerSession,
  } = useP2PBrokerSession({
    enabled: watchAccess.allowed && useP2PPlayback && Boolean(p2pCid) && !useDirectP2PRoute,
    cid: p2pCid,
    title,
    matchId,
  });

  const clearPlaybackMessages = useCallback(() => {
    setAutoFailoverMessage(null);
    setPlaybackError(null);
    failedEventSourceIdsRef.current.clear();
    setFailedEventSourceIds([]);
  }, []);

  const {
    eventStreamState,
    eventFrameLoaded,
    setEventFrameLoaded,
    eventFrameTimedOut,
    setEventFrameTimedOut,
    streamsCheckedAt,
    refreshEventStreams,
    selectEventStream,
  } = useEventStreams({
    enabled: watchAccess.allowed && useEventEmbed,
    eventSources,
    eventStreamKey,
    matchId,
    onStreamsApplied: clearPlaybackMessages,
  });

  const reminderEntry = useMemo(() => {
    if (!startsAt) return null;
    const kickoff = new Date(startsAt).getTime();
    if (!Number.isFinite(kickoff) || kickoff <= currentTime) return null;

    return {
      id: matchId,
      cid: cidValue || matchId,
      title,
      league,
      sport,
      startsAt,
      href: typeof window !== "undefined" ? `${window.location.pathname}${window.location.search}` : `/watch/${encodeURIComponent(cidValue || "")}`,
    };
  }, [cidValue, currentTime, league, matchId, sport, startsAt, title]);
  const { reminded, toggleReminder } = useReminderToggle(reminderEntry);

  const watchReturnTo = useMemo(() => {
    const params = new URLSearchParams();
    if (title) params.set("title", title);
    if (league) params.set("league", league);
    if (sport) params.set("sport", sport);
    if (eventSourceCode) params.set("source", eventSourceCode);
    if (eventSourceId) params.set("eventId", eventSourceId);
    if (eventSourcesParam) params.set("sources", eventSourcesParam);
    if (startsAt) params.set("startsAt", startsAt);
    if (matchId) params.set("matchId", matchId);
    if (rawReturnTo) params.set("returnTo", rawReturnTo);
    if (cidValue) {
      if (isP2PContentId(cidValue)) params.set("cid", cidValue);
      else params.set("id", cidValue);
    }
    return buildWatchPageHref(params);
  }, [cidValue, eventSourceCode, eventSourceId, eventSourcesParam, league, matchId, rawReturnTo, sport, startsAt, title]);

  const closePlayer = useCallback(() => {
    router.replace(homeReturnTo);
  }, [homeReturnTo, router]);

  useEffect(() => {
    if (!cidValue) return;
    recordRecentMatch({ cid: cidValue, title, league });
  }, [cidValue, title, league]);

  useEffect(() => {
    if (!watchAccess.allowed) return;
    let cancelled = false;

    FottyAPI.fetchMatchesFresh()
      .then((matches) => {
        if (cancelled) return;
        setBoardMatches(matches);
        const found = findWatchMatch(matches, cidValue, matchId, title);
        setMatchRecord(found);
        if (!isEventPlayback && found && hasStreameXPlayback(found)) {
          router.replace(buildWatchHref(found, returnTo));
        }
      })
      .catch(() => undefined)
      .finally(() => {
        if (!cancelled) setMatchLookupDone(true);
      });

    return () => {
      cancelled = true;
    };
  }, [cidValue, isEventPlayback, matchId, returnTo, router, title, watchAccess.allowed]);

  const refreshWatchBoard = useCallback(async () => {
    try {
      const matches = await FottyAPI.fetchMatchesFresh();
      setBoardMatches(matches);
      const found = findWatchMatch(matches, cidValue, matchId, title);
      if (found) setMatchRecord(found);
      return true;
    } catch {
      return false;
    }
  }, [cidValue, matchId, title]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      setCurrentTime(Date.now());
    }, 30_000);

    return () => window.clearInterval(interval);
  }, []);

  const isBrokerWarming = useP2PPlayback && !useDirectP2PRoute && brokerPlaybackState === "warming";
  // Default path keeps broker warmup/session reuse. p2pRoute=direct uses the
  // native-style public P2P manifest with a short-lived token for Chrome testing.
  const streamURL = useMemo(() => {
    if (!useP2PPlayback || !p2pCid) {
      return "";
    }
    if (useDirectP2PRoute) {
      return FottyAPI.getNativeP2PStreamURL(p2pCid);
    }
    if (brokerPlaybackState !== "ready" || !brokerSessionId) {
      return "";
    }
    return FottyAPI.getStreamURL(p2pCid, brokerSessionId);
  }, [brokerPlaybackState, brokerSessionId, p2pCid, useDirectP2PRoute, useP2PPlayback]);
  const isEventStreamLoading = Boolean(useEventEmbed && !eventSourceCode && !eventSourceId && eventStreamState.key !== eventStreamKey);
  const eventStreams = useMemo(
    () => (eventStreamState.key === eventStreamKey ? eventStreamState.streams || [] : []),
    [eventStreamKey, eventStreamState.key, eventStreamState.streams]
  );
  const selectedEventStreamIndex = Math.min(eventStreamState.selectedIndex || 0, Math.max(eventStreams.length - 1, 0));
  const selectedEventStream = eventStreams[selectedEventStreamIndex];
  const eventEmbedURL = useMemo(() => {
    if (selectedEventStream?.embedUrl?.trim()) return selectedEventStream.embedUrl;
    const source = selectedEventStream?.source || eventSourceCode;
    const id = selectedEventStream?.id || eventSourceId;
    if (!source || !id) return null;
    return buildDirectEmbedUrl(source, id, selectedEventStream?.streamNo || 1);
  }, [
    eventSourceCode,
    eventSourceId,
    selectedEventStream?.embedUrl,
    selectedEventStream?.source,
    selectedEventStream?.id,
    selectedEventStream?.streamNo,
  ]);
  useLayoutEffect(() => {
    currentEventEmbedURLRef.current = eventEmbedURL;
    embedPlaybackStartedRef.current = false;
    if (useEventEmbed && eventEmbedURL) {
      const sourceKey = `event:${eventStreamKey || matchId}`;
      const maxRecoveries = Math.max(0, eventStreams.length - 1);
      if (
        playbackState.mode !== "event" ||
        playbackState.sourceKey !== sourceKey ||
        playbackState.maxRecoveries !== maxRecoveries
      ) {
        startAttempt(sourceKey, "event", maxRecoveries);
      }
    }
  }, [
    eventEmbedURL,
    eventStreamKey,
    eventStreams.length,
    matchId,
    playbackState.maxRecoveries,
    playbackState.mode,
    playbackState.sourceKey,
    startAttempt,
    useEventEmbed,
  ]);
  useEffect(() => {
    if (useP2PPlayback && p2pCid) {
      startAttempt(`p2p:${p2pCid}`, "p2p", MAX_P2P_SESSION_RECOVERIES);
    }
  }, [p2pCid, startAttempt, useP2PPlayback]);
  const eventStreamError = eventStreamState.key === eventStreamKey ? eventStreamState.error || null : null;
  const hasP2PTelemetry = telemetry.peerCount > 0 || telemetry.downloadSpeedKbps > 0 || telemetry.readySegmentCount > 0;
  const p2pUnavailable =
    useP2PPlayback &&
    !useDirectP2PRoute &&
    brokerPlaybackState === "failed" &&
    !playbackError;
  const isP2PActive = !p2pUnavailable && (useDirectP2PRoute ? Boolean(streamURL) : Boolean(brokerSessionId) || isP2PSessionActive(telemetry));
  const p2pFeedLive = !p2pUnavailable && (useDirectP2PRoute ? Boolean(streamURL) : Boolean(brokerSessionId) || isP2PActive || Boolean(p2pHealth?.playable));
  const sourceSummary = useEventEmbed
    ? FOTTY_LIVE_LABEL
    : p2pUnavailable
      ? "P2P source unavailable"
    : useDirectP2PRoute
      ? "P2P stream"
    : p2pFeedLive
      ? brokerSessionId
        ? "P2P broker session active"
        : isP2PActive
          ? "P2P session active"
          : "P2P stream connected"
      : hasP2PTelemetry
        ? "P2P session warming"
        : "Connecting to P2P swarm…";

  const titleParts = title.split(/\s+vs\.?\s+|\s+v\s+/i);
  const homeName = titleParts[0] || title;
  const awayName = titleParts[1] || "Away";
  const isFixtureTitle = titleParts.length >= 2;
  const eventGuide = useEventEmbed ? rankEventStreamGuide(eventStreams, matchId) : null;

  const switchToEventBackup = useCallback(
    (reason: string) => {
      const resolved = resolveEventBackupIndex(
        eventGuide,
        selectedEventStreamIndex,
        failedEventSourceIdsRef.current,
        pickBackupAfterFailure
      );
      const attemptId = playbackState.attemptId;
      const failed = eventGuide?.all.find(
        (source) => source.eventIndex === selectedEventStreamIndex
      );
      if (failed?.id) {
        failedEventSourceIdsRef.current.add(failed.id);
        setFailedEventSourceIds(Array.from(failedEventSourceIdsRef.current));
      }

      const recoveryAction = reportFault(
        attemptId,
        classifyPlaybackFault(reason, "event_feed_failure")
      );
      if (!resolved || recoveryAction !== "switch-source") return false;

      const { nextIndex, backup } = resolved;
      setAutoFailoverMessage(`${reason} Switched to ${formatStreamFeedLabel(backup, nextIndex)}.`);
      setPlaybackError(null);
      setEventFrameTimedOut(false);
      commitRecovery(attemptId);
      selectEventStream(nextIndex);
      logStreamDiagnostic("fallback_used", {
        matchId,
        sourceId: backup.diagnosticsSafeId,
        playbackMode: "event",
        reason,
      });
      return true;
    },
    [
      commitRecovery,
      eventGuide,
      matchId,
      playbackState.attemptId,
      reportFault,
      selectEventStream,
      selectedEventStreamIndex,
      setEventFrameTimedOut,
    ]
  );

  const tryNextDirectEventFeed = useCallback(
    (reason: string) => {
      const switched = switchToEventBackup(reason);
      if (!switched) {
        const remaining = (eventStreams?.length || 0) - failedEventSourceIdsRef.current.size;
        setPlaybackError(
          remaining > 0
            ? "Could not switch feeds automatically. Use Try backup below or pick another stream."
            : "All direct feeds were tried. Refresh the list or choose another source below."
        );
      }
      return switched;
    },
    [eventStreams.length, switchToEventBackup]
  );

  // StreameX-only for fixtures — P2P channel playback stays on the Live Board for now.
  useEventPlaybackRecovery({
    useEventEmbed,
    // A direct provider iframe is cross-origin. Frame load is not decoded
    // playback proof, and lack of observable playhead data must not make Fotty
    // abandon a stream the user may already be watching.
    canObservePlayback: Boolean(eventEmbedURL?.startsWith("/")),
    eventEmbedURL,
    eventFrameLoaded,
    eventStreamError,
    feedCount: eventStreams?.length || 0,
    embedPlaybackStarted: playbackState.phase === "playing",
    embedPlaybackStartedRef,
    selectedEventStreamIndex,
    loadTimeoutMs: EVENT_IFRAME_LOAD_TIMEOUT_MS,
    startTimeoutMs: EMBED_PLAYBACK_RECOVERY_MS,
    onLoadTimeout: () => tryNextDirectEventFeed("This feed is slow to load — trying another stream."),
    onStartTimeout: () =>
      tryNextDirectEventFeed("This feed had trouble starting — trying another stream."),
    setEventFrameTimedOut,
  });

  // Mid-playback failover relies on embed frame errors while using cross-origin provider iframes.

  const matchContext = buildWatchMatchContext({
    title,
    league,
    sport,
    startsAt,
    match: matchRecord,
    hasWorkingStream: useEventEmbed
      ? Boolean(eventEmbedURL && !eventStreamError)
      : !p2pUnavailable && !playbackError,
    isCheckingStreams: isEventStreamLoading || isBrokerWarming,
  });

  const isEventWatch = isEventPlayback || Boolean(matchRecord && isEventFixture(matchRecord));
  const isFixtureWatch = Boolean(
    matchRecord &&
    !isEventWatch &&
    !fixtureTeamLabels(matchRecord).isUpdating
  );
  const statusTone =
    matchContext.status === "live"
      ? "live"
      : matchContext.status === "upcoming"
        ? "upcoming"
        : matchContext.status === "finished"
          ? "finished"
          : "neutral";

  const streamHealthLine = useMemo(() => {
    if (!useEventEmbed || !eventGuide?.recommended) return undefined;
    const source = eventGuide.recommended;
    const index = eventGuide.all.findIndex((item) => item.id === source.id);
    return formatStreamFeedLabel(source, Math.max(index, 0));
  }, [eventGuide, useEventEmbed]);

  const sameLeagueMatches = useMemo(
    () =>
      relatedWatchMatches(boardMatches, matchRecord, {
        matchId,
        cid: cidValue,
        league,
      }),
    [boardMatches, cidValue, league, matchId, matchRecord]
  );

  useMatchFeedPoll(refreshWatchBoard, 45_000, v2Watch && matchContext.status === "live");

  const handleSelectFeed = useCallback(
    (index: number) => {
      const stream = eventStreams[index];
      if (!stream) return;
      trackEvent("change_source_click", {
        title,
        streamNo: stream.streamNo,
        playbackMode: "event",
        reason: "keyboard_or_chip",
      });
      setPlaybackError(null);
      setAutoFailoverMessage(null);
      embedPlaybackStartedRef.current = false;
      advanceAttempt(playbackState.attemptId);
      selectEventStream(index);
    },
    [advanceAttempt, eventStreams, playbackState.attemptId, selectEventStream, title]
  );

  const handleTogglePiP = useCallback(async () => {
    const result = await requestWatchPictureInPicture(videoStageRef.current);
    if (!result.ok && result.reason === "embed-only") {
      setAutoFailoverMessage("PiP works on native player feeds. Direct embeds open in the provider frame.");
    }
  }, []);

  useWatchKeyboard({
    enabled: v2Watch && watchAccess.allowed,
    feedCount: eventStreams.length,
    onSelectFeed: useEventEmbed && eventStreams.length > 1 ? handleSelectFeed : undefined,
    onBack: closePlayer,
    onTogglePiP: v2Watch && !useEventEmbed && Boolean(streamURL) ? handleTogglePiP : undefined,
  });

  const handleRetryPlayback = useCallback(() => {
    setPlaybackError(null);
    if (useP2PPlayback && p2pCid) {
      startAttempt(`p2p:${p2pCid}`, "p2p", MAX_P2P_SESSION_RECOVERIES);
    }
    retryBrokerSession();
    logStreamDiagnostic("playback_recovered", { matchId, playbackMode: useEventEmbed ? "event" : "p2p", reason: "retry" });
  }, [matchId, p2pCid, retryBrokerSession, startAttempt, useEventEmbed, useP2PPlayback]);

  const handlePlaybackFailure = useCallback(
    (message: string, reason: string) => {
      const attemptId = playbackState.attemptId;
      const recoveryAction = reportFault(
        attemptId,
        classifyPlaybackFault(message, reason)
      );
      if (recoveryAction === "none") return;
      if (useP2PPlayback && !useEventEmbed && p2pCid) {
        if (useDirectP2PRoute) {
          setPlaybackError(message);
          return;
        }
        if (recoveryAction === "recycle-session") {
          setPlaybackError(null);
          setAutoFailoverMessage("Stream hiccup — reconnecting this P2P session.");
          commitRecovery(attemptId);
          retryBrokerSession();
          logStreamDiagnostic("playback_stalled", {
            matchId,
            sourceId: p2pCid,
            playbackMode: "p2p",
            reason: "player_failure_session_recycle",
          });
          return;
        }
      }

      setPlaybackError(message);
    },
    [
      commitRecovery,
      matchId,
      p2pCid,
      playbackState.attemptId,
      reportFault,
      retryBrokerSession,
      useDirectP2PRoute,
      useEventEmbed,
      useP2PPlayback,
    ]
  );

  return (
    <div
      className="flex min-h-[100svh] flex-col overflow-x-hidden bg-background text-text-primary"
      data-shell={v2Watch ? "v2-watch" : undefined}
    >
      <AnimatePresence mode="wait">
        {!authReady ? (
          <div key="auth-loading" className="flex min-h-[100svh] items-center justify-center bg-black text-sm font-bold text-white/60">
            Opening stream…
          </div>
        ) : !watchAccess.allowed ? (
          <div key="gate" className="flex min-h-[100svh] flex-col bg-black">
            <WatchAccessGate
              reason={watchAccess.reason!}
              title={title}
              returnTo={watchReturnTo}
              homeHref={homeReturnTo}
            />
          </div>
        ) : blockedFixturePlayback ? (
          <div key="streameX-required" className="flex min-h-[100svh] flex-col bg-black">
            <UnavailablePlayer
              title="Stream not linked yet"
              message={
                v2Watch
                  ? "Fotty does not have a live stream for this match yet. Check back closer to kickoff, or browse the schedule for other matches."
                  : "Fotty does not have a live stream for this match yet. Check back closer to kickoff, or browse Discover for other fixtures."
              }
              onBrowseLive={closePlayer}
              guideHref={v2Watch ? v2AppPath("/search") : "/search"}
              sourceLabel={title}
            />
          </div>
        ) : isBrokerWarming ? (
          <div key="warmup" className="fixed inset-0 z-50">
            <PlaybackWarmup 
              title={title}
              peerCount={telemetry.peerCount || 0}
              speedKbps={isNaN(telemetry.downloadSpeedKbps) ? 0 : telemetry.downloadSpeedKbps}
              bufferSeconds={telemetry.bufferSeconds || 0}
              readySegments={telemetry.readySegmentCount || 0}
              statusMessage={
                brokerWarmMessage ||
                telemetry.error ||
                (telemetry.readySegmentCount > 0
                  ? "Validating stream segments…"
                  : "Warming P2P broker session…")
              }
              sourceId={p2pCid || cidValue}
              sessionId={brokerSessionId}
              startedAt={brokerWarmStartedAt}
              hasTelemetry={Boolean(telemetry.peerCount > 0 || telemetry.downloadSpeedKbps > 0 || telemetry.readySegmentCount > 0 || telemetry.firstSegmentReady)}
              onCancel={closePlayer}
            />
          </div>
        ) : (
          <div
            key="player"
            className={`flex min-h-[100svh] animate-in flex-col overflow-x-hidden fade-in duration-500 ${
              v2Watch
                ? "lg:grid lg:h-[100dvh] lg:grid-cols-[minmax(0,1fr)_minmax(260px,320px)] lg:grid-rows-1 lg:overflow-hidden"
                : "lg:grid lg:h-[100dvh] lg:grid-cols-[minmax(0,1fr)_minmax(280px,360px)] lg:grid-rows-1 lg:overflow-hidden"
            }`}
          >
            <div className="flex min-h-0 flex-col overflow-visible lg:overflow-y-auto">
              <WatchVideoStage ref={videoStageRef} v2={v2Watch}>
                {useEventEmbed ? (
                <DirectEventPlayer
                  ref={directEventPlayerRef}
                  title={title}
                  embedURL={eventEmbedURL}
                  eventSource={
                    selectedEventStream
                      ? {
                          source: selectedEventStream.source,
                          id: selectedEventStream.id,
                          streamNo: selectedEventStream.streamNo,
                        }
                      : undefined
                  }
                  streamKey={
                    selectedEventStream
                      ? `${selectedEventStream.provider || "event"}:${selectedEventStream.source}:${selectedEventStream.id}:${selectedEventStream.streamNo}`
                      : undefined
                  }
                  isLoading={isEventStreamLoading}
                  error={eventStreamError}
                  returnTo={homeReturnTo}
                  onFrameLoad={(loadedEmbedURL) => {
                    if (loadedEmbedURL !== currentEventEmbedURLRef.current) return;
                    reportFrameReady(playbackState.attemptId);
                    setEventFrameLoaded(true);
                    setEventFrameTimedOut(false);
                    setAutoFailoverMessage(null);
                  }}
                  onPlaybackStarted={() => {
                    embedPlaybackStartedRef.current = true;
                    reportDecodedProgress(playbackState.attemptId);
                  }}
                  onPlaybackPulse={() => {
                    embedPlaybackStartedRef.current = true;
                    reportDecodedProgress(playbackState.attemptId);
                  }}
                  onPlaybackStalled={(failedEmbedURL) => {
                    if (failedEmbedURL !== currentEventEmbedURLRef.current) return;
                    tryNextDirectEventFeed("This feed stopped — trying another stream.");
                  }}
                  onFrameError={(failedEmbedURL) => {
                    if (failedEmbedURL !== currentEventEmbedURLRef.current) return;
                    tryNextDirectEventFeed("This feed had trouble loading — trying another stream.");
                  }}
                  onRetry={refreshEventStreams}
                />
              ) : p2pUnavailable ? (
                <div className="pointer-events-auto absolute inset-0">
                <UnavailablePlayer
                  title={watchUnavailableTitle(brokerWarmMessage)}
                  message={
                    brokerWarmMessage ||
                    "Fotty will keep checking as coverage improves. Try another feed below, retry this source, or head back to Home."
                  }
                  onRetry={handleRetryPlayback}
                  retryLabel="Try again"
                  guideHref={v2Watch ? v2AppPath("/search") : "/search"}
                  onBrowseLive={closePlayer}
                  sourceLabel={title}
                />
                </div>
              ) : streamURL ? (
                <div className="pointer-events-auto absolute inset-0 min-h-0">
                <VideoPlayer
                  key={`${p2pCid || cidValue}-${brokerSessionId}-${playerGeneration}`}
                  src={streamURL}
                  title={title}
                  playbackKey={playerGeneration}
                  onPlaybackFailure={handlePlaybackFailure}
                  onRetry={handleRetryPlayback}
	                  onPlaybackStarted={() => {
	                    reportDecodedProgress(playbackState.attemptId);
	                    setPlaybackError(null);
	                  }}
                />
                </div>
              ) : (
                <div className="pointer-events-auto absolute inset-0">
                <UnavailablePlayer
                  title="Preparing stream"
                  message="Fotty is checking this watch path and preparing the player."
                  onBrowseLive={closePlayer}
                />
                </div>
              )}

              {/* Video overlays — classic only; v2 uses toolbar below the player */}
              {!v2Watch && !p2pUnavailable ? (
                <div className="pointer-events-none absolute left-1/2 top-[calc(0.75rem+env(safe-area-inset-top))] z-30 max-w-[calc(100vw-7rem)] -translate-x-1/2 sm:top-6">
                  {isFixtureTitle ? (
                    <MatchHeaderOverlay
                      home={{ name: homeName, badge: "" }}
                      away={{ name: awayName, badge: "" }}
                    />
                  ) : (
                    <div className="flex max-w-[70vw] items-center gap-2 rounded-full border border-white/10 bg-black/50 px-4 py-2 text-white backdrop-blur-md">
                      <Tv size={16} className={`shrink-0 ${v2Watch ? "text-white/70" : "text-accent"}`} />
                      <span className="truncate text-xs font-black">{title}</span>
                    </div>
                  )}
                </div>
              ) : null}

              {!v2Watch ? (
              <button 
                type="button"
                aria-label="Close player"
                onClick={closePlayer}
                className="pointer-events-auto absolute left-3 top-[calc(0.75rem+env(safe-area-inset-top))] z-40 flex h-10 min-w-10 items-center justify-center gap-1 rounded-full border border-white/10 bg-black/55 px-3 backdrop-blur-md transition-transform active:scale-90 sm:left-6 sm:top-6"
                  >
                    <X size={18} className="text-white" />
                  </button>
              ) : null}
              </WatchVideoStage>

              {v2Watch ? (
                <>
                <WatchToolbarV2
                  title={title}
                  subtitle={isFixtureWatch ? undefined : league || sport}
                  feedCount={eventStreams.length}
                  statusLabel={
                    matchContext.status === "upcoming" && matchContext.kickoffLabel
                      ? matchContext.kickoffLabel
                      : matchContext.statusLabel
                  }
                  statusTone={statusTone}
                  streamHealthLine={streamHealthLine}
                  hideTitle={isFixtureWatch || isEventWatch}
                  showReminder={Boolean(reminderEntry)}
                  reminded={reminded}
                  onToggleReminder={() => {
                    const active = toggleReminder();
                    if (active) updateUserPreferences({ matchReminders: true });
                  }}
                  showDiagnostics={showDiagnostics}
                  onToggleDiagnostics={() => setShowDiagnostics((value) => !value)}
                  showPiP={v2Watch && !useEventEmbed && Boolean(streamURL)}
                  onTogglePiP={!useEventEmbed && streamURL ? handleTogglePiP : undefined}
                  onBack={closePlayer}
                  playbackHint="Tip: Tap the speaker icon on the video toolbar to adjust sound."
                />
                {isFixtureWatch ? (
                  <WatchFixtureHeader
                    match={matchRecord}
                    context={matchContext}
                    now={currentTime}
                  />
                ) : isEventWatch ? (
                  <WatchEventHeader
                    title={title}
                    sport={sport}
                    league={league}
                    match={matchRecord}
                    context={matchContext}
                  />
                ) : null}
                </>
              ) : (
              <div className={`shrink-0 border-b border-white/5 px-3 py-2 sm:px-md lg:py-2 ${v2Watch ? "bg-[#111113]" : "bg-surface"}`}>
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="hidden text-[10px] font-bold uppercase text-text-tertiary sm:block">Now Playing</p>
                  <div className="mt-1 flex min-w-0 items-center gap-2">
                    {useEventEmbed ? <Tv size={15} className={`shrink-0 ${v2Watch ? "text-white/70" : "text-accent"}`} /> : <Activity size={15} className={`shrink-0 ${v2Watch ? "text-white/70" : "text-accent"}`} />}
                    <p className="truncate text-sm font-bold text-text-primary">{sourceSummary}</p>
                  </div>
                </div>

                <div className="flex shrink-0 items-center gap-1 sm:gap-2">
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
                        ? "rounded-full bg-accent px-2.5 py-2 text-[11px] font-bold text-white sm:px-3"
                        : "rounded-full border border-white/10 bg-white/5 px-2.5 py-2 text-[11px] font-bold text-text-secondary sm:px-3"}
                    >
                      <span className="inline-flex items-center gap-2">
                        {reminded ? <BellOff size={13} /> : <Bell size={13} />}
                        <span className="max-[430px]:sr-only">{reminded ? "Reminder saved" : "Remind me"}</span>
                      </span>
                    </button>
                  )}
                  {useP2PPlayback && (
                    <button
                      type="button"
                      aria-pressed={showTelemetry}
                      onClick={() => setShowTelemetry(!showTelemetry)}
                      className={showTelemetry
                        ? "rounded-full bg-accent px-2.5 py-2 text-[11px] font-bold text-white sm:px-3"
                        : "rounded-full border border-white/10 bg-white/5 px-2.5 py-2 text-[11px] font-bold text-text-secondary sm:px-3"}
                    >
                      <span className="max-[430px]:sr-only">{showTelemetry ? "Hide Pulse" : "Pulse"}</span>
                      <Activity size={13} className="hidden max-[430px]:block" />
                    </button>
                  )}
                  <button
                    type="button"
                    aria-pressed={showDiagnostics}
                    onClick={() => setShowDiagnostics((value) => !value)}
                    className={showDiagnostics
                      ? "rounded-full bg-accent px-2.5 py-2 text-[11px] font-bold text-white sm:px-3"
                      : "rounded-full border border-white/10 bg-white/5 px-2.5 py-2 text-[11px] font-bold text-text-secondary sm:px-3"}
                  >
                    <span className="inline-flex items-center gap-2">
                      <Info size={13} />
                      <span className="max-[430px]:sr-only">Status</span>
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={closePlayer}
                    className={
                      v2Watch
                        ? "rounded-full bg-white px-2.5 py-2 text-[11px] font-semibold text-zinc-950 sm:px-3"
                        : "rounded-full border border-white/10 bg-white/5 px-2.5 py-2 text-[11px] font-bold text-text-primary sm:px-3"
                    }
                  >
                    <span className="max-[430px]:hidden">Home</span>
                    <span className="hidden max-[430px]:inline">{v2Watch ? "Home" : "Board"}</span>
                  </button>
                </div>
              </div>
              </div>
              )}

            {showDiagnostics ? (
              <StreamDiagnosticsPanel
                mode={useEventEmbed ? "Event" : "P2P"}
                access={watchAccess.allowed ? "Allowed" : "Blocked"}
                lookup={useEventEmbed ? (isEventStreamLoading ? "Checking" : eventStreamError ? "Failed" : "Ready") : useDirectP2PRoute ? (streamURL ? "Direct" : "Idle") : brokerPlaybackState}
                feeds={useEventEmbed ? eventStreams.length : useDirectP2PRoute ? (streamURL ? 1 : 0) : brokerSessionId ? 1 : 0}
                selected={useEventEmbed
                  ? selectedEventStream
                    ? `${FOTTY_LIVE_LABEL} #${selectedEventStream.streamNo}`
                    : "None"
                  : useDirectP2PRoute ? p2pCid || "None" : brokerSessionId || "None"}
                frameState={useEventEmbed ? eventFrameLoaded ? "Loaded" : eventFrameTimedOut ? "Timed out" : eventEmbedURL ? "Waiting" : "No iframe" : undefined}
                lastCheckedAt={streamsCheckedAt || p2pHealth?.checkedAt}
                error={playbackError || eventStreamError || telemetry.error}
              />
            ) : null}

            {autoFailoverMessage ? (
              <div className={`border-b border-white/5 px-md py-2 text-[11px] font-medium ${v2Watch ? "bg-[var(--v2-surface)] text-text-tertiary" : "bg-surface font-bold text-text-secondary"}`}>
                {autoFailoverMessage}
              </div>
            ) : null}

            {v2Watch ? (
              <MatchStreamHubV2
                mode={useEventEmbed ? "event" : "p2p"}
                matchId={matchId}
                eventStreams={eventStreams}
                selectedEventIndex={selectedEventStreamIndex}
                isLoading={isEventStreamLoading}
                loadError={eventStreamError}
                playbackError={playbackError}
                lastCheckedAt={streamsCheckedAt}
                failedEventSourceIds={failedEventSourceIds}
                onSelectEventStream={handleSelectFeed}
                onTryNextEventStream={
                  useEventEmbed && eventStreams.length > 1
                    ? () => tryNextDirectEventFeed("Trying another direct stream.")
                    : undefined
                }
                onBrowseLive={closePlayer}
                onRefreshEventStreams={refreshEventStreams}
              />
            ) : (
            <MatchStreamHub
              v2={v2Watch}
              watchReturnTo={homeReturnTo}
              mode={useEventEmbed ? "event" : "p2p"}
              matchId={matchId}
              matchContext={matchContext}
              eventStreams={eventStreams}
              selectedEventIndex={selectedEventStreamIndex}
              isLoading={isEventStreamLoading}
              loadError={eventStreamError}
              telemetry={telemetry}
              isP2PWarming={isBrokerWarming}
              isP2PActive={isP2PActive}
              cid={p2pCid || cidValue || undefined}
              p2pHealth={p2pHealth}
              lastCheckedAt={streamsCheckedAt}
              playbackError={playbackError}
              onSelectEventStream={(index) => {
                const stream = eventStreams[index];
                trackEvent("change_source_click", {
                  title,
                  streamNo: stream?.streamNo,
                  playbackMode: "event",
                });
                setPlaybackError(null);
                setAutoFailoverMessage(null);
                selectEventStream(index);
              }}
              failedEventSourceIds={failedEventSourceIds}
              onTryNextEventStream={
                useEventEmbed && eventStreams.length > 1
                  ? () => tryNextDirectEventFeed("Trying another direct stream.")
                  : undefined
              }
              onBrowseLive={closePlayer}
              onRefreshEventStreams={refreshEventStreams}
              onRetryPlayback={useP2PPlayback ? handleRetryPlayback : undefined}
            />
            )}

              {!v2Watch ? (
              <WatchDetailsPanel
                className="min-h-0 flex-1 overflow-visible pb-[calc(1rem+env(safe-area-inset-bottom,0px))] lg:hidden"
                isEventPlayback={useEventEmbed}
                showTelemetry={showTelemetry}
                telemetry={telemetry}
                isP2PActive={isP2PActive}
                p2pFeedConnected={p2pFeedLive}
                title={title}
                league={league}
                sport={sport}
              />
              ) : null}
            </div>

            {v2Watch && useEventEmbed ? (
              <div className="hidden min-h-0 lg:flex">
                <WatchAsideV2
                  title={title}
                  subtitle={league || sport}
                  sources={eventGuide?.all}
                  selectedIndex={selectedEventStreamIndex}
                  onSelectFeed={handleSelectFeed}
                  relatedMatches={sameLeagueMatches}
                  returnTo={homeReturnTo}
                />
              </div>
            ) : (
            <aside className={`hidden min-h-0 flex-col overflow-hidden border-white/5 lg:flex lg:border-l ${v2Watch ? "bg-[var(--v2-background)]" : "bg-background"}`}>
              <div className="shrink-0 border-b border-white/5 px-md py-2">
                <SponsoredSlot placement="watch" compact />
              </div>
              {useP2PPlayback && showTelemetry && (
                <div className="shrink-0 border-b border-white/5 bg-surface-elevated/40 px-md py-2">
                  <TelemetryGrid telemetry={telemetry} isP2PActive={isP2PActive} />
                </div>
              )}
              <div className="min-h-0 flex-1 overflow-hidden">
                <MatchTimeline
                  title={title}
                  league={league}
                  sport={sport}
                  isP2PPlayback={useP2PPlayback}
                  telemetry={telemetry}
                  p2pFeedConnected={p2pFeedLive}
                  compact
                  v2={v2Watch}
                />
              </div>
            </aside>
            )}
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
