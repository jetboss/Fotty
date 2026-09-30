import assert from "node:assert/strict";
import test from "node:test";
import worker from "./index.js";
import { abortable, authorizePaidCoach, boundedJSON, coachDeadline, CoachQuotaBudget, paidCoachLimit } from "./coach-safety.mjs";

const token = "cd".repeat(32);
const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))))
  .map((value) => value.toString(16).padStart(2, "0")).join("");
const baseEnv = {
  FPL_COACH_PAID_ENABLED: "1", FPL_COACH_DAILY_LIMIT: "50",
  FPL_COACH_ACCESS_SHA256: JSON.stringify([digest]), DEEPSEEK_API_KEY: "offline-test-only",
  FPL_COACH_RATE_LIMITER: { limit: async () => ({ success: true }) },
  FPL_COACH_CAPACITY_RATE_LIMITER: { limit: async () => ({ success: true }) },
  FPL_COACH_BUDGET: { idFromName: () => "global", get: () => ({ fetch: async () => Response.json({ allowed: true, remaining: 49 }) }) },
};
function request({ code = token, query = "Should I roll my transfer?", signal } = {}) {
  return new Request("https://test.invalid/api/fpl/coach", {
    method: "POST", signal,
    headers: { "x-fotty-install-id": "offline-install", ...(code ? { authorization: `Bearer ${code}` } : {}) },
    body: JSON.stringify({ query, managerId: 123 }),
  });
}
function storage(initial) {
  const values = new Map(initial ? [["daily-v1", initial]] : []);
  return { get: async (key) => values.get(key), put: async (key, value) => { values.set(key, value); } };
}
const reservation = () => new Request("https://budget.invalid/reserve", { method: "POST" });

test("paid access is explicit, revocable and never trusts installation ID alone", async () => {
  assert.equal(await authorizePaidCoach(request(), baseEnv), null);
  for (const code of [null, "ef".repeat(32), "short"]) assert.equal((await authorizePaidCoach(request({ code }), baseEnv)).status, 401);
  assert.equal((await authorizePaidCoach(request(), { ...baseEnv, FPL_COACH_ACCESS_SHA256: JSON.stringify(["0".repeat(64)]) })).status, 401);
  for (const override of [{ FPL_COACH_PAID_ENABLED: "0" }, { FPL_COACH_ACCESS_SHA256: "invalid" },
    { FPL_COACH_ACCESS_SHA256: "[]" }, { FPL_COACH_DAILY_LIMIT: "0" }, { FPL_COACH_BUDGET: null }]) {
    assert.equal((await authorizePaidCoach(request(), { ...baseEnv, ...override })).status, 503);
  }
});

test("unapproved requests cannot start official evidence or model work", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => { calls++; throw new Error("No upstream allowed"); });
  assert.equal((await worker.fetch(request({ code: null }), baseEnv)).status, 401);
  assert.equal((await worker.fetch(request(), { ...baseEnv, FPL_COACH_RATE_LIMITER: null })).status, 503);
  assert.equal(calls, 0);
});

test("deterministic scoring does not require paid access or spend a reservation", async (t) => {
  let modelCalls = 0;
  t.mock.method(globalThis, "fetch", async (url) => { if (String(url).includes("deepseek")) modelCalls++; throw new Error("Offline"); });
  const result = await worker.fetch(request({ code: null, query: "What is my current total?" }), {
    FPL_COACH_RATE_LIMITER: baseEnv.FPL_COACH_RATE_LIMITER,
    FPL_COACH_CAPACITY_RATE_LIMITER: baseEnv.FPL_COACH_CAPACITY_RATE_LIMITER,
  });
  assert.equal(result.status, 200);
  const body = await result.json();
  assert.equal(body.source, "Fotty rules engine");
  assert.equal(body.usage.totalTokens, 0);
  assert.equal(modelCalls, 0);
});

test("deterministic scoring cannot evade client and capacity limits by rotating installation IDs", async (t) => {
  t.mock.method(globalThis, "fetch", async () => { throw new Error("Offline"); });
  const keys = [];
  const limiter = { limit: async ({ key }) => { keys.push(key); return { success: true }; } };
  const capacity = { limit: async ({ key }) => { keys.push(key); return { success: true }; } };
  for (const install of ["rotating-install-one", "rotating-install-two"]) {
    const scoringRequest = new Request("https://test.invalid/api/fpl/coach", {
      method: "POST",
      headers: { "x-fotty-install-id": install, "cf-connecting-ip": "203.0.113.10" },
      body: JSON.stringify({ query: "What is my current total?", managerId: 123 }),
    });
    assert.equal((await worker.fetch(scoringRequest, {
      FPL_COACH_RATE_LIMITER: limiter,
      FPL_COACH_CAPACITY_RATE_LIMITER: capacity,
    })).status, 200);
  }
  assert.equal(keys.filter((key) => key === "fpl-scoring:203.0.113.10").length, 2);
  assert.equal(keys.filter((key) => key === "fpl-scoring-capacity").length, 2);
});

test("50 concurrent admissions share one persisted group allowance", async () => {
  const state = { storage: storage() };
  const budget = new CoachQuotaBudget(state, baseEnv);
  const responses = await Promise.all(Array.from({ length: 65 }, () => budget.fetch(reservation())));
  assert.equal(responses.filter((value) => value.status === 200).length, 50);
  assert.equal(responses.filter((value) => value.status === 429).length, 15);
  assert.equal((await new CoachQuotaBudget(state, baseEnv).fetch(reservation())).status, 429);
});

test("allowance resets at the UTC day boundary, not per worker instance", async (t) => {
  t.mock.timers.enable({ apis: ["Date"], now: Date.parse("2026-09-04T23:59:59Z") });
  const state = { storage: storage({ day: "2026-09-04", used: 50 }) };
  const budget = new CoachQuotaBudget(state, baseEnv);
  assert.equal((await budget.fetch(reservation())).status, 429);
  t.mock.timers.tick(1001);
  const result = await budget.fetch(reservation());
  assert.equal(result.status, 200);
  assert.equal((await result.json()).remaining, 49);
});

test("invalid, disabled or unreadable quota state fails closed", async () => {
  for (const value of ["", "0", "-1", "1.5", "50oops", "10000"]) assert.equal(paidCoachLimit({ FPL_COACH_DAILY_LIMIT: value }), null);
  for (const prior of [{ day: "bad", used: 1 }, { day: "2026-09-04", used: -1 }, { day: "2999-01-01", used: 0 }]) {
    assert.equal((await new CoachQuotaBudget({ storage: storage(prior) }, baseEnv).fetch(reservation())).status, 503);
  }
  const failed = new CoachQuotaBudget({ storage: { get: async () => { throw new Error("Unavailable"); } } }, baseEnv);
  assert.equal((await failed.fetch(reservation())).status, 503);
  assert.equal((await new CoachQuotaBudget({ storage: storage() }, { ...baseEnv, FPL_COACH_PAID_ENABLED: "0" }).fetch(reservation())).status, 503);
});

test("failed reservation or exhausted quota never invokes the model", async (t) => {
  let modelCalls = 0;
  t.mock.method(globalThis, "fetch", async (url) => { if (String(url).includes("deepseek")) modelCalls++; throw new Error("Offline evidence"); });
  for (const status of [429, 503]) {
    const env = { ...baseEnv, FPL_COACH_BUDGET: {
      idFromName: () => "global", get: () => ({ fetch: async () => Response.json({ allowed: false }, { status }) }),
    } };
    assert.equal((await worker.fetch(request(), env)).status, status);
  }
  assert.equal(modelCalls, 0);
});

test("client abort ends in-flight evidence and never falls through to a model", async (t) => {
  const controller = new AbortController();
  const signals = [];
  let started;
  const start = new Promise((resolve) => { started = resolve; });
  t.mock.method(globalThis, "fetch", (_url, options) => {
    signals.push(options.signal); started(); return new Promise(() => {});
  });
  const response = worker.fetch(request({ signal: controller.signal }), baseEnv);
  await start;
  controller.abort();
  assert.equal((await response).status, 504);
  assert.ok(signals.length > 0 && signals.every((signal) => signal.aborted));
});

test("abandoned model request is aborted once and not automatically retried", async (t) => {
  const controller = new AbortController();
  let started;
  const start = new Promise((resolve) => { started = resolve; });
  let modelSignal;
  let modelCalls = 0;
  let reservations = 0;
  t.mock.method(globalThis, "fetch", (url, options) => {
    if (!String(url).includes("deepseek")) return Promise.reject(new Error("Offline evidence"));
    modelCalls++; modelSignal = options.signal; started(); return new Promise(() => {});
  });
  const response = worker.fetch(request({ signal: controller.signal }), {
    ...baseEnv, FPL_COACH_BUDGET: { idFromName: () => "global", get: () => ({ fetch: async () => {
      reservations++; return Response.json({ allowed: true, remaining: 49 });
    } }) },
  });
  await start;
  controller.abort();
  assert.equal((await response).status, 504);
  assert.equal(modelSignal.aborted, true);
  assert.equal(modelCalls, 1);
  assert.equal(reservations, 1);
});

test("deadline also covers a provider which never resolves", async () => {
  const deadline = coachDeadline(undefined, 10);
  try { await assert.rejects(abortable(() => new Promise(() => {}), deadline.signal), { name: "TimeoutError" }); }
  finally { deadline.dispose(); }
});

test("body bounds cancel oversized streams during reading", async () => {
  let cancelled = false;
  const response = new Response(new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array(20)); }, cancel() { cancelled = true; },
  }));
  await assert.rejects(boundedJSON(response, 10, new AbortController().signal), /large/);
  assert.equal(cancelled, true);
});

test("an aborted response body does not keep a request waiting", async () => {
  const controller = new AbortController();
  let cancelled = false;
  const response = new Response(new ReadableStream({ cancel() { cancelled = true; } }));
  const reading = boundedJSON(response, 10, controller.signal);
  controller.abort();
  await assert.rejects(reading);
  assert.equal(cancelled, true);
});
