import type { ScrapedMatch } from "@/lib/api";

/** User-facing stream labels (never show upstream provider names in the UI). */

export const FOTTY_LIVE_LABEL = "Fotty Live";

const UPSTREAM_NETWORK_PATTERN = /^(echo|delta|golf|alpha|admin|streamex|streamed)\s*stream?$/i;
const UPSTREAM_TOKEN_PATTERN = /^(echo|delta|golf|alpha|admin)$/i;

export function fottyFeedLabel(index: number) {
  return `Fotty ${index + 1}`;
}

export function fottyFeedCountLabel(count: number) {
  return count === 1 ? "1 feed" : `${count} feeds`;
}

export function fottyFeedCountText(count: number) {
  if (count <= 0) return FOTTY_LIVE_LABEL;
  return count === 1 ? "1 Fotty feed" : `${count} Fotty feeds`;
}

export function fottyFeedCountShort(count: number): string | null {
  if (count <= 0) return null;
  return count === 1 ? "1 Fotty feed" : `${count} Fotty feeds`;
}

export function sanitizeMatchNetwork(network?: string): string | undefined {
  if (!network?.trim()) return undefined;
  const value = network.trim();
  if (UPSTREAM_NETWORK_PATTERN.test(value)) return FOTTY_LIVE_LABEL;
  const withoutStream = value.replace(/\s+stream$/i, "").trim();
  if (UPSTREAM_TOKEN_PATTERN.test(withoutStream)) return FOTTY_LIVE_LABEL;
  return value;
}

export function isEventStyleMatch(match: Pick<ScrapedMatch, "playbackType" | "eventSource" | "kind">) {
  return match.playbackType === "event" || Boolean(match.eventSource);
}

export function matchNetworkForDisplay(
  match: Pick<ScrapedMatch, "network" | "playbackType" | "eventSource">
): string | undefined {
  if (isEventStyleMatch(match)) return FOTTY_LIVE_LABEL;
  return sanitizeMatchNetwork(match.network);
}

export function matchFeedSummary(match: Pick<ScrapedMatch, "playbackType" | "eventSource" | "sourceCount" | "alternateCount">) {
  const count = match.sourceCount || match.alternateCount || 0;
  if (isEventStyleMatch(match)) {
    return fottyFeedCountShort(count) || FOTTY_LIVE_LABEL;
  }
  if (count > 0) return `${count} P2P feed${count === 1 ? "" : "s"}`;
  return "P2P";
}

export function coverageLabelForDisplay(match: Pick<ScrapedMatch, "coverage" | "sourceCount">) {
  if (match.coverage === "direct") return FOTTY_LIVE_LABEL;
  if (match.coverage === "fallback") return "Ready";
  if (match.coverage === "channel") return "P2P";
  return match.sourceCount ? "Fotty feeds" : "Open";
}

export function subtitleSourceSegment(sourceCount: number) {
  if (sourceCount <= 0) return undefined;
  return fottyFeedCountShort(sourceCount) ?? undefined;
}
