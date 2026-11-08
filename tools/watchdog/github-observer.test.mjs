import test from "node:test";
import assert from "node:assert/strict";
import { EXPECTED_VERSIONS, COLLECTION_INTERVAL_MS } from "./manifest.mjs";
import { runGitHubObserver, createGitHubClient, collectWorkflowObservations, statusObservations,
  cloudNotifications, WORKFLOWS, CORRECTED_BASELINE, WATCHDOG_STATUS_URL, runDeliveryCanary } from "./github-observer.mjs";
import { createPolicy, emptyLedger, applyObservation } from "./incident-policy.mjs";

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

test("pending activation is quiet; liveness means attempted/completed, never accepted fixtures", () => {
  const inactive = statusObservations(status(NOW, { activation: "pending", lastAttemptedAt: null, lastCompletedAt: null }), NOW);
  assert.ok(inactive.every((row) => row.outcome === "inactive"));
  const rows = statusObservations(status(NOW, { lastAttemptedAt: NOW - 76 * 60_000, lastCompletedAt: NOW - 76 * 60_000 }), NOW);
  assert.deepEqual(rows.filter((row) => row.failureClass === "missing_run").map((row) => [row.facts.dimension, row.outcome]),
    [["completed", "failure"], ["attempted", "failure"]]);
  assert.ok(rows.every((row) => row.acceptedAt === undefined && row.facts.dimension !== "accepted"));
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

test("wire/configuration mismatch and invalid status time still fence cloud notice delivery", () => {
  for (const overrides of [{ observerRevision: "old" }, { configurationRevision: "old" },
    { activatedAt: null }, { expectedDeploymentRevision: "https://unreviewed.invalid" },
    { lastCompletedAt: NOW + 31_000 }]) {
    assert.deepEqual(cloudNotifications(status(NOW, { ...overrides, notifications: [notice()] }), NOW), []);
  }
});

test("polling one failed job does not invent two failed executions; two fresh jobs confirm", async () => {
  const api = fixture();
  api.runs.set("sports-fixtures.yml", [run(NOW, { conclusion: "failure" })]);
  for (let i = 0; i < 3; i++) await invoke(api, NOW + i * WINDOW);
  assert.equal(alerts(api).length, 0);
  const held = Object.values(ledger(api).ledger.incidents).find((row) => row.source === "workflow-sports");
  assert.equal(held.failureCount, 1);
  api.runs.set("sports-fixtures.yml", [run(NOW + 3 * WINDOW, { conclusion: "failure" })]);
  await invoke(api, NOW + 3 * WINDOW); assert.equal(alerts(api).length, 0);
  api.runs.set("sports-fixtures.yml", [run(NOW + 4 * WINDOW, { conclusion: "failure" })]);
  await invoke(api, NOW + 4 * WINDOW);
  assert.equal(alerts(api).length, 0);
  assert.ok(api.issues[0].body.includes("workflow-execution-failure"));
});

test("workflow recovery requires two distinct fresh successful executions, not re-reading one", async () => {
  const api = fixture();
  for (let i = 0; i < 3; i++) {
    api.runs.set("sports-fixtures.yml", [run(NOW + i * WINDOW, { conclusion: "failure" })]);
    await invoke(api, NOW + i * WINDOW);
  }
  assert.equal(alerts(api).length, 0);
  api.runs.set("sports-fixtures.yml", [run(NOW + 3 * WINDOW)]);
  await invoke(api, NOW + 3 * WINDOW); await invoke(api, NOW + 4 * WINDOW);
  assert.equal(Object.values(ledger(api).ledger.incidents).find(r => r.source === "workflow-sports").state, "recovering");
  api.runs.set("sports-fixtures.yml", [run(NOW + 5 * WINDOW)]);
  await invoke(api, NOW + 5 * WINDOW);
  assert.equal(Object.values(ledger(api).ledger.incidents).find(r => r.source === "workflow-sports").state, "resolved");
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

test("human-owned marker is never overwritten and full ambiguous issue inventory fails closed", async () => {
  const api = fixture();
  api.issues.push({ number: 999, user: { login: "owner", type: "User" }, body: "<!-- fotty-watchdog-observer-ledger-v1 -->", state: "open" });
  await invoke(api, NOW); assert.equal(api.issues[0].body, "<!-- fotty-watchdog-observer-ledger-v1 -->");
  const crowded = fixture();
  for (let i = 1; i <= 200; i++) crowded.issues.push({ number: i, user: BOT, body: "Unrelated bot issue", state: "open" });
  await assert.rejects(() => invoke(crowded, NOW), /discovery bound/);
  assert.equal(crowded.calls.length, 2);
});


test("all source incidents and recoveries update one dashboard without comments or assignment", async () => {
  const api = fixture();
  const first = await invoke(api, NOW, status(NOW, { notifications: [notice()] }));
  assert.equal(first.delivered, 0); assert.equal(first.pending, 0);
  assert.equal(api.issues.length, 1); assert.match(api.issues[0].body, /cs \/ manifest: schema/);
  await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice(), notice(2, "resolved")] }));
  assert.equal(api.issues.length, 1); assert.equal(ownerComments(api).length, 0);
  assert.equal(ledger(api).deliveredCloud.length, 0, "dashboard write is not an owner delivery receipt");
  assert.ok(api.calls.every(c => !c.url.includes('/comments') && !JSON.parse(c.body || '{}').assignees));
  assert.ok(!api.issues[0].body.includes('@jetboss'));
});
test("monitor outages remain collected without generating provider issues", async () => {
  const api = fixture();
  for (const now of [NOW, NOW + WINDOW]) await runGitHubObserver({ token: 'fixture', request: api.request, now,
    statusRequest: async () => { throw new Error('offline'); } });
  assert.equal(api.issues.length, 1);
  assert.ok(Object.values(ledger(api).ledger.incidents).some(r => r.state === 'confirmed'));
  assert.equal(ownerComments(api).length, 0);
});
test("migration preserves old delivered receipts and does not touch historical alert issues", async () => {
  const api = fixture(); await invoke(api, NOW);
  const item = api.issues[0], state = ledger(api); state.deliveredCloud = ['f'.repeat(64)];
  item.body = item.body.replace(JSON.stringify(ledger(api)), JSON.stringify(state));
  const historical = { number: 900, user: BOT, body: '<!-- fotty-watchdog-incident-v1:' + 'e'.repeat(64) + ' --> historic', state: 'open' };
  api.issues.push(historical); const prior = structuredClone(historical);
  await invoke(api, NOW + WINDOW, status(NOW + WINDOW, { notifications: [notice()] }));
  assert.deepEqual(ledger(api).deliveredCloud, ['f'.repeat(64)]); assert.deepEqual(historical, prior);
  assert.equal(api.issues.length, 2);
});
test("failed or ambiguous dashboard writes remain retryable without duplicate issue creation", async () => {
  const api = fixture(); let lost = false;
  const request = async (url, options) => {
    const response = await api.request(url, options);
    if (!lost && options?.method === 'POST') { lost = true; throw new Error('lost response'); }
    return response;
  };
  await assert.rejects(() => runGitHubObserver({ token: 'fixture', request, statusRequest: async () => json(status()), now: NOW }));
  await invoke(api, NOW + WINDOW); assert.equal(api.issues.length, 1); assert.equal(ownerComments(api).length, 0);
});
test("retired canary cannot send a mention even with an old dispatch input", async () => {
  const result = await runDeliveryCanary({ request: () => { throw new Error('must not request'); } });
  assert.equal(result.retired, true); assert.equal(result.delivered, 0); assert.equal(result.apiRequests, 0);
});
