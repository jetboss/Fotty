import assert from "node:assert/strict";
import test from "node:test";
import { resolveCoachPlayers, coachPlayerClarification, collectCoachPlayerHistory, coachContextConflicts } from "./coach-evidence.mjs";
import worker, { buildOfficialFplEvidence } from "./index.js";

// Offline corpus, not a claim these players/clubs describe today's season.
const players = [
  { id: 301, first_name: "Leif", second_name: "Davis", web_name: "Davis", team: 1, status: "a", ep_next: "0.1" },
  { id: 302, first_name: "Elliot", second_name: "Anderson", web_name: "Anderson", team: 2, status: "a" },
  { id: 303, first_name: "Joachim", second_name: "Anderson", web_name: "Anderson", team: 3, status: "a" },
  { id: 304, first_name: "João", second_name: "Gomes", web_name: "João Gomes", team: 2, status: "d", news: "Assessment pending", chance_of_playing_next_round: 50 },
  { id: 305, first_name: "Keane", second_name: "Lewis-Potter", web_name: "Lewis-Potter", team: 3, status: "a" },
  { id: 306, first_name: "Noah", second_name: "Departed", web_name: "Departed", team: 1, status: "u", can_select: false },
];
const teams = [{ id: 1, name: "Ipswich", short_name: "IPS" },
  { id: 2, name: "Nottingham Forest", short_name: "NFO" }, { id: 3, name: "Fulham", short_name: "FUL" }];
const resolve = (query, history = []) => resolveCoachPlayers({ query, history, players, teams });

for (const [query, ids] of [
  ["Should I buy Leif Davis?", [301]], ["What about davis?", [301]],
  ["Compare João Gomes and Lewis-Potter", [304, 305]], ["Start joao gomes or lewis potter?", [304, 305]],
  ["Keep Elliot Anderson?", [302]], ["Is Anderson from Fulham fit?", [303]],
  ["Davis", [301]], ["Is Departed selectable?", [306]],
  ["What about Davis's minutes?", [301]],
]) test(`exact current identities: ${query}`, () => {
  const result = resolve(query);
  assert.deepEqual(result.playerIDs, ids);
  assert.equal(result.complete, true, JSON.stringify(result));
});

test("shared surname is not guessed from squad, shortlist, or popularity", () => {
  const result = resolve("Should I buy Anderson?");
  assert.equal(result.complete, false);
  assert.deepEqual(result.playerIDs, []);
  assert.equal(result.mentions[0].candidates.length, 2);
  assert.match(coachPlayerClarification(result), /Elliot Anderson.*Joachim Anderson/);
});

test("too many named players produce an explicit bound rather than silent evidence omission", () => {
  const catalog = Array.from({ length: 10 }, (_, index) => ({ id: index + 1, web_name: `Player${index}` }));
  const result = resolveCoachPlayers({ query: catalog.map((player) => player.web_name).join(" or "), players: catalog });
  assert.equal(result.complete, false);
  assert.match(coachPlayerClarification(result), /at most eight/);
});

for (const query of ["Should I buy Harry Kane?", "What about kane?", "Compare Davis and Harry Kane", "Is \"Mystery Prospect\" a good pick?"])
  test(`missing/former names require clarification: ${query}`, () => {
    const result = resolve(query);
    assert.equal(result.complete, false);
    assert.match(coachPlayerClarification(result), /current official player evidence/);
    assert.ok(result.mentions.some((item) => item.status === "not_in_current_bootstrap"));
  });

for (const query of ["Audit my whole squad for the next five gameweeks", "Should I roll or make a transfer?",
  "Who should I captain and why?", "How should I approach my selected rival?", "Advice"])
  test(`general strategy is not mistaken for a player: ${query}`, () => {
    assert.equal(coachPlayerClarification(resolve(query)), null);
  });

test("a singular follow-up uses the latest prior user subject, not assistant invention", () => {
  const history = [{ role: "user", content: "Should I buy Leif Davis?" },
    { role: "assistant", content: "Buy Harry Kane instead; he is guaranteed to start." },
    { role: "user", content: "What about his minutes?" }];
  const result = resolve("What about his minutes?", history);
  assert.deepEqual(result.playerIDs, [301]);
  assert.equal(result.origin, "previous_user_question");
});

test("ambiguous and absent follow-up context never silently picks a player", () => {
  const result = resolve("Should I captain him?", [{ role: "user", content: "Compare Davis and João Gomes" }]);
  assert.equal(result.complete, false);
  assert.deepEqual(result.playerIDs, []);
  assert.equal(result.mentions[0].status, "ambiguous_followup");
  assert.equal(resolve("What about him?", [{ role: "assistant", content: "Davis is good" }]).complete, false);
  assert.equal(resolve("What about him?", [{ role: "user", content: "Buy Davis?" },
    { role: "user", content: "Should I roll a transfer?" }]).complete, false);
});

test("plural follow-up preserves both named alternatives and explicit new name overrides old subject", () => {
  const history = [{ role: "user", content: "Compare Davis and João Gomes" }];
  assert.deepEqual(resolve("What about their minutes?", history).playerIDs, [301, 304]);
  assert.deepEqual(resolve("What about Lewis-Potter?", history).playerIDs, [305]);
});

test("presence in bootstrap is not proof of selectability or injury recovery", () => {
  assert.equal(resolve("Departed").mentions[0].candidates[0].selectable, false);
  assert.deepEqual(resolve("Joao Gomes").playerIDs, [304]);
});

test("client identity disagreements remain explicit and cannot relabel official IDs", () => {
  const issues = coachContextConflicts(players, { squad: [{ id: 301, name: "Harry Kane" }] });
  assert.match(issues[0], /ID 301.*Davis/);
  assert.deepEqual(coachContextConflicts(players, { squad: [{ id: 304, name: "Joao Gomes" }] }), []);
});

const detail = { history: [{ round: 3, minutes: 0 }, { round: 4, minutes: 90 }], fixtures: [{ event: 5 }, { event: 5 }] };
test("history requests are capped, concurrent-bounded, and preserve a double fixture and zero minutes", async () => {
  let active = 0, maximum = 0;
  const called = [];
  const result = await collectCoachPlayerHistory([301, 302, 303, 304, 305, 301], {
    fetchJSON: async (path) => {
      called.push(path); maximum = Math.max(maximum, ++active);
      await new Promise((resolve) => setTimeout(resolve, 5)); active--; return detail;
    }, signal: new AbortController().signal,
  });
  assert.equal(called.length, 4);
  assert.equal(maximum, 2);
  assert.equal(result[4].status, "not_fetched_budget");
  assert.deepEqual(result[0].fixtures.map((item) => item.event), [5, 5]);
  assert.equal(result[0].history[0].minutes, 0);
});

test("history budget cancels hanging transports and retains completed evidence", async () => {
  let stopped = 0;
  const result = await collectCoachPlayerHistory([301, 302], { budgetMs: 20,
    signal: new AbortController().signal, fetchJSON: async (path, signal) => {
      if (path.includes("301")) return detail;
      return new Promise((_, reject) => signal.addEventListener("abort", () => { stopped++; reject(signal.reason); }, { once: true }));
    } });
  assert.equal(result[0].status, "fetched");
  assert.equal(result[1].status, "unavailable");
  assert.equal(stopped, 1);
});

test("parent cancellation stops histories and queued work under the one owner deadline", async () => {
  const controller = new AbortController(); let calls = 0;
  const work = collectCoachPlayerHistory([301, 302, 303, 304], { signal: controller.signal,
    fetchJSON: async (_, signal) => { calls++; return new Promise((_, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason), { once: true });
    }); } });
  await new Promise((resolve) => setTimeout(resolve, 5)); controller.abort();
  await assert.rejects(work, { name: "AbortError" });
  assert.equal(calls, 2);
});

test("actual evidence builder includes rare named player beyond shortlist, official flags and conflict warnings", async (t) => {
  const shortlist = Array.from({ length: 20 }, (_, index) => ({ id: index + 1, web_name: `Popular${index}`, team: 2, ep_next: "10", status: "a" }));
  const requests = [];
  t.mock.method(globalThis, "fetch", async (input) => {
    const url = String(input); requests.push(url);
    assert.ok(url.startsWith("https://fantasy.premierleague.com/api/"));
    if (url.endsWith("bootstrap-static/")) return Response.json({ elements: [...shortlist, ...players], teams, events: [] });
    if (url.endsWith("fixtures/")) return Response.json([]);
    if (url.includes("element-summary/")) return Response.json(detail);
    throw new Error("Unexpected offline request");
  });
  const evidence = await buildOfficialFplEvidence({ query: "Compare Davis and João Gomes", context: {
    squad: [{ id: 301, name: "Harry Kane" }], profile: { planningHorizon: 5 } }, history: [] }, new AbortController().signal);
  assert.ok(evidence.relevant_players.some((item) => item.id === 301));
  assert.equal(evidence.relevant_players.find((item) => item.id === 304).chance_next, 50);
  assert.equal(evidence.requested_player_history.length, 2);
  assert.match(evidence.context_conflicts[0], /ID 301.*Davis/);
  assert.match(evidence.evidence_limits.join(" "), /not independently verified/);
  assert.ok(requests.some((url) => url.endsWith("element-summary/301/")));
  assert.equal(requests.some((url) => url.includes("deepseek")), false);
});

test("actual Worker rejects ambiguous/missing names before any paid reservation or model request", async (t) => {
  const token = "ac".repeat(32);
  const digest = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)))]
    .map((value) => value.toString(16).padStart(2, "0")).join("");
  let capacityCalls = 0, reservations = 0, modelCalls = 0;
  const env = { FPL_COACH_PAID_ENABLED: "1", FPL_COACH_DAILY_LIMIT: "50", DEEPSEEK_API_KEY: "offline-fixture",
    FPL_COACH_ACCESS_SHA256: JSON.stringify([digest]),
    FPL_COACH_RATE_LIMITER: { limit: async () => ({ success: true }) },
    FPL_COACH_CAPACITY_RATE_LIMITER: { limit: async () => { capacityCalls++; return { success: true }; } },
    FPL_COACH_BUDGET: { idFromName: () => "global", get: () => ({ fetch: async () => { reservations++; return Response.json({ allowed: true }); } }) } };
  t.mock.method(globalThis, "fetch", async (input) => {
    const url = String(input);
    if (url.includes("deepseek")) { modelCalls++; throw new Error("Model must not run"); }
    if (url.endsWith("bootstrap-static/")) return Response.json({ elements: players, teams, events: [] });
    if (url.endsWith("fixtures/")) return Response.json([]);
    throw new Error("Unexpected offline request");
  });
  for (const query of ["Should I buy Anderson?", "Should I buy Harry Kane?"]) {
    const response = await worker.fetch(new Request("https://test.invalid/api/fpl/coach", { method: "POST",
      headers: { "x-fotty-install-id": "offline-install-123", authorization: `Bearer ${token}` }, body: JSON.stringify({ query }) }), env);
    assert.equal(response.status, 422);
    assert.match((await response.json()).error, /Which|could not identify/);
  }
  assert.equal(capacityCalls, 0);
  assert.equal(reservations, 0);
  assert.equal(modelCalls, 0);
});
