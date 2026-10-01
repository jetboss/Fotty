import { descriptorCompetitions, fixtureInstant } from "../web/workers/playback/src/sports-fixture-policy.mjs";

const MINUTE = 60_000;
const allowedStatuses = new Set(["scheduled", "live", "finished", "cancelled", "postponed", "unknown"]);
export const sportsMonitorIssueTitle = "[Fotty] Sports fixture service requires attention";
export const sportsMonitorIssueMarker = "<!-- fotty-sports-fixture-monitor:v1 -->";
export const sportsAuditFindingMessages = Object.freeze({
  "endpoint-unavailable": "The sports fixture service is unreachable or unavailable.",
  "invalid-contract": "The fixture snapshot has an invalid identity, coverage count, or receipt.",
  "stale-live-evidence": "A currently live or imminent fixture has a source receipt more than 30 minutes old.",
  "repeated-source-failure": "A schedule source has failed at least two consecutive refresh attempts.",
  "unconfirmed-correction": "An accepted fixture conflicts with a current source observation; the old facts remain retained.",
  "missing-coverage": "A configured competition has no coverage receipt.",
  "source-unavailable": "A schedule source has no accepted current snapshot.",
  "quiet-source-stale": "A source has not refreshed within its four-hour quiet-period allowance.",
  "same-upstream-current-omission": "A newly fetched league schedule contains a current or imminent fixture missing from accepted coverage.",
  "same-upstream-fixture-disagreement": "The accepted fixture and a newly fetched league schedule disagree on identity, time or status; repeat verification is required.",
  "comparison-source-unavailable": "The bounded league-schedule comparison could not obtain complete source evidence.",
  "comparison-receipt-stale": "The league-schedule comparison returned stale evidence; it cannot establish an omission.",
});
function requireValue(value) { if (!value) throw new Error("Invalid sports snapshot"); }
export function failedSportsAudit(code, now = Date.now()) {
  requireValue(Object.hasOwn(sportsAuditFindingMessages, code));
  return { version: 1, checkedAt: new Date(now).toISOString(), failed: true, actionable: false, findings: [{ code, actionable: false }] };
}

export function auditSportsSnapshot(body, { now = Date.now(), descriptors = [] } = {}) {
  requireValue(body?.schemaVersion === 1 && body.complete === true && ["verified", "partial", "last-known-good"].includes(body.sourceStatus)
    && typeof body.revision === "string" && body.revision.length > 0 && body.revision.length <= 128);
  requireValue(fixtureInstant(body.checkedAt) <= now + 5 * MINUTE && Array.isArray(body.fixtures) && body.fixtures.length <= 3000
    && Array.isArray(body.coverage) && body.coverage.length > 0 && body.coverage.length <= 100);
  const findings = new Map();
  const add = (code, actionable, competitionId) => {
    const key = `${code}:${competitionId || "service"}`;
    findings.set(key, { code, actionable, ...(competitionId ? { competitionId } : {}) });
  };
  const coverage = new Map();
  for (const row of body.coverage) {
    requireValue(row && typeof row.competitionId === "string" && !coverage.has(row.competitionId)
      && ["covered", "unavailable", "unsupported"].includes(row.status) && Number.isInteger(row.fixtureCount) && row.fixtureCount >= 0
      && Number.isInteger(row.pendingFixtureCount) && row.pendingFixtureCount >= 0);
    requireValue(row.checkedAt === null || fixtureInstant(row.checkedAt) <= now + 5 * MINUTE);
    requireValue(row.status !== "covered" || row.checkedAt !== null);
    requireValue(row.sync && Number.isInteger(row.sync.consecutiveFailures) && row.sync.consecutiveFailures >= 0);
    coverage.set(row.competitionId, { ...row, actualCount: 0 });
    if (row.status === "unsupported") continue; // Explicit reviewed gaps are not new incidents.
    if (row.sync.conflict) add("unconfirmed-correction", true, row.competitionId);
    if (row.sync.consecutiveFailures >= 2) add("repeated-source-failure", true, row.competitionId);
    else if (row.status === "unavailable") add("source-unavailable", false, row.competitionId);
    if (row.checkedAt && now - fixtureInstant(row.checkedAt) > 4 * 60 * MINUTE + 30 * MINUTE) add("quiet-source-stale", true, row.competitionId);
  }
  for (const descriptor of descriptors) for (const competition of descriptorCompetitions(descriptor)) {
    if (!coverage.has(competition.id)) add("missing-coverage", true, competition.id);
  }
  const ids = new Set(); let liveCount = 0;
  for (const fixture of body.fixtures) {
    requireValue(fixture && typeof fixture.id === "string" && fixture.id.startsWith(`sports-fixture:${fixture.competitionId}:`) && !ids.has(fixture.id)
      && allowedStatuses.has(fixture.status) && ["match", "session", "tournament", "card"].includes(fixture.eventKind));
    ids.add(fixture.id);
    const row = coverage.get(fixture.competitionId);
    requireValue(row && row.status !== "unsupported" && row.sport === fixture.sport && row.competitionName === fixture.competitionName
      && Array.isArray(fixture.participants) && (fixture.eventKind !== "match" || fixture.participants.length === 2));
    requireValue(fixture.participants.every((participant) => typeof participant.id === "string" && participant.id.length > 0
      && typeof participant.name === "string" && participant.name.length > 0));
    requireValue(new Set(fixture.participants.map((participant) => participant.id)).size === fixture.participants.length);
    const start = fixtureInstant(fixture.start), observedAt = fixtureInstant(fixture.source?.observedAt);
    requireValue(observedAt <= now + 5 * MINUTE && row.checkedAt && observedAt === fixtureInstant(row.checkedAt));
    const active = fixture.status === "live" || fixture.status === "scheduled" && start >= now - 4 * 60 * MINUTE && start <= now + 30 * MINUTE;
    if (fixture.status === "live") liveCount++;
    if (active && now - observedAt > 30 * MINUTE) add("stale-live-evidence", true, fixture.competitionId);
    if (fixture.source.updatedAt && fixture.status === "live" && now - fixtureInstant(fixture.source.updatedAt) > 30 * MINUTE) add("stale-live-evidence", true, fixture.competitionId);
    row.actualCount++;
  }
  for (const row of coverage.values()) requireValue(row.actualCount === row.fixtureCount);
  const values = [...findings.values()];
  return { version: 1, checkedAt: new Date(now).toISOString(), failed: values.length > 0, actionable: values.some((finding) => finding.actionable),
    fixtureCount: body.fixtures.length, competitionCount: coverage.size, liveCount,
    unsupportedCount: body.coverage.filter((row) => row.status === "unsupported").length, findings: values };
}

export function sportsMonitorIssueBody(report, runURL) {
  const url = new URL(runURL);
  requireValue(url.protocol === "https:" && url.hostname === "github.com" && !url.username && !url.password && !url.search && !url.hash
    && /^\/[^/]+\/[^/]+\/actions\/runs\/\d+$/.test(url.pathname));
  requireValue(report.version === 1 && report.failed && Array.isArray(report.findings));
  const messages = [...new Set(report.findings.map((finding) => { requireValue(Object.hasOwn(sportsAuditFindingMessages, finding.code)); return sportsAuditFindingMessages[finding.code]; }))];
  return `${sportsMonitorIssueMarker}\n\nThe fixture monitor found an actionable or repeated schedule problem.\n\nChecked: ${new Date(fixtureInstant(report.checkedAt)).toISOString()}\n\n`
    + messages.map((message) => `- ${message}`).join("\n") + `\n\n[Inspect the monitor run](${url.href}).\n\n`
    + "Accepted facts are retained. This concerns fixture coverage, identity and freshness—not evidence of playable streams. The monitor does not repair, merge or deploy changes.\n";
}
