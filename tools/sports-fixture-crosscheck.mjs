import { abortable, boundedText, coachDeadline } from "../web/workers/playback/src/coach-safety.mjs";
import { SPORTS_SOURCES, collectSportsSource, sportsFixtureWindow } from "../web/workers/playback/src/sports-fixture-sources.mjs";
import { admitSportsCollection, fixtureInstant } from "../web/workers/playback/src/sports-fixture-policy.mjs";
import { auditSportsSnapshot } from "./audit-sports-fixtures-policy.mjs";

const MINUTE = 60_000;
const DAY = 86_400_000;
const MODE = "same-upstream-independently-fetched";
export const SPORTS_CROSSCHECK_SOURCE_IDS = Object.freeze(["mlb", "nhl", "wnba"]);
const SOURCES = SPORTS_CROSSCHECK_SOURCE_IDS.map((id) => SPORTS_SOURCES.find((source) => source.id === id));
const STATUSES = new Set(["scheduled", "live", "finished", "cancelled", "postponed", "unknown"]);

function check(value) { if (!value) throw new Error("Invalid sports coverage comparison"); }
function clock(value) {
  const instant = value instanceof Date ? value.getTime() : value;
  check(Number.isFinite(instant));
  return instant;
}
function permittedURL(descriptor, value) {
  let url;
  try { url = new URL(value); } catch { return false; }
  const expected = new URL(descriptor.sourceURL);
  if (url.origin !== expected.origin || url.username || url.password || url.hash) return false;
  if (descriptor.id === "nhl") return /^\/v1\/schedule\/\d{4}-\d{2}-\d{2}$/.test(url.pathname);
  if (descriptor.id === "mlb") return url.pathname === expected.pathname && url.searchParams.get("sportId") === "1";
  return url.href === expected.href;
}
function providerIdentity(fixture, descriptor) {
  return new RegExp(`^sports-fixture:${descriptor.id}:[1-9][0-9]*$`).test(fixture?.id)
    && fixture.source?.name === descriptor.sourceName && permittedURL(descriptor, fixture.source?.url);
}
function identity(fixture) {
  return JSON.stringify({ sport: fixture.sport, competitionId: fixture.competitionId, kind: fixture.eventKind,
    gender: fixture.squad?.gender, ageGroup: fixture.squad?.ageGroup,
    participants: fixture.participants.map((row) => [row.id, row.role || null]).sort((a, b) => a[0].localeCompare(b[0])) });
}
function sourceIdentity(fixture, descriptor) {
  // Date-window URLs vary for an otherwise identical reviewed publisher. A
  // foreign source URL remains distinct in the digest, never in report text.
  return [fixture.source?.name ?? null, permittedURL(descriptor, fixture.source?.url)
    ? descriptor.sourceURL : fixture.source?.url ?? null];
}
function expectedFixture(fixture, now) {
  const start = fixtureInstant(fixture.start);
  return fixture.status === "live" || fixture.status === "scheduled" && start >= now && start < now + DAY;
}
function imminent(fixture, now) { return fixture.status === "live" || fixtureInstant(fixture.start) <= now + 30 * MINUTE; }
function coveredSources(body, now) {
  // This validates complete accepted envelopes/counts before any comparison GET.
  // Existing freshness findings remain the main audit's responsibility.
  auditSportsSnapshot(body, { now });
  return SOURCES.filter((descriptor) => {
    const row = body.coverage.find((candidate) => candidate.competitionId === descriptor.id && candidate.status === "covered");
    if (row) check(row.sport === descriptor.sport && row.competitionName === descriptor.competitions[0].name);
    return Boolean(row);
  });
}
function validateComparison(collection, descriptor, now) {
  const window = sportsFixtureWindow(new Date(now));
  check(collection?.windowStart === window.windowStart && collection.windowEnd === window.windowEnd);
  const result = admitSportsCollection(collection, undefined, descriptor, new Date(now));
  check(result.accepted && collection.fixtures.every((row) => providerIdentity(row, descriptor)
    && row.eventKind === "match" && row.squad.gender === descriptor.gender && row.squad.ageGroup === descriptor.ageGroup
    && row.participants.every((participant) => new RegExp(`^${descriptor.id}:[1-9][0-9]*$`).test(participant.id))
    && new Set(row.participants.map((participant) => participant.role)).size === 2
    && row.participants.every((participant) => ["home", "away"].includes(participant.role))));
  return result.accepted;
}
async function evidenceKey(facts) {
  const bytes = new TextEncoder().encode(JSON.stringify(facts.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)))));
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)))
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function baseLane(descriptor, checkedAt) {
  return { sourceId: descriptor.id, competitionId: descriptor.id, checkedAt, expectedCount: 0, matchedCount: 0,
    omittedCount: 0, disagreementCount: 0, pendingFixtureCount: 0 };
}

// This is a new fetch of the SAME league-owned schedule, not corroboration from
// an independent publisher. It detects accepted-catalog omissions only within
// the public primary source's supported schema/window and known time/team data.
// No source facts are overwritten and no raw upstream text/URLs/errors escape.
export async function reconcileSportsFixtureCoverage(body, comparisonCollections, { now = Date.now() } = {}) {
  now = clock(now);
  const descriptors = coveredSources(body, now);
  const collections = comparisonCollections instanceof Map ? comparisonCollections : new Map(Object.entries(comparisonCollections || {}));
  const lanes = [];
  const findings = [];
  for (const descriptor of descriptors) {
    const coverage = body.coverage.find((row) => row.competitionId === descriptor.id);
    const lane = baseLane(descriptor, new Date(now).toISOString());
    const comparison = collections.get(descriptor.id);
    const failure = comparison?.comparisonFailure;
    if (!comparison || failure) {
      const code = failure === "comparison-receipt-stale" ? failure : "comparison-source-unavailable";
      lane.status = code === "comparison-receipt-stale" ? "comparison-stale" : "comparison-unavailable";
      findings.push({ code, competitionId: descriptor.id, actionable: false });
      lanes.push(lane); continue;
    }
    let acceptedComparison;
    try {
      const receiptAge = now - fixtureInstant(comparison.observedAt);
      if (receiptAge > 5 * MINUTE || receiptAge < -5 * MINUTE) {
        lane.status = "comparison-stale";
        findings.push({ code: "comparison-receipt-stale", competitionId: descriptor.id, actionable: false });
        lanes.push(lane); continue;
      }
      acceptedComparison = validateComparison(comparison, descriptor, now);
    } catch {
      lane.status = "comparison-unavailable";
      findings.push({ code: "comparison-source-unavailable", competitionId: descriptor.id, actionable: false });
      lanes.push(lane); continue;
    }
    const expected = acceptedComparison.fixtures.filter((fixture) => expectedFixture(fixture, now));
    lane.expectedCount = expected.length;
    lane.pendingFixtureCount = acceptedComparison.pendingFixtureCount;
    const oldRows = body.fixtures.filter((fixture) => fixture.competitionId === descriptor.id);
    const oldByID = new Map(oldRows.map((row) => [row.id, row]));
    const coverageAge = now - fixtureInstant(coverage.checkedAt);
    const publisherStale = expected.some((fixture) => imminent(fixture, now) && fixture.source.updatedAt
      && now - fixtureInstant(fixture.source.updatedAt) >= 30 * MINUTE);
    if (publisherStale) {
      lane.status = "comparison-stale";
      findings.push({ code: "comparison-receipt-stale", competitionId: descriptor.id, actionable: false });
      lanes.push(lane); continue;
    }
    const disagreements = [];
    const omissions = [];
    for (const fixture of expected) {
      const old = oldByID.get(fixture.id);
      if (!old) { lane.omittedCount++; if (imminent(fixture, now)) omissions.push([fixture.id, fixture.start, fixture.status, identity(fixture)]); continue; }
      const sameIdentity = providerIdentity(old, descriptor) && old.sport === descriptor.sport
        && old.competitionName === descriptor.competitions[0].name && old.eventKind === "match"
        && old.squad?.gender === descriptor.gender && old.squad?.ageGroup === descriptor.ageGroup
        && identity(old) === identity(fixture);
      const sameTime = fixtureInstant(old.start) === fixtureInstant(fixture.start);
      const sameStatus = STATUSES.has(old.status) && old.status === fixture.status;
      if (sameIdentity && sameTime && sameStatus) lane.matchedCount++;
      else {
        lane.disagreementCount++;
        // A matching event ID with changed participants/time/status is an
        // ambiguous correction, not proof that another event is absent.
        disagreements.push([fixture.id, sameIdentity ? "same-identity" : "identity-conflict", old.start, fixture.start, old.status, fixture.status,
          identity(fixture), identity(old), sourceIdentity(fixture, descriptor), sourceIdentity(old, descriptor)]);
      }
    }
    if (coverageAge > 30 * MINUTE) {
      // Quiet lanes normally refresh every four hours. An old accepted receipt
      // cannot establish an omission/correction; this is informational only.
      lane.status = "comparison-stale";
    } else {
      if (disagreements.length) findings.push({ code: "same-upstream-fixture-disagreement", competitionId: descriptor.id,
        actionable: false, evidenceKey: await evidenceKey(disagreements) });
      if (omissions.length) findings.push({ code: "same-upstream-current-omission", competitionId: descriptor.id,
        actionable: coverageAge >= 10 * MINUTE, evidenceKey: await evidenceKey(omissions) });
      // A continuously renewed but incorrect receipt must remain detectable on
      // an identical repeated monitor observation. Fresh grace findings are
      // non-actionable; future-only gaps have no finding at all.
      lane.status = (lane.omittedCount || lane.disagreementCount) && coverageAge < 10 * MINUTE ? "comparison-pending"
        : disagreements.length || omissions.length ? "disagreement" : lane.omittedCount ? "comparison-pending" : "matched";
    }
    lanes.push(lane);
  }
  return { mode: MODE, checkedAt: new Date(now).toISOString(), lanes, findings };
}

export async function collectSportsFixtureCrosscheck(body, {
  now = Date.now(), fetchImpl = fetch, collect = collectSportsSource, timeoutMs = 12_000,
} = {}) {
  now = clock(now);
  const descriptors = coveredSources(body, now);
  const collections = new Map();
  if (!descriptors.length) return reconcileSportsFixtureCoverage(body, collections, { now });
  check(Number.isFinite(timeoutMs) && timeoutMs > 0);
  const deadline = coachDeadline(undefined, Math.min(timeoutMs, 12_000));
  let requests = 0;
  let closed = false;
  try {
    const operations = descriptors.map(async (descriptor) => {
      const checkedFetch = async (url, init = {}) => {
        // The fixed collectors make four GETs total: MLB one, NHL two, WNBA one.
        check(permittedURL(descriptor, String(url)) && ++requests <= 4);
        const signal = AbortSignal.any([deadline.signal, ...(init.signal ? [init.signal] : [])]);
        const response = await abortable(() => fetchImpl(url, { ...init, redirect: "error", signal }), deadline.signal);
        check(response.ok && !response.redirected);
        const age = response.headers.get("age");
        if (age !== null && (!/^\d+$/.test(age) || !Number.isSafeInteger(Number(age)) || Number(age) >= 1800)) {
          void response.body?.cancel().catch(() => {});
          throw Object.assign(new Error("Comparison evidence stale"), { comparisonFailure: "comparison-receipt-stale" });
        }
        // Bind streaming bodies to the OUTER deadline as well as each source's
        // local guard. A body ignoring fetch cancellation cannot outlive this
        // reconciliation or bypass the per-response two-megabyte ceiling.
        const body = await boundedText(response, 2_000_000, deadline.signal);
        return new Response(body, { status: response.status, headers: response.headers });
      };
      try {
        const collection = await abortable(() => collect(descriptor, new Date(now), {}, checkedFetch), deadline.signal);
        if (!closed) collections.set(descriptor.id, collection);
      } catch (error) {
        if (!closed) collections.set(descriptor.id, { comparisonFailure: error?.comparisonFailure === "comparison-receipt-stale"
          ? "comparison-receipt-stale" : "comparison-source-unavailable" });
      }
    });
    try { await abortable(() => Promise.all(operations), deadline.signal); }
    catch { /* Each unfinished lane is recorded below without exception text. */ }
    for (const descriptor of descriptors) if (!collections.has(descriptor.id)) collections.set(descriptor.id,
      { comparisonFailure: "comparison-source-unavailable" });
  } finally { closed = true; deadline.dispose(); }
  return reconcileSportsFixtureCoverage(body, new Map(collections), { now });
}
