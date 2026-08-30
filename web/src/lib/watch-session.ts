export { buildWatchPageHref, WATCH_ROUTE_SEGMENT } from "@/lib/watch-route";

/** Retained for legacy player error classification; account-backed sessions are retired. */
export function isWatchSessionAuthError(_message?: string | null): boolean {
  void _message;
  return false;
}

/** Account-backed stream sessions are retired; playback is guest-accessible. */
export async function refreshWatchSessionIfNeeded(): Promise<boolean> {
  return false;
}

/** No token exists in the supported guest-access product graph. */
export function invalidateWatchSessionToken(): boolean {
  return false;
}

/** Compatibility shim for retired account-backed stream sessions. */
export async function invalidateWatchSessionTokenAsync(): Promise<boolean> {
  return false;
}

export function isP2PContentId(value?: string | null): value is string {
  return Boolean(value && /^[a-f0-9]{40}$/i.test(value));
}

const STATIC_EXPORT_PLACEHOLDER_IDS = new Set(["index", "placeholder"]);

/** Resolve /watch/[id] on static hosts where every watch URL serves /watch/index. */
export function resolveWatchRouteId(paramsId?: string | string[] | null, searchParams?: URLSearchParams | null) {
  const fromParams = Array.isArray(paramsId) ? paramsId[0] : paramsId || "";
  if (fromParams && !STATIC_EXPORT_PLACEHOLDER_IDS.has(fromParams)) {
    return fromParams;
  }

  const fromQuery = searchParams?.get("cid") || searchParams?.get("id");
  if (fromQuery && !STATIC_EXPORT_PLACEHOLDER_IDS.has(fromQuery)) {
    return fromQuery;
  }

  if (typeof window !== "undefined") {
    const match = window.location.pathname.match(/\/watch\/([^/?#]+)/i);
    const fromPath = match?.[1] ? decodeURIComponent(match[1]) : "";
    if (fromPath && !STATIC_EXPORT_PLACEHOLDER_IDS.has(fromPath)) {
      return fromPath;
    }
  }

  return fromParams;
}
