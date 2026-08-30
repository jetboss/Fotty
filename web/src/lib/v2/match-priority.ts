import type { ScrapedMatch } from "@/lib/api";
import { canOpenBroadcast, hasStreameXPlayback, isMatchLiveNow } from "@/lib/live";

function kickoffTime(match: ScrapedMatch) {
  return match.startsAt ? new Date(match.startsAt).getTime() : Number.MAX_SAFE_INTEGER;
}

export function isMatchLive(match: ScrapedMatch) {
  if (match.status === "Live") {
    return isMatchLiveNow(match) || !match.startsAt;
  }
  return isMatchLiveNow(match);
}

/** Lower sorts first: live+watchable → live → watchable → rest. */
export function fixtureDisplayPriority(match: ScrapedMatch) {
  const live = isMatchLive(match);
  const watchable = canOpenBroadcast(match) || hasStreameXPlayback(match);
  if (live && watchable) return 0;
  if (live) return 1;
  if (watchable) return 2;
  return 3;
}

export function sortFixturesForDisplay(matches: ScrapedMatch[]) {
  return [...matches].sort((a, b) => {
    const priority = fixtureDisplayPriority(a) - fixtureDisplayPriority(b);
    if (priority !== 0) return priority;
    return kickoffTime(a) - kickoffTime(b);
  });
}
