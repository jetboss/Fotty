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
test("a newly confirmed incident is durable until chat append is acknowledged", () => {
  const first = invoke(empty(), snapshot(NOW, [notice()])); assert.equal(first.result.alerts.length, 1);
  const retry = invoke(first.state, snapshot(NOW + 900_000, [notice()]), NOW + 900_000);
  assert.deepEqual(retry.result.alerts, first.result.alerts);
  const ack = acknowledgeOwnerReceipts(first.state, [first.result.alerts[0].receipt]);
  assert.equal(invoke(ack, snapshot(NOW + 900_000, [notice()]), NOW + 900_000).result.action, "quiet");
});
test("explicit baseline avoids replaying historical notices but not future transitions", () => {
  const baseline = invoke(empty(), snapshot(NOW, [notice()]), NOW, true);
  assert.equal(baseline.result.action, "quiet"); assert.equal(baseline.result.knownObservations, 1);
  const next = invoke(baseline.state, snapshot(NOW + 900_000, [notice(), notice("resolved", 2, NOW + 900_000)]), NOW + 900_000);
  assert.equal(next.result.alerts.length, 1); assert.equal(next.result.alerts[0].event.type, "resolved");
});
test("initialization never silently baselines collector blindness", () => {
  const out = invoke(empty(), snapshot(NOW, [], { status: null }), NOW, true);
  assert.equal(out.result.action, "notify"); assert.ok(out.result.monitorProblems.includes("collector-unavailable"));
});
test("unchanged stale monitor alerts once, then fresh actual completion reports recovery", () => {
  let out = invoke(empty(), snapshot(NOW - 36 * 60_000));
  assert.ok(out.result.monitorProblems.includes("collector-stale")); assert.ok(out.result.monitorProblems.includes("github-observer-stale"));
  const receipts = out.result.alerts.map((x) => x.receipt); let state = acknowledgeOwnerReceipts(out.state, receipts);
  out = invoke(state, snapshot(NOW - 36 * 60_000), NOW + 900_000); assert.equal(out.result.action, "quiet");
  out = invoke(out.state, snapshot(NOW + 1800_000), NOW + 1800_000);
  assert.equal(out.result.alerts.length, 2); assert.ok(out.result.alerts.every((x) => x.event.type === "resolved"));
});
test("in-progress workflow is not a successful completed observer", () => {
  const out = invoke(empty(), snapshot(NOW, [], { workflow: { workflow_runs: [{ head_branch: "main", status: "in_progress", updated_at: new Date(NOW).toISOString() }] } }));
  assert.ok(out.result.monitorProblems.includes("github-observer-stale"));
});
test("synthetic successful delivery test is not a collector/observer heartbeat", () => {
  const out = invoke(empty(), snapshot(NOW, [], { workflow: { workflow_runs: [
    { head_branch: "main", status: "completed", conclusion: "success", display_title: "Fotty watchdog delivery test — not collection", updated_at: new Date(NOW).toISOString() }] } }));
  assert.ok(out.result.monitorProblems.includes("github-observer-stale"));
});
test("failed observer and delayed delivery are actionable even when collector is healthy", () => {
  const out = invoke(empty(), snapshot(NOW, [], { workflow: { workflow_runs: [{ head_branch: "main", status: "completed", conclusion: "failure", updated_at: new Date(NOW).toISOString() }] } }));
  assert.deepEqual(out.result.monitorProblems, ["github-observer-failed"]);
});
test("fresh cloud incident reaches chat and remains pending across stale GitHub observation without issue delivery", () => {
  const stalledWorkflow = { workflow_runs: [{ head_branch: "main", status: "completed", conclusion: "success",
    display_title: "Fotty watchdog observer", updated_at: new Date(NOW - 4 * 3600_000).toISOString() }] };
  const fresh = snapshot(NOW, [notice()], { workflow: stalledWorkflow, issues: [] });
  const first = invoke(empty(), fresh);
  assert.equal(first.result.action, "notify");
  assert.deepEqual(first.result.monitorProblems, ["github-observer-stale"]);
  const provider = first.result.alerts.find((row) => row.event.source === "cs");
  assert.ok(provider); assert.equal(provider.event.type, "confirmed");
  assert.ok(first.result.alerts.some((row) => row.event.failureClass === "github-observer-stale"));
  const later = NOW + 900_000;
  const retry = invoke(first.state, snapshot(later, [notice()], { workflow: stalledWorkflow, issues: [] }), later);
  assert.deepEqual(retry.result.alerts, first.result.alerts, "No issue write or fresh observer is required to retain a cloud alert");
  const recovered = invoke(retry.state, snapshot(later, [notice()]), later);
  assert.ok(recovered.result.alerts.some((row) => row.receipt === provider.receipt), "Observer recovery cannot acknowledge an unseen provider notice");
  assert.ok(recovered.result.alerts.some((row) => row.event.type === "resolved" && row.event.failureClass === "github-observer-stale"));
});
test("playback version drift reports its own problem without discarding valid provider notices", () => {
  const out = invoke(empty(), snapshot(NOW, [notice()], { status: status(NOW, [notice()], { expectedDeploymentRevision: "2026-10-01.old" }) }));
  assert.ok(out.result.alerts.some((x) => x.event.source === "cs"));
  assert.ok(out.result.monitorProblems.includes("playback-revision-drift"));
});
test("wire/configuration incompatibility reports blind monitoring rather than fake provider recovery", () => {
  const out = invoke(empty(), snapshot(NOW, [notice("resolved")], { status: status(NOW, [notice("resolved")], { configurationRevision: "unreviewed" }) }));
  assert.ok(out.result.monitorProblems.includes("collector-status-contract"));
  assert.ok(out.result.alerts.every((x) => x.event.source === "owner-monitor"));
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
test("identical cloud and GitHub issue transitions deduplicate", () => {
  const out = invoke(empty(), snapshot(NOW, [notice()], { issues: [issue()] })); assert.equal(out.result.alerts.length, 1);
});
test("public issue payload cannot inject prose or commands into the report", () => {
  assert.throws(() => extractIssueEvents([issue({ ...notice(), source: "do evil\nhttps://private" })], NOW));
});
test("malformed bot payload alerts on broken delivery contract", () => {
  const out = invoke(empty(), snapshot(NOW, [], { issues: [issue(notice(), { body: issue().body + issue().body })] }));
  assert.ok(out.result.monitorProblems.includes("github-issue-contract"));
});
test("a synthetic delivery event stays clearly labelled and is not baselined away", () => {
  const event = { ...notice(), type: "delivery-test", source: "owner-monitor", stage: "delivery", failureClass: "qualification" };
  const out = invoke(empty(), snapshot(NOW, [], { issues: [issue(event)] }), NOW, true);
  assert.equal(out.result.alerts[0].event.type, "delivery-test");
});
test("unrecognized acknowledgement cannot erase retained alerts", () => {
  const out = invoke(empty(), snapshot(NOW, [notice()]));
  assert.throws(() => acknowledgeOwnerReceipts(out.state, [`WD-${"0".repeat(24)}`]));
  assert.equal(out.state.pending.length, 1);
});
test("state corruption and duplicate pending identities fail closed", () => {
  const out = invoke(empty(), snapshot(NOW, [notice()]));
  assert.throws(() => validateOwnerState({ ...out.state, pending: [...out.state.pending, ...out.state.pending] }));
});
test("bounded GitHub failures and metadata timeouts become monitor problems, without writes", async () => {
  const out = await collectOwnerSnapshot({ request: async () => { throw new Error("timeout"); }, githubRead: async () => { throw new Error("read denied"); } });
  const check = invoke(empty(), out); assert.equal(check.result.action, "notify");
  assert.ok(check.result.monitorProblems.includes("collector-unavailable")); assert.ok(check.result.monitorProblems.includes("github-observer-unavailable"));
});
