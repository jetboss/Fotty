import { isV2Enabled, isV2RoutePath } from "@/lib/v2/preview";

/** True when watch was opened from the v2 shell. */
export function isV2WatchReturn(returnTo: string) {
  if (isV2Enabled() && isV2RoutePath(returnTo)) return true;
  return returnTo === "/next" || returnTo.startsWith("/next/");
}

/** v2 watch chrome when the site is on v2 or the opener was a v2 route. */
export function isV2WatchMode(returnTo: string) {
  return isV2Enabled() || isV2WatchReturn(returnTo);
}
