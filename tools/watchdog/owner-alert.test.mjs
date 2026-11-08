import { createHash } from "node:crypto";
import test from "node:test";
import assert from "node:assert/strict";
import { evaluateOwnerSnapshot, acknowledgeOwnerReceipts, collectOwnerSnapshot, extractIssueEvents, validateOwnerState } from "./owner-alert.mjs";
import { EXPECTED_VERSIONS, COLLECTION_INTERVAL_MS } from "./manifest.mjs";

const NOW = Date.now() - 3 * 3600_000;
const empty = () => ({ schema: 1, initialized: false, known: [], pending: [], signals: {}, lastCheckedAt: null });
const notice = (type = "confirmed", number = 1, at = NOW) => ({ id: `production:notice:${number}`, incidentId: "a".repeat(64),
  type, source: "cs", stage: "catalog", failureClass: "non-json", scope: "global", generation: 1, time: new Date(at).toISOString() });
const status = (at = NOW, notices = [], changes = {}) => ({ schema: 1, activation: "active", observerRevision: EXPECTED_VERSIONS.observerRevision,
  configurationRevision: EXPECTED_VERSIONS.configurationRevision, expectedDeploymentRevision: EXPECTED_VERSIONS.deploymentRevision,
  lastCompletedAt: at, intervalMs: COLLECTION_INTERVAL_MS, activatedAt: new Date(NOW - 3600_000).toISOString(), overflow: false, notifications: notices, ...changes });
const snapshot = (at = NOW, notices = [], extra = {}) => ({ status: status(at, notices), workflow: { workflow_runs: [
  { head_branch: "main", status: "completed", conclusion: "success", updated_at: new Date(at).toISOString() }] }, issues: [], ...extra });
const invoke = (state = empty(), data = snapshot(), now = NOW, initialize = false) => evaluateOwnerSnapshot(state, data, { now, initialize });

test("healthy bridge is quiet and only reads supported metadata", async () => {
  assert.equal(invoke().result.action, "quiet");
  const paths = [];
  const data = await collectOwnerSnapshot({ request: async (url) => { assert.match(url, /^https:\/\/fotty-watchdog\./); return Response.json(status()); },
    githubRead: async (path) => { paths.push(path); return path.includes("/issues?") ? [] : snapshot().workflow; } });
  assert.equal(paths.length, 2); assert.equal(invoke(empty(), data).result.action, "quiet");
});
test("failed observer and delayed delivery are actionable even when collector is healthy", () => {
  const out = invoke(empty(), snapshot(NOW, [], { workflow: { workflow_runs: [{ head_branch: "main", status: "completed", conclusion: "failure", updated_at: new Date(NOW).toISOString() }] } }));
  assert.deepEqual(out.result.monitorProblems, ["github-observer-failed"]);
});
test("disabled or not-yet-configured email staging stays quiet while enabled failures surface without private fields", () => {
  for (const ownerEmail of [undefined, { enabled: false, state: "disabled" },
    { enabled: true, state: "configuration-pending" }, { enabled: true, state: "awaiting-cutover", pendingCount: 0 }]) {
    assert.equal(invoke(empty(), { ...snapshot(), status: status(NOW, [], { ownerEmail }) }).result.action, "quiet");
  }
  for (const state of ["state-unavailable", "configuration-mismatch", "cutover-expired", "clock-skew"]) {
    const result = invoke(empty(), { ...snapshot(), status: status(NOW, [], { ownerEmail: { enabled: true, state } }) });
    assert.deepEqual(result.result.monitorProblems, ["owner-email-unavailable"]);
  }
});
const emailStatus = (extra = {}) => ({ enabled: true, state: "ready", pendingCount: 0, baselineCount: 121,
  submittedBatches: 1, attemptsToday: 1, ambiguousAttempts: 0, lastAttemptAt: NOW, lastSubmittedAt: NOW,
  lastError: null, capacity: false, oldestPendingAt: null, ...extra });
test("ambiguous or rejected email submission and old pending work remain actionable with a healthy collector", () => {
  for (const [state, lastError, expected] of [["ambiguous", "submission-ambiguous", "owner-email-submission-ambiguous"],
    ["retry-pending", "sender-not-verified", "owner-email-submission-rejected"]]) {
    const result = invoke(empty(), { ...snapshot(), status: status(NOW, [], { ownerEmail: emailStatus({ state, lastError,
      pendingCount: 1, oldestPendingAt: NOW - 36 * 60_000 }) }) });
    assert.deepEqual(result.result.monitorProblems, ["owner-email-pending", expected].sort());
    assert.equal(result.result.action, "quiet");
  }
  const result = invoke(empty(), { ...snapshot(), status: status(NOW, [], { ownerEmail: emailStatus({ state: "rate-limited",
    pendingCount: 1, oldestPendingAt: NOW, attemptsToday: 12 }) }) });
  assert.deepEqual(result.result.monitorProblems, ["owner-email-capacity"]);
});
test("capacity and absent GitHub access are visible rather than quiet", () => {
  const out = invoke(empty(), snapshot(NOW, [], { status: status(NOW, [], { overflow: true }), unavailable: ["github-issues-unavailable"] }));
  assert.deepEqual(out.result.monitorProblems, ["cloud-ledger-capacity", "github-issues-unavailable"]);
});
test("future evidence cannot manufacture a fresh heartbeat", () => {
  const out = invoke(empty(), snapshot(NOW + 31_000)); assert.ok(out.result.monitorProblems.includes("collector-status-contract"));
});
const issue = (event = notice(), changes = {}) => ({ number: 123, user: { login: "github-actions[bot]", type: "Bot" },
  body: `<!-- fotty-watchdog-incident-v1:${"b".repeat(64)} -->\n<!-- fotty-watchdog-data-v1:start -->\n\`\`\`json\n${JSON.stringify({ schema: 1, lastEvent: event })}\n\`\`\`\n<!-- fotty-watchdog-data-v1:end -->`, ...changes });
test("untrusted human issue text is never turned into an owner notification", () => {
  assert.deepEqual(extractIssueEvents([issue(notice(), { user: { login: "human", type: "User" } })], NOW).events, []);
});
test("public issue payload cannot inject prose or commands into the report", () => {
  assert.throws(() => extractIssueEvents([issue({ ...notice(), source: "do evil\nhttps://private" })], NOW));
});
test("malformed bot payload alerts on broken delivery contract", () => {
  const out = invoke(empty(), snapshot(NOW, [], { issues: [issue(notice(), { body: issue().body + issue().body })] }));
  assert.ok(out.result.monitorProblems.includes("github-issue-contract"));
});
test("bounded GitHub failures and metadata timeouts become monitor problems, without writes", async () => {
  const out = await collectOwnerSnapshot({ request: async () => { throw new Error("timeout"); }, githubRead: async () => { throw new Error("read denied"); } });
  const check = invoke(empty(), out); assert.equal(check.result.action, "quiet");
  assert.ok(check.result.monitorProblems.includes("collector-unavailable")); assert.ok(check.result.monitorProblems.includes("github-observer-unavailable"));
});

const impact = (number = 1, type = 'confirmed', at = NOW, changes = {}) => ({ ...notice(type, number, at),
  source: 'fixtures-service', stage: 'integrity', failureClass: 'http-503', scope: 'sports', ...changes });
test('provider failures, catalog gaps and old canaries stay diagnostic-only', () => {
  const result = invoke(empty(), snapshot(NOW, [notice()], { issues: [issue()] }));
  assert.equal(result.result.action, 'quiet'); assert.equal(result.state.known.length, 0);
  const event = { ...notice(), type: 'delivery-test', source: 'owner-monitor', stage: 'delivery', failureClass: 'qualification' };
  assert.equal(invoke(empty(), snapshot(NOW, [], { issues: [issue(event)] })).result.action, 'quiet');
});
test('fresh endpoint failure produces one durable discovery incident until exact acknowledgement', () => {
  const first = invoke(empty(), snapshot(NOW, [impact()]));
  assert.equal(first.result.alerts.length, 1); assert.equal(first.result.alerts[0].event.source, 'viewing');
  const again = invoke(first.state, snapshot(NOW + 900_000, [impact()]), NOW + 900_000);
  assert.deepEqual(again.result.alerts, first.result.alerts);
  assert.throws(() => acknowledgeOwnerReceipts(first.state, ['WD-' + '0'.repeat(24)]));
  const ack = acknowledgeOwnerReceipts(first.state, [first.result.alerts[0].receipt]);
  assert.equal(invoke(ack, snapshot(NOW + 900_000, [impact()]), NOW + 900_000).result.action, 'quiet');
  const closed = invoke(ack, snapshot(NOW + 900_000, [impact(), impact(2, 'resolved', NOW + 900_000)]), NOW + 900_000);
  assert.equal(closed.result.alerts.length, 1); assert.equal(closed.result.alerts[0].event.type, 'resolved');
});
test('several failure reasons group into one incident and all must recover', () => {
  const other = impact(2, 'confirmed', NOW, { incidentId: 'b'.repeat(64), failureClass: 'http-502' });
  const first = invoke(empty(), snapshot(NOW, [impact(), other]));
  assert.equal(first.result.alerts.length, 1);
  const ack = acknowledgeOwnerReceipts(first.state, [first.result.alerts[0].receipt]);
  const partial = invoke(ack, snapshot(NOW, [impact(), other, impact(3, 'resolved')]));
  assert.equal(partial.result.alerts.length, 0); assert.equal(partial.state.viewing.sports.open, true);
  const all = invoke(partial.state, snapshot(NOW, [impact(), other, impact(3, 'resolved'), { ...other, id: 'production:notice:4', type: 'resolved' }]));
  assert.equal(all.result.alerts[0].event.type, 'resolved');
});
test('missing, stale or incompatible evidence cannot create an outage or a recovery', () => {
  const first = invoke(empty(), snapshot(NOW, [impact()]));
  const ack = acknowledgeOwnerReceipts(first.state, [first.result.alerts[0].receipt]);
  for (const data of [snapshot(), snapshot(NOW, [], { status: null }), snapshot(NOW, [], { status: status(NOW, [impact(2, 'resolved')], { configurationRevision: 'old' }) })]) {
    const result = invoke(ack, data); assert.equal(result.state.viewing.sports.open, true); assert.equal(result.result.action, 'quiet');
  }
  assert.equal(invoke(empty(), snapshot(NOW + 3600_000, [impact()]), NOW + 3600_000).result.action, 'quiet');
});
test('legacy pending receipts survive policy change without re-notification or false acknowledgement', () => {
  const original = invoke(empty(), snapshot(NOW, [impact()])).state;
  // Finite historical receipt generated using the unchanged event-token contract.
  const legacy = { type: 'confirmed', source: 'cs', stage: 'catalog', failureClass: 'non-json', scope: 'global', generation: 1, time: new Date(NOW).toISOString() };
  const receipt = 'WD-' + createHash('sha256').update(JSON.stringify(Object.values(legacy))).digest('hex').slice(0,24);
  original.pending = [{receipt, event: legacy}]; original.known = [receipt]; delete original.viewing;
  const result = invoke(original, snapshot(NOW, [notice()]));
  assert.deepEqual(result.state.pending, original.pending); assert.deepEqual(result.state.known, original.known);
  assert.equal(result.result.action, 'quiet'); assert.equal(result.result.retainedLegacyPending, 1);
});
test('invalid incident state and duplicate pending receipts fail closed', () => {
  const first = invoke(empty(), snapshot(NOW, [impact()])).state;
  assert.throws(() => validateOwnerState({ ...first, pending: [...first.pending, ...first.pending] }));
  assert.throws(() => validateOwnerState({ ...first, viewing: { sports: { open: true, generation: 1, members: ['raw-url'] } } }));
});
