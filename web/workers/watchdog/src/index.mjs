import { createPolicy, emptyLedger, validateLedger, listNotifications } from "../../../../tools/watchdog/incident-policy.mjs";
import { applyObservationBatch } from "../../../../tools/watchdog/observation-batch.mjs";
import { observerPolicyOptions, PROVIDERS, OBSERVER_REVISION, CONFIGURATION_REVISION, EXPECTED_VERSIONS, COLLECTION_INTERVAL_MS, CONFIRMATION_WINDOWS } from "../../../../tools/watchdog/manifest.mjs";
import { probeSources } from "../../../../tools/watchdog/source-probes.mjs";
import { collectFixtureReceipts } from "../../../../tools/watchdog/fixture-receipts.mjs";

const KEY = "watchdog-observation-v1", INTERVAL = COLLECTION_INTERVAL_MS, LEASE = 4 * 60_000;
function activationTime(env, now = Date.now()) {
  if (env.FOTTY_WATCHDOG_ENABLED !== "1" || !Number.isSafeInteger(now) || now < 0) return null;
  const value = env.FOTTY_WATCHDOG_ACTIVATED_AT;
  // The flag alone is not activation authority. Require a real, non-future
  // RFC3339 instant, not Date.parse's permissive prose/date-only spellings or
  // a normalized impossible calendar date (for example, February30).
  if (typeof value !== "string" || value.length > 40) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) return null;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
  const calendar = new Date(0);
  calendar.setUTCFullYear(year, month - 1, day);
  if (calendar.getUTCFullYear() !== year || calendar.getUTCMonth() !== month - 1 || calendar.getUTCDate() !== day
    || hour > 23 || minute > 59 || second > 59) return null;
  const offset = match[8];
  if (offset !== "Z" && (Number(offset.slice(1, 3)) > 23 || Number(offset.slice(4, 6)) > 59)) return null;
  const parsed = Date.parse(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 && parsed <= now ? parsed : null;
}
// Leave room for the scheduler/budget envelope and a durable overflow notice.
const policy = createPolicy({ ...observerPolicyOptions(), failureWindows: CONFIRMATION_WINDOWS,
  limits: { ledgerBytes: 1024 * 1024 - 4096 } });
const response = (body, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
async function publicNotification(event) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(event.key));
  const incidentId = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const { id, type, source, stage, failureClass, scope, generation, time } = event;
  return { id, type, incidentId, source, stage, failureClass, scope, generation, time };
}
const scalarTime = (value) => Number.isSafeInteger(value) && value >= 0;
function validateRuntime(runtime) {
  const fields = new Set(["fence", "lease", "nextAt", "budget", "lastAttemptedAt", "lastCompletedAt"]);
  if (!runtime || Object.keys(runtime).some((key) => !fields.has(key)) || !scalarTime(runtime.fence)
    || !scalarTime(runtime.nextAt)) throw new Error("Invalid observer runtime");
  for (const name of ["lastAttemptedAt", "lastCompletedAt"]) if (runtime[name] != null && !scalarTime(runtime[name])) throw new Error("Invalid observer time");
  if (runtime.lease && (!scalarTime(runtime.lease.fence) || runtime.lease.fence < 1 || runtime.lease.fence > runtime.fence
    || !scalarTime(runtime.lease.expiresAt) || Object.keys(runtime.lease).some((key) => !["fence", "expiresAt"].includes(key)))) throw new Error("Invalid observer lease");
  const budget = runtime.budget;
  if (!budget || Object.keys(budget).some((key) => !["day", "counts"].includes(key))) throw new Error("Invalid observer budget");
  if (budget.day != null) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(budget.day) || !budget.counts || Object.keys(budget.counts).length > PROVIDERS.length) throw new Error("Invalid budget day");
    for (const [source, count] of Object.entries(budget.counts)) {
      const bound = PROVIDERS.find((row) => row.source === source)?.maxRequestsPerDay;
      if (!bound || !scalarTime(count) || count > bound) throw new Error("Invalid source budget");
    }
  } else if (Object.keys(budget).length) throw new Error("Missing budget day");
}
export class WatchdogState {
  constructor(state, env) { this.state = state; this.env = env; }
  async transact(change) {
    return this.state.storage.transaction(async (transaction) => {
      const stored = await transaction.get(KEY) || { ledger: emptyLedger(policy), runtime: { fence: 0, lease: null, nextAt: 0, budget: {} } };
      validateLedger(stored.ledger, policy);
      validateRuntime(stored.runtime);
      const result = change(stored);
      validateLedger(stored.ledger, policy);
      validateRuntime(stored.runtime);
      if (new TextEncoder().encode(JSON.stringify(stored)).length > 1024 * 1024) throw new Error("Watchdog storage bound");
      await transaction.put(KEY, stored); return result;
    });
  }
  async run(now = Date.now()) {
    if (activationTime(this.env, now) === null) return response({ activation: "pending" });
    const fence = await this.transact((stored) => {
      const runtime = stored.runtime;
      // An existing collector can retain the previous release's longer cadence.
      // Bring only its due time forward; keep completion evidence, budgets,
      // incidents/outbox and an active collector lease exactly as recorded.
      if (runtime.lastCompletedAt != null) runtime.nextAt = Math.min(runtime.nextAt, runtime.lastCompletedAt + INTERVAL);
      if (runtime.nextAt > now || runtime.lease?.expiresAt > now) return null;
      if (runtime.fence >= Number.MAX_SAFE_INTEGER) throw new Error("Observer fence exhausted");
      runtime.fence++; runtime.lease = { fence: runtime.fence, expiresAt: now + LEASE };
      runtime.lastAttemptedAt = now; return runtime.fence;
    });
    if (fence === null) return response({ due: false });
    const reserve = (source) => this.transact((stored) => {
      if (stored.runtime.lease?.fence !== fence || stored.runtime.lease.expiresAt <= Date.now()) return false;
      const day = new Date(Date.now()).toISOString().slice(0, 10), bound = PROVIDERS.find((row) => row.source === source)?.maxRequestsPerDay;
      if (!bound) return false;
      if (stored.runtime.budget.day !== day) stored.runtime.budget = { day, counts: {} };
      const used = stored.runtime.budget.counts[source] || 0;
      if (used >= bound) return false;
      stored.runtime.budget.counts[source] = used + 1; return true;
    });
    try {
      let sportsSnapshot;
      const fixtureReceipts = await collectFixtureReceipts({ now, onSportsSnapshot: (body) => { sportsSnapshot = body; } });
      const receipts = [...await probeSources({ now, reserve, sportsSnapshot }), ...fixtureReceipts];
      const committed = await this.transact((stored) => {
        if (stored.runtime.lease?.fence !== fence || stored.runtime.lease.expiresAt <= Date.now()) return { committed: false, events: [] };
        const result = applyObservationBatch(stored.ledger, receipts, policy, Date.now());
        result.state.revision = stored.ledger.revision + 1; stored.ledger = result.state;
        stored.runtime.lastCompletedAt = Date.now(); stored.runtime.nextAt = now + INTERVAL; stored.runtime.lease = null;
        return { committed: true, events: result.events };
      });
      // A failed storage commit must never announce a transition. Delivery is
      // separately retried from durable history by the independent observer.
      for (const event of committed.events) console.log(JSON.stringify({ category: "watchdog", type: event.type, generation: event.generation || null }));
      return response({ committed: committed.committed, changes: committed.events.length }, committed.committed ? 200 : 409);
    } catch {
      // No success heartbeat and no accepted-fixture mutation on store/probe
      // failure. The independent observer will detect the missed completion.
      return response({ committed: false, failure: "observer-check-failed" }, 503);
    }
  }
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/run") return this.run();
    if (request.method !== "GET" || url.pathname !== "/status") return response({ error: "not-found" }, 404);
    const stored = await this.state.storage.get(KEY);
    if (stored) { validateLedger(stored.ledger, policy); validateRuntime(stored.runtime); }
    const activatedAt = activationTime(this.env);
    return response({ schema: 1, observerRevision: OBSERVER_REVISION, configurationRevision: CONFIGURATION_REVISION,
      expectedDeploymentRevision: EXPECTED_VERSIONS.deploymentRevision, activation: activatedAt === null ? "pending" : "active",
      activatedAt: activatedAt === null ? null : new Date(activatedAt).toISOString(),
      intervalMs: INTERVAL, nativeEvidence: "private-device-canary-only", streamDelivery: "not-probed",
      lastAttemptedAt: stored?.runtime.lastAttemptedAt || null, lastCompletedAt: stored?.runtime.lastCompletedAt || null,
      nextAt: stored?.runtime.nextAt || null, overflow: Boolean(stored?.ledger.overflow),
      notifications: stored ? await Promise.all(listNotifications(stored.ledger, policy).map(publicNotification)) : [],
      incidents: Object.values(stored?.ledger.incidents || {}).map(({ source, stage, failureClass, state, facts, generation }) =>
        ({ source, stage, failureClass, state, generation, scope: facts.scope || null })) });
  }
}
const stub = (env) => env.WATCHDOG_STATE.get(env.WATCHDOG_STATE.idFromName("production-observation-v1"));
export default {
  scheduled(_controller, env, ctx) {
    if (activationTime(env) !== null) ctx.waitUntil(stub(env).fetch("https://watchdog.internal/run", { method: "POST" }).then((result) => {
      if (!result.ok) throw new Error("Watchdog did not commit a completion receipt");
    }));
  },
  async fetch(request, env) {
    const url = new URL(request.url);
    // Public surface is read-only and redacted. Cron alone can start a run.
    if (request.method !== "GET" || url.pathname !== "/status") return response({ error: "not-found" }, 404);
    return stub(env).fetch("https://watchdog.internal/status");
  },
};
