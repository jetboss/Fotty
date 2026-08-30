import type { ScrapedMatch } from "@/lib/api";
import { canOpenBroadcast, matchKey } from "@/lib/live";
import { fixtureCardPhase } from "@/lib/v2/fixture-display";
import { fixtureDisplayPriority, isMatchLive, sortFixturesForDisplay } from "@/lib/v2/match-priority";
import { isKnockoutBracketTbd, isEventFixture } from "@/lib/fixture-normalization";
import { eventSportLabel } from "@/lib/v2/fixture-display";

function kickoffTime(match: ScrapedMatch) {
  return match.startsAt ? new Date(match.startsAt).getTime() : Number.MAX_SAFE_INTEGER;
}

function isFixture(match: ScrapedMatch) {
  return match.kind === "fixture";
}

function isFinishedFixture(match: ScrapedMatch) {
  return fixtureCardPhase(match) === "finished";
}

export function discoverSportLabel(match: ScrapedMatch) {
  if (isEventFixture(match)) return eventSportLabel(match);
  const sport = match.sport?.trim();
  if (sport && sport.toLowerCase() !== "other") return sport;
  const league = match.league?.trim();
  if (league && league.toLowerCase() !== "other") return league;
  return sport || "More sport";
}

/** Mix sports so one competition does not fill an entire rail. */
function diversifyRail(matches: ScrapedMatch[], limit = 12, maxPerSport = 4) {
  if (matches.length <= limit) return matches;

  const buckets = new Map<string, ScrapedMatch[]>();
  for (const match of matches) {
    const label = discoverSportLabel(match);
    const bucket = buckets.get(label) || [];
    bucket.push(match);
    buckets.set(label, bucket);
  }

  const sports = [...buckets.keys()].sort((left, right) => {
    const leftMatch = buckets.get(left)?.[0];
    const rightMatch = buckets.get(right)?.[0];
    if (!leftMatch || !rightMatch) return 0;
    return fixtureDisplayPriority(leftMatch) - fixtureDisplayPriority(rightMatch);
  });

  const result: ScrapedMatch[] = [];
  while (result.length < limit) {
    let added = false;
    for (const sport of sports) {
      const bucket = buckets.get(sport);
      if (!bucket?.length) continue;
      const taken = result.filter((match) => discoverSportLabel(match) === sport).length;
      if (taken >= maxPerSport) continue;
      const next = bucket.shift();
      if (!next) continue;
      result.push(next);
      added = true;
      if (result.length >= limit) break;
    }
    if (!added) break;
  }

  return result;
}

export function discoverLiveRail(matches: ScrapedMatch[]) {
  return diversifyRail(
    sortFixturesForDisplay(
      matches.filter(
        (match) => isFixture(match) && isMatchLive(match) && !isKnockoutBracketTbd(match)
      )
    ),
    12,
    4
  );
}

/** Kickoffs in the next few hours — not already live. */
export function discoverStartingSoonRail(
  matches: ScrapedMatch[],
  excludeKeys: Set<string> = new Set(),
  now = Date.now()
) {
  const soonEnd = now + 6 * 60 * 60 * 1000;

  const candidates = sortFixturesForDisplay(
    matches.filter((match) => {
      if (!isFixture(match) || isFinishedFixture(match) || isMatchLive(match)) return false;
      const key = matchKey(match);
      if (excludeKeys.has(key)) return false;

      const phase = fixtureCardPhase(match);
      if (phase === "starting" || phase === "watch") return true;

      const t = kickoffTime(match);
      return Number.isFinite(t) && t >= now && t <= soonEnd;
    })
  );

  return diversifyRail(candidates, 12, 3);
}

export function discoverUpcomingRail(
  matches: ScrapedMatch[],
  excludeKeys: Set<string> = new Set(),
  now = Date.now()
) {
  const end = now + 48 * 60 * 60 * 1000;

  const candidates = sortFixturesForDisplay(
    matches.filter((match) => {
      if (!isFixture(match) || isFinishedFixture(match) || isMatchLive(match)) return false;
      const key = matchKey(match);
      if (excludeKeys.has(key)) return false;
      const t = kickoffTime(match);
      return Number.isFinite(t) && t >= now && t <= end;
    })
  );

  return diversifyRail(candidates, 12, 3);
}

export function discoverChannelRail(matches: ScrapedMatch[]) {
  return matches
    .filter((match) => match.kind !== "fixture" && canOpenBroadcast(match))
    .sort((left, right) => {
      const leftLive = left.status === "Live" ? 0 : 1;
      const rightLive = right.status === "Live" ? 0 : 1;
      if (leftLive !== rightLive) return leftLive - rightLive;
      return (right.rank || 0) - (left.rank || 0);
    })
    .slice(0, 16);
}

export interface SportRail {
  sport: string;
  matches: ScrapedMatch[];
}

export function discoverSportRails(
  matches: ScrapedMatch[],
  excludeKeys: Set<string> = new Set(),
  maxSports = 6
) {
  const bySport = new Map<string, ScrapedMatch[]>();

  for (const match of matches) {
    if (!isFixture(match) || isFinishedFixture(match)) continue;
    const key = matchKey(match);
    if (excludeKeys.has(key)) continue;
    const label = discoverSportLabel(match);
    const bucket = bySport.get(label) || [];
    bucket.push(match);
    bySport.set(label, bucket);
  }

  return [...bySport.entries()]
    .map(([sport, sportMatches]) => ({
      sport,
      matches: sortFixturesForDisplay(sportMatches).slice(0, 8),
    }))
    .filter((rail) => rail.matches.length > 0)
    .sort((left, right) => {
      const priority =
        fixtureDisplayPriority(left.matches[0]) - fixtureDisplayPriority(right.matches[0]);
      if (priority !== 0) return priority;
      return right.matches.length - left.matches.length;
    })
    .slice(0, maxSports);
}

export interface ChannelSportRail {
  sport: string;
  channels: ScrapedMatch[];
}

export function discoverChannelSportRails(matches: ScrapedMatch[], maxSports = 4) {
  const bySport = new Map<string, ScrapedMatch[]>();

  for (const match of matches) {
    if (match.kind === "fixture" || !canOpenBroadcast(match)) continue;
    const label = match.sport?.trim() || "Live TV";
    const bucket = bySport.get(label) || [];
    bucket.push(match);
    bySport.set(label, bucket);
  }

  return [...bySport.entries()]
    .map(([sport, channels]) => ({
      sport,
      channels: channels
        .sort((left, right) => {
          const leftLive = left.status === "Live" ? 0 : 1;
          const rightLive = right.status === "Live" ? 0 : 1;
          if (leftLive !== rightLive) return leftLive - rightLive;
          return (right.rank || 0) - (left.rank || 0);
        })
        .slice(0, 10),
    }))
    .filter((rail) => rail.channels.length > 0)
    .sort((left, right) => {
      const leftLive = left.channels.some((channel) => channel.status === "Live") ? 0 : 1;
      const rightLive = right.channels.some((channel) => channel.status === "Live") ? 0 : 1;
      if (leftLive !== rightLive) return leftLive - rightLive;
      return right.channels.length - left.channels.length;
    })
    .slice(0, maxSports);
}
