"use client";

import { useCallback, useRef, useState } from "react";
import {
  initialPlaybackControllerState,
  playbackControllerReducer,
  type PlaybackControllerEvent,
  type PlaybackControllerState,
  type PlaybackFault,
  type PlaybackMode,
  type PlaybackRecoveryAction,
} from "@/lib/playback-controller";

export function usePlaybackController() {
  const stateRef = useRef<PlaybackControllerState>(initialPlaybackControllerState);
  const [state, setState] = useState<PlaybackControllerState>(
    initialPlaybackControllerState
  );

  const apply = useCallback((event: PlaybackControllerEvent) => {
    const next = playbackControllerReducer(stateRef.current, event);
    stateRef.current = next;
    setState(next);
    return next;
  }, []);

  const startAttempt = useCallback(
    (sourceKey: string, mode: PlaybackMode, maxRecoveries: number) =>
      apply({ type: "start-attempt", sourceKey, mode, maxRecoveries }),
    [apply]
  );

  const reportFrameReady = useCallback(
    (attemptId: number) => apply({ type: "frame-ready", attemptId }),
    [apply]
  );

  const reportDecodedProgress = useCallback(
    (attemptId: number) =>
      apply({ type: "decoded-progress", attemptId, at: Date.now() }),
    [apply]
  );

  const reportFault = useCallback(
    (attemptId: number, fault: PlaybackFault): PlaybackRecoveryAction =>
      apply({ type: "fault", attemptId, fault }).pendingAction,
    [apply]
  );

  const commitRecovery = useCallback(
    (attemptId: number) =>
      apply({ type: "recovery-committed", attemptId }).attemptId,
    [apply]
  );

  const advanceAttempt = useCallback(
    (attemptId: number) =>
      apply({ type: "advance-attempt", attemptId }).attemptId,
    [apply]
  );

  const reset = useCallback(() => apply({ type: "reset" }), [apply]);

  return {
    state,
    startAttempt,
    reportFrameReady,
    reportDecodedProgress,
    reportFault,
    commitRecovery,
    advanceAttempt,
    reset,
  };
}
