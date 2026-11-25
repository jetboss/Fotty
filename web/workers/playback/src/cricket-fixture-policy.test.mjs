import assert from "node:assert/strict";
import test from "node:test";
import worker from "./index.js";
import { admitICC, admitICCIsolated, cricketWindow, iccScheduleURL, iccSourceTime, nextCricketRefresh, normalizeICC, parseICCPage, validateCricketSnapshot } from "./cricket-fixture-policy.mjs";
import { collectICC, CricketFixtureRegistry, refreshCricketState } from "./cricket-fixture-registry.mjs";
import { boundedCricketContexts, normalizeICCContext, validCricketContext } from "./cricket-context-policy.mjs";
import { auditCricketSnapshot } from "../../../../tools/audit-cricket-fixtures-policy.mjs";
import cplFallback from "../../../public/data/cpl-2026-fixtures.json" with { type: "json" };

const now = new Date("2026-09-30T16:00:00Z");
const row = (overrides = {}) => ({ match_id: "270271", league_id: "1", match_date_gmt: "9/30/2026", match_time_gmt: "08:30",
  teama_id: "4", teama: "India", teamb_id: "9", teamb: "West Indies", series_name: "West Indies in India, 3 ODI Series, 2026",
  match_type: "ODI", live: true, upcoming: false, recent: false, is_deleted: false, ...overrides });
const payload = (rows = [row()], overrides = {}) => ({ data: { matches: rows }, meta: { app_status_code: 1,
  pagination: true, count: rows.length, timestamp: { utc_time: "9/30/2026 4:00:00 PM" }, ...overrides } });
const normalized = (rows = [row()]) => normalizeICC([parseICCPage(payload(rows), now)], now);
const cohortCollection = () => normalized([row(), row({ match_id: "270272", teamb: "England", teamb_id: "1" })]);
const withReceipt = (collection, receipt) => ({ ...collection, observedAt: receipt.toISOString(),
  fixtures: collection.fixtures.map((fixture) => ({ ...fixture, source: { ...fixture.source, observedAt: receipt.toISOString() } })) });

test("optional CA cohort is isolated, opt-in only, and refreshes despite base backoff", async () => {
  const clock = new Date(), future = new Date(+clock + 60_000).toISOString();
  const base = await refreshCricketState(null, now, async () => normalized());
  base.nextAttemptAt = future;
  const storage = new Map([["cricket-registry-v1", base]]);
  const pending = [];
  const state = { storage: { get: async (key) => storage.get(key), put: async (key, value) => storage.set(key, value) },
    waitUntil: (p) => pending.push(p) };
  let caCalls = 0, iccCalls = 0;
  const options = { collectCA: async () => { caCalls++; return { observedAt: clock.toISOString(), fixtures: [] }; },
    collectICC: async () => { iccCalls++; throw Error("upstream"); } };
  const disabled = new CricketFixtureRegistry(state, {}, options);
  await disabled.fetch(new Request("https://internal/refresh", { method: "POST" }));
  assert.equal(caCalls, 0); assert.equal(storage.size, 1);
  const registry = new CricketFixtureRegistry(state, { CRICKET_WBBL_ENABLED: "true" }, options);
  await registry.fetch(new Request("https://internal/refresh", { method: "POST" }));
  assert.equal(caCalls, 1); assert.equal(iccCalls, 0); assert.equal(storage.get("cricket-registry-v1"), base);
  const response = await (await registry.fetch(new Request("https://internal/fixtures"))).json();
  assert.equal(response.coverage.find((c) => c.competitionId === "wbbl").status, "covered");
  assert.deepEqual(response.fixtures, base.snapshot.fixtures);
  await registry.fetch(new Request("https://internal/refresh", { method: "POST" }));
  assert.equal(caCalls, 1, "Concurrent cron/read paths share the persisted backoff");
  const oldCA = storage.get("cricket-australia-wbbl-v1"); oldCA.nextAttemptAt = "1970-01-01T00:00:00Z";
  options.collectCA = async () => { throw Error("private upstream URL"); };
  await registry.fetch(new Request("https://internal/refresh", { method: "POST" }));
  const failed = await (await registry.fetch(new Request("https://internal/fixtures"))).json();
  assert.equal(failed.coverage.find((c) => c.competitionId === "wbbl").status, "unavailable");
  assert.deepEqual(failed.fixtures, base.snapshot.fixtures);
  assert.equal(storage.get("cricket-registry-v1"), base);
  const restored = await (await disabled.fetch(new Request("https://internal/fixtures"))).json();
  assert.equal(restored.coverage.length, 3, "Flag rollback omits domestic projection without erasing either storage key");
});
const marked = (fixtures, verification) => fixtures.map((fixture) => ({ ...fixture, source: { ...fixture.source, verification } }));
const activeSeason = new Date("2026-09-20T16:00:00Z");
const recoveredCPL = (receipt) => Response.json({ ...cplFallback, checkedAt: receipt.toISOString(), sourceStatus: "verified" });

test("ICC limited-overs ordinal comes from agreeing explicit fields even without score context", () => {
  for (const [match_type, match_number, match_ordinal, expected] of [
    ["ODI", "5th ODI", "5", 5], ["T20", "3rd T20I", "3", 3], ["T20I", "1st T20I", 1, 1],
    ["T20", "21st T20", "21", 21], ["Youth ODI", "1st Youth ODI", "1", 1],
    ["Youth T20I", "2nd Youth T20I", "2", 2], ["ODI", "11th ODI", "11", 11],
  ]) {
    const fixture = normalized([row({ match_type, match_number, match_ordinal })]).fixtures[0];
    assert.equal(fixture.matchOrdinal, expected);
    assert.equal(fixture.context, undefined, "Missing scores do not erase an explicit fixture ordinal");
    assert.equal(fixture.start, "2026-09-30T08:30:00.000Z");
  }
});

test("malformed, contradictory or series-count ordinals stay absent without erasing the official fixture", () => {
  for (const changes of [
    {}, { match_ordinal: "5" }, { match_number: "5th ODI" }, { match_ordinal: "4", match_number: "5th ODI" },
    { match_ordinal: "5", match_number: "5st ODI" }, { match_ordinal: "11", match_number: "11st ODI" },
    { match_ordinal: "05", match_number: "5th ODI" }, { match_ordinal: 0, match_number: "0th ODI" },
    { match_ordinal: 100, match_number: "100th ODI" }, { match_ordinal: 5.5, match_number: "5th ODI" },
    { match_ordinal: null, match_number: "5th ODI" }, { match_ordinal: "5", match_number: "5 ODI Series" },
    { match_ordinal: "5", match_number: "5th T20I" }, { match_ordinal: "5", match_number: "5th ODI<script>" },
    { match_ordinal: "5", match_number: "5th Youth ODI" },
    { match_type: "Youth ODI", match_ordinal: "5", match_number: "5th ODI" },
    { match_type: "Test", match_ordinal: "5", match_number: "5th Test" },
  ]) {
    const result = normalized([row({ ...changes, series_name: "Ireland in Namibia, 5 ODI Series, 2026" })]);
    assert.equal(result.fixtures.length, 1);
    assert.equal(result.fixtures[0].matchOrdinal, undefined, JSON.stringify(changes));
    assert.equal(result.fixtures[0].status, "live");
  }
});

test("a changed explicit limited-overs ordinal is isolated while fresh missing ordinal never borrows old authority", () => {
  const initial = normalized([row({ match_ordinal: "5", match_number: "5th ODI" })]);
  const previous = admitICC(initial, [], now).fixtures;
  const changed = normalized([row({ match_ordinal: "4", match_number: "4th ODI" }),
    row({ match_id: "999999", teamb: "England", teamb_id: "1" })]);
  assert.throws(() => admitICC(changed, previous, now), /ICC ordinal conflict/u);
  const isolated = admitICCIsolated(changed, previous, now);
  assert.equal(isolated.fixtures.find((f) => f.id === previous[0].id).matchOrdinal, 5);
  assert.equal(isolated.fixtures.find((f) => f.id === previous[0].id).source.verification, "held");
  assert.equal(isolated.fixtures.find((f) => f.id === "icc:999999").source.verification, "verified");
  const missing = admitICC(normalized([row()]), previous, now).fixtures[0];
  assert.equal(missing.matchOrdinal, undefined);
  assert.equal(missing.id, previous[0].id);
  assert.equal(admitICC(initial, admitICC(normalized(), [], now).fixtures, now).fixtures[0].matchOrdinal, 5,
    "An older accepted snapshot without the additive field can acquire current explicit authority");
});

test("public cricket snapshots bound optional limited-overs ordinal without changing Test context", () => {
  const fixture = admitICC(normalized([row({ match_ordinal: "5", match_number: "5th ODI" })]), [], now).fixtures[0];
  const snapshot = { schemaVersion: 1, complete: true, fixtures: [fixture], coverage: [
    { competitionId: "cpl", status: "offseason", fixtureCount: 0 },
    { competitionId: "west-indies", status: "covered", fixtureCount: 1 },
    { competitionId: "icc", status: "covered", fixtureCount: 0 },
  ] };
  assert.equal(validateCricketSnapshot(snapshot).fixtures[0].matchOrdinal, 5);
  for (const matchOrdinal of [null, "5", 0, -1, 100, 5.5])
    assert.throws(() => validateCricketSnapshot({ ...snapshot, fixtures: [{ ...fixture, matchOrdinal }] }), /Invalid cricket fixture/u);
  assert.throws(() => validateCricketSnapshot({ ...snapshot, fixtures: [{ ...fixture, format: "Test" }] }), /Invalid cricket fixture/u,
    "Existing Test ordinals remain in their explicit score context, not this limited-overs field");
});
const reviewNow = new Date("2026-10-01T19:00:00.000Z");
const triSeriesRows = (corrected) => [
  { match_id: "275298", match_date_gmt: "10/4/2026", match_time_gmt: corrected ? "02:00" : "02:30",
    teama_id: "1810", teama: "Indonesia", teamb_id: "1754", teamb: "Samoa" },
  { match_id: "275299", match_date_gmt: "10/6/2026", match_time_gmt: corrected ? "02:30" : "02:00",
    teama_id: "1638", teama: "Malaysia", teamb_id: "1810", teamb: "Indonesia" },
  { match_id: "275300", match_date_gmt: "10/7/2026", match_time_gmt: corrected ? "02:00" : "02:30",
    teama_id: "1638", teama: "Malaysia", teamb_id: "1754", teamb: "Samoa" },
].map((fixture) => row({ ...fixture, league_id: "10", match_type: "T20I", series_id: "15827",
  series_name: "Women's T20I Tri-Series in Malaysia, 2026", live: false, upcoming: true, is_revised: false }));
const triSeriesCollection = (corrected) => normalizeICC([parseICCPage(payload(triSeriesRows(corrected),
  { timestamp: { utc_time: "10/1/2026 7:00:00 PM" } }), reviewNow)], reviewNow);
const priorTriSeries = () => admitICC(withReceipt(triSeriesCollection(false), new Date("2026-10-01T13:00:00Z")),
  [], new Date("2026-10-01T13:00:00Z")).fixtures;
function octoberConflictScenario() {
  const initialAt = new Date("2026-10-03T04:51:20.000Z");
  const attemptedAt = new Date("2026-10-06T15:35:00.000Z");
  const rows = [
    triSeriesRows(true)[2],
    row({ match_id: "273760", teama: "Oman", teama_id: "25", teamb: "Canada", teamb_id: "12",
      match_date_gmt: "10/9/2026", match_time_gmt: "06:00", live: false, upcoming: true }),
    row({ match_id: "274655", teama: "Afghanistan", teama_id: "1188", teamb: "Bangladesh", teamb_id: "2",
      match_date_gmt: "10/9/2026", match_time_gmt: "05:30", match_type: "Test", live: false, upcoming: true }),
    row({ match_id: "270987", league_id: "9", teama: "India U19", teama_id: "1120", teamb: "Australia U19", teamb_id: "1121",
      match_date_gmt: "10/5/2026", match_time_gmt: "04:00", match_type: "Test", live: false, upcoming: true }),
    row({ match_id: "274310", teama: "Pakistan", teama_id: "6", teamb: "India", teamb_id: "4",
      match_date_gmt: "10/3/2026", match_time_gmt: "04:30", match_type: "T20" }),
    row({ match_id: "270273", match_date_gmt: "10/6/2026", match_time_gmt: "13:30", match_type: "T20", live: false, upcoming: true }),
  ];
  const initial = normalizeICC([parseICCPage(payload(rows,
    { timestamp: { utc_time: "10/3/2026 4:51:20 AM" } }), initialAt)], initialAt);
  const candidate = withReceipt({ ...initial, fixtures: initial.fixtures.filter((fixture) => fixture.id !== "icc:275300")
    .map((fixture) => {
      if (fixture.id === "icc:273760") return { ...fixture, start: "2026-10-09T05:00:00.000Z", revised: false };
      if (fixture.id === "icc:274655") return { ...fixture, start: "2026-10-09T06:00:00.000Z", revised: false };
      if (["icc:270987", "icc:270273"].includes(fixture.id)) return { ...fixture, status: "live" };
      if (fixture.id === "icc:274310") return { ...fixture, status: "finished" };
      return fixture;
    }) }, attemptedAt);
  return { initialAt, attemptedAt, initial, candidate };
}
async function nearBoundScenario() {
  const templates = cohortCollection();
  const makeRows = (id, count, identity) => Array.from({ length: count }, (_, offset) => {
    const template = templates.fixtures.find((fixture) => fixture.competitionId === id);
    return { ...template, id: `icc:${identity + offset}`, status: "scheduled",
      start: new Date(Date.parse("2026-09-21T08:30:00Z") + offset * 60_000).toISOString(),
      source: { ...template.source, url: `https://www.icc-cricket.com/matches/${identity + offset}` } };
  });
  const initial = withReceipt({ ...templates, fixtures: makeRows("icc", 300, 300000) }, activeSeason);
  const noCPL = async () => { throw new Error("CPL unavailable"); };
  const first = await refreshCricketState(null, activeSeason, async () => initial, noCPL);
  const partialAt = new Date(activeSeason.getTime() + 5 * 60_000);
  const candidate = withReceipt({ ...templates, fixtures: [...initial.fixtures.slice(0, 210),
    ...makeRows("west-indies", 90, 400000)] }, partialAt);
  candidate.fixtures[0].start = "2026-09-21T09:00:00.000Z";
  const previous = await refreshCricketState(first, partialAt, async () => candidate, noCPL);
  assert.equal(previous.snapshot.fixtures.length, 390);
  assert.equal(previous.snapshot.sourceStatus, "partial");
  assert.equal(previous.snapshot.coverage.find((coverage) => coverage.competitionId === "cpl").fixtureCount, 0);
  return { previous, candidate, attemptedAt: new Date(partialAt.getTime() + 5 * 60_000) };
}

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

test("isolated admission retains only conflicts without guessing the status of absent fixtures", () => {
  const { initialAt, attemptedAt, initial, candidate } = octoberConflictScenario();
  const old = admitICC(initial, [], initialAt).fixtures;
  const beforeCandidate = structuredClone(candidate);
  const beforeOld = structuredClone(old);
  assert.throws(() => admitICC(candidate, old, attemptedAt), /disappeared/);
  const admitted = admitICCIsolated(candidate, old, attemptedAt);
  for (const id of ["icc:275300", "icc:273760", "icc:274655"]) {
    assert.deepEqual(admitted.fixtures.find((fixture) => fixture.id === id), marked(old.filter((fixture) => fixture.id === id), "held")[0]);
  }
  for (const [id, status] of [["icc:270987", "live"], ["icc:274310", "finished"], ["icc:270273", "live"]]) {
    const fixture = admitted.fixtures.find((item) => item.id === id);
    assert.equal(fixture.status, status);
    assert.equal(fixture.source.verification, "verified");
    assert.equal(fixture.source.observedAt, attemptedAt.toISOString());
  }
  assert.equal(admitted.fixtures.length, old.length);
  assert.deepEqual(candidate, beforeCandidate);
  assert.deepEqual(old, beforeOld);
  assert.ok(admitted.fixtures.every((fixture) => !Object.hasOwn(fixture, "revised") && !Object.hasOwn(fixture, "publisherSeriesId")));

  const missing = old.find((fixture) => fixture.id === "icc:275300");
  for (const previous of [
    { ...missing, status: "finished" },
    { ...missing, start: "2026-09-29T02:00:00.000Z" },
    { ...missing, start: "2026-10-09T02:00:00.000Z" },
  ]) {
    const result = admitICCIsolated({ ...candidate, fixtures: [] }, [previous], attemptedAt);
    assert.equal(result.fixtures.length, 0, "Absent rows are retained only when strict admission's active disappearance guard applies");
    assert.equal(result.failure, undefined);
  }
});

test("isolated admission refuses a regressed collection watermark before any record can advance", () => {
  const { initialAt, attemptedAt, initial, candidate } = octoberConflictScenario();
  const old = admitICC(initial, [], initialAt).fixtures;
  const mixed = admitICCIsolated(candidate, old, attemptedAt);
  const regressed = withReceipt(candidate, new Date(attemptedAt.getTime() - 1));
  assert.throws(() => admitICCIsolated(regressed, mixed.fixtures, attemptedAt), /receipt regressed/);
});

test("exact publisher-confirmed tri-series transitions admit without fabricating revision flags or public evidence fields", () => {
  const candidate = triSeriesCollection(true);
  const before = structuredClone(candidate);
  const accepted = admitICC(candidate, priorTriSeries(), reviewNow);
  assert.deepEqual(accepted.fixtures.map(({ id, start }) => ({ id, start })), [
    { id: "icc:275298", start: "2026-10-04T02:00:00.000Z" },
    { id: "icc:275299", start: "2026-10-06T02:30:00.000Z" },
    { id: "icc:275300", start: "2026-10-07T02:00:00.000Z" },
  ]);
  assert.deepEqual(candidate, before, "Admission cannot manufacture a publisher revision or mutate collection evidence");
  assert.ok(candidate.fixtures.every((fixture) => fixture.revised === false && fixture.publisherSeriesId === "15827"));
  assert.ok(accepted.fixtures.every((fixture) => !Object.hasOwn(fixture, "revised")
    && !Object.hasOwn(fixture, "publisherSeriesId")));
});

test("reviewed correction cannot authorize a different identity, competition, format, status, source or time tuple", () => {
  const mutations = [
    (current) => { current.id = "icc:999999"; },
    (current, old) => { old.start = "2026-10-04T03:00:00.000Z"; },
    (current) => { current.start = "2026-10-04T01:30:00.000Z"; },
    (current) => { current.publisherSeriesId = "99999"; },
    (current) => { delete current.publisherSeriesId; },
    (current) => { current.home.id = "icc:1:1810"; },
    (current) => { current.home.name = "Indonesia"; },
    (current, old) => { old.away.name = "Another Samoa squad"; },
    (current) => { current.competitionId = "west-indies"; },
    (current, old) => { old.competitionName = "Another tournament"; },
    (current) => { current.competitionName = "Another tournament"; },
    (current) => { current.format = "ODI"; },
    (current, old) => { old.format = "ODI"; },
    (current) => { current.status = "live"; },
    (current, old) => { old.status = "finished"; },
    (current) => { current.source.name = "Another publisher"; },
    (current) => { current.source.url = "https://another-publisher.invalid/matches/275298"; },
    (current, old) => { old.source.url = "https://another-publisher.invalid/matches/275298"; },
    (current) => { current.source.observedAt = "2026-10-01T18:55:00.000Z"; },
  ];
  for (const mutate of mutations) {
    const candidate = triSeriesCollection(true);
    const previous = priorTriSeries();
    mutate(candidate.fixtures[0], previous[0]);
    // An unrelated ID must not borrow a reviewed transition, even if it has
    // the same old start and participant tuple.
    if (candidate.fixtures[0].id === "icc:999999") {
      previous[0].id = "icc:999999";
      previous[0].source.url = "https://www.icc-cricket.com/matches/999999";
    }
    assert.throws(() => admitICC(candidate, previous, reviewNow), /ICC/);
  }
});

test("reviewed corrections require post-verification fresh receipts and expire before either kickoff", () => {
  for (const receipt of ["2026-10-01T18:38:42.868Z", "2026-10-01T19:00:01.000Z", "2026-10-01T12:59:59.000Z"]) {
    assert.throws(() => admitICC(withReceipt(triSeriesCollection(true), new Date(receipt)), priorTriSeries(), reviewNow), /kickoff/);
  }
  for (let index = 0; index < 3; index++) {
    const current = triSeriesCollection(true).fixtures[index];
    const old = priorTriSeries()[index];
    const boundary = Math.min(Date.parse(current.start), Date.parse(old.start));
    const single = { ...triSeriesCollection(true), fixtures: [current] };
    const beforeKickoff = new Date(boundary - 1);
    assert.doesNotThrow(() => admitICC(withReceipt(single, beforeKickoff), [old], beforeKickoff));
    const atKickoff = new Date(boundary);
    assert.throws(() => admitICC(withReceipt(single, atKickoff), [old], atKickoff), /kickoff/);
  }
  const staleAt = new Date(reviewNow.getTime() + 6 * 3_600_000 + 1);
  assert.throws(() => admitICC(triSeriesCollection(true), priorTriSeries(), staleAt), /kickoff/);
  assert.doesNotThrow(() => admitICC(withReceipt(triSeriesCollection(true), new Date("2026-10-01T18:38:42.869Z")),
    priorTriSeries(), reviewNow));
});

test("correction receipts never synthesize cold fixtures, reverse a transition or clear another conflict", () => {
  const old = priorTriSeries();
  assert.deepEqual(admitICC(triSeriesCollection(false), [], reviewNow).fixtures.map((fixture) => fixture.start),
    old.map((fixture) => fixture.start), "A reviewed transition is not a fallback schedule or source rewrite");
  const accepted = admitICC(triSeriesCollection(true), old, reviewNow);
  const later = new Date(reviewNow.getTime() + 5 * 60_000);
  assert.throws(() => admitICC(withReceipt(triSeriesCollection(false), later), accepted.fixtures, later), /kickoff/);
  const anotherChange = withReceipt(triSeriesCollection(true), later);
  anotherChange.fixtures[1].start = "2026-10-06T03:00:00.000Z";
  assert.throws(() => admitICC(anotherChange, old, later), /kickoff/);
  const explicitLaterRevision = withReceipt(triSeriesCollection(false), later);
  explicitLaterRevision.fixtures.forEach((fixture) => { fixture.revised = true; });
  assert.doesNotThrow(() => admitICC(explicitLaterRevision, accepted.fixtures, later),
    "A genuine later publisher-flagged reschedule retains the existing admission contract");
});

test("reviewed recovery clears persisted ICC failure only when the complete cohort passes", async () => {
  const earlier = new Date("2026-10-01T13:00:00.000Z");
  const first = await refreshCricketState(null, earlier, async () => withReceipt(triSeriesCollection(false), earlier));
  const beforeReview = new Date("2026-10-01T18:30:00.000Z");
  const held = await refreshCricketState(first, beforeReview, async () => withReceipt(triSeriesCollection(true), beforeReview));
  assert.equal(held.cohorts.icc.consecutiveFailures, 1);
  assert.deepEqual(held.snapshot.fixtures, marked(first.snapshot.fixtures, "held"));
  const recovered = await refreshCricketState(held, reviewNow, async () => triSeriesCollection(true));
  assert.equal(recovered.snapshot.sourceStatus, "verified");
  assert.equal(recovered.consecutiveFailures, 0);
  assert.equal(recovered.cohorts.icc.consecutiveFailures, 0);
  assert.equal(recovered.cohorts.icc.failure, undefined);
  assert.equal(recovered.lastSuccessAt, reviewNow.toISOString());
  assert.notEqual(recovered.snapshot.revision, first.snapshot.revision);
  assert.ok(recovered.snapshot.fixtures.every((fixture) => fixture.source.observedAt === reviewNow.toISOString()));
  const later = new Date(reviewNow.getTime() + 5 * 60_000);
  const repeated = await refreshCricketState(recovered, later, async () => withReceipt(triSeriesCollection(true), later));
  assert.equal(repeated.snapshot.revision, recovered.snapshot.revision);
  assert.equal(repeated.consecutiveFailures, 0);
  assert.ok(repeated.snapshot.fixtures.every((fixture) => !Object.hasOwn(fixture, "revised")
    && !Object.hasOwn(fixture, "publisherSeriesId")));
  const otherConflict = triSeriesCollection(true);
  otherConflict.fixtures[2].start = "2026-10-07T03:00:00.000Z";
  const stillHeld = await refreshCricketState(held, reviewNow, async () => otherConflict);
  assert.equal(stillHeld.cohorts.icc.consecutiveFailures, 2);
  assert.deepEqual(stillHeld.snapshot.fixtures.find((fixture) => fixture.id === "icc:275300"),
    held.snapshot.fixtures.find((fixture) => fixture.id === "icc:275300"));
  assert.ok(stillHeld.snapshot.fixtures.filter((fixture) => fixture.id !== "icc:275300")
    .every((fixture) => fixture.source.verification === "verified" && fixture.source.observedAt === reviewNow.toISOString()));
  assert.equal(stillHeld.lastSuccessAt, held.lastSuccessAt);
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

test("ICC-only conflict marks retained ICC facts held while fresh West Indies stays legacy-compatible", async () => {
  const first = await refreshCricketState(null, now, async () => cohortCollection());
  const later = new Date(now.getTime() + 5 * 60_000);
  const candidate = withReceipt(cohortCollection(), later);
  candidate.fixtures.find((fixture) => fixture.competitionId === "icc").start = "2026-09-30T09:00:00.000Z";
  const mixed = await refreshCricketState(first, later, async () => candidate);
  const byScope = (state, id) => state.snapshot.fixtures.filter((fixture) => fixture.competitionId === id);
  assert.deepEqual(byScope(mixed, "icc"), marked(byScope(first, "icc"), "held"));
  assert.equal(byScope(mixed, "west-indies")[0].source.observedAt, later.toISOString());
  assert.equal(mixed.snapshot.sourceStatus, "partial");
  assert.equal(mixed.snapshot.schemaVersion, 1);
  assert.equal(mixed.snapshot.complete, true);
  assert.equal(mixed.snapshot.checkedAt, later.toISOString());
  assert.equal(mixed.snapshot.coverage.length, 3);
  assert.equal(new Set(mixed.snapshot.fixtures.map((fixture) => fixture.id)).size, mixed.snapshot.fixtures.length);
  assert.equal(mixed.snapshot.fixtures.some((fixture) => Object.hasOwn(fixture, "revised")), false);
  for (const coverage of mixed.snapshot.coverage) {
    assert.equal(coverage.fixtureCount, byScope(mixed, coverage.competitionId).length);
  }
  assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === "west-indies").status, "covered");
  assert.deepEqual(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === "icc"),
    { ...first.snapshot.coverage.find((coverage) => coverage.competitionId === "icc"), status: "unavailable" });
  assert.deepEqual(mixed.snapshot.sync.cohorts.icc.failure, { stage: "admission", code: "kickoff-unconfirmed" });
  assert.equal(mixed.snapshot.sync.cohorts["west-indies"].consecutiveFailures, 0);
  assert.equal(mixed.snapshot.sync.cohorts.icc.consecutiveFailures, 1);
  assert.equal(mixed.consecutiveFailures, 1);
  assert.equal(mixed.lastSuccessAt, first.lastSuccessAt, "A partial refresh cannot claim full source recovery");
  assert.notEqual(mixed.snapshot.revision, first.snapshot.revision, "Verification changes are content changes even when retained facts are equal");
  assert.equal(Date.parse(mixed.nextAttemptAt) - later.getTime(), 5 * 60_000);
  const retriedAt = new Date(later.getTime() + 5 * 60_000);
  const repeated = await refreshCricketState(mixed, retriedAt, async () => withReceipt(candidate, retriedAt));
  assert.equal(repeated.consecutiveFailures, 2);
  assert.equal(repeated.snapshot.sync.cohorts.icc.consecutiveFailures, 2);
  assert.equal(repeated.snapshot.sync.cohorts["west-indies"].consecutiveFailures, 0);
  const audit = auditCricketSnapshot(repeated.snapshot, { now: retriedAt.getTime(),
    expectedCompetitionIds: ["cpl", "west-indies", "icc"] });
  assert.equal(audit.actionable, true);
  assert.ok(audit.findings.some((finding) => finding.code === "repeated-sync-failure"));
});

test("October 6 conflicts preserve old coverage while healthy ICC live and terminal rows advance", async () => {
  const { initialAt, attemptedAt, initial, candidate } = octoberConflictScenario();
  const first = await refreshCricketState(null, initialAt, async () => initial);
  const mixed = await refreshCricketState(first, attemptedAt, async () => candidate);
  const coverage = mixed.snapshot.coverage.find((item) => item.competitionId === "icc");
  assert.equal(mixed.snapshot.sourceStatus, "partial");
  assert.equal(coverage.status, "unavailable");
  assert.equal(coverage.checkedAt, initialAt.toISOString());
  assert.equal(coverage.fixtureCount, mixed.snapshot.fixtures.filter((fixture) => fixture.competitionId === "icc").length);
  assert.equal(mixed.cohorts.icc.consecutiveFailures, 1);
  assert.equal(mixed.cohorts.icc.lastSuccessAt, initialAt.toISOString());
  assert.deepEqual(mixed.cohorts.icc.failure, { stage: "admission", code: "accepted-fixture-missing" });
  assert.equal(mixed.lastSuccessAt, first.lastSuccessAt);
  assert.equal(Date.parse(mixed.nextAttemptAt) - attemptedAt.getTime(), 5 * 60_000);
  for (const [id, status] of [["icc:270987", "live"], ["icc:274310", "finished"]]) {
    const fixture = mixed.snapshot.fixtures.find((item) => item.id === id);
    assert.equal(fixture.status, status);
    assert.equal(fixture.source.verification, "verified");
    assert.equal(fixture.source.observedAt, attemptedAt.toISOString());
  }
  const wi = mixed.snapshot.fixtures.find((item) => item.id === "icc:270273");
  assert.equal(wi.status, "live");
  assert.equal(wi.source.verification, undefined, "A fully admitted cohort keeps its legacy source payload");
  for (const id of ["icc:275300", "icc:273760", "icc:274655"]) {
    assert.deepEqual(mixed.snapshot.fixtures.find((item) => item.id === id),
      marked(first.snapshot.fixtures.filter((item) => item.id === id), "held")[0]);
  }
  assert.doesNotThrow(() => validateCricketSnapshot(mixed.snapshot));
  const later = new Date(attemptedAt.getTime() + 5 * 60_000);
  const repeated = await refreshCricketState(mixed, later, async () => withReceipt(candidate, later));
  assert.equal(repeated.snapshot.revision, mixed.snapshot.revision, "Receipt renewal alone is not a content revision");
  assert.equal(repeated.cohorts.icc.consecutiveFailures, 2);
  assert.equal(repeated.snapshot.coverage.find((item) => item.competitionId === "icc").checkedAt, initialAt.toISOString());
});

test("record isolation supports verified live rows even when both international cohorts have conflicts", async () => {
  const rows = [row(), row({ match_id: "270272", teamb: "England", teamb_id: "1" }),
    row({ match_id: "270274" }), row({ match_id: "270275", teamb: "England", teamb_id: "1" })]
    .map((item) => ({ ...item, live: false, upcoming: true }));
  const initial = normalized(rows);
  const first = await refreshCricketState(null, now, async () => initial);
  const later = new Date(now.getTime() + 5 * 60_000);
  const candidate = withReceipt({ ...initial, fixtures: initial.fixtures.map((fixture) =>
    ["icc:270271", "icc:270272"].includes(fixture.id)
      ? { ...fixture, start: "2026-09-30T09:00:00.000Z" }
      : { ...fixture, status: "live" }) }, later);
  const mixed = await refreshCricketState(first, later, async () => candidate);
  assert.equal(mixed.snapshot.sourceStatus, "partial");
  assert.equal(mixed.consecutiveFailures, 1);
  assert.equal(mixed.lastSuccessAt, first.lastSuccessAt);
  for (const scope of ["west-indies", "icc"]) {
    const scopeRows = mixed.snapshot.fixtures.filter((fixture) => fixture.competitionId === scope);
    const fresh = scopeRows.find((fixture) => fixture.source.verification === "verified");
    const held = scopeRows.find((fixture) => fixture.source.verification === "held");
    assert.equal(fresh.status, "live");
    assert.equal(fresh.source.observedAt, later.toISOString());
    assert.equal(held.source.observedAt, now.toISOString());
    assert.equal(mixed.cohorts[scope].consecutiveFailures, 1);
    assert.equal(mixed.snapshot.coverage.find((item) => item.competitionId === scope).status, "unavailable");
    assert.equal(mixed.snapshot.coverage.find((item) => item.competitionId === scope).checkedAt, now.toISOString());
  }
});

test("isolated state survives restart, recollection failure and reviewed recovery without renewing held receipts", async (t) => {
  const { initialAt, attemptedAt, initial, candidate } = octoberConflictScenario();
  const first = await refreshCricketState(null, initialAt, async () => initial);
  first.nextAttemptAt = new Date(attemptedAt.getTime() - 1).toISOString();
  t.mock.timers.enable({ apis: ["Date"], now: attemptedAt.getTime() });
  const storage = new Map([["cricket-registry-v1", first]]);
  const state = { storage: { get: async (key) => storage.get(key), put: async (key, value) => storage.set(key, structuredClone(value)) },
    waitUntil: () => {} };
  let calls = 0;
  let fail = false;
  let recover = false;
  const options = { collectICC: async (receipt) => {
    calls++;
    if (fail) throw new Error("Incomplete ICC page");
    const collection = recover ? { ...candidate, fixtures: [...candidate.fixtures.map((fixture) =>
      ["icc:273760", "icc:274655"].includes(fixture.id) ? { ...fixture, revised: true } : fixture),
    initial.fixtures.find((fixture) => fixture.id === "icc:275300")] } : candidate;
    return withReceipt(collection, receipt);
  } };
  const registry = new CricketFixtureRegistry(state, {}, options);
  await Promise.all(Array.from({ length: 5 }, () => registry.fetch(new Request("https://internal/refresh", { method: "POST" }))));
  const isolated = storage.get("cricket-registry-v1");
  assert.equal(calls, 1);
  assert.equal(isolated.snapshot.sourceStatus, "partial");
  const restarted = new CricketFixtureRegistry(state, {}, options);
  const response = await restarted.fetch(new Request("https://internal/fixtures"));
  assert.deepEqual((await response.json()).fixtures, isolated.snapshot.fixtures);
  assert.equal(calls, 1);
  t.mock.timers.tick(5 * 60_000);
  fail = true;
  await restarted.fetch(new Request("https://internal/refresh", { method: "POST" }));
  const unavailable = storage.get("cricket-registry-v1");
  assert.equal(unavailable.snapshot.sourceStatus, "last-known-good");
  assert.deepEqual(unavailable.snapshot.fixtures, isolated.snapshot.fixtures, "A failed collection cannot change verification or renew any row receipt");
  assert.equal(unavailable.snapshot.revision, isolated.snapshot.revision);
  t.mock.timers.tick(5 * 60_000);
  fail = false;
  await restarted.fetch(new Request("https://internal/refresh", { method: "POST" }));
  const retried = storage.get("cricket-registry-v1");
  assert.equal(retried.cohorts.icc.consecutiveFailures, 3);
  assert.equal(retried.snapshot.sourceStatus, "partial");
  for (const fixture of isolated.snapshot.fixtures.filter((item) => item.source.verification === "held")) {
    assert.deepEqual(retried.snapshot.fixtures.find((item) => item.id === fixture.id), fixture);
  }
  assert.equal(retried.snapshot.coverage.find((item) => item.competitionId === "icc").checkedAt, initialAt.toISOString());
  t.mock.timers.tick(5 * 60_000);
  recover = true;
  await restarted.fetch(new Request("https://internal/refresh", { method: "POST" }));
  const recovered = storage.get("cricket-registry-v1");
  assert.equal(calls, 4);
  assert.equal(recovered.snapshot.sourceStatus, "verified");
  assert.equal(recovered.consecutiveFailures, 0);
  assert.equal(recovered.cohorts.icc.consecutiveFailures, 0);
  assert.ok(recovered.snapshot.fixtures.every((fixture) => fixture.source.verification === undefined));
  assert.ok(recovered.snapshot.fixtures.every((fixture) => fixture.source.observedAt === new Date().toISOString()));
});

test("older receipts after isolation hold all rows despite the deliberately retained old coverage timestamp", async () => {
  const { initialAt, attemptedAt, initial, candidate } = octoberConflictScenario();
  const first = await refreshCricketState(null, initialAt, async () => initial);
  const isolated = await refreshCricketState(first, attemptedAt, async () => candidate);
  const later = new Date(attemptedAt.getTime() + 5 * 60_000);
  const regressed = await refreshCricketState(isolated, later,
    async () => withReceipt(candidate, new Date(attemptedAt.getTime() - 1)));
  assert.equal(regressed.snapshot.sourceStatus, "last-known-good");
  assert.deepEqual(regressed.snapshot.fixtures, marked(isolated.snapshot.fixtures, "held"));
  for (const scope of ["west-indies", "icc"]) {
    assert.deepEqual(regressed.cohorts[scope].failure, { stage: "admission", code: "receipt-regressed" });
  }
});

test("a cohort watermark failure downgrades its verified rows while the other cohort refreshes in a partial response", async () => {
  const { initialAt, attemptedAt, initial, candidate } = octoberConflictScenario();
  const first = await refreshCricketState(null, initialAt, async () => initial);
  const identityConflict = structuredClone(candidate);
  identityConflict.fixtures.find((fixture) => fixture.id === "icc:270273").home = { id: "icc:1:7", name: "Australia" };
  const isolated = await refreshCricketState(first, attemptedAt, async () => identityConflict);
  assert.equal(isolated.snapshot.sourceStatus, "partial");
  assert.ok(isolated.snapshot.fixtures.some((fixture) => fixture.competitionId === "icc" && fixture.source.verification === "verified"));
  assert.equal(isolated.snapshot.fixtures.find((fixture) => fixture.id === "icc:270273").source.observedAt, initialAt.toISOString());
  const later = new Date(attemptedAt.getTime() + 5 * 60_000);
  const publisherReceipt = new Date(attemptedAt.getTime() - 1);
  const mixed = await refreshCricketState(isolated, later, async () => withReceipt(candidate, publisherReceipt));
  const byScope = (state, scope) => state.snapshot.fixtures.filter((fixture) => fixture.competitionId === scope);
  assert.equal(mixed.snapshot.sourceStatus, "partial");
  assert.deepEqual(byScope(mixed, "icc"), marked(byScope(isolated, "icc"), "held"),
    "Scoped receipt failure must downgrade every previously verified row without renewing any receipt");
  assert.deepEqual(mixed.cohorts.icc.failure, { stage: "admission", code: "receipt-regressed" });
  assert.equal(mixed.cohorts.icc.consecutiveFailures, 2);
  assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === "icc").checkedAt, initialAt.toISOString());
  const wi = byScope(mixed, "west-indies")[0];
  assert.equal(wi.status, "live");
  assert.equal(wi.home.name, "India");
  assert.equal(wi.source.observedAt, publisherReceipt.toISOString());
  assert.equal(wi.source.verification, undefined);
  assert.equal(mixed.cohorts["west-indies"].consecutiveFailures, 0);
  assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === "west-indies").status, "covered");
  assert.equal(mixed.lastSuccessAt, first.lastSuccessAt);
});

test("public source verification accepts only the additive verified or held enum", async () => {
  const first = await refreshCricketState(null, now, async () => cohortCollection());
  assert.doesNotThrow(() => validateCricketSnapshot(first.snapshot));
  for (const verification of ["verified", "held", "unknown", null, true]) {
    const snapshot = structuredClone(first.snapshot);
    snapshot.fixtures[0].source.verification = verification;
    if (verification === "held") snapshot.coverage.find((coverage) => coverage.competitionId === snapshot.fixtures[0].competitionId).status = "unavailable";
    if (["verified", "held"].includes(verification)) assert.doesNotThrow(() => validateCricketSnapshot(snapshot));
    else assert.throws(() => validateCricketSnapshot(snapshot), /Invalid cricket fixture/);
  }
});

test("verification markers cannot certify CPL or another source scope and held rows require unavailable coverage", async () => {
  const first = await refreshCricketState(null, now, async () => cohortCollection());
  for (const verification of ["verified", "held"]) {
    for (const scope of ["cpl", "unknown"]) {
      const snapshot = structuredClone(first.snapshot);
      const fixture = snapshot.fixtures[0];
      snapshot.coverage.find((coverage) => coverage.competitionId === fixture.competitionId).fixtureCount--;
      fixture.competitionId = scope;
      fixture.source.verification = verification;
      const coverage = snapshot.coverage.find((item) => item.competitionId === scope);
      if (coverage) { coverage.fixtureCount++; coverage.status = verification === "held" ? "unavailable" : "covered"; }
      assert.throws(() => validateCricketSnapshot(snapshot), /Invalid cricket fixture/);
    }
  }
  for (const scope of ["west-indies", "icc"]) {
    for (const status of ["covered", "offseason"]) {
      const snapshot = structuredClone(first.snapshot);
      const fixture = snapshot.fixtures.find((item) => item.competitionId === scope);
      fixture.source.verification = "held";
      snapshot.coverage.find((coverage) => coverage.competitionId === scope).status = status;
      assert.throws(() => validateCricketSnapshot(snapshot), /Invalid cricket fixture/);
    }
  }
});

test("similar future women's IDs with unreviewed teams and tournament remain held without blocking West Indies", async () => {
  const women = (match_id, match_date_gmt, match_time_gmt, teama, teamb) => row({ match_id, match_date_gmt, match_time_gmt,
    teama, teamb, teama_id: "17", teamb_id: "18", league_id: "10", match_type: "T20", live: false, upcoming: true,
    is_revised: false, series_name: "Women's international cricket" });
  const rows = [row(), women("275298", "10/4/2026", "02:30", "Indonesia", "Samoa"),
    women("275299", "10/6/2026", "02:00", "Malaysia", "Indonesia"),
    women("275300", "10/7/2026", "02:30", "Malaysia", "Samoa")];
  const first = await refreshCricketState(null, now, async () => normalized(rows));
  const later = new Date(now.getTime() + 5 * 60_000);
  const changedRows = rows.map((fixture, index) => index === 0 ? fixture
    : { ...fixture, match_time_gmt: index === 2 ? "02:30" : "02:00" });
  const candidate = withReceipt(normalized(changedRows), later);
  assert.throws(() => admitICC(candidate, first.snapshot.fixtures, later), /Unconfirmed ICC kickoff/);
  const mixed = await refreshCricketState(first, later, async () => candidate);
  assert.deepEqual(mixed.snapshot.fixtures.filter((fixture) => fixture.competitionId === "icc"),
    marked(first.snapshot.fixtures.filter((fixture) => fixture.competitionId === "icc"), "held"));
  assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === "icc").fixtureCount, 3);
  assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === "icc").checkedAt, now.toISOString());
  assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === "west-indies").checkedAt, later.toISOString());
  assert.equal(mixed.snapshot.sourceStatus, "partial");
});

test("kickoff, participant, live and terminal guards isolate either international cohort without weakening admission", async () => {
  const later = new Date(now.getTime() + 5 * 60_000);
  for (const failedID of ["west-indies", "icc"]) {
    for (const conflict of ["kickoff", "identity", "live", "terminal"]) {
      const initial = cohortCollection();
      if (conflict === "terminal") initial.fixtures.find((fixture) => fixture.competitionId === failedID).status = "finished";
      const first = await refreshCricketState(null, now, async () => initial);
      const candidate = withReceipt(cohortCollection(), later);
      const changed = candidate.fixtures.find((fixture) => fixture.competitionId === failedID);
      if (conflict === "kickoff") changed.start = "2026-09-30T09:00:00.000Z";
      if (conflict === "identity") changed.home = { ...changed.home, id: "icc:1:7", name: "Australia" };
      if (conflict === "live") changed.status = "scheduled";
      const mixed = await refreshCricketState(first, later, async () => candidate);
      assert.deepEqual(mixed.snapshot.fixtures.filter((fixture) => fixture.competitionId === failedID),
        marked(first.snapshot.fixtures.filter((fixture) => fixture.competitionId === failedID), "held"), `${failedID}/${conflict} factual fields must be held exactly`);
      const healthyID = failedID === "icc" ? "west-indies" : "icc";
      assert.equal(mixed.snapshot.fixtures.find((fixture) => fixture.competitionId === healthyID).source.observedAt, later.toISOString());
      assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === failedID).status, "unavailable");
      assert.equal(mixed.snapshot.coverage.find((coverage) => coverage.competitionId === healthyID).status, "covered");
    }
  }
});

test("cross-cohort ID and participant movement holds both scopes and cannot duplicate retained identities", async () => {
  const first = await refreshCricketState(null, now, async () => cohortCollection());
  const later = new Date(now.getTime() + 5 * 60_000);
  for (const movedID of ["west-indies", "icc"]) {
    const candidate = withReceipt(cohortCollection(), later);
    const moved = candidate.fixtures.find((fixture) => fixture.competitionId === movedID);
    moved.competitionId = movedID === "icc" ? "west-indies" : "icc";
    moved.away = { ...moved.away, id: "icc:1:7", name: "Australia" };
    moved.revised = true;
    const held = await refreshCricketState(first, later, async () => candidate);
    assert.deepEqual(held.snapshot.fixtures, marked(first.snapshot.fixtures, "held"));
    assert.equal(new Set(held.snapshot.fixtures.map((fixture) => fixture.id)).size, first.snapshot.fixtures.length);
    assert.equal(held.snapshot.sourceStatus, "last-known-good");
    assert.equal(held.snapshot.checkedAt, first.snapshot.checkedAt);
    for (const id of ["west-indies", "icc"]) {
      assert.equal(held.snapshot.coverage.find((coverage) => coverage.competitionId === id).status, "unavailable");
      assert.deepEqual(held.snapshot.sync.cohorts[id].failure, { stage: "admission", code: "scope-conflict" });
    }
  }
});

test("explicit revised corrections still admit and clear prior cohort failures only on full recovery", async () => {
  const first = await refreshCricketState(null, now, async () => cohortCollection());
  const later = new Date(now.getTime() + 5 * 60_000);
  const candidate = withReceipt(cohortCollection(), later);
  const changed = candidate.fixtures.find((fixture) => fixture.competitionId === "icc");
  changed.start = "2026-09-30T09:00:00.000Z";
  const held = await refreshCricketState(first, later, async () => candidate);
  changed.revised = true;
  const recoveredAt = new Date(later.getTime() + 5 * 60_000);
  const recovered = await refreshCricketState(held, recoveredAt, async () => withReceipt(candidate, recoveredAt));
  assert.equal(recovered.snapshot.fixtures.find((fixture) => fixture.id === changed.id).start, changed.start);
  assert.equal(recovered.snapshot.sourceStatus, "verified");
  assert.equal(recovered.consecutiveFailures, 0);
  assert.equal(recovered.lastSuccessAt, recoveredAt.toISOString());
  assert.equal(recovered.snapshot.sync.cohorts.icc.consecutiveFailures, 0);
  assert.equal(recovered.snapshot.sync.cohorts.icc.failure, undefined);
  assert.equal(recovered.snapshot.fixtures.some((fixture) => Object.hasOwn(fixture, "revised")), false);
});

test("legacy shared failure streak survives cohort migration without falsely clearing unresolved ICC conflict", async () => {
  const legacy = await refreshCricketState(null, now, async () => cohortCollection());
  delete legacy.cohorts;
  delete legacy.snapshot.sync.cohorts;
  legacy.consecutiveFailures = 8;
  legacy.snapshot.sync.consecutiveFailures = 8;
  legacy.snapshot.sourceStatus = "last-known-good";
  legacy.snapshot.coverage = legacy.snapshot.coverage.map((coverage) => coverage.competitionId === "cpl"
    ? coverage : { ...coverage, status: "unavailable" });
  const later = new Date(now.getTime() + 5 * 60_000);
  const candidate = withReceipt(cohortCollection(), later);
  candidate.fixtures.find((fixture) => fixture.competitionId === "icc").start = "2026-09-30T09:00:00.000Z";
  const mixed = await refreshCricketState(legacy, later, async () => candidate);
  assert.equal(mixed.snapshot.sourceStatus, "partial");
  assert.equal(mixed.consecutiveFailures, 9);
  assert.equal(mixed.cohorts.icc.consecutiveFailures, 9);
  assert.equal(mixed.cohorts["west-indies"].consecutiveFailures, 0);
  assert.equal(mixed.lastSuccessAt, legacy.lastSuccessAt);
});

test("empty and pending-only cohort watermarks reject older publisher receipts in either scope", async () => {
  const later = new Date(now.getTime() + 5 * 60_000);
  const older = new Date(now.getTime() - 5 * 60_000);
  for (const emptyID of ["west-indies", "icc"]) {
    for (const pending of [false, true]) {
      const wi = row({ live: false, is_match_ended: true });
      const other = row({ match_id: "270272", teamb: "England", teamb_id: "1", live: false, is_match_ended: true });
      const rows = [emptyID === "icc" ? wi : other];
      if (pending) rows.push({ ...(emptyID === "icc" ? other : wi), is_provisional_time: true });
      const initial = normalized(rows);
      const first = await refreshCricketState(null, now, async () => initial);
      const oldCoverage = first.snapshot.coverage.find((coverage) => coverage.competitionId === emptyID);
      assert.equal(oldCoverage.fixtureCount, 0);
      assert.equal(oldCoverage.pendingFixtureCount, pending ? 1 : 0);
      const held = await refreshCricketState(first, later, async () => withReceipt(initial, older));
      assert.deepEqual(held.snapshot.fixtures, marked(first.snapshot.fixtures, "held"));
      assert.deepEqual(held.snapshot.coverage.find((coverage) => coverage.competitionId === emptyID),
        { ...oldCoverage, status: "unavailable" });
      assert.equal(held.snapshot.checkedAt, first.snapshot.checkedAt);
      assert.equal(held.snapshot.sourceStatus, "last-known-good");
      assert.equal(held.cohorts[emptyID].consecutiveFailures, 1);
      assert.equal(held.cohorts[emptyID].lastSuccessAt, first.cohorts[emptyID].lastSuccessAt);
      assert.deepEqual(held.cohorts[emptyID].failure, { stage: "admission", code: "receipt-regressed" });
      const recoveredAt = new Date(later.getTime() + 5 * 60_000);
      const recovered = await refreshCricketState(held, recoveredAt, async () => withReceipt(initial, recoveredAt));
      const freshCoverage = recovered.snapshot.coverage.find((coverage) => coverage.competitionId === emptyID);
      assert.equal(freshCoverage.status, "covered");
      assert.equal(freshCoverage.checkedAt, recoveredAt.toISOString());
      assert.equal(freshCoverage.pendingFixtureCount, pending ? 1 : 0);
      assert.equal(recovered.cohorts[emptyID].consecutiveFailures, 0);
    }
  }
});

test("a fresh and retained cohort union cannot overflow the bounded snapshot or silently drop rows", async () => {
  const templates = cohortCollection();
  const makeRows = (id, count, identity, status) => Array.from({ length: count }, (_, offset) => ({
    ...templates.fixtures.find((fixture) => fixture.competitionId === id),
    id: `icc:${identity + offset}`, start: "2026-10-01T08:30:00.000Z", status,
  }));
  const initial = { ...templates, fixtures: [...makeRows("west-indies", 10, 300000, "finished"),
    ...makeRows("icc", 290, 400000, "scheduled")] };
  const first = await refreshCricketState(null, now, async () => initial);
  const later = new Date(now.getTime() + 5 * 60_000);
  const candidate = withReceipt({ ...templates, fixtures: [...makeRows("west-indies", 290, 500000, "scheduled"),
    ...makeRows("icc", 10, 400000, "scheduled")] }, later);
  candidate.fixtures.find((fixture) => fixture.competitionId === "icc").start = "2026-10-01T09:00:00.000Z";
  const held = await refreshCricketState(first, later, async () => candidate);
  assert.deepEqual(held.snapshot.fixtures, marked(first.snapshot.fixtures, "held"));
  assert.equal(held.snapshot.fixtures.length, 300);
  assert.equal(held.snapshot.sourceStatus, "last-known-good");
  for (const id of ["west-indies", "icc"]) {
    assert.deepEqual(held.snapshot.sync.cohorts[id].failure, { stage: "admission", code: "source-incomplete" });
  }
});

test("recovered CPL overflow preserves the whole valid snapshot on collection success and failure", async () => {
  const { previous, candidate, attemptedAt } = await nearBoundScenario();
  for (const transportFailure of [false, true]) {
    const collect = async () => {
      if (transportFailure) throw new Error("ICC upstream unavailable");
      return withReceipt(candidate, attemptedAt);
    };
    const held = await refreshCricketState(previous, attemptedAt, collect, async () => recoveredCPL(attemptedAt));
    assert.deepEqual(held.snapshot.fixtures, previous.snapshot.fixtures, "No international or CPL rows may be truncated/replaced");
    assert.equal(held.snapshot.fixtures.length, 390);
    assert.equal(held.snapshot.checkedAt, previous.snapshot.checkedAt);
    assert.equal(held.snapshot.revision, previous.snapshot.revision);
    assert.equal(held.snapshot.schemaVersion, 1);
    assert.equal(held.snapshot.complete, true);
    assert.equal(held.snapshot.sourceStatus, "last-known-good");
    assert.deepEqual(held.snapshot.coverage, previous.snapshot.coverage.map((coverage) => ({ ...coverage, status: "unavailable" })));
    assert.equal(held.snapshot.coverage.find((coverage) => coverage.competitionId === "cpl").checkedAt,
      previous.snapshot.coverage.find((coverage) => coverage.competitionId === "cpl").checkedAt);
    assert.equal(held.consecutiveFailures, previous.consecutiveFailures + 1);
    assert.equal(held.lastSuccessAt, previous.lastSuccessAt);
    assert.equal(Date.parse(held.nextAttemptAt) - attemptedAt.getTime(), 5 * 60_000);
    assert.deepEqual(held.snapshot.sync.failure, { stage: "admission", code: "source-incomplete" });
    const audit = auditCricketSnapshot(held.snapshot, { now: attemptedAt.getTime(), expectedCompetitionIds: ["cpl", "west-indies", "icc"] });
    assert.equal(audit.fixtureCount, 390);
    assert.equal(audit.actionable, true);
    assert.equal(new Set(held.snapshot.fixtures.map((fixture) =>
      `${fixture.competitionId}|${fixture.start}|${fixture.home.id}|${fixture.away.id}`)).size, 390,
    "The native identity grain must remain complete and unique");
  }
});

test("combined CPL overflow persists one failure/backoff across concurrent refresh, restart and retry", async (t) => {
  const { previous, candidate, attemptedAt } = await nearBoundScenario();
  t.mock.timers.enable({ apis: ["Date"], now: attemptedAt.getTime() });
  const storage = new Map([["cricket-registry-v1", previous]]);
  let calls = 0;
  let cplCalls = 0;
  let backgroundCalls = 0;
  const state = { storage: { get: async (key) => storage.get(key), put: async (key, value) => storage.set(key, value) },
    waitUntil: () => { backgroundCalls++; } };
  const options = { collectICC: async (receipt) => { calls++; return withReceipt(candidate, receipt); },
    collectCPL: async () => { cplCalls++; return recoveredCPL(new Date()); } };
  const registry = new CricketFixtureRegistry(state, {}, options);
  await Promise.all(Array.from({ length: 5 }, () => registry.fetch(new Request("https://internal/refresh", { method: "POST" }))));
  const retained = storage.get("cricket-registry-v1");
  assert.equal(calls, 1);
  assert.equal(cplCalls, 1);
  assert.equal(retained.consecutiveFailures, previous.consecutiveFailures + 1);
  assert.deepEqual(retained.snapshot.fixtures, previous.snapshot.fixtures);
  assert.equal(Date.parse(retained.nextAttemptAt) - attemptedAt.getTime(), 5 * 60_000);
  const restarted = new CricketFixtureRegistry(state, {}, options);
  const response = await restarted.fetch(new Request("https://internal/fixtures"));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).fixtures.length, 390);
  assert.equal(backgroundCalls, 0);
  t.mock.timers.tick(5 * 60_000 - 1);
  await restarted.fetch(new Request("https://internal/refresh", { method: "POST" }));
  assert.equal(calls, 1);
  t.mock.timers.tick(1);
  await restarted.fetch(new Request("https://internal/refresh", { method: "POST" }));
  assert.equal(calls, 2);
  assert.equal(cplCalls, 2);
  assert.equal(storage.get("cricket-registry-v1").consecutiveFailures, previous.consecutiveFailures + 2);
  assert.deepEqual(storage.get("cricket-registry-v1").snapshot.fixtures, previous.snapshot.fixtures);
});

test("whole collection failure preserves every cohort and cold failure cannot invent a successful empty snapshot", async () => {
  const privateText = "private publisher body https://publisher.invalid/?credential=secret";
  const fail = async () => { throw new Error(privateText); };
  const cold = await refreshCricketState(null, now, fail);
  assert.equal(cold.snapshot, undefined);
  assert.equal(cold.consecutiveFailures, 1);
  assert.equal(Date.parse(cold.nextAttemptAt) - now.getTime(), 5 * 60_000);
  const first = await refreshCricketState(null, now, async () => cohortCollection());
  const later = new Date(now.getTime() + 5 * 60_000);
  for (const error of [new Error(privateText), new Error("Incomplete ICC page"), new Error("Truncated ICC schedule")]) {
    const failed = await refreshCricketState(first, later, async () => { throw error; });
    assert.deepEqual(failed.snapshot.fixtures, first.snapshot.fixtures);
    assert.equal(failed.snapshot.checkedAt, first.snapshot.checkedAt);
    assert.equal(failed.snapshot.sourceStatus, "last-known-good");
    assert.equal(failed.lastSuccessAt, first.lastSuccessAt);
    assert.equal(JSON.stringify(failed).includes(privateText), false);
    for (const id of ["west-indies", "icc"]) {
      assert.deepEqual(failed.snapshot.coverage.find((coverage) => coverage.competitionId === id),
        { ...first.snapshot.coverage.find((coverage) => coverage.competitionId === id), status: "unavailable" });
      assert.equal(failed.snapshot.sync.cohorts[id].failure.stage, "collection");
    }
  }
});

test("cold collection failure returns the unchanged unavailable 503 contract with finite cohort diagnostics", async () => {
  const storage = new Map();
  const state = { storage: { get: async (key) => storage.get(key), put: async (key, value) => storage.set(key, value) }, waitUntil: () => {} };
  const registry = new CricketFixtureRegistry(state, {}, { collectICC: async () => { throw new Error("private source failure"); } });
  const response = await registry.fetch(new Request("https://internal/fixtures"));
  assert.equal(response.status, 503);
  const body = await response.json();
  assert.equal(body.schemaVersion, 1);
  assert.equal(body.complete, false);
  assert.equal(body.sourceStatus, "unavailable");
  assert.equal(body.sync.consecutiveFailures, 1);
  assert.equal(JSON.stringify(body).includes("private source failure"), false);
  for (const id of ["west-indies", "icc"]) {
    assert.deepEqual(body.sync.cohorts[id].failure, { stage: "collection", code: "validation-or-runtime-failure" });
    assert.equal(body.sync.cohorts[id].lastSuccessAt, undefined);
  }
});

test("partial conflict attempts persist a five-minute backoff across concurrent registry calls and restart", async () => {
  const instant = new Date();
  const initial = withReceipt(cohortCollection(), instant);
  const first = await refreshCricketState(null, instant, async () => initial);
  first.nextAttemptAt = new Date(instant.getTime() - 1).toISOString();
  const storage = new Map([["cricket-registry-v1", first]]);
  let calls = 0;
  let backgroundCalls = 0;
  const state = { storage: { get: async (key) => storage.get(key), put: async (key, value) => storage.set(key, value) },
    waitUntil: () => { backgroundCalls++; } };
  const options = { collectICC: async (receipt) => {
    calls++;
    const candidate = withReceipt(cohortCollection(), receipt);
    candidate.fixtures.find((fixture) => fixture.competitionId === "icc").start = "2026-09-30T09:00:00.000Z";
    return candidate;
  } };
  const registry = new CricketFixtureRegistry(state, {}, options);
  await Promise.all(Array.from({ length: 5 }, () => registry.fetch(new Request("https://internal/refresh", { method: "POST" }))));
  assert.equal(calls, 1);
  assert.equal(storage.get("cricket-registry-v1").consecutiveFailures, 1);
  const restarted = new CricketFixtureRegistry(state, {}, options);
  const response = await restarted.fetch(new Request("https://internal/fixtures"));
  assert.equal((await response.json()).sourceStatus, "partial");
  assert.equal(backgroundCalls, 0);
  assert.equal(calls, 1);
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

// Public score fields redacted from the already admitted ICC schedule receipt
// at2026-10-29T17:21:44.453Z (59/59 rows). Replay them in the existing fixed
// fixture/date harness: these are contract regressions, not current-live proof.
const testScoreRow = (overrides = {}) => row({ match_id: "274665", teama: "Bangladesh", teama_id: "2",
  teamb: "West Indies", teamb_id: "9", match_type: "Test", current_innings: "2", day: "2", session: "3",
  match_status: "Stumps", match_display_status: "Stumps",
  current_status_message: "Stumps, Day 2 - West Indies trail by 138 runs",
  scores: [{ inning_no: "1", team_id: "2", team_runs: "272", team_wickets: "10", team_overs: "97.4" },
    { inning_no: "2", team_id: "9", team_runs: "134", team_wickets: "4", team_overs: "48.0" }], ...overrides });
const t20ScoreRow = (overrides = {}) => row({ match_id: "274661", teama: "Afghanistan", teama_id: "1188",
  teamb: "Zimbabwe", teamb_id: "10", match_type: "T20", current_innings: "2",
  match_status: "Play In Progress", match_display_status: "Live",
  current_status_message: "Second Innings : Zimbabwe need 134 runs in 54 balls at 14.88 rpo",
  scores: [{ inning_no: "1", team_id: "1188", team_runs: "221", team_wickets: "7", team_overs: "20.0", allotted_overs: "20" },
    { inning_no: "2", team_id: "10", team_runs: "88", team_wickets: "5", team_overs: "11.0", target: "222", allotted_overs: "20" }], ...overrides });

test("ICC optional Test context keeps exact innings scores and explicit Stumps without changing live authority", () => {
  const fixture = normalized([testScoreRow()]).fixtures[0];
  assert.equal(fixture.id, "icc:274665");
  assert.equal(fixture.status, "live");
  assert.equal(fixture.source.observedAt, now.toISOString());
  assert.deepEqual(fixture.context, { innings: [
    { number: 1, teamID: "icc:1:2", runs: 272, wickets: 10, overs: "97.4" },
    { number: 2, teamID: "icc:1:9", runs: 134, wickets: 4, overs: "48.0" }],
  currentInnings: 2, day: 2, session: 3, phase: "stumps", message: "Stumps, Day 2 - West Indies trail by 138 runs" });
  assert.equal(fixture.sources, undefined, "A score is not a stream");
});

test("ICC Test context preserves repeated batting teams rather than collapsing innings by team", () => {
  const fixture = normalized([testScoreRow({ match_id: "269792", teama: "South Africa", teama_id: "7",
    teamb: "Australia", teamb_id: "1", current_innings: "3", day: "3",
    current_status_message: "Stumps, Day 3 - South Africa lead by 40 runs",
    scores: [{ inning_no: "1", team_id: "7", team_runs: "329", team_wickets: "10", team_overs: "82.3" },
      { inning_no: "2", team_id: "1", team_runs: "429", team_wickets: "10", team_overs: "125.1" },
      { inning_no: "3", team_id: "7", team_runs: "140", team_wickets: "4", team_overs: "47.0" }] })]).fixtures[0];
  assert.deepEqual(fixture.context.innings.map((inning) => [inning.number, inning.teamID, inning.overs]),
    [[1, "icc:1:7", "82.3"], [2, "icc:1:1", "125.1"], [3, "icc:1:7", "47.0"]]);
  assert.equal(fixture.context.currentInnings, 3);
});

test("ICC explicit Test ordinal and Day4 intervals retain the canonical initial fixture", () => {
  // Whitelisted public fields inspected at2026-10-30T11:30:49.662Z. This
  // historical replay establishes the contract, not current playback or a
  // daily broadcast kickoff. The publisher's series count is not an ordinal.
  const at = new Date("2026-10-30T11:30:49.662Z");
  for (const [label, expected] of [["Lunch", "lunch"], ["Play In Progress", "in-play"], ["Stumps", "stumps"]]) {
    const raw = testScoreRow({ match_id: "269792", teama: "South Africa", teama_id: "7",
      teamb: "Australia", teamb_id: "1", match_date_gmt: "10/27/2026", match_time_gmt: "08:30",
      end_match_date_gmt: "10/31/2026", end_match_time_gmt: "15:30",
      series_name: "Australia in South Africa, 3 Test Series, 2026", match_number: "3rd Test", match_ordinal: "3",
      day: "4", session: "2", match_status: label, match_display_status: "Live", current_innings: "3",
      current_status_message: `Day 4 - ${label}`, scores: [
        { inning_no: "1", team_id: "7", team_runs: "329", team_wickets: "10", team_overs: "82.3" },
        { inning_no: "2", team_id: "1", team_runs: "429", team_wickets: "10", team_overs: "125.1" },
        { inning_no: "3", team_id: "7", team_runs: "217", team_wickets: "5", team_overs: "80.0" }] });
    const result = normalizeICC([parseICCPage(payload([raw],
      { timestamp: { utc_time: "10/30/2026 11:30:49 AM" } }), at)], at);
    const fixture = result.fixtures[0];
    assert.equal(fixture.id, "icc:269792");
    assert.equal(fixture.start, "2026-10-27T08:30:00.000Z");
    assert.equal(fixture.status, "live");
    assert.equal(fixture.context.matchOrdinal, 3);
    assert.equal(fixture.context.matchEndsAt, "2026-10-31T15:30:00.000Z");
    assert.equal(fixture.context.day, 4);
    assert.equal(fixture.context.session, 2);
    assert.equal(fixture.context.phase, expected);
    assert.equal(fixture.context.broadcastDate, undefined);
    assert.equal(fixture.context.dailyStart, undefined);
    assert.equal(fixture.source.observedAt, "2026-10-30T11:30:49.000Z");
  }
});

test("Test ordinal requires explicit agreeing ordinal and correctly suffixed match label", () => {
  for (const [match_ordinal, match_number, expected] of [[1, "1st Test", 1], ["2", "2nd Test", 2],
    ["3", "3rd Test", 3], ["11", "11th Test", 11], ["12", "12th Test", 12], ["13", "13th Test", 13],
    ["21", "21st Test", 21], ["3", " 3RD TEST ", 3]]) {
    assert.equal(normalized([testScoreRow({ match_ordinal, match_number })]).fixtures[0].context.matchOrdinal, expected);
  }
  for (const changes of [{}, { match_ordinal: "3" }, { match_number: "3rd Test" },
    { match_ordinal: "2", match_number: "3rd Test" }, { match_ordinal: "3", match_number: "3th Test" },
    { match_ordinal: "11", match_number: "11st Test" }, { match_ordinal: "03", match_number: "3rd Test" },
    { match_ordinal: 0, match_number: "0th Test" }, { match_ordinal: "100", match_number: "100th Test" },
    { match_ordinal: "3", match_number: "3 Test Series" }, { match_ordinal: "3", match_number: "3rd ODI" },
    { match_ordinal: "3", match_number: "3rd Test<script>" }, { match_ordinal: null, match_number: "3rd Test" }]) {
    const result = normalized([testScoreRow({ ...changes, series_name: "Australia in South Africa, 3 Test Series, 2026" }), row({ match_id: "999999" })]);
    assert.equal(result.fixtures.length, 2);
    assert.equal(result.fixtures[0].context.matchOrdinal, undefined);
    assert.equal(result.fixtures[0].context.phase, "stumps", "Invalid optional ordinal must not discard independently valid context");
    assert.equal(result.fixtures[0].status, "live");
  }
  const otherFormat = normalized([t20ScoreRow({ match_ordinal: "3", match_number: "3rd Test" })]).fixtures[0];
  assert.equal(otherFormat.context.matchOrdinal, undefined);
});

test("malformed wire Test ordinals cannot provide context authority", () => {
  const fixture = normalized([testScoreRow({ match_ordinal: "3", match_number: "3rd Test" })]).fixtures[0];
  assert.equal(validCricketContext(fixture.context, fixture), true);
  for (const matchOrdinal of [null, "3", 0, 100, 1.5, NaN, Infinity]) {
    assert.equal(validCricketContext({ ...fixture.context, matchOrdinal }, fixture), false);
  }
  const t20 = normalized([t20ScoreRow()]).fixtures[0];
  assert.equal(validCricketContext({ ...t20.context, matchOrdinal: 3 }, t20), false);
});

test("Test end bound comes only from strict explicit same-record GMT fields", () => {
  const explicit = { end_match_date_gmt: "10/4/2026", end_match_time_gmt: "15:30" };
  const fixture = normalized([testScoreRow(explicit)]).fixtures[0];
  assert.equal(fixture.context.matchEndsAt, "2026-10-04T15:30:00.000Z");
  assert.equal(fixture.start, "2026-09-30T08:30:00.000Z");
  const exactlySix = normalized([testScoreRow({ end_match_date_gmt: "10/6/2026", end_match_time_gmt: "08:30" })]).fixtures[0];
  assert.equal(exactlySix.context.matchEndsAt, "2026-10-06T08:30:00.000Z");
  for (const changes of [{}, { end_match_date_gmt: "10/4/2026" }, { end_match_time_gmt: "15:30" },
    { end_match_date_gmt: "2/30/2026", end_match_time_gmt: "15:30" },
    { end_match_date_gmt: "13/4/2026", end_match_time_gmt: "15:30" },
    { end_match_date_gmt: "10/0/2026", end_match_time_gmt: "15:30" },
    { end_match_date_gmt: "10/4/2026", end_match_time_gmt: "24:00" },
    { end_match_date_gmt: "10/4/2026", end_match_time_gmt: "15:60" },
    { end_match_date_gmt: "10/4/2026", end_match_time_gmt: "15:30+02:00" },
    { end_match_date_gmt: "9/30/2026", end_match_time_gmt: "08:30" },
    { end_match_date_gmt: "9/30/2026", end_match_time_gmt: "08:29" },
    { end_match_date_gmt: "10/6/2026", end_match_time_gmt: "08:31" },
    { end_match_date_local: "10/4/2026", end_match_time_local: "15:30" }]) {
    const result = normalized([testScoreRow({ ...changes, day: "4" }), row({ match_id: "999999" })]);
    assert.equal(result.fixtures.length, 2);
    assert.equal(result.fixtures[0].context.matchEndsAt, undefined, "No date/offset/day/receipt fallback");
    assert.equal(result.fixtures[0].context.day, 4);
  }
  const t20 = normalized([t20ScoreRow(explicit)]).fixtures[0];
  assert.equal(t20.context.matchEndsAt, undefined);
  for (const matchEndsAt of [null, 123, "2026-10-04T15:30:00Z", "2026-10-04T17:30:00.000+02:00",
    "2026-09-31T15:30:00.000Z", "2026-09-30T08:30:00.000Z", "2026-10-06T08:31:00.000Z"]) {
    assert.equal(validCricketContext({ ...fixture.context, matchEndsAt }, fixture), false);
  }
  assert.equal(validCricketContext({ ...t20.context, matchEndsAt: fixture.context.matchEndsAt }, t20), false);
});

test("explicit Test end-bound update changes revision without changing canonical fixture identity", async () => {
  const first = await refreshCricketState(null, now, async () => normalized([testScoreRow({
    end_match_date_gmt: "10/4/2026", end_match_time_gmt: "15:30" })]));
  const later = new Date(now.getTime() + 5 * 60_000);
  const candidate = withReceipt(normalized([testScoreRow({ end_match_date_gmt: "10/4/2026", end_match_time_gmt: "16:00" })]), later);
  const second = await refreshCricketState(first, later, async () => candidate);
  assert.notEqual(second.snapshot.revision, first.snapshot.revision);
  assert.equal(second.snapshot.fixtures[0].context.matchEndsAt, "2026-10-04T16:00:00.000Z");
  for (const key of ["id", "start", "status", "format", "home", "away"]) assert.deepEqual(second.snapshot.fixtures[0][key], first.snapshot.fixtures[0][key]);
  const noEnd = withReceipt(normalized([testScoreRow()]), later);
  const cleared = await refreshCricketState(first, later, async () => noEnd);
  assert.equal(cleared.snapshot.fixtures[0].context.matchEndsAt, undefined, "Fresh missing bound never borrows an accepted end");
});

test("fresh Test ordinal changes advance revision and invalid ordinal never inherits prior authority", async () => {
  const original = normalized([testScoreRow({ match_ordinal: "3", match_number: "3rd Test" })]);
  const first = await refreshCricketState(null, now, async () => original);
  const later = new Date(now.getTime() + 5 * 60_000);
  const invalid = withReceipt(normalized([testScoreRow({ match_ordinal: "2", match_number: "3rd Test" })]), later);
  const second = await refreshCricketState(first, later, async () => invalid);
  assert.notEqual(second.snapshot.revision, first.snapshot.revision);
  const fixture = second.snapshot.fixtures[0];
  assert.equal(fixture.context.matchOrdinal, undefined);
  assert.equal(fixture.context.day, first.snapshot.fixtures[0].context.day);
  assert.equal(fixture.context.phase, first.snapshot.fixtures[0].context.phase);
  assert.equal(fixture.source.observedAt, later.toISOString());
  for (const key of ["id", "start", "status", "format", "home", "away"]) assert.deepEqual(fixture[key], first.snapshot.fixtures[0][key]);
  const failed = await refreshCricketState(first, later, async () => { throw new Error("ICC upstream unavailable"); });
  assert.equal(failed.snapshot.fixtures[0].context.matchOrdinal, 3);
  assert.equal(failed.snapshot.fixtures[0].source.observedAt, now.toISOString(), "Failure cannot renew prior ordinal observation");
});

test("ICC T20 target comes from the exact current innings and overs remain strings", () => {
  const fixture = normalized([t20ScoreRow()]).fixtures[0];
  assert.equal(fixture.context.target, 222);
  assert.equal(fixture.context.phase, "in-play");
  assert.equal(fixture.context.innings[1].overs, "11.0");
  const first = normalized([t20ScoreRow({ current_innings: "1", scores: [t20ScoreRow().scores[0]] })]).fixtures[0];
  assert.equal(first.context.target, undefined, "Never borrow a later innings target");
});

test("score context uses exact canonical squad/team IDs and validates explicit batting identity", () => {
  const women = normalized([t20ScoreRow({ league_id: "10" })]).fixtures[0];
  assert.deepEqual(women.context.innings.map((inning) => inning.teamID), ["icc:10:1188", "icc:10:10"]);
  const youth = normalized([t20ScoreRow({ league_id: "35" })]).fixtures[0];
  assert.equal(youth.context.innings[0].teamID, "icc:35:1188");
  const exact = normalized([t20ScoreRow({ current_batting_team_id: "10", current_bowling_team_id: "1188" })]).fixtures[0];
  assert.equal(exact.context.battingTeamID, exact.away.id);
  assert.equal(exact.context.bowlingTeamID, exact.home.id);
  for (const mismatch of [{ current_batting_team_id: "1188" }, { current_bowling_team_id: "9999" },
    { current_batting_team_id: "10", current_bowling_team_id: "10" }]) {
    const fixture = normalized([t20ScoreRow(mismatch)]).fixtures[0];
    assert.equal(fixture.context, undefined);
    assert.equal(fixture.status, "live");
  }
});

test("optional scores cannot manufacture live from a scheduled/unknown fixture or override terminal status", () => {
  for (const flags of [{ live: false, upcoming: true }, { live: false, upcoming: false },
    { is_match_abandoned: true }, { match_status: "Postponed" }]) {
    const fixture = normalized([t20ScoreRow(flags)]).fixtures[0];
    assert.equal(fixture.context, undefined);
    assert.notEqual(fixture.status, "live");
  }
  const finished = normalized([t20ScoreRow({ is_match_ended: true })]).fixtures[0];
  assert.equal(finished.status, "finished");
  assert.equal(finished.context.phase, "finished");
});

test("explicit break/interrupt/Stumps evidence overrides a generic Live label", () => {
  for (const [flags, expected] of [[{ is_match_on_break: true }, "break"],
    [{ is_match_interrupted: true }, "interrupted"], [{ match_status: "Innings Break" }, "innings-break"],
    [{ match_status: "Delayed" }, "delayed"]]) {
    assert.equal(normalized([t20ScoreRow(flags)]).fixtures[0].context.phase, expected);
  }
  for (const [label, expected] of [["Stumps", "stumps"], ["Lunch", "lunch"], ["Tea", "tea"]]) {
    assert.equal(normalized([testScoreRow({ match_status: label, match_display_status: "Live" })]).fixtures[0].context.phase, expected);
  }
  const unknown = normalized([t20ScoreRow({ match_status: "Unreviewed state", match_display_status: "Unreviewed state" })]).fixtures[0];
  assert.equal(unknown.context.phase, undefined, "Score progress must not fill in an unknown phase");
});

test("malformed optional scores are omitted whole without dropping any fixture or sibling", () => {
  const valid = t20ScoreRow().scores;
  const invalid = [null, {}, [], [...valid, { ...valid[0], inning_no: "3" }],
    [{ ...valid[0], team_runs: undefined }], [{ ...valid[0], team_wickets: null }],
    [{ ...valid[0], team_runs: "1e2" }], [{ ...valid[0], team_runs: "-1" }],
    [{ ...valid[0], team_runs: "2001" }], [{ ...valid[0], team_wickets: "11" }],
    [{ ...valid[0], inning_no: "0" }], [{ ...valid[0], inning_no: "1.5" }],
    [{ ...valid[0], team_id: "9999" }], [valid[0], { ...valid[1], inning_no: "1" }],
    [valid[1]], [valid[0], { ...valid[1], team_id: valid[0].team_id }]];
  for (const scores of invalid) {
    const result = normalized([t20ScoreRow({ scores }), row({ match_id: "999999" })]);
    assert.equal(result.fixtures.length, 2);
    assert.equal(result.fixtures[0].context, undefined);
    assert.equal(result.fixtures[0].status, "live");
  }
});

test("Test follow-on can repeat a team while missing/future innings receipts stay unavailable", () => {
  const raw = testScoreRow({ current_innings: "3" });
  raw.scores.push({ inning_no: "3", team_id: "9", team_runs: "20", team_wickets: "1", team_overs: "10.0" });
  assert.equal(normalized([raw]).fixtures[0].context.innings[2].teamID, "icc:1:9");
  assert.equal(normalized([testScoreRow({ current_innings: "1" })]).fixtures[0].context, undefined);
  const missing = structuredClone(raw); missing.scores.splice(1, 1);
  assert.equal(normalized([missing]).fixtures[0].context, undefined);
  const repeated = structuredClone(raw); repeated.scores[0].team_id = "9";
  assert.equal(normalized([repeated]).fixtures[0].context, undefined);
});

test("cricket overs use balls0 through5 and format bounds rather than decimal arithmetic", () => {
  const fixture = normalized([t20ScoreRow()]).fixtures[0];
  for (const team_overs of ["19.5", "20.0", "0", "0.0"]) {
    const raw = t20ScoreRow(); raw.scores[1].team_overs = team_overs;
    assert.equal(normalizeICCContext(raw, fixture).innings[1].overs, team_overs);
  }
  for (const team_overs of ["11.6", "11.9", "20.1", "500.0", "01.0", "1e1", 11.1, "11.05"]) {
    const raw = t20ScoreRow(); raw.scores[1].team_overs = team_overs;
    assert.equal(normalizeICCContext(raw, fixture), undefined);
  }
});

test("unsupported formats/superovers and malformed optional context metadata stay unavailable", () => {
  for (const changes of [{ match_type: "Unknown" }, { has_super_over: true }, { current_innings: "3" },
    { day: "2" }, { current_status_message: "<script>bad</script>" }, { current_status_message: "x".repeat(201) },
    { current_status_message: "bad\nmessage" }, { match_status: "Stumps" }]) {
    assert.equal(normalized([t20ScoreRow(changes)]).fixtures[0].context, undefined);
  }
  assert.equal(normalized([testScoreRow({ session: "4" })]).fixtures[0].context, undefined);
  assert.equal(normalized([testScoreRow({ day: "7" })]).fixtures[0].context, undefined);
  const valid = normalized([testScoreRow()]).fixtures[0];
  for (const context of [null, { ...valid.context, extra: true }, { ...valid.context, currentInnings: null },
    { ...valid.context, target: 0 }, { ...valid.context, phase: "invented" }]) {
    assert.equal(validCricketContext(context, valid), false);
  }
});

test("score-only changes advance revision while identity/status/fixture count remain unchanged", async () => {
  const before = normalized([t20ScoreRow()]);
  const first = await refreshCricketState(null, now, async () => before);
  const next = t20ScoreRow(); next.scores[1].team_runs = "89";
  const candidate = withReceipt(normalized([next]), new Date(now.getTime() + 5 * 60_000));
  const second = await refreshCricketState(first, new Date(now.getTime() + 5 * 60_000), async () => candidate);
  assert.notEqual(first.snapshot.revision, second.snapshot.revision);
  assert.equal(second.snapshot.fixtures[0].context.innings[1].runs, 89);
  for (const key of ["id", "start", "status", "format", "home", "away"]) assert.deepEqual(first.snapshot.fixtures[0][key], second.snapshot.fixtures[0][key]);
});

test("fresh same-fixture receipts without usable scores cannot renew or inherit previous context", async () => {
  const first = await refreshCricketState(null, now, async () => normalized([t20ScoreRow()]));
  const later = new Date(now.getTime() + 5 * 60_000);
  for (const scores of [undefined, [], [{ inning_no: "2", team_id: "10", team_runs: "bad", team_wickets: "5" }]]) {
    const next = withReceipt(normalized([t20ScoreRow({ scores })]), later);
    const refreshed = await refreshCricketState(first, later, async () => next);
    assert.equal(refreshed.snapshot.sourceStatus, "verified");
    assert.equal(refreshed.snapshot.fixtures[0].id, first.snapshot.fixtures[0].id);
    assert.equal(refreshed.snapshot.fixtures[0].source.observedAt, later.toISOString());
    assert.equal(refreshed.snapshot.fixtures[0].context, undefined, "No old score may acquire a new observation");
  }
});

test("failed collection and isolated identity conflict retain original score context and observation", async () => {
  const original = normalized([testScoreRow()]);
  const first = await refreshCricketState(null, now, async () => original);
  const later = new Date(now.getTime() + 5 * 60_000);
  const failed = await refreshCricketState(first, later, async () => { throw new Error("ICC upstream unavailable"); });
  assert.deepEqual(failed.snapshot.fixtures[0].context, first.snapshot.fixtures[0].context);
  assert.equal(failed.snapshot.fixtures[0].source.observedAt, now.toISOString());
  assert.equal(failed.snapshot.sourceStatus, "last-known-good");
  const changed = withReceipt(normalized([testScoreRow({ teamb_id: "99" })]), later);
  const held = await refreshCricketState(first, later, async () => changed);
  assert.equal(held.snapshot.fixtures[0].source.verification, "held");
  assert.deepEqual(held.snapshot.fixtures[0].context, first.snapshot.fixtures[0].context);
  assert.equal(held.snapshot.fixtures[0].source.observedAt, now.toISOString());
});

test("optional context budget preserves every accepted fixture and prioritizes current rows", () => {
  const template = normalized([testScoreRow({ match_ordinal: "3", match_number: "3rd Test",
    end_match_date_gmt: "10/4/2026", end_match_time_gmt: "15:30" })]).fixtures[0];
  const fixtures = Array.from({ length: 400 }, (_, index) => ({ ...template, id: `icc:${900000 + index}`,
    status: index === 399 ? "live" : "finished", context: { ...template.context, phase: index === 399 ? "stumps" : "finished",
      message: "x".repeat(200) } }));
  const snapshot = { schemaVersion: 1, complete: true, fixtures, coverage: [] };
  const bounded = boundedCricketContexts(snapshot);
  assert.equal(bounded.fixtures.length, 400);
  assert.deepEqual(bounded.fixtures.map((fixture) => fixture.id), fixtures.map((fixture) => fixture.id));
  assert.ok(bounded.fixtures.filter((fixture) => fixture.context).length < 400);
  assert.ok(bounded.fixtures[399].context);
  assert.equal(bounded.fixtures[399].context.matchOrdinal, 3);
  assert.equal(bounded.fixtures[399].context.matchEndsAt, "2026-10-04T15:30:00.000Z");
  const base = boundedCricketContexts({ ...snapshot, fixtures: fixtures.map((fixture) => ({ ...fixture, context: null })) });
  assert.ok(Buffer.byteLength(JSON.stringify(bounded)) - Buffer.byteLength(JSON.stringify(base)) <= 64 * 1024);
  const nearPayloadLimit = boundedCricketContexts({ ...snapshot, padding: "p".repeat(512 * 1024 - Buffer.byteLength(JSON.stringify(base)) - 100) });
  assert.ok(Buffer.byteLength(JSON.stringify(nearPayloadLimit)) <= 512 * 1024);
  assert.equal(nearPayloadLimit.fixtures.length, 400);
  assert.ok(fixtures.every((fixture) => fixture.context), "Budget projection must not mutate accepted input");
});

test("legacy schema1 response keeps its old contract and strips malformed optional context without new collection", async () => {
  const initial = await refreshCricketState(null, now, async () => normalized([testScoreRow()]));
  initial.nextAttemptAt = "2100-01-01T00:00:00Z";
  const storage = new Map([["cricket-registry-v1", initial]]);
  let collections = 0;
  const registry = new CricketFixtureRegistry({ storage: { get: async (key) => storage.get(key) }, waitUntil: () => {} }, {},
    { collectICC: async () => { collections++; return normalized(); } });
  const result = await (await registry.fetch(new Request("https://internal/fixtures"))).json();
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.complete, true);
  assert.equal(result.fixtures[0].context.phase, "stumps");
  assert.deepEqual(auditCricketSnapshot(result, { now: now.getTime() }).findings, []);
  storage.get("cricket-registry-v1").snapshot.fixtures[0].context = { innings: [{ number: 1, teamID: "foreign", runs: 1, wickets: 0 }] };
  const malformed = await (await registry.fetch(new Request("https://internal/fixtures"))).json();
  assert.equal(malformed.fixtures.length, 1);
  assert.equal(malformed.fixtures[0].context, undefined);
  assert.equal(collections, 0);
});
