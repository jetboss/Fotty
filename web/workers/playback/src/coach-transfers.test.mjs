import assert from "node:assert/strict";
import test from "node:test";
import { coachTransferContext, validateCoachTransfers } from "./coach-transfers.mjs";
import worker from "./index.js";

function fixture() {
  const positions = [1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4];
  const players = positions.map((element_type, index) => ({ id: index + 1, web_name: `Player${index + 1}`,
    element_type, team: index < 2 ? 6 : index % 5 + 1, now_cost: 50, status: "a" }));
  players.push(...[16, 17].map((id) => ({ id, web_name: `Player${id}`, element_type: 2, team: 6, now_cost: 60, status: "a" })));
  players.push({ id: 18, web_name: "Midfielder", element_type: 3, team: 7, now_cost: 50, status: "a" },
    { id: 19, web_name: "Departed", element_type: 2, team: 7, now_cost: 50, status: "u", can_select: false });
  return { players, picks: players.slice(0, 15).map(({ id }) => ({ id })), bank: 20,
    baselineSource: "published official lineup", budgetBasis: "published last-deadline bank",
    elementTypes: [], settings: { squad_team_limit: 3, squad_squadsize: 15 } };
}

test("two independently legal moves fail their combined club limit", () => {
  const context = fixture();
  assert.equal(validateCoachTransfers([{ out: 3, in: 16 }], context).status, "conditional");
  assert.equal(validateCoachTransfers([{ out: 4, in: 17 }], context).status, "conditional");
  const combined = validateCoachTransfers([{ out: 3, in: 16 }, { out: 4, in: 17 }], context);
  assert.equal(combined.status, "invalid");
  assert.match(combined.reasons[0], /combined route exceeds the 3-player/);
});

test("two independently affordable moves cannot overspend the complete budget", () => {
  const context = fixture();
  for (const player of context.players.filter((item) => [16, 17].includes(item.id))) { player.team = 7; player.now_cost = 65; }
  assert.equal(validateCoachTransfers([{ out: 3, in: 16 }], context).status, "conditional");
  assert.equal(validateCoachTransfers([{ out: 4, in: 17 }], context).status, "conditional");
  const result = validateCoachTransfers([{ out: 3, in: 16 }, { out: 4, in: 17 }], context);
  assert.equal(result.status, "invalid");
  assert.equal(result.structureChecked, true);
  assert.equal(result.estimatedBankAfter, -10);
});

test("a complete legal two-move route passes only as an explicit budget estimate", () => {
  const context = fixture();
  for (const player of context.players.filter((item) => [16, 17].includes(item.id))) player.team = 7;
  const result = validateCoachTransfers([{ out: 3, in: 16 }, { out: 4, in: 17 }], context);
  assert.equal(result.status, "conditional");
  assert.equal(result.structureChecked, true);
  assert.equal(result.budgetStatus, "passes_estimate");
  assert.equal(result.estimatedBankAfter, 0);
  assert.match(result.reasons.join(" "), /not verified private-account affordability/);
});

for (const [name, proposal, reason] of [
  ["duplicate incoming", [{ out: 3, in: 16 }, { out: 4, in: 16 }], /repeat/],
  ["duplicate outgoing", [{ out: 3, in: 16 }, { out: 3, in: 17 }], /repeat/],
  ["buy/sell cycle", [{ out: 3, in: 4 }, { out: 4, in: 3 }], /buy and sell/],
  ["outgoing not owned", [{ out: 99, in: 16 }], /not owned/],
  ["already owned incoming", [{ out: 3, in: 7 }], /already owned/],
  ["unknown incoming", [{ out: 3, in: 999 }], /missing from the current/],
  ["different position", [{ out: 3, in: 18 }], /same official position/],
  ["unselectable incoming", [{ out: 3, in: 19 }], /not currently selectable/],
  ["string instead of ID", [{ out: "3", in: 16 }], /malformed/],
]) test(`rejects ${name} rather than inferring a legal route`, () => {
  const result = validateCoachTransfers(proposal, fixture());
  assert.equal(result.status, "invalid");
  assert.match(result.reasons[0], reason);
});

test("unknown bank does not become zero, affordability, or full-route validation", () => {
  const context = fixture(); context.bank = null;
  const result = validateCoachTransfers([{ out: 3, in: 16 }], context);
  assert.equal(result.status, "unverified");
  assert.equal(result.structureChecked, true);
  assert.equal(result.budgetStatus, "unknown");
  assert.equal(result.estimatedBankAfter, undefined);
});

test("missing sale value is a labeled current-price estimate, never private purchase history", () => {
  const context = fixture();
  const estimated = validateCoachTransfers([{ out: 3, in: 16 }], context);
  assert.equal(estimated.status, "conditional");
  assert.equal(estimated.estimatedBankAfter, 10);
  assert.match(estimated.reasons.join(" "), /missing selling values are estimated from current catalog prices/);
  context.picks.find((item) => item.id === 3).sellingPrice = 40;
  const supplied = validateCoachTransfers([{ out: 3, in: 16 }], context);
  assert.equal(supplied.estimatedBankAfter, 0);
  assert.equal(supplied.status, "conditional");
  assert.match(supplied.reasons.join(" "), /require confirmation in the official account/);
});

test("whole resulting squad quotas are checked even when the proposed pair preserves position", () => {
  const context = fixture(); context.players[0].element_type = 3;
  const result = validateCoachTransfers([{ out: 3, in: 16 }], context);
  assert.equal(result.status, "invalid");
  assert.match(result.reasons[0], /complete resulting squad/);
});

test("a partial baseline or missing catalog never authorizes a route", () => {
  const context = fixture(); context.picks.pop();
  assert.equal(validateCoachTransfers([{ out: 3, in: 16 }], context).status, "unverified");
  assert.equal(validateCoachTransfers([{ out: 3, in: 16 }], null).status, "unverified");
});

test("absent structured IDs leave prose unverified and never parse it into moves", () => {
  for (const proposal of [undefined, null, []]) {
    const result = validateCoachTransfers(proposal, fixture());
    assert.equal(result.status, "not_provided");
    assert.equal(result.structureChecked, false);
    assert.match(result.reasons[0], /Prose suggestions have not passed/);
  }
});

test("draft context cannot reuse a published bank or silently change ownership baseline", () => {
  const data = fixture();
  const picks = { picks: data.picks.map((item) => ({ element: item.id })), entry_history: { bank: 20 } };
  const draft = data.picks.map((item) => ({ ...item })); draft[2].id = 16;
  const args = { bootstrap: { elements: data.players }, picks, manager: { last_deadline_bank: 99 }, context: { squad: draft } };
  assert.equal(coachTransferContext(args).baselineUncertain, true);
  args.context.isLocalDraft = true;
  const selected = coachTransferContext(args);
  assert.equal(selected.bank, undefined);
  assert.equal(selected.picks[2].id, 16);
  assert.equal(validateCoachTransfers([{ out: 4, in: 17 }], selected).status, "invalid", "Structure still rejects the combined club cap even without a draft bank");
});

test("actual Worker withholds an illegal model route with usage and no automatic paid retry", async (t) => {
  const context = fixture(), token = "ad".repeat(32);
  const digest = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)))]
    .map((value) => value.toString(16).padStart(2, "0")).join("");
  let reservations = 0, modelCalls = 0;
  const env = { FPL_COACH_PAID_ENABLED: "1", FPL_COACH_DAILY_LIMIT: "50", DEEPSEEK_API_KEY: "offline-fixture",
    FPL_COACH_ACCESS_SHA256: JSON.stringify([digest]), FPL_COACH_RATE_LIMITER: { limit: async () => ({ success: true }) },
    FPL_COACH_CAPACITY_RATE_LIMITER: { limit: async () => ({ success: true }) },
    FPL_COACH_BUDGET: { idFromName: () => "global", get: () => ({ fetch: async () => { reservations++; return Response.json({ allowed: true, remaining: 49 }); } }) } };
  t.mock.method(globalThis, "fetch", async (input, options) => {
    const url = String(input);
    if (url.includes("deepseek")) {
      modelCalls++;
      assert.match(JSON.parse(options.body).messages[0].content, /optional proposedTransfers/);
      return Response.json({ model: "offline-model", usage: { total_tokens: 99 }, choices: [{ message: { content: JSON.stringify({
        answer: "Make both transfers", confidence: "high", evidence: ["Player prices"], assumptions: ["Verify budget"],
        actions: ["Use Transfer Lab"], proposedTransfers: [{ out: 3, in: 16 }, { out: 4, in: 17 }],
      }) } }] });
    }
    if (url.endsWith("bootstrap-static/")) return Response.json({ elements: context.players,
      events: [{ id: 1, is_current: true, deadline_time: "2020-01-01T00:00:00Z" }] });
    if (url.endsWith("fixtures/")) return Response.json([]);
    if (url.endsWith("picks/")) return Response.json({ picks: context.picks.map(({ id }) => ({ element: id })), entry_history: { bank: 20 } });
    if (url.includes("/entry/")) return Response.json({ last_deadline_bank: 20 });
    if (url.endsWith("live/")) return Response.json({ elements: [] });
    throw new Error("Unexpected offline request");
  });
  const response = await worker.fetch(new Request("https://test.invalid/api/fpl/coach", { method: "POST",
    headers: { "x-fotty-install-id": "offline-install-123", authorization: `Bearer ${token}` },
    body: JSON.stringify({ query: "Should I make a transfer?", managerId: 123 }) }), env);
  const result = await response.json();
  assert.equal(response.status, 422);
  assert.equal(result.answer, undefined);
  assert.equal(result.transferValidation.status, "invalid");
  assert.equal(result.usage.totalTokens, 99);
  assert.match(result.error, /No moves were applied and no automatic paid retry/);
  assert.equal(reservations, 1);
  assert.equal(modelCalls, 1);
});
