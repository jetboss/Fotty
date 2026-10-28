// Independent, bounded observer. It never starts the Worker, collects media,
// repairs sources, reads native telemetry, or interprets fixtures as fresh.
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import { createPolicy, emptyLedger, validateLedger, listNotifications, missedRunObservations, normalizeFacts } from "./incident-policy.mjs";
import { applyObservationBatch } from "./observation-batch.mjs";
import { EXPECTED_VERSIONS, observerPolicyOptions, WATCHDOG_ORIGIN, COLLECTION_INTERVAL_MS, CONFIRMATION_WINDOWS } from "./manifest.mjs";
import { readMetadata } from "./source-probes.mjs";

export const WATCHDOG_STATUS_URL = `${WATCHDOG_ORIGIN}/status`;
export const REPOSITORY = "jetboss/Fotty";
// Repository owner verified through GitHub's repository API. Assignment and a
// bot-authored mention request delivery; neither is proof that a human read it.
export const OWNER = "jetboss";
export const CORRECTED_BASELINE = "243f9bb662b2b1a42f187bd324071c654aa26884";
export const WORKFLOWS = Object.freeze([
  { source: "workflow-sports", file: "sports-fixtures.yml", deadlineMs: 3 * 3600_000 },
  { source: "workflow-cricket", file: "cricket-fixtures.yml", deadlineMs: 3 * 3600_000 },
  { source: "workflow-provider", file: "provider-monitor.yml", deadlineMs: 30 * 3600_000 },
]);
const WINDOW = COLLECTION_INTERVAL_MS, STALE = 35 * 60_000, MAX_API = 32, MAX_DELIVERIES = 8;
const LEDGER_MARKER = "<!-- fotty-watchdog-observer-ledger-v1 -->";
const CANARY_MARKER = "<!-- fotty-watchdog-delivery-canary-v1 -->";
const PAYLOAD_START = "<!-- fotty-watchdog-data-v1:start -->\n```json\n";
const PAYLOAD_END = "\n```\n<!-- fotty-watchdog-data-v1:end -->";
const SUMMARY_START = "<!-- fotty-watchdog-summary-v1:start -->\n", SUMMARY_END = "\n<!-- fotty-watchdog-summary-v1:end -->";
const sha = (value) => createHash("sha256").update(value).digest("hex");
const scalar = (value, limit = 96) => typeof value === "string" && value.length <= limit
  && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value) && !/(?:bearer|password|cookie|authorization|token=)/i.test(value);
const validSHA = (value) => typeof value === "string" && /^[a-f0-9]{40}$/.test(value);
const validHash = (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const time = (value) => value == null ? null : typeof value === "number" ? value : Date.parse(value);
const validTime = (value) => Number.isSafeInteger(value) && value >= 0;
const policy = createPolicy({ environment: "github-observer", windowMs: WINDOW, failureWindows: CONFIRMATION_WINDOWS, recoveryWindows: 2,
  maxReceiptAgeMs: 31 * 3600_000,
  limits: { active: 16, resolved: 16, outbox: 64, ledgerBytes: 24_000 }, admittedSources: [
    { source: "observer", stages: ["liveness"], activation: "active", expected: EXPECTED_VERSIONS },
    ...WORKFLOWS.map(({ source }) => ({ source, stages: ["workflow"], activation: "active", expected: EXPECTED_VERSIONS })),
  ] });
const observation = (source, stage, outcome, failureClass, now, facts = {}) => ({ environment: policy.environment,
  source, stage, outcome, failureClass, facts, observedAt: now, checkedAt: now, versions: { ...EXPECTED_VERSIONS } });

function statusContractFailure(body, now) {
  if (!body || body.schema !== 1 || body.intervalMs !== WINDOW || !["active", "pending"].includes(body.activation)
    || !scalar(body.expectedDeploymentRevision)) return "invalid-contract";
  if (body.observerRevision !== EXPECTED_VERSIONS.observerRevision
    || body.configurationRevision !== EXPECTED_VERSIONS.configurationRevision) return "version-mismatch";
  const times = [body.lastAttemptedAt, body.lastCompletedAt, body.activatedAt].map(time);
  if (body.activation === "active" && times[2] == null
    || times.some((value) => value != null && (!validTime(value) || value > now + 30_000))) return "invalid-time";
  return null;
}
export function statusObservations(body, now) {
  const failure = (code) => [observation("observer", "liveness", "failure", "status-contract", now,
    { dimension: "identity", code })];
  const invalid = statusContractFailure(body, now);
  if (invalid) return failure(invalid);
  const times = [body.lastAttemptedAt, body.lastCompletedAt, body.activatedAt].map(time);
  const deploymentMatches = body.expectedDeploymentRevision === EXPECTED_VERSIONS.deploymentRevision;
  // A metadata deployment drift is its own incident. It cannot suppress durable
  // notices from the still-compatible observer/configuration wire contract.
  return [observation("observer", "liveness", body.activation !== "active" ? "inactive" : deploymentMatches ? "success" : "failure",
    deploymentMatches ? "status-check" : "status-contract", now,
    { dimension: "identity", code: "version-mismatch" }),
    observation("observer", "liveness", body.activation === "active" ? "success" : "inactive", "status-check", now,
      { dimension: "identity", code: "invalid-contract" }),
    observation("observer", "liveness", body.activation === "active" ? "success" : "inactive", "status-check", now,
      { dimension: "identity", code: "invalid-time" }),
    observation("observer", "liveness", body.activation === "active" ? "success" : "inactive", "status-check", now),
    ...missedRunObservations({ environment: policy.environment, source: "observer", stage: "liveness",
      activation: body.activation, intervalMs: WINDOW, graceMs: STALE - WINDOW, startedAt: times[2],
      lastAttemptedAt: times[0], lastCompletedAt: times[1], versions: EXPECTED_VERSIONS }, now)];
}

// Cloud notices are already durable. Read-only delivery cannot acknowledge or
// erase them; exact IDs are retained independently to survive process restart.
export function cloudNotifications(body, now = Date.now()) {
  if (body?.activation !== "active" || statusContractFailure(body, now)) return [];
  if (!Array.isArray(body.notifications) || body.notifications.length > 513) throw new Error("Invalid notification count");
  const sources = observerPolicyOptions().admittedSources;
  const ids = new Set(); let priorSequence = 0;
  return body.notifications.map((event) => {
    const fields = ["id", "type", "incidentId", "source", "stage", "failureClass", "scope", "generation", "time"];
    if (!event || Object.keys(event).some((key) => !fields.includes(key))
      || !/^production:notice:[1-9][0-9]{0,15}$/.test(event.id) || ids.has(event.id)
      || !["confirmed", "resolved", "overflow"].includes(event.type) || !validHash(event.incidentId)
      || !scalar(event.source, 64) || !scalar(event.stage, 64) || !scalar(event.failureClass, 64) || !scalar(event.scope)
      || !Number.isSafeInteger(event.generation) || event.generation < 1 || typeof event.time !== "string"
      || !validTime(time(event.time)) || new Date(time(event.time)).toISOString() !== event.time
      || time(event.time) > now + 30_000) throw new Error("Invalid notification");
    const sequence = Number(event.id.split(":").at(-1));
    if (!Number.isSafeInteger(sequence) || sequence <= priorSequence) throw new Error("Unordered notification sequence");
    priorSequence = sequence;
    if (event.type === "overflow" ? event.source !== "watchdog-ledger" || event.stage !== "storage" || event.failureClass !== "capacity"
      : !sources.some((source) => source.source === event.source && source.stages.includes(event.stage))) throw new Error("Unreviewed notification");
    ids.add(event.id); return { ...event };
  });
}

export function createGitHubClient({ token, request = fetch, maxRequests = MAX_API } = {}) {
  if (typeof token !== "string" || !token || !Number.isInteger(maxRequests) || maxRequests < 1 || maxRequests > MAX_API) throw new Error("Invalid GitHub configuration");
  let used = 0;
  return { get requestCount() { return used; }, async call(path, { method = "GET", body } = {}) {
    if (!path.startsWith(`/repos/${REPOSITORY}/`) || !["GET", "POST", "PATCH"].includes(method)) throw new Error("Unreviewed GitHub request");
    if (used >= maxRequests) throw new Error("GitHub request bound");
    used++;
    const response = await request(`https://api.github.com${path}`, { method, redirect: "error", signal: AbortSignal.timeout(10_000),
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28",
        ...(body ? { "Content-Type": "application/json" } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
    if (!response.ok) { await response.body?.cancel(); const error = new Error("GitHub request failed"); error.status = response.status; throw error; }
    // GitHub creates issues with 201, not 200. Adapt a verified successful
    // response to the metadata reader without bypassing its streaming bound.
    const data = await readMetadata("https://api.github.com", { maxBytes: 2 * 1024 * 1024,
      request: async () => new Response(response.body, { status: 200, headers: response.headers }) });
    if (data.failure) throw new Error("GitHub response bound");
    return JSON.parse(data.text);
  } };
}

export async function collectWorkflowObservations(client, { now, startedAt = null } = {}) {
  const receipts = [], comparisons = new Map(); let mainSHA;
  try { mainSHA = (await client.call(`/repos/${REPOSITORY}/git/ref/heads/main`)).object?.sha; }
  catch { return WORKFLOWS.map(({ source }) => observation(source, "workflow", "unknown", "workflow-check", now)); }
  if (!validSHA(mainSHA)) return WORKFLOWS.map(({ source }) => observation(source, "workflow", "unknown", "workflow-check", now));
  async function reviewed(head) {
    if (!validSHA(head)) return false;
    if (head === mainSHA) return true;
    if (!comparisons.has(head)) comparisons.set(head, (async () => {
      try {
        const result = await client.call(`/repos/${REPOSITORY}/compare/${CORRECTED_BASELINE}...${head}`);
        return ["ahead", "identical"].includes(result.status) && result.merge_base_commit?.sha === CORRECTED_BASELINE;
      } catch { return false; }
    })());
    return comparisons.get(head);
  }
  for (const descriptor of WORKFLOWS) {
    const facts = { scope: descriptor.file.replace(/\.yml$/, ""), dimension: "execution" };
    let body;
    try { body = await client.call(`/repos/${REPOSITORY}/actions/workflows/${descriptor.file}/runs?branch=main&per_page=5`); }
    catch (error) { receipts.push(observation(descriptor.source, "workflow", error.status === 404 ? "inactive" : "failure", "workflow-api", now,
      { ...facts, dimension: "api" })); continue; }
    if (!Array.isArray(body.workflow_runs) || body.workflow_runs.length > 5) {
      receipts.push(observation(descriptor.source, "workflow", "unknown", "workflow-check", now, facts)); continue;
    }
    receipts.push(observation(descriptor.source, "workflow", "success", "workflow-api", now, { ...facts, dimension: "api" }));
    const eligible = [];
    for (const run of body.workflow_runs) {
      if (run.head_branch !== "main" || !["queued", "in_progress", "completed", "waiting", "requested", "pending"].includes(run.status)
        || !validTime(time(run.created_at)) || !validTime(time(run.updated_at)) || time(run.updated_at) > now + 30_000) continue;
      if (await reviewed(run.head_sha)) eligible.push(run);
    }
    eligible.sort((a, b) => time(b.created_at) - time(a.created_at));
    const completed = eligible.filter((run) => run.status === "completed").sort((a, b) => time(b.updated_at) - time(a.updated_at))[0];
    if (completed && now - time(completed.updated_at) <= descriptor.deadlineMs
      && ["success", "failure", "timed_out", "action_required", "startup_failure"].includes(completed.conclusion)) {
      receipts.push(observation(descriptor.source, "workflow", completed.conclusion === "success" ? "success" : "failure",
        "workflow-execution-failure", now, facts));
      // Re-reading one completed job is not another failed execution or a new
      // recovery check. Preserve its published check time; API fetch is fresh.
      receipts.at(-1).checkedAt = time(completed.updated_at);
    } else receipts.push(observation(descriptor.source, "workflow", "unknown", "workflow-execution-failure", now, facts));
    // Old/unverified heads cannot establish a current failure, heartbeat or
    // recovery. No published runs at all may establish absence after activation.
    const origin = completed ? time(completed.updated_at) : eligible.length || body.workflow_runs.length === 0 ? time(startedAt) : null;
    receipts.push(observation(descriptor.source, "workflow", origin == null ? "unknown"
      : now - origin > descriptor.deadlineMs ? "failure" : completed ? "success" : "unknown", "missing_run", now,
      { ...facts, dimension: "completed" }));
  }
  return receipts;
}

function botOwned(issue) { return issue && !issue.pull_request && Number.isSafeInteger(issue.number) && issue.number > 0
  && issue.user?.type === "Bot" && issue.user.login === "github-actions[bot]"; }
function parsePayload(issue) {
  if (!botOwned(issue) || typeof issue.body !== "string" || Buffer.byteLength(issue.body) > 64_000) throw new Error("Unsafe observer issue");
  const start = issue.body.indexOf(PAYLOAD_START), end = issue.body.indexOf(PAYLOAD_END);
  if (start < 0 || end < start || issue.body.indexOf(PAYLOAD_START, start + 1) !== -1 || issue.body.indexOf(PAYLOAD_END, end + 1) !== -1) throw new Error("Invalid observer payload");
  return JSON.parse(issue.body.slice(start + PAYLOAD_START.length, end));
}
function replacePayload(issue, prefix, payload) {
  const encoded = JSON.stringify(payload);
  if (Buffer.byteLength(encoded) > 60_000) throw new Error("Observer issue capacity");
  if (!issue) return `${prefix}\n${PAYLOAD_START}${encoded}${PAYLOAD_END}`;
  parsePayload(issue);
  const start = issue.body.indexOf(PAYLOAD_START), end = issue.body.indexOf(PAYLOAD_END) + PAYLOAD_END.length;
  const result = issue.body.slice(0, start) + PAYLOAD_START + encoded + PAYLOAD_END + issue.body.slice(end);
  if (Buffer.byteLength(result) > 64_000) throw new Error("Observer issue capacity");
  return result;
}
function alertSummary(body, event) {
  const summary = `Fotty watchdog ${event.type}: ${event.source} / ${event.stage} / ${event.failureClass}.`;
  const start = body.indexOf(SUMMARY_START), end = body.indexOf(SUMMARY_END);
  if (start >= 0 && end > start && body.indexOf(SUMMARY_START, start + 1) === -1 && body.indexOf(SUMMARY_END, end + 1) === -1)
    return body.slice(0, start) + SUMMARY_START + summary + SUMMARY_END + body.slice(end + SUMMARY_END.length);
  if (start >= 0 || end >= 0) throw new Error("Invalid bot summary region");
  const markerEnd = body.indexOf("-->") + 3;
  return body.slice(0, markerEnd) + `\n${SUMMARY_START}${summary}${SUMMARY_END}` + body.slice(markerEnd);
}
function validateState(state) {
  if (!state || state.schema !== 1 || Object.keys(state).some((key) => !["schema", "ledger", "deliveredCloud"].includes(key))
    || !Array.isArray(state.deliveredCloud) || state.deliveredCloud.length > 513
    || new Set(state.deliveredCloud).size !== state.deliveredCloud.length || !state.deliveredCloud.every(validHash)) throw new Error("Invalid independent state");
  validateLedger(state.ledger, policy); return state;
}
async function inventory(client) {
  const issues = [];
  for (let page = 1; page <= 2; page++) {
    const batch = await client.call(`/repos/${REPOSITORY}/issues?state=all&creator=github-actions%5Bbot%5D&per_page=100&page=${page}`);
    if (!Array.isArray(batch) || batch.length > 100) throw new Error("Invalid issue inventory");
    issues.push(...batch.filter(botOwned));
    if (batch.length < 100) return issues;
  }
  throw new Error("Observer issue discovery bound; no ambiguous creation");
}
function uniqueIssue(issues, marker) {
  const found = issues.filter((issue) => typeof issue.body === "string" && issue.body.includes(marker));
  if (found.length > 1) throw new Error("Duplicate observer issue markers");
  return found[0];
}

function deliveryPayload(issue) {
  const payload = issue ? parsePayload(issue) : { schema: 1, eventHashes: [] };
  if (payload.schema !== 1 || !Array.isArray(payload.eventHashes) || payload.eventHashes.length > 513
    || !payload.eventHashes.every(validHash) || new Set(payload.eventHashes).size !== payload.eventHashes.length
    || (payload.pendingEventHash !== undefined && (!validHash(payload.pendingEventHash)
      || payload.eventHashes.includes(payload.pendingEventHash)))) throw new Error("Invalid delivery ledger");
  return payload;
}
function ownerAssigned(issue) { return Array.isArray(issue?.assignees)
  && issue.assignees.some((assignee) => assignee.login === OWNER && assignee.type === "User"); }
function ownerAssignees(issue) {
  const logins = (issue?.assignees ?? []).map((row) => row.login);
  if (logins.some((login) => typeof login !== "string" || !/^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/.test(login))) throw new Error("Invalid issue assignees");
  const result = [...new Set([...logins, OWNER])];
  if (result.length > 10) throw new Error("Issue assignee capacity");
  return result;
}
function ownerComment(eventHash, event, canary) {
  const summary = canary ? "Fotty watchdog delivery test — not a provider outage."
    : `Fotty watchdog ${event.type}: ${event.source} / ${event.stage} / ${event.failureClass}.`;
  return `<!-- fotty-watchdog-owner-event-v1:${eventHash} -->\n@${OWNER} ${summary}\n`
    + `Scope: ${event.scope}. Generation: ${event.generation}. Observed: ${event.time}.\n`
    + "Bot delivery receipt only; human reading or email receipt is not confirmed. No automated repair.";
}
function verifiedComment(comment, body) {
  return Number.isSafeInteger(comment?.id) && comment.id > 0 && comment.user?.type === "Bot"
    && comment.user.login === "github-actions[bot]" && comment.body === body;
}
async function findOwnerComment(client, issue, marker, body) {
  const found = [];
  for (let page = 1; page <= 2; page++) {
    const batch = await client.call(`/repos/${REPOSITORY}/issues/${issue.number}/comments?per_page=100&page=${page}`);
    if (!Array.isArray(batch) || batch.length > 100) throw new Error("Invalid comment inventory");
    found.push(...batch.filter((comment) => typeof comment.body === "string" && comment.body.includes(marker)));
    if (batch.length < 100) {
      if (found.length > 1 || found.some((comment) => !verifiedComment(comment, body))) throw new Error("Ambiguous owner comment");
      return found[0];
    }
  }
  throw new Error("Owner comment discovery bound; no ambiguous creation");
}
async function deliverOwnerEvent(client, issues, { event, eventHash, marker, canary = false }) {
  let issue = uniqueIssue(issues, marker);
  const payload = deliveryPayload(issue);
  // Existing hashes are historical issue-write receipts. Do not replay the
  // pre-upgrade backlog as mentions; the next real transition uses this path.
  if (payload.eventHashes.includes(eventHash)) return { delivered: false, issueNumber: issue.number };
  if (payload.pendingEventHash && payload.pendingEventHash !== eventHash) throw new Error("Prior owner delivery is pending");
  if (payload.eventHashes.length >= 513) throw new Error("Alert issue capacity");
  const finiteEvent = Object.fromEntries(["type", "source", "stage", "failureClass", "scope", "generation", "time"].map((key) => [key, event[key]]));
  const prefix = canary ? `${marker}\nDelivery test only; not a provider incident or recovery.`
    : `${marker}\nMetadata observation only; no automated repair.`;
  const state = canary || event.type !== "resolved" ? "open" : "closed";
  async function write(payloadValue) {
    const body = canary ? replacePayload(issue, prefix, payloadValue)
      : alertSummary(replacePayload(issue, prefix, payloadValue), finiteEvent);
    const saved = await client.call(`/repos/${REPOSITORY}/issues${issue ? `/${issue.number}` : ""}`, {
      method: issue ? "PATCH" : "POST", body: { ...(issue ? {} : { title: canary
        ? "Fotty watchdog delivery test — not provider outage" : `Fotty watchdog: ${event.source} / ${event.stage}` }),
      body, state, assignees: ownerAssignees(issue) },
    });
    if (!botOwned(saved) || saved.body !== body || saved.state !== state || !ownerAssigned(saved)) throw new Error("Owner issue write not verified");
    const updated = { ...saved, body };
    if (issue) issues.splice(issues.indexOf(issue), 1, updated); else issues.push(updated);
    issue = updated;
  }
  const wasNew = !issue;
  // Staging is deliberately not a delivery receipt. After an ambiguous issue or
  // comment response, restart can find the marker before attempting a new POST.
  if (payload.pendingEventHash !== eventHash || !ownerAssigned(issue) || issue.state !== state)
    await write({ schema: 1, eventHashes: payload.eventHashes, pendingEventHash: eventHash, lastEvent: finiteEvent });
  const body = ownerComment(eventHash, finiteEvent, canary);
  const commentMarker = body.slice(0, body.indexOf("\n"));
  const prior = wasNew ? null : await findOwnerComment(client, issue, commentMarker, body);
  if (!prior) {
    const comment = await client.call(`/repos/${REPOSITORY}/issues/${issue.number}/comments`, { method: "POST", body: { body } });
    if (!verifiedComment(comment, body)) throw new Error("Owner comment write not verified");
  }
  // Only a verified issue assignment AND the exact bot mention allow the durable
  // event hash to advance. This is channel submission, never human acknowledgement.
  await write({ schema: 1, eventHashes: [...payload.eventHashes, eventHash], lastEvent: finiteEvent });
  return { delivered: true, issueNumber: issue.number };
}

export async function runDeliveryCanary({ token = process.env.GITHUB_TOKEN, request = fetch,
  runId = process.env.GITHUB_RUN_ID, now = Date.now() } = {}) {
  if (!validTime(now) || typeof runId !== "string" || !/^[1-9][0-9]{0,19}$/.test(runId)) throw new Error("Invalid delivery test identity");
  const client = createGitHubClient({ token, request }), issues = await inventory(client);
  const eventHash = sha(`delivery-test:${runId}`), existing = uniqueIssue(issues, CANARY_MARKER);
  const payload = deliveryPayload(existing);
  const prior = payload.lastEvent;
  if (payload.pendingEventHash && (prior?.type !== "delivery-test" || prior.source !== "observer" || prior.stage !== "delivery"
    || prior.failureClass !== "canary" || prior.scope !== "owner" || prior.generation !== 1
    || !validTime(time(prior.time)) || new Date(time(prior.time)).toISOString() !== prior.time || time(prior.time) > now + 30_000))
    throw new Error("Invalid pending delivery test");
  if (payload.pendingEventHash && payload.pendingEventHash !== eventHash) {
    // A later explicit test first completes its retained predecessor. This keeps
    // retry possible after a new dispatch without overtaking an ambiguous POST.
    await deliverOwnerEvent(client, issues, { event: prior, eventHash: payload.pendingEventHash, marker: CANARY_MARKER, canary: true });
  }
  // The event's time remains stable on workflow reruns, including a response lost
  // after comment creation. A dispatch with a new run ID is a new explicit test.
  const event = { type: "delivery-test", source: "observer", stage: "delivery", failureClass: "canary", scope: "owner",
    generation: 1, time: payload.pendingEventHash === eventHash && prior?.type === "delivery-test" ? prior.time : new Date(now).toISOString() };
  const result = await deliverOwnerEvent(client, issues, { event, eventHash, marker: CANARY_MARKER, canary: true });
  return { deliveryTest: true, issueNumber: result.issueNumber, delivered: Number(result.delivered),
    humanAcknowledged: false, apiRequests: client.requestCount };
}

export async function runGitHubObserver({ token = process.env.GITHUB_TOKEN, request = fetch, statusRequest = fetch, now = Date.now() } = {}) {
  if (!validTime(now)) throw new Error("Invalid observer clock");
  const client = createGitHubClient({ token, request }), issues = await inventory(client);
  let ledgerIssue = uniqueIssue(issues, LEDGER_MARKER);
  const state = ledgerIssue ? validateState(parsePayload(ledgerIssue)) : { schema: 1, ledger: emptyLedger(policy), deliveredCloud: [] };
  let status, receipts, notices = [];
  try {
    const result = await readMetadata(WATCHDOG_STATUS_URL, { request: statusRequest, maxBytes: 512 * 1024 });
    if (result.failure) throw new Error("Observer status unavailable");
    try { status = JSON.parse(result.text); }
    catch { receipts = [observation("observer", "liveness", "failure", "status-contract", now,
      { dimension: "identity", code: "invalid-contract" })]; }
    receipts ??= statusObservations(status, now);
    try { notices = cloudNotifications(status, now); }
    catch { receipts.push(observation("observer", "liveness", "failure", "status-contract", now,
      { dimension: "identity", code: "invalid-contract" })); }
  } catch { receipts = [observation("observer", "liveness", "failure", "status-transport", now)]; }
  receipts.push(...await collectWorkflowObservations(client, { now, startedAt: status?.activatedAt }));
  // An incomplete check cannot preserve a suspect failure streak or manufacture
  // recovery. Reset only unresolved incidents on the exact unknown path.
  for (const record of Object.values(state.ledger.incidents)) {
    if (record.state === "resolved" || receipts.some((row) => row.source === record.source && row.stage === record.stage
      && row.failureClass === record.failureClass && JSON.stringify(normalizeFacts(row.facts)) === JSON.stringify(record.facts))) continue;
    const path = receipts.filter((row) => row.source === record.source && row.stage === record.stage);
    if (path.length && !path.some((row) => row.outcome === "success")) receipts.push(observation(record.source, record.stage,
      path.every((row) => row.outcome === "inactive") ? "inactive" : "unknown", record.failureClass, now, record.facts));
  }
  const result = applyObservationBatch(state.ledger, receipts, policy, now);
  state.ledger = result.state; state.ledger.revision++;
  validateState(state);
  async function saveLedger() {
    const body = replacePayload(ledgerIssue, `${LEDGER_MARKER}\nIndependent monitoring state; not a fixture freshness certificate.`, state);
    const saved = await client.call(`/repos/${REPOSITORY}/issues${ledgerIssue ? `/${ledgerIssue.number}` : ""}`,
      { method: ledgerIssue ? "PATCH" : "POST", body: { ...(ledgerIssue ? {} : { title: "Fotty watchdog independent observer state" }), body } });
    if (!botOwned(saved) || saved.body !== body) throw new Error("Observer ledger write not verified");
    ledgerIssue = { ...saved, body };
  }
  // First persist observation transitions. A crash or delivery failure then
  // retries their retained outbox rather than losing or recreating an alert.
  await saveLedger();
  const events = [
    ...listNotifications(state.ledger, policy).map((event) => ({ ...event, incidentId: sha(event.key), namespace: "independent", lane: "independent" })),
    ...notices.map((event) => ({ ...event, namespace: `cloud-${EXPECTED_VERSIONS.observerRevision}`, lane: "cloud" })),
  ];
  let delivered = 0, pending = 0, dirty = false;
  const blockedMarkers = new Set();
  for (const event of events) {
    const eventHash = sha(`${event.namespace}:${event.id}`), marker = `<!-- fotty-watchdog-incident-v1:${sha(`${event.lane}:${event.incidentId}`)} -->`;
    if (event.namespace.startsWith("cloud-") && state.deliveredCloud.includes(eventHash)) continue;
    // A later recovery cannot overtake a failed/ambiguous confirmation write.
    // Otherwise retrying the older event could reopen an already-resolved issue.
    if (blockedMarkers.has(marker)) { pending++; continue; }
    const issue = uniqueIssue(issues, marker), payload = deliveryPayload(issue);
    if (!payload.eventHashes.includes(eventHash)) {
      // Reserve the final ledger write and the worst-case bounded comment scan.
      if (delivered >= MAX_DELIVERIES || client.requestCount > MAX_API - 1 - (issue ? 5 : 3)) {
        blockedMarkers.add(marker); pending++; continue;
      }
      try {
        const delivery = await deliverOwnerEvent(client, issues, { event, eventHash, marker });
        delivered += Number(delivery.delivered);
      } catch { blockedMarkers.add(marker); pending++; continue; }
    }
    if (event.namespace.startsWith("cloud-") && !state.deliveredCloud.includes(eventHash)) {
      state.deliveredCloud.push(eventHash); dirty = true;
    }
  }
  if (dirty) { validateState(state); await saveLedger(); }
  return { ledgerIssue: ledgerIssue.number, confirmedChanges: result.events.length, delivered, pending, apiRequests: client.requestCount };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const canary = process.env.FOTTY_WATCHDOG_DELIVERY_CANARY;
  const action = canary === "true" ? runDeliveryCanary : canary == null || canary === "false" ? runGitHubObserver : null;
  Promise.resolve().then(() => { if (!action) throw new Error("Invalid delivery test flag"); return action(); }).then((result) => {
    console.log(JSON.stringify(result));
    // Pending/ambiguous notification writes are degraded delivery, not a green
    // workflow. Their staged receipts remain intact for the next bounded retry.
    if (result.pending > 0) process.exitCode = 1;
  }).catch(() => {
    console.error("Fotty independent watchdog could not complete; retained alerts will retry."); process.exitCode = 1;
  });
}
