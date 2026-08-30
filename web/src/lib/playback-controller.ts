export type PlaybackMode = "event" | "p2p";

export type PlaybackPhase =
  | "idle"
  | "starting"
  | "frame-ready"
  | "playing"
  | "recovering"
  | "failed";

export type PlaybackFaultKind =
  | "auth"
  | "entitlement"
  | "startup-timeout"
  | "network"
  | "media"
  | "stalled"
  | "source"
  | "unknown";

export type PlaybackRecoveryAction =
  | "none"
  | "switch-source"
  | "recycle-session"
  | "fail";

export type PlaybackFault = {
  kind: PlaybackFaultKind;
  message: string;
  reason?: string;
};

export type PlaybackControllerState = {
  attemptId: number;
  sourceKey: string;
  mode: PlaybackMode | null;
  phase: PlaybackPhase;
  recoveryCount: number;
  maxRecoveries: number;
  decodedProgressAt: number | null;
  lastFault: PlaybackFault | null;
  pendingAction: PlaybackRecoveryAction;
};

export type PlaybackControllerEvent =
  | {
      type: "start-attempt";
      sourceKey: string;
      mode: PlaybackMode;
      maxRecoveries: number;
    }
  | { type: "frame-ready"; attemptId: number }
  | { type: "decoded-progress"; attemptId: number; at: number }
  | { type: "fault"; attemptId: number; fault: PlaybackFault }
  | { type: "recovery-committed"; attemptId: number }
  | { type: "advance-attempt"; attemptId: number }
  | { type: "reset" };

export const initialPlaybackControllerState: PlaybackControllerState = {
  attemptId: 0,
  sourceKey: "",
  mode: null,
  phase: "idle",
  recoveryCount: 0,
  maxRecoveries: 0,
  decodedProgressAt: null,
  lastFault: null,
  pendingAction: "none",
};

function isTerminalFault(kind: PlaybackFaultKind): boolean {
  return kind === "auth" || kind === "entitlement";
}

export function recoveryActionFor(
  state: PlaybackControllerState,
  fault: PlaybackFault
): PlaybackRecoveryAction {
  if (!state.mode || isTerminalFault(fault.kind)) return "fail";
  if (state.recoveryCount >= state.maxRecoveries) return "fail";
  return state.mode === "event" ? "switch-source" : "recycle-session";
}

/**
 * One attempt owns one source generation. Facts from an older attempt are
 * ignored so a late iframe/media event cannot revive or fail the new source.
 */
export function playbackControllerReducer(
  state: PlaybackControllerState,
  event: PlaybackControllerEvent
): PlaybackControllerState {
  if (event.type === "reset") return initialPlaybackControllerState;

  if (event.type === "start-attempt") {
    return {
      attemptId: state.attemptId + 1,
      sourceKey: event.sourceKey,
      mode: event.mode,
      phase: "starting",
      recoveryCount: 0,
      maxRecoveries: Math.max(0, event.maxRecoveries),
      decodedProgressAt: null,
      lastFault: null,
      pendingAction: "none",
    };
  }

  if (event.attemptId !== state.attemptId) return state;

  switch (event.type) {
    case "frame-ready":
      if (state.phase === "playing" || state.phase === "failed") return state;
      return { ...state, phase: "frame-ready" };
    case "decoded-progress":
      return {
        ...state,
        phase: "playing",
        decodedProgressAt: event.at,
        lastFault: null,
        pendingAction: "none",
      };
    case "fault": {
      const pendingAction = recoveryActionFor(state, event.fault);
      return {
        ...state,
        phase: pendingAction === "fail" ? "failed" : "recovering",
        recoveryCount:
          pendingAction === "fail" ? state.recoveryCount : state.recoveryCount + 1,
        lastFault: event.fault,
        pendingAction,
      };
    }
    case "recovery-committed":
      if (state.phase !== "recovering") return state;
      return {
        ...state,
        attemptId: state.attemptId + 1,
        phase: "starting",
        decodedProgressAt: null,
        pendingAction: "none",
      };
    case "advance-attempt":
      return {
        ...state,
        attemptId: state.attemptId + 1,
        phase: "starting",
        decodedProgressAt: null,
        lastFault: null,
        pendingAction: "none",
      };
  }
}

export function classifyPlaybackFault(
  message: string,
  reason = ""
): PlaybackFault {
  const normalized = `${reason} ${message}`.toLowerCase();
  let kind: PlaybackFaultKind = "unknown";

  if (/(sign[- ]?in|session expired|invalid.*session|manifest_401|\bauth\b)/.test(normalized)) {
    kind = "auth";
  } else if (/(paid.*plan|live access|entitlement|manifest_403)/.test(normalized)) {
    kind = "entitlement";
  } else if (/(startup|start timeout|still buffering)/.test(normalized)) {
    kind = "startup-timeout";
  } else if (/(network|could not reach|timeout|fetch)/.test(normalized)) {
    kind = "network";
  } else if (/(media|decode|video element)/.test(normalized)) {
    kind = "media";
  } else if (/(stall|stopped|frozen|waiting)/.test(normalized)) {
    kind = "stalled";
  } else if (/(source|feed|manifest|stream)/.test(normalized)) {
    kind = "source";
  }

  return { kind, message, reason: reason || undefined };
}

export function isDecodedProgressSample(input: {
  previousTime: number;
  currentTime: number;
  readyState: number;
  videoWidth: number;
}): boolean {
  return (
    input.currentTime > input.previousTime + 0.2 &&
    input.readyState >= 2 &&
    input.videoWidth > 0
  );
}

export function shouldRecoverStalledPlayback(input: {
  hasStarted: boolean;
  isPlaying: boolean;
  hasError: boolean;
  stalledMs: number;
  playheadStallMs: number;
  hardStallMs: number;
  bufferAhead: number;
  lowBufferSeconds: number;
  readyState: number;
}): boolean {
  if (!input.hasStarted || !input.isPlaying || input.hasError) return false;
  if (input.stalledMs < input.playheadStallMs) return false;
  const lowBuffer = input.bufferAhead < input.lowBufferSeconds || input.readyState < 3;
  return lowBuffer || input.stalledMs >= input.hardStallMs;
}
