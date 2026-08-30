import type { ScrapedMatch } from "./api";
import type { ReminderEntry } from "./storage";
import { buildWatchPageHref, isP2PContentId } from "./watch-session";
import { encodeWatchEventSources } from "./watch-event-sources";

export const FOTTY_TIME_ZONE = "America/Port_of_Spain";
export const FOTTY_LOCALE = "en-US";

export function getDisplayTimeZone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || FOTTY_TIME_ZONE;
  } catch {
    return FOTTY_TIME_ZONE;
  }
}

function dayKey(date: Date) {
  return new Intl.DateTimeFormat(FOTTY_LOCALE, {
    timeZone: getDisplayTimeZone(),
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export function matchKey(match: ScrapedMatch) {
  return match.id || `${match.cid}:${match.title}`;
}

export function formatKickoff(startsAt?: string) {
  if (!startsAt) return "";
  const date = new Date(startsAt);
  if (Number.isNaN(date.getTime())) return "";

  const now = new Date();
  const today = dayKey(now) === dayKey(date);
  const tomorrow = new Date(now);
  tomorrow.setDate(now.getDate() + 1);
  const isTomorrow = dayKey(tomorrow) === dayKey(date);
  const timeLabel = new Intl.DateTimeFormat(FOTTY_LOCALE, {
    timeZone: getDisplayTimeZone(),
    hour: "numeric",
    minute: "2-digit",
  }).format(date);

  if (today) return `Today ${timeLabel}`;
  if (isTomorrow) return `Tomorrow ${timeLabel}`;

  const dayLabel = new Intl.DateTimeFormat(FOTTY_LOCALE, {
    timeZone: getDisplayTimeZone(),
    month: "short",
    day: "numeric",
  }).format(date);

  return `${dayLabel} ${timeLabel}`;
}

export function canSetReminder(match: ScrapedMatch) {
  if (match.kind !== "fixture" || !match.startsAt) return false;
  const kickoff = new Date(match.startsAt).getTime();
  return Number.isFinite(kickoff) && kickoff > Date.now();
}

function broadcastWindowForSport(sport?: string, title?: string) {
  const normalized = sport?.toLowerCase() || "";
  const titleLower = title?.toLowerCase() || "";
  if (normalized.includes("football") && !normalized.includes("american")) return 150 * 60 * 1000;
  if (normalized.includes("basketball") || normalized.includes("hockey") || normalized.includes("combat")) return 180 * 60 * 1000;
  if (normalized.includes("american football") || normalized.includes("baseball")) return 240 * 60 * 1000;
  if (normalized.includes("cricket")) return 10 * 60 * 60 * 1000;
  if (/cycling|tour de france|\buci\b/.test(titleLower)) return 8 * 60 * 60 * 1000;
  if (/wimbledon|tennis|golf|masters/.test(titleLower)) return 8 * 60 * 60 * 1000;
  return 4 * 60 * 60 * 1000;
}

export function hasStreameXPlayback(match: Pick<ScrapedMatch, "eventSource" | "kind">) {
  const source = match.eventSource?.source?.trim();
  const id = match.eventSource?.id?.trim();
  return Boolean(source && id);
}

export function canOpenBroadcast(match: ScrapedMatch) {
  if (match.kind === "channel") return true;
  if (match.kind === "fixture" && !hasStreameXPlayback(match)) return false;
  if (match.kind !== "fixture") return hasStreameXPlayback(match);

  if (!match.startsAt) return match.status === "Live" || match.status === "Starting Soon";

  const kickoff = new Date(match.startsAt).getTime();
  if (!Number.isFinite(kickoff)) return false;

  const now = Date.now();
  const pregameWindowMs = 30 * 60 * 1000;
  const liveWindowMs = broadcastWindowForSport(match.sport || match.league, match.displayTitle || match.title);
  return now >= kickoff - pregameWindowMs && now <= kickoff + liveWindowMs;
}

export function isMatchLiveNow(match: ScrapedMatch, now = Date.now()) {
  if (match.kind !== "fixture" || match.status !== "Live") return false;
  if (!match.startsAt) return true;

  const kickoff = new Date(match.startsAt).getTime();
  if (!Number.isFinite(kickoff)) return true;

  const clockSkewGraceMs = 5 * 60 * 1000;
  const liveWindowMs = broadcastWindowForSport(match.sport || match.league, match.displayTitle || match.title);
  return now >= kickoff - clockSkewGraceMs && now <= kickoff + liveWindowMs;
}

export function buildWatchHref(match: ScrapedMatch, returnTo: string) {
  if (match.kind === "fixture" && !hasStreameXPlayback(match)) {
    return returnTo;
  }

  const watchId = hasStreameXPlayback(match)
    ? match.id || match.eventSource!.id
    : match.cid;
  const params = new URLSearchParams({
    title: match.displayTitle || match.title,
    league: match.subtitle || match.league || "",
    returnTo,
    matchId: match.id || match.cid,
  });

  if (match.sport) params.set("sport", match.sport);
  if (hasStreameXPlayback(match)) params.set("playback", "event");
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

export function buildReminderPayload(match: ScrapedMatch, returnTo: string): Omit<ReminderEntry, "createdAt"> | null {
  if (!canSetReminder(match) || !match.startsAt) return null;

  return {
    id: match.id || match.cid,
    cid: match.cid,
    title: match.displayTitle || match.title,
    league: match.league || match.subtitle,
    sport: match.sport,
    startsAt: match.startsAt,
    href: buildWatchHref(match, returnTo),
  };
}
