import test from "node:test";
import assert from "node:assert/strict";
import { admitSportsCollection, fixtureInstant, nextSportsRefresh, sportsRevision } from "./sports-fixture-policy.mjs";
import { assembleSportsSnapshot, refreshSportsSource, sourceCoverage, SportsFixtureRegistry } from "./sports-fixture-registry.mjs";

const now = new Date("2026-09-30T22:00:00.000Z");
const descriptor = { id: "nba", sport: "basketball", supported: true, competitions: [{ id: "nba", name: "NBA" }] };
function fixture(changes = {}, at = now) {
  return { id: "sports-fixture:nba:1", sport: "basketball", start: "2026-09-30T23:00:00.000Z", status: "scheduled",
    eventKind: "match", title: "Alpha vs Beta", competitionId: "nba", competitionName: "NBA",
    participants: [{ id: "nba:1", name: "Alpha", role: "home" }, { id: "nba:2", name: "Beta", role: "away" }],
    squad: { gender: "men", ageGroup: "senior" }, source: { name: "ESPN", url: "https://www.espn.com/nba/scoreboard", observedAt: at.toISOString() }, ...changes };
}
function collection(fixtures = [fixture()], at = now) { return { fixtures, pendingFixtureCount: 0, observedAt: at.toISOString() }; }

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
