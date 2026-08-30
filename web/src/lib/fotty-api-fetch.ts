/** Browser fetch helper for static hosts (getfotty.com FTP) that lack Node `/api` handlers. */

import { FOTTY_DEFAULTS } from "@/lib/fotty-config";

/**
 * Optional remote API base for live Watch APIs (streams / embed proxy / HLS).
 * Homelab is retired — do **not** default to pixel-invoice.com.
 * Set `NEXT_PUBLIC_FOTTY_API_BASE` at static build time to a Cloudflare Worker
 * (or other public host) that runs `/api/live/streams` and `/api/embed/player`.
 *
 * Catalog JSON baked into the static export (`/api/matches`, football, etc.) stays same-origin.
 */
export function getPublicFottyApiBase() {
  const configured = process.env.NEXT_PUBLIC_FOTTY_API_BASE?.trim();
  if (configured) return configured.replace(/\/$/, "");
  // Always fall back to the public playback Worker so static FTP Watch can resolve
  // /api/live/streams instead of synthesizing dead "Fotty 1–4" shells.
  return FOTTY_DEFAULTS.playbackApiBase.replace(/\/$/, "");
}

/** True when Watch can hit a live playback API (not same-origin static FTP shells). */
export function hasRemoteFottyApi() {
  return Boolean(getPublicFottyApiBase());
}

function normalizeApiPath(path: string) {
  if (!path.startsWith("/")) return `/${path}`;
  return path;
}

export function isStaticFottyHost(hostname?: string) {
  const host = hostname || (typeof window !== "undefined" ? window.location.hostname : "");
  return host === "getfotty.com" || host === "www.getfotty.com";
}

function splitPath(path: string) {
  const normalized = normalizeApiPath(path);
  const queryIndex = normalized.indexOf("?");
  const pathname = queryIndex === -1 ? normalized : normalized.slice(0, queryIndex);
  const query = queryIndex === -1 ? "" : normalized.slice(queryIndex);
  return { pathname, query };
}

/**
 * App pages use trailingSlash: true. Extensionless static API files on Apache
 * (e.g. `/api/matches`) 404 when requested as `/api/matches/`.
 */
function resolveRequestPath(path: string) {
  const { pathname, query } = splitPath(path);
  if (pathname.startsWith("/api/") && !pathname.endsWith("/")) {
    return `${pathname}${query}`;
  }
  const slashPath = pathname.endsWith("/") ? pathname : `${pathname}/`;
  return `${slashPath}${query}`;
}

/** Live Watch / playback paths that the Cloudflare Worker (or similar) actually serves. */
function isRemotePlaybackPath(pathname: string) {
  return (
    pathname === "/api/live/streams" ||
    pathname.startsWith("/api/live/streams?") ||
    pathname.startsWith("/api/embed/") ||
    pathname === "/api/stream" ||
    pathname.startsWith("/api/stream/") ||
    pathname === "/api/status" ||
    pathname.startsWith("/api/status?") ||
    pathname === "/api/p2p/health" ||
    pathname.startsWith("/api/p2p/health?")
  );
}

/** Same-origin path, or absolute Worker URL for playback-only APIs. */
export function resolveFottyApiUrl(path: string): string {
  const resolved = resolveRequestPath(path);
  const { pathname } = splitPath(resolved);
  const base = getPublicFottyApiBase();
  if (base && isRemotePlaybackPath(pathname)) {
    return `${base}${resolved}`;
  }
  return resolved;
}

/**
 * Fetch Fotty API paths.
 * - Playback routes (`/api/live/*`, `/api/embed/*`, …): remote Worker when configured.
 * - Catalog routes (`/api/matches`, football, …): same-origin static JSON / local Next.
 * Never falls back to a retired homelab host.
 */
export async function fetchFottyApi(path: string, init?: RequestInit): Promise<Response> {
  return fetch(resolveFottyApiUrl(path), init);
}
