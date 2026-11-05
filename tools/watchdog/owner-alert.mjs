// Supplemental owner-chat bridge. It reads bounded public metadata and the
// owner's existing GitHub connection; it never probes streams or changes issues.
import { createHash, randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, readFile, rename, writeFile, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { cloudNotifications, WATCHDOG_STATUS_URL, REPOSITORY } from "./github-observer.mjs";
import { EXPECTED_VERSIONS } from "./manifest.mjs";
import { readMetadata } from "./source-probes.mjs";

import { advanceViewingIncidents, validateViewingState } from "./viewing-incidents.mjs";

const run = promisify(execFile);
const MAX_STATE = 256 * 1024, MAX_PENDING = 128, MAX_KNOWN = 1024;
const STALE = 35 * 60_000;
const statePath = () => join(homedir(), ".codex", "automation-state", "fotty-owner-provider-alerts-v1.json");
const hash = (v) => createHash("sha256").update(v).digest("hex");
const scalar = (v, max = 96) => typeof v === "string" && v.length <= max && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
const instant = (v) => typeof v === "number" ? v : typeof v === "string" ? Date.parse(v) : NaN;
const validTime = (v, now) => Number.isSafeInteger(instant(v)) && instant(v) >= 0 && instant(v) <= now + 30_000;
const fields = ["type", "source", "stage", "failureClass", "scope", "generation", "time"];
const blank = () => ({ schema: 1, initialized: false, known: [], pending: [], signals: {}, lastCheckedAt: null });
export function finiteEvent(value, now) {
  if (!value || !["confirmed", "resolved", "overflow", "delivery-test"].includes(value.type)
    || !["source", "stage", "failureClass", "scope"].every((k) => scalar(value[k]))
    || !Number.isSafeInteger(value.generation) || value.generation < 1
    || !validTime(value.time, now)) throw new Error("Invalid owner event");
  return Object.fromEntries(fields.map((k) => [k, value[k]]));
}
const eventToken = (event) => `WD-${hash(JSON.stringify(fields.map((k) => event[k]))).slice(0, 24)}`;
export function validateOwnerState(value, now = Date.now()) {
  if (!value || value.schema !== 1 || typeof value.initialized !== "boolean"
    || Object.keys(value).some((k) => !["schema", "initialized", "known", "pending", "signals", "lastCheckedAt", "viewing"].includes(k))
    || !Array.isArray(value.known) || value.known.length > MAX_KNOWN
    || new Set(value.known).size !== value.known.length || !value.known.every((v) => /^WD-[a-f0-9]{24}$/.test(v))
    || !Array.isArray(value.pending) || value.pending.length > MAX_PENDING
    || !value.signals || Array.isArray(value.signals) || typeof value.signals !== "object"
    || Object.keys(value.signals).length > 16
    || JSON.stringify(value).length > MAX_STATE) throw new Error("Invalid owner alert state");
  validateViewingState(value.viewing);
  for (const item of value.pending) {
    if (!item || item.receipt !== eventToken(finiteEvent(item.event, now))
      || !value.known.includes(item.receipt) || Object.keys(item).some((k) => !["receipt", "event"].includes(k))) throw new Error("Invalid pending owner alert");
  }
  for (const [key, val] of Object.entries(value.signals)) if (!scalar(key) || typeof val !== "boolean") throw new Error("Invalid monitor signal");
  if (new Set(value.pending.map((item) => item.receipt)).size !== value.pending.length) throw new Error("Duplicate pending owner receipt");
  if (value.lastCheckedAt !== null && !validTime(value.lastCheckedAt, now)) throw new Error("Invalid owner check time");
  return value;
}
export function extractIssueEvents(issues, now) {
  if (!Array.isArray(issues) || issues.length > 200) throw new Error("Owner issue inventory bound");
  const events = [], pendingDelivery = [];
  const start = "<!-- fotty-watchdog-data-v1:start -->\n```json\n", end = "\n```\n<!-- fotty-watchdog-data-v1:end -->";
  for (const issue of issues) {
    if (issue.pull_request || issue.user?.login !== "github-actions[bot]" || issue.user?.type !== "Bot") continue;
    if (typeof issue.body !== "string" || Buffer.byteLength(issue.body) > 64_000) throw new Error("Owner issue body bound");
    if (!/<!-- fotty-watchdog-(?:incident-v1:[a-f0-9]{64}|delivery-canary-v1) -->/.test(issue.body)) continue;
    const a = issue.body.indexOf(start), b = issue.body.indexOf(end);
    if (a < 0 || b < a || issue.body.indexOf(start, a + 1) !== -1 || issue.body.indexOf(end, b + 1) !== -1) throw new Error("Owner issue payload contract");
    const payload = JSON.parse(issue.body.slice(a + start.length, b));
    if (payload.schema !== 1) throw new Error("Owner issue schema");
    if (payload.lastEvent) events.push(finiteEvent(payload.lastEvent, now));
    if (payload.pendingEventHash && payload.lastEvent && now - instant(payload.lastEvent.time) > STALE) pendingDelivery.push(issue.number);
  }
  return { events, pendingDelivery };
}
function emailProblems(value, now, problems) {
  if (value === undefined) return; // Older deployed Workers have no email lane.
  try {
    const states = ["disabled", "configuration-pending", "awaiting-cutover", "cutover-expired", "configuration-mismatch", "clock-skew",
      "state-unavailable", "ready", "pending", "submitting", "rate-limited", "ambiguous", "retry-pending", "capacity"];
    const fields = ["enabled", "state", "pendingCount", "baselineCount", "submittedBatches", "attemptsToday", "ambiguousAttempts",
      "lastAttemptAt", "lastSubmittedAt", "lastError", "capacity", "oldestPendingAt"];
    if (!value || typeof value !== "object" || Array.isArray(value) || typeof value.enabled !== "boolean"
      || !states.includes(value.state) || Object.keys(value).some((key) => !fields.includes(key))) throw new Error("email contract");
    if (!value.enabled) { if (value.state !== "disabled") throw new Error("email disabled contract"); return; }
    if (["configuration-pending", "awaiting-cutover"].includes(value.state)) return;
    if (["cutover-expired", "configuration-mismatch", "state-unavailable", "clock-skew"].includes(value.state)) {
      problems.add("owner-email-unavailable"); return;
    }
    for (const key of ["pendingCount", "baselineCount", "submittedBatches", "attemptsToday", "ambiguousAttempts"]) {
      if (!Number.isSafeInteger(value[key]) || value[key] < 0) throw new Error("email counts");
    }
    if (typeof value.capacity !== "boolean" || ![null, "sender-not-verified", "recipient-not-allowed", "rate-limited",
      "service-rejected", "submission-ambiguous"].includes(value.lastError)
      || !["lastAttemptAt", "lastSubmittedAt", "oldestPendingAt"].every((key) => value[key] === null || validTime(value[key], now))
      || value.pendingCount > 0 && value.oldestPendingAt === null) throw new Error("email receipt");
    if (value.capacity || value.state === "capacity" || value.state === "rate-limited") problems.add("owner-email-capacity");
    if (value.pendingCount && value.lastError === "submission-ambiguous") problems.add("owner-email-submission-ambiguous");
    else if (value.pendingCount && value.lastError !== null) problems.add("owner-email-submission-rejected");
    if (value.pendingCount && now - instant(value.oldestPendingAt) > STALE) problems.add("owner-email-pending");
  } catch { problems.add("owner-email-status-contract"); }
}
export function evaluateOwnerSnapshot(input, { status, workflow, issues = [], unavailable = [] }, { now = Date.now(), initialize = false } = {}) {
  const state = structuredClone(input); validateOwnerState(state, now);
  if (!Number.isSafeInteger(now) || now < 0) throw new Error("Invalid owner clock");
  const problems = new Set(unavailable);
  let currentNotices = null;
  if (status) {
    try {
      if (status.schema !== 1 || status.activation !== "active"
        || status.observerRevision !== EXPECTED_VERSIONS.observerRevision
        || status.configurationRevision !== EXPECTED_VERSIONS.configurationRevision
        || !validTime(status.lastCompletedAt, now)) throw new Error("contract");
      if (now - instant(status.lastCompletedAt) > STALE) problems.add("collector-stale");
      if (status.expectedDeploymentRevision !== EXPECTED_VERSIONS.deploymentRevision) problems.add("playback-revision-drift");
      if (status.overflow) problems.add("cloud-ledger-capacity");
      const notices = cloudNotifications(status, now);
      if (!problems.has("collector-stale") && !problems.has("playback-revision-drift")) currentNotices = notices;
      emailProblems(status.ownerEmail, now, problems);
    } catch { problems.add("collector-status-contract"); }
  } else problems.add("collector-unavailable");
  try {
    const parsed = extractIssueEvents(issues, now);
    if (parsed.pendingDelivery.length) problems.add("owner-delivery-pending");
  } catch { problems.add("github-issue-contract"); }
  const completed = Array.isArray(workflow?.workflow_runs) ? workflow.workflow_runs.filter((v) => v.head_branch === "main"
    && v.status === "completed" && !/watchdog delivery test/i.test(v.display_title || "")
    && validTime(v.updated_at, now)).sort((a, b) => instant(b.updated_at) - instant(a.updated_at))[0] : null;
  if (!completed || now - instant(completed.updated_at) > STALE) problems.add("github-observer-stale");
  else if (completed.conclusion !== "success") problems.add("github-observer-failed");
  const queue = (event, baseline = false) => {
    const clean = finiteEvent(event, now), receipt = eventToken(clean);
    if (state.known.includes(receipt)) return;
    if (state.known.length >= MAX_KNOWN || !baseline && state.pending.length >= MAX_PENDING) throw new Error("Owner alert capacity; do not erase pending alerts");
    state.known.push(receipt); if (!baseline) state.pending.push({ receipt, event: clean });
  };
  // Preserve legacy receipt/known/pending state without replaying provider noise
  // or falsely acknowledging it. Only the new consolidated cases can alert.
  if (currentNotices !== null) {
    const next = advanceViewingIncidents(state.viewing, currentNotices, now);
    state.viewing = next.state;
    for (const event of next.events) queue(event);
  }
  for (const key of new Set([...Object.keys(state.signals), ...problems])) state.signals[key] = problems.has(key);
  state.initialized = true; state.lastCheckedAt = now; validateOwnerState(state, now);
  const alerts = state.pending.filter(item => item.event.source === "viewing");
  return { state, result: { schema: 1, action: alerts.length ? "notify" : "quiet", checkedAt: new Date(now).toISOString(),
    alerts, retainedLegacyPending: state.pending.length - alerts.length, knownObservations: state.known.length, monitorProblems: [...problems].sort(),
    channel: "supplemental Codex chat; GitHub is a quiet diagnostic dashboard",
    evidenceLimit: "Discovery endpoint failures only. Metadata cannot prove decoded playback, exhausted backups or playback recovery.",
    acknowledgement: "Only acknowledge a receipt after its notification appears in this chat. This is not proof of human reading." } };
}
export function acknowledgeOwnerReceipts(input, receipts) {
  const state = structuredClone(input); validateOwnerState(state);
  if (!Array.isArray(receipts) || !receipts.length || receipts.length > MAX_PENDING
    || !receipts.every((v) => /^WD-[a-f0-9]{24}$/.test(v) && state.known.includes(v))) throw new Error("Unrecognized owner receipt");
  state.pending = state.pending.filter((v) => !receipts.includes(v.receipt)); return validateOwnerState(state);
}
async function github(path) {
  if (!path.startsWith(`/repos/${REPOSITORY}/`) || /[\r\n]/.test(path)) throw new Error("Unreviewed owner GitHub request");
  const { stdout } = await run("gh", ["api", path], { timeout: 15_000, maxBuffer: 2 * 1024 * 1024 });
  return JSON.parse(stdout);
}
export async function collectOwnerSnapshot({ request = fetch, githubRead = github } = {}) {
  const snapshot = { unavailable: [] };
  await Promise.all([
    (async () => { try { const result = await readMetadata(WATCHDOG_STATUS_URL, { request, maxBytes: 512 * 1024 });
      if (result.failure) throw new Error("status"); snapshot.status = JSON.parse(result.text); } catch { snapshot.unavailable.push("collector-unavailable"); } })(),
    (async () => { try { snapshot.workflow = await githubRead(`/repos/${REPOSITORY}/actions/workflows/watchdog-observer.yml/runs?branch=main&per_page=5`); }
      catch { snapshot.unavailable.push("github-observer-unavailable"); } })(),
    (async () => { try { snapshot.issues = await githubRead(`/repos/${REPOSITORY}/issues?state=all&creator=github-actions%5Bbot%5D&per_page=100&page=1`);
      if (!Array.isArray(snapshot.issues)) throw new Error("issues");
      if (snapshot.issues.length === 100) { const next = await githubRead(`/repos/${REPOSITORY}/issues?state=all&creator=github-actions%5Bbot%5D&per_page=100&page=2`);
        if (!Array.isArray(next) || next.length >= 100) throw new Error("inventory capacity"); snapshot.issues.push(...next); }
    } catch { snapshot.issues = []; snapshot.unavailable.push("github-issues-unavailable"); } })(),
  ]);
  return snapshot;
}
async function load(path) { try { const text = await readFile(path, "utf8"); if (Buffer.byteLength(text) > MAX_STATE) throw new Error("Owner state bound"); return validateOwnerState(JSON.parse(text)); }
  catch (error) { if (error.code === "ENOENT") return blank(); throw error; } }
async function save(path, state) {
  validateOwnerState(state); await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.${randomUUID()}.tmp`;
  try { await writeFile(temporary, JSON.stringify(state), { mode: 0o600, flag: "wx" }); await rename(temporary, path); }
  finally { await unlink(temporary).catch((e) => { if (e.code !== "ENOENT") throw e; }); }
}
export async function ownerAlertCLI(args = process.argv.slice(2)) {
  const [mode, ...rest] = args, path = statePath(), state = await load(path);
  if (mode === "ack") { const next = acknowledgeOwnerReceipts(state, rest); await save(path, next); return { acknowledged: rest }; }
  if (mode !== "poll" || rest.some((v) => v !== "--initialize")) throw new Error("Use poll [--initialize] or ack RECEIPT...");
  const { state: next, result } = evaluateOwnerSnapshot(state, await collectOwnerSnapshot(), { initialize: rest.includes("--initialize") });
  await save(path, next); return result;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) ownerAlertCLI().then((v) => console.log(JSON.stringify(v)))
  .catch(() => { console.error("Fotty owner-alert bridge failed; retain pending state; monitoring diagnostics unavailable, viewing impact unproven."); process.exitCode = 1; });
