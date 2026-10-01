import { admitSportsCollection, descriptorCompetitions, nextSportsRefresh, sportsRevision, SPORTS_FIXTURE_MAX_ROWS } from "./sports-fixture-policy.mjs";

const STATE_KEY = "sports-source-v1";
const RETRY_MS = 5 * 60_000;
const FAILURE_CODES = new Map([
  ["Sports schedule upstream unavailable", "upstream-unavailable"],
  ["Sports schedule is not JSON", "upstream-not-json"],
  ["Football schedule credential unavailable", "credential-unavailable"],
  ["Football schedule incomplete", "source-incomplete"],
  ["Football schedule window mismatch", "window-mismatch"],
  ["Football competition filter unavailable", "scope-mismatch"],
  ["Pending competition scope invalid", "scope-mismatch"],
  ["Pending competition count mismatch", "source-incomplete"],
  ["Accepted fixture disappeared without cancellation evidence", "accepted-fixture-missing"],
  ["Terminal fixture status regressed", "terminal-rollback"],
  ["Collector receipt invalid", "receipt-invalid"],
  ["Source receipt invalid", "receipt-invalid"],
  ["Fixture competition mismatch", "scope-mismatch"],
  ["Publisher live evidence stale", "publisher-stale"],
]);
const ERROR_KINDS = new Set(["Error", "TypeError", "ReferenceError", "RangeError", "SyntaxError", "AbortError", "TimeoutError"]);

// Scope is evidence, not an inference from today's descriptor. In particular,
// a stored PL/CL receipt cannot prove newly added European leagues empty.
function hasCompetitionReceipt(descriptor, accepted, competitionId) {
  if (!accepted) return false;
  if (accepted.pendingByCompetition !== undefined) {
    const pending = accepted.pendingByCompetition;
    return pending !== null && typeof pending === "object" && !Array.isArray(pending)
      && Object.hasOwn(pending, competitionId) && Number.isInteger(pending[competitionId])
      && pending[competitionId] >= 0 && pending[competitionId] <= 10000;
  }
  // Old single-lane receipts predate pendingByCompetition. Their source ID
  // already fixes the scope; multi-lane legacy state needs explicit evidence.
  return descriptorCompetitions(descriptor).length === 1
    || (accepted.fixtures || []).some((fixture) => fixture.competitionId === competitionId);
}

function requiresScopeRefresh(descriptor, state) {
  return !descriptorCompetitions(descriptor).every((competition) =>
    hasCompetitionReceipt(descriptor, state?.accepted, competition.id));
}

function competitionScope(descriptor) {
  return JSON.stringify(descriptorCompetitions(descriptor).map(({ id }) => id).sort());
}

function refreshDue(descriptor, state, now) {
  const nextAttempt = Date.parse(state?.nextAttemptAt);
  // A newly expanded scope gets one immediate attempt. Persisting its attempted
  // scope means failed migrations still respect the ordinary retry deadline.
  return !state || !Number.isFinite(nextAttempt) || nextAttempt <= now.getTime()
    || requiresScopeRefresh(descriptor, state) && state.lastAttemptScope !== competitionScope(descriptor);
}

// Only finite, reviewed codes escape a failed collector. Never log exception
// text, response bodies, source URLs or credentials—even for unknown errors.
export function sportsFailureInfo(error, stage) {
  const value = { stage: stage === "admission" ? "admission" : "collection",
    code: FAILURE_CODES.get(error?.message) || "validation-or-runtime-failure",
    kind: ERROR_KINDS.has(error?.name) ? error.name : "Error" };
  if (Number.isInteger(error?.fixtureHTTPStatus) && error.fixtureHTTPStatus >= 100 && error.fixtureHTTPStatus <= 599) {
    value.httpStatus = error.fixtureHTTPStatus;
  }
  return value;
}

export function sourceCoverage(descriptor, state, now = new Date()) {
  return descriptorCompetitions(descriptor).map((competition) => {
    const scoped = hasCompetitionReceipt(descriptor, state?.accepted, competition.id);
    const fixtures = (state?.accepted?.fixtures || []).filter((row) => row.competitionId === competition.id);
    const receipt = scoped ? state?.accepted?.observedAt : null;
    const observed = Date.parse(receipt);
    const interval = nextSportsRefresh(fixtures, Number.isFinite(observed) ? new Date(observed) : now);
    const allowedAge = interval <= 15 * 60_000 ? 30 * 60_000 : interval + 30 * 60_000;
    const fresh = Number.isFinite(observed) && observed <= now.getTime() + 5 * 60_000 && now.getTime() - observed <= allowedAge;
    const status = descriptor.supported === false ? "unsupported" : state?.accepted && !state.consecutiveFailures && fresh ? "covered" : "unavailable";
    const pending = scoped ? state?.accepted?.pendingByCompetition?.[competition.id]
      ?? (descriptorCompetitions(descriptor).length === 1 ? state?.accepted?.pendingFixtureCount : 0) : 0;
    return { sport: competition.sport || descriptor.sport, competitionId: competition.id, competitionName: competition.name,
      status, checkedAt: receipt || null, fixtureCount: fixtures.length,
      pendingFixtureCount: Number.isInteger(pending) && pending >= 0 && pending <= 10000 ? pending : 0,
      ...(fixtures.filter((fixture) => fixture.status === "scheduled").map((fixture) => fixture.start).sort()[0]
        ? { nextStart: fixtures.filter((fixture) => fixture.status === "scheduled").map((fixture) => fixture.start).sort()[0] } : {}),
      ...(status === "unsupported" && descriptor.reason ? { reason: descriptor.reason } : {}),
      sync: { consecutiveFailures: state?.consecutiveFailures || 0, lastAttemptAt: state?.lastAttemptAt || null,
        lastSuccessAt: receipt || null, conflict: Boolean(state?.conflict),
        ...(state?.failure ? { failure: state.failure } : {}) } };
  });
}

export async function refreshSportsSource(previous, descriptor, now, collect) {
  if (descriptor.supported === false) return previous || { consecutiveFailures: 0 };
  const attempt = { lastAttemptAt: now.toISOString(), lastAttemptScope: competitionScope(descriptor) };
  let stage = "collection";
  try {
    const collection = await collect(descriptor, now);
    stage = "admission";
    const result = admitSportsCollection(collection, previous?.accepted, descriptor, now, previous?.conflict);
    if (result.conflict) return { ...previous, failure: null, consecutiveFailures: (previous?.consecutiveFailures || 0) + 1, conflict: result.conflict,
      ...attempt, nextAttemptAt: new Date(now.getTime() + RETRY_MS).toISOString() };
    return { accepted: result.accepted, consecutiveFailures: 0, ...attempt,
      nextAttemptAt: new Date(now.getTime() + nextSportsRefresh(result.accepted.fixtures, now)).toISOString() };
  } catch (error) {
    // No exception/body/credential reaches public snapshots or operational logs.
    return { ...previous, consecutiveFailures: (previous?.consecutiveFailures || 0) + 1,
      failure: sportsFailureInfo(error, stage), ...attempt, nextAttemptAt: new Date(now.getTime() + RETRY_MS).toISOString() };
  }
}

export async function assembleSportsSnapshot(descriptors, states, now) {
  const fixtures = [];
  const coverage = [];
  const seen = new Set();
  for (const descriptor of descriptors) {
    const state = states.get(descriptor.id);
    coverage.push(...sourceCoverage(descriptor, state, now));
    for (const fixture of state?.accepted?.fixtures || []) {
      if (seen.has(fixture.id)) throw new Error("Duplicate cross-source fixture identity");
      seen.add(fixture.id);
      fixtures.push(fixture);
    }
  }
  fixtures.sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
  if (fixtures.length > SPORTS_FIXTURE_MAX_ROWS) throw new Error("Aggregate fixture limit exceeded");
  const receipts = coverage.map((row) => row.checkedAt).filter(Boolean).sort();
  const available = coverage.filter((row) => row.status !== "unsupported");
  return { schemaVersion: 1, complete: true, checkedAt: receipts.at(-1) || now.toISOString(),
    revision: await sportsRevision(fixtures, coverage), sourceStatus: available.every((row) => row.status === "covered") && available.length ? "verified" : "partial",
    fixtures, coverage };
}

// One object per reviewed source group. Its own serialized requests cannot
// amplify quota usage, while another league's failure cannot stop its refresh.
export class SportsFixtureRegistry {
  constructor(state, env, options = {}) { this.state = state; this.env = env; this.options = options; this.queue = Promise.resolve(); }
  enqueue(operation) {
    const result = this.queue.then(operation);
    this.queue = result.then(() => undefined, () => undefined);
    return result;
  }
  async refresh(descriptor) {
    const now = new Date();
    const previous = await this.state.storage.get(STATE_KEY);
    if (!refreshDue(descriptor, previous, now)) return previous;
    const next = await refreshSportsSource(previous, descriptor, now,
      (source, instant) => this.options.collect(source, instant, this.env));
    await this.state.storage.put(STATE_KEY, next);
    console.log(JSON.stringify({ event: "sports_fixture_refresh", sourceGroup: descriptor.id,
      outcome: next.consecutiveFailures ? "unavailable" : "covered", fixtureCount: next.accepted?.fixtures.length || 0,
      consecutiveFailures: next.consecutiveFailures || 0, conflict: Boolean(next.conflict),
      ...(next.failure ? { failure: next.failure } : {}) }));
    return next;
  }
  async fetch(request) {
    const url = new URL(request.url);
    const descriptor = this.options.descriptors.find((source) => source.id === url.searchParams.get("source"));
    if (!descriptor || descriptor.supported === false) return Response.json({ error: "Unknown source" }, { status: 404 });
    if (request.method === "POST" && url.pathname === "/refresh") {
      const next = await this.enqueue(() => this.refresh(descriptor));
      return Response.json({ ok: !next.consecutiveFailures, nextAttemptAt: next.nextAttemptAt });
    }
    if (request.method !== "GET" || url.pathname !== "/fixtures") return Response.json({ error: "Not found" }, { status: 404 });
    let current = await this.state.storage.get(STATE_KEY);
    // Cold API callers don't launch every source scrape in their request. The
    // registered cron/bootstrap gate initializes shared snapshots independently.
    if (refreshDue(descriptor, current, new Date())) this.state.waitUntil(this.enqueue(() => this.refresh(descriptor)));
    return Response.json(current || { consecutiveFailures: 0 });
  }
}
