// Reviewed Abu Dhabi T10 schedule from ESPN's public scoreboard (league 18522).
// An isolated cohort like WBBL: fixture facts only, never channel assignments,
// media or playback. Placeholder (TBA) play-off rows are skipped until named.
import { abortable, boundedJSON, coachDeadline } from "./coach-safety.mjs";
import { nextCricketRefresh } from "./cricket-fixture-policy.mjs";

const MINUTE = 60_000, DAY = 86400_000;
export const T10_CRICKET_SOURCE = Object.freeze({ competitionID: "abu-dhabi-t10", leagueID: 18522,
  name: "Abu Dhabi T10", origin: "https://site.api.espn.com",
  seasonFrom: "2026-11-01T00:00:00Z", seasonTo: "2026-12-01T00:00:00Z", maxEvents: 60 });
const S = T10_CRICKET_SOURCE;
const fail = (code) => { throw new Error(code); };
const stamp = (v) => typeof v === "string" && /^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{3})?)?Z$/u.test(v)
  && Number.isFinite(Date.parse(v));
const label = (v) => typeof v === "string" && v === v.trim() && v.length > 0 && v.length <= 120
  && !/[\p{Cc}<>]/u.test(v) && !v.includes("://");
const id = (v) => typeof v === "string" && /^[1-9]\d{0,11}$/u.test(v);
const placeholder = (name) => /^(?:TBA|TBC|TBD)$|\b(?:Winner|Loser)\b/iu.test(name);

export function t10ScheduleURLs(now) {
  if (!(now instanceof Date) || !Number.isFinite(+now)) return fail("invalid-clock");
  if (+now < Date.parse(S.seasonFrom) || +now >= Date.parse(S.seasonTo)) return fail("season-review-required");
  // ESPN's cricket scoreboard accepts whole months. Cover yesterday to +8 days.
  // Only months inside the reviewed season are requested.
  const months = new Set([-DAY, 8 * DAY].map((offset) => Math.min(Math.max(+now + offset, Date.parse(S.seasonFrom)),
    Date.parse(S.seasonTo) - 1)).map((t) => new Date(t).toISOString().slice(0, 7).replace("-", "")));
  return [...months].map((month) => {
    const url = new URL(`/apis/site/v2/sports/cricket/${S.leagueID}/scoreboard`, S.origin);
    url.search = new URLSearchParams({ dates: month }).toString();
    return url;
  });
}

function status(event, start, now) {
  const type = event.status?.type ?? {};
  const words = `${type.name ?? ""} ${type.description ?? ""} ${type.detail ?? ""}`;
  if (type.state === "in") {
    if (start > +now + 5 * MINUTE) return fail("status-conflict");
    return "live";
  }
  if (type.state === "post") {
    if (/abandon|cancel|no result/iu.test(words)) return "cancelled";
    if (/postpone/iu.test(words)) return "postponed";
    if (start > +now + 5 * MINUTE) return fail("status-conflict");
    return "finished";
  }
  if (type.state === "pre") return start > +now ? "scheduled" : "unknown";
  return fail("invalid-fixture");
}

export function normalizeT10(payloads, headers, now) {
  const date = Date.parse(headers.get("date"));
  if (!Number.isFinite(date) || date > +now + 5 * MINUTE || +now - date > 10 * MINUTE) return fail("publisher-stale");
  const observedAt = new Date(Math.min(date, +now)).toISOString(), seen = new Set(), fixtures = [];
  const from = +now - DAY, to = +now + 8 * DAY;
  for (const payload of payloads) {
    const league = payload?.leagues?.[0];
    if (!Array.isArray(payload?.events) || payload.events.length > S.maxEvents
      || String(league?.id) !== String(S.leagueID) || league?.name !== S.name) return fail("source-incomplete");
    for (const event of payload.events) {
      const competition = event?.competitions?.[0];
      if (!id(event?.id) || !stamp(event.date) || !Array.isArray(competition?.competitors)
        || competition.competitors.length !== 2) return fail("invalid-fixture");
      if (seen.has(event.id)) continue; // Adjacent months may both list a boundary event.
      seen.add(event.id);
      const start = Date.parse(event.date);
      if (start < from || start >= to) continue;
      const home = competition.competitors.find((c) => c?.homeAway === "home")?.team;
      const away = competition.competitors.find((c) => c?.homeAway === "away")?.team;
      if (!home || !away || !id(home.id) || !id(away.id) || !label(home.displayName) || !label(away.displayName))
        return fail("identity-conflict");
      if (placeholder(home.displayName) || placeholder(away.displayName)) continue;
      if (home.id === away.id || home.displayName === away.displayName) return fail("identity-conflict");
      const round = competition.description ?? event.description ?? "";
      const number = /^([1-9]\d?)(?:st|nd|rd|th) Match$/u.exec(round);
      if (!number && !/^(?:Final|Qualifier(?: [12])?|Eliminator(?: [12])?|Semi[- ]Final(?: [12])?|3rd Place Play-off)$/u.test(round))
        return fail("unsupported-round");
      fixtures.push({ id: `espn-cricket:${event.id}`, start: new Date(start).toISOString(), format: "T10",
        status: status(event, start, now), competitionId: S.competitionID, competitionName: S.name,
        home: { id: `espn:${home.id}`, name: home.displayName }, away: { id: `espn:${away.id}`, name: away.displayName },
        ...(number ? { matchOrdinal: Number(number[1]) } : {}),
        source: { name: "ESPN", url: `https://www.espncricinfo.com/ci/engine/match/${event.id}.html`, observedAt } });
    }
  }
  return { observedAt, fixtures: fixtures.sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id)) };
}

export async function collectT10(now, fetchImpl = fetch) {
  const urls = t10ScheduleURLs(now), deadline = coachDeadline(undefined, 8000);
  try {
    const payloads = [];
    let headers;
    for (const url of urls) {
      const response = await abortable(() => fetchImpl(url, { redirect: "manual", signal: deadline.signal,
        headers: { Accept: "application/json" }, cf: { cacheEverything: true, cacheTtl: 60 } }), deadline.signal);
      if (!response.ok) return fail("upstream-unavailable");
      headers ??= response.headers;
      payloads.push(await boundedJSON(response, 512 * 1024, deadline.signal));
    }
    return normalizeT10(payloads, headers, now);
  } finally { deadline.dispose(); }
}

function hasActiveFixture(fixtures, now) {
  return (fixtures ?? []).some((f) => f.status === "live" || ["scheduled", "unknown"].includes(f.status)
    && Date.parse(f.start) - +now <= 30 * MINUTE && +now - Date.parse(f.start) <= 4 * 60 * MINUTE);
}

export async function refreshT10(previous, now, collect = collectT10) {
  // A stored quiet-day wait never outlives a match that has since started.
  const overdue = hasActiveFixture(previous?.fixtures, now) && +now - Date.parse(previous?.lastAttemptAt) >= 2 * MINUTE;
  if (Date.parse(previous?.nextAttemptAt) > +now && !overdue) return previous;
  try {
    const next = await collect(now);
    if (Date.parse(next.observedAt) < Date.parse(previous?.observedAt)) return fail("receipt-regressed");
    const byID = new Map(next.fixtures.map((r) => [r.id, r]));
    for (const old of previous?.fixtures ?? []) {
      const row = byID.get(old.id);
      if (!row) {
        if (["scheduled", "live"].includes(old.status) && Date.parse(old.start) >= +now - 12 * 60 * MINUTE
          && Date.parse(old.start) <= +now + DAY) return fail("accepted-fixture-missing");
        continue;
      }
      if (row.home.id !== old.home.id || row.away.id !== old.away.id || row.matchOrdinal !== old.matchOrdinal)
        return fail("identity-conflict");
      if (old.status === "finished" && row.status !== "finished"
        || old.status === "live" && ["scheduled", "unknown"].includes(row.status)) return fail("status-regressed");
    }
    // A live T10 lasts about 90 minutes and feeds Fox programme links whose
    // app-side freshness limit is 10 minutes, so refresh every 2 minutes then.
    // A fixture at or just past its start can be "unknown" (ESPN still says
    // pre) and must not wait for the 4-hour quiet cadence.
    const cadence = hasActiveFixture(next.fixtures, now) ? 2 * MINUTE : nextCricketRefresh(next.fixtures, now);
    return { ...next, status: "covered", consecutiveFailures: 0, lastAttemptAt: now.toISOString(),
      nextAttemptAt: new Date(+now + cadence).toISOString() };
  } catch (error) {
    const allowed = new Set(["publisher-stale", "source-incomplete", "season-review-required", "invalid-fixture",
      "identity-conflict", "unsupported-round", "status-conflict", "upstream-unavailable", "receipt-regressed",
      "accepted-fixture-missing", "status-regressed"]);
    return { fixtures: previous?.fixtures ?? [], observedAt: previous?.observedAt ?? "1970-01-01T00:00:00.000Z",
      status: error.message === "season-review-required" ? "offseason" : "unavailable",
      failure: allowed.has(error.message) ? error.message : "collection-failed",
      consecutiveFailures: Math.min(1000, (previous?.consecutiveFailures ?? 0) + 1),
      lastAttemptAt: now.toISOString(),
      nextAttemptAt: new Date(+now + (error.message === "season-review-required" ? 6 * 60 : 5) * MINUTE).toISOString() };
  }
}

export function appendT10(snapshot, cohort) {
  if (!snapshot || !cohort) return snapshot;
  const at = Date.parse(cohort.lastAttemptAt);
  const rows = cohort.status === "offseason" ? [] : cohort.fixtures.filter((r) => Date.parse(r.start) >= at - 30 * DAY
    && Date.parse(r.start) <= at + 90 * DAY && Date.parse(r.source.observedAt) >= at - 30 * DAY);
  return { ...snapshot, checkedAt: [snapshot.checkedAt, cohort.lastAttemptAt].sort().at(-1),
    revision: `${snapshot.revision}|t10:${cohort.lastAttemptAt}`,
    sourceStatus: snapshot.sourceStatus === "verified" && cohort.status !== "unavailable" ? "verified" : "partial",
    fixtures: [...snapshot.fixtures, ...rows],
    // Offseason is a fresh, honest fact about this attempt, not the last
    // publisher receipt: an expired receipt on a non-unavailable row would make
    // the app reject the whole cricket snapshot (30-day coverage receipt rule).
    coverage: [...snapshot.coverage, { competitionId: S.competitionID, competitionName: S.name,
      checkedAt: cohort.status === "offseason" ? cohort.lastAttemptAt : cohort.observedAt,
      status: cohort.status, fixtureCount: rows.length, expectedFixtureCount: rows.length }],
    sync: { ...snapshot.sync, cohorts: { ...snapshot.sync?.cohorts, [S.competitionID]: {
      lastAttemptAt: cohort.lastAttemptAt,
      ...(cohort.observedAt !== "1970-01-01T00:00:00.000Z" ? { lastSuccessAt: cohort.observedAt } : {}),
      consecutiveFailures: cohort.consecutiveFailures ?? 0,
      ...(cohort.failure ? { failure: { stage: "collection", code: cohort.failure } } : {}) } } } };
}
