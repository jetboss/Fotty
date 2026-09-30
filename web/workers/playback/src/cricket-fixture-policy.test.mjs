import assert from "node:assert/strict";
import test from "node:test";
import worker from "./index.js";
import { admitICC, cricketWindow, iccScheduleURL, iccSourceTime, nextCricketRefresh, normalizeICC, parseICCPage } from "./cricket-fixture-policy.mjs";
import { collectICC, CricketFixtureRegistry, refreshCricketState } from "./cricket-fixture-registry.mjs";

const now = new Date("2026-09-30T16:00:00Z");
const row = (overrides = {}) => ({ match_id: "270271", league_id: "1", match_date_gmt: "9/30/2026", match_time_gmt: "08:30",
  teama_id: "4", teama: "India", teamb_id: "9", teamb: "West Indies", series_name: "West Indies in India, 3 ODI Series, 2026",
  match_type: "ODI", live: true, upcoming: false, recent: false, is_deleted: false, ...overrides });
const payload = (rows = [row()], overrides = {}) => ({ data: { matches: rows }, meta: { app_status_code: 1,
  pagination: true, count: rows.length, timestamp: { utc_time: "9/30/2026 4:00:00 PM" }, ...overrides } });
const normalized = (rows = [row()]) => normalizeICC([parseICCPage(payload(rows), now)], now);

test("ICC official current ODI survives discovery despite starting more than six hours ago", () => {
  const result = normalized();
  assert.equal(result.fixtures[0].status, "live");
  assert.equal(result.fixtures[0].competitionId, "west-indies");
  assert.equal(result.fixtures[0].start, "2026-09-30T08:30:00.000Z");
  assert.equal(result.fixtures[0].source.observedAt, now.toISOString());
});

test("UTC parsing checks AM/PM, invalid calendar dates, and source receipt freshness", () => {
  assert.equal(iccSourceTime("9/30/2026 12:01:00 AM").toISOString(), "2026-09-30T00:01:00.000Z");
  assert.equal(iccSourceTime("9/30/2026 12:01:00 PM").toISOString(), "2026-09-30T12:01:00.000Z");
  assert.throws(() => iccSourceTime("2/30/2026 4:00:00 PM"));
  assert.throws(() => parseICCPage(payload([row()], { timestamp: { utc_time: "9/30/2026 3:00:00 PM" } }), now), /Stale/);
  assert.throws(() => parseICCPage(payload([row()], { timestamp: { utc_time: "9/30/2026 5:00:00 PM" } }), now), /Stale/);
});

test("women and youth cannot borrow men's identities or stream matches", () => {
  const women = normalized([row({ league_id: "10", teamb_id: "1135" })]).fixtures[0];
  const youth = normalized([row({ league_id: "35", teama: "India Under-19", teamb: "West Indies Under-19" })]).fixtures[0];
  assert.equal(women.away.name, "West Indies Women");
  assert.notEqual(women.away.id, normalized().fixtures[0].away.id);
  assert.match(youth.away.name, /Women/);
  assert.match(youth.away.name, /19/);
});

test("terminal status wins over a stale live flag; break remains live", () => {
  assert.equal(normalized([row({ is_match_ended: true })]).fixtures[0].status, "finished");
  assert.equal(normalized([row({ is_match_abandoned: true })]).fixtures[0].status, "cancelled");
  assert.equal(normalized([row({ is_match_on_break: true })]).fixtures[0].status, "live");
});

test("unknown groups fail closed; explicit provisional teams/date do not fabricate a pairing", () => {
  assert.throws(() => normalized([row({ league_id: "200" })]), /Unknown ICC/);
  assert.equal(normalized([row({ is_provisional_time: true })]).fixtures.length, 0);
  assert.equal(normalized([row({ teama: "T.B.C.", teamb: "T.B.C.", teama_id: "", teamb_id: "" })]).fixtures.length, 0);
});

test("complete pagination is bounded and count mismatch, duplicates and empty pages reject", async () => {
  assert.throws(() => normalizeICC([parseICCPage(payload([row()], { count: 2 }), now)], now), /Truncated/);
  assert.throws(() => normalized([row(), row()]), /Duplicate/);
  let requests = 0;
  await assert.rejects(() => collectICC(now, async () => { requests++; return Response.json(payload([], { count: 1 })); }), /incomplete/);
  assert.equal(requests, 1);
  requests = 0;
  const result = await collectICC(now, async (url) => {
    requests++;
    const second = url.searchParams.get("page_number") === "2";
    return Response.json(payload([row(second ? { match_id: "270272", match_time_gmt: "09:30" } : {})], { count: 2 }));
  });
  assert.equal(result.fixtures.length, 2);
  assert.equal(requests, 2);
});

test("rolling window includes multi-day Test starts and never uses local timezone", () => {
  const window = cricketWindow(now);
  assert.equal(window.from.toISOString(), "2026-09-24T00:00:00.000Z");
  assert.equal(iccScheduleURL(now).searchParams.get("to_date"), "20261007");
  assert.equal(normalized([row({ match_type: "TEST", match_date_gmt: "9/26/2026" })]).fixtures[0].format, "Test");
});

test("disappearing active match, identity swap, terminal regression and unconfirmed start move are held", () => {
  const old = admitICC(normalized(), [], now).fixtures;
  assert.throws(() => admitICC({ fixtures: [], observedAt: now.toISOString() }, old, now), /disappeared/);
  assert.throws(() => admitICC(normalized([row({ teama_id: "7" })]), old, now), /identity/);
  assert.throws(() => admitICC(normalized([row({ match_time_gmt: "09:30" })]), old, now), /kickoff/);
  assert.doesNotThrow(() => admitICC(normalized([row({ match_time_gmt: "09:30", is_revised: true })]), old, now));
  assert.throws(() => admitICC(normalized(), [{ ...old[0], status: "finished" }], now), /regression/);
});

test("successful receipt refresh leaves content revision stable; failure retains receipt/rows", async () => {
  const first = await refreshCricketState(null, now, async () => normalized());
  const later = new Date(now.getTime() + 5 * 60_000);
  const second = await refreshCricketState(first, later, async () => ({ ...normalized(), observedAt: later.toISOString(),
    fixtures: normalized().fixtures.map((f) => ({ ...f, source: { ...f.source, observedAt: later.toISOString() } })) }));
  assert.equal(first.snapshot.revision, second.snapshot.revision);
  assert.equal(second.snapshot.checkedAt, later.toISOString());
  const failed = await refreshCricketState(second, new Date(later.getTime() + 5 * 60_000), async () => { throw new Error("timeout"); });
  assert.equal(failed.snapshot.sourceStatus, "last-known-good");
  assert.equal(failed.snapshot.checkedAt, second.snapshot.checkedAt);
  assert.deepEqual(failed.snapshot.fixtures, second.snapshot.fixtures);
  assert.equal(failed.consecutiveFailures, 1);
  assert.equal(failed.snapshot.coverage.find((c) => c.competitionId === "west-indies").status, "unavailable");
});

test("quiet, tomorrow and live refresh budgets are adaptive; terminal rows do not poll fast", () => {
  assert.equal(nextCricketRefresh(normalized().fixtures, now), 5 * 60_000);
  const future = { ...normalized().fixtures[0], status: "scheduled", start: new Date(now.getTime() + 2 * 3_600_000).toISOString() };
  assert.equal(nextCricketRefresh([future], now), 15 * 60_000);
  assert.equal(nextCricketRefresh([{ ...future, status: "finished" }], now), 4 * 3_600_000);
});

test("cold concurrent calls coalesce into one durable accepted snapshot", async () => {
  const storage = new Map();
  const state = { storage: { get: async (key) => storage.get(key), put: async (key, value) => storage.set(key, value) }, waitUntil: () => {} };
  let calls = 0;
  const registry = new CricketFixtureRegistry(state, {}, { collectICC: async () => { calls++; return normalized(); } });
  // Current clock is intentionally decoupled from candidate source fixtures in
  // this persistence/coalescing test; collector admission was tested above.
  const responses = await Promise.all(Array.from({ length: 5 }, () => registry.fetch(new Request("https://internal/fixtures"))));
  assert.equal(calls, 1);
  assert.ok(responses.every((r) => r.status === 200));
});

test("new public route preserves Worker identity/CORS and cannot expose internal refresh POST", async () => {
  const env = { CRICKET_FIXTURES: { idFromName: (n) => n, get: () => ({ fetch: async () => Response.json({ complete: true }) }) } };
  const response = await worker.fetch(new Request("https://worker/api/cricket/fixtures"), env);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
  assert.ok(response.headers.get("X-Fotty-Worker-Version"));
  assert.equal((await worker.fetch(new Request("https://worker/api/cricket/fixtures", { method: "POST" }), env)).status, 405);
});
