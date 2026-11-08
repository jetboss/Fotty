import test from "node:test";
import assert from "node:assert/strict";
import { fixtureReceipts, collectFixtureReceipts } from "./fixture-receipts.mjs";
import { EXPECTED_VERSIONS, WORKER_ORIGIN, observerPolicyOptions } from "./manifest.mjs";
import { SPORTS_SOURCES } from "../../web/workers/playback/src/sports-fixture-sources.mjs";
import { descriptorCompetitions } from "../../web/workers/playback/src/sports-fixture-policy.mjs";
import { applyObservationBatch } from "./observation-batch.mjs";
import { createPolicy, emptyLedger, incidentKey } from "./incident-policy.mjs";

const NOW = Date.UTC(2026, 9, 11);
const iso = (time) => new Date(time).toISOString();
function sports(now = NOW) {
  return { schemaVersion: 1, complete: true, revision: "offline-sports-test", sourceStatus: "verified", checkedAt: iso(now), fixtures: [],
    coverage: SPORTS_SOURCES.filter((source) => source.id !== "wnba").flatMap((source) => descriptorCompetitions(source).map((row) => ({
      sport: row.sport ?? source.sport, competitionId: row.id, competitionName: row.name,
      status: source.supported ? "covered" : "unsupported", checkedAt: source.supported ? iso(now) : null,
      fixtureCount: 0, pendingFixtureCount: 0, sync: { consecutiveFailures: 0 },
    }))),
  };
}
function cricket(now = NOW) {
  return { schemaVersion: 1, complete: true, revision: "offline-cricket-test", sourceStatus: "verified", checkedAt: iso(now), fixtures: [],
    sync: { consecutiveFailures: 0, lastAttemptAt: iso(now), lastSuccessAt: iso(now) },
    coverage: ["cpl", "west-indies", "icc"].map((id) => ({ competitionId: id, competitionName: id,
      status: id === "cpl" ? "offseason" : "covered", checkedAt: iso(now), fixtureCount: 0 })),
  };
}
const health = (changes = {}) => ({ service: "fotty-playback", sourceVersion: EXPECTED_VERSIONS.deploymentRevision,
  sportsFixtureServiceEnabled: true, cricketFixtureRegistryConfigured: true, ...changes });
function offlineRequest({ healthBody = health(), sportsBody = sports(), cricketBody = cricket(), failedPath } = {}) {
  const calls = [];
  return { calls, request: async (url) => {
    calls.push(String(url));
    assert.equal(url.origin, WORKER_ORIGIN);
    if (url.pathname === failedPath) return new Response(null, { status: 503 });
    if (url.pathname === "/health") return Response.json(healthBody);
    if (url.pathname === "/api/sports/fixtures") return Response.json(sportsBody);
    if (url.pathname === "/api/cricket/fixtures") return Response.json(cricketBody);
    throw new Error("Unreviewed offline route");
  } };
}

test("healthy source-backed snapshots emit only exact current metadata revisions and no decode evidence", () => {
  for (const [kind, body] of [["sports", sports()], ["cricket", cricket()]]) {
    const rows = fixtureReceipts(body, { kind, now: NOW });
    assert.ok(rows.some((row) => row.source === "fixtures-service" && row.outcome === "success"));
    assert.ok(rows.every((row) => row.facts.scope === kind && row.environment === "production"
      && row.stage === "integrity" && JSON.stringify(row.versions) === JSON.stringify(EXPECTED_VERSIONS)));
    assert.equal(JSON.stringify(rows).includes("decoded"), false);
    assert.equal(JSON.stringify(rows).includes("https:"), false);
  }
});

test("cricket aggregate gaps stay at service scope and prevent all borrowed per-cohort successes", () => {
  const body = cricket();
  body.coverage.find((row) => row.competitionId === "icc").expectedFixtureCount = 1;
  const rows = fixtureReceipts(body, { kind: "cricket", now: NOW });
  const failures = rows.filter((row) => row.outcome === "failure");
  assert.deepEqual(failures.map((row) => [row.source, row.failureClass, row.facts.scope]), [["fixtures-service", "coverage-gap", "cricket"]]);
  assert.ok(rows.filter((row) => row.source !== "fixtures-service" && row.source !== "fixtures-cpl").every((row) => row.outcome === "unknown"));
  assert.equal(rows.some((row) => row.outcome === "success"), false);
});

test("a sports cohort failure remains isolated while healthy reviewed siblings stay successful", () => {
  const body = sports();
  body.coverage.find((row) => row.competitionId === "mlb").sync.consecutiveFailures = 2;
  const rows = fixtureReceipts(body, { kind: "sports", now: NOW });
  assert.ok(rows.some((row) => row.source === "fixtures-mlb" && row.outcome === "failure" && row.failureClass === "repeated-source-failure"));
  assert.ok(rows.some((row) => row.source === "fixtures-mlb" && row.outcome === "unknown"));
  assert.ok(rows.some((row) => row.source === "fixtures-nhl" && row.outcome === "success"));
  assert.equal(rows.some((row) => row.source === "fixtures-service" && row.outcome === "success"), false);
});

test("deployed Carabao failures have their own scope and healthy leagues cannot clear them", () => {
  const policy = createPolicy({ ...observerPolicyOptions(), windowMs: 1000, maxReceiptAgeMs: 10_000 });
  let ledger = emptyLedger(policy), key;
  for (let window = 0; window < 3; window++) {
    const now = NOW + window * 1000, body = sports(now);
    const cup = body.coverage.find((row) => row.competitionId === "carabao-cup");
    assert.ok(cup); cup.status = "unavailable"; cup.sync.consecutiveFailures = 2;
    const rows = fixtureReceipts(body, { kind: "sports", now });
    const failed = rows.find((row) => row.source === "fixtures-carabao-cup" && row.outcome === "failure");
    assert.ok(failed); key = incidentKey(failed);
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
  }
  assert.equal(ledger.incidents[key].state, "confirmed");
  for (let window = 3; window < 5; window++) {
    const now = NOW + window * 1000, body = sports(now);
    const cup = body.coverage.find((row) => row.competitionId === "carabao-cup"); cup.status = "unsupported";
    ledger = applyObservationBatch(ledger, fixtureReceipts(body, { kind: "sports", now }), policy, now).state;
  }
  assert.equal(ledger.incidents[key].state, "confirmed"); assert.equal(ledger.incidents[key].successCount, 0);
});

test("offseason and unavailable cricket do not manufacture healthy cohort recovery", () => {
  const body = cricket();
  body.coverage.find((row) => row.competitionId === "icc").status = "unavailable";
  const rows = fixtureReceipts(body, { kind: "cricket", now: NOW });
  assert.equal(rows.find((row) => row.source === "fixtures-cpl").outcome, "inactive");
  assert.equal(rows.find((row) => row.source === "fixtures-icc").outcome, "unknown");
  assert.equal(rows.some((row) => row.source === "fixtures-service" && row.outcome === "success"), false);
});

test("worker identity mismatches stop collection before fixture reads or recovery", async () => {
  for (const changes of [{ service: "other-service" }, { sourceVersion: "old-deployment" }]) {
    const stub = offlineRequest({ healthBody: health(changes) });
    const rows = await collectFixtureReceipts({ request: stub.request, now: NOW });
    assert.equal(stub.calls.length, 1);
    assert.deepEqual(rows.map((row) => [row.source, row.stage, row.outcome, row.failureClass]), [["worker", "identity", "failure", "version-mismatch"]]);
  }
});

test("one audited same-version sports response supplies optional canary context without another request", async () => {
  const body = sports(), stub = offlineRequest({ sportsBody: body }); let context;
  const rows = await collectFixtureReceipts({ request: stub.request, now: NOW, onSportsSnapshot: (value) => { context = value; } });
  assert.deepEqual(context, body); assert.ok(Array.isArray(rows)); assert.equal(stub.calls.length, 3);
  for (const options of [{ healthBody: health({ sourceVersion: "other" }) }, { sportsBody: { schemaVersion: 1, coverage: [] } },
    { healthBody: health({ sportsFixtureServiceEnabled: false }) }]) {
    const invalid = offlineRequest(options); let called = false;
    await collectFixtureReceipts({ request: invalid.request, now: NOW, onSportsSnapshot: () => { called = true; } });
    assert.equal(called, false);
  }
});

test("activation flags and staged endpoint receipts remain inactive without unnecessary reads", async () => {
  const stub = offlineRequest({ healthBody: health({ sportsFixtureServiceEnabled: false, cricketFixtureRegistryConfigured: false }) });
  const rows = await collectFixtureReceipts({ request: stub.request, now: NOW });
  assert.equal(stub.calls.length, 1);
  assert.deepEqual(rows.filter((row) => row.source === "fixtures-service").map((row) => [row.outcome, row.facts.scope]), [["inactive", "sports"], ["inactive", "cricket"]]);
  const pending = offlineRequest({ cricketBody: { activation: "pending" } });
  const pendingRows = await collectFixtureReceipts({ request: pending.request, now: NOW });
  assert.ok(pendingRows.some((row) => row.outcome === "inactive" && row.facts.scope === "cricket"));
});

test("endpoint and malformed snapshot failures retain their exact service scope", async () => {
  for (const [path, scope] of [["/api/sports/fixtures", "sports"], ["/api/cricket/fixtures", "cricket"]]) {
    const stub = offlineRequest({ failedPath: path });
    const rows = await collectFixtureReceipts({ request: stub.request, now: NOW });
    assert.ok(rows.some((row) => row.source === "fixtures-service" && row.outcome === "failure" && row.failureClass === "http-503" && row.facts.scope === scope));
    assert.ok(rows.some((row) => row.source === "fixtures-service" && row.outcome === "success" && row.facts.scope !== scope));
  }
  const malformed = offlineRequest({ cricketBody: { schemaVersion: 1, coverage: [] } });
  const rows = await collectFixtureReceipts({ request: malformed.request, now: NOW });
  assert.ok(rows.some((row) => row.outcome === "failure" && row.failureClass === "invalid-contract" && row.facts.scope === "cricket"));
});

test("fresh healthy sports snapshots cannot resolve a confirmed cricket service gap", () => {
  const policy = createPolicy({ ...observerPolicyOptions("qualification"), windowMs: 1000, maxReceiptAgeMs: 10_000 });
  let state = emptyLedger(policy), key;
  for (let window = 0; window < 3; window++) {
    const now = NOW + window * 1000, body = cricket(now);
    body.coverage.find((row) => row.competitionId === "icc").expectedFixtureCount = 1;
    const rows = fixtureReceipts(body, { kind: "cricket", now, environment: "qualification" });
    key = incidentKey(rows.find((row) => row.outcome === "failure"));
    state = applyObservationBatch(state, rows, policy, now).state;
  }
  assert.equal(state.incidents[key].state, "confirmed");
  for (let window = 3; window < 5; window++) {
    const now = NOW + window * 1000;
    state = applyObservationBatch(state, fixtureReceipts(sports(now), { kind: "sports", now, environment: "qualification" }), policy, now).state;
  }
  assert.equal(state.incidents[key].state, "confirmed");
  assert.equal(state.incidents[key].successCount, 0);
  for (let window = 5; window < 7; window++) {
    const now = NOW + window * 1000;
    state = applyObservationBatch(state, fixtureReceipts(cricket(now), { kind: "cricket", now, environment: "qualification" }), policy, now).state;
  }
  assert.equal(state.incidents[key].state, "resolved");
});
