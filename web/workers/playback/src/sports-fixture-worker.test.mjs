import test from "node:test";
import assert from "node:assert/strict";
import worker from "./index.js";
import { SPORTS_SOURCES } from "./sports-fixture-sources.mjs";
import { SPORTS_EVENT_SOURCES } from "./sports-fixture-event-sources.mjs";

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
  assert.equal(calls.length, SPORTS_SOURCES.filter((source) => source.supported && !source.publicUndocumented && source.id !== "wnba").length);
  assert.equal(calls.some((name) => name.endsWith(":wnba")), false);
  assert.equal(calls.some((name) => name.endsWith(":nba") || name.includes("tennis-atp")), false);
});

test("one failing source group does not stop later cricket/sports refresh groups", async () => {
  const calls = []; const waits = [];
  const env = { FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "1", FOTTY_SPORTS_WNBA_ENABLED: "1",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { async fetch() { calls.push(name); if (name.endsWith(":football-data")) throw new Error("private error"); return Response.json({ ok: true }); } }; } } };
  await worker.scheduled({}, env, { waitUntil(value) { waits.push(value); } });
  await Promise.all(waits);
  assert.equal(calls.length, [...SPORTS_SOURCES, ...SPORTS_EVENT_SOURCES].filter((source) => source.supported).length);
  assert.ok(calls.some((name) => name.endsWith(":afl")));
  assert.ok(calls.length < 49, "the coordinator stays within the free subrequest ceiling with cricket retained");
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
