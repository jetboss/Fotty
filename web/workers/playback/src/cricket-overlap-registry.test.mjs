import assert from "node:assert/strict";
import test from "node:test";
import { collectICC, refreshCricketState } from "./cricket-fixture-registry.mjs";
import { loadBroadcastRegistryFixtures } from "./index.js";
import { associateBroadcasts, normalizeBroadcastCollection } from "./broadcast-registry-policy.mjs";

const now = new Date("2026-11-04T02:45:00Z");
const odi = { match_id: "271651", league_id: "1", match_date_gmt: "11/4/2026", match_time_gmt: "02:00",
  teama_id: "5", teama: "New Zealand", teamb_id: "4", teamb: "India",
  series_name: "India in New Zealand, 5 ODI Series, 2026", match_type: "ODI",
  match_number: "1st ODI", match_ordinal: "1", live: true, upcoming: false, recent: false };
const overlap = { ...odi, match_id: "269792", teama_id: "7", teama: "South Africa", teamb_id: "1", teamb: "Australia",
  series_name: "Australia in South Africa, 3 Test Series, 2026", match_type: "Test", match_number: "2nd Test", match_ordinal: "2",
  match_date_gmt: "10/27/2026", match_time_gmt: "08:30", end_match_date_gmt: "10/31/2026", end_match_time_gmt: "13:16",
  live: false, recent: true, is_match_ended: true };
const wi = { ...overlap, match_id: "274665", teama_id: "2", teama: "Bangladesh", teamb_id: "9", teamb: "West Indies",
  series_name: "West Indies in Bangladesh, 2 Test Series, 2026", match_date_gmt: "10/28/2026", match_time_gmt: "03:30",
  end_match_date_gmt: "10/31/2026", end_match_time_gmt: "09:54" };
const collect = (rows, requests = []) => collectICC(now, async (url) => {
  requests.push(new URL(url));
  return Response.json({ data: { matches: rows }, meta: { app_status_code: 1, pagination: true,
    count: rows.length, timestamp: { utc_time: "11/4/2026 2:45:00 AM" } } });
});

test("ICC overlap response keeps original Test starts and terminal facts without blocking a live ODI", async () => {
  const requests = [], result = await collect([overlap, wi, odi], requests);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].searchParams.get("from_date"), "20261029");
  assert.equal(result.fixtures.length, 3);
  assert.equal(result.fixtures[0].start, "2026-10-27T08:30:00.000Z");
  assert.equal(result.fixtures[0].status, "finished");
  assert.equal(result.fixtures[1].status, "finished");
  assert.equal(result.fixtures[2].status, "live");
  assert.equal(result.fixtures[2].matchOrdinal, 1);
});

test("only explicit bounded Test intervals may overlap the lower window boundary", async () => {
  for (const changes of [
    { match_type: "ODI" }, { match_type: "T20" }, { match_type: "unknown" },
    { end_match_date_gmt: undefined }, { end_match_time_gmt: undefined },
    { end_match_date_gmt: "10/26/2026" }, { end_match_date_gmt: "10/28/2026" },
    { end_match_date_gmt: "11/4/2026" }, { end_match_date_gmt: "10/32/2026" },
    { end_match_time_gmt: "25:00" },
    { match_date_gmt: "11/12/2026", end_match_date_gmt: "11/16/2026" },
  ]) await assert.rejects(collect([{ ...overlap, ...changes }, odi]), /ICC (fixture outside requested window|kickoff|date)/,
    JSON.stringify(changes));
  const youth = await collect([{ ...overlap, league_id: "9", match_type: "Youth Test" }, odi]);
  assert.match(youth.fixtures[0].home.name, /U19/);
  const boundary = await collect([{ ...overlap, end_match_date_gmt: "10/29/2026", end_match_time_gmt: "00:00" }, odi]);
  assert.equal(boundary.fixtures.length, 2);
});

test("invalid overlap retains accepted snapshots and exposes a finite window/date failure", async () => {
  const first = await refreshCricketState(null, now, () => collect([odi]));
  for (const [change, code] of [[{ end_match_date_gmt: "10/28/2026" }, "source-window-conflict"],
    [{ end_match_time_gmt: "bad" }, "source-date-invalid"]]) {
    const failed = await refreshCricketState(first, now, () => collect([{ ...overlap, ...change }, odi]));
    assert.equal(failed.failure.code, code);
    assert.equal(failed.snapshot.sourceStatus, "last-known-good");
    assert.equal(failed.snapshot.fixtures[0].source.observedAt, first.snapshot.fixtures[0].source.observedAt);
    assert.equal(failed.snapshot.fixtures[0].status, "live");
  }
});

test("collector recovery reaches the real Worker fixture loader and exact CS early-coverage association", async () => {
  const first = await refreshCricketState(null, new Date("2026-11-03T02:45:00Z"), async () => {
    const result = await collect([odi]);
    return { ...result, observedAt: "2026-11-03T02:45:00.000Z", fixtures: result.fixtures.map(f => ({ ...f,
      status: "scheduled", source: { ...f.source, observedAt: "2026-11-03T02:45:00.000Z" } })) };
  });
  const recovered = await refreshCricketState(first, now, () => collect([overlap, wi, odi]));
  assert.equal(recovered.cohorts.icc.consecutiveFailures, 0);
  const env = { CRICKET_FIXTURES: { idFromName: () => "test", get: () => ({ fetch: async () => Response.json(recovered.snapshot) }) } };
  const { fixtures, siblings } = await loadBroadcastRegistryFixtures(env, { includeAmbiguity: true });
  assert.equal(fixtures.length, 1, "Terminal Tests must not become Watch targets");
  assert.equal(fixtures[0].status, "live");
  const providerCode = "communitysports";
  const source = await normalizeBroadcastCollection(providerCode, { providerCode, complete: true,
    observedAt: now.toISOString(), scopes: [{ scope: "cricket", status: "available", complete: true }],
    broadcasts: [{ providerEventID: "nuvio_sport_reviewed_test", streamID: "nuvio_sport_reviewed_test", resourceType: "tv",
      scope: "cricket", kind: "event", sport: "cricket", title: "New Zealand vs India", participants: ["New Zealand", "India"],
      start: "2026-11-04T01:30:00.000Z", format: "ODI", matchOrdinal: 1, verification: "dated", issues: [],
      observedAt: now.toISOString(), expiresAt: "2026-11-04T03:45:00.000Z" }] }, now);
  const join = (rows) => associateBroadcasts({ fixtures: rows, ambiguityFixtures: siblings,
    broadcasts: source.broadcasts, providers: source.scopes, now });
  const links = join(fixtures);
  assert.equal(links.length, 1);
  assert.equal(links[0].state, "listed");
  assert.equal(links[0].startRelation, "early-coverage");
  assert.equal(links[0].fixtureFingerprint.start, "2026-11-04T02:00:00.000Z");
  assert.equal(join(fixtures.map(f => ({ ...f, observedAt: "2026-11-03T02:45:00Z" }))).length, 0,
    "Recovery cannot be simulated by retaining stale official facts");
  assert.equal(join(fixtures.map(f => ({ ...f, participants: ["New Zealand Women", "India Women"] }))).length, 0);
  const conflict = join(fixtures.map(f => ({ ...f, matchOrdinal: 2 })))[0];
  assert.equal(conflict.state, "conflicting");
  assert.equal(conflict.reason, "ordinal-conflict");
  assert.equal(join(fixtures.map(f => ({ ...f, matchOrdinal: undefined })))[0].state, "listed",
    "Missing optional ordinal is not an invented conflict for exact dated events");
});
