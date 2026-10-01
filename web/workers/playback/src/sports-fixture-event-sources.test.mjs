import assert from "node:assert/strict";
import test from "node:test";
import { collectSportsEventSource, SPORTS_EVENT_SOURCES, sportsEventStatus, sportsEventWindow } from "./sports-fixture-event-sources.mjs";

const now = new Date("2026-09-30T16:00:00Z");
const source = (id) => SPORTS_EVENT_SOURCES.find((row) => row.id === id);
const status = (name = "STATUS_SCHEDULED", state = "pre", completed = false) => ({ type: { name, state, completed } });
const athlete = (id, name) => ({ id, type: "athlete", athlete: { displayName: name }, homeAway: id === "1" ? "home" : "away" });
const match = (overrides = {}) => ({ id: "77", date: "2026-10-01T03:00Z", timeValid: true, status: status(),
  competitors: [athlete("1", "First Player"), athlete("2", "Second Player")], ...overrides });
const tennisEvent = (rows = [match()], overrides = {}) => ({ id: "959-2026", name: "China Open", date: "2026-09-27T04:00Z",
  status: status("STATUS_FINAL", "post", true), groupings: [{ grouping: { slug: "mens-singles" }, competitions: rows }], ...overrides });
const board = (descriptor, events) => ({ leagues: [{ id: descriptor.leagueId, slug: descriptor.path.split("/").at(-1) }], events });
const respond = (data) => Response.json(data);
const collectBoard = (id, events, clock = now) => collectSportsEventSource(source(id), clock, {}, async () => respond(board(source(id), events)));

test("window is UTC midnight, one past day and eight exclusive forward days", () => {
  const window = sportsEventWindow(new Date("2026-09-30T23:59:59-04:00"));
  assert.equal(window.from.toISOString(), "2026-09-30T00:00:00.000Z");
  assert.equal(window.to.toISOString(), "2026-10-09T00:00:00.000Z");
});

test("tennis makes nine bounded daily calls, retains ongoing tournaments, and deduplicates match IDs", async () => {
  const calls = [];
  const descriptor = source("tennis-atp");
  const result = await collectSportsEventSource(descriptor, now, {}, async (url, options) => {
    calls.push(new URL(url));
    assert.equal(options.redirect, "error");
    return respond(board(descriptor, [tennisEvent()]));
  });
  assert.deepEqual(calls.map((url) => url.searchParams.get("dates")), ["20260929", "20260930", "20261001", "20261002", "20261003", "20261004", "20261005", "20261006", "20261007"]);
  assert.equal(result.fixtures.length, 1);
  assert.equal(result.fixtures[0].id, "sports-fixture:atp:77");
  assert.equal(result.fixtures[0].start, "2026-10-01T03:00:00.000Z");
  assert.equal(result.fixtures[0].status, "scheduled");
  assert.equal(result.fixtures[0].participants[0].role, undefined);
  assert.equal(result.fixtures[0].source.observedAt, now.toISOString());
  assert.equal(result.fixtures[0].source.updatedAt, undefined);
});

test("tennis filters gender groups and represents doubles as two rosters without home/away", async () => {
  const doubles = match({ id: "78", competitors: [
    { id: "1-2", type: "team", roster: { displayName: "Player One / Player Two" }, homeAway: "home" },
    { id: "3-4", type: "team", roster: { displayName: "Player Three / Player Four" }, homeAway: "away" },
  ] });
  const event = tennisEvent([], { groupings: [
    { grouping: { slug: "mens-doubles" }, competitions: [doubles] },
    { grouping: { slug: "womens-singles" }, competitions: [match({ id: "79" })] },
  ] });
  const result = await collectBoard("tennis-atp", [event]);
  assert.equal(result.fixtures.length, 1);
  assert.equal(result.fixtures[0].participants[0].name, "Player One / Player Two");
  assert.equal(result.fixtures[0].squad.gender, "men");
  assert.ok(result.fixtures[0].participants.every((participant) => !participant.role));
  const women = await collectBoard("tennis-wta", [event]);
  assert.equal(women.fixtures.length, 1);
  assert.equal(women.fixtures[0].id, "sports-fixture:wta:79");
  assert.equal(women.fixtures[0].squad.gender, "women");
});

test("TBD participants, duplicate sides, missing UTC start, and provisional time stay pending", async () => {
  const events = [tennisEvent([
    match({ id: "1", competitors: [athlete("-4", "TBD"), athlete("-3", "TBD")] }),
    match({ id: "2", timeValid: false }),
    match({ id: "3", date: undefined }),
    match({ id: "4", date: "2026-10-01" }),
    match({ id: "5", competitors: [athlete("1", "First Player"), athlete("1", "First Player")] }),
    match({ id: "6", competitors: [athlete("1", "Opponent TBA"), athlete("2", "Second Player")] }),
  ])];
  const result = await collectBoard("tennis-atp", events);
  assert.equal(result.fixtures.length, 0);
  assert.equal(result.pendingFixtureCount, 6);
});

test("competition status takes precedence over a final tennis tournament parent", async () => {
  const result = await collectBoard("tennis-atp", [tennisEvent([
    match({ id: "live", date: "2026-09-30T15:00Z", status: status("STATUS_IN_PROGRESS", "in") }),
    match({ id: "finished", date: "2026-09-30T14:00Z", status: status("STATUS_FINAL", "post", true) }),
    match({ id: "cancelled", status: status("STATUS_CANCELED", "post") }),
    match({ id: "postponed", status: status("STATUS_POSTPONED", "pre") }),
  ])]);
  assert.deepEqual(Object.fromEntries(result.fixtures.map((fixture) => [fixture.id.split(":").at(-1), fixture.status])), {
    finished: "finished", live: "live", cancelled: "cancelled", postponed: "postponed",
  });
});

test("verified tennis retirement and walkover terminal statuses remain finished", async () => {
  const result = await collectBoard("tennis-wta", [tennisEvent([], { groupings: [{ grouping: { slug: "womens-singles" }, competitions: [
    match({ id: "retired", date: "2026-09-30T14:00Z", status: status("STATUS_RETIRED", "post", true) }),
    match({ id: "walkover", date: "2026-09-30T14:00Z", status: status("STATUS_WALKOVER", "post", true) }),
  ] }] })]);
  assert.equal(result.fixtures.length, 2);
  assert.ok(result.fixtures.every((fixture) => fixture.status === "finished"));
});

test("unknown status and live/final future dates fail closed", async () => {
  assert.throws(() => sportsEventStatus(status("STATUS_NEW", "in")), /Unknown/);
  assert.throws(() => sportsEventStatus(status("STATUS_FINAL", "post", false)), /Unknown/);
  await assert.rejects(collectBoard("tennis-atp", [tennisEvent([match({ status: status("STATUS_NEW", "in") })])]), /Unknown/);
  await assert.rejects(collectBoard("tennis-atp", [tennisEvent([match({ status: status("STATUS_FINAL", "post", true) })])]), /future/);
  await assert.rejects(collectBoard("tennis-atp", [tennisEvent([match({ status: status("STATUS_IN_PROGRESS", "in") })])]), /future/);
});

test("wrong sport shapes, wrong leagues, truncation, and malformed matches reject the source", async () => {
  await assert.rejects(collectBoard("tennis-atp", [{ id: "1", name: "Not a tennis tournament", competitions: [match()] }]), /shape/);
  await assert.rejects(collectBoard("tennis-atp", [tennisEvent([match({ competitors: [] })])]), /shape/);
  await assert.rejects(collectSportsEventSource(source("tennis-atp"), now, {}, async () => respond({ leagues: [{ id: "900" }], events: [] })), /wrong ESPN/);
  await assert.rejects(collectSportsEventSource(source("golf-pga"), now, {}, async () => respond(board(source("golf-pga"), Array(100).fill({})))), /Incomplete/);
  await assert.rejects(collectBoard("golf-pga", [{ id: "1", name: "Wrong tournament", competitions: [match(), match()] }]), /shape/);
});

test("strict ISO parsing rejects impossible dates and filters both UTC window boundaries", async () => {
  const result = await collectBoard("tennis-atp", [tennisEvent([
    match({ id: "before", date: "2026-09-28T23:59:59Z" }),
    match({ id: "at-start", date: "2026-09-29T00:00:00Z" }),
    match({ id: "at-end", date: "2026-10-08T00:00:00Z" }),
    match({ id: "bad-date", date: "2026-09-31T03:00Z" }),
  ])]);
  assert.equal(result.fixtures.length, 1);
  assert.equal(result.fixtures[0].id, "sports-fixture:atp:at-start");
  assert.equal(result.pendingFixtureCount, 1);
});

test("golf exposes a tournament title and no fabricated opponent; false time stays pending", async () => {
  const event = { id: "123", date: "2026-10-01T04:00Z", name: "Bank of Utah Championship",
    competitions: [{ id: "123", date: "2026-10-01T04:00Z", timeValid: true, status: status(), competitors: [athlete("1", "Golfer")] }] };
  const result = await collectBoard("golf-pga", [event]);
  assert.equal(result.fixtures[0].eventKind, "tournament");
  assert.equal(result.fixtures[0].title, event.name);
  assert.deepEqual(result.fixtures[0].participants, []);
  assert.equal(result.fixtures[0].home, undefined);
  const pending = await collectBoard("golf-pga", [{ ...event, competitions: [{ ...event.competitions[0], timeValid: false }] }]);
  assert.equal(pending.fixtures.length, 0);
  assert.equal(pending.pendingFixtureCount, 1);
  const noField = await collectBoard("golf-pga", [{ ...event, competitions: [{ ...event.competitions[0], competitors: undefined, timeValid: false }] }]);
  assert.equal(noField.pendingFixtureCount, 1);
});

test("explicit live multi-day events may start up to seven past UTC days; completed events and match pairs may not", async () => {
  const tournament = (id, date, tournamentStatus) => ({ id, date, name: "Ongoing tournament", competitions: [
    { id, date, timeValid: true, status: tournamentStatus },
  ] });
  const result = await collectBoard("golf-pga", [
    tournament("old-live", "2026-09-23T12:00Z", status("STATUS_IN_PROGRESS", "in")),
    tournament("too-old", "2026-09-22T23:59Z", status("STATUS_IN_PROGRESS", "in")),
    tournament("old-final", "2026-09-23T12:00Z", status("STATUS_FINAL", "post", true)),
  ]);
  assert.deepEqual(result.fixtures.map((fixture) => fixture.id), ["sports-fixture:pga:old-live"]);
  assert.equal(result.fixtures[0].status, "live");
  const pairs = await collectBoard("tennis-atp", [tennisEvent([match({ date: "2026-09-23T12:00Z", status: status("STATUS_IN_PROGRESS", "in") })])]);
  assert.equal(pairs.fixtures.length, 0);
});

test("Formula 1 expands typed sessions; NASCAR uses its verified sole race shape", async () => {
  const event = { id: "600", date: "2026-10-02T04:30Z", name: "Grand Prix", competitions: [
    { id: "601", date: "2026-10-02T04:30Z", timeValid: true, type: { abbreviation: "FP1" }, status: status() },
    { id: "602", date: "2026-10-04T07:00Z", timeValid: true, type: { abbreviation: "Race" }, status: status() },
  ] };
  const result = await collectBoard("racing-f1", [event]);
  assert.equal(result.fixtures.length, 2);
  assert.equal(result.fixtures[0].title, "Grand Prix — FP1");
  assert.equal(result.fixtures[0].eventKind, "session");
  assert.deepEqual(result.fixtures[0].participants, []);
  await assert.rejects(collectBoard("racing-f1", [{ ...event, competitions: [{ ...event.competitions[0], type: undefined }] }]), /session type/);
  const race = await collectBoard("racing-nascar-premier", [{ ...event, competitions: [{ ...event.competitions[0], type: undefined }] }]);
  assert.equal(race.fixtures[0].title, "Grand Prix — Race");
});

test("UFC remains a card and uses a verified opening-bout timestamp, not an invented fight pair", async () => {
  const event = { id: "600", date: "2026-10-03T20:00Z", name: "UFC 332: Silva vs. Wang", status: status(),
    competitions: [match({ date: "2026-10-03T20:00Z" })] };
  const result = await collectBoard("fight-ufc", [event]);
  assert.equal(result.fixtures[0].id, "sports-fixture:ufc:600");
  assert.equal(result.fixtures[0].eventKind, "card");
  assert.deepEqual(result.fixtures[0].participants, []);
  const pending = await collectBoard("fight-ufc", [{ ...event, competitions: [match({ date: "2026-10-03T21:00Z" })] }]);
  assert.equal(pending.pendingFixtureCount, 1);
  assert.equal(pending.fixtures.length, 0);
});

function coreFetch(descriptor, count = 1, overrides = {}) {
  const calls = [];
  const base = `https://sports.core.api.espn.com/v2/sports/${descriptor.path}`;
  const fetchImpl = async (value, options) => {
    const url = new URL(value);
    calls.push({ url, options });
    const path = url.pathname;
    if (path === `/v2/sports/${descriptor.path}`) return respond({ slug: descriptor.path.split("/").at(-1), name: descriptor.competitionName,
      events: { $ref: `${base}/events` }, ...overrides.league });
    if (path.endsWith("/events")) return respond({ count, pageIndex: 1, pageSize: 100, pageCount: count ? 1 : 0,
      items: Array.from({ length: count }, (_, index) => ({ $ref: `${base}/events/${100 + index}` })), ...overrides.index });
    if (path.endsWith("/status")) return respond(overrides.status || status());
    const teamID = path.match(/\/teams\/(\d+)$/)?.[1];
    if (teamID) return respond({ id: teamID, displayName: `Team ${teamID}` });
    const eventID = path.match(/\/events\/(\d+)$/)?.[1];
    if (eventID) return respond({ id: eventID, date: "2026-10-02T18:45Z", name: "Home Team vs Away Team", timeValid: true,
      competitions: [{ id: eventID, date: "2026-10-02T18:45Z", timeValid: true, status: { $ref: `${base}/events/${eventID}/competitions/${eventID}/status` },
        competitors: [{ id: "1", type: "team", homeAway: "home", team: { $ref: `${base}/seasons/2027/teams/1` } },
          { id: "2", type: "team", homeAway: "away", team: { $ref: `${base}/seasons/2027/teams/2` } }], ...overrides.competition }], ...overrides.event });
    throw new Error("Unexpected core request");
  };
  return { calls, fetchImpl, base };
}

test("rugby hydrates all referenced identities and statuses within the complete 38-request bound", async () => {
  const descriptor = source("rugby-top14");
  const mock = coreFetch(descriptor, 9);
  const result = await collectSportsEventSource(descriptor, now, {}, mock.fetchImpl);
  assert.equal(mock.calls.length, 38);
  assert.equal(result.fixtures.length, 9);
  assert.deepEqual(result.fixtures[0].participants.map((participant) => participant.role), ["home", "away"]);
  assert.ok(mock.calls.every(({ url, options }) => url.protocol === "https:" && options.redirect === "error"));
});

test("AFL empty window still requires a verified league and complete index; it does not infer offseason", async () => {
  const descriptor = source("afl");
  const mock = coreFetch(descriptor, 0, { index: { pageIndex: 0 } });
  const result = await collectSportsEventSource(descriptor, now, {}, mock.fetchImpl);
  assert.equal(mock.calls.length, 2);
  assert.deepEqual(result.fixtures, []);
  assert.equal(result.offseason, undefined);
  const wrong = coreFetch(descriptor, 0, { league: { slug: "wrong" } });
  await assert.rejects(collectSportsEventSource(descriptor, now, {}, wrong.fetchImpl), /Wrong ESPN core league/);
});

test("oversized, paginated, duplicate, and unsafe core indexes cannot report partial success", async () => {
  const descriptor = source("rugby-prem");
  for (const mock of [coreFetch(descriptor, 10), coreFetch(descriptor, 1, { index: { pageCount: 2 } }),
    coreFetch(descriptor, 2, { index: { items: [{ $ref: `https://sports.core.api.espn.com/v2/sports/${descriptor.path}/events/100` }, { $ref: `https://sports.core.api.espn.com/v2/sports/${descriptor.path}/events/100` }] } }),
    coreFetch(descriptor, 1, { index: { items: [{ $ref: "http://private.invalid/events/100" }] } })]) {
    await assert.rejects(collectSportsEventSource(descriptor, now, {}, mock.fetchImpl), /Incomplete|Duplicate|Unsafe/);
    assert.ok(mock.calls.length <= 40);
    assert.ok(mock.calls.every(({ url }) => url.hostname === "sports.core.api.espn.com"));
  }
});

test("unavailable, redirected, oversized, and unsupported feeds fail before returning a receipt", async () => {
  const descriptor = source("golf-pga");
  await assert.rejects(collectSportsEventSource(descriptor, now, {}, async () => new Response("bad", { status: 400 })), /unavailable/);
  await assert.rejects(collectSportsEventSource(descriptor, now, {}, async () => ({ ok: true, redirected: true })), /unavailable/);
  await assert.rejects(collectSportsEventSource(descriptor, now, {}, async () => new Response("{}", { headers: { "content-length": "2000001" } })), /too large/);
  for (const id of ["fight-boxing", "darts-pdc"]) {
    let calls = 0;
    await assert.rejects(collectSportsEventSource(source(id), now, {}, async () => { calls++; }), /Unsupported/);
    assert.equal(calls, 0);
    assert.ok(source(id).reason.length > 20);
  }
});
