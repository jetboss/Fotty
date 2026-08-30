import type { ScrapedMatch } from "@/lib/api";

function feedMatchKey(match: ScrapedMatch) {
  return match.id || `${match.cid}:${match.title}`;
}

/** Cheap fingerprint so poll refreshes skip React updates when nothing changed. */
export function matchFeedSignature(matches: ScrapedMatch[]) {
  return matches
    .map((match) => {
      const key = feedMatchKey(match);
      const home = match.score?.home ?? "";
      const away = match.score?.away ?? "";
      const eventSource = match.eventSource
        ? `${match.eventSource.source}:${match.eventSource.id}`
        : "";
      return [
        key,
        match.status ?? "",
        match.startsAt ?? "",
        home,
        away,
        eventSource,
        match.playbackType ?? "",
        match.sourceCount ?? 0,
      ].join(":");
    })
    .join("|");
}

/**
 * A provider refresh can temporarily lose its event mapping while retaining the
 * fixture. Keep the last playable mapping for active fixtures instead of
 * turning visible cards into inert articles.
 */
export function mergeFreshMatchFeed(
  previous: ScrapedMatch[],
  fresh: ScrapedMatch[]
): ScrapedMatch[] {
  if (fresh.length === 0) return previous;

  const previousByKey = new Map(previous.map((match) => [feedMatchKey(match), match]));
  return fresh.map((match) => {
    if (match.eventSource || match.status === "Finished") return match;

    const prior = previousByKey.get(feedMatchKey(match));
    const source = prior?.eventSource;
    const appearsActive =
      match.status === "Live" ||
      match.status === "Starting Soon" ||
      (match.sourceCount ?? 0) > 0;
    if (!source || !appearsActive) return match;

    return {
      ...match,
      eventSource: source,
      playbackType: "event",
      coverage: match.coverage === "unavailable" ? prior.coverage || "direct" : match.coverage,
      network: match.network || prior.network,
      sourceCount: Math.max(match.sourceCount || 0, prior.sourceCount || 1),
      sourceIds: Array.from(
        new Set([...(match.sourceIds || []), ...(prior.sourceIds || []), source.id])
      ),
      alternateCount: Math.max(match.alternateCount || 0, prior.alternateCount || 1),
    };
  });
}
