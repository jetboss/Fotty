import type { ScrapedMatch } from "@/lib/api";
import { buildWatchPageHref, isP2PContentId } from "@/lib/watch-session";
import { encodeWatchEventSources } from "@/lib/watch-event-sources";

/** Server-safe watch URL builder (no browser APIs). */
export function buildServerWatchHref(match: ScrapedMatch, returnTo: string) {
  if (match.kind === "fixture" && !match.eventSource?.source?.trim()) {
    return returnTo;
  }

  const watchId = match.eventSource?.source
    ? match.id || match.eventSource.id
    : match.cid;
  const params = new URLSearchParams({
    title: match.displayTitle || match.title,
    league: match.subtitle || match.league || "",
    returnTo,
    matchId: match.id || match.cid,
  });

  if (match.sport) params.set("sport", match.sport);
  if (match.eventSource) params.set("playback", "event");
  if (match.startsAt) params.set("startsAt", match.startsAt);

  if (match.kind === "channel" || isP2PContentId(watchId)) {
    params.set("cid", watchId);
    params.set("kind", "channel");
  } else {
    params.set("id", watchId);
  }

  if (match.eventSource) {
    params.set("source", match.eventSource.source);
    params.set("eventId", match.eventSource.id);

    const extraSources = (match.eventSources || []).filter(
      (entry) => entry.source && entry.id
    );
    if (extraSources.length > 1) {
      params.set("sources", encodeWatchEventSources(extraSources));
    }
  }

  return buildWatchPageHref(params);
}

export function serverMatchKey(match: ScrapedMatch) {
  return match.id || `${match.cid}:${match.title}`;
}
