"use client";

import { useEffect, useRef } from "react";
import {
  shouldArmEmbedLoadTimeout,
  shouldArmEmbedStartTimeout,
} from "@/lib/watch-event-recovery";

type UseEventPlaybackRecoveryArgs = {
  useEventEmbed: boolean;
  canObservePlayback: boolean;
  eventEmbedURL: string | null | undefined;
  eventFrameLoaded: boolean;
  eventStreamError: string | null | undefined;
  feedCount: number;
  embedPlaybackStarted: boolean;
  embedPlaybackStartedRef: { current: boolean };
  selectedEventStreamIndex: number;
  loadTimeoutMs: number;
  startTimeoutMs: number;
  onLoadTimeout: () => void;
  onStartTimeout: () => void;
  setEventFrameTimedOut: (value: boolean) => void;
};

/**
 * Arms embed load/start failover timers. Failover selection stays in the page
 * so stream-guide ranking and UI messaging stay colocated.
 */
export function useEventPlaybackRecovery({
  useEventEmbed,
  canObservePlayback,
  eventEmbedURL,
  eventFrameLoaded,
  eventStreamError,
  feedCount,
  embedPlaybackStarted,
  embedPlaybackStartedRef,
  selectedEventStreamIndex,
  loadTimeoutMs,
  startTimeoutMs,
  onLoadTimeout,
  onStartTimeout,
  setEventFrameTimedOut,
}: UseEventPlaybackRecoveryArgs) {
  const onLoadTimeoutRef = useRef(onLoadTimeout);
  const onStartTimeoutRef = useRef(onStartTimeout);
  const setTimedOutRef = useRef(setEventFrameTimedOut);

  useEffect(() => {
    onLoadTimeoutRef.current = onLoadTimeout;
    onStartTimeoutRef.current = onStartTimeout;
    setTimedOutRef.current = setEventFrameTimedOut;
  }, [onLoadTimeout, onStartTimeout, setEventFrameTimedOut]);

  useEffect(() => {
    if (
      !shouldArmEmbedLoadTimeout({
        useEventEmbed,
        hasEmbedURL: Boolean(eventEmbedURL),
        frameLoaded: eventFrameLoaded,
        streamError: eventStreamError,
        feedCount,
      })
    ) {
      return;
    }

    const timer = window.setTimeout(() => {
      setTimedOutRef.current(true);
      onLoadTimeoutRef.current();
    }, loadTimeoutMs);

    return () => window.clearTimeout(timer);
  }, [
    eventEmbedURL,
    eventFrameLoaded,
    eventStreamError,
    feedCount,
    loadTimeoutMs,
    selectedEventStreamIndex,
    useEventEmbed,
  ]);

  useEffect(() => {
    if (
      !shouldArmEmbedStartTimeout({
        useEventEmbed,
        canObservePlayback,
        frameLoaded: eventFrameLoaded,
        feedCount,
        playbackStarted: embedPlaybackStarted,
      })
    ) {
      return;
    }

    const timer = window.setTimeout(() => {
      if (embedPlaybackStartedRef.current) return;
      onStartTimeoutRef.current();
    }, startTimeoutMs);

    return () => window.clearTimeout(timer);
  }, [
    embedPlaybackStarted,
    embedPlaybackStartedRef,
    canObservePlayback,
    eventFrameLoaded,
    feedCount,
    selectedEventStreamIndex,
    startTimeoutMs,
    useEventEmbed,
  ]);
}
