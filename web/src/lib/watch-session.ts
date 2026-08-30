import { getAuthSession, setAuthSession } from "@/lib/auth";
import { pocketBaseRefreshAuthToken } from "@/lib/pocketbase-client-auth";
export { buildWatchPageHref, WATCH_ROUTE_SEGMENT } from "@/lib/watch-route";

/** True when an API or player message indicates the PocketBase token must be refreshed. */
export function isWatchSessionAuthError(message?: string | null): boolean {
  const normalized = message?.toLowerCase() || "";
  return /(sign[- ]?in|session expired|refresh access|secure watch|invalid or expired session|sign-in needs to be refreshed)/.test(
    normalized
  );
}

/** Try PocketBase auth-refresh before dropping the bearer token. */
export async function refreshWatchSessionIfNeeded(): Promise<boolean> {
  const session = getAuthSession();
  if (!session?.token) return false;

  const refreshed = await pocketBaseRefreshAuthToken(session.token);
  if (!refreshed) return false;

  setAuthSession({ ...session, token: refreshed });
  return true;
}

/** Drop the bearer token while keeping email and entitlement so the watch gate can prompt re-auth. */
export function invalidateWatchSessionToken(): boolean {
  const session = getAuthSession();
  if (!session?.token) return false;

  const next = { ...session };
  delete next.token;
  delete next.userID;
  setAuthSession(next);
  return true;
}

/** Refresh the PocketBase token when possible; otherwise invalidate the watch session. */
export async function invalidateWatchSessionTokenAsync(): Promise<boolean> {
  const refreshed = await refreshWatchSessionIfNeeded();
  if (refreshed) return false;
  return invalidateWatchSessionToken();
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
