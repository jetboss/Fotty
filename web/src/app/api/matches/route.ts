export const dynamic = "force-dynamic";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { NextResponse } from "next/server";
import type { ScrapedMatch, TeamReference } from "@/lib/api";

export const revalidate = 45;

/**
 * Same Nexus/StreamEx catalog the iOS app uses (StreamEx=delta, VipLeague=echo,
 * plus other web embeds). Homelab scraper / AceStream `admin` sources are retired.
 */
const STREAMED_IMAGE_BASE = "https://streamed.pk";
const IOS_SAFARI_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

const SCHEDULE_PROVIDERS = [
  {
    label: "StreamEx",
    url: "https://www.streamex.net/api/live/matches/all",
    referer: "https://www.streamex.net",
  },
  {
    label: "StreamEx Mirror",
    url: "https://streamex.sh/api/live/matches/all",
    referer: "https://streamex.sh",
  },
  {
    label: "Streamed Backup",
    url: "https://streamed.pk/api/matches/all",
    referer: "https://streamed.pk",
  },
];

interface ScheduleSource {
  source?: string;
  id?: string;
  cid?: string;
}

interface ScheduleMatchPayload {
  id?: string;
  title?: string;
  category?: string;
  date?: number | string;
  poster?: string;
  popular?: boolean;
  teams?: {
    home?: TeamReference;
    away?: TeamReference;
  };
  sources?: ScheduleSource[];
}

interface SchedulePayload {
  matches?: ScheduleMatchPayload[];
}

const CATEGORY_LABELS: Record<string, string> = {
  afl: "AFL",
  "american-football": "American Football",
  baseball: "Baseball",
  basketball: "Basketball",
  cricket: "Cricket",
  fight: "Combat Sports",
  football: "Football",
  hockey: "Hockey",
  "motor-sports": "Motorsport",
};

const KNOWN_ACRONYMS = new Set([
  "AFL",
  "BT",
  "ESPN",
  "F1",
  "FOX",
  "HD",
  "MLB",
  "NBA",
  "NFL",
  "NHL",
  "RTVS",
  "SKY",
  "TNT",
  "TVP",
  "UFC",
  "UK",
  "USA",
]);

/**
 * Prefer StreamEx `admin` (PPV/exclusives), `delta`, and `golf` on web.
 */
const SOURCE_PRIORITY = ["admin", "delta", "golf", "hotel", "echo", "india", "alpha"];

function isPlayableWebSource(source?: string) {
  return Boolean(source?.trim());
}

async function fetchJSON<T>(
  url: string,
  fallback: T,
  headers: Record<string, string>,
  timeoutMs = 4500
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      headers,
      signal: controller.signal,
      next: { revalidate: 60 },
    });

    if (!response.ok) return fallback;
    return (await response.json()) as T;
  } catch {
    return fallback;
  } finally {
    clearTimeout(timeout);
  }
}

function titleCase(value: string) {
  return value
    .split(/(\s+|-|\+)/)
    .map((part) => {
      const normalized = part.toUpperCase();
      if (KNOWN_ACRONYMS.has(normalized) || /^\d+$/.test(part) || /^\W+$/.test(part)) return part;
      return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase();
    })
    .join("");
}

function splitTeams(title: string): ScrapedMatch["teams"] | undefined {
  const parts = title.split(/\s+vs\.?\s+|\s+v\s+|\s+@\s+/i).map((part) => part.trim()).filter(Boolean);
  if (parts.length < 2) return undefined;

  return {
    home: { name: titleCase(parts[0]), badge: parts[0].slice(0, 2).toUpperCase() },
    away: { name: titleCase(parts[1]), badge: parts[1].slice(0, 2).toUpperCase() },
  };
}

function inferSport(rawTitle: string, categories: string[] = []) {
  const text = `${rawTitle} ${categories.join(" ")}`.toLowerCase();
  if (/(snooker|billiards|pool)/.test(text)) return "Snooker";
  if (/(football|soccer|premier|laliga|serie a|bundesliga|champions league|uefa|sky sports football)/.test(text)) return "Football";
  if (/(tennis|atp|wta)/.test(text)) return "Tennis";
  if (/(basket|nba|euroleague)/.test(text)) return "Basketball";
  if (/(f1|formula|motorsport|racing|moto gp|motogp)/.test(text)) return "Motorsport";
  if (/(ufc|mma|fight|boxing|wwe)/.test(text)) return "Combat Sports";
  if (/(hockey|nhl)/.test(text)) return "Hockey";
  if (/(golf)/.test(text)) return "Golf";
  return "Live Sports";
}

function normalizeCategory(raw?: string) {
  return raw?.trim().toLowerCase() || "football";
}

function categoryLabel(raw?: string) {
  const normalized = normalizeCategory(raw);
  return CATEGORY_LABELS[normalized] || titleCase(normalized.replace(/-/g, " "));
}

function eventSportLabel(event: ScheduleMatchPayload) {
  const category = normalizeCategory(event.category);
  const label = categoryLabel(category);

  if (category === "other" || label === "Other") {
    const inferred = inferSport(event.title || "", [category]);
    return inferred === "Live Sports" ? label : inferred;
  }

  return label;
}

function toKickoffMillis(value?: number | string) {
  if (value === undefined || value === null || value === "") return undefined;
  const numeric = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return undefined;
  const millis = numeric > 10_000_000_000 ? numeric : numeric * 1000;
  return millis >= 946_684_800_000 ? millis : undefined;
}

function kickoffLabel(millis?: number) {
  if (!millis) return undefined;

  const date = new Date(millis);
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(now.getDate() + 1);

  const sameDay = date.toDateString() === now.toDateString();
  const nextDay = date.toDateString() === tomorrow.toDateString();
  const time = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(date);

  if (sameDay) return `Today ${time}`;
  if (nextDay) return `Tomorrow ${time}`;
  return new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function statusForKickoff(millis: number | undefined, sourceCount: number) {
  const now = Date.now();
  if (!millis) return sourceCount > 0 ? "Live" : "Available";
  if (millis <= now && millis >= now - 4 * 60 * 60 * 1000) return "Live";
  if (millis < now - 4 * 60 * 60 * 1000) return "Finished";
  if (millis - now <= 30 * 60 * 1000) return "Starting Soon";
  return "Upcoming";
}

function normalizeText(value: string) {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function resolveImageURL(raw?: string) {
  if (!raw) return undefined;
  if (raw.startsWith("http://") || raw.startsWith("https://")) return raw;
  if (raw.startsWith("/api/")) return `${STREAMED_IMAGE_BASE}${raw}`;
  if (raw.length > 4) return `${STREAMED_IMAGE_BASE}/api/images/badge/${encodeURIComponent(raw)}.webp`;
  return raw;
}

function resolveTeams(event: ScheduleMatchPayload) {
  if (event.teams?.home?.name && event.teams.away?.name) {
    return {
      home: {
        ...event.teams.home,
        badge: resolveImageURL(event.teams.home.badge),
      },
      away: {
        ...event.teams.away,
        badge: resolveImageURL(event.teams.away.badge),
      },
    };
  }

  return splitTeams(event.title || "");
}

function scheduleSources(event: ScheduleMatchPayload) {
  const sources: Array<{ source?: string; id: string }> = [];

  for (const source of event.sources || []) {
    const id = (source.cid || source.id)?.trim();
    const code = source.source?.trim() || undefined;
    if (!id || !isPlayableWebSource(code)) continue;
    sources.push({ source: code, id });
  }

  return sources;
}

function sourceKey(source: { source?: string; id: string }) {
  return `${source.source || "source"}:${source.id}`;
}

function sourceRank(source?: string) {
  const index = SOURCE_PRIORITY.indexOf(source?.toLowerCase() || "");
  return index >= 0 ? index : 999;
}

function chooseEventSource(sources: Array<{ source?: string; id: string }>) {
  return [...sources].sort((a, b) => sourceRank(a.source) - sourceRank(b.source))[0];
}

/**
 * All playable provider links for a fixture, ordered by source priority and
 * deduped by source/id, so the watch page can offer every broadcaster/language
 * feed instead of collapsing to a single source.
 */
function orderEventSources(sources: Array<{ source?: string; id: string }>) {
  const seen = new Set<string>();
  const ordered: Array<{ source: string; id: string }> = [];
  for (const source of [...sources].sort((a, b) => sourceRank(a.source) - sourceRank(b.source))) {
    const code = source.source?.trim();
    const id = source.id?.trim();
    if (!code || !id) continue;
    const key = `${code}:${id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ordered.push({ source: code, id });
  }
  return ordered;
}

function scheduleKey(event: ScheduleMatchPayload) {
  const id = event.id?.trim();
  if (id && !id.startsWith("p2p-")) return id;
  return `${normalizeText(event.title || "match").replace(/\s+/g, "-")}-${toKickoffMillis(event.date) || 0}`;
}

function mergeScheduleMatches(lists: ScheduleMatchPayload[][]) {
  const deduped = new Map<string, ScheduleMatchPayload>();

  for (const event of lists.flat()) {
    if (!event.title?.trim()) continue;
    const key = scheduleKey(event);
    const existing = deduped.get(key);

    if (!existing) {
      deduped.set(key, event);
      continue;
    }

    const sources = new Map<string, ScheduleSource>();
    for (const source of [...scheduleSources(existing), ...scheduleSources(event)]) {
      sources.set(sourceKey(source), source);
    }

    deduped.set(key, {
      ...existing,
      id: existing.id || event.id,
      title: existing.title || event.title,
      category: existing.category || event.category,
      date: existing.date || event.date,
      poster: existing.poster || event.poster,
      popular: existing.popular === true || event.popular === true,
      teams: existing.teams || event.teams,
      sources: Array.from(sources.values()),
    });
  }

  return Array.from(deduped.values());
}

function normalizeSchedulePayload(payload: SchedulePayload | ScheduleMatchPayload[] | null) {
  if (Array.isArray(payload)) return payload;
  return payload?.matches || [];
}

async function loadLocalSchedule() {
  try {
    const raw = await readFile(path.join(process.cwd(), "data", "matches.json"), "utf8");
    return normalizeSchedulePayload(JSON.parse(raw) as SchedulePayload);
  } catch {
    // Local cache is a fallback, not a hard dependency.
    return [];
  }
}

async function fetchSchedule() {
  const headers = {
    Accept: "application/json",
    "User-Agent": IOS_SAFARI_USER_AGENT,
  };
  const providerRequests = SCHEDULE_PROVIDERS.map((provider) =>
    fetchJSON<SchedulePayload | ScheduleMatchPayload[] | null>(
      provider.url,
      null,
      {
        ...headers,
        Referer: provider.referer,
      },
      8000
    ).then(normalizeSchedulePayload)
  );
  const lists = await Promise.all([
    ...providerRequests,
    loadLocalSchedule(),
  ]);

  return mergeScheduleMatches(lists);
}

function isRelevantEvent(event: ScheduleMatchPayload) {
  const kickoffMillis = toKickoffMillis(event.date);
  if (!kickoffMillis) return Boolean(splitTeams(event.title || ""));
  return kickoffMillis >= Date.now() - 6 * 60 * 60 * 1000;
}

function fixtureRank(match: ScrapedMatch, kickoffMillis?: number, popular?: boolean) {
  const now = Date.now();
  const statusBoost = match.status === "Live" ? 500_000 : match.status === "Starting Soon" ? 420_000 : match.status === "Upcoming" ? 320_000 : 0;
  const popularBoost = popular ? 90_000 : 0;
  const sourceBoost = (match.sourceCount || 0) * 1000;
  const coverageBoost = match.coverage === "direct" ? 18_000 : match.coverage === "matched" ? 10_000 : match.coverage === "fallback" ? 4_000 : 0;
  const timeScore = kickoffMillis ? Math.max(0, 120_000 - Math.abs(kickoffMillis - now) / 60000) : 0;
  return statusBoost + popularBoost + sourceBoost + coverageBoost + timeScore + (match.availability || 0) * 1000;
}

function fixtureToMatch(event: ScheduleMatchPayload): ScrapedMatch | null {
  const title = event.title?.trim();
  if (!title || !isRelevantEvent(event)) return null;

  const sources = scheduleSources(event);
  const eventSource = chooseEventSource(sources);
  const playableEventSource = eventSource?.source ? { source: eventSource.source, id: eventSource.id } : undefined;
  const playableEventSources = playableEventSource
    ? orderEventSources(sources)
    : undefined;
  const sourceIds = sources.map((source) => source.id);
  const teams = resolveTeams(event);
  const category = normalizeCategory(event.category);
  const sport = eventSportLabel(event);
  const kickoffMillis = toKickoffMillis(event.date);
  const status = statusForKickoff(kickoffMillis, sources.length);
  const startsAt = kickoffMillis ? new Date(kickoffMillis).toISOString() : undefined;
  const kickoff = kickoffLabel(kickoffMillis);
  const quality = sources.length > 0 ? "HD" : "Unknown";
  const sourceCount = sources.length;
  const subtitleParts = [
    sport,
    kickoff,
    sourceCount > 1 ? `${sourceCount} sources` : sourceCount === 1 ? "1 source" : undefined,
  ].filter(Boolean);

  const match: ScrapedMatch = {
    id: event.id || scheduleKey(event),
    cid: sourceIds[0] || event.id || title,
    title,
    displayTitle: title,
    subtitle: subtitleParts.join(" · "),
    kind: "fixture",
    availability: sources.length > 0 ? 0.7 : 0,
    categories: [category],
    teams,
    poster: resolveImageURL(event.poster),
    league: sport,
    sport,
    network: playableEventSource ? `${playableEventSource.source.toUpperCase()} stream` : undefined,
    quality,
    alternateCount: Math.max(sourceCount, 1),
    startsAt,
    status,
    sourceCount,
    sourceIds,
    isPopular: event.popular === true,
    coverage: playableEventSource ? "direct" : "unavailable",
    playbackType: "event",
    eventSource: playableEventSource,
    eventSources: playableEventSources && playableEventSources.length > 1 ? playableEventSources : undefined,
  };

  return {
    ...match,
    rank: fixtureRank(match, kickoffMillis, event.popular),
  };
}

async function getMatchFeed(): Promise<ScrapedMatch[]> {
  // Build-time + runtime: StreamEx/VipLeague web catalog only (no homelab scraper).
  // Static FTP export bakes this into /api/matches so getfotty.com stays populated.
  const schedule = await fetchSchedule();

  return schedule
    .map(fixtureToMatch)
    .filter((match): match is ScrapedMatch => Boolean(match?.eventSource))
    .sort((a, b) => (b.rank || 0) - (a.rank || 0));
}

export async function GET() {
  return NextResponse.json(await getMatchFeed());
}
