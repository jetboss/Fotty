import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  auditCricketSnapshot,
  auditUnavailableCricketService,
  cricketMonitorIssueBody,
  cricketMonitorIssueMarker,
  cricketMonitorIssueTitle,
  failedCricketAudit,
  shouldNotifyCricketOwner,
} from "./audit-cricket-fixtures-policy.mjs";
import {
  isDedicatedCricketMonitorIssue,
  previousRunHadFailedCricketAudit,
  reportCricketAuditToGitHub,
} from "./audit-cricket-fixtures-github.mjs";
import {
  auditIndependentCricketCoverage,
  independentCurrentFixtures,
  parseIndependentCWIInternationalFixtures,
} from "./audit-cricket-fixtures-independent.mjs";

const now = Date.parse("2026-09-30T15:00:00Z");
const expectedCompetitionIds = ["cpl", "west-indies", "icc"];
const options = { now, expectedCompetitionIds };

function healthySnapshot() {
  return {
    schemaVersion: 1,
    complete: true,
    revision: "2026-09-30.cricket-audit-test",
    sourceStatus: "verified",
    checkedAt: "2026-09-30T14:55:00Z",
    sync: { consecutiveFailures: 0, lastAttemptAt: "2026-09-30T14:55:00Z", lastSuccessAt: "2026-09-30T14:55:00Z" },
    coverage: [
      { competitionId: "cpl", competitionName: "Caribbean Premier League", status: "offseason", checkedAt: "2026-09-30T14:55:00Z", fixtureCount: 0 },
      { competitionId: "west-indies", competitionName: "West Indies", status: "covered", checkedAt: "2026-09-30T14:55:00Z", fixtureCount: 1 },
      { competitionId: "icc", competitionName: "International cricket", status: "covered", checkedAt: "2026-09-30T14:55:00Z", fixtureCount: 0 },
    ],
    fixtures: [{
      id: "current-match",
      competitionId: "west-indies",
      competitionName: "West Indies",
      start: "2026-09-30T12:30:00Z",
      format: "T20",
      status: "live",
      home: { id: "west-indies", name: "West Indies" },
      away: { id: "india", name: "India" },
      source: { name: "Official fixture feed", url: "https://official.example/fixture/current", observedAt: "2026-09-30T14:55:00Z" },
    }],
  };
}

test("current fixture receipts pass without any stream-provider data", () => {
  const report = auditCricketSnapshot(healthySnapshot(), options);
  assert.equal(report.failed, false);
  assert.equal(report.fixtureCount, 1);
  assert.equal(report.activeWindowCount, 1);
  assert.deepEqual(report.findings, []);
});

test("fresh empty covered and offseason competitions do not create a missing-match alert", () => {
  const body = healthySnapshot();
  body.fixtures = [];
  body.coverage[1].fixtureCount = 0;
  assert.equal(auditCricketSnapshot(body, options).failed, false);
});

test("old finished fixtures are valid archival evidence and do not create a stale match alert", () => {
  const body = healthySnapshot();
  body.fixtures[0].status = "finished";
  body.fixtures[0].start = "2026-09-20T15:00:00Z";
  body.fixtures[0].source.observedAt = "2026-09-20T20:00:00Z";
  body.coverage[1].checkedAt = "2026-09-20T20:00:00Z";
  body.coverage[1].status = "offseason";
  assert.equal(auditCricketSnapshot(body, options).failed, false);
});

test("a fresh top-level check cannot conceal stale current-fixture observations", () => {
  const body = healthySnapshot();
  body.fixtures[0].source.observedAt = "2026-09-30T14:00:00Z";
  const report = auditCricketSnapshot(body, options);
  assert.equal(report.actionable, true);
  assert.equal(report.staleActiveCount, 1);
  assert.deepEqual(report.findings, [{ code: "stale-match-window", actionable: true }]);
});

test("a stale snapshot during an imminent scheduled match is actionable", () => {
  const body = healthySnapshot();
  body.checkedAt = body.fixtures[0].source.observedAt = "2026-09-30T14:00:00Z";
  body.fixtures[0].status = "scheduled";
  body.fixtures[0].start = "2026-09-30T15:20:00Z";
  assert.equal(auditCricketSnapshot(body, options).actionable, true);
});

test("cancelled, postponed and expired T20 fixtures are not current match evidence", () => {
  for (const status of ["cancelled", "postponed", "scheduled"]) {
    const body = healthySnapshot();
    body.fixtures[0].status = status;
    body.fixtures[0].start = "2026-09-29T15:00:00Z";
    body.fixtures[0].source.observedAt = "2026-09-29T15:00:00Z";
    assert.equal(auditCricketSnapshot(body, options).activeWindowCount, 0);
    assert.equal(auditCricketSnapshot(body, options).failed, false);
  }
});

test("unknown and Test formats require an explicit live status to count as current", () => {
  for (const format of ["unknown", "Test"]) {
    const body = healthySnapshot();
    body.fixtures[0].format = format;
    body.fixtures[0].status = "scheduled";
    assert.equal(auditCricketSnapshot(body, options).activeWindowCount, 0);
    body.fixtures[0].status = "live";
    assert.equal(auditCricketSnapshot(body, options).activeWindowCount, 1);
  }
});

test("an unknown status does not fabricate a match window from its kickoff", () => {
  const body = healthySnapshot();
  body.fixtures[0].status = "unknown";
  assert.equal(auditCricketSnapshot(body, options).activeWindowCount, 0);
});

test("a confirmed expected fixture omission alerts even when the response is structurally valid", () => {
  const body = healthySnapshot();
  body.coverage[1].expectedFixtureCount = 2;
  assert.deepEqual(auditCricketSnapshot(body, options).findings, [{ code: "coverage-gap", actionable: true }]);
});

test("unavailable coverage around a independently known kickoff is actionable", () => {
  const body = healthySnapshot();
  body.fixtures = [];
  body.coverage[1] = { ...body.coverage[1], fixtureCount: 0, status: "unavailable", checkedAt: null, nextStart: "2026-09-30T15:20:00Z" };
  assert.equal(auditCricketSnapshot(body, options).actionable, true);
});

test("one quiet-source failure waits for a repeated audit; healthy offseason does not fail", () => {
  const body = healthySnapshot();
  body.coverage[2].status = "unavailable";
  body.coverage[2].checkedAt = null;
  const report = auditCricketSnapshot(body, options);
  assert.equal(report.failed, true);
  assert.equal(report.actionable, false);
  assert.equal(shouldNotifyCricketOwner(report), false);
  assert.equal(shouldNotifyCricketOwner(report, { previousAuditFailed: true }), true);
});

test("the Worker failure streak triggers after two sync attempts", () => {
  const body = healthySnapshot();
  body.sync.consecutiveFailures = 1;
  assert.equal(auditCricketSnapshot(body, options).actionable, false);
  body.sync.consecutiveFailures = 2;
  assert.equal(auditCricketSnapshot(body, options).actionable, true);
});

test("a valid cold-start 503 receipt alerts after two failed syncs without inventing a snapshot", () => {
  const unavailable = { schemaVersion: 1, complete: false, sourceStatus: "unavailable",
    sync: { consecutiveFailures: 1, lastAttemptAt: "2026-09-30T14:55:00Z" } };
  assert.equal(auditUnavailableCricketService(unavailable, { now }).actionable, false);
  unavailable.sync.consecutiveFailures = 2;
  const report = auditUnavailableCricketService(unavailable, { now });
  assert.equal(report.actionable, true);
  assert.equal(report.fixtureCount, undefined);
  assert.deepEqual(report.findings, [{ code: "endpoint-unavailable", actionable: false }, { code: "repeated-sync-failure", actionable: true }]);
  unavailable.sync.lastAttemptAt = "2026-10-01T14:55:00Z";
  assert.throws(() => auditUnavailableCricketService(unavailable, { now }), /in the future/);
});

test("missing configured coverage and inconsistent counts are rejected", () => {
  const body = healthySnapshot();
  body.coverage.pop();
  assert.throws(() => auditCricketSnapshot(body, options), /no coverage receipt/);
  body.coverage[1].fixtureCount = 0;
  assert.throws(() => auditCricketSnapshot(body, { now }), /count disagrees/);
});

test("incomplete data, duplicate identities and ambiguous timestamps are rejected", () => {
  const incomplete = healthySnapshot();
  incomplete.complete = false;
  assert.throws(() => auditCricketSnapshot(incomplete, options), /not complete/);
  const duplicate = healthySnapshot();
  duplicate.fixtures.push(structuredClone(duplicate.fixtures[0]));
  assert.throws(() => auditCricketSnapshot(duplicate, options), /duplicated/);
  const ambiguous = healthySnapshot();
  ambiguous.fixtures[0].start = "2026-09-30T08:30:00-04:00";
  assert.throws(() => auditCricketSnapshot(ambiguous, options), /UTC timestamp/);
  ambiguous.fixtures[0].start = "2026-02-30T08:30:00Z";
  assert.throws(() => auditCricketSnapshot(ambiguous, options), /real calendar/);
});

test("future observations and stale success newer than attempt receipts are rejected", () => {
  const future = healthySnapshot();
  future.fixtures[0].source.observedAt = "2026-10-01T15:00:00Z";
  assert.throws(() => auditCricketSnapshot(future, options), /in the future/);
  const impossible = healthySnapshot();
  impossible.sync.lastSuccessAt = "2026-09-30T14:59:00Z";
  assert.throws(() => auditCricketSnapshot(impossible, options), /inconsistent/);
});

test("redacted owner issue contains only fixed findings and the GitHub run receipt", () => {
  const report = failedCricketAudit("endpoint-unavailable", now);
  report.sourceURL = "https://provider.example/private?token=never-print-me";
  report.diagnostic = "private provider diagnostics";
  const body = cricketMonitorIssueBody(report, { runURL: "https://github.com/jetboss/Fotty/actions/runs/123" });
  assert.ok(body.includes(cricketMonitorIssueMarker));
  assert.ok(body.includes("endpoint could not be reached"));
  assert.ok(!body.includes("never-print-me"));
  assert.ok(!body.includes("provider.example"));
  assert.ok(!body.includes("private provider diagnostics"));
  assert.throws(() => cricketMonitorIssueBody(report, { runURL: "https://secret@github.com/jetboss/Fotty/actions/runs/123" }), /invalid/);
});

test("only the immediately preceding monitor audit failure counts as repeated failure", () => {
  assert.equal(previousRunHadFailedCricketAudit([{ steps: [{ name: "Validate the cricket monitoring policy", conclusion: "failure" }] }]), false);
  assert.equal(previousRunHadFailedCricketAudit([{ steps: [{ name: "Record an unhealthy cricket audit: endpoint-unavailable", conclusion: "failure" }] }]), true);
  assert.equal(previousRunHadFailedCricketAudit([{ steps: [{ name: "Record an unhealthy cricket audit: endpoint-unavailable", conclusion: "skipped" }] }]), false);
});

test("deduplication cannot edit a human issue or an issue from another monitor", () => {
  const dedicated = { title: cricketMonitorIssueTitle, body: cricketMonitorIssueMarker, user: { login: "github-actions[bot]" } };
  assert.equal(isDedicatedCricketMonitorIssue(dedicated), true);
  assert.equal(isDedicatedCricketMonitorIssue({ ...dedicated, user: { login: "jetboss" } }), false);
  assert.equal(isDedicatedCricketMonitorIssue({ ...dedicated, body: "Another monitoring issue" }), false);
  assert.equal(isDedicatedCricketMonitorIssue({ ...dedicated, pull_request: {} }), false);
});

function githubContext(report, request) {
  return { report, repository: "jetboss/Fotty", token: "test-token", runId: "123", runNumber: "3", branch: "main", request };
}

test("a single endpoint failure makes no GitHub issue mutation", async () => {
  const calls = [];
  const result = await reportCricketAuditToGitHub(githubContext(failedCricketAudit("endpoint-unavailable", now), async (url, init) => {
    calls.push({ url, method: init.method });
    if (url.includes("/runs?")) return { ok: true, json: async () => ({ workflow_runs: [{ id: 122, run_number: 2 }] }) };
    return { ok: true, json: async () => ({ jobs: [{ steps: [{ name: "Record an unhealthy cricket audit: endpoint-unavailable", conclusion: "skipped" }] }] }) };
  }));
  assert.equal(result.reason, "awaiting-repeat");
  assert.ok(calls.every((call) => call.method === "GET"));
});

test("a current stale window updates the existing dedicated issue instead of creating another", async () => {
  const body = healthySnapshot();
  body.fixtures[0].source.observedAt = "2026-09-30T14:00:00Z";
  const calls = [];
  const result = await reportCricketAuditToGitHub(githubContext(auditCricketSnapshot(body, options), async (url, init) => {
    calls.push({ url, method: init.method, body: init.body });
    if (init.method === "GET") return { ok: true, json: async () => [{ number: 42, title: cricketMonitorIssueTitle, body: cricketMonitorIssueMarker, user: { login: "github-actions[bot]" } }] };
    return { ok: true, json: async () => ({ number: 42 }) };
  }));
  assert.equal(result.reason, "updated");
  assert.deepEqual(calls.map((call) => call.method), ["GET", "PATCH"]);
  assert.ok(calls[1].url.endsWith("issues/42"));
  assert.ok(!calls[1].body.includes("official.example"));
});

test("a repeated endpoint failure creates one dedicated redacted issue", async () => {
  const calls = [];
  const result = await reportCricketAuditToGitHub(githubContext(failedCricketAudit("endpoint-unavailable", now), async (url, init) => {
    calls.push({ url, method: init.method });
    let value;
    if (url.includes("/runs?")) value = { workflow_runs: [{ id: 122, run_number: 2 }, { id: 121, run_number: 1 }] };
    else if (url.includes("/jobs?")) value = { jobs: [{ steps: [{ name: "Record an unhealthy cricket audit: endpoint-unavailable", conclusion: "failure" }] }] };
    else if (init.method === "GET") value = [];
    else value = { number: 43 };
    return { ok: true, json: async () => value };
  }));
  assert.equal(result.reason, "created");
  assert.deepEqual(calls.map((call) => call.method), ["GET", "GET", "GET", "POST"]);
});

test("a different prior finding cannot turn a new transient failure into a repeated-failure alert", async () => {
  const calls = [];
  const result = await reportCricketAuditToGitHub(githubContext(failedCricketAudit("endpoint-unavailable", now), async (url, init) => {
    calls.push(init.method);
    const value = url.includes("/runs?")
      ? { workflow_runs: [{ id: 122, run_number: 2 }] }
      : { jobs: [{ steps: [{ name: "Record an unhealthy cricket audit: independent-status-disagreement", conclusion: "failure" }] }] };
    return { ok: true, json: async () => value };
  }));
  assert.equal(result.reason, "awaiting-repeat");
  assert.deepEqual(calls, ["GET", "GET"]);
});

test("healthy recovery stays silent and never automatically closes a human-reviewed issue", async () => {
  const result = await reportCricketAuditToGitHub(githubContext(auditCricketSnapshot(healthySnapshot(), options), async () => {
    assert.fail("A healthy audit must not contact the issue API.");
  }));
  assert.equal(result.reason, "healthy");
});

test("CLI hides untrusted response text while preserving a machine-readable failure receipt", async () => {
  const directory = await mkdtemp(resolve(tmpdir(), "fotty-cricket-audit-test-"));
  try {
    const fixturePath = resolve(directory, "fixture.json");
    const reportPath = resolve(directory, "report.json");
    await writeFile(fixturePath, JSON.stringify({ diagnostic: "https://provider.example/private?token=never-print-me" }));
    const scriptPath = fileURLToPath(new URL("./audit-cricket-fixtures.mjs", import.meta.url));
    const result = spawnSync(process.execPath, [scriptPath, `--fixture-file=${fixturePath}`, `--output=${reportPath}`, "--at=2026-09-30T15:00:00Z"], { encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.ok(!`${result.stdout}${result.stderr}`.includes("never-print-me"));
    assert.deepEqual(JSON.parse(await readFile(reportPath, "utf8")).findings, [{ code: "invalid-contract", actionable: false }]);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

function cwiFixture({ id = "18dbf036-8619-4610-abbc-2ea9b4725320", home = "India", away = "West Indies", time = "08:30 AST (12:30 UTC)", title = "2nd T20I", live = true } = {}) {
  return `<div class="wi-fixture">
    <div class="wi-fixture-section-intro"><div class="wi-fixture-title">${title}</div>
      <div class="wi-fixture-time"><svg></svg><div class="wi-fixture-time-inner">${time}</div></div>
    </div>
    <div class="wi-fixture-section-teams"><div class="wi-fixture-team first"><div class="wi-fixture-team-name">${home}</div></div>
      <div class="wi-fixture-team last"><div class="wi-fixture-team-name">${away}</div></div></div>
    ${live ? '<a class="button wi-fixture-live"><div class="wi-fixture-live-text">Live</div></a>' : ""}
    <a href="https://matchcentre.windiescricket.com/match/${id}">Match Centre</a>
  </div>`;
}

const cwiDate = "<h3><span>Wed 30 Sep</span> 2026</h3>";

test("independent CWI parser handles nested divs, repeated links and multiple fixtures per date", () => {
  const html = cwiDate + cwiFixture()
    + cwiFixture({ id: "a93a9f6f-77bc-4487-9f00-71e7958adf25", home: "Zimbabwe Women", away: "West Indies Women", live: false });
  const fixtures = parseIndependentCWIInternationalFixtures(html);
  assert.equal(fixtures.length, 2);
  assert.equal(fixtures[0].start, "2026-09-30T12:30:00.000Z");
  assert.equal(fixtures[0].format, "T20");
  assert.equal(fixtures[0].status, "live");
  assert.equal(fixtures[1].status, "scheduled");
  assert.equal(fixtures[1].away.name, "West Indies Women");
});

test("cross-midnight fixtures fail closed until the independent calendar-heading timezone is documented", () => {
  assert.throws(() => parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture({ time: "21:30 AST (01:30 UTC)" })), /timezone is ambiguous/);
});

test("independent malformed UTC offsets, weekday mismatches and incomplete rows fail closed", () => {
  assert.throws(() => parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture({ time: "08:30 AST (08:30 UTC)" })), /clocks disagree/);
  assert.throws(() => parseIndependentCWIInternationalFixtures(cwiDate.replace("Wed", "Tue") + cwiFixture()), /calendar date/);
  assert.throws(() => parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture().replace('class="wi-fixture-team-name">India', 'class="changed">India')), /incomplete or ambiguous/);
  assert.throws(() => parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture() + cwiFixture()), /duplicated/);
});

test("genuine reviewed CWI empty-state structure passes while an arbitrary empty page does not", () => {
  assert.deepEqual(parseIndependentCWIInternationalFixtures('<body class="template-fixturesindexpage"><main><div class="row wi-fixtures">\n\n</div></main></body>'), []);
  assert.throws(() => parseIndependentCWIInternationalFixtures("<html><body>Temporary service error</body></html>"), /not recognized/);
  assert.throws(() => parseIndependentCWIInternationalFixtures('<div class="row wi-fixtures"></div>'), /not recognized/);
});

test("independent live fixture omissions are detected in a structurally healthy empty snapshot", () => {
  const body = healthySnapshot();
  body.fixtures = [];
  body.coverage[1].fixtureCount = 0;
  assert.equal(auditCricketSnapshot(body, options).failed, false);
  const independent = parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture());
  assert.deepEqual(auditIndependentCricketCoverage(body, independent, { now }).findings, [{ code: "independent-current-omission", actionable: true }]);
});

test("independent identity matching preserves women while accepting reversed team order and known aliases", () => {
  const body = healthySnapshot();
  body.fixtures[0].home.name = "WI";
  body.fixtures[0].away.name = "IND";
  const independent = parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture());
  const matched = auditIndependentCricketCoverage(body, independent, { now });
  assert.equal(matched.matchedCurrentCount, 1);
  assert.deepEqual(matched.findings, []);
  independent[0].home.name = "India Women";
  independent[0].away.name = "West Indies Women";
  assert.deepEqual(auditIndependentCricketCoverage(body, independent, { now }).findings, [{ code: "independent-current-omission", actionable: true }]);
});

test("independent disagreement alerts without changing stored fixture time or status", () => {
  const body = healthySnapshot();
  const independent = parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture());
  body.fixtures[0].start = "2026-09-30T13:00:00Z";
  body.fixtures[0].status = "finished";
  const prior = JSON.stringify(body);
  assert.deepEqual(auditIndependentCricketCoverage(body, independent, { now }).findings, [
    { code: "independent-kickoff-disagreement", actionable: true },
    { code: "independent-status-disagreement", actionable: false },
  ]);
  assert.equal(JSON.stringify(body), prior);
});

test("an independent quiet schedule does not manufacture current matches from next week's fixtures", () => {
  const independent = parseIndependentCWIInternationalFixtures("<h3><span>Sat 03 Oct</span> 2026</h3>" + cwiFixture({ live: false }));
  assert.deepEqual(independentCurrentFixtures(independent, now), []);
  assert.deepEqual(auditIndependentCricketCoverage(healthySnapshot(), independent, { now }).findings, []);
});

test("independent sources must state live for a Test fixture rather than assuming a five-day window", () => {
  const independent = parseIndependentCWIInternationalFixtures(cwiDate + cwiFixture({ title: "1st Test", live: false }));
  assert.deepEqual(independentCurrentFixtures(independent, now), []);
  independent[0].status = "live";
  assert.equal(independentCurrentFixtures(independent, now).length, 1);
});
