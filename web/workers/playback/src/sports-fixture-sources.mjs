import { abortable, boundedJSON, coachDeadline } from "./coach-safety.mjs";

const DAY = 86_400_000;
const MAX_BYTES = 2_000_000;
const ESPN_CAPACITY = 500;

const competition = (id, name, sport) => ({ id, name, sport });
const single = (id, name, sport, adapter, sourceURL, extra = {}) => ({
  id, sport, adapter, supported: true, competitions: [competition(id, name, sport)],
  gender: "men", ageGroup: "senior", sourceName: adapter === "espn" ? "ESPN" : name,
  sourceURL, ...extra,
});
const espn = (id, name, sport, path, leagueID, extra = {}) => single(id, name, sport, "espn",
  `https://site.api.espn.com/apis/site/v2/sports/${path}/scoreboard`, {
    path, leagueID, publicUndocumented: true, permissionStatus: "deployment-review-required", ...extra,
  });

// ESPN's website feeds are publicly reachable but undocumented, with no
// published capacity/SLA or reuse grant. These descriptors stage code only;
// enabling cloud collection remains a separate deployment decision.
export const SPORTS_SOURCES = Object.freeze([
  { id: "football-data", sport: "football", adapter: "football-data", supported: true,
    competitions: [competition("premier-league", "Premier League", "football"),
      competition("champions-league", "UEFA Champions League", "football")],
    codes: { PL: "premier-league", CL: "champions-league" }, gender: "men", ageGroup: "senior",
    sourceName: "football-data.org", sourceURL: "https://api.football-data.org/v4/matches" },
  single("mlb", "Major League Baseball", "baseball", "mlb", "https://statsapi.mlb.com/api/v1/schedule"),
  single("nhl", "National Hockey League", "hockey", "nhl", "https://api-web.nhle.com/v1/schedule"),
  single("wnba", "Women's National Basketball Association", "basketball", "wnba",
    "https://cdn.wnba.com/static/json/staticData/scheduleLeagueV2.json", { gender: "women" }),
  espn("nba", "National Basketball Association", "basketball", "basketball/nba", "46"),
  espn("nfl", "National Football League", "american-football", "football/nfl", "28"),
  espn("college-football", "NCAA Football", "american-football", "football/college-football", "23", { groups: ["80", "81"], ageGroup: "college" }),
  espn("college-basketball-men", "NCAA Division I Men's Basketball", "basketball", "basketball/mens-college-basketball", "41", { group: "50", ageGroup: "college" }),
  espn("college-basketball-women", "NCAA Division I Women's Basketball", "basketball", "basketball/womens-college-basketball", "54", { group: "50", gender: "women", ageGroup: "college" }),
  espn("la-liga", "La Liga", "football", "soccer/esp.1", "740"),
  espn("serie-a", "Serie A", "football", "soccer/ita.1", "730"),
  espn("bundesliga", "Bundesliga", "football", "soccer/ger.1", "720"),
  espn("ligue-1", "Ligue 1", "football", "soccer/fra.1", "710"),
  espn("mls", "Major League Soccer", "football", "soccer/usa.1", "770"),
]);

function check(condition, message) { if (!condition) throw new Error(message); }
function identifier(value) { return /^(?:[1-9][0-9]*)$/.test(String(value)); }
function name(value) { return typeof value === "string" && value.trim().length > 0 && value.length <= 200; }
function utc(value) {
  check(typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z$/.test(value), "Invalid UTC fixture date");
  const parsed = new Date(value);
  check(Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value.slice(0, 10), "Invalid UTC fixture date");
  return parsed.toISOString();
}
function count(value) { return Number.isSafeInteger(value) && value >= 0; }
function day(value) { return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && utc(`${value}T00:00Z`).slice(0, 10) === value; }
function unique(rows, key, message = "Duplicate upstream fixture") {
  const seen = new Set();
  for (const row of rows) { const id = key(row); check(!seen.has(id), message); seen.add(id); }
}
function sourceStatus(status, mapping) {
  check(typeof status === "string" && Object.hasOwn(mapping, status), "Unknown upstream fixture status");
  return mapping[status];
}
function participant(prefix, id, label, role) {
  if (!identifier(id) || !name(label) || /^(?:TBD|TBC|T\.B\.[CD]\.|To be (?:confirmed|determined))$/i.test(label.trim())) return null;
  return { id: `${prefix}:${id}`, name: label.trim(), role };
}
function normalize(descriptor, id, start, status, teams, observedAt, url, updatedAt, compID = descriptor.competitions[0].id) {
  check(identifier(id), "Invalid upstream fixture identity");
  const comp = descriptor.competitions.find((item) => item.id === compID);
  check(comp, "Unexpected fixture competition");
  if (!teams.every(Boolean)) return null;
  check(teams.length === 2 && teams[0].id !== teams[1].id, "Invalid fixture participants");
  return { id: `sports-fixture:${comp.id}:${id}`, sport: descriptor.sport, start: utc(start), status,
    eventKind: "match", title: `${teams[0].name} vs ${teams[1].name}`,
    competitionId: comp.id, competitionName: comp.name, participants: teams,
    squad: { gender: descriptor.gender, ageGroup: descriptor.ageGroup },
    source: { name: descriptor.sourceName, url, observedAt, ...(updatedAt ? { updatedAt } : {}) } };
}

export function sportsFixtureWindow(now) {
  check(now instanceof Date && Number.isFinite(now.getTime()), "Invalid collection time");
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return { windowStart: new Date(today - DAY).toISOString(), windowEnd: new Date(today + 8 * DAY).toISOString() };
}

async function requestJSON(url, deadline, fetchImpl, headers = {}, withHeaders = false) {
  // Workers supports manual/follow, not the Node fetch "error" mode. Never
  // follow a redirect with a credential or accept an alternate publisher.
  const response = await abortable(() => fetchImpl(url, { signal: deadline.signal, redirect: "manual",
    headers: { Accept: "application/json", ...headers }, cf: { cacheEverything: true, cacheTtl: 60 } }), deadline.signal);
  if (!response.ok || response.redirected || response.status >= 300 && response.status < 400) {
    throw Object.assign(new Error("Sports schedule upstream unavailable"), { fixtureHTTPStatus: response.status });
  }
  const contentType = response.headers.get("content-type") || "";
  // The league-owned WNBA JSON file is served as text/plain. Its exact
  // allowlisted URL and complete typed league schema remain mandatory.
  const wnbaText = String(url) === "https://cdn.wnba.com/static/json/staticData/scheduleLeagueV2.json" && /^text\/plain(?:\s*;|$)/i.test(contentType);
  check(wnbaText || /(?:^|\/)json(?:\s*;|$)|\+json(?:\s*;|$)/i.test(contentType), "Sports schedule is not JSON");
  const data = await boundedJSON(response, MAX_BYTES, deadline.signal);
  return withHeaders ? { data, lastModified: response.headers.get("last-modified"), age: response.headers.get("age") } : data;
}

async function football(descriptor, context) {
  const { windowStart, windowEnd, observedAt, env, get } = context;
  check(typeof env.FOOTBALL_DATA_API_KEY === "string" && env.FOOTBALL_DATA_API_KEY.length > 0, "Football schedule credential unavailable");
  const url = new URL(descriptor.sourceURL);
  url.searchParams.set("competitions", Object.keys(descriptor.codes).join(","));
  url.searchParams.set("limit", "500");
  url.searchParams.set("dateFrom", windowStart.slice(0, 10));
  // football-data v4 dateTo is exclusive; the MLB equivalent is inclusive.
  url.searchParams.set("dateTo", windowEnd.slice(0, 10));
  const data = await get(url, { "X-Auth-Token": env.FOOTBALL_DATA_API_KEY });
  check(Array.isArray(data.matches) && data.matches.length < 500 && count(data.resultSet?.count)
    && data.resultSet.count === data.matches.length, "Football schedule incomplete");
  check(data.filters?.dateFrom === url.searchParams.get("dateFrom") && data.filters?.dateTo === url.searchParams.get("dateTo"), "Football schedule window mismatch");
  check(typeof data.filters?.competitions === "string" && data.filters.competitions.split(",").sort().join(",") === Object.keys(descriptor.codes).sort().join(","), "Football competition filter unavailable");
  unique(data.matches, (row) => row.id);
  const mapping = { SCHEDULED: "scheduled", TIMED: "scheduled", IN_PLAY: "live", PAUSED: "live", EXTRA_TIME: "live", PENALTY_SHOOTOUT: "live",
    FINISHED: "finished", POSTPONED: "postponed", SUSPENDED: "postponed", CANCELLED: "cancelled", AWARDED: "finished" };
  return data.matches.map((row) => {
    check(identifier(row.id), "Invalid upstream fixture identity");
    const compID = descriptor.codes[row.competition?.code];
    check(compID, "Unexpected football competition");
    const status = sourceStatus(row.status, mapping);
    utc(row.utcDate);
    const updatedAt = row.lastUpdated === undefined ? undefined : utc(row.lastUpdated);
    if (updatedAt) check(Date.parse(updatedAt) <= context.now.getTime() + 15 * 60_000, "Football update timestamp invalid");
    // SCHEDULED means a rough date; TIMED means a confirmed kickoff in v4.
    return { fixture: row.status === "SCHEDULED" ? null : normalize(descriptor, row.id, row.utcDate, status,
      [participant("football-data", row.homeTeam?.id, row.homeTeam?.name, "home"),
        participant("football-data", row.awayTeam?.id, row.awayTeam?.name, "away")], observedAt, url.href, updatedAt, compID),
      start: row.utcDate, competitionId: compID };
  });
}

async function mlb(descriptor, context) {
  const { windowStart, windowEnd, observedAt, get } = context;
  const url = new URL(descriptor.sourceURL);
  url.searchParams.set("sportId", "1");
  url.searchParams.set("startDate", windowStart.slice(0, 10));
  url.searchParams.set("endDate", new Date(Date.parse(windowEnd) - DAY).toISOString().slice(0, 10));
  const data = await get(url);
  check(Array.isArray(data.dates) && count(data.totalGames) && data.totalGames === data.totalItems
    && data.totalEvents === 0 && data.totalGames <= 500, "MLB schedule incomplete");
  unique(data.dates, (row) => row.date, "Duplicate MLB schedule day");
  const rows = data.dates.flatMap((entry) => {
    check(day(entry.date) && Array.isArray(entry.games) && entry.totalGames === entry.games.length
      && entry.totalItems === entry.totalGames && entry.totalEvents === 0, "MLB day incomplete");
    for (const row of entry.games) check(row.officialDate === entry.date, "MLB schedule day mismatch");
    return entry.games;
  });
  check(rows.length === data.totalGames, "MLB total count mismatch");
  unique(rows, (row) => row.gamePk);
  return rows.map((row) => {
    check(identifier(row.gamePk), "Invalid upstream fixture identity");
    // MLB's /api/v1/gameStatus enumerates these primary states. Detailed
    // challenge/weather labels change during play and must not erase games.
    const status = sourceStatus(row.status?.codedGameState, { S: "scheduled", P: "scheduled", I: "live", M: "live", N: "live",
      D: "postponed", T: "postponed", U: "postponed", C: "cancelled", F: "finished", O: "finished", Q: "finished", R: "finished", X: "unknown", W: "unknown" });
    check(name(row.status?.detailedState) && ["Preview", "Live", "Final", "Other"].includes(row.status?.abstractGameState), "MLB status schema unavailable");
    const expectedStates = { S: ["Preview"], P: ["Preview", "Live"], I: ["Live"], M: ["Live"], N: ["Live"], D: ["Final"],
      T: ["Preview", "Live"], U: ["Live"], C: ["Final"], F: ["Final"], O: ["Final"], Q: ["Final"], R: ["Final"], X: ["Other"], W: ["Other"] };
    check(expectedStates[row.status.codedGameState].includes(row.status.abstractGameState), "MLB status conflict");
    check(typeof row.status?.startTimeTBD === "boolean", "MLB time validity unavailable");
    check(["Y", "N"].includes(row.ifNecessary), "MLB conditional fixture state unavailable");
    const start = utc(row.gameDate);
    const conditional = row.ifNecessary === "Y" && status === "scheduled";
    return { start, fixture: row.status.startTimeTBD || conditional ? null : normalize(descriptor, row.gamePk, start, status,
      [participant("mlb", row.teams?.home?.team?.id, row.teams?.home?.team?.name, "home"),
        participant("mlb", row.teams?.away?.team?.id, row.teams?.away?.team?.name, "away")], observedAt, url.href) };
  });
}

async function nhl(descriptor, context) {
  const { windowStart, observedAt, get } = context;
  const pages = await Promise.all([0, 7].map(async (offset) => {
    const date = new Date(Date.parse(windowStart) + offset * DAY).toISOString().slice(0, 10);
    const url = `${descriptor.sourceURL}/${date}`;
    const data = await get(url);
    check(Array.isArray(data.gameWeek) && data.gameWeek.length === 7 && count(data.numberOfGames), "NHL schedule incomplete");
    const rows = data.gameWeek.flatMap((entry, index) => {
      const expected = new Date(Date.parse(`${date}T00:00Z`) + index * DAY).toISOString().slice(0, 10);
      check(entry.date === expected && Array.isArray(entry.games), "NHL schedule day missing");
      return entry.games;
    });
    check(rows.length === data.numberOfGames && rows.length <= 200, "NHL total count mismatch");
    return rows.map((row) => ({ row, url }));
  }));
  const rows = pages.flat();
  unique(rows, ({ row }) => row.id);
  return rows.map(({ row, url }) => {
    check(identifier(row.id), "Invalid upstream fixture identity");
    const state = sourceStatus(row.gameState, { FUT: "scheduled", PRE: "scheduled", LIVE: "live", CRIT: "live", FINAL: "finished", OFF: "finished", PPD: "postponed", CANC: "cancelled" });
    const scheduled = sourceStatus(row.gameScheduleState, { OK: state, PPD: "postponed", CNCL: "cancelled", TBD: "unknown" });
    const start = utc(row.startTimeUTC);
    const team = (value, role) => participant("nhl", value?.id,
      value?.placeName?.default && value?.commonName?.default ? `${value.placeName.default} ${value.commonName.default}` : undefined, role);
    return { start, fixture: row.gameScheduleState === "TBD" ? null : normalize(descriptor, row.id, start, scheduled,
      [team(row.homeTeam, "home"), team(row.awayTeam, "away")], observedAt, url) };
  });
}

async function wnba(descriptor, context) {
  const { now, observedAt, getWithHeaders, windowStart, windowEnd } = context;
  const { data, lastModified, age } = await getWithHeaders(descriptor.sourceURL);
  const league = data.leagueSchedule;
  // A fresh fetch of last year's season file proves no current-year coverage.
  // Do not infer an offseason/rollover grace period: the new year's feed must
  // be published and reviewed before it can establish a healthy empty lane.
  // Failed refreshes preserve prior accepted facts in the registry.
  check(league?.leagueId === "10" && /^\d{4}$/.test(league.seasonYear)
    && Number(league.seasonYear) === now.getUTCFullYear()
    && Array.isArray(league.gameDates) && league.gameDates.length > 0 && league.gameDates.length <= 366, "WNBA schedule identity unavailable");
  // meta.time has been observed four hours behind Last-Modified while labelled
  // Z. Do not repair an assumed timezone or claim it updates each game. The
  // HTTP artifact timestamp is independent publisher-generation evidence.
  utc(data.meta?.time);
  let updatedAt;
  if (lastModified !== null) {
    const parsed = new Date(lastModified);
    check(/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$/.test(lastModified)
      && Number.isFinite(parsed.getTime()) && parsed.toUTCString() === lastModified, "WNBA publisher timestamp invalid");
    check(parsed.getTime() <= now.getTime() + 5 * 60_000 && now.getTime() - parsed.getTime() <= DAY, "WNBA source timestamp stale");
    updatedAt = parsed.toISOString();
  }
  if (age !== null) check(/^\d+$/.test(age) && Number.isSafeInteger(Number(age)), "WNBA response age invalid");
  const rows = league.gameDates.flatMap((entry) => { check(Array.isArray(entry.games), "WNBA day incomplete"); return entry.games; });
  check(rows.length > 0 && rows.length <= 1000, "WNBA schedule incomplete");
  unique(rows, (row) => row.gameId);
  const live = rows.some((row) => row.gameStatus === 2 && Date.parse(row.gameDateTimeUTC) >= Date.parse(windowStart)
    && Date.parse(row.gameDateTimeUTC) < Date.parse(windowEnd));
  if (live) check((!updatedAt || now.getTime() - Date.parse(updatedAt) < 30 * 60_000)
    && (age === null || Number(age) < 1800), "WNBA publisher live evidence stale");
  return rows.map((row) => {
    check(identifier(row.gameId), "Invalid upstream fixture identity");
    const status = sourceStatus(String(row.gameStatus), { "1": "scheduled", "2": "live", "3": "finished" });
    check(["N", "Y"].includes(row.postponedStatus) && typeof row.ifNecessary === "boolean" && typeof row.gameStatusText === "string", "WNBA schedule state unavailable");
    const start = utc(row.gameDateTimeUTC);
    const team = (value, role) => participant("wnba", value?.teamId,
      value?.teamCity && value?.teamName ? `${value.teamCity} ${value.teamName}` : undefined, role);
    const pending = row.gameStatusText.trim() === "TBD" || (row.ifNecessary && status === "scheduled");
    return { start, fixture: pending ? null : normalize(descriptor, row.gameId, start,
      row.postponedStatus === "Y" ? "postponed" : status,
      [team(row.homeTeam, "home"), team(row.awayTeam, "away")], observedAt, descriptor.sourceURL, updatedAt) };
  });
}

async function espnDaily(descriptor, context) {
  const { windowStart, windowEnd, observedAt, get } = context;
  // ESPN uses the US sports calendar: a Sept 30 page includes Oct 1 UTC
  // kickoffs. Pad the first day and filter actual UTC instants afterwards.
  const dates = [];
  for (let time = Date.parse(windowStart) - DAY; time < Date.parse(windowEnd); time += DAY) dates.push(new Date(time).toISOString().slice(0, 10).replaceAll("-", ""));
  const requests = dates.flatMap((date) => (descriptor.groups || [descriptor.group]).map((group) => ({ date, group })));
  check(requests.length <= 40, "ESPN request bound exceeded");
  const rows = [];
  // At most four transports at once, all sharing the whole collection deadline.
  for (let index = 0; index < requests.length; index += 4) {
    const pages = await Promise.all(requests.slice(index, index + 4).map(async ({ date, group }) => {
      const url = new URL(descriptor.sourceURL);
      url.searchParams.set("dates", date);
      url.searchParams.set("limit", String(ESPN_CAPACITY));
      if (group) url.searchParams.set("groups", group);
      const data = await get(url);
      const league = data.leagues?.[0];
      check(Array.isArray(data.leagues) && data.leagues.length === 1 && league.id === descriptor.leagueID
        && league.slug === descriptor.path.split("/")[1] && name(league.name)
        && Date.parse(utc(league.calendarStartDate)) < Date.parse(utc(league.calendarEndDate)), "ESPN competition calendar unavailable");
      if (group) check(Array.isArray(data.groups) && data.groups.length === 1 && data.groups[0] === group, "ESPN group mismatch");
      check(Array.isArray(data.events) && data.events.length < ESPN_CAPACITY, "ESPN schedule truncated");
      unique(data.events, (row) => row.id);
      return data.events.map((row) => ({ row, url: url.href, group }));
    }));
    rows.push(...pages.flat());
  }
  const mapping = { STATUS_SCHEDULED: "scheduled", STATUS_IN_PROGRESS: "live", STATUS_FIRST_HALF: "live", STATUS_SECOND_HALF: "live", STATUS_HALFTIME: "live",
    STATUS_END_PERIOD: "live", STATUS_OVERTIME: "live", STATUS_FINAL: "finished", STATUS_FULL_TIME: "finished", STATUS_POSTPONED: "postponed",
    STATUS_SUSPENDED: "postponed", STATUS_CANCELED: "cancelled", STATUS_CANCELLED: "cancelled", STATUS_DELAYED: "unknown" };
  const normalized = rows.map(({ row, url, group }) => {
    check(identifier(row.id), "Invalid upstream fixture identity");
    const sportID = { basketball: "40", football: "20", soccer: "600" }[descriptor.path.split("/")[0]];
    check(row.uid === `s:${sportID}~l:${descriptor.leagueID}~e:${row.id}`,
      "ESPN event identity mismatch");
    check(Array.isArray(row.competitions) && row.competitions.length === 1, "ESPN event topology unavailable");
    const match = row.competitions[0];
    check(String(match.id) === String(row.id) && typeof match.timeValid === "boolean"
      && Array.isArray(match.competitors) && match.competitors.length === 2, "ESPN match schema unavailable");
    check(match.date === row.date && (!match.startDate || match.startDate === row.date), "ESPN kickoff conflict");
    const start = utc(row.date);
    const status = sourceStatus(row.status?.type?.name, mapping);
    check(typeof row.status.type.completed === "boolean" && ["pre", "in", "post"].includes(row.status.type.state), "ESPN status schema unavailable");
    if (status === "finished") check(row.status.type.completed && row.status.type.state === "post", "ESPN final state conflict");
    if (status === "live") check(!row.status.type.completed && row.status.type.state === "in", "ESPN live state conflict");
    const team = (role) => {
      const item = match.competitors.find((candidate) => candidate.homeAway === role);
      check(item?.type === "team" && String(item.id) === String(item.team?.id), "ESPN participant schema unavailable");
      return participant(`espn:${descriptor.path.split("/")[1]}`, item.team.id, item.team.displayName, role);
    };
    const teams = [team("home"), team("away")];
    return { start, fixture: match.timeValid ? normalize(descriptor, row.id, start, status, teams, observedAt, url) : null,
      providerID: row.id, group, agreement: JSON.stringify({ uid: row.uid, start, status, timeValid: match.timeValid,
        participants: match.competitors.map((item) => ({ role: item.homeAway, id: item.team.id, name: item.team.displayName }))
          .sort((a, b) => a.role.localeCompare(b.role)), squad: { gender: descriptor.gender, ageGroup: descriptor.ageGroup } }) };
  });
  const merged = new Map();
  for (const row of normalized) {
    const old = merged.get(row.providerID);
    if (old) {
      check(descriptor.groups && old.group !== row.group, "Duplicate upstream fixture");
      check(old.agreement === row.agreement, "Conflicting ESPN fixture across groups");
    } else merged.set(row.providerID, row);
  }
  return [...merged.values()].map(({ start, fixture }) => ({ start, fixture }));
}

export async function collectSportsSource(descriptor, now, env = {}, fetchImpl = fetch) {
  const known = SPORTS_SOURCES.find((item) => item.id === descriptor?.id);
  check(known?.supported, "Unknown sports schedule source");
  const window = sportsFixtureWindow(now);
  const observedAt = now.toISOString();
  const deadline = coachDeadline(undefined, 12_000);
  try {
    const context = { ...window, observedAt, now, env,
      get: (url, headers) => requestJSON(url, deadline, fetchImpl, headers),
      getWithHeaders: (url) => requestJSON(url, deadline, fetchImpl, {}, true) };
    const adapters = { "football-data": football, mlb, nhl, wnba, espn: espnDaily };
    const rows = await abortable(() => adapters[known.adapter](known, context), deadline.signal);
    const relevant = rows.filter((row) => Date.parse(row.start) >= Date.parse(window.windowStart) && Date.parse(row.start) < Date.parse(window.windowEnd));
    const fixtures = relevant.flatMap((row) => row.fixture ? [row.fixture] : []).sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
    const pendingByCompetition = Object.fromEntries(known.competitions.map((item) => [item.id, 0]));
    for (const row of relevant) if (!row.fixture) pendingByCompetition[row.competitionId || known.competitions[0].id]++;
    return { fixtures, pendingFixtureCount: relevant.length - fixtures.length, pendingByCompetition, observedAt, ...window };
  } finally { deadline.dispose(); }
}
