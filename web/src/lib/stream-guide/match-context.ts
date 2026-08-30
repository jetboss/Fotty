import type { ScrapedMatch } from "@/lib/api";
import { formatKickoff } from "@/lib/live";

export type MatchBroadcastStatus = "live" | "upcoming" | "finished" | "unknown";

export interface WatchMatchContext {
  homeName: string;
  awayName: string;
  league?: string;
  sport?: string;
  status: MatchBroadcastStatus;
  statusLabel: string;
  kickoffLabel?: string;
  score?: { home: number; away: number };
  streamAvailability: "available" | "checking" | "unavailable";
  streamAvailabilityLabel: string;
}

const PREGAME_MS = 30 * 60 * 1000;

function broadcastWindowMs(sport?: string, title?: string) {
  const normalized = sport?.toLowerCase() || "";
  const titleLower = title?.toLowerCase() || "";
  if (normalized.includes("football") && !normalized.includes("american")) return 150 * 60 * 1000;
  if (normalized.includes("basketball") || normalized.includes("hockey") || normalized.includes("combat")) {
    return 180 * 60 * 1000;
  }
  if (normalized.includes("american football") || normalized.includes("baseball")) return 240 * 60 * 1000;
  if (normalized.includes("cricket")) return 10 * 60 * 60 * 1000;
  if (/cycling|tour de france|\buci\b/.test(titleLower)) return 8 * 60 * 60 * 1000;
  if (/wimbledon|tennis|golf|masters/.test(titleLower)) return 8 * 60 * 60 * 1000;
  return 4 * 60 * 60 * 1000;
}

export function deriveMatchBroadcastStatus(
  startsAt?: string,
  apiStatus?: string,
  sport?: string,
  title?: string
): { status: MatchBroadcastStatus; label: string } {
  const normalized = apiStatus?.trim().toLowerCase();
  if (normalized === "live" || normalized === "in play") {
    return { status: "live", label: "Live" };
  }
  if (normalized === "finished" || normalized === "ft" || normalized === "full time") {
    return { status: "finished", label: "Full time" };
  }
  if (normalized === "starting soon" || normalized === "scheduled") {
    return { status: "upcoming", label: "Starting soon" };
  }

  if (!startsAt) {
    return { status: "unknown", label: "Match" };
  }

  const kickoff = new Date(startsAt).getTime();
  if (!Number.isFinite(kickoff)) {
    return { status: "unknown", label: "Match" };
  }

  const now = Date.now();
  if (now < kickoff - PREGAME_MS) {
    return { status: "upcoming", label: "Upcoming" };
  }
  if (now <= kickoff + broadcastWindowMs(sport, title)) {
    return { status: "live", label: "Live" };
  }
  return { status: "finished", label: "Finished" };
}

export function buildWatchMatchContext(options: {
  title: string;
  league?: string;
  sport?: string;
  startsAt?: string;
  match?: ScrapedMatch | null;
  hasWorkingStream?: boolean;
  isCheckingStreams?: boolean;
}): WatchMatchContext {
  const titleParts = options.title.split(/\s+vs\.?\s+|\s+v\s+/i);
  const hasTeams = Boolean(options.match?.teams?.home?.name && options.match?.teams?.away?.name);
  const homeName = hasTeams
    ? options.match!.teams!.home.name
    : titleParts[0]?.trim() || options.title;
  const awayName = hasTeams
    ? options.match!.teams!.away.name
    : titleParts[1]?.trim() || "";
  const { status, label } = deriveMatchBroadcastStatus(
    options.startsAt || options.match?.startsAt,
    options.match?.status,
    options.sport || options.match?.sport,
    options.title
  );

  let streamAvailability: WatchMatchContext["streamAvailability"] = "available";
  let streamAvailabilityLabel = "Stream ready";

  if (options.isCheckingStreams) {
    streamAvailability = "checking";
    streamAvailabilityLabel = "Checking stream health";
  } else if (!options.hasWorkingStream) {
    streamAvailability = "unavailable";
    streamAvailabilityLabel = "No verified watch path yet";
  }

  return {
    homeName,
    awayName,
    league: options.league || options.match?.league || options.match?.subtitle,
    sport: options.sport || options.match?.sport,
    status,
    statusLabel: label,
    kickoffLabel: formatKickoff(options.startsAt || options.match?.startsAt) || undefined,
    score: options.match?.score,
    streamAvailability,
    streamAvailabilityLabel,
  };
}

export function findWatchMatch(matches: ScrapedMatch[], cid: string, matchId?: string, title?: string) {
  const normalizedTitle = normalizeMatchTitle(title);
  const byMatchId = matchId ? matches.find((match) => match.id === matchId) : undefined;
  if (byMatchId) return byMatchId;

  const byCid = matches.find((match) => match.cid === cid);
  if (byCid && (!normalizedTitle || matchLooksLikeTitle(byCid, normalizedTitle))) {
    return byCid;
  }

  if (normalizedTitle) {
    return matches.find((match) => matchLooksLikeTitle(match, normalizedTitle)) || null;
  }

  return byCid || null;
}

function normalizeMatchTitle(value?: string) {
  return (value || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function matchLooksLikeTitle(match: ScrapedMatch, normalizedTitle: string) {
  const matchText = normalizeMatchTitle(
    [
      match.displayTitle,
      match.title,
      match.teams?.home.name,
      match.teams?.away.name,
    ]
      .filter(Boolean)
      .join(" ")
  );

  if (!matchText || !normalizedTitle) return false;
  if (matchText.includes(normalizedTitle) || normalizedTitle.includes(matchText)) return true;

  const titleTokens = new Set(normalizedTitle.split(/\s+/).filter((token) => token.length >= 3));
  if (titleTokens.size === 0) return false;
  const matchTokens = new Set(matchText.split(/\s+/).filter((token) => token.length >= 3));
  const hits = Array.from(titleTokens).filter((token) => matchTokens.has(token)).length;
  return hits >= Math.min(2, titleTokens.size);
}
