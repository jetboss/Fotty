import test from "node:test";
import assert from "node:assert/strict";
import { admitSportsCollection, admitSportsCollectionIsolated, fixtureInstant, nextSportsRefresh, sportsRevision,
  sportsSnapshotIdentity } from "./sports-fixture-policy.mjs";
import { assembleSportsSnapshot, refreshSportsSource, sourceCoverage, SportsFixtureRegistry, sportsFailureInfo } from "./sports-fixture-registry.mjs";

const now = new Date("2026-09-30T22:00:00.000Z");
const descriptor = { id: "nba", sport: "basketball", supported: true, competitions: [{ id: "nba", name: "NBA" }] };
function fixture(changes = {}, at = now) {
  const participantPrefix = changes.id || "nba";
  return { id: "sports-fixture:nba:1", sport: "basketball", start: "2026-09-30T23:00:00.000Z", status: "scheduled",
    eventKind: "match", title: "Alpha vs Beta", competitionId: "nba", competitionName: "NBA",
    participants: [{ id: `${participantPrefix}:1`, name: "Alpha", role: "home" }, { id: `${participantPrefix}:2`, name: "Beta", role: "away" }],
    squad: { gender: "men", ageGroup: "senior" }, source: { name: "ESPN", url: "https://www.espn.com/nba/scoreboard", observedAt: at.toISOString() }, ...changes };
}
function collection(fixtures = [fixture()], at = now) { return { fixtures, pendingFixtureCount: 0, observedAt: at.toISOString() }; }
const footballDescriptor = { id: "football-data", adapter: "football-data", sport: "football", supported: true,
  competitions: [
    { id: "premier-league", name: "Premier League" },
    { id: "champions-league", name: "UEFA Champions League" },
    { id: "la-liga", name: "La Liga" },
    { id: "serie-a", name: "Serie A" },
    { id: "bundesliga", name: "Bundesliga" },
    { id: "ligue-1", name: "Ligue 1" },
  ] };
const oldFootballDescriptor = { ...footballDescriptor, competitions: footballDescriptor.competitions.slice(0, 2) };
function footballCollection(source, fixtures = [], at = now, pending = {}) {
  const pendingByCompetition = Object.fromEntries(source.competitions.map(({ id }) => [id, pending[id] || 0]));
  return { fixtures, pendingByCompetition, pendingFixtureCount: Object.values(pendingByCompetition).reduce((total, count) => total + count, 0),
    observedAt: at.toISOString() };
}
function footballFixture(competitionId, id, changes = {}, at = now) {
  return fixture({ id: `sports-fixture:${competitionId}:${id}`, sport: "football", competitionId,
    competitionName: footballDescriptor.competitions.find((row) => row.id === competitionId).name, ...changes }, at);
}
function heldCollection(value) {
  return { ...value, fixtures: value.fixtures.map((row) => ({ ...row, source: { ...row.source, verification: "held" } })) };
}

test("valid match collection requires real identities and UTC", () => {
  assert.equal(admitSportsCollection(collection(), null, descriptor, now).accepted.fixtures.length, 1);
  assert.throws(() => fixtureInstant("2026-02-30T10:00:00.000Z"));
  assert.throws(() => admitSportsCollection(collection([fixture({ start: "2026-09-30T23:00:00-04:00" })]), null, descriptor, now));
});
test("wrong competition, placeholder, squad, duplicate identity are rejected", () => {
  for (const row of [fixture({ competitionId: "wnba" }), fixture({ squad: { gender: "men", ageGroup: "youth" } }),
    fixture({ participants: [{ id: "1", name: "TBD" }, { id: "2", name: "Beta" }] })]) {
    assert.throws(() => admitSportsCollection(collection([row]), null, descriptor, now));
  }
  assert.throws(() => admitSportsCollection(collection([fixture(), fixture()]), null, descriptor, now));
});
test("explicit pending receipts require every scoped competition and matching nonnegative counts", () => {
  const valid = footballCollection(footballDescriptor, [], now, { "la-liga": 2, "ligue-1": 1 });
  assert.deepEqual(admitSportsCollection(valid, null, footballDescriptor, now).accepted.pendingByCompetition, valid.pendingByCompetition);
  for (const pendingByCompetition of [null, [], { nba: 3 }, { ...valid.pendingByCompetition, mls: 0 },
    { ...valid.pendingByCompetition, "la-liga": -1 }, { ...valid.pendingByCompetition, "la-liga": 1.5 },
    { ...valid.pendingByCompetition, "la-liga": 10001 }, Object.fromEntries(oldFootballDescriptor.competitions.map(({ id }) => [id, 0]))]) {
    assert.throws(() => admitSportsCollection({ ...valid, pendingByCompetition }, null, footballDescriptor, now), /Pending competition scope/);
  }
  assert.throws(() => admitSportsCollection({ ...valid, pendingFixtureCount: 4 }, null, footballDescriptor, now), /Pending competition count/);
  assert.throws(() => admitSportsCollection({ ...valid, pendingByCompetition: undefined }, null, footballDescriptor, now), /Pending competition scope/);
  assert.equal(admitSportsCollection({ ...collection(), pendingFixtureCount: 2 }, null, descriptor, now).accepted.pendingFixtureCount, 2);
});
test("old PL/CL receipts leave added football lanes unverified until a complete six-league receipt", async () => {
  const previous = await refreshSportsSource(null, oldFootballDescriptor, now, async () => footballCollection(oldFootballDescriptor));
  const oldCoverage = sourceCoverage(footballDescriptor, previous, now);
  assert.deepEqual(oldCoverage.map(({ status }) => status), ["covered", "covered", "unavailable", "unavailable", "unavailable", "unavailable"]);
  for (const lane of oldCoverage.slice(2)) {
    assert.equal(lane.checkedAt, null);
    assert.equal(lane.sync.lastSuccessAt, null);
    assert.equal(lane.fixtureCount, 0);
    assert.equal(lane.pendingFixtureCount, 0);
  }
  const before = await assembleSportsSnapshot([footballDescriptor], new Map([[footballDescriptor.id, previous]]), now);
  assert.equal(before.sourceStatus, "partial");
  const later = new Date(now.getTime() + 60_000);
  const refreshed = await refreshSportsSource(previous, footballDescriptor, later, async () => footballCollection(footballDescriptor, [], later));
  const after = await assembleSportsSnapshot([footballDescriptor], new Map([[footballDescriptor.id, refreshed]]), later);
  assert.equal(after.sourceStatus, "verified");
  assert.equal(after.coverage.filter(({ status }) => status === "covered").length, 6);
  assert.ok(after.coverage.every(({ checkedAt }) => checkedAt === later.toISOString()));
  assert.notEqual(after.revision, before.revision);
});
test("legacy single-lane receipts retain coverage while invalid scope counts cannot establish it", () => {
  const legacy = { accepted: { ...collection(), pendingFixtureCount: 2 }, consecutiveFailures: 0 };
  const coverage = sourceCoverage(descriptor, legacy, now)[0];
  assert.equal(coverage.status, "covered");
  assert.equal(coverage.pendingFixtureCount, 2);
  for (const pendingByCompetition of [null, [], { nba: "0" }, { nba: -1 }, { nba: 1.5 }]) {
    const invalid = sourceCoverage(descriptor, { ...legacy, accepted: { ...legacy.accepted, pendingByCompetition } }, now)[0];
    assert.equal(invalid.status, "unavailable");
    assert.equal(invalid.checkedAt, null);
    assert.equal(invalid.pendingFixtureCount, 0);
  }
});
test("failed scope admission preserves the original two-league receipt", async () => {
  const previous = await refreshSportsSource(null, oldFootballDescriptor, now, async () => footballCollection(oldFootballDescriptor, [], now,
    { "premier-league": 1, "champions-league": 2 }));
  const later = new Date(now.getTime() + 60_000);
  const failed = await refreshSportsSource(previous, footballDescriptor, later, async () => footballCollection(oldFootballDescriptor, [], later));
  assert.deepEqual(failed.accepted, heldCollection(previous.accepted));
  assert.equal(failed.failure.stage, "admission");
  assert.equal(failed.failure.code, "scope-mismatch");
  assert.equal(failed.consecutiveFailures, 1);
  assert.ok(sourceCoverage(footballDescriptor, failed, later).slice(2).every(({ checkedAt }) => checkedAt === null));
});
test("non-team tournament retains its title without invented participants", () => {
  const golf = { ...descriptor, sport: "golf", competitions: [{ id: "pga", name: "PGA" }] };
  const row = fixture({ id: "sports-fixture:pga:99", sport: "golf", competitionId: "pga", competitionName: "PGA", eventKind: "tournament", title: "Tour Championship", participants: [] });
  assert.equal(admitSportsCollection(collection([row]), null, golf, now).accepted.fixtures[0].title, "Tour Championship");
});
test("vanishing active multi-day tournament remains a conflict, not empty success", () => {
  const golf = { ...descriptor, sport: "golf", competitions: [{ id: "pga", name: "PGA" }] };
  const row = fixture({ id: "sports-fixture:pga:99", sport: "golf", competitionId: "pga", competitionName: "PGA", eventKind: "tournament", title: "Tour Championship", participants: [],
    status: "live", start: "2026-09-26T12:00:00.000Z" });
  const old = admitSportsCollection(collection([row]), null, golf, now).accepted;
  assert.throws(() => admitSportsCollection(collection([]), old, golf, now));
});
test("future live and stale publisher live receipts cannot renew authority", () => {
  assert.throws(() => admitSportsCollection(collection([fixture({ status: "live" })]), null, descriptor, now));
  const row = fixture({ start: "2026-09-30T21:00:00.000Z", status: "live", source: { ...fixture().source, updatedAt: "2026-09-30T20:00:00.000Z" } });
  assert.throws(() => admitSportsCollection(collection([row]), null, descriptor, now));
  assert.throws(() => admitSportsCollection(collection([fixture({ status: "finished", start: "2026-10-01T12:00:00.000Z" })]), null, descriptor, now));
});
test("failure preserves accepted rows and receipts independently", async () => {
  const previous = await refreshSportsSource(null, descriptor, now, async () => collection());
  const later = new Date(now.getTime() + 60_000);
  const failed = await refreshSportsSource(previous, descriptor, later, async () => { throw new Error("private source details"); });
  assert.equal(failed.accepted.observedAt, now.toISOString());
  assert.equal(failed.consecutiveFailures, 1);
  assert.equal(sourceCoverage(descriptor, failed)[0].status, "unavailable");
  assert.equal(JSON.stringify(failed).includes("private source details"), false);
});
test("failure diagnostics separate collection/admission and never disclose exception text", async () => {
  const error = Object.assign(new Error("Sports schedule upstream unavailable"), { fixtureHTTPStatus: 403 });
  const failed = await refreshSportsSource(null, descriptor, now, async () => { throw error; });
  assert.deepEqual(failed.failure, { stage: "collection", code: "upstream-unavailable", kind: "Error", httpStatus: 403 });
  const invalid = await refreshSportsSource(null, descriptor, now, async () => ({ ...collection(), observedAt: "private value" }));
  assert.equal(invalid.failure.stage, "admission");
  assert.equal(JSON.stringify(invalid).includes("private value"), false);
  assert.deepEqual(sportsFailureInfo({ name: "private secret", message: "token=private secret", fixtureHTTPStatus: "private secret" }, "unexpected"),
    { stage: "collection", code: "validation-or-runtime-failure", kind: "Error" });
  const recovered = await refreshSportsSource(failed, descriptor, now, async () => collection());
  assert.equal(recovered.failure, undefined);
  const correction = await refreshSportsSource({ ...recovered, failure: failed.failure }, descriptor, now,
    async () => collection([fixture({ start: "2026-10-01T00:00:00.000Z" })]));
  assert.ok(correction.conflict);
  assert.equal(correction.failure, null);
  assert.equal(sourceCoverage(descriptor, correction, now)[0].sync.failure, undefined);
});
test("vanishing scheduled row and terminal rollback preserve accepted snapshot", async () => {
  const previous = await refreshSportsSource(null, descriptor, now, async () => collection());
  const empty = await refreshSportsSource(previous, descriptor, now, async () => collection([]));
  assert.equal(empty.consecutiveFailures, 1);
  assert.equal(empty.accepted.fixtures.length, 1);
  const finished = { accepted: collection([fixture({ status: "finished" })]) };
  assert.throws(() => admitSportsCollection(collection(), finished.accepted, descriptor, now));
});
test("live-to-scheduled correction is not accepted on the first observation", () => {
  const old = collection([fixture({ status: "live", start: "2026-09-30T21:00:00.000Z" })]);
  const candidate = collection([fixture({ status: "scheduled", start: "2026-09-30T21:00:00.000Z" })]);
  assert.ok(admitSportsCollection(candidate, old, descriptor, now).conflict);
});
test("missed cron cannot label expired accepted receipts healthy", async () => {
  const body = await assembleSportsSnapshot([descriptor], new Map([["nba", { accepted: collection(), consecutiveFailures: 0 }]]), new Date(now.getTime() + 11 * 86400_000));
  assert.equal(body.coverage[0].status, "unavailable");
  assert.equal(body.sourceStatus, "partial");
  assert.equal(body.fixtures[0].source.observedAt, now.toISOString());
});
test("missed kickoff polling cannot become healthy when the fixture ages past its hot window", () => {
  const received = new Date("2026-09-30T19:50:00.000Z");
  const later = new Date("2026-09-30T21:00:00.000Z");
  const old = { accepted: collection([fixture({ start: "2026-09-30T20:00:00.000Z" }, received)], received), consecutiveFailures: 0 };
  assert.equal(sourceCoverage(descriptor, old, later)[0].status, "unavailable");
});
test("official time correction requires repeat separated source observations", async () => {
  const previous = await refreshSportsSource(null, descriptor, now, async () => collection());
  const later = new Date(now.getTime() + 5 * 60_000);
  const changed = fixture({ start: "2026-10-01T00:00:00.000Z" }, later);
  const first = await refreshSportsSource(previous, descriptor, later, async () => collection([changed], later));
  assert.equal(first.accepted.fixtures[0].start, previous.accepted.fixtures[0].start);
  assert.equal(first.conflict.observedAt, later.toISOString());
  const repeatedAt = new Date(later.getTime() + 5 * 60_000);
  const repeated = await refreshSportsSource(first, descriptor, repeatedAt, async () => collection([fixture({ start: changed.start }, repeatedAt)], repeatedAt));
  assert.equal(repeated.accepted.fixtures[0].start, changed.start);
  assert.equal(repeated.consecutiveFailures, 0);
  assert.equal(repeated.accepted.fixtures[0].source.correctionConfirmedAt, repeatedAt.toISOString());
  const anotherAt = new Date(repeatedAt.getTime() + 5 * 60_000);
  const another = await refreshSportsSource(repeated, descriptor, anotherAt, async () => collection([fixture({ start: changed.start }, anotherAt)], anotherAt));
  assert.equal(another.accepted.fixtures[0].source.correctionConfirmedAt, repeatedAt.toISOString());
});
test("unsupported source remains explicit, cannot look like covered empty schedule", async () => {
  const unsupported = { id: "boxing", sport: "fight", supported: false, reason: "No verified UTC source", competitions: [{ id: "boxing", name: "Boxing" }] };
  let calls = 0;
  await refreshSportsSource(null, unsupported, now, async () => { calls++; });
  assert.equal(calls, 0);
  const body = await assembleSportsSnapshot([descriptor, unsupported], new Map([["nba", { accepted: collection(), consecutiveFailures: 0 }]]), now);
  assert.equal(body.coverage[1].status, "unsupported");
  assert.equal(body.coverage[1].checkedAt, null);
  assert.equal(body.coverage[1].pendingFixtureCount, 0);
});
test("independent coverage failures affect revisions, check receipts do not", async () => {
  const good = { accepted: collection(), consecutiveFailures: 0 };
  const a = await assembleSportsSnapshot([descriptor], new Map([["nba", good]]), now);
  const later = new Date(now.getTime() + 5 * 60_000);
  const b = await assembleSportsSnapshot([descriptor], new Map([["nba", { accepted: collection([fixture({}, later)], later), consecutiveFailures: 0 }]]), later);
  assert.equal(a.revision, b.revision);
  const c = await assembleSportsSnapshot([descriptor], new Map([["nba", { ...good, consecutiveFailures: 1 }]]), now);
  assert.notEqual(a.revision, c.revision);
  assert.equal(await sportsRevision([]), await sportsRevision([]));
});
test("adaptive refresh is five minutes live, fifteen within a day, four hours quiet", () => {
  assert.equal(nextSportsRefresh([fixture({ status: "live", start: "2026-09-30T21:00:00.000Z" })], now), 300_000);
  assert.equal(nextSportsRefresh([fixture()], now), 900_000);
  assert.equal(nextSportsRefresh([], now), 14_400_000);
});
test("durable object serializes concurrent refresh, cold GET does not wait for scrape", async () => {
  const data = new Map(); const waits = []; let calls = 0;
  const state = { storage: { async get(key) { return data.get(key); }, async put(key, value) { data.set(key, value); } }, waitUntil(value) { waits.push(value); } };
  const registry = new SportsFixtureRegistry(state, {}, { descriptors: [descriptor], collect: async (_source, instant) => { calls++; return collection([fixture({ start: instant.toISOString() }, instant)], instant); } });
  const cold = await registry.fetch(new Request("https://sports-registry.invalid/fixtures?source=nba"));
  assert.equal((await cold.json()).accepted, undefined);
  await Promise.all(waits);
  await Promise.all([registry.fetch(new Request("https://sports-registry.invalid/refresh?source=nba", { method: "POST" })), registry.fetch(new Request("https://sports-registry.invalid/refresh?source=nba", { method: "POST" }))]);
  assert.equal(calls, 1);
});
test("scope migration attempts immediately once and failed retries retain data with five-minute backoff", async () => {
  const received = new Date(Date.now() - 60_000);
  const match = fixture({ id: "sports-fixture:premier-league:1", sport: "football", competitionId: "premier-league", competitionName: "Premier League",
    start: new Date(Date.now() + 60 * 60_000).toISOString() }, received);
  const previous = await refreshSportsSource(null, oldFootballDescriptor, received,
    async () => footballCollection(oldFootballDescriptor, [match], received));
  assert.ok(Date.parse(previous.nextAttemptAt) > Date.now());
  const data = new Map([["sports-source-v1", previous]]); const waits = []; let calls = 0;
  const state = { storage: { async get(key) { return data.get(key); }, async put(key, value) { data.set(key, value); } },
    waitUntil(value) { waits.push(value); } };
  const options = { descriptors: [footballDescriptor], collect: async () => { calls++; throw new Error("unavailable"); } };
  const registry = new SportsFixtureRegistry(state, {}, options);
  const request = () => new Request("https://sports-registry.invalid/refresh?source=football-data", { method: "POST" });
  const response = await registry.fetch(request());
  assert.equal((await response.json()).ok, false);
  assert.equal(calls, 1);
  const failed = data.get("sports-source-v1");
  assert.deepEqual(failed.accepted, heldCollection(previous.accepted));
  assert.equal(Date.parse(failed.nextAttemptAt) - Date.parse(failed.lastAttemptAt), 300_000);
  await Promise.all([registry.fetch(request()), registry.fetch(request())]);
  const restarted = new SportsFixtureRegistry(state, {}, options);
  await restarted.fetch(request());
  const cached = await restarted.fetch(new Request("https://sports-registry.invalid/fixtures?source=football-data"));
  assert.deepEqual((await cached.json()).accepted, heldCollection(previous.accepted));
  assert.equal(calls, 1);
  assert.equal(waits.length, 0);
  assert.equal(data.get("sports-source-v1").lastAttemptAt, failed.lastAttemptAt);
  data.set("sports-source-v1", { ...failed, nextAttemptAt: new Date(Date.now() - 1).toISOString() });
  await restarted.fetch(request());
  assert.equal(calls, 2);
  assert.deepEqual(data.get("sports-source-v1").accepted, heldCollection(previous.accepted));
});

test("one missing Ligue 1 fixture cannot stop current PL/CL updates or renew disputed receipts", async () => {
  const pl = footballFixture("premier-league", "1", { status: "live", start: "2026-09-30T21:00:00.000Z" });
  const disputed = footballFixture("ligue-1", "2", { start: "2026-10-02T20:00:00.000Z" });
  const old = await refreshSportsSource(null, footballDescriptor, now,
    async () => footballCollection(footballDescriptor, [pl, disputed]));
  const later = new Date(now.getTime() + 5 * 60_000);
  const cl = footballFixture("champions-league", "3", { status: "live", start: now.toISOString() }, later);
  const result = await refreshSportsSource(old, footballDescriptor, later, async () => footballCollection(footballDescriptor,
    [footballFixture("premier-league", "1", { status: "finished", start: pl.start }, later), cl], later));
  const byId = new Map(result.accepted.fixtures.map((row) => [row.id, row]));
  assert.equal(byId.get(pl.id).status, "finished");
  assert.equal(byId.get(cl.id).source.verification, "verified");
  assert.deepEqual(byId.get(disputed.id), heldCollection({ fixtures: [disputed] }).fixtures[0]);
  assert.equal(result.failure.code, "accepted-fixture-missing");
  assert.equal(result.consecutiveFailures, 1);
  const body = await assembleSportsSnapshot([footballDescriptor], new Map([[footballDescriptor.id, result]]), later);
  assert.equal(body.sourceStatus, "partial");
  assert.equal(body.checkedAt, later.toISOString());
  assert.deepEqual(body.coverage.filter((row) => row.status === "unavailable").map((row) => row.competitionId), ["ligue-1"]);
  assert.equal(body.coverage.find((row) => row.competitionId === "ligue-1").checkedAt, now.toISOString());
  assert.equal(body.coverage.find((row) => row.competitionId === "premier-league").checkedAt, later.toISOString());
});

test("same-cohort terminal rollback is held while another live record advances", async () => {
  const oldRow = fixture({ status: "finished", start: "2026-09-30T21:00:00.000Z" });
  const old = await refreshSportsSource(null, descriptor, now, async () => collection([oldRow]));
  const later = new Date(now.getTime() + 5 * 60_000);
  const live = fixture({ id: "sports-fixture:nba:2", status: "live", start: now.toISOString() }, later);
  const result = await refreshSportsSource(old, descriptor, later, async () => collection([
    fixture({ status: "scheduled", start: oldRow.start }, later), live], later));
  assert.deepEqual(result.accepted.fixtures.find((row) => row.id === oldRow.id), heldCollection({ fixtures: [oldRow] }).fixtures[0]);
  assert.equal(result.accepted.fixtures.find((row) => row.id === live.id).source.verification, "verified");
  assert.equal(result.failure.code, "terminal-rollback");
  const body = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, result]]), later);
  assert.equal(body.coverage[0].status, "unavailable");
  assert.equal(body.coverage[0].checkedAt, now.toISOString());
  assert.equal(body.checkedAt, later.toISOString());
});

test("a changed opaque ID cannot resurrect exact finished/cancelled facts as scheduled/live", async () => {
  for (const oldStatus of ["finished", "cancelled"]) for (const newStatus of ["scheduled", "live"]) {
    const original = fixture({ id: "sports-fixture:nba:123", status: oldStatus, start: "2026-09-30T21:00:00.000Z" });
    const other = fixture({ id: "sports-fixture:nba:7", status: "live", start: now.toISOString() });
    const old = await refreshSportsSource(null, descriptor, now, async () => collection([original, other]));
    const later = new Date(now.getTime() + 300_000);
    const replacement = fixture({ id: "sports-fixture:nba:456", status: newStatus, start: original.start,
      participants: original.participants }, later);
    const rows = [replacement, fixture({ id: other.id, status: "live", start: other.start }, later)];
    assert.throws(() => admitSportsCollection(collection(rows, later), old.accepted, descriptor, later), /Terminal fixture status regressed/);
    const result = await refreshSportsSource(old, descriptor, later, async () => collection(rows, later));
    assert.deepEqual(result.accepted.fixtures.find((row) => row.id === original.id), heldCollection({ fixtures: [original] }).fixtures[0]);
    assert.equal(result.accepted.fixtures.some((row) => row.id === replacement.id), false);
    assert.equal(result.accepted.fixtures.find((row) => row.id === other.id).source.verification, "verified");
    assert.equal(result.failure.code, "terminal-rollback");
    assert.equal(result.cohorts.nba.observedAt, now.toISOString());
    assert.equal(Date.parse(result.nextAttemptAt) - later.getTime(), 300_000);
    const body = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, result]]), later);
    assert.equal(body.checkedAt, later.toISOString());
    assert.equal(body.coverage[0].status, "unavailable");
    const repeatedAt = new Date(later.getTime() + 300_000);
    const repeated = await refreshSportsSource(result, descriptor, repeatedAt, async () => collection(rows.map((row) => ({ ...row,
      source: { ...row.source, observedAt: repeatedAt.toISOString() } })), repeatedAt));
    assert.deepEqual(repeated.accepted.fixtures.find((row) => row.id === original.id), heldCollection({ fixtures: [original] }).fixtures[0]);
    assert.equal(repeated.accepted.fixtures.some((row) => row.id === replacement.id), false);
  }
});

test("terminal semantic fencing does not merge separate starts, participant order or squads", async () => {
  const original = fixture({ id: "sports-fixture:nba:123", status: "finished", start: "2026-09-30T21:00:00.000Z" });
  const old = await refreshSportsSource(null, descriptor, now, async () => collection([original]));
  const later = new Date(now.getTime() + 300_000);
  for (const changes of [{ start: "2026-10-01T00:00:00.000Z" }, { participants: [...original.participants].reverse() },
    { squad: { gender: "women", ageGroup: "senior" } }]) {
    const current = fixture({ id: "sports-fixture:nba:456", status: "scheduled", start: original.start,
      participants: original.participants, ...changes }, later);
    const result = await refreshSportsSource(old, descriptor, later, async () => collection([current], later));
    assert.equal(result.consecutiveFailures, 0);
    assert.deepEqual(result.accepted.fixtures, [current]);
  }
});

test("a terminal collision caused by changing an existing second record preserves both originals", async () => {
  const terminal = fixture({ status: "finished", start: "2026-09-30T21:00:00.000Z" });
  const second = fixture({ id: "sports-fixture:nba:2", start: "2026-10-01T01:00:00.000Z" });
  const old = await refreshSportsSource(null, descriptor, now, async () => collection([terminal, second]));
  const later = new Date(now.getTime() + 300_000);
  const current = fixture({ id: second.id, start: terminal.start, participants: terminal.participants }, later);
  const result = await refreshSportsSource(old, descriptor, later, async () => collection([current], later));
  assert.deepEqual(result.accepted.fixtures, heldCollection(old.accepted).fixtures);
  assert.equal(result.failure.code, "terminal-rollback");
  const body = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, result]]), later);
  assert.equal(body.fixtures.length, 2);
});

test("opaque ID replacement cannot duplicate retained native identity or stop independent rows", async () => {
  const original = footballFixture("premier-league", "123");
  const other = footballFixture("premier-league", "7", { status: "live", start: "2026-09-30T21:00:00.000Z" });
  const cl = footballFixture("champions-league", "8", { status: "live", start: "2026-09-30T21:00:00.000Z" });
  const old = await refreshSportsSource(null, footballDescriptor, now,
    async () => footballCollection(footballDescriptor, [original, other, cl]));
  const later = new Date(now.getTime() + 300_000);
  const replacement = footballFixture("premier-league", "456", { participants: original.participants, title: "New display title" }, later);
  const currentOther = footballFixture("premier-league", "7", { status: "finished", start: other.start }, later);
  const currentCL = footballFixture("champions-league", "8", { status: "finished", start: cl.start }, later);
  const result = await refreshSportsSource(old, footballDescriptor, later,
    async () => footballCollection(footballDescriptor, [replacement, currentOther, currentCL], later));
  assert.deepEqual(result.accepted.fixtures.find((row) => row.id === original.id), heldCollection({ fixtures: [original] }).fixtures[0]);
  assert.equal(result.accepted.fixtures.some((row) => row.id === replacement.id), false);
  assert.equal(result.accepted.fixtures.find((row) => row.id === other.id).status, "finished");
  assert.equal(result.accepted.fixtures.find((row) => row.id === cl.id).source.verification, "verified");
  assert.equal(result.failure.code, "fixture-identity-conflict");
  assert.equal(Date.parse(result.nextAttemptAt) - later.getTime(), 300_000);
  const body = await assembleSportsSnapshot([footballDescriptor], new Map([[footballDescriptor.id, result]]), later);
  assert.equal(new Set(body.fixtures.map(sportsSnapshotIdentity)).size, body.fixtures.length);
  assert.deepEqual(body.coverage.filter((row) => row.status === "unavailable").map((row) => row.competitionId), ["premier-league"]);
  assert.equal(body.coverage.find((row) => row.competitionId === "premier-league").checkedAt, now.toISOString());
  assert.equal(body.coverage.find((row) => row.competitionId === "champions-league").checkedAt, later.toISOString());
  const repeatedAt = new Date(later.getTime() + 300_000);
  const repeated = await refreshSportsSource(JSON.parse(JSON.stringify(result)), footballDescriptor, repeatedAt,
    async () => footballCollection(footballDescriptor, [footballFixture("premier-league", "456", { participants: original.participants }, repeatedAt)], repeatedAt));
  assert.deepEqual(repeated.accepted.fixtures.find((row) => row.id === original.id), heldCollection({ fixtures: [original] }).fixtures[0]);
  assert.equal(repeated.accepted.fixtures.some((row) => row.id === replacement.id), false, "repetition is not authority to alias opaque IDs");
  const recoveredAt = new Date(repeatedAt.getTime() + 300_000);
  const recovered = await refreshSportsSource(repeated, footballDescriptor, recoveredAt,
    async () => footballCollection(footballDescriptor, [footballFixture("premier-league", "123", {}, recoveredAt)], recoveredAt));
  assert.equal(recovered.consecutiveFailures, 0);
  assert.equal(recovered.accepted.fixtures.length, 1);
  assert.equal(recovered.accepted.fixtures[0].source.verification, undefined);
});

test("confirmed correction colliding with a held record is withheld transitively without deleting original facts", async () => {
  const a = fixture(), b = fixture({ id: "sports-fixture:nba:2", start: "2026-10-01T01:00:00.000Z" });
  const old = await refreshSportsSource(null, descriptor, now, async () => collection([a, b]));
  const firstAt = new Date(now.getTime() + 300_000), secondAt = new Date(now.getTime() + 600_000);
  const changed = (at) => fixture({ start: b.start, participants: b.participants }, at);
  const first = await refreshSportsSource(old, descriptor, firstAt, async () => collection([changed(firstAt)], firstAt));
  const replacement = fixture({ id: "sports-fixture:nba:3", participants: a.participants }, secondAt);
  const second = await refreshSportsSource(first, descriptor, secondAt,
    async () => collection([changed(secondAt), replacement], secondAt));
  assert.deepEqual(second.accepted.fixtures, heldCollection(old.accepted).fixtures);
  assert.equal(second.failure.code, "fixture-identity-conflict");
  assert.equal(second.accepted.fixtures.some((row) => row.id === replacement.id), false);
  const body = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, second]]), secondAt);
  assert.equal(new Set(body.fixtures.map(sportsSnapshotIdentity)).size, 2);
});

test("raw duplicate semantic fixtures remain a complete source barrier rather than partial authority", async () => {
  const original = footballFixture("premier-league", "123");
  const duplicate = footballFixture("premier-league", "456", { participants: original.participants, title: "Another title", start: "2026-09-30T23:00:00Z" });
  assert.throws(() => admitSportsCollection(footballCollection(footballDescriptor, [original, duplicate]), null, footballDescriptor, now),
    /duplicate semantic/);
  const old = await refreshSportsSource(null, footballDescriptor, now,
    async () => footballCollection(footballDescriptor, [original]));
  const later = new Date(now.getTime() + 300_000);
  const rows = [original, duplicate, footballFixture("champions-league", "8")].map((row) => ({ ...row,
    source: { ...row.source, observedAt: later.toISOString() } }));
  const result = await refreshSportsSource(old, footballDescriptor, later,
    async () => footballCollection(footballDescriptor, rows, later));
  assert.deepEqual(result.accepted, heldCollection(old.accepted));
  assert.equal(result.failure.code, "duplicate-fixture-identity");
  assert.ok(sourceCoverage(footballDescriptor, result, later).every((row) => row.status === "unavailable"));
});

test("native semantic identities retain participant order, squad and normalized non-match titles", () => {
  const row = fixture();
  assert.equal(sportsSnapshotIdentity(row), sportsSnapshotIdentity(fixture({ title: "Different match label", start: "2026-09-30T23:00:00Z" })));
  assert.notEqual(sportsSnapshotIdentity(row), sportsSnapshotIdentity(fixture({ participants: [...row.participants].reverse() })));
  assert.notEqual(sportsSnapshotIdentity(row), sportsSnapshotIdentity(fixture({ squad: { gender: "women", ageGroup: "senior" } })));
  const tournament = fixture({ eventKind: "tournament", title: "Café & Tour", participants: [] });
  assert.equal(sportsSnapshotIdentity(tournament), sportsSnapshotIdentity({ ...tournament, title: "ＣＡＦＥ and tour" }));
  assert.notEqual(sportsSnapshotIdentity(tournament), sportsSnapshotIdentity({ ...tournament, title: "A different tour" }));
});

test("snapshot assembly fails closed on persisted semantic duplicate rows even when opaque IDs differ", async () => {
  const original = fixture(), duplicate = fixture({ id: "sports-fixture:nba:2", participants: original.participants });
  const legacy = { accepted: collection([original, duplicate]), consecutiveFailures: 0 };
  await assert.rejects(assembleSportsSnapshot([descriptor], new Map([[descriptor.id, legacy]]), now), /Duplicate cross-source semantic/);
});

test("mixed legacy UTC serialization cannot place the snapshot receipt before a newly admitted row", async () => {
  const original = fixture({ source: { ...fixture().source, observedAt: "2026-09-30T22:00:00Z" } });
  const accepted = { ...collection([original]), observedAt: original.source.observedAt };
  const later = new Date(now.getTime() + 500);
  const result = await refreshSportsSource({ accepted, consecutiveFailures: 0 }, descriptor, later,
    async () => collection([fixture({ id: "sports-fixture:nba:2" }, later)], later));
  const body = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, result]]), later);
  assert.equal(body.checkedAt, later.toISOString());
  assert.equal(body.coverage[0].checkedAt, original.source.observedAt);
  assert.ok(body.fixtures.every((row) => Date.parse(row.source.observedAt) <= Date.parse(body.checkedAt)));
});

test("globally unique football publisher ID cannot migrate competitions or bypass original held receipts", async () => {
  for (const status of ["scheduled", "finished"]) {
    const original = footballFixture("premier-league", "123", { status, start: "2026-09-30T21:00:00.000Z" });
    const pl = footballFixture("premier-league", "7", { status: "live", start: now.toISOString() });
    const cl = footballFixture("champions-league", "8", { status: "live", start: now.toISOString() });
    const old = await refreshSportsSource(null, footballDescriptor, now,
      async () => footballCollection(footballDescriptor, [original, pl, cl]));
    const later = new Date(now.getTime() + 300_000);
    const moved = footballFixture("champions-league", "123", { status, start: original.start, participants: original.participants }, later);
    const rows = [moved, footballFixture("premier-league", "7", { status: "finished", start: pl.start }, later),
      footballFixture("champions-league", "8", { status: "finished", start: cl.start }, later),
      footballFixture("la-liga", "9", { status: "live", start: now.toISOString() }, later)];
    assert.throws(() => admitSportsCollection(footballCollection(footballDescriptor, rows, later), old.accepted, footballDescriptor, later),
      /Publisher fixture competition changed/);
    const result = await refreshSportsSource(old, footballDescriptor, later,
      async () => footballCollection(footballDescriptor, rows, later));
    assert.deepEqual(result.accepted.fixtures.find((row) => row.id === original.id), heldCollection({ fixtures: [original] }).fixtures[0]);
    assert.equal(result.accepted.fixtures.some((row) => row.id === moved.id), false);
    assert.equal(result.accepted.fixtures.find((row) => row.id === pl.id).status, "finished");
    assert.equal(result.accepted.fixtures.find((row) => row.id === cl.id).source.verification, "verified");
    assert.equal(result.failure.code, "publisher-competition-conflict");
    assert.equal(Date.parse(result.nextAttemptAt) - later.getTime(), 300_000);
    const body = await assembleSportsSnapshot([footballDescriptor], new Map([[footballDescriptor.id, result]]), later);
    assert.deepEqual(body.coverage.filter((row) => row.status === "unavailable").map((row) => row.competitionId), ["premier-league", "champions-league"]);
    assert.ok(body.coverage.filter((row) => row.status === "unavailable").every((row) => row.checkedAt === now.toISOString()));
    assert.equal(body.coverage.find((row) => row.competitionId === "la-liga").checkedAt, later.toISOString());
    const repeatedAt = new Date(later.getTime() + 300_000);
    const repeated = await refreshSportsSource(result, footballDescriptor, repeatedAt,
      async () => footballCollection(footballDescriptor, rows.map((row) => ({ ...row,
        source: { ...row.source, observedAt: repeatedAt.toISOString() } })), repeatedAt));
    assert.deepEqual(repeated.accepted.fixtures.find((row) => row.id === original.id), heldCollection({ fixtures: [original] }).fixtures[0]);
    assert.equal(repeated.accepted.fixtures.some((row) => row.id === moved.id), false);
  }
});

test("canonical football publisher ID uniqueness is a raw collection barrier only for the reviewed group", () => {
  const pl = footballFixture("premier-league", "123"), cl = footballFixture("champions-league", "123");
  assert.throws(() => admitSportsCollection(footballCollection(footballDescriptor, [pl, cl]), null, footballDescriptor, now), /duplicate publisher/);
  for (const source of [{ ...footballDescriptor, id: "generic-football" }, { ...footballDescriptor, adapter: "espn" }]) {
    assert.equal(admitSportsCollection(footballCollection(source, [pl, cl]), null, source, now).accepted.fixtures.length, 2);
    const old = footballCollection(source, [pl]);
    const isolated = admitSportsCollectionIsolated(footballCollection(source, [cl]), old, source, now);
    assert.equal(isolated.accepted.fixtures.find((row) => row.id === cl.id).source.verification, "verified");
    assert.deepEqual([...isolated.issues.keys()], ["premier-league"], "no global numeric-ID assumptions across generic leagues");
  }
});

test("per-fixture corrections confirm despite unrelated additions and survive durable restart", async () => {
  const disputed = footballFixture("ligue-1", "2");
  const old = await refreshSportsSource(null, footballDescriptor, now, async () => footballCollection(footballDescriptor, [disputed]));
  const firstAt = new Date(now.getTime() + 5 * 60_000), repeatedAt = new Date(now.getTime() + 10 * 60_000);
  const moved = (at) => footballFixture("ligue-1", "2", { start: "2026-10-01T00:00:00.000Z" }, at);
  const first = await refreshSportsSource(old, footballDescriptor, firstAt,
    async () => footballCollection(footballDescriptor, [moved(firstAt)], firstAt));
  assert.equal(first.accepted.fixtures[0].start, disputed.start);
  assert.ok(first.conflict.fixtures[disputed.id]);
  const restarted = JSON.parse(JSON.stringify(first));
  const result = await refreshSportsSource(restarted, footballDescriptor, repeatedAt, async () => footballCollection(footballDescriptor,
    [moved(repeatedAt), footballFixture("champions-league", "3", {}, repeatedAt)], repeatedAt));
  assert.equal(result.accepted.fixtures.find((row) => row.id === disputed.id).start, moved(repeatedAt).start);
  assert.equal(result.accepted.fixtures.find((row) => row.id === disputed.id).source.correctionConfirmedAt, repeatedAt.toISOString());
  assert.equal(result.consecutiveFailures, 0);
  assert.equal(result.conflict, undefined);
  assert.ok(sourceCoverage(footballDescriptor, result, repeatedAt).every((row) => row.status === "covered"));
});

test("changing one correction does not reset a separately repeated correction", () => {
  const old = collection([fixture(), fixture({ id: "sports-fixture:nba:2" })]);
  const firstAt = new Date(now.getTime() + 5 * 60_000), later = new Date(now.getTime() + 10 * 60_000);
  const a = (at) => fixture({ start: "2026-10-01T00:00:00.000Z" }, at);
  const first = admitSportsCollectionIsolated(collection([a(firstAt), fixture({ id: "sports-fixture:nba:2",
    start: "2026-10-01T01:00:00.000Z" }, firstAt)], firstAt), old, descriptor, firstAt);
  const second = admitSportsCollectionIsolated(collection([a(later), fixture({ id: "sports-fixture:nba:2",
    start: "2026-10-01T02:00:00.000Z" }, later)], later), first.accepted, descriptor, later, first.conflict);
  assert.equal(second.accepted.fixtures.find((row) => row.id === a(later).id).start, a(later).start);
  assert.equal(second.accepted.fixtures.find((row) => row.id.endsWith(":2")).source.verification, "held");
  assert.equal(Object.keys(second.conflict.fixtures).length, 1);
});

test("legacy whole-collection correction receipt can confirm the same per-record correction", () => {
  const old = collection(), firstAt = new Date(now.getTime() + 5 * 60_000), later = new Date(now.getTime() + 10 * 60_000);
  const changed = (at) => collection([fixture({ start: "2026-10-01T00:00:00.000Z" }, at)], at);
  const first = admitSportsCollection(changed(firstAt), old, descriptor, firstAt);
  const legacy = { content: JSON.stringify(Object.values(first.conflict.fixtures).map((row) => JSON.parse(row.content))), observedAt: firstAt.toISOString() };
  assert.equal(admitSportsCollection(changed(later), old, descriptor, later, legacy).accepted.fixtures[0].start, changed(later).fixtures[0].start);
});

test("partial admission followed by collection failure downgrades every current marker without changing facts", async () => {
  const old = await refreshSportsSource(null, descriptor, now, async () => collection());
  const later = new Date(now.getTime() + 5 * 60_000), failedAt = new Date(now.getTime() + 10 * 60_000);
  const partial = await refreshSportsSource(old, descriptor, later, async () => collection([
    fixture({ id: "sports-fixture:nba:2", status: "live", start: now.toISOString() }, later)], later));
  assert.ok(partial.accepted.fixtures.some((row) => row.source.verification === "verified"));
  const failed = await refreshSportsSource(partial, descriptor, failedAt, async () => { throw new Error("source transport failed"); });
  assert.deepEqual(failed.accepted, heldCollection(partial.accepted));
  assert.equal(failed.consecutiveFailures, 2);
  assert.equal(sourceCoverage(descriptor, failed, failedAt)[0].sync.consecutiveFailures, 2);
  assert.equal(sourceCoverage(descriptor, failed, failedAt)[0].checkedAt, now.toISOString());
  const body = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, failed]]), failedAt);
  assert.ok(body.fixtures.every((row) => row.source.verification === "held"));
});

test("source replay and malformed complete collection remain whole-source barriers", async () => {
  const old = await refreshSportsSource(null, descriptor, now, async () => collection());
  const later = new Date(now.getTime() + 5 * 60_000);
  const successful = await refreshSportsSource(old, descriptor, later, async () => collection([fixture({}, later)], later));
  const replay = await refreshSportsSource(successful, descriptor, new Date(now.getTime() + 6 * 60_000), async () => collection());
  assert.equal(replay.failure.code, "receipt-regressed");
  assert.deepEqual(replay.accepted, heldCollection(successful.accepted));
  const malformed = await refreshSportsSource(successful, descriptor, later, async () => collection([fixture({}, later), fixture({}, later)], later));
  assert.deepEqual(malformed.accepted, heldCollection(successful.accepted));
  for (const marker of [null, "held", "verified", "unknown"]) {
    assert.throws(() => admitSportsCollection(collection([fixture({ source: { ...fixture().source, verification: marker } })]), null, descriptor, now), /verification/);
  }
  const legacy = collection([fixture({ source: { ...fixture().source, observedAt: "2026-09-30T22:00:00Z" } })]);
  legacy.observedAt = "2026-09-30T22:00:00Z";
  assert.equal(admitSportsCollection(collection(), legacy, descriptor, now).accepted.observedAt, now.toISOString(),
    "equivalent UTC serialization does not regress a receipt");
});

test("isolation cannot overflow the original source limit or erase accepted rows", async () => {
  const rows = (offset, at) => Array.from({ length: 500 }, (_, index) => fixture({ id: `sports-fixture:nba:${offset + index}` }, at));
  const old = await refreshSportsSource(null, descriptor, now, async () => collection(rows(1, now)));
  const later = new Date(now.getTime() + 5 * 60_000);
  const result = await refreshSportsSource(old, descriptor, later, async () => collection(rows(501, later), later));
  assert.equal(result.failure.stage, "admission");
  assert.deepEqual(result.accepted, heldCollection(old.accepted));
  assert.equal(result.accepted.fixtures.length, 500);
});

test("pending timing drives bounded refresh but never creates fixtures or confirmed starts", async () => {
  const pending = (starts) => ({ ...collection([]), pendingFixtureCount: 1, pendingByCompetition: { nba: 1 },
    pendingStartsByCompetition: { nba: starts } });
  const near = await refreshSportsSource(null, descriptor, now, async () => pending(["2026-09-30T22:05:00.000Z"]));
  assert.equal(Date.parse(near.nextAttemptAt) - now.getTime(), 300_000);
  const unknown = await refreshSportsSource(null, descriptor, now, async () => ({ ...collection([]), pendingFixtureCount: 1 }));
  assert.equal(Date.parse(unknown.nextAttemptAt) - now.getTime(), 900_000);
  const future = await refreshSportsSource(null, descriptor, now, async () => pending(["2026-10-02T22:00:00.000Z"]));
  assert.equal(Date.parse(future.nextAttemptAt) - now.getTime(), 14_400_000);
  assert.equal(nextSportsRefresh([], now, ["2026-09-30T00:00:00.000Z"], 1), 300_000);
  assert.equal(nextSportsRefresh([], now, ["2026-10-01T10:00:00.000Z"], 1), 900_000);
  const body = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, near]]), now);
  assert.deepEqual(body.fixtures, []);
  assert.equal(body.coverage[0].nextStart, undefined);
  assert.equal(body.pendingStartsByCompetition, undefined);
  for (const starts of [null, [], { nba: ["2026-10-08T22:00:00.000Z"] }, { nba: ["not UTC"] }, { nba: [now.toISOString(), now.toISOString()] }, { wnba: [] }]) {
    assert.throws(() => admitSportsCollection({ ...pending([]), pendingStartsByCompetition: starts }, null, descriptor, now));
  }
});

test("verification markers change revisions while healthy receipt-only updates remain stable", async () => {
  const row = fixture();
  const verified = { ...row, source: { ...row.source, verification: "verified" } };
  const held = { ...row, source: { ...row.source, verification: "held" } };
  assert.notEqual(await sportsRevision([verified]), await sportsRevision([held]));
  assert.equal(await sportsRevision([row]), await sportsRevision([fixture({}, new Date(now.getTime() + 300_000))]));
});

test("expired isolated rows lose verification without changing original observations", async () => {
  const old = await refreshSportsSource(null, descriptor, now, async () => collection());
  const later = new Date(now.getTime() + 300_000);
  const result = await refreshSportsSource(old, descriptor, later, async () => collection([
    fixture({ id: "sports-fixture:nba:2", start: "2026-10-03T22:00:00.000Z" }, later)], later));
  const fresh = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, result]]), later);
  assert.equal(fresh.fixtures.find((row) => row.id.endsWith(":2")).source.verification, "verified");
  const stale = await assembleSportsSnapshot([descriptor], new Map([[descriptor.id, result]]), new Date(later.getTime() + 31 * 60_000));
  assert.ok(stale.fixtures.every((row) => row.source.verification === "held"));
  assert.equal(stale.fixtures.find((row) => row.id.endsWith(":2")).source.observedAt, later.toISOString());
  assert.equal(result.accepted.fixtures.find((row) => row.id.endsWith(":2")).source.verification, "verified", "projection does not mutate durable records");
});

test("pending near-term collection does not remain stuck on the quiet GET deadline", async () => {
  const oldAt = new Date(Date.now() - 20 * 60_000);
  const make = (at) => ({ fixtures: [], pendingFixtureCount: 1, pendingByCompetition: { nba: 1 },
    pendingStartsByCompetition: { nba: [new Date(at.getTime() + 5 * 60_000).toISOString()] }, observedAt: at.toISOString() });
  const previous = await refreshSportsSource(null, descriptor, oldAt, async () => make(oldAt));
  const data = new Map([["sports-source-v1", previous]]), waits = []; let calls = 0;
  const registry = new SportsFixtureRegistry({ storage: { async get(key) { return data.get(key); }, async put(key, value) { data.set(key, value); } },
    waitUntil(value) { waits.push(value); } }, {}, { descriptors: [descriptor], collect: async (_source, at) => { calls++; return make(at); } });
  await registry.fetch(new Request("https://sports-registry.invalid/fixtures?source=nba"));
  await Promise.all(waits);
  assert.equal(calls, 1);
  assert.equal(waits.length, 1);
  assert.equal(data.get("sports-source-v1").consecutiveFailures, 0);
  assert.ok(Date.parse(data.get("sports-source-v1").accepted.observedAt) > oldAt.getTime());
  assert.deepEqual(data.get("sports-source-v1").accepted.fixtures, []);
});
