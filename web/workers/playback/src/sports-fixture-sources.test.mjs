import assert from "node:assert/strict";
import test from "node:test";
import { SPORTS_SOURCES, collectSportsSource, sportsFixtureWindow } from "./sports-fixture-sources.mjs";

const now = new Date("2026-09-30T16:00:00Z");
const source = (id) => SPORTS_SOURCES.find((item) => item.id === id);
const collect = (id, impl, env = {}) => collectSportsSource(source(id), now, env, impl);
const json = (value) => Response.json(value);
const start = "2026-09-30T17:00:00Z";

function espnEvent(id = "100", overrides = {}, descriptor = source("nba")) {
  const team = (id, role) => ({ id, type: "team", homeAway: role, team: { id, displayName: `Team ${id}` } });
  const sportID = { basketball: "40", football: "20", soccer: "600" }[descriptor.path.split("/")[0]];
  return { id, uid: `s:${sportID}~l:${descriptor.leagueID}~e:${id}`, date: start,
    competitions: [{ id, date: start, startDate: start, timeValid: true, competitors: [team("1", "home"), team("2", "away")] }],
    status: { type: { name: "STATUS_SCHEDULED", state: "pre", completed: false } }, ...overrides };
}
function espnPayload(descriptor, events = [], group = descriptor.group) {
  return { leagues: [{ id: descriptor.leagueID, slug: descriptor.path.split("/")[1], name: descriptor.competitions[0].name,
    calendarStartDate: "2026-01-01T07:00Z", calendarEndDate: "2027-07-01T06:59Z" }], events,
    ...(group ? { groups: [group] } : {}) };
}
function espnFetch(id = "nba", events = [espnEvent()]) {
  const descriptor = source(id);
  return async (url) => json(espnPayload(descriptor, url.searchParams.get("dates") === "20260930" ? events : [], url.searchParams.get("groups") || undefined));
}
const mlbRow = (overrides = {}) => ({ gamePk: 10, officialDate: "2026-09-30", gameDate: start, ifNecessary: "N",
  status: { codedGameState: "S", abstractGameState: "Preview", detailedState: "Scheduled", startTimeTBD: false },
  teams: { home: { team: { id: 1, name: "Home team" } }, away: { team: { id: 2, name: "Away team" } } }, ...overrides });
function mlbPayload(rows = [mlbRow()]) {
  return { totalItems: rows.length, totalGames: rows.length, totalEvents: 0,
    dates: rows.length ? [{ date: "2026-09-30", totalItems: rows.length, totalGames: rows.length, totalEvents: 0, games: rows }] : [] };
}
const nhlRow = (overrides = {}) => ({ id: 2026020010, startTimeUTC: start, gameState: "FUT", gameScheduleState: "OK",
  homeTeam: { id: 1, placeName: { default: "Home" }, commonName: { default: "Team" } },
  awayTeam: { id: 2, placeName: { default: "Away" }, commonName: { default: "Team" } }, ...overrides });
function nhlFetch(rows = [nhlRow()], mutate = (data) => data) {
  return async (url) => {
    const date = String(url).split("/").at(-1);
    const selected = date === "2026-09-29" ? rows : [];
    const data = { numberOfGames: selected.length, gameWeek: Array.from({ length: 7 }, (_, index) => ({
      date: new Date(Date.parse(`${date}T00:00Z`) + index * 86_400_000).toISOString().slice(0, 10), games: index === 1 ? selected : [] })) };
    return json(mutate(data));
  };
}
const wnbaRow = (overrides = {}) => ({ gameId: "1042600111", gameDateTimeUTC: start, gameStatus: 1,
  gameStatusText: "1:00 pm ET", postponedStatus: "N", ifNecessary: false,
  homeTeam: { teamId: 1, teamCity: "Home", teamName: "Team" }, awayTeam: { teamId: 2, teamCity: "Away", teamName: "Team" }, ...overrides });
const wnbaPayload = (rows = [wnbaRow()], overrides = {}) => ({ meta: { time: now.toISOString() },
  leagueSchedule: { leagueId: "10", seasonYear: "2026", gameDates: [{ games: rows }] }, ...overrides });
const footballRow = (overrides = {}) => ({ id: 111, utcDate: start, status: "TIMED", lastUpdated: "2026-09-29T12:00:00Z",
  competition: { code: "PL" }, homeTeam: { id: 1, name: "Home" }, awayTeam: { id: 2, name: "Away" }, ...overrides });
function footballFetch(rows = [footballRow()], mutate = (data) => data) {
  return async (url) => json(mutate({ filters: { dateFrom: url.searchParams.get("dateFrom"), dateTo: url.searchParams.get("dateTo"), competitions: "PL,CL" },
    resultSet: { count: rows.length }, matches: rows }));
}

test("descriptor scope and collection window use UTC with one past and seven forward days", () => {
  assert.deepEqual(sportsFixtureWindow(now), { windowStart: "2026-09-29T00:00:00.000Z", windowEnd: "2026-10-08T00:00:00.000Z" });
  assert.equal(source("wnba").gender, "women");
  assert.equal(source("college-basketball-women").ageGroup, "college");
  assert.deepEqual(source("college-football").groups, ["80", "81"]);
  assert.equal(new Set(SPORTS_SOURCES.map((item) => item.id)).size, SPORTS_SOURCES.length);
  assert.throws(() => sportsFixtureWindow(new Date("invalid")));
});

test("ESPN produces explicit team, gender, competition and receipt identity without sponsor provenance", async () => {
  const result = await collect("nba", espnFetch());
  const fixture = result.fixtures[0];
  assert.equal(fixture.id, "sports-fixture:nba:100");
  assert.equal(fixture.start, "2026-09-30T17:00:00.000Z");
  assert.deepEqual(fixture.squad, { gender: "men", ageGroup: "senior" });
  assert.equal(fixture.source.name, "ESPN");
  assert.equal(fixture.source.observedAt, now.toISOString());
  assert.equal(fixture.source.updatedAt, undefined);
  assert.equal(result.pendingFixtureCount, 0);
  assert.equal(fixture.participants[0].role, "home");
});

test("ESPN requests individual padded dates at explicit 500 capacity under one signal", async () => {
  const calls = [];
  const result = await collect("nba", async (url, init) => {
    calls.push({ url, init });
    return json(espnPayload(source("nba"), []));
  });
  assert.equal(calls.length, 10);
  assert.equal(calls[0].url.searchParams.get("dates"), "20260928");
  assert.equal(calls.at(-1).url.searchParams.get("dates"), "20261007");
  assert.ok(calls.every(({ url, init }) => url.searchParams.get("limit") === "500" && init.redirect === "error"));
  assert.ok(calls.every(({ init }) => init.signal === calls[0].init.signal));
  assert.equal(calls[0].init.signal.aborted, true);
  assert.deepEqual(result.fixtures, []);
});

test("ESPN empty schema must identify the requested league and its calendar", async () => {
  await assert.rejects(() => collect("nba", async () => json({ leagues: [], events: [] })), /calendar/);
  await assert.rejects(() => collect("nba", async () => json({ ...espnPayload(source("nba")), events: undefined })), /truncated/);
  await assert.rejects(() => collect("college-basketball-men", async () => json(espnPayload(source("college-basketball-women")))), /calendar/);
  await assert.rejects(() => collect("college-football", async () => json({ ...espnPayload(source("college-football")), groups: ["50"] })), /group/);
});

test("ESPN exact capacity, duplicate identities and unknown statuses reject the entire receipt", async () => {
  await assert.rejects(() => collect("nba", espnFetch("nba", Array.from({ length: 500 }, (_, index) => espnEvent(String(index + 1))))), /truncated/);
  await assert.rejects(() => collect("nba", espnFetch("nba", [espnEvent(), espnEvent()])), /Duplicate/);
  await assert.rejects(() => collect("nba", espnFetch("nba", [espnEvent("100", { status: { type: { name: "NEW_STATUS", state: "pre", completed: false } } })])), /Unknown/);
  await assert.rejects(() => collect("nba", espnFetch("nba", [espnEvent("100", { uid: "wrong" })])), /identity/);
});

test("ESPN terminal, live and kickoff conflict checks remain provider-backed", async () => {
  for (const [name, state, completed, expected] of [["STATUS_IN_PROGRESS", "in", false, "live"], ["STATUS_FINAL", "post", true, "finished"], ["STATUS_POSTPONED", "pre", false, "postponed"]]) {
    const result = await collect("nba", espnFetch("nba", [espnEvent("100", { status: { type: { name, state, completed } } })]));
    assert.equal(result.fixtures[0].status, expected);
  }
  const event = espnEvent();
  event.status.type = { name: "STATUS_FINAL", state: "pre", completed: false };
  await assert.rejects(() => collect("nba", espnFetch("nba", [event])), /final state/);
  const conflict = espnEvent(); conflict.competitions[0].date = "2026-09-30T18:00:00Z";
  await assert.rejects(() => collect("nba", espnFetch("nba", [conflict])), /kickoff/);
});

test("ESPN unknown teams and TBD synthetic midnight count as pending without reminders", async () => {
  const time = espnEvent(); time.competitions[0].timeValid = false;
  const teams = espnEvent("101"); teams.competitions[0].competitors[0].id = "-1"; teams.competitions[0].competitors[0].team.id = "-1";
  const result = await collect("nba", espnFetch("nba", [time, teams]));
  assert.equal(result.fixtures.length, 0);
  assert.equal(result.pendingFixtureCount, 2);
  assert.equal(result.pendingByCompetition.nba, 2);
});

test("ESPN football descriptors retain explicit league identities without PL/CL replacement", async () => {
  for (const id of ["la-liga", "serie-a", "bundesliga", "ligue-1", "mls"]) {
    const descriptor = source(id);
    const result = await collect(id, espnFetch(id, [espnEvent("100", {}, descriptor)]));
    assert.equal(result.fixtures[0].sport, "football");
    assert.equal(result.fixtures[0].competitionId, id);
    assert.equal(descriptor.permissionStatus, "deployment-review-required");
  }
  const row = espnEvent("101", { status: { type: { name: "STATUS_FULL_TIME", state: "post", completed: true } } }, source("mls"));
  assert.equal((await collect("mls", espnFetch("mls", [row]))).fixtures[0].status, "finished");
  row.status.type = { name: "STATUS_SECOND_HALF", state: "in", completed: false };
  assert.equal((await collect("mls", espnFetch("mls", [row]))).fixtures[0].status, "live");
});

test("NCAA unions agreeing FBS/FCS events once and rejects cross-group team/time/status conflicts", async () => {
  const descriptor = source("college-football");
  const event = espnEvent("100", {}, descriptor);
  let calls = 0;
  const result = await collect("college-football", async (url) => { calls++; return espnFetch("college-football", [event])(url); });
  assert.equal(calls, 20);
  assert.equal(result.fixtures.length, 1);
  assert.equal(result.fixtures[0].competitionId, "college-football");
  for (const kind of ["team", "time", "status"]) {
    const changed = structuredClone(event);
    if (kind === "team") { changed.competitions[0].competitors[0].id = "3"; changed.competitions[0].competitors[0].team.id = "3"; }
    if (kind === "time") { changed.date = "2026-09-30T18:00:00Z"; changed.competitions[0].date = changed.date; changed.competitions[0].startDate = changed.date; }
    if (kind === "status") changed.status.type = { name: "STATUS_IN_PROGRESS", state: "in", completed: false };
    await assert.rejects(() => collect("college-football", async (url) => espnFetch("college-football", [url.searchParams.get("groups") === "81" ? changed : event])(url)), /Conflicting/);
  }
  await assert.rejects(() => collect("college-football", espnFetch("college-football", [event, event])), /Duplicate/);
});

test("only actual UTC starts inside the advertised window survive", async () => {
  const event = espnEvent();
  event.date = "2026-10-08T00:00:00Z"; event.competitions[0].date = event.date; event.competitions[0].startDate = event.date;
  assert.equal((await collect("nba", espnFetch("nba", [event]))).fixtures.length, 0);
  const bad = espnEvent(); bad.date = "2026-02-30T12:00:00Z"; bad.competitions[0].date = bad.date; bad.competitions[0].startDate = bad.date;
  await assert.rejects(() => collect("nba", espnFetch("nba", [bad])), /Invalid UTC/);
});

test("MLB matches complete totals, preserves challenge-live status and rejects bad counts", async () => {
  const row = mlbRow({ status: { codedGameState: "M", abstractGameState: "Live", detailedState: "Player challenge", startTimeTBD: false } });
  const result = await collect("mlb", async () => json(mlbPayload([row])));
  assert.equal(result.fixtures[0].status, "live");
  assert.equal(result.fixtures[0].source.updatedAt, undefined);
  await assert.rejects(() => collect("mlb", async () => json({ ...mlbPayload(), totalGames: 2, totalItems: 2 })), /count/);
  await assert.rejects(() => collect("mlb", async () => json(mlbPayload([mlbRow(), mlbRow()]))), /Duplicate/);
  const unknown = mlbRow({ status: { codedGameState: "new", abstractGameState: "Live", detailedState: "Changed", startTimeTBD: false } });
  await assert.rejects(() => collect("mlb", async () => json(mlbPayload([unknown]))), /Unknown/);
});

test("MLB only genuine empty and complete schedule envelopes are accepted", async () => {
  assert.equal((await collect("mlb", async () => json(mlbPayload([])))).fixtures.length, 0);
  await assert.rejects(() => collect("mlb", async () => json({ games: [] })), /incomplete/);
  const payload = mlbPayload(); payload.dates[0].totalGames = 2;
  await assert.rejects(() => collect("mlb", async () => json(payload)), /incomplete/);
  const result = await collect("mlb", async () => json(mlbPayload([mlbRow({ ifNecessary: "Y" })])));
  assert.equal(result.pendingFixtureCount, 1);
});

test("NHL checks every calendar day and total across two bounded weeks", async () => {
  const result = await collect("nhl", nhlFetch());
  assert.equal(result.fixtures[0].id, "sports-fixture:nhl:2026020010");
  await assert.rejects(() => collect("nhl", nhlFetch([], (data) => ({ ...data, gameWeek: data.gameWeek.slice(1) }))), /incomplete/);
  await assert.rejects(() => collect("nhl", nhlFetch([], (data) => ({ ...data, numberOfGames: 1 }))), /count/);
  await assert.rejects(() => collect("nhl", nhlFetch([nhlRow({ gameState: "new" })])), /Unknown/);
  assert.equal((await collect("nhl", nhlFetch([]))).fixtures.length, 0);
});

test("WNBA league-owned text/plain JSON has explicit gender, update and conditional exclusion", async () => {
  const result = await collect("wnba", async () => new Response(JSON.stringify(wnbaPayload()), { headers: { "Content-Type": "text/plain", "Last-Modified": now.toUTCString() } }));
  assert.equal(result.fixtures[0].squad.gender, "women");
  assert.equal(result.fixtures[0].source.updatedAt, now.toISOString());
  const pending = await collect("wnba", async () => json(wnbaPayload([wnbaRow({ gameStatusText: "TBD" }), wnbaRow({ gameId: "1042600112", ifNecessary: true })])));
  assert.equal(pending.pendingFixtureCount, 2);
  assert.equal(pending.fixtures.length, 0);
});

test("WNBA stale generation, missing season, duplicate and unknown status fail closed", async () => {
  await assert.rejects(() => collect("wnba", async () => new Response(JSON.stringify(wnbaPayload()), { headers: { "Content-Type": "application/json", "Last-Modified": "Sun, 27 Sep 2026 16:00:00 GMT" } })), /stale/);
  await assert.rejects(() => collect("wnba", async () => json({ meta: { time: now.toISOString() }, leagueSchedule: { leagueId: "00", seasonYear: "2026", gameDates: [] } })), /identity/);
  await assert.rejects(() => collect("wnba", async () => json(wnbaPayload([wnbaRow(), wnbaRow()]))), /Duplicate/);
  await assert.rejects(() => collect("wnba", async () => json(wnbaPayload([wnbaRow({ gameStatus: 9 })]))), /Unknown/);
});

test("WNBA prior-year files cannot prove current September coverage even with a fresh artifact receipt", async () => {
  const old = wnbaPayload([wnbaRow({ gameDateTimeUTC: "2025-09-30T17:00:00Z", gameStatus: 3 })]);
  old.leagueSchedule.seasonYear = "2025";
  await assert.rejects(() => collect("wnba", async () => new Response(JSON.stringify(old), {
    headers: { "Content-Type": "application/json", "Last-Modified": now.toUTCString() },
  })), /identity unavailable/);
  const next = structuredClone(old); next.leagueSchedule.seasonYear = "2027";
  await assert.rejects(() => collect("wnba", async () => json(next)), /identity unavailable/);
});

test("WNBA calendar rollover fails closed until a current-year season feed exists", async () => {
  const rollover = new Date("2027-01-01T16:00:00Z");
  const previous = wnbaPayload([wnbaRow({ gameStatus: 3 })], { meta: { time: rollover.toISOString() } });
  await assert.rejects(() => collectSportsSource(source("wnba"), rollover, {}, async () => new Response(JSON.stringify(previous), {
    headers: { "Content-Type": "application/json", "Last-Modified": rollover.toUTCString() },
  })), /identity unavailable/);
});

test("WNBA publisher generation is distinct from successful receipt and stale live HTTP evidence rejects", async () => {
  const previous = "Wed, 30 Sep 2026 15:55:00 GMT";
  const body = wnbaPayload([wnbaRow({ gameStatus: 2 })], { meta: { time: "2026-09-30T12:00:00Z" } });
  const live = async (headers = {}) => new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json", ...headers } });
  const result = await collect("wnba", () => live({ "Last-Modified": previous, Age: "0" }));
  assert.equal(result.fixtures[0].source.observedAt, now.toISOString());
  assert.equal(result.fixtures[0].source.updatedAt, "2026-09-30T15:55:00.000Z");
  assert.equal((await collect("wnba", () => live())).fixtures[0].source.updatedAt, undefined);
  await assert.rejects(() => collect("wnba", () => live({ "Last-Modified": "Wed, 30 Sep 2026 15:30:00 GMT" })), /live evidence stale/);
  await assert.rejects(() => collect("wnba", () => live({ "Last-Modified": previous, Age: "1800" })), /live evidence stale/);
  await assert.rejects(() => collect("wnba", () => live({ "Last-Modified": "Wed, 30 Sep 2026 17:00:00 GMT" })), /timestamp stale/);
  await assert.rejects(() => collect("wnba", () => live({ "Last-Modified": "2026-09-30T15:55:00Z" })), /timestamp invalid/);
});

test("football reuses one credentialed PL/CL bulk request with exclusive end and source timestamp", async () => {
  const calls = [];
  const result = await collect("football-data", async (url, init) => {
    calls.push({ url, init });
    return footballFetch()(url);
  }, { FOOTBALL_DATA_API_KEY: "test-secret" });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url.searchParams.get("competitions"), "PL,CL");
  assert.equal(calls[0].url.searchParams.get("dateTo"), "2026-10-08");
  assert.equal(calls[0].init.headers["X-Auth-Token"], "test-secret");
  assert.equal(result.fixtures[0].competitionId, "premier-league");
  assert.equal(result.fixtures[0].source.updatedAt, "2026-09-29T12:00:00.000Z");
  assert.ok(!JSON.stringify(result).includes("test-secret"));
});

test("football refuses missing credential, ignored scope, count/window mismatch and rough dates", async () => {
  await assert.rejects(() => collect("football-data", footballFetch()), /credential/);
  const env = { FOOTBALL_DATA_API_KEY: "test-secret" };
  await assert.rejects(() => collect("football-data", footballFetch([], (data) => ({ ...data, filters: { ...data.filters, competitions: "BSA" } })), env), /filter/);
  await assert.rejects(() => collect("football-data", footballFetch([], (data) => ({ ...data, resultSet: { count: 1 } })), env), /incomplete/);
  await assert.rejects(() => collect("football-data", footballFetch([], (data) => ({ ...data, filters: { ...data.filters, dateTo: "2026-10-01" } })), env), /window/);
  await assert.rejects(() => collect("football-data", footballFetch([footballRow({ competition: { code: "BSA" } })]), env), /competition/);
  assert.equal((await collect("football-data", footballFetch([footballRow({ status: "SCHEDULED" })]), env)).pendingFixtureCount, 1);
});

test("transport rejects upstream errors, redirected responses, HTML and oversized streaming bodies", async () => {
  await assert.rejects(() => collect("mlb", async () => new Response("unavailable", { status: 503 })), /unavailable/);
  await assert.rejects(() => collect("mlb", async () => ({ ok: true, redirected: true })), /unavailable/);
  await assert.rejects(() => collect("mlb", async () => new Response("<html>empty</html>", { headers: { "Content-Type": "text/html" } })), /not JSON/);
  await assert.rejects(() => collect("mlb", async () => new Response("{}", { headers: { "Content-Type": "application/json", "Content-Length": "2000001" } })), /too large/);
  await assert.rejects(() => collect("mlb", async () => new Response(" ".repeat(2_000_001), { headers: { "Content-Type": "application/json" } })), /too large/);
  await assert.rejects(() => collectSportsSource({ id: "arbitrary", sourceURL: "https://example.invalid" }, now), /Unknown/);
});

test("a failed ESPN page revokes sibling transports before another date batch starts", async () => {
  const signals = [];
  await assert.rejects(() => collect("nba", async (url, init) => {
    signals.push(init.signal);
    if (url.searchParams.get("dates") === "20260928") return json({ events: [] });
    return new Promise(() => {});
  }), /calendar/);
  assert.equal(signals.length, 4);
  assert.ok(signals.every((signal) => signal.aborted));
});

test("whole collection deadline stops an uncooperative fetch and revokes all transport signals", async () => {
  let signal;
  await assert.rejects(() => collect("mlb", async (_url, init) => { signal = init.signal; return new Promise(() => {}); }), /Deadline/);
  assert.equal(signal.aborted, true);
});
