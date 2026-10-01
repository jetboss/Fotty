import test from "node:test";
import assert from "node:assert/strict";
import { SPORTS_SOURCES, sportsFixtureWindow } from "../web/workers/playback/src/sports-fixture-sources.mjs";
import { SPORTS_CROSSCHECK_SOURCE_IDS, collectSportsFixtureCrosscheck, reconcileSportsFixtureCoverage } from "./sports-fixture-crosscheck.mjs";

const now = Date.parse("2026-09-30T16:00:00.000Z");
const MINUTE = 60_000;
const iso = (time) => new Date(time).toISOString();
const source = (id) => SPORTS_SOURCES.find((descriptor) => descriptor.id === id);
const url = (id) => id === "mlb" ? `${source(id).sourceURL}?sportId=1&startDate=2026-09-29&endDate=2026-10-07`
  : id === "nhl" ? `${source(id).sourceURL}/2026-09-29` : source(id).sourceURL;
function fixture(id = "mlb", eventID = "100", overrides = {}) {
  const descriptor = source(id);
  return { id: `sports-fixture:${id}:${eventID}`, sport: descriptor.sport, competitionId: id,
    competitionName: descriptor.competitions[0].name, eventKind: "match", title: "Alpha vs Beta",
    start: iso(now - 60 * MINUTE), status: "live",
    participants: [{ id: `${id}:1`, name: "Alpha", role: "home" }, { id: `${id}:2`, name: "Beta", role: "away" }],
    squad: { gender: descriptor.gender, ageGroup: descriptor.ageGroup },
    source: { name: descriptor.sourceName, url: url(id), observedAt: iso(now) }, ...overrides };
}
function snapshot(rows = { mlb: [] }, age = 20 * MINUTE) {
  const fixtures = Object.values(rows).flat().map((row) => ({ ...structuredClone(row), source: { ...row.source, observedAt: iso(now - age) } }));
  return { schemaVersion: 1, complete: true, revision: "synthetic", sourceStatus: "verified", checkedAt: iso(now - age), fixtures,
    coverage: Object.entries(rows).map(([id, records]) => ({ competitionId: id, competitionName: source(id).competitions[0].name,
      sport: source(id).sport, status: "covered", checkedAt: iso(now - age), fixtureCount: records.length,
      pendingFixtureCount: 0, sync: { consecutiveFailures: 0 } })) };
}
function collection(fixtures = [], overrides = {}) {
  return { fixtures: structuredClone(fixtures), pendingFixtureCount: 0, observedAt: iso(now),
    ...sportsFixtureWindow(new Date(now)), ...overrides };
}
const reconcile = (body, comparisons) => reconcileSportsFixtureCoverage(body, comparisons, { now });
function mlbGame(overrides = {}) {
  return { gamePk: 100, officialDate: "2026-09-30", gameDate: iso(now - 60 * MINUTE), ifNecessary: "N",
    status: { codedGameState: "I", abstractGameState: "Live", detailedState: "In Progress", startTimeTBD: false },
    teams: { home: { team: { id: 1, name: "Alpha" } }, away: { team: { id: 2, name: "Beta" } } }, ...overrides };
}
function mlbPayload(rows = [mlbGame()]) {
  return { totalItems: rows.length, totalGames: rows.length, totalEvents: 0,
    dates: rows.length ? [{ date: "2026-09-30", totalItems: rows.length, totalGames: rows.length, totalEvents: 0, games: rows }] : [] };
}

test("matching live and next-24-hour fixtures are same-upstream reconciliation, not independent corroboration", async () => {
  const rows = [fixture(), fixture("mlb", "101", { start: iso(now + 2 * 60 * MINUTE), status: "scheduled" })];
  const body = snapshot({ mlb: rows });
  const before = JSON.stringify(body);
  const report = await reconcile(body, { mlb: collection(rows) });
  assert.equal(report.mode, "same-upstream-independently-fetched");
  assert.equal(report.lanes[0].status, "matched");
  assert.equal(report.lanes[0].matchedCount, 2);
  assert.deepEqual(report.findings, []);
  assert.equal(JSON.stringify(body), before);
});

test("finished, cancelled, postponed, unknown, elapsed scheduled and exact 24-hour boundary rows do not establish expected omissions", async () => {
  const rows = [fixture("mlb", "100", { status: "finished" }), fixture("mlb", "101", { status: "cancelled" }),
    fixture("mlb", "102", { status: "postponed" }), fixture("mlb", "103", { status: "unknown" }),
    fixture("mlb", "104", { status: "scheduled" }), fixture("mlb", "105", { status: "scheduled", start: iso(now + 24 * 60 * MINUTE) })];
  const report = await reconcile(snapshot(), { mlb: collection(rows, { pendingFixtureCount: 3 }) });
  assert.equal(report.lanes[0].expectedCount, 0);
  assert.equal(report.lanes[0].pendingFixtureCount, 3);
  assert.deepEqual(report.findings, []);
});

test("an exact missing live or imminent identity after ten-minute grace is actionable with a fixed digest only", async () => {
  for (const row of [fixture(), fixture("mlb", "100", { status: "scheduled", start: iso(now + 30 * MINUTE) })]) {
    const report = await reconcile(snapshot(), { mlb: collection([row]) });
    assert.equal(report.lanes[0].omittedCount, 1);
    assert.deepEqual(report.findings.map(({ evidenceKey, ...finding }) => finding),
      [{ code: "same-upstream-current-omission", competitionId: "mlb", actionable: true }]);
    assert.match(report.findings[0].evidenceKey, /^[a-f0-9]{64}$/);
    assert.equal(JSON.stringify(report).includes("Alpha"), false);
    assert.equal(JSON.stringify(report).includes("https://"), false);
  }
});

test("recent current omissions retain a non-actionable repeat key; farther-future gaps remain informational only", async () => {
  const recent = await reconcile(snapshot({ mlb: [] }, 9 * MINUTE), { mlb: collection([fixture()]) });
  assert.equal(recent.lanes[0].status, "comparison-pending");
  assert.equal(recent.findings[0].code, "same-upstream-current-omission");
  assert.equal(recent.findings[0].actionable, false);
  assert.match(recent.findings[0].evidenceKey, /^[a-f0-9]{64}$/);
  const future = await reconcile(snapshot(), { mlb: collection([fixture("mlb", "100", { status: "scheduled", start: iso(now + 31 * MINUTE) })]) });
  assert.equal(future.lanes[0].status, "comparison-pending");
  assert.equal(future.lanes[0].omittedCount, 1);
  assert.deepEqual(future.findings, []);
});

test("a live omission remains repeat-detectable across fresh receipts renewed every five minutes", async () => {
  const first = await reconcile(snapshot({ mlb: [] }, 5 * MINUTE), { mlb: collection([fixture()]) });
  const later = now + 60 * MINUTE;
  const body = snapshot(); body.checkedAt = body.coverage[0].checkedAt = iso(later - 5 * MINUTE);
  const row = fixture(); row.source.observedAt = iso(later);
  const repeated = await reconcileSportsFixtureCoverage(body, { mlb: collection([row], { observedAt: iso(later) }) }, { now: later });
  assert.equal(first.findings[0].actionable, false);
  assert.equal(repeated.findings[0].actionable, false);
  assert.equal(first.findings[0].evidenceKey, repeated.findings[0].evidenceKey);
  const recovered = await reconcile(snapshot({ mlb: [fixture()] }, 5 * MINUTE), { mlb: collection([fixture()]) });
  assert.equal(recovered.lanes[0].status, "matched");
  assert.deepEqual(recovered.findings, []);
});

test("continuously renewed same-ID disagreements remain non-actionable repeat findings during grace", async () => {
  const old = fixture(); old.participants[0].id = "mlb:3";
  const first = await reconcile(snapshot({ mlb: [old] }, 5 * MINUTE), { mlb: collection([fixture()]) });
  const repeated = await reconcile(snapshot({ mlb: [old] }, MINUTE), { mlb: collection([fixture()]) });
  assert.equal(first.lanes[0].status, "comparison-pending");
  assert.equal(first.findings[0].actionable, false);
  assert.equal(first.findings[0].evidenceKey, repeated.findings[0].evidenceKey);
});

test("old accepted quiet-lane receipts cannot establish actionable omissions or disagreements", async () => {
  const old = await reconcile(snapshot({ mlb: [] }, 31 * MINUTE), { mlb: collection([fixture()]) });
  assert.equal(old.lanes[0].status, "comparison-stale");
  assert.deepEqual(old.findings, []);
  const accepted = fixture(); accepted.start = iso(now - 2 * 60 * MINUTE);
  const disagreement = await reconcile(snapshot({ mlb: [accepted] }, 4 * 60 * MINUTE), { mlb: collection([fixture()]) });
  assert.equal(disagreement.lanes[0].disagreementCount, 1);
  assert.deepEqual(disagreement.findings, []);
});

test("a changed team, UTC, squad, source origin or status for the same event is a non-actionable disagreement, never an omission", async () => {
  const variants = [
    (row) => { row.participants[0].id = "mlb:3"; },
    (row) => { row.start = iso(now - 2 * 60 * MINUTE); },
    (row) => { row.squad.gender = "women"; },
    (row) => { row.source.url = "https://example.com/private-untrusted"; },
    (row) => { row.status = "scheduled"; },
  ];
  for (const mutate of variants) {
    const old = fixture(); mutate(old);
    const report = await reconcile(snapshot({ mlb: [old] }), { mlb: collection([fixture()]) });
    assert.equal(report.lanes[0].disagreementCount, 1);
    assert.equal(report.lanes[0].omittedCount, 0);
    assert.equal(report.findings[0].code, "same-upstream-fixture-disagreement");
    assert.equal(report.findings[0].actionable, false);
    assert.match(report.findings[0].evidenceKey, /^[a-f0-9]{64}$/);
    assert.equal(JSON.stringify(report).includes("private-untrusted"), false);
  }
});

test("disagreement keys ignore observation receipts but change when compared facts change", async () => {
  const old = fixture(); old.start = iso(now - 2 * 60 * MINUTE);
  const first = await reconcile(snapshot({ mlb: [old] }), { mlb: collection([fixture()]) });
  const current = fixture(); current.source.observedAt = iso(now - MINUTE);
  const repeat = await reconcile(snapshot({ mlb: [old] }, 15 * MINUTE), { mlb: collection([current], { observedAt: iso(now - MINUTE) }) });
  assert.equal(first.findings[0].evidenceKey, repeat.findings[0].evidenceKey);
  old.participants[0].id = "mlb:3";
  const changed = await reconcile(snapshot({ mlb: [old] }), { mlb: collection([fixture()]) });
  assert.notEqual(first.findings[0].evidenceKey, changed.findings[0].evidenceKey);
});

test("distinct untrusted publisher identity facts cannot satisfy an identical-disagreement repeat", async () => {
  const old = fixture(); old.source.url = "https://wrong-one.example/schedule";
  const first = await reconcile(snapshot({ mlb: [old] }), { mlb: collection([fixture()]) });
  old.source.url = "https://wrong-two.example/schedule";
  const changedURL = await reconcile(snapshot({ mlb: [old] }), { mlb: collection([fixture()]) });
  assert.notEqual(first.findings[0].evidenceKey, changedURL.findings[0].evidenceKey);
  old.source.name = "Different publisher";
  const changedName = await reconcile(snapshot({ mlb: [old] }), { mlb: collection([fixture()]) });
  assert.notEqual(changedURL.findings[0].evidenceKey, changedName.findings[0].evidenceKey);
  assert.equal(JSON.stringify(changedName).includes("wrong-two"), false);
  assert.equal(JSON.stringify(changedName).includes("Different publisher"), false);
});

test("equal teams and time under another provider event ID do not substitute for an exact missing identity", async () => {
  const report = await reconcile(snapshot({ mlb: [fixture("mlb", "101")] }), { mlb: collection([fixture()]) });
  assert.equal(report.lanes[0].omittedCount, 1);
  assert.equal(report.findings[0].code, "same-upstream-current-omission");
});

test("stale comparison receipts cannot turn missing events into confirmed omissions", async () => {
  const row = fixture(); row.source.observedAt = iso(now - 6 * MINUTE);
  const report = await reconcile(snapshot(), { mlb: collection([row], { observedAt: row.source.observedAt }) });
  assert.equal(report.lanes[0].status, "comparison-stale");
  assert.deepEqual(report.findings, [{ code: "comparison-receipt-stale", competitionId: "mlb", actionable: false }]);
});

test("incomplete windows, duplicate IDs, wrong squads and unknown participant identities fail comparison closed", async () => {
  const wrongSquad = fixture(); wrongSquad.squad.gender = "women";
  const wrongTeamID = fixture(); wrongTeamID.participants[0].id = "unknown:1";
  const wrongRole = fixture(); wrongRole.participants[0].role = "untrusted";
  const invalidCollections = [collection([fixture()], { windowEnd: "2026-10-07T00:00:00.000Z" }),
    collection([fixture(), fixture()]), collection([wrongSquad]), collection([wrongTeamID]), collection([wrongRole])];
  for (const invalid of invalidCollections) {
    const report = await reconcile(snapshot(), { mlb: invalid });
    assert.equal(report.lanes[0].status, "comparison-unavailable");
    assert.deepEqual(report.findings, [{ code: "comparison-source-unavailable", competitionId: "mlb", actionable: false }]);
  }
});

test("an old publisher artifact on an imminent fixture is stale even with a new fetch receipt", async () => {
  const row = fixture("wnba", "100", { status: "scheduled", start: iso(now + 5 * MINUTE) });
  row.source.updatedAt = iso(now - 30 * MINUTE);
  const report = await reconcile(snapshot({ wnba: [] }), { wnba: collection([row]) });
  assert.equal(report.lanes[0].status, "comparison-stale");
  assert.equal(report.findings[0].code, "comparison-receipt-stale");
  assert.equal(report.findings[0].actionable, false);
});

test("only covered MLB/NHL/WNBA lanes are fetched; ESPN and football-data remain excluded", async () => {
  assert.deepEqual(SPORTS_CROSSCHECK_SOURCE_IDS, ["mlb", "nhl", "wnba"]);
  const body = snapshot({ mlb: [], nba: [], nhl: [], wnba: [] });
  body.coverage.find((row) => row.competitionId === "nhl").status = "unsupported";
  body.coverage.find((row) => row.competitionId === "wnba").status = "unavailable";
  const called = [];
  const report = await collectSportsFixtureCrosscheck(body, { now, collect: async (descriptor, observed, env) => {
    called.push(descriptor.id); assert.deepEqual(env, {}); assert.equal(observed.getTime(), now); return collection();
  } });
  assert.deepEqual(called, ["mlb"]);
  assert.deepEqual(report.lanes.map((row) => row.sourceId), ["mlb"]);
  assert.deepEqual(report.findings, []);
  body.coverage.find((row) => row.competitionId === "mlb").status = "unsupported";
  await collectSportsFixtureCrosscheck(body, { now, collect: async () => { throw new Error("must not collect"); } });
});

test("an invalid accepted envelope fails before any comparison GET", async () => {
  const body = snapshot(); body.complete = false;
  let calls = 0;
  await assert.rejects(() => collectSportsFixtureCrosscheck(body, { now, collect: async () => { calls++; return collection(); } }));
  assert.equal(calls, 0);
});

test("a covered but descriptor-mismatched empty lane is an invalid contract, not omission evidence", async () => {
  const body = snapshot(); body.coverage[0].sport = "hockey"; body.coverage[0].competitionName = "Different hockey competition";
  let calls = 0;
  await assert.rejects(() => collectSportsFixtureCrosscheck(body, { now, collect: async () => { calls++; return collection([fixture()]); } }));
  assert.equal(calls, 0);
  await assert.rejects(() => reconcile(body, { mlb: collection([fixture()]) }));
});

test("the actual MLB collector validates totals and pending time/team data before reconciliation", async () => {
  const valid = await collectSportsFixtureCrosscheck(snapshot(), { now, fetchImpl: async (_, init) => {
    assert.equal(init.redirect, "error"); assert.equal(new Headers(init.headers).get("x-auth-token"), null);
    return Response.json(mlbPayload());
  } });
  assert.equal(valid.findings[0].code, "same-upstream-current-omission");
  const incomplete = await collectSportsFixtureCrosscheck(snapshot(), { now,
    fetchImpl: async () => Response.json({ ...mlbPayload(), totalGames: 2, totalItems: 2 }) });
  assert.equal(incomplete.findings[0].code, "comparison-source-unavailable");
  const pendingRow = mlbGame(); pendingRow.status.startTimeTBD = true;
  const pending = await collectSportsFixtureCrosscheck(snapshot(), { now, fetchImpl: async () => Response.json(mlbPayload([pendingRow])) });
  assert.equal(pending.lanes[0].pendingFixtureCount, 1);
  assert.equal(pending.lanes[0].expectedCount, 0);
  assert.deepEqual(pending.findings, []);
});

test("the primary collector rejects oversized bodies, redirect responses and unrecognized empty HTML", async () => {
  const responses = [() => new Response("x".repeat(2_000_001), { headers: { "content-type": "application/json" } }),
    () => new Response("{}", { status: 302, headers: { "content-type": "application/json", location: "https://example.com" } }),
    () => new Response("<html>empty</html>", { headers: { "content-type": "text/html" } })];
  for (const response of responses) {
    const report = await collectSportsFixtureCrosscheck(snapshot(), { now, fetchImpl: async () => response() });
    assert.deepEqual(report.findings, [{ code: "comparison-source-unavailable", competitionId: "mlb", actionable: false }]);
  }
});

test("HTTP Age at thirty minutes rejects cached comparison evidence without an omission", async () => {
  for (const age of ["1800", "not-a-number"]) {
    const report = await collectSportsFixtureCrosscheck(snapshot(), { now,
      fetchImpl: async () => Response.json(mlbPayload(), { headers: { age } }) });
    assert.deepEqual(report.findings, [{ code: "comparison-receipt-stale", competitionId: "mlb", actionable: false }]);
    assert.equal(report.lanes[0].omittedCount, 0);
  }
});

test("a fresh HTTP receipt of a prior-year WNBA season cannot establish a successful empty comparison", async () => {
  const staleSeason = { meta: { time: iso(now) }, leagueSchedule: { leagueId: "10", seasonYear: "2025",
    gameDates: [{ games: [{ gameId: "100", gameDateTimeUTC: "2025-09-30T17:00:00Z", gameStatus: 3,
      gameStatusText: "Final", postponedStatus: "N", ifNecessary: false,
      homeTeam: { teamId: 1, teamCity: "Alpha", teamName: "Club" }, awayTeam: { teamId: 2, teamCity: "Beta", teamName: "Club" } }] }] } };
  const report = await collectSportsFixtureCrosscheck(snapshot({ wnba: [] }), { now, fetchImpl: async () => Response.json(staleSeason,
    { headers: { "Last-Modified": new Date(now).toUTCString() } }) });
  assert.equal(report.lanes[0].status, "comparison-unavailable");
  assert.deepEqual(report.findings, [{ code: "comparison-source-unavailable", competitionId: "wnba", actionable: false }]);
});

test("the complete three-source collection shares four GETs, fixed origins and an outer abort signal", async () => {
  const calls = [];
  const report = await collectSportsFixtureCrosscheck(snapshot({ mlb: [], nhl: [], wnba: [] }), { now,
    collect: async (descriptor, _, env, fetchImpl) => {
      assert.deepEqual(env, {});
      await fetchImpl(url(descriptor.id));
      if (descriptor.id === "nhl") await fetchImpl(`${descriptor.sourceURL}/2026-10-06`);
      return collection();
    }, fetchImpl: async (requestURL, init) => { calls.push({ url: String(requestURL), init }); return Response.json({}); } });
  assert.equal(calls.length, 4);
  assert.ok(calls.every(({ init }) => init.redirect === "error" && init.signal.aborted));
  assert.deepEqual(report.findings, []);
});

test("extra GETs and off-origin URLs are refused without exposing upstream exception text", async () => {
  let calls = 0;
  const offOrigin = await collectSportsFixtureCrosscheck(snapshot(), { now, collect: async (descriptor, _, __, fetchImpl) => {
    await fetchImpl("https://example.com/unsafe-private"); return collection([fixture()]);
  }, fetchImpl: async () => { calls++; throw new Error("private error"); } });
  assert.equal(calls, 0);
  assert.equal(offOrigin.findings[0].code, "comparison-source-unavailable");
  assert.equal(JSON.stringify(offOrigin).includes("unsafe-private"), false);
  const excessive = await collectSportsFixtureCrosscheck(snapshot(), { now, collect: async (descriptor, _, __, fetchImpl) => {
    for (let index = 0; index < 5; index++) await fetchImpl(url(descriptor.id)); return collection();
  }, fetchImpl: async () => { calls++; return Response.json({}); } });
  assert.equal(calls, 4);
  assert.equal(excessive.findings[0].actionable, false);
});

test("the whole collection deadline aborts all parallel sources even when fetch ignores cancellation", async () => {
  const signals = [];
  const started = performance.now();
  const report = await collectSportsFixtureCrosscheck(snapshot({ mlb: [], nhl: [], wnba: [] }), { now, timeoutMs: 20,
    collect: async (descriptor, _, __, fetchImpl) => { await fetchImpl(url(descriptor.id)); return collection([fixture(descriptor.id)]); },
    fetchImpl: async (_, init) => { signals.push(init.signal); return new Promise(() => {}); } });
  assert.ok(performance.now() - started < 250);
  assert.equal(signals.length, 3);
  assert.ok(signals.every((signal) => signal.aborted));
  assert.equal(report.findings.length, 3);
  assert.ok(report.findings.every((finding) => finding.code === "comparison-source-unavailable" && finding.actionable === false));
});

test("a response body ignoring fetch cancellation is cancelled by the shared collection deadline", async () => {
  let cancelled = false;
  const started = performance.now();
  const report = await collectSportsFixtureCrosscheck(snapshot(), { now, timeoutMs: 20, fetchImpl: async () =>
    new Response(new ReadableStream({ pull() { return new Promise(() => {}); }, cancel() { cancelled = true; } }),
      { headers: { "content-type": "application/json" } }) });
  assert.ok(performance.now() - started < 250);
  assert.equal(cancelled, true);
  assert.deepEqual(report.findings, [{ code: "comparison-source-unavailable", competitionId: "mlb", actionable: false }]);
});

test("a timed-out collector completing later cannot overwrite the returned failure", async () => {
  let complete;
  const task = collectSportsFixtureCrosscheck(snapshot(), { now, timeoutMs: 10, collect: () => new Promise((resolve) => { complete = resolve; }) });
  const report = await task;
  complete(collection([fixture()]));
  await Promise.resolve(); await Promise.resolve();
  assert.deepEqual(report.findings, [{ code: "comparison-source-unavailable", competitionId: "mlb", actionable: false }]);
});
