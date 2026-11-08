import test from "node:test";
import assert from "node:assert/strict";
import { matchCoverageReceipt, matchCoverageObservations, validateMatchCoverageReceipt, MATCH_COVERAGE_SOURCE } from "./match-coverage.mjs";
import { collectSportsSource, SPORTS_SOURCES } from "../../web/workers/playback/src/sports-fixture-sources.mjs";
import { normalizeICC, parseICCPage } from "../../web/workers/playback/src/cricket-fixture-policy.mjs";
import { refreshCricketState } from "../../web/workers/playback/src/cricket-fixture-registry.mjs";
import cplFallback from "../../web/public/data/cpl-2026-fixtures.json" with { type: "json" };
import { createPolicy, emptyLedger, incidentKey } from "./incident-policy.mjs";
import { applyObservationBatch } from "./observation-batch.mjs";
import { observerPolicyOptions, EXPECTED_VERSIONS } from "./manifest.mjs";
import { collectFixtureReceipts } from "./fixture-receipts.mjs";
import { probeSources } from "./source-probes.mjs";

const NOW = Date.parse("2026-09-30T16:00:00Z"), iso = (v = NOW) => new Date(v).toISOString();
async function sports(code = "PL", overrides = {}) {
  const source = SPORTS_SOURCES.find((row) => row.id === "football-data");
  const value = await collectSportsSource(source, new Date(NOW), { FOOTBALL_DATA_API_KEY: "offline-placeholder" }, async (url) => {
    assert.equal(url.origin, "https://api.football-data.org");
    return Response.json({ filters: { dateFrom: url.searchParams.get("dateFrom"), dateTo: url.searchParams.get("dateTo"), competitions: url.searchParams.get("competitions") },
      resultSet: { count: 1 }, matches: [{ id: 111, utcDate: iso(NOW - 1800_000), status: "IN_PLAY", lastUpdated: iso(),
        competition: { code }, homeTeam: { id: 1, name: "Liverpool" }, awayTeam: { id: 2, name: "Chelsea" }, ...overrides }] });
  });
  return { schemaVersion: 1, complete: true, checkedAt: iso(), revision: "offline-factory-sports", sourceStatus: "verified", fixtures: value.fixtures,
    coverage: SPORTS_SOURCES.filter((s) => s.id !== "wnba").flatMap((s) => s.competitions.map((c) => ({ competitionId: c.id,
      competitionName: c.name, sport: c.sport, status: "covered", checkedAt: iso(),
      fixtureCount: value.fixtures.filter((f) => f.competitionId === c.id).length, pendingFixtureCount: 0, sync: { consecutiveFailures: 0 } }))) };
}
function cricket(overrides = {}, at = NOW) {
  const date = new Date(at), hour = date.getUTCHours();
  const receipt = `${date.getUTCMonth() + 1}/${date.getUTCDate()}/${date.getUTCFullYear()} ${hour % 12 || 12}:${String(date.getUTCMinutes()).padStart(2, "0")}:${String(date.getUTCSeconds()).padStart(2, "0")} ${hour < 12 ? "AM" : "PM"}`;
  const value = normalizeICC([parseICCPage({ data: { matches: [{ match_id: "270271", league_id: "1",
    match_date_gmt: "9/30/2026", match_time_gmt: "15:30", teama_id: "4", teama: "India", teamb_id: "9", teamb: "West Indies",
    series_name: "West Indies in India, 3 T20I Series, 2026", match_type: "T20I", live: true, upcoming: false,
    recent: false, is_deleted: false, ...overrides }] }, meta: { app_status_code: 1, pagination: true, count: 1,
    timestamp: { utc_time: receipt } } }, date)], date);
  return { schemaVersion: 1, complete: true, checkedAt: iso(at), revision: "offline-factory-cricket", sourceStatus: "verified", fixtures: value.fixtures,
    sync: { consecutiveFailures: 0, lastAttemptAt: iso(at), lastSuccessAt: iso(at) },
    coverage: ["cpl", "west-indies", "icc"].map((competitionId) => ({ competitionId, competitionName: competitionId, status: "covered", checkedAt: iso(at),
      fixtureCount: value.fixtures.filter((f) => f.competitionId === competitionId).length })) };
}
const csEntry = (changes = {}) => ({ id: "nuvio_sport_current", type: "tv", name: "LIVE: Liverpool vs Chelsea",
  cast: ["Liverpool", "Chelsea"], genres: ["FOOTBALL"], released: iso(NOW - 1800_000), ...changes });
const asEntry = (changes = {}) => ({ id: "plaviohdtv-sfly-streamed:football-offline", type: "tv", name: "Liverpool vs Chelsea",
  description: "Liverpool vs Chelsea\n30 Sep 2026 · 15:30 UTC", genres: ["Sports"], ...changes });
const packet = (source, rows, scope = source === "cs" ? "mixed" : "football", checkedAt = NOW) => ({ source, scope, checkedAt, catalog: { metas: rows } });
const cohort = (value, scope = "premier-league") => value.competitions.find((row) => row.scope === scope);
const evaluate = (options) => matchCoverageReceipt({ now: NOW, ...options });

test("real football normalizer fixture joins exact CS catalog as catalog-only, not playback or independence", async () => {
  const body = await sports(), value = evaluate({ sportsSnapshot: body, catalogs: [packet("cs", [csEntry()])] });
  assert.equal(cohort(value).liveFixtureCount, 1); assert.equal(cohort(value).matchedFixtureCount, 1);
  assert.equal(cohort(value).outcome, "success"); assert.equal(value.evidence, "catalog-only");
  for (const privateText of ["Liverpool", "Chelsea", "nuvio_sport", "https:", "playable", "decoded", "independent"]) {
    assert.equal(JSON.stringify(value).includes(privateText), false);
  }
  const cl = evaluate({ sportsSnapshot: await sports("CL"), catalogs: [packet("cs", [csEntry()])] });
  assert.equal(cohort(cl, "champions-league").outcome, "success");
});
test("finished/scheduled rows and stale/held/duplicate/conflicting official authority cannot create a gap or success", async () => {
  for (const status of ["FINISHED", "TIMED", "POSTPONED"]) {
    const v = evaluate({ sportsSnapshot: await sports("PL", { status }), catalogs: [packet("cs", [csEntry()])] });
    assert.equal(cohort(v).liveFixtureCount, 0); assert.equal(cohort(v).outcome, "inactive");
  }
  for (const mutate of [
    (s) => { s.checkedAt = iso(NOW - 31 * 60_000); },
    (s) => { s.fixtures[0].source.verification = "held"; },
    (s) => { s.fixtures.push(structuredClone(s.fixtures[0])); },
    (s) => { s.fixtures[0].squad.ageGroup = "u19"; },
    (s) => { s.fixtures[0].source.observedAt = iso(NOW + 6 * 60_000); },
  ]) {
    const body = await sports(); mutate(body);
    const v = evaluate({ sportsSnapshot: body, catalogs: [packet("cs", [csEntry()])] });
    assert.equal(cohort(v).outcome, "unknown"); assert.equal(cohort(v).matchedFixtureCount, 0);
  }
});
test("missing, empty, stale catalog and transport gaps mean unverifiable metadata coverage, never no-stream failure", async () => {
  const body = await sports();
  for (const catalogs of [[], [packet("cs", [])], [packet("cs", [csEntry()], "mixed", NOW - 31 * 60_000)],
    [packet("cs", [csEntry({ released: undefined })])], [packet("cs", [csEntry({ released: iso(NOW - 86_400_000) })])]]) {
    const v = evaluate({ sportsSnapshot: body, catalogs });
    assert.equal(cohort(v).outcome, "failure"); assert.equal(cohort(v).matchedFixtureCount, 0);
    const r = matchCoverageObservations(v)[0];
    assert.equal(r.failureClass, "unverified-current-coverage"); assert.equal(r.stage, "catalog-match");
  }
});
test("current AS clock-only Football/DLHD envelope cannot borrow official date or produce success", async () => {
  const body = await sports(), entry = { id: "plaviohdtv-dlhd-event", type: "tv", name: "England - League Cup : Liverpool vs Chelsea",
    genres: ["Football"], description: "Starts 15:30 (UK time) · 28 channels" };
  const v = evaluate({ sportsSnapshot: body, catalogs: [packet("as", [entry])] });
  assert.equal(cohort(v).unverifiableFixtureCount, 1); assert.equal(cohort(v).matchedFixtureCount, 0);
  assert.equal(evaluate({ sportsSnapshot: body, catalogs: [packet("as", [asEntry()])] }).competitions[0].outcome, "success");
});
test("same-ID contradictions remain vetoes, but one provider's conflict does not erase another provider's matched catalog", async () => {
  const body = await sports(), conflicts = [csEntry(), csEntry({ released: iso(NOW - 86_400_000) })];
  const failed = evaluate({ sportsSnapshot: body, catalogs: [packet("cs", conflicts)] });
  assert.equal(cohort(failed).conflictingFixtureCount, 1);
  const matched = evaluate({ sportsSnapshot: body, catalogs: [packet("cs", conflicts), packet("as", [asEntry()])] });
  assert.equal(cohort(matched).outcome, "success");
  const asConflict = evaluate({ sportsSnapshot: body, catalogs: [packet("as", [asEntry(), asEntry({ description: "bad date" })])] });
  assert.equal(cohort(asConflict).conflictingFixtureCount, 1);
});
test("AS football date spelling cannot claim a binding native's exact date contract rejects", async () => {
  const at = Date.parse("2026-09-01T16:00:00Z"), start = at - 1800_000, body = await sports();
  body.checkedAt = iso(at);
  for (const c of body.coverage) c.checkedAt = iso(at);
  Object.assign(body.fixtures[0], { start: iso(start) });
  Object.assign(body.fixtures[0].source, { observedAt: iso(at), updatedAt: iso(at) });
  const run = (day) => matchCoverageReceipt({ now: at, sportsSnapshot: body, catalogs: [packet("as", [asEntry({
    description: `Liverpool vs Chelsea\n${day} Sep 2026 · 15:30 UTC`,
  })], "football", at)] });
  assert.equal(cohort(run("1")).outcome, "success");
  assert.equal(cohort(run("01")).matchedFixtureCount, 0);
});
test("real ICC normalizer T20I fixture requires AS explicit format/ordinal/date and preserves women qualifiers", () => {
  const entry = { id: "plaviohdtv-sfly-streamed:cricket-offline", type: "tv", name: "India vs West Indies - 1st T20I",
    description: "India vs West Indies\n30 Sep 2026 · 15:30 UTC", genres: ["Cricket"] };
  const v = evaluate({ cricketSnapshot: cricket(), catalogs: [packet("as", [entry], "cricket")] });
  assert.equal(cohort(v, "west-indies").outcome, "success");
  for (const changed of [{ name: "India vs West Indies - 1st ODI" }, { description: "India vs West Indies\nStarts 15:30" },
    { name: "India vs West Indies - 1st Test Day 2" }, { name: "India Women vs West Indies Women - 1st T20I" }]) {
    const bad = evaluate({ cricketSnapshot: cricket(), catalogs: [packet("as", [{ ...entry, ...changed }], "cricket")] });
    assert.equal(cohort(bad, "west-indies").matchedFixtureCount, 0);
  }
  const women = cricket({ league_id: "10" }), title = "India Women vs West Indies Women";
  const matched = evaluate({ cricketSnapshot: women, catalogs: [packet("as", [{ ...entry, name: title + " - 1st T20I",
    description: title + "\n30 Sep 2026 · 15:30 UTC" }], "cricket")] });
  assert.equal(cohort(matched, "west-indies").outcome, "success");
});
test("real ICC contradictory competition squad evidence cannot recover a men's catalog binding", () => {
  const entry = { id: "plaviohdtv-sfly-streamed:cricket-offline", type: "tv", name: "India vs West Indies - 1st T20I",
    description: "India vs West Indies\n30 Sep 2026 · 15:30 UTC", genres: ["Cricket"] };
  for (const qualifier of ["Women", "Women's", "Ladies", "W", "U19", "Under 19", "Youth", "Academy", "Reserves", "Ｗｏｍｅｎ"]) {
    const body = cricket({ league_id: "1", series_name: `${qualifier} West Indies in India, 3 T20I Series, 2026` });
    assert.equal(body.fixtures[0].home.name, "India"); assert.equal(body.fixtures[0].away.name, "West Indies");
    const value = cohort(evaluate({ cricketSnapshot: body, catalogs: [packet("as", [entry], "cricket")] }), "west-indies");
    assert.equal(value.outcome, "unknown", qualifier); assert.equal(value.unassessedLiveFixtureCount, 1, qualifier);
    assert.equal(value.liveFixtureCount, 0, qualifier); assert.equal(value.matchedFixtureCount, 0, qualifier);
  }
  for (const [league_id, qualifier, suffix] of [["10", "Women", "Women"], ["9", "Under 19", "U19"]]) {
    const body = cricket({ league_id, series_name: `${qualifier} West Indies in India, 3 T20I Series, 2026` });
    const title = `India ${suffix} vs West Indies ${suffix}`;
    const value = cohort(evaluate({ cricketSnapshot: body, catalogs: [packet("as", [{ ...entry,
      name: title + " - 1st T20I", description: title + "\n30 Sep 2026 · 15:30 UTC" }], "cricket")] }), "west-indies");
    assert.equal(value.outcome, "success", qualifier); assert.equal(value.matchedFixtureCount, 1, qualifier);
  }
});
test("unsupported AS formats, missing Test phase, Stumps and later Test days cannot invent active coverage", () => {
  for (const raw of [{ match_type: "ODI" }, { match_type: "Test" }]) {
    const v = evaluate({ cricketSnapshot: cricket(raw), catalogs: [] });
    assert.equal(cohort(v, "west-indies").outcome, "unknown");
  }
  for (const context of [{ phase: "stumps", day: 1 }, { phase: "in-play", day: 2 }]) {
    const body = cricket({ match_type: "Test" }); body.fixtures[0].context = context;
    assert.equal(cohort(evaluate({ cricketSnapshot: body }), "west-indies").outcome, "unknown");
  }
});
test("actual ICC context normalization admits explicit initial Test play without inventing a later day", () => {
  // Replay admitted score/status field shapes in the fixed offline harness.
  // This validates the monitor contract, not current-live source qualification.
  const body = cricket({ match_type: "Test", series_name: "West Indies in India, 1st Test Series, 2026",
    current_innings: "1", day: "1", session: "1", match_status: "Play In Progress", match_display_status: "Live",
    scores: [{ inning_no: "1", team_id: "4", team_runs: "90", team_wickets: "2", team_overs: "20.0" }] });
  assert.equal(body.fixtures[0].context.phase, "in-play"); assert.equal(body.fixtures[0].context.day, 1);
  const entry = { id: "plaviohdtv-sfly-streamed:cricket-offline", type: "tv", name: "India vs West Indies - 1st Test Day 1",
    description: "India vs West Indies\n30 Sep 2026 · 15:30 UTC", genres: ["Cricket"] };
  const receipt = evaluate({ cricketSnapshot: body, catalogs: [packet("as", [entry], "cricket")] });
  assert.equal(cohort(receipt, "west-indies").outcome, "success");
  const cs = csEntry({ name: "India vs West Indies", cast: ["India", "West Indies"], genres: ["CRICKET"],
    description: "🏆 League: 1st Test Day1" });
  assert.equal(cohort(evaluate({ cricketSnapshot: body, catalogs: [packet("cs", [cs])] }), "west-indies").outcome, "success");
  for (const phase of ["stumps", "break", "innings-break", "lunch", "tea", "interrupted"]) {
    const paused = structuredClone(body); paused.fixtures[0].context.phase = phase;
    const value = cohort(evaluate({ cricketSnapshot: paused, catalogs: [packet("cs", [cs]), packet("as", [entry], "cricket")] }), "west-indies");
    assert.equal(value.outcome, "unknown", phase); assert.equal(value.matchedFixtureCount, 0, phase);
    assert.equal(value.unassessedLiveFixtureCount, 1, phase);
  }
  for (const name of ["1st T20I", "1st test", "1st Test Day 2", "1st Test and 2nd Test"]) {
    const contradictory = structuredClone(body); contradictory.fixtures[0].competitionName = name;
    assert.equal(cohort(evaluate({ cricketSnapshot: contradictory, catalogs: [packet("as", [entry], "cricket")] }),
      "west-indies").matchedFixtureCount, 0);
  }
});
test("real ICC current fixture binds already-read mixed CS cricket, with exact dated mismatch remaining unknown", () => {
  const at = Date.parse("2026-09-30T07:30:00Z"), body = cricket({ match_time_gmt: "07:00" }, at);
  const row = csEntry({ id: "nuvio_sport_cricket_contract", name: "India vs West Indies", cast: ["India", "West Indies"], genres: ["CRICKET"],
    released: "2026-09-30T07:00:00Z", description: "🏆 League: T20 International\n📅 Category: CRICKET" });
  const run = (rows, snapshot = body) => cohort(matchCoverageReceipt({ cricketSnapshot: snapshot,
    catalogs: [packet("cs", [csEntry(), ...rows], "mixed", at)], now: at }), "west-indies");
  assert.equal(run([row]).outcome, "success"); assert.equal(run([row]).matchedFixtureCount, 1);
  for (const rows of [[], [{ ...row, released: "2026-09-30T07:30:00Z" }], [{ ...row, released: undefined }]]) {
    const value = run(rows); assert.equal(value.outcome, "unknown"); assert.equal(value.monitorLimitedFixtureCount, 1);
    assert.equal(value.matchedFixtureCount, 0); assert.equal(value.monitorScope, "cs-as-cricket-catalog-bindings");
  }
  const conflict = run([row, { ...row, released: "2026-09-30T07:30:00Z" }]);
  assert.equal(conflict.conflictingFixtureCount, 1); assert.equal(conflict.outcome, "unknown");
  for (const mutate of [(s) => { s.fixtures[0].source.verification = "held"; },
    (s) => { s.fixtures[0].source.observedAt = iso(at - 31 * 60_000); },
    (s) => { s.fixtures.push(structuredClone(s.fixtures[0])); },
    (s) => { s.fixtures[0].start = iso(at + 6 * 60_000); },
    (s) => { s.fixtures[0].competitionName = "Women's T20I Series"; }]) {
    const invalid = structuredClone(body); mutate(invalid);
    assert.equal(run([row], invalid).outcome, "unknown"); assert.equal(run([row], invalid).matchedFixtureCount, 0);
  }
  for (const change of [{ live: false, upcoming: true }, { live: false, recent: true }]) {
    assert.equal(run([row], cricket({ match_time_gmt: "07:00", ...change }, at)).outcome, "inactive");
  }
});
test("CS ODI/T10 capability is source-local and never extends the AS contract", () => {
  for (const [match_type, league] of [["ODI", "One Day International"], ["T10", "T10 International"]]) {
    const body = cricket({ match_type, series_name: `${match_type} Series` });
    const row = csEntry({ name: "India vs West Indies", cast: ["India", "West Indies"], genres: ["CRICKET"],
      description: `🏆 League: ${league}` });
    assert.equal(cohort(evaluate({ cricketSnapshot: body, catalogs: [packet("cs", [row])] }), "west-indies").outcome, "success");
    const as = { id: "plaviohdtv-sfly-streamed:cricket-offline", type: "tv", name: "India vs West Indies - 1st T20I",
      description: "India vs West Indies\n30 Sep 2026 · 15:30 UTC", genres: ["Cricket"] };
    assert.equal(cohort(evaluate({ cricketSnapshot: body, catalogs: [packet("as", [as], "cricket")] }), "west-indies").outcome, "unknown");
  }
});
test("real registry CPL schedule rows stay non-live despite generic channel or LIVE catalog text", async () => {
  const at = new Date("2026-08-07T22:00:00Z"), stamp = at.toISOString();
  const empty = normalizeICC([parseICCPage({ data: { matches: [] }, meta: { app_status_code: 1, pagination: true, count: 0,
    timestamp: { utc_time: "8/7/2026 10:00:00 PM" } } }, at)], at);
  const { snapshot } = await refreshCricketState(null, at, async () => empty,
    async () => Response.json({ ...cplFallback, checkedAt: stamp, sourceStatus: "verified" }));
  assert.ok(snapshot.fixtures.length > 0); assert.ok(snapshot.fixtures.every((f) => f.status === "scheduled"));
  const first = snapshot.fixtures[0], row = csEntry({ name: `LIVE: ${first.home.name} vs ${first.away.name}`,
    cast: [first.home.name, first.away.name], released: first.start, genres: ["CRICKET"], description: "🏆 League: T20" });
  const value = cohort(matchCoverageReceipt({ cricketSnapshot: snapshot, catalogs: [packet("cs", [row], "mixed", at.getTime())], now: at.getTime() }), "cpl");
  assert.equal(value.outcome, "inactive"); assert.equal(value.liveFixtureCount, 0); assert.equal(value.matchedFixtureCount, 0);
});
test("stable aggregate incidents exclude changing counts; empty/unknown cohorts cannot manufacture recovery", async () => {
  const options = observerPolicyOptions();
  if (!options.admittedSources.some((s) => s.source === MATCH_COVERAGE_SOURCE)) options.admittedSources.push({ source: MATCH_COVERAGE_SOURCE,
    stages: ["catalog-match"], activation: "active", expected: EXPECTED_VERSIONS });
  const policy = createPolicy({ ...options, windowMs: 1000, failureWindows: 2, recoveryWindows: 2 });
  let state = emptyLedger(policy), key;
  for (let n = 0; n < 2; n++) {
    const v = matchCoverageReceipt({ sportsSnapshot: await sports(), now: NOW + n * 1000 });
    const r = matchCoverageObservations(v)[0]; key = incidentKey(r);
    state = applyObservationBatch(state, [r], policy, NOW + n * 1000).state;
  }
  assert.equal(state.incidents[key].state, "confirmed");
  const empty = await sports(); empty.fixtures = [];
  state = applyObservationBatch(state, [matchCoverageObservations(matchCoverageReceipt({ sportsSnapshot: empty, now: NOW + 2000 }))[0]], policy, NOW + 2000).state;
  assert.equal(state.incidents[key].state, "confirmed"); assert.equal(state.incidents[key].successCount, 0);
  for (let n = 3; n < 5; n++) {
    const r = matchCoverageObservations(matchCoverageReceipt({ sportsSnapshot: await sports(), catalogs: [packet("cs", [csEntry()])], now: NOW + n * 1000 }))[0];
    assert.equal(incidentKey(r), key); state = applyObservationBatch(state, [r], policy, NOW + n * 1000).state;
  }
  assert.equal(state.incidents[key].state, "resolved");
});
test("durable aggregate validator rejects raw identity/URL additions, wrong scope, invalid counts and oversize", async () => {
  const base = evaluate({ sportsSnapshot: await sports() });
  for (const mutate of [(x) => { x.competitions[0].fixtureID = "private"; }, (x) => { x.url = "https://private.invalid"; },
    (x) => { x.competitions[0].scope = "other"; }, (x) => { x.competitions[0].matchedFixtureCount = -1; },
    (x) => { x.competitions[0].liveFixtureCount = 1.5; }, (x) => { x.competitions[0].outcome = "success"; },
    (x) => { x.competitions[0].outcome = "inactive"; }, (x) => { x.competitions[2].outcome = "failure"; },
    (x) => { x.competitions[0].monitorLimitedFixtureCount = 1; }]) {
    const v = structuredClone(base); mutate(v); assert.throws(() => validateMatchCoverageReceipt(v));
  }
});
test("collector callbacks reuse exactly existing metadata requests and contain no delivery fetch", async () => {
  const body = await sports(), cricketBody = cricket(), packets = [], calls = [];
  const manifest = { id: "community.nuvio.live-sports", version: "1", resources: ["catalog", "stream"], catalogs: [{ type: "tv", id: "nuvio_sports_live" }] };
  const asManifest = { id: "community.plaviohd.private", version: "1.9.98", types: ["tv"], resources: ["catalog", { name: "stream", types: ["tv"], idPrefixes: ["plaviohdtv-"] }],
    catalogs: [{ type: "tv", id: "plaviohd-football" }, { type: "tv", id: "plaviohd-cricket" }] };
  const request = async (raw) => {
    const url = new URL(raw); calls.push(url.pathname); assert.ok(!url.pathname.includes("/stream/") && !url.pathname.includes(".m3u8"));
    if (url.pathname === "/health") return Response.json({ service: "fotty-playback", sourceVersion: EXPECTED_VERSIONS.deploymentRevision,
      sportsFixtureServiceEnabled: true, cricketFixtureRegistryConfigured: true });
    if (url.pathname === "/api/sports/fixtures") return Response.json(body);
    if (url.pathname === "/api/cricket/fixtures") return Response.json(cricketBody);
    if (url.hostname === "nuviosports.xyz") return Response.json(url.pathname === "/manifest.json" ? manifest : { metas: [] });
    if (url.hostname === "addon.plavio.site") return Response.json(url.pathname === "/manifest.json" ? asManifest : { metas: [] });
    if (url.hostname === "www.score808live.tv") return new Response('<div class="elfsight-app-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"></div>', { headers: { "Content-Type": "text/html" } });
    return Response.json([]);
  };
  let returnedCricket;
  await collectFixtureReceipts({ request, now: NOW, onCricketSnapshot: (v) => { returnedCricket = v; } });
  await probeSources({ request, now: NOW, onCatalog: (p) => packets.push(p) });
  assert.deepEqual(returnedCricket, cricketBody); assert.equal(calls.length, 12);
  assert.deepEqual(packets.map((p) => [p.source, p.scope]), [["cs", "mixed"], ["as", "football"], ["as", "cricket"]]);
});
