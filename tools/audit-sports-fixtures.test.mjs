import test from "node:test";
import assert from "node:assert/strict";
import { auditSportsSnapshot, failedSportsAudit, sportsMonitorIssueBody } from "./audit-sports-fixtures-policy.mjs";
import { isDedicatedSportsIssue, previousSportsFindingKeys, reportSportsAuditToGitHub, sportsFindingKey } from "./audit-sports-fixtures-github.mjs";
import { assembleSportsSnapshot } from "../web/workers/playback/src/sports-fixture-registry.mjs";

const now = Date.parse("2026-09-30T22:00:00.000Z");
const descriptor = { id: "nba", sport: "basketball", supported: true, competitions: [{ id: "nba", name: "NBA" }] };
async function snapshot() {
  const fixture = { id: "sports-fixture:nba:1", sport: "basketball", competitionId: "nba", competitionName: "NBA", eventKind: "match",
    title: "Alpha vs Beta", start: "2026-09-30T21:00:00.000Z", status: "live", participants: [{ id: "1", name: "Alpha" }, { id: "2", name: "Beta" }],
    squad: { gender: "men", ageGroup: "senior" }, source: { name: "ESPN", url: "https://www.espn.com/nba/scoreboard", observedAt: new Date(now).toISOString() } };
  return assembleSportsSnapshot([descriptor], new Map([["nba", { accepted: { fixtures: [fixture], observedAt: new Date(now).toISOString(), pendingFixtureCount: 0 }, consecutiveFailures: 0 }]]), new Date(now));
}
test("healthy receipts are quiet and count coverage exactly", async () => {
  const body = await snapshot();
  assert.equal(auditSportsSnapshot(body, { now, descriptors: [descriptor] }).failed, false);
  body.coverage[0].fixtureCount++;
  assert.throws(() => auditSportsSnapshot(body, { now }));
});
test("isolated sports receipts retain cohort failures while counting only admitted fresh live rows", async () => {
  const body = await snapshot();
  body.sourceStatus = "partial";
  body.coverage[0].status = "unavailable";
  body.coverage[0].checkedAt = new Date(now - 4 * 60 * 60_000).toISOString();
  body.coverage[0].sync = { consecutiveFailures: 2, conflict: true };
  body.fixtures[0].source.verification = "verified";
  const report = auditSportsSnapshot(body, { now });
  assert.equal(report.verifiedFixtureCount, 1);
  assert.equal(report.heldFixtureCount, 0);
  assert.equal(report.freshVerifiedLiveCount, 1);
  assert.deepEqual(new Set(report.findings.map((row) => row.code)), new Set(["repeated-source-failure", "unconfirmed-correction"]));
  body.fixtures[0].source.verification = "held";
  body.fixtures[0].source.observedAt = body.coverage[0].checkedAt;
  const held = auditSportsSnapshot(body, { now });
  assert.equal(held.verifiedFixtureCount, 0);
  assert.equal(held.heldFixtureCount, 1);
  assert.equal(held.freshVerifiedLiveCount, 0);
  assert.ok(held.findings.some((finding) => finding.code === "stale-live-evidence"));
});
test("sports marker validation rejects null, unknown and covered holds while keeping legacy receipts compatible", async () => {
  const body = await snapshot();
  assert.equal(auditSportsSnapshot(body, { now }).verifiedFixtureCount, 1);
  for (const marker of [null, "unknown", "held"]) {
    body.fixtures[0].source.verification = marker;
    assert.throws(() => auditSportsSnapshot(body, { now }));
  }
  body.fixtures[0].source.verification = "verified";
  assert.equal(auditSportsSnapshot(body, { now }).freshVerifiedLiveCount, 1);
  body.sourceStatus = "last-known-good";
  assert.equal(auditSportsSnapshot(body, { now }).freshVerifiedLiveCount, 0);
  assert.equal(auditSportsSnapshot(body, { now }).verifiedFixtureCount, 0);
  body.sourceStatus = "partial"; body.coverage[0].status = "unavailable";
  body.fixtures[0].source.verification = "verified";
  body.checkedAt = new Date(now - 60_000).toISOString();
  assert.throws(() => auditSportsSnapshot(body, { now }));
  body.checkedAt = new Date(now).toISOString();
  delete body.fixtures[0].source.verification;
  assert.equal(auditSportsSnapshot(body, { now }).verifiedFixtureCount, 0);
  body.coverage[0].checkedAt = new Date(now - 60_000).toISOString();
  assert.throws(() => auditSportsSnapshot(body, { now }));
});
test("stale live evidence, repeated failures and conflicts are actionable", async () => {
  const body = await snapshot();
  const old = new Date(now - 31 * 60_000).toISOString();
  body.coverage[0].checkedAt = old; body.fixtures[0].source.observedAt = old;
  body.coverage[0].sync = { consecutiveFailures: 2, conflict: true };
  const report = auditSportsSnapshot(body, { now });
  assert.equal(report.actionable, true);
  assert.deepEqual(new Set(report.findings.map((row) => row.code)), new Set(["stale-live-evidence", "repeated-source-failure", "unconfirmed-correction"]));
});
test("missing source scope is not an empty healthy league", async () => {
  const report = auditSportsSnapshot(await snapshot(), { now, descriptors: [{ ...descriptor, competitions: [{ id: "wnba", name: "WNBA" }] }] });
  assert.equal(report.findings[0].code, "missing-coverage");
});
test("unsupported reviewed scope is explicit and quiet", async () => {
  const body = await snapshot();
  body.coverage.push({ sport: "darts", competitionId: "pdc", competitionName: "PDC", status: "unsupported", checkedAt: null, fixtureCount: 0, pendingFixtureCount: 0, sync: { consecutiveFailures: 0 } });
  assert.equal(auditSportsSnapshot(body, { now }).failed, false);
  assert.equal(auditSportsSnapshot(body, { now }).unsupportedCount, 1);
});
test("unrelated source failures do not establish repetition", () => {
  const keys = previousSportsFindingKeys([{ steps: [{ name: "Install tools", conclusion: "failure" },
    { name: "Record an unhealthy sports audit: source-unavailable@wnba", conclusion: "failure" }] }]);
  assert.deepEqual(keys, ["source-unavailable@wnba"]);
  assert.equal(keys.includes(sportsFindingKey({ code: "source-unavailable", competitionId: "nba" })), false);
});
test("comparison repetition requires the same validated event facts, not only the league", () => {
  const finding = { code: "same-upstream-fixture-disagreement", competitionId: "mlb", evidenceKey: "a".repeat(64) };
  const key = sportsFindingKey(finding);
  const keys = previousSportsFindingKeys([{ steps: [{ name: `Record an unhealthy sports audit: ${key}`, conclusion: "failure" }] }]);
  assert.deepEqual(keys, [key]);
  assert.equal(keys.includes(sportsFindingKey({ ...finding, evidenceKey: "b".repeat(64) })), false);
  assert.throws(() => sportsFindingKey({ ...finding, evidenceKey: "unsafe value" }));
  assert.throws(() => sportsFindingKey({ code: "same-upstream-current-omission", competitionId: "mlb" }));
  assert.throws(() => sportsFindingKey({ code: "same-upstream-refresh-required", competitionId: "mlb" }));
  assert.deepEqual(previousSportsFindingKeys([{ steps: [{ name: `Record an unhealthy sports audit: ${key}:extra`, conclusion: "failure" }] }]), []);
});
test("refresh-required alerts escalate only an identical immediately preceding fact digest", async () => {
  const finding = { code: "same-upstream-refresh-required", competitionId: "mlb", actionable: false, evidenceKey: "a".repeat(64) };
  const key = sportsFindingKey(finding);
  const report = { version: 1, checkedAt: new Date(now).toISOString(), failed: true, actionable: false, findings: [finding] };
  const context = { report, repository: "jetboss/Fotty", token: "synthetic", runId: "123", runNumber: "2", branch: "main" };
  for (const previousKey of [key, sportsFindingKey({ ...finding, evidenceKey: "b".repeat(64) })]) {
    const methods = [];
    const result = await reportSportsAuditToGitHub({ ...context, request: async (url, init) => {
      methods.push(init.method);
      if (url.includes("/actions/workflows/")) return Response.json({ workflow_runs: [{ id: 122, run_number: 1 }] });
      if (url.includes("/actions/runs/122/jobs")) return Response.json({ jobs: [{ steps: [
        { name: `Record an unhealthy sports audit: ${previousKey}`, conclusion: "failure" },
      ] }] });
      if (init.method === "GET" && url.includes("/issues?")) return Response.json([]);
      if (init.method === "POST" && url.endsWith("/issues")) return Response.json({ number: 1 });
      throw new Error("Unexpected offline request");
    } });
    assert.equal(result.notified, previousKey === key);
    assert.equal(methods.includes("POST"), previousKey === key);
  }
});
test("issue body accepts fixed findings only and keeps private text out", () => {
  const report = failedSportsAudit("endpoint-unavailable", now);
  const body = sportsMonitorIssueBody(report, "https://github.com/jetboss/Fotty/actions/runs/123");
  assert.equal(body.includes("<!-- fotty-sports-fixture-monitor:v1 -->"), true);
  assert.throws(() => sportsMonitorIssueBody({ ...report, findings: [{ code: "private source URL" }] }, "https://github.com/jetboss/Fotty/actions/runs/123"));
  assert.throws(() => sportsMonitorIssueBody(report, "https://github.com/jetboss/Fotty/actions/runs/123?token=private"));
});
test("only dedicated bot issues are eligible", () => {
  const issue = { title: "[Fotty] Sports fixture service requires attention", body: "<!-- fotty-sports-fixture-monitor:v1 -->", user: { login: "github-actions[bot]" } };
  assert.equal(isDedicatedSportsIssue(issue), true);
  assert.equal(isDedicatedSportsIssue({ ...issue, user: { login: "owner" } }), false);
  assert.equal(isDedicatedSportsIssue({ ...issue, pull_request: {} }), false);
});
test("healthy and pending reports make no GitHub calls", async () => {
  let calls = 0;
  const request = async () => { calls++; throw new Error("unexpected request"); };
  const result = await reportSportsAuditToGitHub({ report: { failed: false, activation: "pending" }, request });
  assert.equal(result.notified, false); assert.equal(calls, 0);
});
