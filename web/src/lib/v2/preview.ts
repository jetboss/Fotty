/** True when the next-gen Fotty shell is the default experience. */
export function isV2Enabled(): boolean {
  if (process.env.NEXT_PUBLIC_FOTTY_V2_ENABLED === "true") return true;
  if (process.env.IS_STATIC_EXPORT === "true") return true;
  if (process.env.NODE_ENV === "production") return true;
  return (
    process.env.NEXT_PUBLIC_FOTTY_PREVIEW_ROUTES_ENABLED === "true" ||
    process.env.FOTTY_PREVIEW_ROUTES_ENABLED === "true"
  );
}

/** @deprecated Use {@link isV2Enabled}. */
export function isV2LocalCutover(): boolean {
  return isV2Enabled();
}

export function v2HomePath(): string {
  return isV2Enabled() ? "/" : "/next";
}

export function v2SearchPath(): string {
  return isV2Enabled() ? "/search" : "/next/search";
}

export function v2GuidePath(): string {
  // /guide is retired (410 Gone on Apache). Schedule is the companion fixture board.
  return isV2Enabled() ? "/schedule" : "/next/schedule";
}

export function v2SchedulePath(): string {
  return isV2Enabled() ? "/schedule" : "/next/schedule";
}

export function v2SwarmPath(): string {
  return "/swarm";
}

export function v2TeamsPath(): string {
  return isV2Enabled() ? "/teams" : "/next/teams";
}

export function v2SettingsPath(): string {
  return isV2Enabled() ? "/settings" : "/next/settings";
}

export function v2TablesPath(): string {
  return isV2Enabled() ? "/tables" : "/next/tables";
}

export function v2WorldCupPath(): string {
  return isV2Enabled() ? "/world-cup" : "/next/world-cup";
}

export function v2FavoritesPath(): string {
  return isV2Enabled() ? "/favorites" : "/next/saved";
}

export function v2MorePath(): string {
  return isV2Enabled() ? "/more" : "/next/more";
}

/** Map a classic Fotty path to its v2 equivalent. */
export function v2AppPath(classicPath: string): string {
  const map: Record<string, string> = {
    "/": v2HomePath(),
    "/swarm": v2SwarmPath(),
    "/guide": v2GuidePath(),
    "/schedule": v2SchedulePath(),
    "/search": v2SearchPath(),
    "/teams": v2TeamsPath(),
    "/settings": v2SettingsPath(),
    "/tables": v2TablesPath(),
    "/world-cup": v2WorldCupPath(),
    "/favorites": v2FavoritesPath(),
    "/saved": v2FavoritesPath(),
    "/more": v2MorePath(),
  };
  return map[classicPath] ?? classicPath;
}

const V2_CANONICAL_PREFIXES = [
  "/",
  "/guide",
  "/schedule",
  "/search",
  "/teams",
  "/settings",
  "/tables",
  "/world-cup",
  "/favorites",
  "/swarm",
  "/more",
] as const;

/** Routes that render inside the v2 shell chrome. */
export function isV2RoutePath(pathname: string): boolean {
  if (!isV2Enabled()) {
    return pathname === "/next" || pathname.startsWith("/next/");
  }
  return V2_CANONICAL_PREFIXES.some((prefix) => {
    if (prefix === "/") return pathname === "/";
    return pathname === prefix || pathname.startsWith(`${prefix}/`);
  });
}

/** Resolve a legacy `/next/...` path to its canonical v2 URL when cutover is on. */
export function v2CanonicalFromNextPath(pathname: string): string | null {
  if (!pathname.startsWith("/next")) return null;
  const suffix = pathname.slice("/next".length) || "/";
  return suffix === "/" ? "/" : suffix;
}
