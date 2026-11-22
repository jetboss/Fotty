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

test("the international football switch enables only the three national-team feeds", async () => {
  const calls = []; const waits = [];
  const env = { FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0", FOTTY_SPORTS_INTERNATIONAL_FOOTBALL_ENABLED: "1",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { async fetch() { calls.push(name); return Response.json({ ok: true }); } }; } },
    CRICKET_FIXTURES: { idFromName(name) { return name; }, get() { return { async fetch() { return Response.json({ ok: true }); } }; } } };
  await worker.scheduled({}, env, { waitUntil(value) { waits.push(value); } });
  await Promise.all(waits);
  for (const id of ["uefa-nations-league", "international-friendlies", "concacaf-nations-league"]) {
    assert.ok(calls.some((name) => name.endsWith(`:${id}`)), id);
  }
  assert.equal(calls.some((name) => name.endsWith(":nba") || name.endsWith(":mls") || name.includes("tennis-atp")), false);
});

test("the NBA switch enables only the NBA ESPN feed (owner decision, 22 Nov 2026)", async () => {
  const calls = []; const waits = [];
  const env = { FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0", FOTTY_SPORTS_NBA_ENABLED: "1",
    SPORTS_FIXTURES: { idFromName(name) { return name; }, get(name) { return { async fetch() { calls.push(name); return Response.json({ ok: true }); } }; } },
    CRICKET_FIXTURES: { idFromName(name) { return name; }, get() { return { async fetch() { return Response.json({ ok: true }); } }; } } };
  await worker.scheduled({}, env, { waitUntil(value) { waits.push(value); } });
  await Promise.all(waits);
  assert.ok(calls.some((name) => name.endsWith(":nba")));
  for (const id of ["wnba", "nfl", "mls", "college-basketball-men", "college-basketball-women", "uefa-nations-league"]) {
    assert.equal(calls.some((name) => name.endsWith(`:${id}`)), false, id);
  }
  assert.equal(calls.some((name) => name.includes("tennis-atp")), false);
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

// Owner decision (21 Nov 2026): a failed read keeps accepted facts as they were.
test("EFL uses existing durable admission and preserves accepted Cup facts after collection failure", async () => {
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "efl-carabao-cup");
  const now = new Date("2026-10-28T20:12:35Z");
  const env = { FOTTY_SPORTS_EFL_ENABLED: "1" };
  const collect = (source, at) => collectSportsSource(source, at, env, async (url) => Response.json({
    data: [{ type: "match", id: "g2687775", attributes: { competitionID: 2,
      kickOffDateUTC: "2026-10-28 20:00:00", TBC: null, matchPeriod: "FirstHalf",
      matchMinutes: 12, homeTeam: { name: "Liverpool", score: 1 }, awayTeam: { name: "Chelsea", score: 0 } } }],
    meta: { count: 1, totalCount: 1 }, links: { self: String(url) },
  }, { headers: { Date: at.toUTCString() } }));
  const admitted = await refreshSportsSource(null, descriptor, now, collect);
  const current = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, admitted]]), now);
  assert.equal(current.coverage[0].status, "covered");
  assert.equal(current.fixtures[0].id, "sports-fixture:carabao-cup:g2687775");
  assert.equal(current.fixtures[0].status, "live");
  assert.deepEqual(current.fixtures[0].footballLive, { home: 1, away: 0, clock: "12′" });
  assert.equal(current.fixtures[0].source.verification, undefined, "The complete covered cohort supplies admission authority");
  const later = new Date(now.getTime() + 300_000);
  const failed = await refreshSportsSource(admitted, descriptor, later, async () => { throw new Error("Sports schedule upstream unavailable"); });
  const retained = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, failed]]), later);
  assert.equal(retained.coverage[0].status, "unavailable");
  assert.equal(retained.fixtures[0].source.verification, undefined, "A failed read never holds accepted facts");
  assert.equal(retained.fixtures[0].footballLive, undefined, "A score is never republished from a failed read");
  assert.equal(retained.fixtures[0].source.observedAt, now.toISOString());
  assert.equal(retained.fixtures[0].start, current.fixtures[0].start);
  assert.equal(retained.fixtures[0].competitionId, "carabao-cup");
  assert.equal(retained.coverage[0].sync.consecutiveFailures, 1);
});

test("EFL's typed empty-window response cannot erase an accepted active Cup fixture", async () => {
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "efl-carabao-cup");
  const first = new Date("2026-10-29T20:00:00Z"), later = new Date("2026-10-29T20:05:00Z");
  const env = { FOTTY_SPORTS_EFL_ENABLED: "1" };
  const admitted = await refreshSportsSource(null, descriptor, first, (source, at) => collectSportsSource(source, at, env,
    async (url) => Response.json({ data: [{ type: "match", id: "g2687773", attributes: {
      competitionID: 2, kickOffDateUTC: "2026-10-29 19:45:00", TBC: null, matchPeriod: "FirstHalf",
      homeTeam: { name: "Everton" }, awayTeam: { name: "Newcastle United" } } }],
    meta: { count: 1, totalCount: 1 }, links: { self: String(url) } }, { headers: { Date: at.toUTCString() } })));
  const refreshed = await refreshSportsSource(admitted, descriptor, later, (source, at) => collectSportsSource(source, at, env,
    async () => Response.json({ errors: [{ detail: "No matches found", title: "Not Found", status: "404" }] },
      { status: 404, headers: { Date: at.toUTCString() } })));
  const snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, refreshed]]), later);
  assert.equal(snapshot.coverage[0].status, "unavailable");
  assert.equal(snapshot.coverage[0].sync.consecutiveFailures, 1);
  assert.equal(snapshot.fixtures[0].id, "sports-fixture:carabao-cup:g2687773");
  assert.equal(snapshot.fixtures[0].source.verification, "held");
  assert.equal(snapshot.fixtures[0].source.observedAt, first.toISOString());
  assert.equal(snapshot.fixtures[0].start, "2026-10-29T19:45:00.000Z");
});

test("EFL's verified empty rolling window recovers source coverage after completed Cup fixtures age out", async () => {
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "efl-carabao-cup");
  const first = new Date("2026-10-30T21:50:04Z"), later = new Date("2026-11-01T19:02:44Z");
  const env = { FOTTY_SPORTS_EFL_ENABLED: "1" };
  const admitted = await refreshSportsSource(null, descriptor, first, (source, at) => collectSportsSource(source, at, env,
    async (url) => Response.json({ data: [{ type: "match", id: "g2687773", attributes: {
      competitionID: 2, kickOffDateUTC: "2026-10-29 19:45:00", TBC: null, matchPeriod: "FullTime",
      homeTeam: { name: "Everton" }, awayTeam: { name: "Newcastle United" } } }],
    meta: { count: 1, totalCount: 1 }, links: { self: String(url) } }, { headers: { Date: at.toUTCString() } })));
  const original = JSON.stringify(admitted);
  const refreshed = await refreshSportsSource(admitted, descriptor, later, (source, at) => collectSportsSource(source, at, env,
    async () => Response.json({ errors: [{ detail: "No matches found", title: "Not Found", status: "404" }] },
      { status: 404, headers: { Date: at.toUTCString() } })));
  const snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, refreshed]]), later);
  assert.equal(snapshot.coverage[0].status, "covered");
  assert.equal(snapshot.coverage[0].fixtureCount, 0);
  assert.equal(snapshot.coverage[0].sync.consecutiveFailures, 0);
  assert.equal(snapshot.coverage[0].sync.lastSuccessAt, later.toISOString());
  assert.deepEqual(snapshot.fixtures, []);
  assert.equal(JSON.stringify(admitted), original, "A new empty window cannot mutate the earlier accepted facts");
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
  assert.equal(calls.length, 4, "The hung group is retried once before it is reported unavailable");
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
  // Owner decision (21 Nov 2026): a failed read keeps the verified fresh row.
  const failedRead = await refreshSportsSource(partial, source, now, async () => { throw new Error("publisher unavailable"); });
  const kept = await responseFor(failedRead);
  assert.equal(kept.status, 200);
  assert.equal((await kept.json()).fixtures.find((row) => row.id.endsWith(":2")).source.verification, "verified");
});

test("per-league football-data rows assemble into the public snapshot (21 Nov 503 regression)", async () => {
  // Per-league rows carry /v4/competitions/{CODE}/matches as their source.
  // The snapshot used to accept only /v4/matches and failed the whole feed.
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "football-data");
  const now = new Date("2026-11-21T15:40:00Z");
  const env = { FOOTBALL_DATA_API_KEY: "test" };
  const collect = (source, at) => collectSportsSource(source, at, env, async (url) => {
    const code = url.pathname.split("/").at(-2);
    const matches = code === "PL" ? [{ id: 560642, utcDate: "2026-11-21T15:00:00Z", status: "IN_PLAY", minute: 40,
      lastUpdated: "2026-11-21T15:39:00Z", competition: { code: "PL" }, score: { fullTime: { home: 1, away: 1 } },
      homeTeam: { id: 61, name: "Chelsea FC" }, awayTeam: { id: 341, name: "Leeds United FC" } }] : [];
    return Response.json({ filters: { season: "2026" }, competition: { code },
      resultSet: { count: matches.length, ...(matches.length ? { first: "2026-11-21", last: "2026-11-21" } : {}) }, matches });
  });
  const admitted = await refreshSportsSource(null, descriptor, now, collect);
  const snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, admitted]]), now);
  const fixture = snapshot.fixtures.find((row) => row.id === "sports-fixture:premier-league:560642");
  assert.equal(fixture.status, "live");
  assert.equal(new URL(fixture.source.url).pathname, "/v4/competitions/PL/matches");

  // A league path that doesn't belong to the row's competition is still refused.
  const forged = { ...admitted, accepted: { ...admitted.accepted, fixtures: admitted.accepted.fixtures.map((row) =>
    ({ ...row, source: { ...row.source, url: "https://api.football-data.org/v4/competitions/CL/matches" } })) } };
  await assert.rejects(() => assembleSportsSnapshot([descriptor], new Map([[descriptor.id, forged]]), now), /provenance/);
});

test("a held per-league row is named in coverage and the snapshot still assembles", async () => {
  // End to end with populated stored rows (lesson from the 21 Nov 503).
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "football-data");
  const env = { FOOTBALL_DATA_API_KEY: "test" };
  const row = (status) => ({ id: 560643, utcDate: "2026-11-21T12:30:00Z", status,
    lastUpdated: status === "FINISHED" ? "2026-11-21T14:27:00Z" : "2026-11-21T15:04:00Z",
    competition: { code: "PL" }, homeTeam: { id: 65, name: "Manchester City FC" }, awayTeam: { id: 63, name: "Fulham FC" } });
  const collect = (status) => (source, at) => collectSportsSource(source, at, env, async (url) => {
    const code = url.pathname.split("/").at(-2);
    const matches = code === "PL" ? [row(status)] : [];
    return Response.json({ filters: { season: "2026" }, competition: { code },
      resultSet: { count: matches.length, ...(matches.length ? { first: "2026-11-21", last: "2026-11-21" } : {}) }, matches });
  });
  const first = new Date("2026-11-21T15:00:00Z"), second = new Date("2026-11-21T15:05:00Z");
  const finished = await refreshSportsSource(null, descriptor, first, collect("FINISHED"));
  const regressed = await refreshSportsSource(finished, descriptor, second, collect("IN_PLAY"));
  const snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, regressed]]), second);
  const lane = snapshot.coverage.find((coverage) => coverage.competitionId === "premier-league");
  assert.equal(lane.sync.failure.code, "terminal-rollback");
  assert.equal(lane.sync.failure.fixtureId, "sports-fixture:premier-league:560643");
  assert.deepEqual(lane.heldFixtureIds, ["sports-fixture:premier-league:560643"]);
  assert.equal(snapshot.fixtures.find((fixture) => fixture.id.endsWith(":560643")).status, "finished");
});

test("an older publisher copy never holds a league: finished stays finished, live stays live", async () => {
  // 21 Nov: a stale football-data replica sent Lazio-Lecce as IN_PLAY and
  // Parma-Roma as TIMED, both with older lastUpdated than the accepted rows.
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "football-data");
  const env = { FOOTBALL_DATA_API_KEY: "test" };
  const lazio = (status, lastUpdated) => ({ id: 558528, utcDate: "2026-11-21T14:00:00Z", status, lastUpdated,
    competition: { code: "SA" }, homeTeam: { id: 110, name: "SS Lazio" }, awayTeam: { id: 5890, name: "US Lecce" } });
  const parma = (status, lastUpdated) => ({ id: 558526, utcDate: "2026-11-21T17:00:00Z", status, lastUpdated,
    competition: { code: "SA" }, homeTeam: { id: 112, name: "Parma Calcio 1913" }, awayTeam: { id: 100, name: "AS Roma" } });
  const collect = (rows) => (source, at) => collectSportsSource(source, at, env, async (url) => {
    const code = url.pathname.split("/").at(-2);
    const matches = code === "SA" ? rows : [];
    return Response.json({ filters: { season: "2026" }, competition: { code },
      resultSet: { count: matches.length, ...(matches.length ? { first: "2026-11-21", last: "2026-11-21" } : {}) }, matches });
  });
  const first = new Date("2026-11-21T17:29:30Z"), second = new Date("2026-11-21T17:35:00Z");
  const accepted = await refreshSportsSource(null, descriptor, first,
    collect([lazio("FINISHED", "2026-11-21T15:57:31Z"), parma("IN_PLAY", "2026-11-21T17:29:14Z")]));
  const stale = await refreshSportsSource(accepted, descriptor, second,
    collect([lazio("IN_PLAY", "2026-11-21T15:40:00Z"), parma("TIMED", "2026-11-21T00:20:36Z")]));
  const snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, stale]]), second);
  const lane = snapshot.coverage.find((coverage) => coverage.competitionId === "serie-a");
  assert.equal(lane.status, "covered");
  assert.equal(lane.sync.failure, undefined);
  assert.equal(lane.heldFixtureIds, undefined);
  const byID = new Map(snapshot.fixtures.map((fixture) => [fixture.id, fixture]));
  assert.equal(byID.get("sports-fixture:serie-a:558528").status, "finished");
  assert.equal(byID.get("sports-fixture:serie-a:558526").status, "live");
  assert.equal(byID.get("sports-fixture:serie-a:558526").source.updatedAt, "2026-11-21T17:29:14.000Z");

  // A genuinely newer contradiction is still refused: un-finishing with a newer stamp.
  const newer = await refreshSportsSource(accepted, descriptor, second,
    collect([lazio("IN_PLAY", "2026-11-21T17:34:00Z"), parma("IN_PLAY", "2026-11-21T17:34:30Z")]));
  const refused = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, newer]]), second);
  const refusedLane = refused.coverage.find((coverage) => coverage.competitionId === "serie-a");
  assert.equal(refusedLane.sync.failure.code, "terminal-rollback");
  assert.equal(refused.fixtures.find((fixture) => fixture.id.endsWith(":558526")).status, "live");
});

test("an ESPN-live row admits, assembles, survives a lagging football-data copy and hands over", async () => {
  const descriptor = SPORTS_SOURCES.find((source) => source.id === "football-data");
  const env = { FOOTBALL_DATA_API_KEY: "test" };
  const sa = (status, lastUpdated) => ({ id: 558526, utcDate: "2026-11-21T17:30:00Z", status, lastUpdated,
    competition: { code: "SA" }, homeTeam: { id: 112, name: "Parma Calcio 1913", shortName: "Parma" },
    awayTeam: { id: 100, name: "AS Roma", shortName: "Roma" } });
  const event = { id: "735001", date: "2026-11-21T17:30Z",
    status: { displayClock: "12'", type: { name: "STATUS_FIRST_HALF", state: "in", completed: false } },
    competitions: [{ competitors: [{ homeAway: "home", score: "0", team: { displayName: "Parma" } },
      { homeAway: "away", score: "1", team: { displayName: "AS Roma" } }] }] };
  const collect = (row, espn) => (source, at) => collectSportsSource(source, at, env, async (url) => {
    if (url.hostname === "site.api.espn.com") return Response.json({ leagues: [{ slug: "ita.1" }], events: espn ? [espn] : [] });
    const code = url.pathname.split("/").at(-2);
    const matches = code === "SA" ? [row] : [];
    return Response.json({ filters: { season: "2026" }, competition: { code },
      resultSet: { count: matches.length, ...(matches.length ? { first: "2026-11-21", last: "2026-11-21" } : {}) }, matches });
  });
  const t1 = new Date("2026-11-21T17:40:00Z"), t2 = new Date("2026-11-21T17:45:00Z"), t3 = new Date("2026-11-21T17:50:00Z");
  const first = await refreshSportsSource(null, descriptor, t1, collect(sa("TIMED", "2026-11-21T00:20:36Z"), event));
  let snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, first]]), t1);
  let row = snapshot.fixtures.find((fixture) => fixture.id.endsWith(":558526"));
  assert.equal(row.status, "live");
  assert.deepEqual(row.footballLive, { home: 0, away: 1, clock: "12′" });
  assert.equal(snapshot.coverage.find((lane) => lane.competitionId === "serie-a").status, "covered");

  // ESPN briefly unavailable, football-data still lagging: the accepted live row stays live.
  const second = await refreshSportsSource(first, descriptor, t2, collect(sa("TIMED", "2026-11-21T00:20:36Z"), null));
  snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, second]]), t2);
  row = snapshot.fixtures.find((fixture) => fixture.id.endsWith(":558526"));
  assert.equal(row.status, "live");
  assert.equal(snapshot.coverage.find((lane) => lane.competitionId === "serie-a").status, "covered");

  // football-data catches up with a newer stamp: its own row takes over.
  const third = await refreshSportsSource(second, descriptor, t3, collect(sa("IN_PLAY", "2026-11-21T17:49:30Z"), null));
  snapshot = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, third]]), t3);
  row = snapshot.fixtures.find((fixture) => fixture.id.endsWith(":558526"));
  assert.equal(row.status, "live");
  assert.equal(row.liveEvidence, undefined);
  assert.equal(row.source.updatedAt, "2026-11-21T17:49:30.000Z");
});
