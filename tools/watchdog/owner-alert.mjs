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
    || Object.keys(value).some((k) => !["schema", "initialized", "known", "pending", "signals", "lastCheckedAt"].includes(k))
    || !Array.isArray(value.known) || value.known.length > MAX_KNOWN
    || new Set(value.known).size !== value.known.length || !value.known.every((v) => /^WD-[a-f0-9]{24}$/.test(v))
    || !Array.isArray(value.pending) || value.pending.length > MAX_PENDING
    || !value.signals || Array.isArray(value.signals) || typeof value.signals !== "object"
    || Object.keys(value.signals).length > 16
    || JSON.stringify(value).length > MAX_STATE) throw new Error("Invalid owner alert state");
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
export function evaluateOwnerSnapshot(input, { status, workflow, issues = [], unavailable = [] }, { now = Date.now(), initialize = false } = {}) {
  const state = structuredClone(input); validateOwnerState(state, now);
  if (!Number.isSafeInteger(now) || now < 0) throw new Error("Invalid owner clock");
  const events = [], problems = new Set(unavailable);
  if (status) {
    try {
      if (status.schema !== 1 || status.activation !== "active"
        || status.observerRevision !== EXPECTED_VERSIONS.observerRevision
        || status.configurationRevision !== EXPECTED_VERSIONS.configurationRevision
        || !validTime(status.lastCompletedAt, now)) throw new Error("contract");
      if (now - instant(status.lastCompletedAt) > STALE) problems.add("collector-stale");
      if (status.expectedDeploymentRevision !== EXPECTED_VERSIONS.deploymentRevision) problems.add("playback-revision-drift");
      if (status.overflow) problems.add("cloud-ledger-capacity");
      events.push(...cloudNotifications(status, now).map((v) => finiteEvent(v, now)));
    } catch { problems.add("collector-status-contract"); }
  } else problems.add("collector-unavailable");
  try {
    const parsed = extractIssueEvents(issues, now); events.push(...parsed.events);
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
  // Explicit bootstrap records historical observations, never claims prior human
  // receipt, and never baselines monitor blindness or future transitions away.
  for (const event of events) queue(event, initialize && !state.initialized && event.type !== "delivery-test");
  for (const key of new Set([...Object.keys(state.signals), ...problems])) {
    const failed = problems.has(key);
    if (failed !== (state.signals[key] || false)) queue({ type: failed ? "confirmed" : "resolved", source: "owner-monitor",
      stage: "delivery", failureClass: key, scope: "production", generation: 1, time: new Date(now).toISOString() });
    state.signals[key] = failed;
  }
  state.initialized = true; state.lastCheckedAt = now; validateOwnerState(state, now);
  return { state, result: { schema: 1, action: state.pending.length ? "notify" : "quiet", checkedAt: new Date(now).toISOString(),
    alerts: state.pending, knownObservations: state.known.length, monitorProblems: [...problems].sort(),
    channel: "supplemental Codex chat; GitHub targeted notices are the cloud channel",
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
  .catch(() => { console.error("Fotty owner-alert bridge failed; retain pending state and notify the owner of monitoring failure."); process.exitCode = 1; });
