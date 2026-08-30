/**
 * Homelab / standalone builds must keep watch and auth API routes dynamic so
 * Authorization headers and query params are evaluated at request time.
 *
 * Static FTP export (`IS_STATIC_EXPORT=true`) cannot ship dynamic API routes.
 * Use `npm run build:static`, which patches the watch/auth route list to
 * `force-static` for that build only. Docker/homelab builds never patch.
 *
 * Keep this list in sync with `scripts/patch-watch-routes-static.sh`.
 */
export const WATCH_AUTH_DYNAMIC_ROUTES = [
  "src/app/api/stream/token/route.ts",
  "src/app/api/stream/session/route.ts",
  "src/app/api/stream/segment/route.ts",
  "src/app/api/stream/native/route.ts",
  "src/app/api/stream/route.ts",
  "src/app/api/status/route.ts",
  "src/app/api/p2p/health/route.ts",
  "src/app/api/live/streams/route.ts",
  "src/app/api/embed/hls/route.ts",
  "src/app/api/embed/player/route.ts",
  "src/app/api/pocketbase/entitlement/route.ts",
  "src/app/api/football/matches/route.ts",
] as const;
