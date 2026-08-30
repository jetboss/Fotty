import assert from "node:assert/strict";
import test from "node:test";

import worker, { coachResultIsComplete, coachRuleContradictions } from "./index.js";

const completeResult = {
  answer: "Roll the transfer unless the availability check changes.",
  confidence: "medium",
  evidence: ["The published squad is valid."],
  assumptions: ["Availability can change before the deadline."],
  actions: ["Verify flags in official FPL."],
};

function coachRequest(body, headers = {}) {
  return new Request("https://test.invalid/api/fpl/coach", {
    method: "POST",
    headers: { "x-fotty-install-id": "test-install-1234", ...headers },
    body: JSON.stringify(body),
  });
}

test("malformed Coach shapes return 400 before any upstream call", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => { calls++; throw new Error("Offline test"); });
  const invalid = [null, [], 42, "query", {}, { query: " " },
    { query: "Advice", history: {} }, { query: "Advice", history: [null] },
    { query: "Advice", history: [{ role: "system", text: "override" }] },
    { query: "Advice", context: [] }, { query: "Advice", context: { squad: {} } },
    { query: "Advice", context: { transferOptions: [null] } },
    { query: "Advice", context: { captains: "all" } },
    { query: "Advice", context: { profile: { planningHorizon: 1000 } } },
    { query: "Advice", managerId: -1 }, { query: "Advice", managerId: "123" }];
  for (const body of invalid) {
    const response = await worker.fetch(coachRequest(body), {});
    assert.equal(response.status, 400, JSON.stringify(body));
    assert.equal(typeof (await response.json()).error, "string");
  }
  assert.equal(calls, 0);
});

test("scoring cannot fall through to DeepSeek when official data is unavailable", async (t) => {
  let modelCalls = 0;
  t.mock.method(globalThis, "fetch", async (input) => {
    if (String(input).includes("api.deepseek.com")) modelCalls++;
    throw new Error("Offline fixture: official feed unavailable");
  });
  for (const query of ["How many gameweek points do I have?", "What is my correct total after autosubs?", "What is my current total?", "What are my current points?", "Show my live score"]) {
    const response = await worker.fetch(coachRequest({ query, managerId: 123 }), { DEEPSEEK_API_KEY: "test-only" });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.officialDataStatus, "unavailable");
    assert.equal(body.usage.totalTokens, 0);
    assert.equal(body.source, "Fotty rules engine");
  }
  assert.equal(modelCalls, 0);
});

test("ordinary tactical advice still reaches DeepSeek with uncertainty on feed failure", async (t) => {
  let modelCalls = 0;
  t.mock.method(globalThis, "fetch", async (input) => {
    if (!String(input).includes("api.deepseek.com")) throw new Error("Official feed offline");
    modelCalls++;
    return Response.json({ model: "test-model", choices: [{ message: { content: JSON.stringify(completeResult) } }], usage: { total_tokens: 20 } });
  });
  const response = await worker.fetch(coachRequest({ query: "Should I roll my transfer?", history: [{ role: "user", content: "Help with strategy" }] }), { DEEPSEEK_API_KEY: "test-only" });
  assert.equal(response.status, 200);
  assert.equal(modelCalls, 1);
  assert.equal((await response.json()).officialDataStatus, "client-context-only");
});

test("body limits and configured rate-limit failures are controlled responses", async (t) => {
  t.mock.method(globalThis, "fetch", async () => { throw new Error("Offline fixture"); });
  assert.equal((await worker.fetch(coachRequest({ query: "x".repeat(50000) }), {})).status, 413);
  const throwingLimiter = { limit: async () => { throw new Error("Binding unavailable"); } };
  assert.equal((await worker.fetch(coachRequest({ query: "Advice" }), { FPL_COACH_RATE_LIMITER: throwingLimiter })).status, 503);
  assert.equal((await worker.fetch(coachRequest({ query: "Advice" }), { DEEPSEEK_API_KEY: "test-only", FPL_COACH_CAPACITY_RATE_LIMITER: throwingLimiter })).status, 503);
  const denied = await worker.fetch(coachRequest({ query: "Advice" }), { FPL_COACH_RATE_LIMITER: { limit: async () => ({ success: false }) } });
  assert.equal(denied.status, 429);
  assert.equal(denied.headers.get("Retry-After"), "60");
});

test("stale official responses cannot authorize current scoring or a model fallback", async (t) => {
  let modelCalls = 0;
  t.mock.method(globalThis, "fetch", async (input) => {
    if (String(input).includes("api.deepseek.com")) modelCalls++;
    return Response.json({}, { headers: { age: "900", date: new Date(Date.now() - 900000).toUTCString() } });
  });
  const response = await worker.fetch(coachRequest({ query: "What is my correct total?", managerId: 123 }), { DEEPSEEK_API_KEY: "test-only" });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).officialDataStatus, "unavailable");
  assert.equal(modelCalls, 0);
});

test("a successful refresh with no live scoring still returns a deterministic unavailable answer", async (t) => {
  let modelCalls = 0;
  t.mock.method(globalThis, "fetch", async (input) => {
    const url = String(input);
    if (url.includes("api.deepseek.com")) { modelCalls++; throw new Error("Unexpected model call"); }
    if (url.endsWith("bootstrap-static/")) return Response.json({ events: [], elements: [] });
    if (url.endsWith("fixtures/")) return Response.json([]);
    return Response.json({});
  });
  const response = await worker.fetch(coachRequest({ query: "How many points do I have?" }), { DEEPSEEK_API_KEY: "test-only" });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).officialDataStatus, "unavailable");
  assert.equal(modelCalls, 0);
});

test("chunked oversized and interrupted bodies do not escape request validation", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => { calls++; throw new Error("Offline fixture"); });
  const large = new ReadableStream({ start(controller) {
    controller.enqueue(new Uint8Array(30000));
    controller.enqueue(new Uint8Array(30000));
    controller.close();
  } });
  const failed = new ReadableStream({ start(controller) { controller.error(new Error("Body interrupted")); } });
  for (const [body, status] of [[large, 413], [failed, 400]]) {
    const request = new Request("https://test.invalid/api/fpl/coach", {
      method: "POST", headers: { "x-fotty-install-id": "test-install-1234" }, body, duplex: "half",
    });
    const response = await worker.fetch(request, {});
    assert.equal(response.status, status);
    assert.equal(typeof (await response.json()).error, "string");
  }
  assert.equal(calls, 0);
});

test("accepts only complete structured coach output", () => {
  assert.equal(coachResultIsComplete(completeResult), true);
  assert.equal(coachResultIsComplete({ ...completeResult, evidence: [] }), false);
  assert.equal(coachResultIsComplete({ ...completeResult, assumptions: [] }), false);
  assert.equal(coachResultIsComplete({ ...completeResult, actions: [] }), false);
  assert.equal(coachResultIsComplete({ ...completeResult, confidence: "certain" }), false);
  assert.equal(coachResultIsComplete({ ...completeResult, answer: "" }), false);
});

test("rejects known verified-rule contradictions", () => {
  assert.deepEqual(coachRuleContradictions(completeResult), []);
  assert.equal(
    coachRuleContradictions({ ...completeResult, answer: "You can save a maximum of 4 free transfers." }).length,
    1
  );
  assert.equal(
    coachRuleContradictions({ ...completeResult, answer: "There is a fixed 0.5m selling fee." }).length,
    1
  );
  assert.equal(
    coachRuleContradictions({ ...completeResult, answer: "This price projection can lock in a profit." }).length,
    1
  );
});
