export { buildWatchPageHref } from "@/lib/watch-route";

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
