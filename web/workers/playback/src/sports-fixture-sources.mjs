import { abortable, boundedJSON, coachDeadline } from "./coach-safety.mjs";
import { normalizeUCLReportedScore } from "./ucl-reported-score-policy.mjs";

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
      competition("champions-league", "UEFA Champions League", "football"),
      competition("la-liga", "La Liga", "football"), competition("serie-a", "Serie A", "football"),
      competition("bundesliga", "Bundesliga", "football"), competition("ligue-1", "Ligue 1", "football")],
    codes: { PL: "premier-league", CL: "champions-league", PD: "la-liga", SA: "serie-a", BL1: "bundesliga", FL1: "ligue-1" }, gender: "men", ageGroup: "senior",
    sourceName: "football-data.org", sourceURL: "https://api.football-data.org/v4/matches" },
  single("efl-carabao-cup", "Carabao Cup", "football", "efl", "https://multi-club-matches.webapi.gc.eflservices.co.uk/v2/matches", {
    competitions: [competition("carabao-cup", "Carabao Cup", "football")],
    sourceName: "EFL", publisherCompetitionID: "2", activationFlag: "FOTTY_SPORTS_EFL_ENABLED",
    permissionStatus: "official-public-metadata-separate-activation",
  }),
  single("mlb", "Major League Baseball", "baseball", "mlb", "https://statsapi.mlb.com/api/v1/schedule"),
  single("nhl", "National Hockey League", "hockey", "nhl", "https://api-web.nhle.com/v1/schedule"),
  single("wnba", "Women's National Basketball Association", "basketball", "wnba",
    "https://cdn.wnba.com/static/json/staticData/scheduleLeagueV2.json", { gender: "women" }),
  espn("nba", "National Basketball Association", "basketball", "basketball/nba", "46"),
  espn("nfl", "National Football League", "american-football", "football/nfl", "28"),
  espn("college-football", "NCAA Football", "american-football", "football/college-football", "23", { groups: ["80", "81"], ageGroup: "college" }),
  espn("college-basketball-men", "NCAA Division I Men's Basketball", "basketball", "basketball/mens-college-basketball", "41", { group: "50", ageGroup: "college" }),
  espn("college-basketball-women", "NCAA Division I Women's Basketball", "basketball", "basketball/womens-college-basketball", "54", { group: "50", gender: "women", ageGroup: "college" }),
  espn("mls", "Major League Soccer", "football", "soccer/usa.1", "770"),
  // National-team football. The same exact team/date admission applies;
  // League IDs and slugs were read from ESPN's own scoreboard on 10 Nov 2026.
  espn("uefa-nations-league", "UEFA Nations League", "football", "soccer/uefa.nations", "2395"),
  espn("international-friendlies", "International Friendlies", "football", "soccer/fifa.friendly", "3922"),
  espn("concacaf-nations-league", "Concacaf Nations League", "football", "soccer/concacaf.nations.league", "19267"),
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

// Football clocks are observations, never time elapsed since the scheduled start.
// Both ESPN (45'+2') and the EFL (45' +2') publish a base minute and added time.
function footballMinute(value, injuryTime) {
  if (typeof value === "string") {
    const match = /^(\d{1,3})['′]?(?:\s*\+\s*(\d{1,2})['′]?)?$/.exec(value.trim());
    if (!match) return undefined;
    value = Number(match[1]);
    if (match[2] !== undefined) injuryTime = Number(match[2]);
  }
  if (!count(value) || value > 150 || (injuryTime != null && (!count(injuryTime) || injuryTime > 99))) return undefined;
  return injuryTime ? `${value}+${injuryTime}′` : `${value}′`;
}
function attachFootballLive(fixture, home, away, clock) {
  if (fixture?.sport !== "football" || fixture.status !== "live") return;
  const hasScore = count(home) && home <= 99 && count(away) && away <= 99;
  if (clock || hasScore) fixture.footballLive = { ...(hasScore ? { home, away } : {}), ...(clock ? { clock } : {}) };
}

export function sportsFixtureWindow(now) {
  check(now instanceof Date && Number.isFinite(now.getTime()), "Invalid collection time");
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return { windowStart: new Date(today - DAY).toISOString(), windowEnd: new Date(today + 8 * DAY).toISOString() };
}

async function requestJSON(url, deadline, fetchImpl, headers = {}, withHeaders = false, allowEFLEmpty = false) {
  // Workers supports manual/follow, not the Node fetch "error" mode. Never
  // follow a redirect with a credential or accept an alternate publisher.
  // No edge cache: the collector polls at most every 5 minutes, so a cached
  // body can only ever be an older copy. On 21 Nov a stale football-data body
  // (rows last updated at 00:20) published in-play Premier League matches as
  // "scheduled" and made a finished match look regressed, freezing the league.
  const response = await abortable(() => fetchImpl(url, { signal: deadline.signal, redirect: "manual",
    headers: { Accept: "application/json", ...headers } }), deadline.signal);
  // EFL's published Match Centre API returns this exact JSON error, rather
  // than a 200 empty list, when the requested Cup window has no matches. This
  // exception belongs only to that exact activated adapter and request route.
  const eflEmptyResponse = allowEFLEmpty && withHeaders && response.status === 404
    && url.origin === "https://multi-club-matches.webapi.gc.eflservices.co.uk" && url.pathname === "/v2/matches";
  if ((!response.ok && !eflEmptyResponse) || response.redirected || response.status >= 300 && response.status < 400) {
    throw Object.assign(new Error("Sports schedule upstream unavailable"), { fixtureHTTPStatus: response.status });
  }
  const contentType = response.headers.get("content-type") || "";
  // The league-owned WNBA JSON file is served as text/plain. Its exact
  // allowlisted URL and complete typed league schema remain mandatory.
  const wnbaText = String(url) === "https://cdn.wnba.com/static/json/staticData/scheduleLeagueV2.json" && /^text\/plain(?:\s*;|$)/i.test(contentType);
  check(wnbaText || /(?:^|\/)json(?:\s*;|$)|\+json(?:\s*;|$)/i.test(contentType), "Sports schedule is not JSON");
  const data = await boundedJSON(response, MAX_BYTES, deadline.signal);
  if (eflEmptyResponse) {
    const error = data?.errors?.[0];
    check(data && !Array.isArray(data) && Object.keys(data).length === 1
      && Array.isArray(data.errors) && data.errors.length === 1
      && error && !Array.isArray(error) && Object.keys(error).length === 3
      && error.detail === "No matches found" && error.title === "Not Found" && error.status === "404",
    "EFL empty-window response unrecognized");
  }
  return withHeaders ? { data, lastModified: response.headers.get("last-modified"), age: response.headers.get("age"),
    date: response.headers.get("date"), ...(eflEmptyResponse ? { emptyEFLWindow: true } : {}) } : data;
}

async function efl(descriptor, context) {
  const { now, env, observedAt, windowStart, windowEnd, getWithHeaders } = context;
  check(env.FOTTY_SPORTS_EFL_ENABLED === "1", "EFL fixture activation pending");
  // This is the request advertised by EFL's own Match Centre. Competition 2
  // is Carabao Cup; football-data's ELC code is the separate Championship.
  const season = now.getUTCFullYear() - (now.getUTCMonth() < 6 ? 1 : 0);
  const url = new URL(descriptor.sourceURL);
  const date = (value) => value.toISOString().slice(0, 19).replace("T", " ") + "Z";
  url.search = new URLSearchParams({ from: date(new Date(windowStart)),
    to: date(new Date(Date.parse(windowEnd) - 1000)), competitionID: descriptor.publisherCompetitionID,
    seasonID: String(season), "page.size": "100" });
  const { data, date: responseDate, age, emptyEFLWindow } = await getWithHeaders(url);
  const generated = new Date(responseDate);
  check(typeof responseDate === "string" && generated.toUTCString() === responseDate
    && generated.getTime() <= now.getTime() + 300_000
    && now.getTime() - generated.getTime() <= 6 * 3600_000, "EFL publisher receipt invalid");
  check(age === null || /^\d+$/.test(age) && Number.isSafeInteger(Number(age)), "EFL response age invalid");
  // No fixture, synthetic self-link or kickoff is manufactured from the error.
  // Durable admission still protects a previously accepted active fixture from
  // disappearing merely because a later publisher response is empty.
  if (emptyEFLWindow) return [];
  check(Array.isArray(data.data) && data.data.length < 100 && count(data.meta?.totalCount)
    && data.meta.totalCount === data.meta.count && data.meta.count === data.data.length, "EFL schedule incomplete");
  const self = typeof data.links?.self === "string" ? new URL(data.links.self) : null;
  check(self && self.origin === url.origin && self.pathname === url.pathname
    && !self.username && !self.password && !self.hash
    && [...url.searchParams].every(([key, value]) => self.searchParams.getAll(key).length === 1
      && self.searchParams.get(key) === value)
    && [...self.searchParams.keys()].every((key) => url.searchParams.has(key))
    && !data.links.next && !data.links.prev, "EFL schedule scope mismatch");
  unique(data.data, (row) => row.id);
  const periods = { PreMatch: "scheduled", FirstHalf: "live", HalfTime: "live", SecondHalf: "live",
    ExtraFirstHalf: "live", ExtraHalfTime: "live", ExtraSecondHalf: "live", ShootOut: "live", Penalties: "live",
    FullTime: "finished", Postponed: "postponed", Cancelled: "cancelled", Abandoned: "cancelled", Suspended: "unknown" };
  return data.data.map((row) => {
    const item = row.attributes;
    check(row.type === "match" && /^g[1-9]\d{0,11}$/.test(row.id) && item?.competitionID === Number(descriptor.publisherCompetitionID),
      "EFL fixture identity mismatch");
    check(typeof item.kickOffDateUTC === "string" && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(item.kickOffDateUTC),
      "EFL kickoff is not explicit UTC");
    const start = utc(item.kickOffDateUTC.replace(" ", "T") + "Z");
    check(Date.parse(start) >= Date.parse(windowStart) && Date.parse(start) < Date.parse(windowEnd), "EFL schedule window mismatch");
    check(item.TBC === null || typeof item.TBC === "boolean", "EFL provisional state unavailable");
    const status = sourceStatus(item.matchPeriod, periods);
    if (status === "live") check(now.getTime() - generated.getTime() < 30 * 60_000
      && (age === null || Number(age) < 1800), "Publisher live evidence stale");
    const team = (value, role) => {
      if (!name(value?.name) || /^(?:TBD|TBC|T\.B\.[CD]\.|To be (?:confirmed|determined)|Winner\b|Loser\b)/i.test(value.name.trim())) return null;
      // The published fixture supplies a stable match ID and explicit names,
      // not participant IDs. Namespace whole names; never use a crest as ID.
      const key = value.name.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase()
        .split(/[^a-z0-9]+/).filter(Boolean).join("-");
      check(key && key.length <= 80, "EFL participant identity unavailable");
      return { id: `efl:team:${key}`, name: value.name.trim(), role };
    };
    const teams = [team(item.homeTeam, "home"), team(item.awayTeam, "away")];
    check(!teams.every(Boolean) || teams[0].id !== teams[1].id, "EFL duplicate participants");
    const fixture = item.TBC || !teams.every(Boolean) ? null : {
      id: `sports-fixture:carabao-cup:${row.id}`, sport: "football", competitionId: "carabao-cup", competitionName: "Carabao Cup",
      start, status, eventKind: "match", title: `${teams[0].name} vs ${teams[1].name}`, participants: teams,
      squad: { gender: "men", ageGroup: "senior" },
      source: { name: "EFL", url: url.href, observedAt, updatedAt: generated.toISOString() },
    };
    if (fixture?.status === "live") {
      const phase = { HalfTime: "HT", ExtraHalfTime: "HT", ShootOut: "PEN", Penalties: "PEN" }[item.matchPeriod];
      const clock = phase ?? footballMinute(item.formattedMatchTime) ?? footballMinute(item.matchMinutes);
      attachFootballLive(fixture, item.homeTeam.score, item.awayTeam.score, clock);
    }
    return { start, fixture };
  });
}

async function football(descriptor, context) {
  const { windowStart, windowEnd, observedAt, env, get } = context;
  check(typeof env.FOOTBALL_DATA_API_KEY === "string" && env.FOOTBALL_DATA_API_KEY.length > 0, "Football schedule credential unavailable");
  // One request per league. On 21 Nov the combined /v4/matches body kept
  // in-play Premier League rows at their 00:20 values for hours while
  // /v4/competitions/PL/matches was current, freezing every live status.
  // The per-league endpoint's dateTo is inclusive and it does not echo date
  // filters, so the window is proved from resultSet and every row instead.
  const dateFrom = windowStart.slice(0, 10);
  const dateTo = new Date(Date.parse(windowEnd) - DAY).toISOString().slice(0, 10);
  const matches = [];
  for (const code of Object.keys(descriptor.codes)) {
    const url = new URL(`competitions/${code}/matches`, descriptor.sourceURL.replace(/matches$/, ""));
    url.searchParams.set("dateFrom", dateFrom);
    url.searchParams.set("dateTo", dateTo);
    const data = await get(url, { "X-Auth-Token": env.FOOTBALL_DATA_API_KEY });
    check(Array.isArray(data.matches) && data.matches.length < 500 && count(data.resultSet?.count)
      && data.resultSet.count === data.matches.length, "Football schedule incomplete");
    check(data.competition?.code === code, "Football competition filter unavailable");
    const inWindow = (day) => typeof day === "string" && day.slice(0, 10) >= dateFrom && day.slice(0, 10) <= dateTo;
    check(data.matches.length === 0 || inWindow(data.resultSet.first) && inWindow(data.resultSet.last), "Football schedule window mismatch");
    for (const row of data.matches) {
      check(inWindow(row.utcDate), "Football schedule window mismatch");
      check(row.competition === undefined || row.competition?.code === code, "Unexpected football competition");
      matches.push({ ...row, competition: { ...row.competition, code }, sourceHref: url.href });
    }
  }
  check(matches.length < 500, "Football schedule incomplete");
  const data = { matches };
  unique(data.matches, (row) => row.id);
  const mapping = { SCHEDULED: "scheduled", TIMED: "scheduled", IN_PLAY: "live", PAUSED: "live", EXTRA_TIME: "live", PENALTY_SHOOTOUT: "live",
    FINISHED: "finished", POSTPONED: "postponed", SUSPENDED: "postponed", CANCELLED: "cancelled", AWARDED: "finished" };
  const liveNames = new Map();
  const rows = data.matches.map((row) => {
    check(identifier(row.id), "Invalid upstream fixture identity");
    const compID = descriptor.codes[row.competition?.code];
    check(compID, "Unexpected football competition");
    const status = sourceStatus(row.status, mapping);
    utc(row.utcDate);
    const updatedAt = row.lastUpdated === undefined ? undefined : utc(row.lastUpdated);
    if (updatedAt) check(Date.parse(updatedAt) <= context.now.getTime() + 15 * 60_000, "Football update timestamp invalid");
    // SCHEDULED means a rough date; TIMED means a confirmed kickoff in v4.
    const fixture = row.status === "SCHEDULED" ? null : normalize(descriptor, row.id, row.utcDate, status,
      [participant("football-data", row.homeTeam?.id, row.homeTeam?.name, "home"),
        participant("football-data", row.awayTeam?.id, row.awayTeam?.name, "away")], observedAt, row.sourceHref, updatedAt, compID);
    const reportedScore = fixture ? normalizeUCLReportedScore(row, fixture) : undefined;
    if (reportedScore) fixture.reportedScore = reportedScore;
    if (fixture?.status === "live" && updatedAt) {
      const shootout = row.status === "PENALTY_SHOOTOUT" || row.score?.duration === "PENALTY_SHOOTOUT";
      const phase = shootout ? "PEN" : row.status === "PAUSED" ? "HT" : undefined;
      const clock = phase ?? footballMinute(row.minute, row.injuryTime) ?? (row.status === "EXTRA_TIME" ? "ET" : undefined);
      // football-data's cumulative fullTime includes penalties. Subtract its
      // explicit shootout totals to preserve match goals as the score advances.
      const matchGoals = (side) => {
        const total = row.score?.fullTime?.[side];
        if (!shootout) return total;
        const penalties = row.score?.penalties?.[side];
        return count(total) && count(penalties) && total >= penalties ? total - penalties : undefined;
      };
      attachFootballLive(fixture, matchGoals("home"), matchGoals("away"), clock);
    }
    if (fixture) liveNames.set(fixture.id, { home: [row.homeTeam?.name, row.homeTeam?.shortName],
      away: [row.awayTeam?.name, row.awayTeam?.shortName] });
    return { fixture,
      start: row.utcDate, competitionId: compID };
  });
  if (env.FOTTY_FOOTBALL_LIVE_OVERLAY !== "0" && context.getOverlay) {
    await overlayESPNFootballLive(rows.flatMap((row) => row.fixture ? [row.fixture] : []), liveNames, context);
  }
  return rows;
}

// Owner decision 21 Nov 2026: football-data marks kickoffs late (Newcastle-
// Arsenal still TIMED five minutes in) and the big European leagues have no
// free official live feed. ESPN's public scoreboard, already used for MLS and
// national teams, is a live layer only: it can turn a scheduled row live and
// add score/minute, never finish, cancel, add or remove a fixture. A row is
// touched only when ESPN says in progress, kickoff agrees within five minutes
// and both teams match in their roles, uniquely. ESPN failures are ignored.
const ESPN_LIVE_LEAGUES = Object.freeze({ "champions-league": "uefa.champions", "la-liga": "esp.1",
  "serie-a": "ita.1", "bundesliga": "ger.1", "ligue-1": "fra.1" });
const TEAM_NAME_NOISE = new Set(["fc", "cf", "ac", "as", "ss", "ssc", "sc", "us", "afc", "cd", "ud", "sd", "rcd", "rc",
  "club", "calcio", "de", "del", "la", "le", "sv", "vfl", "vfb", "tsg", "fsv", "bsc", "osc", "ogc", "fk", "sk", "rb", "stade"]);

export function teamNameTokens(value) {
  if (typeof value !== "string") return new Set();
  return new Set(value.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase().replace(/ß/g, "ss")
    .split(/[^a-z0-9]+/).filter((token) => token && !TEAM_NAME_NOISE.has(token) && !/^\d+$/.test(token)));
}

export function sameTeamName(ours, theirs) {
  for (const left of ours.map(teamNameTokens)) for (const right of theirs.map(teamNameTokens)) {
    if (!left.size || !right.size) continue;
    if ([...left].every((token) => right.has(token)) || [...right].every((token) => left.has(token))) return true;
  }
  return false;
}

async function overlayESPNFootballLive(fixtures, names, context) {
  const now = context.now.getTime();
  const candidates = fixtures.filter((fixture) => ESPN_LIVE_LEAGUES[fixture.competitionId] && fixture.status === "scheduled"
    && Date.parse(fixture.start) <= now + 5 * 60_000 && Date.parse(fixture.start) >= now - 3 * 3_600_000);
  const leagues = [...new Set(candidates.map((fixture) => fixture.competitionId))];
  await Promise.all(leagues.map(async (competitionId) => {
    let events;
    try {
      const url = new URL(`https://site.api.espn.com/apis/site/v2/sports/soccer/${ESPN_LIVE_LEAGUES[competitionId]}/scoreboard`);
      // ESPN pages follow the US Eastern calendar day.
      url.searchParams.set("dates", new Date(now - 5 * 3_600_000).toISOString().slice(0, 10).replaceAll("-", ""));
      const data = await context.getOverlay(url);
      if (data?.leagues?.[0]?.slug !== ESPN_LIVE_LEAGUES[competitionId] || !Array.isArray(data.events)) return;
      events = data.events;
    } catch { return; }
    const inPlay = events.flatMap((event) => {
      const match = event?.competitions?.[0];
      const state = event?.status?.type;
      if (state?.state !== "in" || state.completed !== false || !Array.isArray(match?.competitors) || match.competitors.length !== 2) return [];
      const side = (role) => match.competitors.find((item) => item?.homeAway === role);
      const home = side("home"), away = side("away");
      const kickoff = Date.parse(event.date);
      if (!home?.team || !away?.team || !Number.isFinite(kickoff)) return [];
      return [{ kickoff, home, away, status: event.status }];
    });
    const local = candidates.filter((fixture) => fixture.competitionId === competitionId);
    const pairs = [];
    for (const event of inPlay) for (const fixture of local) {
      const teams = names.get(fixture.id);
      if (!teams || Math.abs(Date.parse(fixture.start) - event.kickoff) > 5 * 60_000) continue;
      const espnNames = (item) => [item.team.displayName, item.team.shortDisplayName, item.team.name];
      if (sameTeamName(teams.home, espnNames(event.home)) && sameTeamName(teams.away, espnNames(event.away))) pairs.push({ event, fixture });
    }
    for (const { event, fixture } of pairs) {
      if (pairs.filter((pair) => pair.event === event || pair.fixture === fixture).length !== 1) continue;
      const score = (item) => typeof item.score === "string" && /^\d{1,2}$/.test(item.score) ? Number(item.score) : undefined;
      const phase = event.status.type.name === "STATUS_HALFTIME" ? "HT" : undefined;
      const clock = phase ?? footballMinute(event.status.displayClock) ?? footballMinute(event.status.type.shortDetail);
      fixture.status = "live";
      fixture.source = { ...fixture.source, updatedAt: context.observedAt };
      fixture.liveEvidence = "espn";
      attachFootballLive(fixture, score(event.home), score(event.away), clock);
    }
  }));
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

export const NHL_PAGE_GAP_MS = 1_000;

// Owner decision (22 Nov 2026): when the NHL API refuses (HTTP 429 or a server
// error), the last accepted NHL schedule is kept with its own IDs, teams,
// times and provenance, and each game's status comes from ESPN's public NHL
// scoreboard (a unique same-team match within 15 minutes of the accepted
// start). ESPN never adds, moves or renames a game, and a finished, cancelled
// or postponed game never becomes active again.
const NHL_ESPN_STATUS = Object.freeze({ STATUS_POSTPONED: "postponed", STATUS_CANCELED: "cancelled" });

async function nhl(descriptor, context) {
  try { return await nhlSchedule(descriptor, context); } catch (error) {
    const status = error?.fixtureHTTPStatus;
    if (status !== 429 && !(status >= 500 && status <= 599)) throw error;
    const rows = await nhlFromESPN(descriptor, context);
    if (!rows) throw error;
    return rows;
  }
}

async function nhlFromESPN(descriptor, context) {
  const accepted = (context.previous?.fixtures || []).filter((fixture) => fixture.competitionId === "nhl"
    && fixture.sport === descriptor.sport && typeof fixture.source?.url === "string"
    && fixture.source.url.startsWith(`${descriptor.sourceURL}/`));
  if (!accepted.length) return null;
  const day = (instant) => new Date(instant - 5 * 3_600_000).toISOString().slice(0, 10).replaceAll("-", "");
  const url = new URL("https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard");
  url.searchParams.set("dates", `${day(Date.parse(context.windowStart))}-${day(Date.parse(context.windowEnd))}`);
  url.searchParams.set("limit", "500");
  let events;
  try {
    const data = await context.getOverlay(url);
    if (data?.leagues?.[0]?.slug !== "nhl" || !Array.isArray(data.events) || data.events.length > 500) return null;
    events = data.events;
  } catch { return null; }
  const games = events.flatMap((event) => {
    const competitors = event?.competitions?.[0]?.competitors;
    const side = (role) => Array.isArray(competitors) ? competitors.find((item) => item?.homeAway === role)?.team : undefined;
    const home = side("home"), away = side("away"), start = Date.parse(event?.date), type = event?.status?.type;
    if (!home || !away || !Number.isFinite(start) || !type) return [];
    const names = (team) => [team.displayName, team.shortDisplayName, team.name].filter((name) => typeof name === "string");
    const status = NHL_ESPN_STATUS[type.name] || (type.state === "in" ? "live"
      : type.state === "post" && type.completed === true ? "finished" : type.state === "pre" ? "scheduled" : undefined);
    return status ? [{ home: names(home), away: names(away), start, status }] : [];
  });
  return accepted.map((fixture) => {
    const { verification: _marker, ...source } = fixture.source;
    const ours = (role) => fixture.participants?.find((item) => item.role === role)?.name;
    const matches = games.filter((game) => Math.abs(game.start - Date.parse(fixture.start)) <= 15 * 60_000
      && ours("home") && ours("away") && sameTeamName([ours("home")], game.home) && sameTeamName([ours("away")], game.away));
    const terminal = ["finished", "cancelled", "postponed"].includes(fixture.status);
    const status = matches.length === 1 && !terminal ? matches[0].status : fixture.status;
    const { liveEvidence: _evidence, footballLive: _live, ...rest } = fixture;
    return { start: fixture.start, fixture: { ...rest, status, source: { ...source, observedAt: context.observedAt },
      ...(matches.length === 1 && !terminal ? { liveEvidence: "espn" } : {}) } };
  });
}

async function nhlSchedule(descriptor, context) {
  const { windowStart, observedAt, get } = context;
  // The two weekly pages are requested one after another, never as a
  // simultaneous burst: the NHL API rate-limits Worker traffic (HTTP 429 on
  // most refreshes, 20-22 Nov 2026).
  const pages = [];
  for (const offset of [0, 7]) {
    if (pages.length) await new Promise((resolve) => setTimeout(resolve, NHL_PAGE_GAP_MS));
    pages.push(await nhlPage(offset));
  }
  async function nhlPage(offset) {
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
  }
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
    const fixture = match.timeValid ? normalize(descriptor, row.id, start, status, teams, observedAt, url) : null;
    if (fixture?.sport === "football" && status === "live") {
      const score = (role) => {
        const value = match.competitors.find((item) => item.homeAway === role).score;
        return typeof value === "string" && /^\d{1,2}$/.test(value) ? Number(value) : value;
      };
      const phase = row.status.type.name === "STATUS_HALFTIME" ? "HT" : undefined;
      const clock = phase ?? footballMinute(row.status.displayClock) ?? footballMinute(row.status.type.shortDetail)
        ?? (row.status.type.name === "STATUS_OVERTIME" ? "ET" : undefined);
      attachFootballLive(fixture, score("home"), score("away"), clock);
    }
    return { start, fixture,
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

export async function collectSportsSource(descriptor, now, env = {}, fetchImpl = fetch, { previous } = {}) {
  const known = SPORTS_SOURCES.find((item) => item.id === descriptor?.id);
  check(known?.supported, "Unknown sports schedule source");
  const window = sportsFixtureWindow(now);
  const observedAt = now.toISOString();
  const deadline = coachDeadline(undefined, 12_000);
  try {
    const context = { ...window, observedAt, now, env, previous,
      get: (url, headers) => requestJSON(url, deadline, fetchImpl, headers),
      getWithHeaders: (url) => requestJSON(url, deadline, fetchImpl, {}, true, known.id === "efl-carabao-cup"),
      // The live layer has its own short bound so it can never consume the
      // collection's deadline or fail the schedule it decorates.
      getOverlay: async (url) => {
        const overlayDeadline = coachDeadline(undefined, 4_000);
        try { return await requestJSON(url, overlayDeadline, fetchImpl); } finally { overlayDeadline.dispose(); }
      } };
    const adapters = { "football-data": football, efl, mlb, nhl, wnba, espn: espnDaily };
    const rows = await abortable(() => adapters[known.adapter](known, context), deadline.signal);
    const relevant = rows.filter((row) => Date.parse(row.start) >= Date.parse(window.windowStart) && Date.parse(row.start) < Date.parse(window.windowEnd));
    const fixtures = relevant.flatMap((row) => row.fixture ? [row.fixture] : []).sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
    const pendingByCompetition = Object.fromEntries(known.competitions.map((item) => [item.id, 0]));
    const pendingStartsByCompetition = Object.fromEntries(known.competitions.map((item) => [item.id, []]));
    for (const row of relevant) if (!row.fixture) {
      const id = row.competitionId || known.competitions[0].id;
      pendingByCompetition[id]++;
      // A provisional publisher date is internal polling evidence only. It
      // does not become a fixture, confirmed kickoff, countdown or reminder.
      pendingStartsByCompetition[id].push(new Date(row.start).toISOString());
    }
    return { fixtures, pendingFixtureCount: relevant.length - fixtures.length, pendingByCompetition,
      pendingStartsByCompetition, observedAt, ...window };
  } finally { deadline.dispose(); }
}
