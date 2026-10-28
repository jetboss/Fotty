import test from "node:test";
import assert from "node:assert/strict";
import { EXPECTED_VERSIONS, COLLECTION_INTERVAL_MS } from "./manifest.mjs";
import { runGitHubObserver, createGitHubClient, collectWorkflowObservations, statusObservations,
  cloudNotifications, WORKFLOWS, CORRECTED_BASELINE, WATCHDOG_STATUS_URL, OWNER, runDeliveryCanary } from "./github-observer.mjs";

const NOW = Date.parse("2026-10-11T12:00:00Z"), WINDOW = COLLECTION_INTERVAL_MS;
const MAIN = "a".repeat(40), OLD = "b".repeat(40), BOT = { login: "github-actions[bot]", type: "Bot" };
const json = (body, status = 200) => Response.json(body, { status });
const iso = (value) => new Date(value).toISOString();
function status(now = NOW, overrides = {}) {
  return { schema: 1, activation: "active", intervalMs: WINDOW, activatedAt: iso(NOW - 3 * 3600_000),
    observerRevision: EXPECTED_VERSIONS.observerRevision, configurationRevision: EXPECTED_VERSIONS.configurationRevision,
    expectedDeploymentRevision: EXPECTED_VERSIONS.deploymentRevision, lastAttemptedAt: now - 60_000,
    lastCompletedAt: now - 30_000, notifications: [], ...overrides };
}
function run(now = NOW, overrides = {}) {
  return { head_sha: MAIN, head_branch: "main", status: "completed", conclusion: "success",
    created_at: iso(now - 10 * 60_000), updated_at: iso(now - 5 * 60_000), ...overrides };
}
function notice(id = 1, type = "confirmed", overrides = {}) {
  return { id: `production:notice:${id}`, type, incidentId: "c".repeat(64), source: "cs", stage: "manifest",
    failureClass: "schema", scope: "source", generation: 1, time: iso(NOW), ...overrides };
}
function fixture() {
  const issues = [], calls = [], comments = new Map(), runs = new Map(WORKFLOWS.map(({ file }) => [file, [run()]]));
  let number = 1, commentId = 1, alertFailures = 0, ambiguousFailure = false, commentFailures = 0, ambiguousComment = false,
    commitFailures = 0, ambiguousCommit = false;
  const api = { issues, calls, comments, runs, comparisons: new Map(), omitAssignee: false,
    failAlerts(count, ambiguous = false) { alertFailures = count; ambiguousFailure = ambiguous; },
    failComments(count, ambiguous = false) { commentFailures = count; ambiguousComment = ambiguous; },
    failCommits(count, ambiguous = false) { commitFailures = count; ambiguousCommit = ambiguous; },
    async request(url, options = {}) {
      calls.push({ url: String(url), ...options });
      const path = new URL(url).pathname, method = options.method || "GET";
      if (path.endsWith("/git/ref/heads/main")) return json({ object: { sha: MAIN } });
      if (path.includes("/compare/")) {
        const head = path.split("...").at(-1);
        return json(api.comparisons.get(head) || { status: "behind", merge_base_commit: { sha: OLD } });
      }
      if (path.includes("/actions/workflows/")) {
        const file = path.split("/actions/workflows/")[1].split("/")[0], value = runs.get(file);
        if (value instanceof Response) return value;
        return json({ workflow_runs: value || [] });
      }
      if (path.endsWith("/issues") && method === "GET") {
        const page = Number(new URL(url).searchParams.get("page"));
        return json(issues.slice((page - 1) * 100, page * 100));
      }
      const data = JSON.parse(options.body || "{}"), alert = data.body?.includes("fotty-watchdog-incident-v1:");
      const issueComments = path.match(/\/issues\/([0-9]+)\/comments$/);
      if (issueComments) {
        const issueNumber = Number(issueComments[1]), rows = comments.get(issueNumber) ?? [];
        if (method === "GET") {
          const page = Number(new URL(url).searchParams.get("page"));
          return json(rows.slice((page - 1) * 100, page * 100));
        }
        if (method === "POST") {
          if (commentFailures > 0 && !ambiguousComment) { commentFailures--; return json({}, 503); }
          const comment = { id: commentId++, user: BOT, body: data.body };
          rows.push(comment); comments.set(issueNumber, rows);
          if (commentFailures > 0) { commentFailures--; throw new Error("Response lost after committed comment"); }
          return json(comment, 201);
        }
      }
      if (alert && alertFailures > 0 && !ambiguousFailure) { alertFailures--; return json({}, 503); }
      const assigned = data.assignees ? { assignees: api.omitAssignee ? [] : data.assignees.map((login) => ({ login, type: "User" })) } : {};
      if (method === "POST" && path.endsWith("/issues")) {
        const issue = { number: number++, user: BOT, state: "open", ...data, ...assigned }; issues.push(issue);
        if (alert && alertFailures > 0) { alertFailures--; throw new Error("Response lost after committed issue"); }
        return json(issue, 201);
      }
      if (method === "PATCH" && /\/issues\/[0-9]+$/.test(path)) {
        const issue = issues.find((row) => row.number === Number(path.split("/").at(-1)));
        if (!issue) return json({}, 404);
        const commit = alert && !data.body.includes('"pendingEventHash"');
        if (commit && commitFailures > 0 && !ambiguousCommit) { commitFailures--; return json({}, 503); }
        Object.assign(issue, data, assigned);
        if (commit && commitFailures > 0) { commitFailures--; throw new Error("Response lost after committed receipt"); }
        return json(issue);
      }
      throw new Error("Unexpected fixture route");
    },
  };
  return api;
}
const ledger = (api) => {
  const issue = api.issues.find((row) => row.body.includes("fotty-watchdog-observer-ledger-v1"));
  return JSON.parse(issue.body.split("```json\n")[1].split("\n```")[0]);
};
const alerts = (api) => api.issues.filter((row) => row.body.includes("fotty-watchdog-incident-v1:"));
const issuePayload = (issue) => JSON.parse(issue.body.split("```json\n")[1].split("\n```")[0]);
const ownerComments = (api) => [...api.comments.values()].flat();
const invoke = (api, now, body = status(now)) => runGitHubObserver({ token: "fixture-secret", request: api.request,
  statusRequest: async (url, options) => { assert.equal(String(url), WATCHDOG_STATUS_URL); assert.equal(options.headers.Authorization, undefined); return json(body); }, now });

test("real 201 issue creation, restart persistence and token isolation", async () => {
  const api = fixture();
  const result = await invoke(api, NOW);
  assert.equal(result.ledgerIssue, 1); assert.equal(result.delivered, 0); assert.equal(alerts(api).length, 0);
  assert.equal(ledger(api).ledger.revision, 1);
  await invoke(api, NOW + WINDOW);
  assert.equal(api.issues.length, 1); assert.equal(ledger(api).ledger.revision, 2);
  assert.ok(api.calls.every((call) => call.headers.Authorization === "Bearer fixture-secret"));
  assert.ok(api.calls.every((call) => !call.url.includes("fixture-secret")));
  assert.ok(api.calls.every((call) => ["GET", "POST", "PATCH"].includes(call.method)));
});

test("CLI-compatible default reads GITHUB_TOKEN, not an unrelated environment variable", async () => {
  const api = fixture(), prior = process.env.GITHUB_TOKEN;
  process.env.GITHUB_TOKEN = "environment-fixture-token";
  try {
    await runGitHubObserver({ request: api.request, statusRequest: async () => json(status()), now: NOW });
    assert.ok(api.calls.every((call) => call.headers.Authorization === "Bearer environment-fixture-token"));
  } finally { if (prior === undefined) delete process.env.GITHUB_TOKEN; else process.env.GITHUB_TOKEN = prior; }
});

test("transport outage is suspect and quiet until two independent windows", async () => {
  const api = fixture();
  const check = (now) => runGitHubObserver({ token: "fixture", request: api.request, now, statusRequest: async () => { throw new Error("private provider URL"); } });
  await check(NOW); await check(NOW);
  assert.equal(alerts(api).length, 0);
  await check(NOW + WINDOW);
  assert.equal(alerts(api).length, 1);
  assert.equal(Object.values(ledger(api).ledger.incidents)[0].state, "confirmed");
  assert.ok(!api.issues.some((issue) => issue.body.includes("private provider URL")));
});

test("wrong revisions cannot deliver cloud events or clear held liveness incidents", async () => {
  const api = fixture(), bad = status(NOW, { observerRevision: "old", notifications: [notice()] });
  for (let i = 0; i < 3; i++) await invoke(api, NOW + i * WINDOW, bad);
  assert.equal(alerts(api).length, 1);
  assert.equal(ledger(api).deliveredCloud.length, 0);
  assert.equal(alerts(api)[0].body.includes('"failureClass":"status-contract"'), true);
});

test("pending activation is quiet; liveness means attempted/completed, never accepted fixtures", () => {
  const inactive = statusObservations(status(NOW, { activation: "pending", lastAttemptedAt: null, lastCompletedAt: null }), NOW);
  assert.ok(inactive.every((row) => row.outcome === "inactive"));
  const rows = statusObservations(status(NOW, { lastAttemptedAt: NOW - 76 * 60_000, lastCompletedAt: NOW - 76 * 60_000 }), NOW);
  assert.deepEqual(rows.filter((row) => row.failureClass === "missing_run").map((row) => [row.facts.dimension, row.outcome]),
    [["completed", "failure"], ["attempted", "failure"]]);
  assert.ok(rows.every((row) => row.acceptedAt === undefined && row.facts.dimension !== "accepted"));
});

test("missing scheduled completion confirms after two rechecks, then requires two fresh recovery windows", async () => {
  const api = fixture(), old = NOW - 80 * 60_000;
  for (let i = 0; i < 3; i++) await invoke(api, NOW + i * WINDOW, status(NOW, { lastAttemptedAt: old, lastCompletedAt: old }));
  assert.equal(alerts(api).length, 2);
  await invoke(api, NOW + 3 * WINDOW); await invoke(api, NOW + 3 * WINDOW);
  assert.ok(alerts(api).every((issue) => issue.state === "open"));
  await invoke(api, NOW + 4 * WINDOW);
  assert.ok(alerts(api).every((issue) => issue.state === "closed"));
  assert.equal(alerts(api).length, 2);
});

test("workflow failure on uncorrected older head is unknown, not a new current incident", async () => {
  const api = fixture();
  api.runs.set("sports-fixtures.yml", [run(NOW, { head_sha: OLD, conclusion: "failure" })]);
  const client = createGitHubClient({ token: "fixture", request: api.request });
  const rows = await collectWorkflowObservations(client, { now: NOW, startedAt: iso(NOW - 24 * 3600_000) });
  assert.ok(rows.filter((row) => row.source === "workflow-sports" && row.failureClass !== "workflow-api").every((row) => row.outcome === "unknown"));
  assert.ok(api.calls.some((call) => call.url.includes(`${CORRECTED_BASELINE}...${OLD}`)));
});

test("ancestry-confirmed corrected head may report current failure; queued run is not recovery", async () => {
  const api = fixture();
  api.comparisons.set(OLD, { status: "ahead", merge_base_commit: { sha: CORRECTED_BASELINE } });
  api.runs.set("sports-fixtures.yml", [run(NOW, { status: "in_progress", conclusion: null }), run(NOW, { head_sha: OLD, conclusion: "failure" })]);
  const rows = await collectWorkflowObservations(createGitHubClient({ token: "fixture", request: api.request }), { now: NOW });
  assert.equal(rows.find((row) => row.source === "workflow-sports" && row.failureClass === "workflow-execution-failure").outcome, "failure");
});

test("workflow publication gaps are inactive; published empty runs use reviewed deadlines", async () => {
  const api = fixture(); api.runs.set("sports-fixtures.yml", []); api.runs.set("cricket-fixtures.yml", json({}, 404)); api.runs.set("provider-monitor.yml", []);
  const rows = await collectWorkflowObservations(createGitHubClient({ token: "fixture", request: api.request }), { now: NOW, startedAt: iso(NOW - 4 * 3600_000) });
  assert.equal(rows.find((row) => row.source === "workflow-sports" && row.failureClass === "missing_run").outcome, "failure");
  assert.equal(rows.find((row) => row.source === "workflow-cricket").outcome, "inactive");
  assert.equal(rows.find((row) => row.source === "workflow-provider" && row.failureClass === "missing_run").outcome, "unknown");
});

test("cloud delivery retries failed issue POST after restart, never erasing Worker notices", async () => {
  const api = fixture(); api.failAlerts(1);
  const body = status(NOW, { notifications: [notice()] });
  const first = await invoke(api, NOW, body);
  assert.equal(first.pending, 1); assert.equal(ledger(api).deliveredCloud.length, 0);
  const retry = await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
  assert.equal(retry.delivered, 1); assert.equal(ledger(api).deliveredCloud.length, 1); assert.equal(alerts(api).length, 1);
  const duplicate = await invoke(api, NOW + 2 * WINDOW, status(NOW + 2 * WINDOW, { notifications: [notice()] }));
  assert.equal(duplicate.delivered, 0); assert.equal(alerts(api).length, 1);
  assert.ok(api.calls.every((call) => !new URL(call.url).pathname.endsWith("/run")));
});

test("ambiguous committed POST is deduplicated by issue marker/event hash on restart", async () => {
  const api = fixture(); api.failAlerts(1, true);
  await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  assert.equal(alerts(api).length, 1); assert.equal(ledger(api).deliveredCloud.length, 0);
  await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
  assert.equal(alerts(api).length, 1); assert.equal(ledger(api).deliveredCloud.length, 1);
});

test("failed confirmation delivery cannot be overtaken by recovery on the same incident", async () => {
  for (const ambiguous of [false, true]) {
    const api = fixture(); api.failAlerts(1, ambiguous);
    const events = [notice(), notice(2, "resolved")];
    const first = await invoke(api, NOW, status(NOW, { notifications: events }));
    assert.equal(first.pending, 2); assert.equal(ledger(api).deliveredCloud.length, 0);
    assert.ok(alerts(api).every((issue) => issue.state === "open"));
    await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: events }));
    assert.equal(alerts(api).length, 1); assert.equal(alerts(api)[0].state, "closed");
    assert.equal(ledger(api).deliveredCloud.length, 2);
    await invoke(api, NOW + 2 * WINDOW, status(NOW + 2 * WINDOW, { notifications: events }));
    assert.equal(alerts(api)[0].state, "closed");
  }
});

test("independent retained confirmation/recovery also preserves delivery order after failed writes", async () => {
  const api = fixture(); api.failAlerts(4);
  const outage = (now) => runGitHubObserver({ token: "fixture", request: api.request, now,
    statusRequest: async () => { throw new Error("Fixture outage"); } });
  for (let i = 0; i < 3; i++) await outage(NOW + i * WINDOW);
  await invoke(api, NOW + 3 * WINDOW);
  const recovering = await invoke(api, NOW + 4 * WINDOW);
  assert.equal(recovering.pending, 2); assert.equal(alerts(api).length, 0);
  const outbox = ledger(api).ledger.outbox;
  assert.deepEqual(outbox.map((row) => row.type), ["confirmed", "resolved"]);
  await invoke(api, NOW + 5 * WINDOW);
  assert.equal(alerts(api).length, 1); assert.equal(alerts(api)[0].state, "closed");
  await invoke(api, NOW + 6 * WINDOW);
  assert.equal(alerts(api)[0].state, "closed"); assert.equal(alerts(api).length, 1);
});

test("cloud resolution upserts/closes same stable incident issue, not another invitation", async () => {
  const api = fixture(); await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  alerts(api)[0].body += "\nOwner note: keep this context.";
  await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice(), notice(2, "resolved")] }));
  assert.equal(alerts(api).length, 1); assert.equal(alerts(api)[0].state, "closed");
  assert.equal(ledger(api).deliveredCloud.length, 2);
  assert.ok(alerts(api)[0].body.includes("Fotty watchdog resolved: cs / manifest / schema."));
  assert.ok(!alerts(api)[0].body.includes("Fotty watchdog confirmed:"));
  assert.ok(alerts(api)[0].body.endsWith("Owner note: keep this context."));
});

test("each new transition verifies owner assignment and one event-marked bot mention before delivery", async () => {
  const api = fixture();
  const first = await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  assert.equal(first.delivered, 1);
  assert.deepEqual(alerts(api)[0].assignees, [{ login: OWNER, type: "User" }]);
  assert.equal(ownerComments(api).length, 1);
  assert.match(ownerComments(api)[0].body, /^<!-- fotty-watchdog-owner-event-v1:[a-f0-9]{64} -->\n@jetboss Fotty watchdog confirmed:/);
  assert.match(ownerComments(api)[0].body, /human reading or email receipt is not confirmed/);
  const writes = api.calls.filter((call) => call.method !== "GET" && !JSON.parse(call.body).body?.includes("fotty-watchdog-observer-ledger-v1"));
  assert.ok(JSON.parse(writes[0].body).body.includes('"pendingEventHash"'));
  assert.ok(!JSON.parse(writes[0].body).body.includes('"eventHashes":["'));
  assert.ok(new URL(writes[1].url).pathname.endsWith("/comments"));
  assert.ok(!JSON.parse(writes[2].body).body.includes('"pendingEventHash"'));
  await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice(), notice(2, "resolved")] }));
  assert.equal(ownerComments(api).length, 2);
  assert.match(ownerComments(api)[1].body, /@jetboss Fotty watchdog resolved:/);
  await invoke(api, NOW + 2 * WINDOW, status(NOW + 2 * WINDOW, { notifications: [notice(), notice(2, "resolved")] }));
  assert.equal(ownerComments(api).length, 2);
});

test("a failed owner comment is pending, is not acknowledged, and blocks overtaking recovery", async () => {
  const api = fixture(); api.failComments(1);
  const notifications = [notice(), notice(2, "resolved")];
  const failed = await invoke(api, NOW, status(NOW, { notifications }));
  assert.equal(failed.pending, 2); assert.equal(failed.delivered, 0);
  assert.equal(ledger(api).deliveredCloud.length, 0);
  assert.equal(issuePayload(alerts(api)[0]).eventHashes.length, 0);
  assert.match(issuePayload(alerts(api)[0]).pendingEventHash, /^[a-f0-9]{64}$/);
  assert.equal(alerts(api)[0].state, "open");
  const retry = await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications }));
  assert.equal(retry.pending, 0); assert.equal(retry.delivered, 2);
  assert.equal(ownerComments(api).length, 2); assert.equal(alerts(api)[0].state, "closed");
});

test("ambiguous comment or final receipt writes retry without duplicate mentions", async () => {
  for (const phase of ["comment", "commit"]) {
    const api = fixture();
    if (phase === "comment") api.failComments(1, true); else api.failCommits(1, true);
    const first = await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
    assert.equal(first.pending, 1); assert.equal(ledger(api).deliveredCloud.length, 0);
    assert.equal(ownerComments(api).length, 1);
    const second = await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
    assert.equal(second.pending, 0); assert.equal(ledger(api).deliveredCloud.length, 1);
    assert.equal(ownerComments(api).length, 1);
    assert.equal(api.calls.filter((call) => call.method === "POST" && new URL(call.url).pathname.endsWith("/comments")).length, 1);
  }
});

test("GitHub rejecting owner assignment cannot be recorded as delivered", async () => {
  const api = fixture(); api.omitAssignee = true;
  const failed = await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  assert.equal(failed.pending, 1); assert.equal(ledger(api).deliveredCloud.length, 0);
  assert.equal(ownerComments(api).length, 0);
  api.omitAssignee = false;
  const retry = await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
  assert.equal(retry.delivered, 1); assert.equal(ownerComments(api).length, 1);
});

test("a human comment with the event marker cannot stand in for verified bot delivery", async () => {
  const api = fixture(); api.failComments(1);
  await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  const attempted = api.calls.find((call) => call.method === "POST" && new URL(call.url).pathname.endsWith("/comments"));
  api.comments.set(alerts(api)[0].number, [{ id: 900, user: { login: "human", type: "User" }, body: JSON.parse(attempted.body).body }]);
  const count = api.calls.length;
  const retry = await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
  assert.equal(retry.pending, 1); assert.equal(ledger(api).deliveredCloud.length, 0);
  assert.equal(api.calls.slice(count).filter((call) => call.method === "POST" && new URL(call.url).pathname.endsWith("/comments")).length, 0);
});

test("full comment discovery fails closed without an ambiguous duplicate POST", async () => {
  const api = fixture(); api.failComments(1);
  await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  api.comments.set(alerts(api)[0].number, Array.from({ length: 200 }, (_, i) => ({ id: i + 1, user: BOT, body: "Unrelated retained comment" })));
  const count = api.calls.length;
  const retry = await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
  assert.equal(retry.pending, 1); assert.ok(retry.apiRequests <= 32);
  assert.equal(api.calls.slice(count).filter((call) => call.method === "POST" && new URL(call.url).pathname.endsWith("/comments")).length, 0);
});

test("legacy issue-only receipts do not replay history, but the next real change mentions owner", async () => {
  const api = fixture();
  await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  // Model the pre-upgrade receipt: the event hash exists, with no mention or assignee.
  api.comments.clear(); delete alerts(api)[0].assignees;
  await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
  assert.equal(ownerComments(api).length, 0);
  await invoke(api, NOW + 2 * WINDOW, status(NOW + 2 * WINDOW, { notifications: [notice(), notice(2, "resolved")] }));
  assert.equal(ownerComments(api).length, 1);
  assert.match(ownerComments(api)[0].body, /watchdog resolved:/);
  assert.deepEqual(alerts(api)[0].assignees, [{ login: OWNER, type: "User" }]);
});

test("compatible metadata revision drift alerts separately without discarding cloud notices", async () => {
  const api = fixture(), drift = "2026-10-28.new-fixture-source";
  const first = await invoke(api, NOW, status(NOW, { expectedDeploymentRevision: drift, notifications: [notice()] }));
  assert.equal(first.delivered, 1); assert.equal(ledger(api).deliveredCloud.length, 1);
  await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { expectedDeploymentRevision: drift, notifications: [notice()] }));
  assert.equal(alerts(api).length, 2);
  assert.equal(ownerComments(api).length, 2);
  assert.ok(alerts(api).some((issue) => issue.body.includes('"failureClass":"status-contract"')));
  // The same cloud event remains deduplicated when metadata versions converge.
  await invoke(api, NOW + 2 * WINDOW, status(NOW + 2 * WINDOW, { notifications: [notice()] }));
  await invoke(api, NOW + 3 * WINDOW, status(NOW + 3 * WINDOW, { notifications: [notice()] }));
  assert.equal(ledger(api).deliveredCloud.length, 1);
  assert.equal(ownerComments(api).length, 3);
  assert.match(ownerComments(api)[2].body, /watchdog resolved:/);
});

test("wire/configuration mismatch and invalid status time still fence cloud notice delivery", () => {
  for (const overrides of [{ observerRevision: "old" }, { configurationRevision: "old" },
    { activatedAt: null }, { expectedDeploymentRevision: "https://unreviewed.invalid" },
    { lastCompletedAt: NOW + 31_000 }]) {
    assert.deepEqual(cloudNotifications(status(NOW, { ...overrides, notifications: [notice()] }), NOW), []);
  }
});

test("canary uses a separate bot issue, explicit run identity and no production ledger changes", async () => {
  const api = fixture(); await invoke(api, NOW);
  const before = JSON.stringify(ledger(api));
  const first = await runDeliveryCanary({ token: "fixture", request: api.request, runId: "40766151178", now: NOW });
  assert.equal(first.deliveryTest, true); assert.equal(first.delivered, 1); assert.equal(first.humanAcknowledged, false);
  assert.equal(JSON.stringify(ledger(api)), before); assert.equal(alerts(api).length, 0);
  const canary = api.issues.find((issue) => issue.title.includes("delivery test"));
  assert.ok(canary); assert.deepEqual(canary.assignees, [{ login: OWNER, type: "User" }]);
  assert.match(ownerComments(api)[0].body, /@jetboss Fotty watchdog delivery test — not a provider outage/);
  const duplicate = await runDeliveryCanary({ token: "fixture", request: api.request, runId: "40766151178", now: NOW + WINDOW });
  assert.equal(duplicate.delivered, 0); assert.equal(ownerComments(api).length, 1);
  await runDeliveryCanary({ token: "fixture", request: api.request, runId: "40766151179", now: NOW + 2 * WINDOW });
  assert.equal(ownerComments(api).length, 2); assert.equal(JSON.stringify(ledger(api)), before);
  await assert.rejects(() => runDeliveryCanary({ token: "fixture", request: api.request, runId: "bad/id", now: NOW }), /identity/);
});

test("canary ambiguous comment retries retain original event time and a single mention", async () => {
  const api = fixture(); api.failComments(1, true);
  await assert.rejects(() => runDeliveryCanary({ token: "fixture", request: api.request, runId: "40766151178", now: NOW }));
  assert.equal(ownerComments(api).length, 1);
  const result = await runDeliveryCanary({ token: "fixture", request: api.request, runId: "40766151178", now: NOW + WINDOW });
  assert.equal(result.delivered, 1); assert.equal(ownerComments(api).length, 1);
  assert.equal(api.issues.length, 1); assert.equal(alerts(api).length, 0);
});

test("a fresh canary dispatch completes the retained predecessor before its own event", async () => {
  const api = fixture(); api.failComments(1, true);
  await assert.rejects(() => runDeliveryCanary({ token: "fixture", request: api.request, runId: "40766151178", now: NOW }));
  await runDeliveryCanary({ token: "fixture", request: api.request, runId: "40766151179", now: NOW + WINDOW });
  assert.equal(ownerComments(api).length, 2);
  const canary = api.issues.find((issue) => issue.title.includes("delivery test"));
  assert.equal(issuePayload(canary).eventHashes.length, 2);
  assert.equal(issuePayload(canary).pendingEventHash, undefined);
  assert.match(ownerComments(api)[0].body, /Observed: 2026-10-11T12:00:00.000Z/);
  assert.equal(alerts(api).length, 0);
});

test("polling one failed job does not invent two failed executions; two fresh jobs confirm", async () => {
  const api = fixture();
  api.runs.set("sports-fixtures.yml", [run(NOW, { conclusion: "failure" })]);
  for (let i = 0; i < 3; i++) await invoke(api, NOW + i * WINDOW);
  assert.equal(alerts(api).length, 0);
  const held = Object.values(ledger(api).ledger.incidents).find((row) => row.source === "workflow-sports");
  assert.equal(held.failureCount, 1);
  api.runs.set("sports-fixtures.yml", [run(NOW + 3 * WINDOW, { conclusion: "failure" })]);
  await invoke(api, NOW + 3 * WINDOW); assert.equal(alerts(api).length, 1);
  api.runs.set("sports-fixtures.yml", [run(NOW + 4 * WINDOW, { conclusion: "failure" })]);
  await invoke(api, NOW + 4 * WINDOW);
  assert.equal(alerts(api).length, 1);
  assert.ok(alerts(api)[0].body.includes("workflow-execution-failure"));
});

test("workflow recovery requires two distinct fresh successful executions, not re-reading one", async () => {
  const api = fixture();
  for (let i = 0; i < 3; i++) {
    api.runs.set("sports-fixtures.yml", [run(NOW + i * WINDOW, { conclusion: "failure" })]);
    await invoke(api, NOW + i * WINDOW);
  }
  assert.equal(alerts(api).length, 1);
  api.runs.set("sports-fixtures.yml", [run(NOW + 3 * WINDOW)]);
  await invoke(api, NOW + 3 * WINDOW); await invoke(api, NOW + 4 * WINDOW);
  assert.equal(alerts(api)[0].state, "open");
  api.runs.set("sports-fixtures.yml", [run(NOW + 5 * WINDOW)]);
  await invoke(api, NOW + 5 * WINDOW);
  assert.equal(alerts(api)[0].state, "closed");
});

test("uncorrected workflow head interrupts a suspect streak rather than carrying it into another failure", async () => {
  const api = fixture();
  api.runs.set("sports-fixtures.yml", [run(NOW, { conclusion: "failure" })]); await invoke(api, NOW);
  api.runs.set("sports-fixtures.yml", [run(NOW + WINDOW, { head_sha: OLD, conclusion: "failure" })]); await invoke(api, NOW + WINDOW);
  api.runs.set("sports-fixtures.yml", [run(NOW + 2 * WINDOW, { conclusion: "failure" })]); await invoke(api, NOW + 2 * WINDOW);
  assert.equal(alerts(api).length, 0);
  assert.equal(Object.values(ledger(api).ledger.incidents).find((row) => row.source === "workflow-sports").failureCount, 1);
});

test("notification validation rejects unknown sources, raw URLs, duplicate IDs and future evidence", () => {
  for (const events of [[notice(1, "confirmed", { source: "invented-provider" })], [notice(1, "confirmed", { scope: "https://private.invalid" })],
    [notice(), notice()], [notice(1, "confirmed", { time: iso(NOW + 31_000) })],
    [notice(2, "resolved"), notice()],
    [notice(1, "confirmed", { time: "Sun, 11 Oct 2026 12:00:00 GMT (private note)" })]]) {
    assert.throws(() => cloudNotifications(status(NOW, { notifications: events }), NOW));
  }
});

test("a malformed status body is a contract failure, not a claimed network outage", async () => {
  const api = fixture();
  await runGitHubObserver({ token: "fixture", request: api.request, now: NOW,
    statusRequest: async () => new Response("not JSON", { status: 200 }) });
  const incident = Object.values(ledger(api).ledger.incidents)[0];
  assert.equal(incident.failureClass, "status-contract");
  assert.equal(alerts(api).length, 0);
});

test("active observer without activation origin is an invalid contract, not permanently unknown", () => {
  const rows = statusObservations(status(NOW, { activatedAt: null, lastAttemptedAt: null, lastCompletedAt: null }), NOW);
  assert.equal(rows.length, 1); assert.equal(rows[0].outcome, "failure");
  assert.equal(rows[0].failureClass, "status-contract"); assert.equal(rows[0].facts.code, "invalid-time");
});

test("API call and delivery caps leave retained history pending", async () => {
  const api = fixture(), events = Array.from({ length: 12 }, (_, index) => notice(index + 1, "confirmed", { incidentId: (index + 1).toString(16).padStart(64, "0") }));
  const result = await invoke(api, NOW, status(NOW, { notifications: events }));
  assert.equal(result.delivered, 8); assert.equal(result.pending, 4); assert.ok(result.apiRequests <= 32);
  assert.equal(ledger(api).deliveredCloud.length, 8);
  const client = createGitHubClient({ token: "fixture", request: api.request, maxRequests: 1 });
  await client.call("/repos/jetboss/Fotty/git/ref/heads/main");
  await assert.rejects(() => client.call("/repos/jetboss/Fotty/git/ref/heads/main"), /bound/);
  assert.equal(client.requestCount, 1);
});

test("human-owned marker is never overwritten and full ambiguous issue inventory fails closed", async () => {
  const api = fixture();
  api.issues.push({ number: 999, user: { login: "owner", type: "User" }, body: "<!-- fotty-watchdog-observer-ledger-v1 -->", state: "open" });
  await invoke(api, NOW); assert.equal(api.issues[0].body, "<!-- fotty-watchdog-observer-ledger-v1 -->");
  const crowded = fixture();
  for (let i = 1; i <= 200; i++) crowded.issues.push({ number: i, user: BOT, body: "Unrelated bot issue", state: "open" });
  await assert.rejects(() => invoke(crowded, NOW), /discovery bound/);
  assert.equal(crowded.calls.length, 2);
});
