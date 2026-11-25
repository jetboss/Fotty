import type { StreamHealthState } from "./types";

export function healthStateFromScore(score: number | null | undefined): StreamHealthState {
  if (score === null || score === undefined) return "unknown";
  if (score >= 90) return "excellent";
  if (score >= 70) return "good";
  if (score >= 50) return "fair";
  if (score >= 25) return "unstable";
  return "offline";
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
