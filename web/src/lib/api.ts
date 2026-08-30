"use client";

import { getWatchAuthHeaders } from "@/lib/watch-auth-headers";
import { fetchFottyApi, hasRemoteFottyApi, isStaticFottyHost, resolveFottyApiUrl } from "@/lib/fotty-api-fetch";
import { buildDirectEmbedUrl, synthesizeEventStreamVariants } from "@/lib/stream-guide/embed-url";
import { invalidateWatchSessionToken, refreshWatchSessionIfNeeded } from "@/lib/watch-session";
import { fetchWatchStreamToken, invalidateWatchStreamTokenCache } from "@/lib/watch-stream-token-client";

/** Saved cards (bookmarks, continue watching). Not TMDB — sports web only. */
export type SavedCardKind = "session" | "fixture" | "channel";

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
  playbackType?: "event" | "p2p";
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
  p2pHealth?: {
    playable: boolean;
    latencyMs?: number;
    checkedAt?: string;
    reason?: string;
    kind?: string;
  };
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

export interface SwarmStatus {
  peerCount: number;
  downloadSpeedKbps: number;
  bufferSeconds: number;
  readySegmentCount: number;
  firstSegmentReady: boolean;
  clientCount?: number;
  isLive?: boolean;
  status?: string;
  error?: string;
}

export type MediaType = "movie" | "tv" | "sport";

export interface CatalogSection {
  id?: string;
  title: string;
  subtitle?: string;
  items: MediaItem[];
}

export interface CatalogResponse {
  sections: CatalogSection[];
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
  /** Attach session headers for paid-watch API routes. */
  watch?: boolean;
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

async function withWatchStreamToken(url: string) {
  try {
    const watchToken = await fetchWatchStreamToken();
    if (!watchToken) return url;
    return `${url}${url.includes("?") ? "&" : "?"}watchToken=${encodeURIComponent(watchToken)}`;
  } catch {
    return url;
  }
}

async function fetchJSON<T>(url: string, fallback: T, options: FetchOptions = {}): Promise<T> {
  const ttlMs = options.ttlMs ?? 0;
  const storage = options.storage ?? "none";
  const cached = ttlMs > 0 ? readCachedValue<T>(url, storage) : undefined;
  if (cached !== undefined) return cached;

  try {
    const requestUrl = options.watch ? await withWatchStreamToken(url) : url;
    const response = await fetchFottyApi(requestUrl, {
      headers: {
        Accept: "application/json",
        ...(options.watch ? getWatchAuthHeaders() : {}),
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
  async fetchMediaDetail(type: string, id: string): Promise<MediaItem | null> {
    void type;
    void id;
    return null;
  },

  async searchMedia(query: string): Promise<MediaItem[]> {
    void query;
    return [];
  },

  async fetchMatches(): Promise<ScrapedMatch[]> {
    return fetchJSON<ScrapedMatch[]>("/api/matches", [], { ttlMs: 45_000, storage: "local" });
  },

  async fetchMatchesFresh(): Promise<ScrapedMatch[]> {
    return fetchJSON<ScrapedMatch[]>("/api/matches", [], { ttlMs: 0, storage: "none" });
  },

  /** P2P channel catalog retired — always empty. */
  async fetchP2PChannels(): Promise<ScrapedMatch[]> {
    return [];
  },

  async fetchEventStreams(source: string, id: string): Promise<EventStreamVariant[]> {
    // Static FTP has no live handlers unless `NEXT_PUBLIC_FOTTY_API_BASE` points at a Worker.
    if (typeof window !== "undefined" && isStaticFottyHost() && !hasRemoteFottyApi()) {
      // Match iOS feed depth: try Fotty 1–4 when the streams API is unavailable.
      return synthesizeEventStreamVariants(source, id, 4);
    }

    const authHeaders = getWatchAuthHeaders();
    const params = new URLSearchParams({ source, id });

    try {
      const watchToken = await fetchWatchStreamToken();
      if (watchToken) {
        params.set("watchToken", watchToken);
      }
    } catch {
      // Streams endpoint still receives session headers below.
    }

    let response: Response;
    try {
      response = await fetchFottyApi(`/api/live/streams?${params.toString()}`, {
        headers: {
          Accept: "application/json",
          ...authHeaders,
        },
        cache: "no-store",
      });
    } catch {
      return synthesizeEventStreamVariants(source, id, 4);
    }

    if (response.status === 401) {
      const refreshed = await refreshWatchSessionIfNeeded();
      if (refreshed) {
        const retry = await fetchFottyApi(`/api/live/streams?${params.toString()}`, {
          headers: {
            Accept: "application/json",
            ...getWatchAuthHeaders(),
          },
          cache: "no-store",
        });
        if (retry.ok) {
          const payload = (await retry.json().catch(() => [])) as unknown;
          return Array.isArray(payload) ? (payload as EventStreamVariant[]) : [];
        }
        if (retry.status !== 401) {
          if (retry.status === 403) {
            throw new Error("This device is signed in without active watch access. Sign out and sign back in.");
          }
          throw new Error("Fotty could not verify this watch path. Try another source.");
        }
      }
      invalidateWatchSessionToken();
      invalidateWatchStreamTokenCache();
      throw new Error("Your session expired on this device. Sign in again to watch.");
    }
    if (response.status === 403) {
      throw new Error("This device is signed in without active watch access. Sign out and sign back in.");
    }
    if (!response.ok) {
      throw new Error("Fotty could not verify this watch path. Try another source.");
    }

    const payload = (await response.json().catch(() => [])) as unknown;
    return Array.isArray(payload) ? (payload as EventStreamVariant[]) : [];
  },

  async getEventPlayerURL(source: string, id: string, streamNo = 1): Promise<string> {
    // In-page iframe uses the provider embed directly.
    // PHP /playback/player.php can fetch HTML but not HLS (upstream 403 to host IP).
    return buildDirectEmbedUrl(source, id, streamNo);
  },

  async getSwarmStatus(cid: string, sessionId?: string | null): Promise<SwarmStatus> {
    const params = new URLSearchParams({ id: cid });
    if (sessionId) params.set("session", sessionId);
    return fetchJSON<SwarmStatus>(`/api/status?${params.toString()}`, {
      peerCount: 0,
      downloadSpeedKbps: 0,
      bufferSeconds: 0,
      readySegmentCount: 0,
      firstSegmentReady: false,
      error: "Status unavailable",
      },
      { watch: true }
    );
  },

  async checkP2PHealth(cid: string): Promise<NonNullable<ScrapedMatch["p2pHealth"]>> {
    return fetchJSON<NonNullable<ScrapedMatch["p2pHealth"]>>(
      `/api/p2p/health?id=${encodeURIComponent(cid)}`,
      {
        playable: false,
        reason: "health_unavailable",
      },
      { ttlMs: 90_000, storage: "session" }
    );
  },

  getStreamURL(cid: string, sessionId?: string | null): string {
    const params = new URLSearchParams({ id: cid });
    if (sessionId) params.set("session", sessionId);
    return resolveFottyApiUrl(`/api/stream?${params.toString()}`);
  },

  getNativeP2PStreamURL(cid: string): string {
    const params = new URLSearchParams({ id: cid });
    return resolveFottyApiUrl(`/api/stream/native?${params.toString()}`);
  },

  async prepareP2PBrokerSession(
    cid: string,
    options: { title?: string; forceNew?: boolean } = {},
    retried = false
  ): Promise<{
    sessionId: string;
    ready: boolean;
    state?: string;
    message?: string;
    error?: string;
    status?: number;
  } | null> {
    const brokerFailureMessage = (status: number, payload?: { error?: string; detail?: string }) => {
      if (status === 401) return "Your sign-in needs to be refreshed before this stream can open.";
      if (status === 403) return "This account needs active live access before this stream can open.";
      if (status === 429) return "Too many stream attempts from this device. Wait a moment, then try again.";
      if (status === 502 || status === 504) return "The stream broker could not prepare this source. Try another feed or refresh Home.";
      const raw = payload?.error || payload?.detail;
      if (raw && !/api_password|token|secret|authorization/i.test(raw)) return raw.slice(0, 180);
      return "Fotty could not prepare this source. Try another feed or refresh Home.";
    };

    try {
      const sessionPath = await withWatchStreamToken("/api/stream/session");
      const response = await fetchFottyApi(sessionPath, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          ...getWatchAuthHeaders(),
        },
        cache: "no-store",
        body: JSON.stringify({
          cid,
          ...(options.title ? { title: options.title } : {}),
          ...(options.forceNew ? { forceNew: true } : {}),
        }),
      });

      if (!response.ok) {
        const payload = (await response.json().catch(() => ({}))) as { error?: string; detail?: string };
        console.error("Broker session API failed", response.status, payload);
        if (response.status === 401) {
          if (!retried && (await refreshWatchSessionIfNeeded())) {
            return FottyAPI.prepareP2PBrokerSession(cid, options, true);
          }
          invalidateWatchSessionToken();
        }
        const message = brokerFailureMessage(response.status, payload);
        return {
          sessionId: "",
          ready: false,
          state: "failed",
          status: response.status,
          error: message,
          message,
        };
      }
      const data = (await response.json()) as {
        sessionId?: string;
        ready?: boolean;
        state?: string;
        message?: string;
        error?: string;
      };
      if (!data.sessionId) {
        console.error("Broker session response missing session id", data);
        return {
          sessionId: "",
          ready: false,
          state: "failed",
          error: "The stream broker did not return a session. Try another feed or refresh Home.",
          message: "The stream broker did not return a session. Try another feed or refresh Home.",
        };
      }
      return {
        sessionId: data.sessionId,
        ready: Boolean(data.ready),
        state: data.state,
        message: data.message,
        error: data.error,
      };
    } catch (error) {
      console.error("Broker session request failed", error);
      return {
        sessionId: "",
        ready: false,
        state: "failed",
        error: "This device could not reach the stream broker. Refresh Fotty or try another feed.",
        message: "This device could not reach the stream broker. Refresh Fotty or try another feed.",
      };
    }
  },
};
