// Reviewed Cricket Australia WBBL schedule contract. This isolated cohort owns
// fixture facts, never channel assignments or media. Other CA competitions are
// not inferred from this season's response.
import { abortable, boundedJSON, coachDeadline } from "./coach-safety.mjs";
import { nextCricketRefresh } from "./cricket-fixture-policy.mjs";

const MINUTE = 60_000, DAY = 86400_000;
export const CA_CRICKET_SOURCE = Object.freeze({ competitionID: "wbbl", publisherID: 4687,
  name: "Women's Big Bash League", origin: "https://apiv2.cricket.com.au",
  seasonFrom: "2026-10-01T00:00:00Z", seasonTo: "2027-01-01T00:00:00Z", limit: 50 });
const S = CA_CRICKET_SOURCE;
const fail = (code) => { throw new Error(code); };
const stamp = (v) => typeof v === "string" && /^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/u.test(v)
  && Number.isFinite(Date.parse(v)) && new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
const label = (v) => typeof v === "string" && v === v.trim() && v.length > 0 && v.length <= 200
  && !/[\p{Cc}<>]/u.test(v) && !v.includes("://");
const id = (v) => Number.isSafeInteger(v) && v > 0 && v < 1e10;

export function caCricketURL(now) {
  if (!(now instanceof Date) || !Number.isFinite(+now)) return fail("invalid-clock");
  if (+now < Date.parse(S.seasonFrom) || +now >= Date.parse(S.seasonTo)) return fail("season-review-required");
  const midnight = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const url = new URL("/web/fixtures/yearfilter", S.origin);
  url.search = new URLSearchParams({ competitionId: String(S.publisherID),
    startDateTime: new Date(midnight - DAY).toISOString().slice(0, 10),
    endDateTime: new Date(midnight + 8 * DAY).toISOString().slice(0, 10),
    limit: String(S.limit), format: "json", jsconfig: "eccn:true" }).toString();
  return url;
}

export function normalizeCACricket(payload, headers, now) {
  const requested = caCricketURL(now);
  const date = Date.parse(headers.get("date")), ageText = headers.get("age");
  const age = ageText === null ? 0 : /^\d+$/u.test(ageText) ? Number(ageText) : NaN;
  // Date/Age is a current response receipt, not a claimed event update time.
  if (!Number.isFinite(date) || !Number.isSafeInteger(age) || age > 300
    || date > +now + 5 * MINUTE || +now - date > 10 * MINUTE) return fail("publisher-stale");
  if (payload?.responseError || !Array.isArray(payload?.fixtures) || payload.fixtures.length >= S.limit)
    return fail("source-incomplete");
  const observedAt = new Date(Math.min(date, +now)).toISOString(), seen = new Set();
  const from = Date.parse(requested.searchParams.get("startDateTime"));
  const to = Date.parse(requested.searchParams.get("endDateTime")) + DAY;
  const fixtures = payload.fixtures.map((r) => {
    if (!id(r?.id) || seen.has(r.id) || r.competition?.id !== S.publisherID
      || !label(r.competition?.name) || !/\bWBBL\b/u.test(r.competition.name)
      || r.gameTypeId !== 41 || r.isWomensMatch !== true || !stamp(r.startDateTime)
      || Date.parse(r.startDateTime) < from || Date.parse(r.startDateTime) >= to
      || [r.isLive, r.isCompleted, r.isInProgress].some((v) => typeof v !== "boolean")
      || r.isCompleted && (r.isLive || r.isInProgress)) return fail("invalid-fixture");
    seen.add(r.id);
    const teams = [r.homeTeam, r.awayTeam];
    if (teams.some((t) => !id(t?.id) || !label(t?.name) || !/\bWomen$/u.test(t.name)
      || /\b(?:TBC|TBD|Winner|Loser)\b/iu.test(t.name)) || teams[0].id === teams[1].id
      || teams[0].name === teams[1].name) return fail("identity-conflict");
    const number = /^Match ([1-9]\d?)$/u.exec(r.name ?? "");
    // Finals are legitimate fixtures; do not invent a round number for them.
    if (!number && !/^(?:Final|Semi Final [12]|Semi-Final [12]|Eliminator|Challenger)$/u.test(r.name ?? ""))
      return fail("unsupported-round");
    let status = r.isCompleted ? "finished" : r.isLive || r.isInProgress ? "live"
      : Date.parse(r.startDateTime) > +now ? "scheduled" : "unknown";
    if (status === "live" && Date.parse(r.startDateTime) > +now + 5 * MINUTE) return fail("status-conflict");
    return { id: `ca:${r.id}`, start: new Date(r.startDateTime).toISOString(), format: "T20", status,
      competitionId: S.competitionID, competitionName: S.name,
      home: { id: `ca:${teams[0].id}`, name: teams[0].name }, away: { id: `ca:${teams[1].id}`, name: teams[1].name },
      ...(number ? { matchOrdinal: Number(number[1]) } : {}),
      source: { name: "Cricket Australia", url: `https://www.cricket.com.au/matches/CA:${r.id}`, observedAt } };
  });
  return { observedAt, fixtures };
}

export async function collectCACricket(now, fetchImpl = fetch) {
  const url = caCricketURL(now), deadline = coachDeadline(undefined, 8000);
  try {
    const response = await abortable(() => fetchImpl(url, { redirect: "error", signal: deadline.signal,
      headers: { Accept: "application/json" }, cf: { cacheEverything: true, cacheTtl: 60 } }), deadline.signal);
    if (!response.ok) return fail("upstream-unavailable");
    return normalizeCACricket(await boundedJSON(response, 256 * 1024, deadline.signal), response.headers, now);
  } finally { deadline.dispose(); }
}

export async function refreshCACricket(previous, now, collect = collectCACricket) {
  if (Date.parse(previous?.nextAttemptAt) > +now) return previous;
  try {
    const next = await collect(now);
    if (Date.parse(next.observedAt) < Date.parse(previous?.observedAt)) return fail("receipt-regressed");
    const byID = new Map(next.fixtures.map((r) => [r.id, r]));
    for (const old of previous?.fixtures ?? []) {
      const row = byID.get(old.id);
      if (!row) {
        if (["scheduled", "live"].includes(old.status) && Date.parse(old.start) >= +now - DAY
          && Date.parse(old.start) <= +now + DAY) return fail("accepted-fixture-missing");
        continue;
      }
      if (row.home.id !== old.home.id || row.away.id !== old.away.id || row.start !== old.start
        || row.matchOrdinal !== old.matchOrdinal) return fail("identity-conflict");
      if (old.status === "finished" && row.status !== "finished"
        || old.status === "live" && ["scheduled", "unknown"].includes(row.status)) return fail("status-regressed");
    }
    return { ...next, status: "covered", consecutiveFailures: 0, lastAttemptAt: now.toISOString(),
      nextAttemptAt: new Date(+now + nextCricketRefresh(next.fixtures, now)).toISOString() };
  } catch (error) {
    const allowed = new Set(["publisher-stale", "source-incomplete", "season-review-required", "invalid-fixture",
      "identity-conflict", "unsupported-round", "status-conflict", "upstream-unavailable", "receipt-regressed",
      "accepted-fixture-missing", "status-regressed"]);
    return { fixtures: previous?.fixtures ?? [], observedAt: previous?.observedAt ?? "1970-01-01T00:00:00.000Z",
      status: "unavailable", failure: allowed.has(error.message) ? error.message : "collection-failed",
      consecutiveFailures: Math.min(1000, (previous?.consecutiveFailures ?? 0) + 1),
      lastAttemptAt: now.toISOString(), nextAttemptAt: new Date(+now + 5 * MINUTE).toISOString() };
  }
}

export function appendCACricket(snapshot, cohort) {
  if (!snapshot || !cohort) return snapshot;
  // Retain accepted storage on outages, but do not poison the whole native
  // catalog with records outside its public 30-day receipt/window contract.
  const at = Date.parse(cohort.lastAttemptAt);
  const domestic = cohort.fixtures.filter((r) => Date.parse(r.start) >= at - 30 * DAY
    && Date.parse(r.start) <= at + 90 * DAY && Date.parse(r.source.observedAt) >= at - 30 * DAY);
  const count = domestic.length;
  const baseVerified = ["verified", "partial"].includes(snapshot.sourceStatus);
  return { ...snapshot, checkedAt: [snapshot.checkedAt, cohort.lastAttemptAt].sort().at(-1),
    revision: `cricket:ca:${snapshot.checkedAt}:${cohort.lastAttemptAt}`,
    sourceStatus: snapshot.sourceStatus === "verified" && cohort.status === "covered" ? "verified" : "partial",
    fixtures: [...snapshot.fixtures.map((r) => baseVerified || r.source.verification === undefined ? r
      : { ...r, source: { ...r.source, verification: "held" } }), ...domestic],
    coverage: [...snapshot.coverage.map((c) => baseVerified ? c : { ...c, status: "unavailable" }),
      { competitionId: S.competitionID, competitionName: S.name, checkedAt: cohort.observedAt,
        status: cohort.status, fixtureCount: count, expectedFixtureCount: count }],
    sync: { ...snapshot.sync, cohorts: { ...snapshot.sync?.cohorts, wbbl: {
      lastAttemptAt: cohort.lastAttemptAt, ...(cohort.observedAt !== "1970-01-01T00:00:00.000Z" ? { lastSuccessAt: cohort.observedAt } : {}),
      consecutiveFailures: cohort.consecutiveFailures ?? 0,
      ...(cohort.failure ? { failure: { stage: "collection", code: cohort.failure } } : {}) } } } };
}
