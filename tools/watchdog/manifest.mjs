// Reviewed observer scope, not a source activation or playback allowlist.
import { WORKER_SOURCE_VERSION } from "../../web/workers/playback/src/worker-version.mjs";

export const OBSERVER_REVISION = "2026-10-11.watchdog-1";
export const CONFIGURATION_REVISION = "2026-10-11.admitted-metadata-1";
export const WORKER_ORIGIN = "https://fotty-playback-v3.adaptive-rhubarb.workers.dev";
export const WATCHDOG_ORIGIN = "https://fotty-watchdog.adaptive-rhubarb.workers.dev";
export const PROVIDERS = Object.freeze([
  { source: "cs", kind: "cs", origin: "https://nuviosports.xyz", path: "/manifest.json", maxRequestsPerDay: 96 },
  { source: "streamex-primary", kind: "streamex", origin: "https://www.streamex.net", path: "/api/live/matches/all", maxRequestsPerDay: 48 },
  { source: "streamex-mirror", kind: "streamex", origin: "https://streamex.sh", path: "/api/live/matches/all", maxRequestsPerDay: 48 },
  { source: "streamed-backup", kind: "streamex", origin: "https://streamed.pk", path: "/api/matches/all", maxRequestsPerDay: 48 },
  { source: "score808", kind: "score808", origin: "https://www.score808live.tv", path: "/score808-live-football-scores-real-time-match-updates-results/", maxRequestsPerDay: 48 },
]);
export const FIXTURE_SCOPES = Object.freeze([
  "premier-league", "champions-league", "la-liga", "serie-a", "bundesliga", "ligue-1", "mlb", "nhl",
  "cpl", "west-indies", "icc",
]);
export const EXPECTED_VERSIONS = Object.freeze({ observerRevision: OBSERVER_REVISION,
  configurationRevision: CONFIGURATION_REVISION, deploymentRevision: WORKER_SOURCE_VERSION });
export function observerPolicyOptions(environment = "production") {
  return { environment, admittedSources: [
    ...PROVIDERS.map(({ source, kind }) => ({ source, stages: kind === "cs" ? ["manifest", "catalog"] : ["catalog"],
      activation: "active", expected: EXPECTED_VERSIONS })),
    ...FIXTURE_SCOPES.map((scope) => ({ source: `fixtures-${scope}`, stages: ["integrity"], activation: "active", expected: EXPECTED_VERSIONS })),
    { source: "worker", stages: ["identity"], activation: "active", expected: EXPECTED_VERSIONS },
    { source: "fixtures-service", stages: ["integrity"], activation: "active", expected: EXPECTED_VERSIONS },
    { source: "observer", stages: ["liveness"], activation: "active", expected: EXPECTED_VERSIONS },
  ] };
}
