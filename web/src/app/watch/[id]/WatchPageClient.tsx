"use client";

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { FottyAPI, type ScrapedMatch } from "@/lib/api";
import { trackEvent } from "@/lib/analytics";
import {
  buildWatchMatchContext,
  findWatchMatch,
  logStreamDiagnostic,
  pickBackupAfterFailure,
  rankEventStreamGuide,
} from "@/lib/stream-guide";
import { buildDirectEmbedUrl } from "@/lib/stream-guide/embed-url";
import { formatStreamFeedLabel } from "@/lib/stream-guide/feed-label";
import { buildWatchHref, hasStreameXPlayback } from "@/lib/live";
import { fixtureTeamLabels, isEventFixture } from "@/lib/fixture-normalization";
import { resolveWatchRouteId } from "@/lib/watch-session";
import { decodeWatchEventSources, dedupeWatchEventSources, watchEventSourcesKey } from "@/lib/watch-event-sources";
import { resolveEventBackupIndex } from "@/lib/watch-event-recovery";
import { relatedWatchMatches } from "@/lib/v2/watch-related-matches";
import { v2AppPath, v2HomePath } from "@/lib/v2/preview";
import { recordRecentMatch, updateUserPreferences } from "@/lib/storage";
import { useReminderToggle } from "@/lib/user-experience";
import { useMatchFeedPoll } from "@/hooks/use-match-feed-poll";
import { useWatchKeyboard } from "@/hooks/use-watch-keyboard";
import { WatchVideoStage } from "@/components/watch/WatchPanels";
import {
  DirectEventPlayer,
  type DirectEventPlayerHandle,
} from "@/components/watch/WatchPlayers";
import { WatchToolbarV2 } from "@/components/watch/WatchToolbarV2";
import { WatchFixtureHeader } from "@/components/watch/WatchFixtureHeader";
import { WatchEventHeader } from "@/components/watch/WatchEventHeader";
import { WatchAsideV2 } from "@/components/watch/WatchAsideV2";
import { MatchStreamHubV2 } from "@/components/stream-guide/MatchStreamHubV2";
import { useEventStreams } from "./useEventStreams";
import { useEventPlaybackRecovery } from "./useEventPlaybackRecovery";

const EVENT_IFRAME_LOAD_TIMEOUT_MS = 20_000;
const EMBED_PLAYBACK_RECOVERY_MS = 20_000;

export default function WatchPageClient() {
  const { id } = useParams();
  const router = useRouter();
  const searchParams = useSearchParams();
  const routeId = resolveWatchRouteId(id, searchParams);
  const title = searchParams.get("title") || "Live Stream";
  const league = searchParams.get("league") || undefined;
  const sport = searchParams.get("sport") || league?.split(" · ")[0] || undefined;
  const eventSourceCode = searchParams.get("source") || undefined;
  const eventSourceId = searchParams.get("eventId") || undefined;
  const eventSourcesParam = searchParams.get("sources") || undefined;
  const startsAt = searchParams.get("startsAt") || undefined;
  const rawReturnTo = searchParams.get("returnTo") || v2HomePath();
  const returnTo = rawReturnTo.startsWith("/") ? rawReturnTo : v2HomePath();
  const matchId = searchParams.get("matchId") || routeId || title;
  const routeValue = routeId || "";

  const eventSources = useMemo(() => {
    const primary = eventSourceCode && eventSourceId
      ? [{ source: eventSourceCode, id: eventSourceId }]
      : [];
    return dedupeWatchEventSources([
      ...primary,
      ...decodeWatchEventSources(eventSourcesParam),
    ]);
  }, [eventSourceCode, eventSourceId, eventSourcesParam]);
  const eventStreamKey = eventSources.length > 0
    ? watchEventSourcesKey(eventSources)
    : undefined;
  const hasEventIdentity = eventSources.length > 0;

  const [matchRecord, setMatchRecord] = useState<ScrapedMatch | null>(null);
  const [boardMatches, setBoardMatches] = useState<ScrapedMatch[]>([]);
  const [matchLookupDone, setMatchLookupDone] = useState(false);
  const [currentTime, setCurrentTime] = useState(() => Date.now());
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const [autoFailoverMessage, setAutoFailoverMessage] = useState<string | null>(null);
  const [failedEventSourceIds, setFailedEventSourceIds] = useState<string[]>([]);
  const [playbackStartedURL, setPlaybackStartedURL] = useState<string | null>(null);
  const failedEventSourceIdsRef = useRef<Set<string>>(new Set());
  const embedPlaybackStartedRef = useRef(false);
  const currentEventEmbedURLRef = useRef<string | null>(null);
  const directEventPlayerRef = useRef<DirectEventPlayerHandle>(null);

  const clearPlaybackMessages = useCallback(() => {
    setPlaybackError(null);
    setAutoFailoverMessage(null);
    failedEventSourceIdsRef.current.clear();
    setFailedEventSourceIds([]);
  }, []);

  const {
    eventStreamState,
    eventFrameLoaded,
    setEventFrameLoaded,
    streamsCheckedAt,
    refreshEventStreams,
    selectEventStream,
  } = useEventStreams({
    enabled: hasEventIdentity,
    eventSources,
    eventStreamKey,
    matchId,
    onStreamsApplied: clearPlaybackMessages,
  });

  const eventStreams = useMemo(
    () => eventStreamState.key === eventStreamKey ? eventStreamState.streams || [] : [],
    [eventStreamKey, eventStreamState.key, eventStreamState.streams]
  );
  const selectedEventStreamIndex = Math.min(
    eventStreamState.selectedIndex || 0,
    Math.max(eventStreams.length - 1, 0)
  );
  const selectedEventStream = eventStreams[selectedEventStreamIndex];
  const eventStreamError = !hasEventIdentity
    ? "This retired watch route has no supported StreamEx or Score808 source. Return to Discover and choose a current match."
    : eventStreamState.key === eventStreamKey
      ? eventStreamState.error || null
      : null;
  const isEventStreamLoading = hasEventIdentity && eventStreamState.key !== eventStreamKey;
  const eventEmbedURL = useMemo(() => {
    if (selectedEventStream?.embedUrl?.trim()) return selectedEventStream.embedUrl;
    const source = selectedEventStream?.source || eventSourceCode;
    const sourceId = selectedEventStream?.id || eventSourceId;
    if (!source || !sourceId) return null;
    return buildDirectEmbedUrl(source, sourceId, selectedEventStream?.streamNo || 1);
  }, [eventSourceCode, eventSourceId, selectedEventStream]);
  const embedPlaybackStarted = playbackStartedURL === eventEmbedURL;

  useLayoutEffect(() => {
    currentEventEmbedURLRef.current = eventEmbedURL;
    embedPlaybackStartedRef.current = false;
  }, [eventEmbedURL]);

  const closePlayer = useCallback(() => {
    router.replace(returnTo);
  }, [returnTo, router]);

  useEffect(() => {
    let cancelled = false;
    FottyAPI.fetchMatchesFresh()
      .then((matches) => {
        if (cancelled) return;
        setBoardMatches(matches);
        const found = findWatchMatch(matches, routeValue, matchId, title);
        setMatchRecord(found);
        if (!hasEventIdentity && found && hasStreameXPlayback(found)) {
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
  }, [hasEventIdentity, matchId, returnTo, routeValue, router, title]);

  const refreshWatchBoard = useCallback(async () => {
    try {
      const matches = await FottyAPI.fetchMatchesFresh();
      setBoardMatches(matches);
      setMatchRecord(findWatchMatch(matches, routeValue, matchId, title));
      return true;
    } catch {
      return false;
    }
  }, [matchId, routeValue, title]);

  useEffect(() => {
    const interval = window.setInterval(() => setCurrentTime(Date.now()), 30_000);
    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!routeValue) return;
    recordRecentMatch({ cid: routeValue, title, league });
  }, [league, routeValue, title]);

  const eventGuide = useMemo(
    () => rankEventStreamGuide(eventStreams, matchId),
    [eventStreams, matchId]
  );

  const switchToEventBackup = useCallback((reason: string) => {
    const resolved = resolveEventBackupIndex(
      eventGuide,
      selectedEventStreamIndex,
      failedEventSourceIdsRef.current,
      pickBackupAfterFailure
    );
    const failed = eventGuide.all.find(
      (source) => source.eventIndex === selectedEventStreamIndex
    );
    if (failed?.id) {
      failedEventSourceIdsRef.current.add(failed.id);
      setFailedEventSourceIds(Array.from(failedEventSourceIdsRef.current));
    }
    if (!resolved) return false;

    const { nextIndex, backup } = resolved;
    setAutoFailoverMessage(`${reason} Switched to ${formatStreamFeedLabel(backup, nextIndex)}.`);
    setPlaybackError(null);
    selectEventStream(nextIndex);
    logStreamDiagnostic("fallback_used", {
      matchId,
      sourceId: backup.diagnosticsSafeId,
      playbackMode: "event",
      reason,
    });
    return true;
  }, [eventGuide, matchId, selectEventStream, selectedEventStreamIndex]);

  const tryNextDirectEventFeed = useCallback((reason: string) => {
    if (switchToEventBackup(reason)) return true;
    setPlaybackError(
      eventStreams.length > failedEventSourceIdsRef.current.size
        ? "Could not switch automatically. Choose another feed below."
        : "All available feeds were tried. Refresh the list or choose another match."
    );
    return false;
  }, [eventStreams.length, switchToEventBackup]);

  useEventPlaybackRecovery({
    useEventEmbed: hasEventIdentity,
    canObservePlayback: Boolean(eventEmbedURL?.startsWith("/")),
    eventEmbedURL,
    eventFrameLoaded,
    eventStreamError,
    feedCount: eventStreams.length,
    embedPlaybackStarted,
    embedPlaybackStartedRef,
    selectedEventStreamIndex,
    loadTimeoutMs: EVENT_IFRAME_LOAD_TIMEOUT_MS,
    startTimeoutMs: EMBED_PLAYBACK_RECOVERY_MS,
    onLoadTimeout: () => tryNextDirectEventFeed("This feed is slow to load — trying another stream."),
    onStartTimeout: () => tryNextDirectEventFeed("This feed had trouble starting — trying another stream."),
  });

  const reminderEntry = useMemo(() => {
    if (!startsAt) return null;
    const kickoff = new Date(startsAt).getTime();
    if (!Number.isFinite(kickoff) || kickoff <= currentTime) return null;
    return {
      id: matchId,
      cid: routeValue || matchId,
      title,
      league,
      sport,
      startsAt,
      href: typeof window !== "undefined"
        ? `${window.location.pathname}${window.location.search}`
        : `/watch/index`,
    };
  }, [currentTime, league, matchId, routeValue, sport, startsAt, title]);
  const { reminded, toggleReminder } = useReminderToggle(reminderEntry);

  const matchContext = buildWatchMatchContext({
    title,
    league,
    sport,
    startsAt,
    match: matchRecord,
    hasWorkingStream: Boolean(eventEmbedURL && !eventStreamError),
    isCheckingStreams: isEventStreamLoading || (!hasEventIdentity && !matchLookupDone),
  });
  const isEventWatch = hasEventIdentity || Boolean(matchRecord && isEventFixture(matchRecord));
  const isFixtureWatch = Boolean(
    matchRecord && !isEventWatch && !fixtureTeamLabels(matchRecord).isUpdating
  );
  const statusTone = matchContext.status === "live"
    ? "live"
    : matchContext.status === "upcoming"
      ? "upcoming"
      : matchContext.status === "finished"
        ? "finished"
        : "neutral";
  const streamHealthLine = eventGuide.recommended
    ? formatStreamFeedLabel(
        eventGuide.recommended,
        Math.max(eventGuide.all.findIndex((source) => source.id === eventGuide.recommended?.id), 0)
      )
    : undefined;
  const sameLeagueMatches = useMemo(
    () => relatedWatchMatches(boardMatches, matchRecord, { matchId, cid: routeValue, league }),
    [boardMatches, league, matchId, matchRecord, routeValue]
  );

  useMatchFeedPoll(refreshWatchBoard, 45_000, matchContext.status === "live");

  const handleSelectFeed = useCallback((index: number) => {
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
    setPlaybackStartedURL(null);
    selectEventStream(index);
  }, [eventStreams, selectEventStream, title]);

  useWatchKeyboard({
    enabled: true,
    feedCount: eventStreams.length,
    onSelectFeed: eventStreams.length > 1 ? handleSelectFeed : undefined,
    onBack: closePlayer,
  });

  return (
    <main className="min-h-[100svh] bg-[var(--v2-background)] text-white">
      <div className="lg:grid lg:h-[100dvh] lg:grid-cols-[minmax(0,1fr)_minmax(260px,320px)] lg:overflow-hidden">
        <div className="flex min-h-0 flex-col lg:overflow-y-auto">
          <WatchVideoStage v2>
            <DirectEventPlayer
              ref={directEventPlayerRef}
              title={title}
              embedURL={eventEmbedURL}
              eventSource={selectedEventStream ? {
                source: selectedEventStream.source,
                id: selectedEventStream.id,
                streamNo: selectedEventStream.streamNo,
              } : undefined}
              streamKey={selectedEventStream
                ? `${selectedEventStream.provider || "event"}:${selectedEventStream.source}:${selectedEventStream.id}:${selectedEventStream.streamNo}`
                : undefined}
              isLoading={isEventStreamLoading || (!hasEventIdentity && !matchLookupDone)}
              error={eventStreamError}
              returnTo={returnTo}
              onFrameLoad={(loadedURL) => {
                if (loadedURL !== currentEventEmbedURLRef.current) return;
                setEventFrameLoaded(true);
                setAutoFailoverMessage(null);
              }}
              onFrameError={(failedURL) => {
                if (failedURL === currentEventEmbedURLRef.current) {
                  tryNextDirectEventFeed("This feed had trouble loading — trying another stream.");
                }
              }}
              onPlaybackStarted={() => {
                embedPlaybackStartedRef.current = true;
                setPlaybackStartedURL(eventEmbedURL);
              }}
              onPlaybackPulse={() => {
                embedPlaybackStartedRef.current = true;
                setPlaybackStartedURL(eventEmbedURL);
              }}
              onPlaybackStalled={(failedURL) => {
                if (failedURL === currentEventEmbedURLRef.current) {
                  tryNextDirectEventFeed("This feed stopped — trying another stream.");
                }
              }}
              onRetry={refreshEventStreams}
            />
          </WatchVideoStage>

          <WatchToolbarV2
            title={title}
            subtitle={league || sport}
            feedCount={eventStreams.length}
            statusLabel={matchContext.status === "upcoming" && matchContext.kickoffLabel
              ? matchContext.kickoffLabel
              : matchContext.statusLabel}
            statusTone={statusTone}
            streamHealthLine={streamHealthLine}
            hideTitle={isFixtureWatch || isEventWatch}
            showReminder={Boolean(reminderEntry)}
            reminded={reminded}
            onToggleReminder={() => {
              if (toggleReminder()) updateUserPreferences({ matchReminders: true });
            }}
            onUnmute={() => directEventPlayerRef.current?.unmute()}
            onBack={closePlayer}
            playbackHint="Use the provider controls inside the video for sound and playback."
          />

          {isFixtureWatch ? (
            <WatchFixtureHeader match={matchRecord} context={matchContext} now={currentTime} />
          ) : isEventWatch ? (
            <WatchEventHeader
              title={title}
              sport={sport}
              league={league}
              match={matchRecord}
              context={matchContext}
            />
          ) : null}

          {autoFailoverMessage ? (
            <div className="border-b border-white/5 bg-[var(--v2-surface)] px-4 py-2 text-[11px] text-text-tertiary">
              {autoFailoverMessage}
            </div>
          ) : null}

          <MatchStreamHubV2
            matchId={matchId}
            eventStreams={eventStreams}
            selectedEventIndex={selectedEventStreamIndex}
            isLoading={isEventStreamLoading}
            loadError={eventStreamError}
            playbackError={playbackError}
            lastCheckedAt={streamsCheckedAt}
            failedEventSourceIds={failedEventSourceIds}
            onSelectEventStream={handleSelectFeed}
            onTryNextEventStream={eventStreams.length > 1
              ? () => tryNextDirectEventFeed("Trying another direct stream.")
              : undefined}
            onBrowseLive={closePlayer}
            onRefreshEventStreams={refreshEventStreams}
          />
        </div>

        <div className="hidden min-h-0 lg:flex">
          <WatchAsideV2
            title={title}
            subtitle={league || sport}
            sources={eventGuide.all}
            selectedIndex={selectedEventStreamIndex}
            onSelectFeed={handleSelectFeed}
            relatedMatches={sameLeagueMatches}
            returnTo={returnTo || v2AppPath("/")}
          />
        </div>
      </div>
    </main>
  );
}
