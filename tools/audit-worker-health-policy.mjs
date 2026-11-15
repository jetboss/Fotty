import { validateCPLManifest } from "../web/workers/playback/src/cpl-fixture-policy.mjs";

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

export function validateWorkerHealth({ body, headerVersion, expectedVersion }) {
  requireValue(body && typeof body === "object", "Worker health did not return an object.");
  requireValue(body.ok === true, "Worker health did not report ok=true.");
  requireValue(body.service === "fotty-playback", "Worker health reported the wrong service.");
  requireValue(body.sourceVersion === expectedVersion, `Production source is ${body.sourceVersion || "missing"}; expected ${expectedVersion}.`);
  requireValue(headerVersion === expectedVersion, "Worker version header does not match the expected source.");
  requireValue(body.footballScheduleConfigured === true, "Football schedule credentials are not configured.");
  requireValue(typeof body.apiFootballCredentialConfigured === "boolean", "Live-score credential state is missing.");
  requireValue(typeof body.premierLeagueLiveScoresConfigured === "boolean", "Live-score availability state is missing.");
  requireValue(body.liveScoreQuota && typeof body.liveScoreQuota === "object", "Live-score quota state is missing.");

  const warnings = [];
  if (body.liveScoreQuota.accessRestricted === true) {
    requireValue(body.premierLeagueLiveScoresConfigured === false, "A restricted live-score plan was advertised as available.");
    warnings.push("API-Football current-season access is restricted; official FPL/football-data fallback remains required.");
  }
  if (body.liveScoreQuota.status === "unavailable") {
    warnings.push("The live-score quota coordinator could not be inspected.");
  }
  return { warnings };
}

export function validateWorkerCPL({ body, sourceHeader, headerVersion, expectedVersion }) {
  requireValue(headerVersion === expectedVersion, "CPL response came from an unexpected Worker version.");
  validateCPLManifest(body);
  const allowed = new Set(["verified", "live-verified", "last-known-good"]);
  requireValue(allowed.has(body.sourceStatus), `Unexpected CPL source status: ${body.sourceStatus || "missing"}.`);
  requireValue(sourceHeader === body.sourceStatus, "CPL source header does not match its response body.");
  return {
    fixtureCount: body.fixtures.length,
    sourceStatus: body.sourceStatus,
    warnings: body.sourceStatus === "last-known-good"
      ? ["Live CPL verification is unavailable; production is serving the reviewed fallback."]
      : [],
  };
}
