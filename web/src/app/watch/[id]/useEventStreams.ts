"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { EventStreamVariant, FottyAPI } from "@/lib/api";
import { firstPlayableEventStream, synthesizeEventStreamVariants } from "@/lib/stream-guide/embed-url";
import { rankEventStreamGuide } from "@/lib/stream-guide";
import {
  dedupeWatchEventSources,
  watchEventSourcesKey,
  type WatchEventSource,
} from "@/lib/watch-event-sources";

interface EventStreamState {
  key?: string;
  streams?: EventStreamVariant[];
  selectedIndex?: number;
  error?: string;
}

function streamLookupErrorMessage(error: unknown, fallback: string) {
  return error instanceof Error && error.message.trim() ? error.message : fallback;
}

/**
 * Merge every provider link for a fixture into one feed list. Each source
 * (broadcaster/language) contributes its own numbered variants; when a source
 * returns no detail we still surface its primary embed so all links are
 * playable. Single-source matches keep their four-deep synthesized backups.
 */
function combinePlayableStreams(
  sources: WatchEventSource[],
  resultsBySourceKey: Map<string, EventStreamVariant[]>
): EventStreamVariant[] {
  const combined: EventStreamVariant[] = [];
  const seenEmbed = new Set<string>();
  const multiSource = sources.length > 1;

  const pushVariant = (variant: EventStreamVariant) => {
    const embedUrl = variant.embedUrl?.trim();
    if (!embedUrl || seenEmbed.has(embedUrl)) return;
    seenEmbed.add(embedUrl);
    combined.push(variant);
  };

  for (const { source, id } of sources) {
    const variants = (resultsBySourceKey.get(`${source}:${id}`) || []).filter((variant) =>
      variant.embedUrl?.trim()
    );
    const byStreamNo = new Map<number, EventStreamVariant>();
    for (const variant of variants) {
      const streamNo = variant.streamNo || 1;
      if (!byStreamNo.has(streamNo)) byStreamNo.set(streamNo, { ...variant, source, id });
    }
    Array.from(byStreamNo.values())
      .sort((a, b) => (a.streamNo || 1) - (b.streamNo || 1))
      .forEach(pushVariant);
  }

  // Only synthesize when every provider lookup failed. Never pad fake Fotty 2–4
  // stream numbers on top of real/legacy rows — those 404 as "NOT FOUND".
  if (combined.length === 0) {
    for (const { source, id } of sources) {
      synthesizeEventStreamVariants(source, id, multiSource ? 1 : 4).forEach(pushVariant);
    }
  }

  if (combined.length > 0) return combined;
  const primary = sources[0];
  return primary ? synthesizeEventStreamVariants(primary.source, primary.id, 4) : [];
}

function pickInitialStream(streams: EventStreamVariant[], matchId: string) {
  const guide = rankEventStreamGuide(streams, matchId);
  const recommendedIndex = guide.recommended?.eventIndex ?? 0;
  const recommended = streams[recommendedIndex];
  if (recommended?.embedUrl?.trim()) {
    return { streams, selectedIndex: recommendedIndex };
  }

  const fallbackIndex = streams.findIndex((stream) => stream.embedUrl?.trim());
  if (fallbackIndex >= 0) {
    return { streams, selectedIndex: fallbackIndex };
  }

  const first = firstPlayableEventStream(streams);
  if (!first) return null;

  const selectedIndex = streams.findIndex((stream) => stream === first);
  return { streams, selectedIndex: selectedIndex >= 0 ? selectedIndex : 0 };
}

async function fetchAllSourceStreams(sources: WatchEventSource[]) {
  const results = new Map<string, EventStreamVariant[]>();
  await Promise.all(
    sources.map(async ({ source, id }) => {
      try {
        const streams = await FottyAPI.fetchEventStreams(source, id);
        results.set(`${source}:${id}`, streams);
      } catch (error) {
        console.error("Direct event stream lookup failed", source, id, error);
        results.set(`${source}:${id}`, []);
      }
    })
  );
  return results;
}

/**
 * Owns direct-event stream lookup and selection for the watch page:
 * initial fetch with timeout, manual refresh, source selection, and iframe load tracking.
 * Accepts every provider link for the fixture so all broadcaster/language feeds are offered.
 */
export function useEventStreams({
  enabled,
  eventSources,
  eventStreamKey,
  matchId,
  onStreamsApplied,
}: {
  /** watch access granted and event params present */
  enabled: boolean;
  eventSources: WatchEventSource[];
  eventStreamKey?: string;
  matchId: string;
  /** Called when fresh streams are applied (parent clears playback/failover errors). */
  onStreamsApplied?: () => void;
}) {
  const [eventStreamState, setEventStreamState] = useState<EventStreamState>({});
  const [eventFrameLoaded, setEventFrameLoaded] = useState(false);
  const [eventFrameTimedOut, setEventFrameTimedOut] = useState(false);
  const [streamsCheckedAt, setStreamsCheckedAt] = useState<string | undefined>();

  const resolvedSources = useMemo(() => dedupeWatchEventSources(eventSources), [eventSources]);
  const sourcesKey = useMemo(() => watchEventSourcesKey(resolvedSources), [resolvedSources]);

  useEffect(() => {
    if (!enabled || resolvedSources.length === 0 || !eventStreamKey) return;

    let isMounted = true;
    const timeout = window.setTimeout(() => {
      if (!isMounted) return;
      setEventStreamState({ key: eventStreamKey, error: "Stream lookup is taking too long. Try another Fotty feed." });
    }, 9000);

    fetchAllSourceStreams(resolvedSources)
      .then((results) => {
        if (!isMounted) return;
        window.clearTimeout(timeout);
        const playable = combinePlayableStreams(resolvedSources, results);
        const picked = pickInitialStream(playable, matchId);
        if (picked) {
          setEventStreamState({ key: eventStreamKey, streams: picked.streams, selectedIndex: picked.selectedIndex });
          setStreamsCheckedAt(new Date().toISOString());
          setEventFrameLoaded(false);
          setEventFrameTimedOut(false);
          onStreamsApplied?.();
          return;
        }

        setEventStreamState({
          key: eventStreamKey,
          error: "No direct stream is ready for this match. Try another Fotty feed.",
        });
      })
      .catch((error: unknown) => {
        if (!isMounted) return;
        console.error("Direct event stream lookup failed", error);
        window.clearTimeout(timeout);
        const playable = combinePlayableStreams(resolvedSources, new Map());
        const picked = pickInitialStream(playable, matchId);
        if (picked) {
          setEventStreamState({ key: eventStreamKey, streams: picked.streams, selectedIndex: picked.selectedIndex });
          setStreamsCheckedAt(new Date().toISOString());
          setEventFrameLoaded(false);
          setEventFrameTimedOut(false);
          onStreamsApplied?.();
          return;
        }

        setEventStreamState({
          key: eventStreamKey,
          error: streamLookupErrorMessage(
            error,
            "Fotty could not verify this watch path. Try another Fotty feed."
          ),
        });
      });

    return () => {
      isMounted = false;
      window.clearTimeout(timeout);
    };
    // sourcesKey captures the identity of resolvedSources for the effect.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, sourcesKey, eventStreamKey, matchId, onStreamsApplied]);

  const refreshEventStreams = useCallback(() => {
    if (resolvedSources.length === 0 || !eventStreamKey) return;
    setEventStreamState({});
    fetchAllSourceStreams(resolvedSources)
      .then((results) => {
        const playable = combinePlayableStreams(resolvedSources, results);
        const picked = pickInitialStream(playable, matchId);
        if (!picked) {
          setEventStreamState({
            key: eventStreamKey,
            error: "Fotty could not verify this watch path. Try again shortly or choose another feed.",
          });
          return;
        }

        setEventStreamState({
          key: eventStreamKey,
          streams: picked.streams,
          selectedIndex: picked.selectedIndex,
        });
        setStreamsCheckedAt(new Date().toISOString());
        setEventFrameLoaded(false);
        setEventFrameTimedOut(false);
        onStreamsApplied?.();
      })
      .catch((error: unknown) => {
        console.error("Direct event stream refresh failed", error);
        const playable = combinePlayableStreams(resolvedSources, new Map());
        const picked = pickInitialStream(playable, matchId);
        if (picked) {
          setEventStreamState({
            key: eventStreamKey,
            streams: picked.streams,
            selectedIndex: picked.selectedIndex,
          });
          setStreamsCheckedAt(new Date().toISOString());
          setEventFrameLoaded(false);
          setEventFrameTimedOut(false);
          onStreamsApplied?.();
          return;
        }

        setEventStreamState({
          key: eventStreamKey,
          error: streamLookupErrorMessage(
            error,
            "Fotty could not verify this watch path. Try again shortly or choose another feed."
          ),
        });
      });
  }, [resolvedSources, eventStreamKey, matchId, onStreamsApplied]);

  const selectEventStream = useCallback((index: number) => {
    setEventFrameLoaded(false);
    setEventFrameTimedOut(false);
    setEventStreamState((current) => ({
      ...current,
      selectedIndex: index,
    }));
  }, []);

  return {
    eventStreamState,
    eventFrameLoaded,
    setEventFrameLoaded,
    eventFrameTimedOut,
    setEventFrameTimedOut,
    streamsCheckedAt,
    refreshEventStreams,
    selectEventStream,
  };
}
