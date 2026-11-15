import assert from "node:assert/strict";
import test from "node:test";
import cplManifest from "../web/public/data/cpl-2026-fixtures.json" with { type: "json" };
import {
  validateWorkerCPL,
  validateWorkerHealth,
} from "./audit-worker-health-policy.mjs";

const version = "2026-09-20.worker-stability-1";
const health = {
  ok: true,
  service: "fotty-playback",
  sourceVersion: version,
  footballScheduleConfigured: true,
  apiFootballCredentialConfigured: true,
  premierLeagueLiveScoresConfigured: false,
  liveScoreQuota: { configured: true, accessRestricted: true },
};

const cpl = { ...structuredClone(cplManifest), sourceStatus: "verified" };

test("health accepts an explicitly restricted live-score plan as a warning", () => {
  const result = validateWorkerHealth({ body: health, headerVersion: version, expectedVersion: version });
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
