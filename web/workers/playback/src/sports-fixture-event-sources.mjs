import { abortable, boundedJSON, coachDeadline } from "./coach-safety.mjs";

// These are public feeds used by ESPN's own products, not a documented or
// licensed third-party API. Enabling them remains an explicit service decision.
const SITE_ORIGIN = "https://site.api.espn.com";
const CORE_ORIGIN = "https://sports.core.api.espn.com";
const DAY = 86_400_000;
const MAX_REQUESTS = 40;
const MAX_PAGE_BYTES = 2_000_000;
const MAX_FIXTURES = 1_000;

function descriptor(id, sport, competitionId, competitionName, adapter, path, extra = {}) {
  return Object.freeze({ id, sport, competitionId, competitionName, adapter, path, supported: true,
    publicUndocumented: true, permissionStatus: "deployment-review-required",
    competitions: Object.freeze([Object.freeze({ id: competitionId, name: competitionName, sport })]), ...extra });
}
function unsupported(id, sport, competitionId, competitionName, reason) {
  return Object.freeze({ id, sport, competitionId, competitionName, supported: false, reason,
    competitions: Object.freeze([Object.freeze({ id: competitionId, name: competitionName, sport })]) });
}

export const SPORTS_EVENT_SOURCES = Object.freeze([
  descriptor("tennis-atp", "tennis", "atp", "ATP men's singles and doubles", "tennis", "tennis/atp", { leagueId: "851", gender: "men" }),
  descriptor("tennis-wta", "tennis", "wta", "WTA women's singles and doubles", "tennis", "tennis/wta", { leagueId: "900", gender: "women" }),
  descriptor("golf-pga", "golf", "pga", "PGA Tour", "tournament", "golf/pga", { leagueId: "1106", gender: "men" }),
  descriptor("golf-lpga", "golf", "lpga", "LPGA Tour", "tournament", "golf/lpga", { leagueId: "1107", gender: "women" }),
  descriptor("golf-eur", "golf", "dp-world-tour", "DP World Tour", "tournament", "golf/eur", { leagueId: "7002", gender: "men" }),
  descriptor("racing-f1", "motorsport", "formula-1", "Formula 1", "session", "racing/f1", { leagueId: "2030", requireSessionType: true }),
  descriptor("racing-irl", "motorsport", "indycar", "IndyCar Series", "session", "racing/irl", { leagueId: "2040" }),
  descriptor("racing-nascar-premier", "motorsport", "nascar-cup", "NASCAR Cup Series", "session", "racing/nascar-premier", { leagueId: "2021" }),
  descriptor("fight-ufc", "fight", "ufc", "Ultimate Fighting Championship", "card", "mma/ufc", { leagueId: "3321", gender: "mixed" }),
  descriptor("rugby-prem", "rugby", "rugby-prem", "Prem Rugby", "core", "rugby/leagues/267979"),
  descriptor("rugby-urc", "rugby", "rugby-urc", "United Rugby Championship", "core", "rugby/leagues/270557"),
  descriptor("rugby-top14", "rugby", "rugby-top14", "French Top 14", "core", "rugby/leagues/270559"),
  descriptor("rugby-nrl", "rugby", "nrl", "National Rugby League", "core", "rugby-league/leagues/3"),
  descriptor("afl", "afl", "afl", "Australian Football League", "core", "australian-football/leagues/afl"),
  unsupported("fight-boxing", "fight", "boxing", "Boxing", "No verified complete public schedule with explicit UTC start times; ESPN does not expose a boxing scoreboard league."),
  unsupported("darts-pdc", "darts", "pdc", "PDC darts", "The official PDC feed exposes local startDate/startTime without a verified timezone; bounded date filtering and live-status semantics need verification."),
]);

export function sportsEventWindow(now) {
  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) throw new Error("Invalid fixture clock");
  const day = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return { from: new Date(day - DAY), to: new Date(day + 8 * DAY) };
}

function label(value) {
  if (typeof value !== "string" || !value.trim() || value.length > 240 || /[\u0000-\u001f<>]/.test(value)) throw new Error("Invalid sports event label");
  return value.trim();
}
function identity(value) {
  const id = String(value ?? "");
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(id)) throw new Error("Invalid sports event identity");
  return id;
}
function startTime(value) {
  if (typeof value !== "string") return null;
  const parts = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/);
  if (!parts) return null;
  const [year, month, day, hour, minute, second] = parts.slice(1, 7).map((v) => Number(v || 0));
  const calendar = new Date(Date.UTC(year, month - 1, day));
  if (calendar.getUTCFullYear() !== year || calendar.getUTCMonth() !== month - 1 || calendar.getUTCDate() !== day
    || hour > 23 || minute > 59 || second > 59) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

// `state: post` also occurs for cancellations; names must take precedence over
// state. Unknown names never become a scheduled/live fixture by inference.
export function sportsEventStatus(status) {
  const type = status?.type;
  if (!type || typeof type.name !== "string") throw new Error("Unknown sports event status");
  if (["STATUS_CANCELED", "STATUS_CANCELLED", "STATUS_ABANDONED"].includes(type.name)) return "cancelled";
  if (type.name === "STATUS_POSTPONED") return "postponed";
  if (["STATUS_FINAL", "STATUS_FINAL_OVERTIME", "STATUS_FINAL_SHOOTOUT", "STATUS_RETIRED", "STATUS_WALKOVER"].includes(type.name) && type.completed === true && type.state === "post") return "finished";
  if (type.name === "STATUS_SCHEDULED" && type.state === "pre" && type.completed === false) return "scheduled";
  if (["STATUS_IN_PROGRESS", "STATUS_HALFTIME", "STATUS_END_PERIOD", "STATUS_INTERMISSION", "STATUS_END_ROUND", "STATUS_BETWEEN_ROUNDS"].includes(type.name)
    && type.state === "in" && type.completed === false) return "live";
  throw new Error("Unknown sports event status");
}

function realParticipant(raw) {
  const name = raw?.athlete?.displayName || raw?.roster?.displayName || raw?.team?.displayName || raw?.team?.name;
  if (typeof name !== "string" || /^(?:T\.?B\.?[ACD]\.?|N\/A|(?:Opponent )?TBA|to be (?:confirmed|announced|determined)|winner\b|loser\b)/i.test(name.trim())) return null;
  const id = String(raw.id ?? raw.athlete?.id ?? raw.team?.id ?? "");
  if (!id || id.startsWith("-")) return null;
  return { id: `espn:${identity(id)}`, name: label(name) };
}

function dateKey(date) { return date.toISOString().slice(0, 10).replaceAll("-", ""); }
function siteURL(source, window, day) {
  const url = new URL(`/apis/site/v2/sports/${source.path}/scoreboard`, SITE_ORIGIN);
  url.search = new URLSearchParams({ dates: day ? dateKey(day) : `${dateKey(window.from)}-${dateKey(new Date(window.to.getTime() - DAY))}`, limit: "100" }).toString();
  return url;
}
function coreURL(source, suffix = "") { return new URL(`/v2/sports/${source.path}${suffix}`, CORE_ORIGIN); }

function resultBuilder(source, now, window) {
  const fixtures = new Map();
  const pending = new Set();
  const observedAt = now.toISOString();
  return {
    add(nativeId, row, eventKind, title, participants, url) {
      const id = `sports-fixture:${source.competitionId}:${identity(nativeId)}`;
      const start = startTime(row.date);
      if (start && start >= window.to) return;
      if (start && start < window.from) {
        // A multi-day tournament/card/session can still be explicitly live.
        // Retain only that evidence, within seven past UTC days; never infer
        // live from the date or keep completed events outside the window.
        if (eventKind === "match" || start.getTime() < window.from.getTime() - 6 * DAY || sportsEventStatus(row.status) !== "live") return;
      }
      if (!start || row.timeValid === false || (eventKind === "match" && (!participants || participants.length !== 2))) {
        if (!fixtures.has(id)) pending.add(id);
        if (fixtures.size + pending.size > MAX_FIXTURES) throw new Error("Sports event count exceeded bound");
        return;
      }
      const status = sportsEventStatus(row.status);
      if (["live", "finished"].includes(status) && start.getTime() > now.getTime() + 5 * 60_000) throw new Error("Sports event status conflicts with future start");
      const fixture = { id, sport: source.sport, start: start.toISOString(), status, eventKind, title: label(title),
        competitionId: source.competitionId, competitionName: source.competitionName, participants: participants || [],
        squad: { gender: source.gender || (eventKind === "match" ? "men" : "unknown"), ageGroup: "senior" },
        source: { name: "ESPN", url: url.toString(), observedAt } };
      const old = fixtures.get(id);
      if (old && (old.start !== fixture.start || JSON.stringify(old.participants) !== JSON.stringify(fixture.participants))) throw new Error("Conflicting sports event identity");
      if (old && ["finished", "cancelled"].includes(old.status) && ["scheduled", "live"].includes(status)) throw new Error("Sports event terminal status regressed during collection");
      pending.delete(id);
      fixtures.set(id, fixture);
      if (fixtures.size + pending.size > MAX_FIXTURES) throw new Error("Sports event count exceeded bound");
    },
    finish() { return { fixtures: [...fixtures.values()].sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id)),
      pendingFixtureCount: pending.size, observedAt, windowStart: window.from.toISOString(), windowEnd: window.to.toISOString() }; },
  };
}

function scoreboard(payload, source) {
  const league = source.path.split("/").at(-1);
  if (!Array.isArray(payload?.leagues) || !payload.leagues.some((l) => String(l.id) === source.leagueId && (!l.slug || l.slug === league))
    || !Array.isArray(payload.events) || payload.events.length >= 100) throw new Error("Incomplete or wrong ESPN scoreboard");
  return payload.events;
}
function competitions(event) {
  identity(event?.id);
  label(event.name);
  if (!Array.isArray(event.competitions) || !event.competitions.length || event.competitions.length > 250) throw new Error("Wrong sports event competition shape");
  return event.competitions;
}
function parseTennis(payload, source, builder, url) {
  const acceptedGroups = source.gender === "men" ? new Set(["mens-singles", "mens-doubles"]) : new Set(["womens-singles", "womens-doubles"]);
  for (const event of scoreboard(payload, source)) {
    identity(event.id); label(event.name);
    if (!Array.isArray(event.groupings) || !event.groupings.length || event.groupings.length > 12) throw new Error("Wrong tennis tournament shape");
    for (const group of event.groupings) {
      if (!group?.grouping || !Array.isArray(group.competitions) || group.competitions.length > 400) throw new Error("Wrong tennis grouping shape");
      if (!acceptedGroups.has(group.grouping.slug)) continue;
      for (const row of group.competitions) {
        if (!Array.isArray(row.competitors) || row.competitors.length !== 2) throw new Error("Wrong tennis match shape");
        const pair = row.competitors.map(realParticipant);
        const participants = pair.every(Boolean) && pair[0].id !== pair[1].id ? pair : null;
        // A doubles roster is one side, not an invented home/away team.
        builder.add(row.id, row, "match", participants ? `${participants[0].name} vs ${participants[1].name}` : event.name, participants, url);
      }
    }
  }
}
function parseEvents(payload, source, builder, url) {
  for (const event of scoreboard(payload, source)) {
    const rows = competitions(event);
    if (source.adapter === "session") {
      for (const row of rows) {
        let session = row.type?.text || row.type?.abbreviation;
        if (!session && source.requireSessionType) throw new Error("Missing racing session type");
        session ||= "Race";
        builder.add(row.id, row, "session", `${event.name} — ${label(session)}`, [], url);
      }
    } else if (source.adapter === "tournament") {
      if (rows.length !== 1 || (rows[0].competitors !== undefined && !Array.isArray(rows[0].competitors))) throw new Error("Wrong golf tournament shape");
      builder.add(event.id, { ...rows[0], date: event.date, status: rows[0].status || event.status }, "tournament", event.name, [], url);
    } else if (source.adapter === "card") {
      // ESPN dates a card at the opening bout. Card identity/title stay distinct
      // from fighter identities and all the individual bouts on that card.
      const start = rows.find((row) => row.date === event.date && row.timeValid === true);
      builder.add(event.id, { date: event.date, timeValid: event.timeValid === false || !start ? false : true, status: event.status }, "card", event.name, [], url);
    } else throw new Error("Unknown sports event adapter");
  }
}

async function mapBounded(values, operation, concurrency = 3) {
  const results = new Array(values.length);
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, async () => {
    while (cursor < values.length) { const index = cursor++; results[index] = await operation(values[index]); }
  }));
  return results;
}

function coreReference(value, source, suffixPattern) {
  const url = new URL(value?.$ref || "https://invalid.invalid");
  const base = `/v2/sports/${source.path}`;
  if (!["http:", "https:"].includes(url.protocol) || url.hostname !== new URL(CORE_ORIGIN).hostname || url.port || url.username || url.password
    || !url.pathname.startsWith(`${base}/`) || !suffixPattern.test(url.pathname.slice(base.length))) throw new Error("Unsafe ESPN core reference");
  url.protocol = "https:";
  return url;
}
async function collectCore(source, now, window, request, builder) {
  const league = await request(coreURL(source));
  if (league?.slug !== source.path.split("/").at(-1) || typeof league.name !== "string" || !league.events?.$ref) throw new Error("Wrong ESPN core league");
  const indexURL = coreURL(source, "/events");
  indexURL.search = new URLSearchParams({ dates: `${dateKey(window.from)}-${dateKey(new Date(window.to.getTime() - DAY))}`, limit: "100" }).toString();
  const index = await request(indexURL);
  // Hydrating one fixture takes event + status + two team requests. All rows
  // must fit the 40-request budget; exceeding it is unavailable, never partial.
  if (!Number.isSafeInteger(index?.count) || index.count < 0 || index.count > 9 || !Array.isArray(index.items)
    || index.items.length !== index.count || !Number.isSafeInteger(index.pageIndex) || !Number.isSafeInteger(index.pageCount)
    || (index.count > 0 ? index.pageIndex !== 1 || index.pageCount !== 1 : ![0, 1].includes(index.pageIndex) || ![0, 1].includes(index.pageCount))) throw new Error("Incomplete or over-budget ESPN core index");
  const seen = new Set();
  await mapBounded(index.items, async (reference) => {
    const url = coreReference(reference, source, /^\/events\/\d+$/);
    if (seen.has(url.pathname)) throw new Error("Duplicate ESPN core fixture");
    seen.add(url.pathname);
    const event = await request(url);
    if (String(event?.id) !== url.pathname.split("/").at(-1)) throw new Error("Wrong ESPN core event identity");
    const rows = competitions(event);
    if (rows.length !== 1 || String(rows[0].id) !== String(event.id) || !Array.isArray(rows[0].competitors) || rows[0].competitors.length !== 2) throw new Error("Wrong ESPN core match shape");
    const row = rows[0];
    const statusURL = coreReference(row.status, source, new RegExp(`^/events/${identity(event.id)}/competitions/${identity(row.id)}/status$`));
    const [status, teams] = await Promise.all([
      request(statusURL),
      Promise.all(row.competitors.map(async (competitor) => {
        if (competitor.type !== "team" || !["home", "away"].includes(competitor.homeAway)) throw new Error("Wrong ESPN core competitor");
        const teamURL = coreReference(competitor.team, source, /^\/(?:seasons\/\d+\/)?teams\/\d+$/);
        const team = await request(teamURL);
        if (String(team?.id) !== String(competitor.id)) throw new Error("Wrong ESPN core team identity");
        const participant = realParticipant({ ...competitor, team });
        return participant && { ...participant, role: competitor.homeAway };
      })),
    ]);
    const participants = teams.every(Boolean) && teams[0].id !== teams[1].id && teams[0].role !== teams[1].role ? teams : null;
    builder.add(event.id, { ...row, status, timeValid: event.timeValid === false ? false : row.timeValid }, "match", event.name, participants, url);
  });
}

export async function collectSportsEventSource(source, now, _env = {}, fetchImpl = fetch) {
  void _env; // Preserve the common collector signature; this adapter needs no secret.
  if (!source?.supported || !SPORTS_EVENT_SOURCES.includes(source)) throw new Error("Unsupported sports schedule source");
  const window = sportsEventWindow(now);
  const builder = resultBuilder(source, now, window);
  const deadline = coachDeadline(undefined, 12_000);
  let requests = 0;
  const request = async (url) => {
    if (++requests > MAX_REQUESTS) throw new Error("Sports source request budget exceeded");
    const response = await abortable(() => fetchImpl(url, { signal: deadline.signal, redirect: "manual",
      headers: { Accept: "application/json", "User-Agent": "Fotty fixture service/1.0" },
      cf: { cacheEverything: true, cacheTtl: 60 } }), deadline.signal);
    if (!response.ok || response.redirected || response.status >= 300 && response.status < 400) {
      throw Object.assign(new Error("Sports schedule upstream unavailable"), { fixtureHTTPStatus: response.status });
    }
    return boundedJSON(response, MAX_PAGE_BYTES, deadline.signal);
  };
  try {
    if (source.adapter === "core") await collectCore(source, now, window, request, builder);
    else if (source.adapter === "tennis") {
      // ESPN's range endpoint omitted China Open in the verified 30 Sep
      // response. Daily requests include ongoing tournaments; deduplicate the
      // matches and filter their own UTC dates, not the tournament start date.
      const days = Array.from({ length: 9 }, (_, index) => new Date(window.from.getTime() + index * DAY));
      const pages = await mapBounded(days, async (day) => {
        const url = siteURL(source, window, day);
        return { url, payload: await request(url) };
      });
      for (const page of pages) parseTennis(page.payload, source, builder, page.url);
    } else {
      const url = siteURL(source, window);
      parseEvents(await request(url), source, builder, url);
    }
    return builder.finish();
  } finally { deadline.dispose(); }
}
