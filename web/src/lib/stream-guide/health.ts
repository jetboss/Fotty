import type { StreamHealthState } from "./types";

export interface StreamHealthPresentation {
  state: StreamHealthState;
  label: string;
  userMessage: string;
  action: string;
  score: number | null;
}

const HEALTH_COPY: Record<
  StreamHealthState,
  Pick<StreamHealthPresentation, "label" | "userMessage" | "action">
> = {
  excellent: {
    label: "Excellent",
    userMessage: "This stream is performing well.",
    action: "Watch now",
  },
  good: {
    label: "Good",
    userMessage: "This stream looks stable for live viewing.",
    action: "Watch now",
  },
  fair: {
    label: "Fair",
    userMessage: "This stream may buffer occasionally. A backup is available if needed.",
    action: "Watch or try backup",
  },
  unstable: {
    label: "Unstable",
    userMessage: "This stream may buffer. Try a backup if playback stalls.",
    action: "Watch or choose backup",
  },
  offline: {
    label: "Offline",
    userMessage: "This stream is unavailable right now.",
    action: "Try another stream",
  },
  checking: {
    label: "Checking",
    userMessage: "Fotty is checking this stream.",
    action: "Wait or refresh",
  },
  unknown: {
    label: "Unknown",
    userMessage: "Stream health is still being assessed.",
    action: "Try stream",
  },
};

export function healthStateFromScore(score: number | null | undefined): StreamHealthState {
  if (score === null || score === undefined) return "unknown";
  if (score >= 90) return "excellent";
  if (score >= 70) return "good";
  if (score >= 50) return "fair";
  if (score >= 25) return "unstable";
  return "offline";
}

export function presentStreamHealth(
  state: StreamHealthState,
  score: number | null = null,
  options?: { inferred?: boolean }
): StreamHealthPresentation {
  const base = HEALTH_COPY[state];
  const userMessage =
    options?.inferred && state !== "checking" && state !== "unknown"
      ? `${base.userMessage} Health is estimated from feed signals.`
      : base.userMessage;

  return {
    state,
    label: base.label,
    userMessage,
    action: base.action,
    score,
  };
}

export function healthScoreFromHeatTier(heatTier?: string): number | null {
  switch (heatTier?.toLowerCase()) {
    case "veryhigh":
      return 92;
    case "high":
      return 82;
    case "medium":
      return 68;
    case "low":
      return 45;
    case "legacy":
      return 60;
    default:
      return null;
  }
}
