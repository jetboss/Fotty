import type { ScrapedMatch } from "@/lib/api";
import { healthStateFromScore } from "./health";
import type { StreamHealthState } from "./types";

export function p2pHealthToScore(health?: ScrapedMatch["p2pHealth"]): number | null {
  if (!health) return null;
  if (!health.playable) {
    if (health.reason === "missing_cid") return 0;
    return 20;
  }

  const latency = health.latencyMs ?? 9999;
  if (latency < 1200) return 94;
  if (latency < 2500) return 84;
  if (latency < 5000) return 72;
  return 60;
}

export function p2pHealthToStatus(health?: ScrapedMatch["p2pHealth"]): StreamHealthState {
  const score = p2pHealthToScore(health);
  if (score === null) return "checking";
  return healthStateFromScore(score);
}
