/**
 * Standalone builds must keep the remaining live-data API routes dynamic so
 * query parameters are evaluated at request time.
 *
 * Static FTP export (`IS_STATIC_EXPORT=true`) cannot ship dynamic API routes.
 * Use `npm run build:static`, which patches the discovered API routes to
 * `force-static` for that build only. Standalone builds never patch.
 *
 * Keep this list in sync with `scripts/patch-watch-routes-static.sh`.
 */
export const DYNAMIC_DATA_ROUTES = [
  "src/app/api/live/streams/route.ts",
  "src/app/api/football/matches/route.ts",
] as const;
