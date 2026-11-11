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
  requireValue(Number.isInteger(body.catalogProviderCount) && body.catalogProviderCount > 0, "No catalog providers are configured.");
  requireValue(body.catalogCoverageMode === "parallel-with-direct-fallback", "Catalog coverage mode is unexpected.");
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
  return { catalogProviderCount: body.catalogProviderCount, warnings };
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

export function validateWorkerCatalog({ body, headers, expectedVersion, expectedProviderCount }) {
  requireValue(headers.version === expectedVersion, "Catalog response came from an unexpected Worker version.");
  requireValue(Array.isArray(body) && body.length > 0, "Catalog lookup did not preserve a playable fallback.");
  const attempted = Number(headers.attempted);
  const responding = Number(headers.responding);
  requireValue(Number.isInteger(attempted) && attempted === expectedProviderCount, "Catalog attempted-provider count is inconsistent with health.");
  requireValue(Number.isInteger(responding) && responding >= 0 && responding <= attempted, "Catalog responding-provider count is invalid.");
  const expectedCoverage = responding === attempted ? "complete" : responding > 0 ? "partial" : "fallback-only";
  requireValue(headers.coverage === expectedCoverage, "Catalog coverage classification is inconsistent.");
  return {
    attempted,
    responding,
    coverage: headers.coverage,
    warnings: headers.coverage === "complete" ? [] : [`Catalog coverage is ${headers.coverage} (${responding}/${attempted} providers responding).`],
  };
}

export function validateEmbedRedirect({ status, location, expectedVersion, headerVersion }) {
  requireValue(status === 302, `Embed route returned HTTP ${status}; expected 302.`);
  requireValue(headerVersion === expectedVersion, "Embed response came from an unexpected Worker version.");
  const url = new URL(location);
  requireValue(url.protocol === "https:" && url.hostname === "embed.st", "Embed route redirected to an unexpected origin.");
  requireValue(url.pathname === "/embed/alpha/fotty-worker-health-probe/1", "Embed route changed the requested source identity.");
}
