import test from "node:test";
import assert from "node:assert/strict";
import worker from "./index.js";
import { SPORTS_SOURCES, collectSportsSource } from "./sports-fixture-sources.mjs";
import { SPORTS_EVENT_SOURCES } from "./sports-fixture-event-sources.mjs";
import { refreshSportsSource, assembleSportsSnapshot } from "./sports-fixture-registry.mjs";

test("staged service returns pending and cannot collect without explicit activation", async () => {
  let calls = 0;
  const response = await worker.fetch(new Request("https://test.invalid/api/sports/fixtures"), {
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get() { calls++; throw new Error("Should not collect"); } }, FOTTY_SPORTS_FIXTURES_ENABLED: "0",
  });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).activation, "pending");
  assert.equal(calls, 0);
});

test("general activation does not enable unreviewed public website feeds", async () => {
  const calls = []; const waits = [];
  const env = { FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { async fetch() { calls.push(name); return Response.json({ ok: true }); } }; } },
    CRICKET_FIXTURES: { idFromName(name) { return name; }, get() { return { async fetch() { return Response.json({ ok: true }); } }; } } };
  await worker.scheduled({}, env, { waitUntil(value) { waits.push(value); } });
  await Promise.all(waits);
  assert.equal(calls.length, SPORTS_SOURCES.filter((source) => source.supported && !source.publicUndocumented
    && !["wnba", "efl-carabao-cup"].includes(source.id)).length);
  assert.equal(calls.some((name) => name.endsWith(":wnba")), false);
  assert.equal(calls.some((name) => name.endsWith(":efl-carabao-cup")), false);
  assert.equal(calls.some((name) => name.endsWith(":nba") || name.includes("tennis-atp")), false);
});

test("one failing source group does not stop later cricket/sports refresh groups", async () => {
  const calls = []; const waits = [];
  const env = { FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "1", FOTTY_SPORTS_WNBA_ENABLED: "1", FOTTY_SPORTS_EFL_ENABLED: "1",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { async fetch() { calls.push(name); if (name.endsWith(":football-data")) throw new Error("private error"); return Response.json({ ok: true }); } }; } } };
  await worker.scheduled({}, env, { waitUntil(value) { waits.push(value); } });
  await Promise.all(waits);
  assert.equal(calls.length, [...SPORTS_SOURCES, ...SPORTS_EVENT_SOURCES].filter((source) => source.supported).length);
  assert.ok(calls.some((name) => name.endsWith(":afl")));
  assert.ok(calls.length < 49, "the coordinator stays within the free subrequest ceiling with cricket retained");
});

test("dedicated EFL activation does not activate ESPN website feeds or WNBA", async () => {
  const calls = [], waits = [];
  await worker.scheduled({}, { FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_EFL_ENABLED: "1",
    FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0", FOTTY_SPORTS_WNBA_ENABLED: "0",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { async fetch() {
      calls.push(name); return Response.json({ ok: true });
    } }; } },
  }, { waitUntil(value) { waits.push(value); } });
  await Promise.all(waits);
  assert.ok(calls.some((name) => name.endsWith(":efl-carabao-cup")));
  assert.equal(calls.some((name) => name.endsWith(":nba") || name.endsWith(":wnba") || name.includes("tennis-atp")), false);
});

test("EFL uses existing durable admission and preserves accepted Cup facts after collection failure", async () => {
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "efl-carabao-cup");
  const now = new Date("2026-10-28T20:12:35Z");
  const env = { FOTTY_SPORTS_EFL_ENABLED: "1" };
  const collect = (source, at) => collectSportsSource(source, at, env, async (url) => Response.json({
    data: [{ type: "match", id: "g2687775", attributes: { competitionID: 2,
      kickOffDateUTC: "2026-10-28 20:00:00", TBC: null, matchPeriod: "FirstHalf",
      homeTeam: { name: "Liverpool" }, awayTeam: { name: "Chelsea" } } }],
    meta: { count: 1, totalCount: 1 }, links: { self: String(url) },
  }, { headers: { Date: at.toUTCString() } }));
  const admitted = await refreshSportsSource(null, descriptor, now, collect);
  const current = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, admitted]]), now);
  assert.equal(current.coverage[0].status, "covered");
  assert.equal(current.fixtures[0].id, "sports-fixture:carabao-cup:g2687775");
  assert.equal(current.fixtures[0].status, "live");
  assert.equal(current.fixtures[0].source.verification, undefined, "The complete covered cohort supplies admission authority");
  const later = new Date(now.getTime() + 300_000);
  const failed = await refreshSportsSource(admitted, descriptor, later, async () => { throw new Error("Sports schedule upstream unavailable"); });
  const retained = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, failed]]), later);
  assert.equal(retained.coverage[0].status, "unavailable");
  assert.equal(retained.fixtures[0].source.verification, "held");
  assert.equal(retained.fixtures[0].source.observedAt, now.toISOString());
  assert.equal(retained.fixtures[0].start, current.fixtures[0].start);
  assert.equal(retained.fixtures[0].competitionId, "carabao-cup");
  assert.equal(retained.coverage[0].sync.consecutiveFailures, 1);
});

test("a hung registry GET expires while other source receipts remain available", async () => {
  const calls = []; const now = new Date().toISOString();
  const response = await worker.fetch(new Request("https://test.invalid/api/sports/fixtures"), {
    FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { fetch() {
      calls.push(name); if (name.endsWith(":football-data")) return new Promise(() => {});
      return Promise.resolve(Response.json({ accepted: { fixtures: [], observedAt: now, pendingFixtureCount: 0 }, consecutiveFailures: 0 }));
    } }; } },
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.coverage.find((row) => row.competitionId === "mlb").status, "covered");
  assert.equal(body.coverage.find((row) => row.competitionId === "premier-league").status, "unavailable");
  assert.equal(body.coverage.find((row) => row.competitionId === "atp").status, "unsupported");
  assert.equal(body.coverage.find((row) => row.competitionId === "wnba").status, "unsupported");
  assert.equal(calls.length, 3);
});

test("a wholly partial service exposes validated fresh rows without masking held conflicts", async () => {
  const source = SPORTS_SOURCES.find((row) => row.id === "mlb");
  const now = new Date(), oldAt = new Date(now.getTime() - 300_000);
  const make = (id, at) => ({ id: `sports-fixture:mlb:${id}`, sport: "baseball", competitionId: "mlb",
    competitionName: source.competitions[0].name, title: "Alpha vs Beta", eventKind: "match",
    start: new Date(now.getTime() - 600_000).toISOString(), status: "live", squad: { gender: "men", ageGroup: "senior" },
    participants: [{ id: `mlb:${id}1`, name: "Alpha", role: "home" }, { id: `mlb:${id}2`, name: "Beta", role: "away" }],
    source: { name: source.sourceName, url: `${source.sourceURL}?sportId=1`, observedAt: at.toISOString() } });
  const collection = (rows, at) => ({ fixtures: rows, observedAt: at.toISOString(), pendingFixtureCount: 0, pendingByCompetition: { mlb: 0 } });
  const previous = await refreshSportsSource(null, source, oldAt, async () => collection([make(1, oldAt)], oldAt));
  const partial = await refreshSportsSource(previous, source, now, async () => collection([make(2, now)], now));
  const responseFor = (state) => worker.fetch(new Request("https://test.invalid/api/sports/fixtures"), {
    FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { async fetch() {
      return Response.json(name.endsWith(":mlb") ? state : { consecutiveFailures: 1 });
    } }; } },
  });
  const response = await responseFor(partial);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.sourceStatus, "partial");
  assert.ok(body.coverage.every((row) => row.status !== "covered"));
  assert.equal(body.fixtures.find((row) => row.id.endsWith(":1")).source.verification, "held");
  assert.equal(body.fixtures.find((row) => row.id.endsWith(":2")).source.verification, "verified");
  assert.equal(body.coverage.find((row) => row.competitionId === "mlb").sync.consecutiveFailures, 1);
  assert.equal(body.checkedAt, now.toISOString());
  for (const corrupt of [
    (state) => { state.accepted.fixtures[0].source.verification = null; },
    (state) => { state.accepted.fixtures[0].participants[0].name = "TBD"; },
    (state) => { state.accepted.fixtures[0].source.url = "https://unreviewed.example/schedule"; },
    (state) => { state.accepted.fixtures[0].source.name = "Unreviewed publisher"; },
    (state) => { state.accepted.fixtures.find((row) => row.source.verification === "verified").source.observedAt = oldAt.toISOString(); },
    (state) => { delete state.cohorts; },
  ]) {
    const state = structuredClone(partial); corrupt(state);
    assert.equal((await responseFor(state)).status, 503, "a marker alone cannot bypass complete admitted provenance");
  }
  const heldOnly = await refreshSportsSource(partial, source, now, async () => { throw new Error("publisher unavailable"); });
  assert.equal((await responseFor(heldOnly)).status, 503);
});
