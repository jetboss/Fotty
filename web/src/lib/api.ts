"use client";

import { fetchFottyApi, hasRemoteFottyApi, isStaticFottyHost } from "@/lib/fotty-api-fetch";
import { synthesizeEventStreamVariants } from "@/lib/stream-guide/embed-url";

/** Saved cards (bookmarks, continue watching). Not TMDB — sports web only. */
type SavedCardKind = "session" | "fixture" | "channel";

export interface TeamReference {
  name: string;
  badge?: string;
}

export interface ScrapedMatch {
  id?: string;
  title: string;
  displayTitle?: string;
  subtitle?: string;
  kind?: "fixture" | "channel";
  cid: string;
  availability: number;
  categories?: string[];
  bitrate_kbps?: number;
  teams?: {
    home: TeamReference;
    away: TeamReference;
  };
  poster?: string;
  league?: string;
  sport?: string;
  region?: string;
  network?: string;
  quality?: "HD" | "HQ" | "SD" | "Unknown";
  alternateCount?: number;
  sourceCount?: number;
  sourceIds?: string[];
  isPopular?: boolean;
  coverage?: "direct" | "matched" | "fallback" | "channel" | "unavailable";
  playbackType?: "event";
  eventSource?: {
    source: string;
    id: string;
  };
  eventSources?: Array<{
    source: string;
    id: string;
  }>;
  rank?: number;
  score?: {
    home: number;
    away: number;
  };
  startsAt?: string;
  status?: string;
}

export interface EventStreamVariant {
  id: string;
  source: string;
  streamNo: number;
  language?: string;
  hd?: boolean;
  embedUrl: string;
  viewers?: number;
  provider?: string;
  heatTier?: string;
}

export interface MediaItem {
  id: string | number;
  type: SavedCardKind | string;
  title: string;
  overview?: string;
  poster?: string;
  backdrop?: string;
  rating?: number;
  year?: string;
  meta?: string;
  genres?: string[];
  runtime?: string;
  seasons?: number;
  episodes?: number;
  tagline?: string;
  status?: string;
  /** When set, card links here (e.g. `/watch/...`). */
  href?: string;
}

interface CachedPayload<T> {
  expiresAt: number;
  value: T;
}

interface FetchOptions {
  ttlMs?: number;
  storage?: "local" | "session" | "none";
}

function cacheKey(url: string) {
  return `fotty.web.cache:${url}`;
}

function readCachedValue<T>(url: string, storage: FetchOptions["storage"], allowExpired = false): T | undefined {
  if (typeof window === "undefined" || storage === "none") return undefined;

  const target = storage === "session" ? window.sessionStorage : window.localStorage;

  try {
    const raw = target.getItem(cacheKey(url));
    if (!raw) return undefined;
    const parsed = JSON.parse(raw) as CachedPayload<T>;
    if (!allowExpired && Date.now() > parsed.expiresAt) return undefined;
    return parsed.value;
  } catch {
    return undefined;
  }
}

function writeCachedValue<T>(url: string, value: T, ttlMs: number, storage: FetchOptions["storage"]) {
  if (typeof window === "undefined" || storage === "none" || ttlMs <= 0) return;

  const target = storage === "session" ? window.sessionStorage : window.localStorage;

  try {
    target.setItem(
      cacheKey(url),
      JSON.stringify({
        expiresAt: Date.now() + ttlMs,
        value,
      } satisfies CachedPayload<T>)
    );
  } catch {
    // Caching should never block playback or browsing.
  }
}

async function fetchJSON<T>(url: string, fallback: T, options: FetchOptions = {}): Promise<T> {
  const ttlMs = options.ttlMs ?? 0;
  const storage = options.storage ?? "none";
  const cached = ttlMs > 0 ? readCachedValue<T>(url, storage) : undefined;
  if (cached !== undefined) return cached;

  try {
    const response = await fetchFottyApi(url, {
      headers: {
        Accept: "application/json",
      },
      cache: "no-store",
    });

    if (!response.ok) return fallback;
    const value = (await response.json()) as T;
    writeCachedValue(url, value, ttlMs, storage);
    return value;
  } catch {
    const stale = ttlMs > 0 ? readCachedValue<T>(url, storage, true) : undefined;
    return stale !== undefined ? stale : fallback;
  }
}

export const FottyAPI = {
  async fetchMatches(): Promise<ScrapedMatch[]> {
    return fetchJSON<ScrapedMatch[]>("/api/matches", [], { ttlMs: 45_000, storage: "local" });
  },

  async fetchMatchesFresh(): Promise<ScrapedMatch[]> {
    return fetchJSON<ScrapedMatch[]>("/api/matches", [], { ttlMs: 0, storage: "none" });
  },

  async fetchEventStreams(source: string, id: string): Promise<EventStreamVariant[]> {
    // Static FTP has no live handlers unless `NEXT_PUBLIC_FOTTY_API_BASE` points at a Worker.
    if (typeof window !== "undefined" && isStaticFottyHost() && !hasRemoteFottyApi()) {
      // Match iOS feed depth: try Fotty 1–4 when the streams API is unavailable.
      return synthesizeEventStreamVariants(source, id, 4);
    }

    const params = new URLSearchParams({ source, id });

    let response: Response;
    try {
      response = await fetchFottyApi(`/api/live/streams?${params.toString()}`, {
        headers: {
          Accept: "application/json",
        },
        cache: "no-store",
      });
    } catch {
      return synthesizeEventStreamVariants(source, id, 4);
    }

    if (response.status === 401) {
      throw new Error("This feed rejected the playback request. Try another source.");
    }
    if (response.status === 403) {
      throw new Error("This feed is not available for playback. Try another source.");
    }
    if (!response.ok) {
      throw new Error("Fotty could not verify this watch path. Try another source.");
    }

    const payload = (await response.json().catch(() => [])) as unknown;
    return Array.isArray(payload) ? (payload as EventStreamVariant[]) : [];
  },

};
