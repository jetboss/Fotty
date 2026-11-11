import test from "node:test";
import assert from "node:assert/strict";
import { t10ScheduleURLs, normalizeT10, refreshT10, appendT10, T10_CRICKET_SOURCE } from "./cricket-espn-t10.mjs";

const now = new Date("2026-11-11T14:20:00Z");
const headers = () => new Headers({ date: now.toUTCString() });
const team = (id, name) => ({ id, displayName: name });
const event = (changes = {}) => ({ id: "1561260", date: "2026-11-11T13:45Z", description: "11th Match",
  status: { type: { state: "in", name: "STATUS_IN_PROGRESS", description: "In Progress" } },
  competitions: [{ description: "11th Match", competitors: [
    { homeAway: "home", team: team("1561249", "Royal Desert Champions") },
    { homeAway: "away", team: team("1511694", "UAE Bulls") }] }], ...changes });
const payload = (events = [event()]) => ({ leagues: [{ id: "18522", name: "Abu Dhabi T10" }], events });
const parse = (events, h = headers()) => normalizeT10([payload(events)], h, now);

test("T10 requests ESPN's league month(s) covering yesterday to +8 days; season gated", () => {
  const urls = t10ScheduleURLs(now).map(String);
  assert.deepEqual(urls, ["https://site.api.espn.com/apis/site/v2/sports/cricket/18522/scoreboard?dates=202611"]);
  assert.equal(t10ScheduleURLs(new Date("2026-11-28T00:00:00Z")).length, 1, "Season ends in November");
  assert.throws(() => t10ScheduleURLs(new Date("2026-12-01T00:00:00Z")), /season-review-required/);
});

test("T10 keeps ESPN identity, match number, UTC start and the feed's live state", () => {
  const f = parse().fixtures[0];
  assert.equal(f.id, "espn-cricket:1561260");
  assert.equal(f.competitionId, "abu-dhabi-t10");
  assert.equal(f.format, "T10");
  assert.equal(f.status, "live");
  assert.equal(f.start, "2026-11-11T13:45:00.000Z");
  assert.equal(f.matchOrdinal, 11);
  assert.deepEqual([f.home.name, f.away.name], ["Royal Desert Champions", "UAE Bulls"]);
  const pre = event({ id: "1561261", date: "2026-11-11T16:00Z", status: { type: { state: "pre" } } });
  assert.equal(parse([pre]).fixtures[0].status, "scheduled");
  const late = event({ id: "1561262", date: "2026-11-11T14:00Z", status: { type: { state: "pre" } } });
  assert.equal(parse([late]).fixtures[0].status, "unknown", "A listed start is not LIVE authority");
  const done = event({ status: { type: { state: "post", name: "STATUS_FINAL" } } });
  assert.equal(parse([done]).fixtures[0].status, "finished");
  const abandoned = event({ status: { type: { state: "post", description: "Abandoned" } } });
  assert.equal(parse([abandoned]).fixtures[0].status, "cancelled");
});

test("T10 skips TBA play-offs and rows outside the window, rejects malformed identity", () => {
  const tba = event({ id: "1561281", date: "2026-11-15T05:00Z", competitions: [{ description: "Final", competitors: [
    { homeAway: "home", team: team("984779", "TBA") }, { homeAway: "away", team: team("984779", "TBA") }] }],
    status: { type: { state: "pre" } } });
  const old = event({ id: "1561250", date: "2026-11-07T11:30Z", status: { type: { state: "post" } } });
  assert.equal(parse([tba, old, event()]).fixtures.length, 1);
  for (const bad of [
    event({ id: "abc" }),
    event({ competitions: [{ description: "11th Match", competitors: [{ homeAway: "home", team: team("1", "A") }] }] }),
    event({ competitions: [{ description: "11th Match", competitors: [
      { homeAway: "home", team: team("1", "Same") }, { homeAway: "away", team: team("2", "Same") }] }] }),
    event({ competitions: [{ description: "Exhibition", competitors: event().competitions[0].competitors }] }),
    event({ date: "2026-11-11T18:00Z" }), // LIVE before its start
  ]) assert.throws(() => parse([bad]));
  assert.throws(() => normalizeT10([{ leagues: [{ id: "1", name: "Other" }], events: [] }], headers(), now), /source-incomplete/);
  assert.throws(() => parse([event()], new Headers({ date: new Date(+now - 11 * 60_000).toUTCString() })), /publisher-stale/);
});

test("T10 refresh keeps accepted rows on failure and refuses identity or status regressions", async () => {
  const accepted = await refreshT10(undefined, now, async () => parse());
  assert.equal(accepted.status, "covered");
  assert.equal(accepted.fixtures.length, 1);
  const later = new Date(+now + 10 * 60_000);
  const outage = await refreshT10(accepted, later, async () => { throw new Error("upstream-unavailable"); });
  assert.equal(outage.status, "unavailable");
  assert.equal(outage.fixtures.length, 1);
  const swapped = await refreshT10(accepted, later, async () => ({ observedAt: later.toISOString(),
    fixtures: [{ ...accepted.fixtures[0], away: { id: "espn:9", name: "Other" } }] }));
  assert.equal(swapped.failure, "identity-conflict");
  const regressed = await refreshT10(accepted, later, async () => ({ observedAt: later.toISOString(),
    fixtures: [{ ...accepted.fixtures[0], status: "scheduled" }] }));
  assert.equal(regressed.failure, "status-regressed");
  const off = await refreshT10(undefined, new Date("2026-12-02T00:00:00Z"));
  assert.equal(off.status, "offseason");
});

test("T10 appends one coverage row with an exact count and keeps other cohorts intact", async () => {
  const cohort = await refreshT10(undefined, now, async () => parse());
  const base = { schemaVersion: 1, complete: true, sourceStatus: "verified", checkedAt: now.toISOString(), revision: "r",
    fixtures: [{ id: "icc:1", competitionId: "icc" }],
    coverage: [{ competitionId: "icc", status: "covered", fixtureCount: 1 }], sync: {} };
  const merged = appendT10(base, cohort);
  assert.equal(merged.fixtures.length, 2);
  const coverage = merged.coverage.find((c) => c.competitionId === T10_CRICKET_SOURCE.competitionID);
  assert.equal(coverage.fixtureCount, 1);
  assert.equal(coverage.status, "covered");
  assert.equal(merged.sourceStatus, "verified");
  assert.equal(merged.sync.cohorts["abu-dhabi-t10"].consecutiveFailures, 0);
  const off = appendT10(base, { ...cohort, status: "offseason", observedAt: "2026-11-20T10:00:00.000Z",
    lastAttemptAt: "2027-02-01T00:00:00.000Z" });
  assert.equal(off.coverage.at(-1).fixtureCount, 0);
  assert.equal(off.coverage.at(-1).checkedAt, "2027-02-01T00:00:00.000Z",
    "Offseason publishes a fresh receipt, never an expired season receipt the app would reject");
  const empty = appendT10(base, await refreshT10(undefined, new Date("2026-12-02T00:00:00Z")));
  assert.equal(empty.coverage.at(-1).checkedAt, "2026-12-02T00:00:00.000Z", "No epoch receipt for empty offseason storage");
  assert.equal(off.fixtures.length, 1, "Offseason publishes no rows");
  assert.equal(appendT10(base, undefined), base);
});
