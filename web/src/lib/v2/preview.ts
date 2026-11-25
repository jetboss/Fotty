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

export function v2HomePath(): string {
  return isV2Enabled() ? "/" : "/next";
}

export function v2SearchPath(): string {
  return isV2Enabled() ? "/search" : "/next/search";
}

export function v2SchedulePath(): string {
  return isV2Enabled() ? "/schedule" : "/next/schedule";
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
    "/schedule": v2SchedulePath(),
    "/search": v2SearchPath(),
    "/teams": v2TeamsPath(),
    "/settings": v2SettingsPath(),
    "/tables": v2TablesPath(),
    "/favorites": v2FavoritesPath(),
    "/saved": v2FavoritesPath(),
    "/more": v2MorePath(),
  };
  return map[classicPath] ?? classicPath;
}

const V2_CANONICAL_PREFIXES = [
  "/",
  "/schedule",
  "/search",
  "/teams",
  "/settings",
  "/tables",
  "/favorites",
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
