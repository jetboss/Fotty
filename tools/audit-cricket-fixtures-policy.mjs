const minute = 60_000;
const hour = 60 * minute;
const sourceStatuses = new Set(["verified", "partial", "last-known-good", "unavailable"]);
const coverageStatuses = new Set(["covered", "offseason", "unavailable"]);
const fixtureStatuses = new Set(["scheduled", "live", "finished", "cancelled", "postponed", "unknown"]);
const formats = new Set(["T10", "T20", "ODI", "TEST", "UNKNOWN"]);
const estimatedWindows = Object.freeze({ T10: 4 * hour, T20: 8 * hour, ODI: 12 * hour });

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function boundedText(value, maximum = 256) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= maximum;
}

function utcTime(value, label, { optional = false } = {}) {
  if (optional && value == null) return null;
  requireValue(typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value), `${label} must be a UTC timestamp.`);
  const timestamp = Date.parse(value);
  requireValue(Number.isFinite(timestamp), `${label} must be a valid timestamp.`);
  requireValue(new Date(timestamp).toISOString().slice(0, 19) === value.slice(0, 19), `${label} must be a real calendar timestamp.`);
  return timestamp;
}

function checkedTime(value, label, now, options) {
  const timestamp = utcTime(value, label, options);
  requireValue(timestamp === null || timestamp <= now + 5 * minute, `${label} is in the future.`);
  return timestamp;
}

function validTeam(team) {
  return team && typeof team === "object" && boundedText(team.id) && boundedText(team.name);
}

// Fixture identity is deliberately independent of provider channels or stream availability.
export function validateCricketSnapshot(body, { now = Date.now(), expectedCompetitionIds = [] } = {}) {
  requireValue(Number.isFinite(now), "The audit clock is invalid.");
  requireValue(body && typeof body === "object" && !Array.isArray(body), "The cricket service must return an object.");
  requireValue(body.schemaVersion === 1, "The cricket schema version is unsupported.");
  requireValue(body.complete === true, "The cricket snapshot is not complete.");
  requireValue(boundedText(body.revision), "The cricket revision is missing.");
  requireValue(sourceStatuses.has(body.sourceStatus) && body.sourceStatus !== "unavailable", "The cricket source status is invalid.");
  const checkedAt = checkedTime(body.checkedAt, "Snapshot checkedAt", now);
  requireValue(Array.isArray(body.fixtures) && body.fixtures.length <= 2_000, "The cricket fixture list is invalid.");
  requireValue(Array.isArray(body.coverage) && body.coverage.length > 0 && body.coverage.length <= 100, "The cricket coverage list is invalid.");
  requireValue(body.sync && typeof body.sync === "object", "The cricket sync receipt is missing.");
  requireValue(Number.isSafeInteger(body.sync.consecutiveFailures) && body.sync.consecutiveFailures >= 0, "The cricket sync failure count is invalid.");
  const lastAttemptAt = checkedTime(body.sync.lastAttemptAt, "Sync lastAttemptAt", now);
  const lastSuccessAt = checkedTime(body.sync.lastSuccessAt, "Sync lastSuccessAt", now, { optional: true });
  requireValue(lastSuccessAt === null || lastSuccessAt <= lastAttemptAt, "The cricket sync receipt is inconsistent.");

  const coverageById = new Map();
  for (const row of body.coverage) {
    requireValue(row && boundedText(row.competitionId) && boundedText(row.competitionName), "A cricket coverage identity is invalid.");
    requireValue(!coverageById.has(row.competitionId), "A cricket competition has duplicate coverage.");
    requireValue(coverageStatuses.has(row.status), "A cricket coverage status is invalid.");
    requireValue(Number.isSafeInteger(row.fixtureCount) && row.fixtureCount >= 0, "A cricket coverage count is invalid.");
    requireValue(row.expectedFixtureCount == null || (Number.isSafeInteger(row.expectedFixtureCount) && row.expectedFixtureCount >= 0), "A cricket expected fixture count is invalid.");
    const observedAt = checkedTime(row.checkedAt, "Coverage checkedAt", now, { optional: row.status === "unavailable" });
    const nextStart = utcTime(row.nextStart, "Coverage nextStart", { optional: true });
    coverageById.set(row.competitionId, { ...row, observedAt, nextStart, actualCount: 0 });
  }
  for (const id of expectedCompetitionIds) {
    requireValue(coverageById.has(id), "A configured cricket competition has no coverage receipt.");
  }

  const fixtureIds = new Set();
  const fixtures = body.fixtures.map((row) => {
    requireValue(row && boundedText(row.id) && !fixtureIds.has(row.id), "A cricket fixture identity is invalid or duplicated.");
    fixtureIds.add(row.id);
    requireValue(boundedText(row.competitionId) && boundedText(row.competitionName), "A cricket fixture competition is invalid.");
    const coverage = coverageById.get(row.competitionId);
    requireValue(coverage, "A cricket fixture has no competition coverage receipt.");
    requireValue(validTeam(row.home) && validTeam(row.away) && row.home.id !== row.away.id, "A cricket fixture has invalid team identities.");
    requireValue(fixtureStatuses.has(row.status), "A cricket fixture status is invalid.");
    const format = String(row.format || "").toUpperCase();
    requireValue(formats.has(format), "A cricket fixture format is invalid.");
    const startAt = utcTime(row.start, "Fixture start");
    requireValue(row.source && boundedText(row.source.name) && boundedText(row.source.url, 2_048), "A cricket source receipt is missing.");
    let sourceURL;
    try { sourceURL = new URL(row.source.url); } catch { throw new Error("A cricket source URL is invalid."); }
    requireValue(sourceURL.protocol === "https:" && !sourceURL.username && !sourceURL.password, "A cricket source URL is invalid.");
    const observedAt = checkedTime(row.source.observedAt, "Source observedAt", now);
    requireValue(observedAt <= checkedAt + 5 * minute, "A cricket source receipt is newer than its snapshot.");
    coverage.actualCount += 1;
    return { status: row.status, format, startAt, observedAt, competitionId: row.competitionId };
  });
  for (const row of coverageById.values()) {
    requireValue(row.fixtureCount === row.actualCount, "A cricket coverage count disagrees with its fixture list.");
    requireValue(row.status !== "offseason" || !fixtures.some((fixture) => fixture.competitionId === row.competitionId
      && (fixture.status === "live" || (fixture.status === "scheduled" && fixture.startAt >= now))), "An offseason competition contains an active or future fixture.");
  }
  return { checkedAt, fixtures, coverage: [...coverageById.values()], sourceStatus: body.sourceStatus, sync: { ...body.sync, lastAttemptAt, lastSuccessAt } };
}

function inMatchWindow(fixture, now) {
  if (["finished", "cancelled", "postponed"].includes(fixture.status)) return false;
  if (fixture.status === "live") return true;
  if (fixture.status !== "scheduled") return false;
  const window = estimatedWindows[fixture.format];
  // Test/unknown-format schedules do not provide enough evidence to invent an end.
  return window !== undefined && fixture.startAt >= now - window && fixture.startAt <= now + 30 * minute;
}

export function auditCricketSnapshot(body, { now = Date.now(), expectedCompetitionIds = [] } = {}) {
  const snapshot = validateCricketSnapshot(body, { now, expectedCompetitionIds });
  const findings = [];
  const addFinding = (code, actionable) => findings.push({ code, actionable });
  const active = snapshot.fixtures.filter((row) => inMatchWindow(row, now));
  const activeCompetitions = new Set(active.map((row) => row.competitionId));
  const staleActive = active.filter((row) => now - row.observedAt > 30 * minute);
  if (active.length > 0 && (now - snapshot.checkedAt > 30 * minute || staleActive.length > 0)) {
    addFinding("stale-match-window", true);
  }
  if (snapshot.sync.consecutiveFailures >= 2) addFinding("repeated-sync-failure", true);
  else if (snapshot.sync.consecutiveFailures === 1) addFinding("single-sync-failure", false);

  for (const row of snapshot.coverage) {
    const missingExpected = row.expectedFixtureCount != null && row.expectedFixtureCount > row.actualCount;
    const imminentKnown = row.nextStart !== null && row.nextStart >= now - 12 * hour && row.nextStart <= now + 30 * minute;
    if (missingExpected || (row.status === "unavailable" && (activeCompetitions.has(row.competitionId) || imminentKnown))) {
      addFinding("coverage-gap", true);
    } else if (row.status === "unavailable") {
      addFinding("coverage-unavailable", false);
    }
    if ((activeCompetitions.has(row.competitionId) || imminentKnown) && row.observedAt !== null && now - row.observedAt > 30 * minute) {
      addFinding("stale-competition-window", true);
    }
  }
  const distinctFindings = [...new Map(findings.map((finding) => [finding.code, finding])).values()];
  return {
    version: 1,
    checkedAt: new Date(now).toISOString(),
    failed: distinctFindings.length > 0,
    actionable: distinctFindings.some((finding) => finding.actionable),
    sourceStatus: snapshot.sourceStatus,
    fixtureCount: snapshot.fixtures.length,
    competitionCount: snapshot.coverage.length,
    activeWindowCount: active.length,
    staleActiveCount: staleActive.length,
    syncFailureCount: snapshot.sync.consecutiveFailures,
    findings: distinctFindings,
  };
}

export function failedCricketAudit(code, now = Date.now()) {
  const allowed = new Set(["endpoint-unavailable", "invalid-contract", "invalid-json", "response-too-large"]);
  requireValue(allowed.has(code), "An audit failure code is invalid.");
  return {
    version: 1,
    checkedAt: new Date(now).toISOString(),
    failed: true,
    actionable: false,
    findings: [{ code, actionable: false }],
  };
}

export function auditUnavailableCricketService(body, { now = Date.now() } = {}) {
  requireValue(body && body.schemaVersion === 1 && body.complete === false && body.sourceStatus === "unavailable",
    "The unavailable cricket service receipt is invalid.");
  requireValue(body.sync && Number.isSafeInteger(body.sync.consecutiveFailures) && body.sync.consecutiveFailures >= 0,
    "The unavailable cricket sync failure count is invalid.");
  checkedTime(body.sync.lastAttemptAt, "Unavailable sync lastAttemptAt", now);
  const report = failedCricketAudit("endpoint-unavailable", now);
  report.syncFailureCount = body.sync.consecutiveFailures;
  if (body.sync.consecutiveFailures >= 2) {
    report.findings.push({ code: "repeated-sync-failure", actionable: true });
    report.actionable = true;
  }
  return report;
}

export const cricketAuditFindingMessages = Object.freeze({
  "stale-match-window": "Fixture observations are more than 30 minutes old during a current or imminent match window.",
  "stale-competition-window": "Competition coverage is more than 30 minutes old during a current or imminent match window.",
  "repeated-sync-failure": "The Worker reports at least two consecutive fixture sync failures.",
  "single-sync-failure": "The Worker reports one fixture sync failure; a repeated failure will notify the owner.",
  "coverage-gap": "A supported competition has a confirmed coverage gap or unavailable coverage during a known match window.",
  "coverage-unavailable": "A competition source is unavailable outside a known match window; a repeated failure will notify the owner.",
  "endpoint-unavailable": "The cricket fixture endpoint could not be reached or did not return a successful response.",
  "invalid-contract": "The cricket fixture response failed snapshot identity, coverage or receipt validation.",
  "invalid-json": "The cricket fixture endpoint returned invalid JSON.",
  "response-too-large": "The cricket fixture response exceeded the monitor's size limit.",
  "independent-check-unavailable": "The independent official cricket schedule could not be verified; a repeated failure will notify the owner.",
  "independent-current-omission": "An independently listed current or imminent international fixture is missing from the Worker snapshot.",
  "independent-kickoff-disagreement": "The Worker and the independent official schedule disagree on a current fixture's UTC kickoff by more than 15 minutes.",
  "independent-status-disagreement": "The independent official schedule marks a fixture live while the Worker reports another status; a repeated disagreement will notify the owner.",
});

export const cricketMonitorIssueTitle = "[Fotty] Cricket fixture service requires attention";
export const cricketMonitorIssueMarker = "<!-- fotty-cricket-fixture-monitor:v1 -->";

export function shouldNotifyCricketOwner(report, { previousAuditFailed = false } = {}) {
  return report.failed === true && (report.actionable === true || previousAuditFailed === true);
}

export function cricketMonitorIssueBody(report, { runURL }) {
  requireValue(report.version === 1 && report.failed === true && Array.isArray(report.findings), "The owner report is invalid.");
  const run = new URL(runURL);
  requireValue(run.protocol === "https:" && run.hostname === "github.com"
    && !run.username && !run.password && !run.port
    && /^\/[^/]+\/[^/]+\/actions\/runs\/\d+$/.test(run.pathname) && !run.search && !run.hash,
  "The owner report run URL is invalid.");
  const observed = utcTime(report.checkedAt, "Audit checkedAt");
  const messages = [...new Set(report.findings.map((finding) => {
    requireValue(Object.hasOwn(cricketAuditFindingMessages, finding.code), "The owner report finding is invalid.");
    return cricketAuditFindingMessages[finding.code];
  }))];
  return `${cricketMonitorIssueMarker}\n\nThe hourly fixture monitor found a current match-window problem or a repeated service failure.\n\n`
    + `Checked: ${new Date(observed).toISOString()}\n\n`
    + messages.map((message) => `- ${message}`).join("\n")
    + `\n\n[Inspect the monitor run](${run.href}).\n\n`
    + "This concerns fixture identity, coverage and freshness. Stream-provider reachability is not a fixture-health signal. "
    + "The monitor does not change fixture data, deploy code or merge changes. Review the recovery before closing this issue.\n";
}
