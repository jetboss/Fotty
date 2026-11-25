import assert from "node:assert/strict";
import test from "node:test";
import cplManifest from "../web/public/data/cpl-2026-fixtures.json" with { type: "json" };
import {
  validateEmbedRedirect,
  validateWorkerCatalog,
  validateWorkerCPL,
  validateWorkerHealth,
} from "./audit-worker-health-policy.mjs";

const version = "2026-09-20.worker-stability-1";
const health = {
  ok: true,
  service: "fotty-playback",
  sourceVersion: version,
  footballScheduleConfigured: true,
  catalogProviderCount: 3,
  catalogCoverageMode: "parallel-with-direct-fallback",
  apiFootballCredentialConfigured: true,
  premierLeagueLiveScoresConfigured: false,
  liveScoreQuota: { configured: true, accessRestricted: true },
};

const cpl = { ...structuredClone(cplManifest), sourceStatus: "verified" };

test("health accepts an explicitly restricted live-score plan as a warning", () => {
  const result = validateWorkerHealth({ body: health, headerVersion: version, expectedVersion: version });
  assert.equal(result.catalogProviderCount, 3);
  assert.equal(result.warnings.length, 1);
});

test("health rejects a stale production version", () => {
  assert.throws(
    () => validateWorkerHealth({ body: health, headerVersion: version, expectedVersion: "new-version" }),
    /expected new-version/,
  );
});

test("CPL validation rejects a mismatched source receipt", () => {
  assert.throws(
    () => validateWorkerCPL({ body: cpl, sourceHeader: "last-known-good", headerVersion: version, expectedVersion: version }),
    /does not match/,
  );
});

test("catalog coverage must agree with the provider counts", () => {
  const result = validateWorkerCatalog({
    body: [{ provider: "Legacy", embedUrl: "https://embed.st/embed/alpha/probe/1" }],
    expectedVersion: version,
    expectedProviderCount: 3,
    headers: { version, attempted: "3", responding: "1", coverage: "partial" },
  });
  assert.equal(result.coverage, "partial");
  assert.throws(() => validateWorkerCatalog({
    body: [{ provider: "Legacy" }],
    expectedVersion: version,
    expectedProviderCount: 3,
    headers: { version, attempted: "3", responding: "1", coverage: "complete" },
  }), /inconsistent/);
});

test("embed contract rejects any redirect outside the approved origin", () => {
  validateEmbedRedirect({
    status: 302,
    location: "https://embed.st/embed/alpha/fotty-worker-health-probe/1",
    headerVersion: version,
    expectedVersion: version,
  });
  assert.throws(() => validateEmbedRedirect({
    status: 302,
    location: "https://example.com/embed/alpha/fotty-worker-health-probe/1",
    headerVersion: version,
    expectedVersion: version,
  }), /unexpected origin/);
});
