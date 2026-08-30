/** Path segment generated for the watch page by static exports. */
export const WATCH_ROUTE_SEGMENT = "index";

/**
 * Build one canonical watch URL for static exports and server deployments.
 * The real content identifier remains in the `id` or `cid` query parameter.
 */
export function buildWatchPageHref(params: URLSearchParams): string {
  const qs = params.toString();
  return qs ? `/watch/${WATCH_ROUTE_SEGMENT}?${qs}` : `/watch/${WATCH_ROUTE_SEGMENT}`;
}
