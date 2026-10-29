// Reviewed observer scope, not a source activation or playback allowlist.
import { WORKER_SOURCE_VERSION } from "../../web/workers/playback/src/worker-version.mjs";

export const OBSERVER_REVISION = "2026-10-11.watchdog-1";
export const CONFIGURATION_REVISION = "2026-10-29.native-catalog-parity-1";
export const COLLECTION_INTERVAL_MS = 15 * 60_000;
export const CONFIRMATION_WINDOWS = 2;
export const WORKER_ORIGIN = "https://fotty-playback-v3.adaptive-rhubarb.workers.dev";
export const WATCHDOG_ORIGIN = "https://fotty-watchdog.adaptive-rhubarb.workers.dev";
export const PROVIDERS = Object.freeze([
  // Third read is allowed only for one exactly matched current official fixture's
  // descriptor; returned delivery/media URLs are never fetched by this observer.
  { source: "cs", kind: "cs", origin: "https://nuviosports.xyz", path: "/manifest.json", maxRequestsPerDay: 288 },
  { source: "streamex-primary", kind: "streamex", origin: "https://www.streamex.net", path: "/api/live/matches/all", maxRequestsPerDay: 96 },
  { source: "streamex-mirror", kind: "streamex", origin: "https://streamex.sh", path: "/api/live/matches/all", maxRequestsPerDay: 96 },
  { source: "streamed-backup", kind: "streamex", origin: "https://streamed.pk", path: "/api/matches/all", maxRequestsPerDay: 96 },
  { source: "score808", kind: "score808", origin: "https://www.score808live.tv", path: "/score808-live-football-scores-real-time-match-updates-results/", maxRequestsPerDay: 96 },
  // Already admitted by the native AS adapter. At the reviewed15-minute cadence,
  // one manifest plus both advertised catalogs uses at most288 reads/day. Check
  // both scopes together so missing-check fences cannot reset their streaks.
  { source: "as", kind: "as", origin: "https://hd.plavio.site", path: "/manifest.json", maxRequestsPerDay: 288 },
]);
export const FIXTURE_SCOPES = Object.freeze([
  "premier-league", "champions-league", "la-liga", "serie-a", "bundesliga", "ligue-1", "mlb", "nhl", "carabao-cup",
  "cpl", "west-indies", "icc",
]);
export const EXPECTED_VERSIONS = Object.freeze({ observerRevision: OBSERVER_REVISION,
  configurationRevision: CONFIGURATION_REVISION, deploymentRevision: WORKER_SOURCE_VERSION });
export function observerPolicyOptions(environment = "production") {
  return { environment, admittedSources: [
    ...PROVIDERS.map(({ source, kind }) => ({ source, stages: kind === "cs" ? ["manifest", "catalog", "delivery-contract"]
      : kind === "as" ? ["manifest", "catalog"] : ["catalog"],
      activation: "active", expected: EXPECTED_VERSIONS,
      ...(kind === "streamex" ? { immediateFailureClasses: ["published-closure"] } : {}) })),
    ...FIXTURE_SCOPES.map((scope) => ({ source: `fixtures-${scope}`, stages: ["integrity"], activation: "active", expected: EXPECTED_VERSIONS })),
    { source: "worker", stages: ["identity"], activation: "active", expected: EXPECTED_VERSIONS },
    { source: "fixtures-service", stages: ["integrity"], activation: "active", expected: EXPECTED_VERSIONS },
    { source: "observer", stages: ["liveness"], activation: "active", expected: EXPECTED_VERSIONS },
  ] };
}
