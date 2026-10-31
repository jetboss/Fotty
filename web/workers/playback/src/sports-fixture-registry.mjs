import { admitSportsCollectionIsolated, descriptorCompetitions, fixtureInstant, nextSportsRefresh, sportsRevision, sportsSnapshotIdentity,
  validateSportsFixture, SPORTS_FIXTURE_MAX_ROWS } from "./sports-fixture-policy.mjs";

const STATE_KEY = "sports-source-v1";
const RETRY_MS = 5 * 60_000;
const FAILURE_CODES = new Map([
  ["Sports schedule upstream unavailable", "upstream-unavailable"],
  ["Sports schedule is not JSON", "upstream-not-json"],
  ["Football schedule credential unavailable", "credential-unavailable"],
  ["Football schedule incomplete", "source-incomplete"],
  ["Football schedule window mismatch", "window-mismatch"],
  ["Football competition filter unavailable", "scope-mismatch"],
  ["EFL fixture activation pending", "activation-pending"],
  ["EFL schedule incomplete", "source-incomplete"],
  ["EFL schedule scope mismatch", "scope-mismatch"],
  ["EFL fixture identity mismatch", "scope-mismatch"],
  ["EFL schedule window mismatch", "window-mismatch"],
  ["EFL publisher receipt invalid", "receipt-invalid"],
  ["Pending competition scope invalid", "scope-mismatch"],
  ["Pending competition count mismatch", "source-incomplete"],
  ["Accepted fixture disappeared without cancellation evidence", "accepted-fixture-missing"],
  ["Accepted fixture identity became ambiguous", "fixture-identity-conflict"],
  ["Publisher fixture competition changed", "publisher-competition-conflict"],
  ["Source duplicate semantic fixture identity", "duplicate-fixture-identity"],
  ["Source duplicate publisher fixture identity", "duplicate-fixture-identity"],
  ["Terminal fixture status regressed", "terminal-rollback"],
  ["Collector receipt invalid", "receipt-invalid"],
  ["Source receipt invalid", "receipt-invalid"],
  ["Source receipt regressed", "receipt-regressed"],
  ["Pending timing scope invalid", "scope-mismatch"],
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
    const cohort = state?.cohorts?.[competition.id];
    const receipt = scoped ? cohort?.observedAt ?? state?.accepted?.observedAt : null;
    const observed = Date.parse(receipt);
    const pending = scoped ? cohort?.pendingFixtureCount ?? state?.accepted?.pendingByCompetition?.[competition.id]
      ?? (descriptorCompetitions(descriptor).length === 1 ? state?.accepted?.pendingFixtureCount : 0) : 0;
    const starts = cohort?.pendingStarts ?? state?.accepted?.pendingStartsByCompetition?.[competition.id] ?? [];
    const interval = nextSportsRefresh(fixtures, Number.isFinite(observed) ? new Date(observed) : now, starts, pending);
    const allowedAge = interval <= 15 * 60_000 ? 30 * 60_000 : interval + 30 * 60_000;
    const fresh = Number.isFinite(observed) && observed <= now.getTime() + 5 * 60_000 && now.getTime() - observed <= allowedAge;
    const failures = cohort?.consecutiveFailures ?? state?.consecutiveFailures ?? 0;
    const status = descriptor.supported === false ? "unsupported" : state?.accepted && !failures && fresh ? "covered" : "unavailable";
    return { sport: competition.sport || descriptor.sport, competitionId: competition.id, competitionName: competition.name,
      status, checkedAt: receipt || null, fixtureCount: fixtures.length,
      pendingFixtureCount: Number.isInteger(pending) && pending >= 0 && pending <= 10000 ? pending : 0,
      ...(fixtures.filter((fixture) => fixture.status === "scheduled").map((fixture) => fixture.start).sort()[0]
        ? { nextStart: fixtures.filter((fixture) => fixture.status === "scheduled").map((fixture) => fixture.start).sort()[0] } : {}),
      ...(status === "unsupported" && descriptor.reason ? { reason: descriptor.reason } : {}),
      sync: { consecutiveFailures: failures, lastAttemptAt: state?.lastAttemptAt || null,
        lastSuccessAt: receipt || null, conflict: cohort ? Boolean(cohort.conflict) : Boolean(state?.conflict),
        ...(cohort?.failure || !cohort && state?.failure ? { failure: cohort?.failure || state.failure } : {}) } };
  });
}

function previousCohort(previous, descriptor, competitionId) {
  const cohort = previous?.cohorts?.[competitionId];
  if (cohort) return cohort;
  const scoped = hasCompetitionReceipt(descriptor, previous?.accepted, competitionId);
  return { observedAt: scoped ? previous.accepted.observedAt : null,
    consecutiveFailures: previous?.consecutiveFailures || 0, conflict: Boolean(previous?.conflict),
    pendingFixtureCount: scoped ? previous.accepted.pendingByCompetition?.[competitionId]
      ?? (descriptorCompetitions(descriptor).length === 1 ? previous.accepted.pendingFixtureCount : 0) : 0,
    pendingStarts: previous?.accepted?.pendingStartsByCompetition?.[competitionId] || [],
    ...(previous?.failure ? { failure: previous.failure } : {}) };
}

function retainedAccepted(accepted, preserveAdmission = false) {
  return accepted && { ...accepted, fixtures: accepted.fixtures.map((fixture) => ({ ...fixture,
    source: { ...fixture.source, verification: preserveAdmission && fixture.source.verification !== "held" ? fixture.source.verification : "held" } })) };
}

export async function refreshSportsSource(previous, descriptor, now, collect) {
  if (descriptor.supported === false) return previous || { consecutiveFailures: 0 };
  const attempt = { lastAttemptAt: now.toISOString(), lastAttemptScope: competitionScope(descriptor) };
  let stage = "collection";
  try {
    const collection = await collect(descriptor, now);
    stage = "admission";
    const result = admitSportsCollectionIsolated(collection, previous?.accepted, descriptor, now, previous?.conflict);
    const cohorts = Object.fromEntries(descriptorCompetitions(descriptor).map(({ id }) => {
      const issue = result.issues.get(id), old = previousCohort(previous, descriptor, id);
      return [id, issue ? { ...old, consecutiveFailures: old.consecutiveFailures + 1, conflict: Boolean(issue.conflict),
        ...(issue.failure ? { failure: sportsFailureInfo(issue.failure, "admission") } : { failure: null }) }
        : { observedAt: collection.observedAt, consecutiveFailures: 0, conflict: false,
          pendingFixtureCount: collection.pendingByCompetition?.[id] ?? collection.pendingFixtureCount,
          pendingStarts: collection.pendingStartsByCompetition?.[id] || [] }];
    }));
    const issueFailure = [...result.issues.values()].find((issue) => issue.failure)?.failure;
    const partial = result.issues.size > 0;
    const pendingStarts = Object.values(collection.pendingStartsByCompetition || {}).flat();
    return { accepted: result.accepted, cohorts, consecutiveFailures: partial ? (previous?.consecutiveFailures || 0) + 1 : 0,
      ...(partial ? { failure: issueFailure ? sportsFailureInfo(issueFailure, "admission") : null } : {}),
      ...(result.conflict ? { conflict: result.conflict } : {}), ...attempt,
      nextAttemptAt: new Date(now.getTime() + (partial ? RETRY_MS
        : nextSportsRefresh(result.accepted.fixtures, now, pendingStarts, collection.pendingFixtureCount))).toISOString() };
  } catch (error) {
    // No exception/body/credential reaches public snapshots or operational logs.
    const failure = sportsFailureInfo(error, stage);
    const cohorts = Object.fromEntries(descriptorCompetitions(descriptor).map(({ id }) => {
      const old = previousCohort(previous, descriptor, id);
      return [id, { ...old, consecutiveFailures: old.consecutiveFailures + 1, failure }];
    }));
    return { ...previous, ...(previous?.accepted ? { accepted: retainedAccepted(previous.accepted, stage === "collection"
      && (["TimeoutError", "AbortError"].includes(failure.kind) || failure.code === "upstream-unavailable"
        && ([408, 429].includes(failure.httpStatus) || failure.httpStatus >= 500))) } : {}), cohorts,
      consecutiveFailures: (previous?.consecutiveFailures || 0) + 1, failure, ...attempt,
      nextAttemptAt: new Date(now.getTime() + RETRY_MS).toISOString() };
  }
}

// Preserve only already admitted, still-current fixture facts after a typed
// temporary transport failure. The scope remains unavailable. Neither the
// source receipt nor LIVE expiry advances, and a conflict/contract failure can
// never use this continuity path. This also supports legacy stored cohorts.
export function retainedSportsFixture(fixture, descriptor, state, now) {
  const failure = state?.failure;
  const temporary = failure?.stage === "collection" && (["TimeoutError", "AbortError"].includes(failure.kind)
    || failure.code === "upstream-unavailable" && ([408, 429].includes(failure.httpStatus) || failure.httpStatus >= 500));
  const observed = Date.parse(fixture.source?.observedAt), age = +now - observed;
  if (!temporary || state.conflict || fixture.source.verification !== undefined
    || !hasCompetitionReceipt(descriptor, state.accepted, fixture.competitionId)
    || fixture.source.observedAt !== state.accepted.observedAt || age < -300_000 || age > 1_800_000) return fixture;
  return { ...fixture, source: { ...fixture.source, verification: "verified" } };
}

export async function assembleSportsSnapshot(descriptors, states, now) {
  const fixtures = [];
  const coverage = [];
  const seen = new Set(), identities = new Set();
  for (const descriptor of descriptors) {
    const state = states.get(descriptor.id);
    const sourceLanes = sourceCoverage(descriptor, state, now);
    coverage.push(...sourceLanes);
    for (const fixture of state?.accepted?.fixtures || []) {
      if (seen.has(fixture.id)) throw new Error("Duplicate cross-source fixture identity");
      const lane = sourceLanes.find((row) => row.competitionId === fixture.competitionId);
      const marker = fixture.source?.verification;
      if (!lane || marker !== undefined && !["verified", "held"].includes(marker)
        || marker === "held" && lane.status !== "unavailable"
        || marker === "verified" && (!state.cohorts?.[fixture.competitionId]
          || fixture.source.observedAt !== state.accepted.observedAt)
        || marker === undefined && fixture.source.observedAt !== lane.checkedAt
        || lane.status === "covered" && fixture.source.observedAt !== lane.checkedAt) throw new Error("Invalid sports admission provenance");
      const source = { ...fixture.source };
      delete source.verification;
      // Retained records validate at their original collection instant, never
      // by substituting today's time or trusting a verification bit alone.
      validateSportsFixture({ ...fixture, source }, new Date(fixtureInstant(source.observedAt)), descriptor);
      const semantic = sportsSnapshotIdentity(fixture);
      if (identities.has(semantic)) throw new Error("Duplicate cross-source semantic fixture identity");
      identities.add(semantic);
      if (descriptor.sourceName && source.name !== descriptor.sourceName) throw new Error("Invalid sports admission provenance");
      if (descriptor.sourceURL) {
        const actual = new URL(source.url), expected = new URL(descriptor.sourceURL);
        const pathMatches = descriptor.adapter === "nhl"
          ? actual.pathname.startsWith(`${expected.pathname}/`) && /^\d{4}-\d{2}-\d{2}$/.test(actual.pathname.slice(expected.pathname.length + 1))
          : actual.pathname === expected.pathname;
        if (actual.origin !== expected.origin || !pathMatches) throw new Error("Invalid sports admission provenance");
      }
      seen.add(fixture.id);
      const age = now.getTime() - fixtureInstant(fixture.source.observedAt);
      // A per-record override only represents a recent partial admission.
      // Quiet whole-cohort freshness must not renew an unavailable cohort's
      // stale verified row when the cron has stopped advancing it.
      fixtures.push(marker === "verified" && lane.status === "unavailable" && (age > 30 * 60_000 || age < -5 * 60_000)
        ? { ...fixture, source: { ...fixture.source, verification: "held" } }
        : retainedSportsFixture(fixture, descriptor, state, now));
    }
  }
  fixtures.sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
  if (fixtures.length > SPORTS_FIXTURE_MAX_ROWS) throw new Error("Aggregate fixture limit exceeded");
  const receipts = [...coverage.map((row) => row.checkedAt), ...fixtures.map((row) => row.source.observedAt)].filter(Boolean);
  // Legacy UTC without fractions can sort after a newer fractional receipt in
  // the same second. Compare instants; never let the envelope predate its rows.
  const latestReceipt = receipts.reduce((latest, receipt) => {
    const time = fixtureInstant(receipt);
    return time > latest.time ? { time, receipt } : latest;
  }, { time: -Infinity, receipt: null }).receipt;
  const available = coverage.filter((row) => row.status !== "unsupported");
  const snapshot = { schemaVersion: 1, complete: true, checkedAt: latestReceipt || now.toISOString(),
    sourceStatus: available.every((row) => row.status === "covered") && available.length ? "verified" : "partial", fixtures, coverage };
  return { ...snapshot, revision: await sportsRevision(snapshot.fixtures, coverage) };
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
