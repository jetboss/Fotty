import { associateBroadcasts, buildBroadcastSnapshot, normalizeBroadcastCollection,
  normalizeRegistryFixtures, mergeBroadcastRecords, BROADCAST_PROVIDER_CODES, BROADCAST_SCOPES, BROADCAST_REGISTRY_LIMITS,
  BROADCAST_REASONS, isReviewedTVFootballAssignment } from "./broadcast-registry-policy.mjs";

import { REVIEWED_TV_GUIDE_KEY, validateReviewedTVGuide, currentReviewedTVGuide } from "./reviewed-tv-guide.mjs";
import { reviewedTVGuideAssignments } from "./reviewed-tv-guide-assignments.mjs";

const KEY = "shared-broadcast-registry-v1", minute = 60_000, day = 86_400_000;
export const DEFAULT_BROADCAST_REGISTRY_PROVIDERS = Object.freeze(BROADCAST_PROVIDER_CODES.map((providerCode) => Object.freeze({
  providerCode, maxRequestsPerDay: providerCode === "reviewedtv" ? 576 : ["communitysports", "plaviosports"].includes(providerCode) ? 288 : 96,
})));
const blank = () => ({ version: 1, providers: {}, budgets: {}, cursor: 0 });
const failure = (error) => BROADCAST_REASONS.includes(error?.message) ? error.message : "source-unavailable";
const iso = (n) => new Date(n).toISOString();
const RECORD_KEYS = new Set(["id", "providerCode", "providerEventID", "streamID", "resourceType", "scope", "kind", "sport", "title", "participants",
  "start", "startBasis", "end", "competitionID", "squad", "format", "matchOrdinal", "day", "channelID", "stationMarket", "observedAt", "expiresAt", "verification", "issues"]);

function validateState(state) {
  if (!state || state.version !== 1 || !state.providers || !state.budgets || !Number.isSafeInteger(state.cursor)
    || Object.keys(state.providers).some((code) => !BROADCAST_PROVIDER_CODES.includes(code))
    || Object.keys(state.budgets).some((code) => !BROADCAST_PROVIDER_CODES.includes(code))) throw new Error("invalid-registry-state");
  for (const budget of Object.values(state.budgets)) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(budget.day) || !Number.isSafeInteger(budget.count) || budget.count < 0
      || !Number.isFinite(budget.lastAt)) throw new Error("invalid-registry-state");
  }
  let count = 0;
  for (const [code, source] of Object.entries(state.providers)) {
    if (!source || !source.scopes || !Array.isArray(source.records) || !Number.isSafeInteger(source.failures)
      || source.failures < 0 || !Number.isSafeInteger(source.cursor) || source.cursor < 0 || source.cursor > 65535) throw new Error("invalid-registry-state");
    if (source.kickoffCheckpoint !== undefined) {
      const checkpoint = source.kickoffCheckpoint;
      if (!checkpoint || Array.isArray(checkpoint) || Object.keys(checkpoint).sort().join() !== "ordinaryDue,postponedUntil,start,takenAt"
        || ![checkpoint.start, checkpoint.takenAt, checkpoint.ordinaryDue, checkpoint.postponedUntil].every((n) => Number.isSafeInteger(n) && n >= 0)
        || checkpoint.start < checkpoint.takenAt || checkpoint.start - checkpoint.takenAt > 5 * minute
        || checkpoint.ordinaryDue < checkpoint.takenAt || checkpoint.postponedUntil < checkpoint.ordinaryDue
        || checkpoint.postponedUntil - checkpoint.takenAt > 16 * day) throw new Error("invalid-registry-state");
    }
    count += source.records.length;
    for (const [id, scope] of Object.entries(source.scopes)) {
      if (!BROADCAST_SCOPES.includes(id) || scope.scope !== id || scope.providerCode !== code
        || !["available", "partial", "empty", "failed", "unsupported"].includes(scope.status)
        || scope.failure !== undefined && !BROADCAST_REASONS.includes(scope.failure)) throw new Error("invalid-registry-state");
    }
    for (const row of source.records) {
      if (!row || Object.keys(row).some((key) => !RECORD_KEYS.has(key)) || row.providerCode !== code || !BROADCAST_SCOPES.includes(row.scope)
        || !/^br:[a-f0-9]{64}$/.test(row.id) || !Number.isFinite(Date.parse(row.observedAt)) || !Number.isFinite(Date.parse(row.expiresAt))
        || JSON.stringify(row).includes("://")) throw new Error("invalid-registry-state");
      if (row.stationMarket !== undefined && !isReviewedTVFootballAssignment(row) && (row.stationMarket !== "US" || code !== "communitysports" || row.kind !== "channel"
        || !["networks", "cricket", "live"].includes(row.scope) || row.sport !== "cricket" || row.channelID !== "cricket-channel:willow")) throw new Error("invalid-registry-state");
    }
  }
  if (count > BROADCAST_REGISTRY_LIMITS.records || new TextEncoder().encode(JSON.stringify(state)).length > BROADCAST_REGISTRY_LIMITS.snapshotBytes) throw new Error("capacity-exceeded");
  return state;
}

function supportedFixtures(code, fixtures) {
  // Activity only changes collection scheduling. It is never admission, LIVE
  // inference or permission to invent a provider route for an unsupported sport.
  if (code === "score808") return fixtures.filter((f) => f.sport === "football");
  if (code === "cncsports") return fixtures.filter((f) => f.sport === "hockey" && f.competitionID === "nhl");
  if (code === "streamvix") return fixtures.filter((f) => f.sport === "football"
    && ["premier-league", "champions-league"].includes(f.competitionID));
  if (code === "plaviosports") return fixtures.filter((f) => ["football", "cricket"].includes(f.sport));
  if (code === "reviewedtv") return fixtures.filter((f) => f.sport === "cricket" || f.sport === "baseball" && f.competitionID === "mlb" || f.sport === "hockey" && f.competitionID === "nhl" || f.sport === "football"
    && ["premier-league", "champions-league", "la-liga", "serie-a", "bundesliga", "ligue-1"].includes(f.competitionID));
  if (code === "flixstreams") return fixtures.filter((f) => f.sport === "cricket" || f.sport === "football"
    && ["premier-league", "champions-league", "serie-a", "la-liga", "bundesliga", "ligue-1"].includes(f.competitionID));
  return fixtures;
}

function cadence(fixtures, now, cost, cap) {
  const active = fixtures.some((f) => f.status === "live" || Date.parse(f.start) <= now + 30 * minute && Date.parse(f.start) >= now - 30 * minute);
  const soon = fixtures.some((f) => Date.parse(f.start) > now && Date.parse(f.start) <= now + day);
  // Spend actual reads, not logical batches. A three-request source cannot
  // silently acquire one-request cadence or borrow the observer's allowance.
  return Math.max(active ? 5 * minute : soon ? 15 * minute : 4 * 60 * minute,
    Math.ceil(day * Math.max(1, cost) / cap));
}

function activeReviewedTV(fixtures, now) {
  return supportedFixtures("reviewedtv", fixtures).some((f) => f.status === "live"
    || Math.abs(Date.parse(f.start) - now) <= 30 * minute);
}
function healthyReviewedTVExpiry(source, now) {
  return Math.max(0, ...(source?.records ?? []).filter((r) => r.providerCode === "reviewedtv" && r.verification === "dated"
    && ["available", "partial"].includes(source.scopes?.[r.scope]?.status) && Date.parse(r.expiresAt) > now)
    .map((r) => Date.parse(r.expiresAt)));
}
function reviewedTVDemandDue(descriptor, source, fixtures, now) {
  const due = Date.parse(source?.nextAttemptAt ?? "1970-01-01T00:00:00Z"), last = Date.parse(source?.lastAttemptAt);
  if (descriptor.providerCode !== "reviewedtv" || !Number.isFinite(last) || !activeReviewedTV(fixtures, now)
    || source.failures && !healthyReviewedTVExpiry(source, now)) return due;
  // Quiet/soon planning is not a prepaid HTTP reservation. Re-evaluate it when
  // actual admitted demand becomes active, using the fixed collector's maximum
  // three reads (two Willow dates plus one RSS), inside the SAME daily ledger.
  // Existing spend-ahead debt remains binding; no old reads are refunded.
  return Math.max(source.kickoffCheckpoint?.postponedUntil ?? 0,
    Math.min(due, last + cadence(supportedFixtures("reviewedtv", fixtures), now, 3, descriptor.maxRequestsPerDay)));
}

function checkpointPlan(source, fixtures, now, ordinaryDue, cap) {
  if (source?.failures || !Number.isFinite(ordinaryDue)) return null;
  const prior = source?.kickoffCheckpoint;
  // One checkpoint groups every fixture with the same literal accepted UTC
  // kickoff. Do not advance another slot until the previous advance is repaid.
  if (prior && prior.postponedUntil > now) return null;
  const start = [...new Set(fixtures.map((f) => Date.parse(f.start)))].sort((a, b) => a - b)
    .find((at) => at > now && at <= now + 5 * minute && (!prior || at > prior.start));
  if (start === undefined) return null;
  if (ordinaryDue <= now) return { start, takenAt: now, ordinaryDue: now, postponedUntil: now };
  const last = Date.parse(source.lastAttemptAt), interval = ordinaryDue - last;
  if (!Number.isFinite(last) || last > now || interval < 5 * minute || interval > 8 * day) return null;
  // Move the existing next background cycle into this pre-kickoff window, then
  // skip its old slot. This is spend-ahead debt, not another repeating cadence.
  // A crash before settlement must conservatively charge a full eight-read
  // slot. The completed cycle settles this using its actual durable reads.
  return { start, takenAt: now, ordinaryDue,
    postponedUntil: ordinaryDue + Math.max(interval, Math.ceil(day * 8 / cap)) };
}

export class BroadcastRegistry {
  constructor(state, env, options = {}) {
    this.state = state; this.env = env; this.options = options; this.queue = Promise.resolve(); this.budgetQueue = Promise.resolve();
    this.providers = options.providers ?? DEFAULT_BROADCAST_REGISTRY_PROVIDERS;
    if (!Array.isArray(this.providers) || this.providers.length > BROADCAST_PROVIDER_CODES.length || new Set(this.providers.map((p) => p.providerCode)).size !== this.providers.length
      || this.providers.some((p) => !BROADCAST_PROVIDER_CODES.includes(p.providerCode) || !Number.isSafeInteger(p.maxRequestsPerDay)
        || p.maxRequestsPerDay < 1 || p.maxRequestsPerDay > (p.providerCode === "reviewedtv" ? 576 : 288))) throw new Error("invalid-registry-configuration");
  }
  now() { const n = Number(this.options.clock?.() ?? new Date()); if (!Number.isFinite(n)) throw new Error("invalid-registry-clock"); return n; }
  enabled() { return this.options.enabled?.() !== false; }
  enqueue(operation) { const result = this.queue.then(operation); this.queue = result.then(() => undefined, () => undefined); return result; }
  async stored() { const state = await this.state.storage.get(KEY); return state ? validateState(state) : blank(); }
  async reserve(stored, descriptor, cycle) {
    const operation = async () => {
      const now = this.now(), date = iso(now).slice(0, 10), prior = stored.budgets[descriptor.providerCode];
      if (!this.enabled() || cycle.reads >= 8 || prior && now < prior.lastAt) return false;
      const budget = prior && date <= prior.day ? { ...prior } : { day: date, count: 0, lastAt: now };
      if (budget.day !== date || budget.count >= descriptor.maxRequestsPerDay) return false;
      budget.count++; budget.lastAt = now; stored.budgets[descriptor.providerCode] = budget;
      // Persist the reservation before any HTTP request. A failed write rejects
      // the read; cancellation/restart/re-enable cannot refund spent requests.
      await this.state.storage.put(KEY, stored);
      cycle.reads++;
      return true;
    };
    const result = this.budgetQueue.then(operation);
    this.budgetQueue = result.then(() => undefined, () => undefined);
    return result;
  }
  async snapshot(stored, fixtures, now) {
    const providers = [], broadcasts = [];
    for (const descriptor of this.providers) {
      const state = stored.providers[descriptor.providerCode];
      if (!state) continue;
      for (const scope of Object.values(state.scopes ?? {})) providers.push({ ...scope,
        ...(state.nextAttemptAt ? { nextAttemptAt: state.nextAttemptAt } : {}) });
      for (const record of state.records ?? []) {
        if (now - Date.parse(record.observedAt) <= BROADCAST_REGISTRY_LIMITS.retention) broadcasts.push(record);
      }
    }
    const merged = mergeBroadcastRecords(broadcasts, new Date(now), providers);
    const links = associateBroadcasts({ fixtures, broadcasts: merged, providers, now: new Date(now) });
    const snapshot = await buildBroadcastSnapshot({ providers, broadcasts: merged, links, now: new Date(now) });
    // Separate storage preserves the existing accepted registry/rollback schema.
    // A malformed guide cannot withdraw working fixture associations.
    try {
      const guide = await this.state.storage.get(REVIEWED_TV_GUIDE_KEY);
      if (guide !== undefined) {
        snapshot.tvGuide = currentReviewedTVGuide(guide, new Date(now));
        snapshot.tvGuideAssignments = await reviewedTVGuideAssignments(snapshot.tvGuide, fixtures, new Date(now));
      }
    } catch { /* Retain the main registry; omit unverified guide data. */ }
    return snapshot;
  }
  async fixtures() {
    if (typeof this.options.loadFixtures !== "function") throw new Error("official-fixtures-unavailable");
    return normalizeRegistryFixtures(await this.options.loadFixtures(), new Date(this.now()));
  }
  eligible(descriptor, stored, now, fixtures = []) {
    const source = stored.providers[descriptor.providerCode], budget = stored.budgets[descriptor.providerCode];
    if (budget && (now < budget.lastAt || budget.day === iso(now).slice(0, 10) && budget.count >= descriptor.maxRequestsPerDay)) return false;
    const due = reviewedTVDemandDue(descriptor, source, fixtures, now);
    return due <= now || descriptor.providerCode !== "reviewedtv"
      && checkpointPlan(source, supportedFixtures(descriptor.providerCode, fixtures), now, due, descriptor.maxRequestsPerDay) !== null;
  }
  async continueIfDue(stored, now, fixtures) {
    if (this.enabled() && this.providers.some((p) => this.eligible(p, stored, now, fixtures))) {
      // One bounded continuation drains at most two more due providers. Repeated
      // cron/alarm delivery uses the same due times and persisted read ledger.
      await this.state.storage.setAlarm?.(now + 15_000);
    } else {
      const descriptor = this.providers.find((p) => p.providerCode === "reviewedtv"), source = stored.providers.reviewedtv;
      const budget = stored.budgets.reviewedtv, due = descriptor && reviewedTVDemandDue(descriptor, source, fixtures, now);
      // The five-minute cron rounds a7.5-minute due time up to the ten-minute
      // expiry boundary. One DO alarm executes the ALREADY planned TV slot;
      // it adds no reads/cadence and cannot loop on empty or failed inventories.
      if (this.enabled() && descriptor && activeReviewedTV(fixtures, now) && due > now
        && due < healthyReviewedTVExpiry(source, now) && !(budget && (now < budget.lastAt
          || budget.day === iso(now).slice(0, 10) && budget.count >= descriptor.maxRequestsPerDay))) {
        await this.state.storage.setAlarm?.(due);
      } else await this.state.storage.deleteAlarm?.();
    }
  }
  async refresh() {
    if (!this.enabled()) { await this.state.storage.deleteAlarm?.(); throw new Error("registry-disabled"); }
    if (typeof this.options.collect !== "function") throw new Error("collector-unavailable");
    const stored = await this.stored(), now = this.now(), fixtures = await this.fixtures();
    const ordered = this.providers.map((_, i) => this.providers[(stored.cursor + i) % this.providers.length]);
    const reviewed = this.providers.find((p) => p.providerCode === "reviewedtv"), reviewedState = stored.providers.reviewedtv;
    if (reviewed && reviewedState) reviewedState.nextAttemptAt = iso(reviewedTVDemandDue(reviewed, reviewedState, fixtures, now));
    const due = ordered.filter((p) => this.eligible(p, stored, now, fixtures));
    const urgentTV = due.find((p) => p.providerCode === "reviewedtv" && activeReviewedTV(fixtures, now) && healthyReviewedTVExpiry(reviewedState, now));
    // Short-lived accepted TV facts must not wait behind several20-second
    // collector batches. The second slot/other provider ledgers stay unchanged.
    const selected = (urgentTV ? [urgentTV, ...due.filter((p) => p !== urgentTV)] : due).slice(0, 2);
    let checkpointChanged = false;
    for (const descriptor of selected) {
      // TV's ordinary deadline already refreshes before its ten-minute expiry.
      // A new spend-ahead checkpoint would repay by creating a longer stale gap.
      if (descriptor.providerCode === "reviewedtv") continue;
      const source = stored.providers[descriptor.providerCode];
      const checkpoint = checkpointPlan(source, supportedFixtures(descriptor.providerCode, fixtures), now,
        Date.parse(source?.nextAttemptAt ?? "1970-01-01T00:00:00Z"), descriptor.maxRequestsPerDay);
      if (checkpoint) {
        stored.providers[descriptor.providerCode] = { ...(source ?? { scopes: {}, records: [], failures: 0, cursor: 0 }), kickoffCheckpoint: checkpoint,
          nextAttemptAt: iso(Math.max(now, checkpoint.postponedUntil)) };
        checkpointChanged = true;
      }
    }
    // Consume the grouped window/debt before any HTTP reservation. A restart or
    // failed collection cannot spend the same advanced background slot again.
    if (checkpointChanged) await this.state.storage.put(KEY, stored);
    const accepted = structuredClone(stored.providers);
    const results = await Promise.all(selected.map(async (descriptor) => {
      const cycle = { reads: 0 }, previous = stored.providers[descriptor.providerCode];
      const signal = AbortSignal.timeout(20_000);
      try {
        const raw = await this.options.collect(descriptor.providerCode, { now: new Date(now), signal,
          cursor: previous?.cursor ?? 0, fixtures: structuredClone(fixtures),
          reserveRequest: () => this.reserve(stored, descriptor, cycle) });
        if (signal.aborted) throw new Error("source-unavailable");
        const collection = await normalizeBroadcastCollection(descriptor.providerCode, raw, new Date(this.now()));
        let tvGuide;
        if (descriptor.providerCode === "reviewedtv" && raw.tvGuide !== undefined) {
          try { tvGuide = validateReviewedTVGuide(raw.tvGuide, new Date(this.now())); } catch { /* Guide isolation. */ }
        }
        return { descriptor, cycle, collection, tvGuide };
      } catch (error) { return { descriptor, cycle, error: failure(error) }; }
    }));
    for (const { descriptor, cycle, collection, error, tvGuide } of results) {
      if (tvGuide !== undefined) {
        try { await this.state.storage.put(REVIEWED_TV_GUIDE_KEY, tvGuide); }
        catch { console.warn("TV guide persistence failed; accepted match registry retained"); }
      }
      const code = descriptor.providerCode, previous = stored.providers[code] ?? { scopes: {}, records: [], failures: 0, cursor: 0 };
      const state = { ...previous, scopes: { ...previous.scopes }, records: [...previous.records], lastAttemptAt: iso(now) };
      if (collection) {
        for (const scope of collection.scopes) {
          const old = state.scopes[scope.scope];
          if (["available", "partial", "empty"].includes(scope.status)) {
            const incoming = collection.broadcasts.filter((r) => r.scope === scope.scope), ids = new Set(incoming.map((r) => r.id));
            if (scope.complete) state.records = state.records.filter((r) => r.scope !== scope.scope);
            else state.records = state.records.filter((r) => r.scope !== scope.scope || !ids.has(r.id));
            state.records.push(...incoming);
            state.scopes[scope.scope] = { ...scope, lastSuccessAt: scope.observedAt,
              expiresAt: iso(Date.parse(scope.observedAt) + BROADCAST_REGISTRY_LIMITS.sourceLifetime) };
          } else {
            state.scopes[scope.scope] = { ...(old ?? { providerCode: code, scope: scope.scope }),
              status: scope.status, complete: scope.complete,
              ...(scope.failure ? { failure: scope.failure } : {}), lastAttemptAt: iso(now) };
          }
        }
        state.failures = collection.scopes.some((s) => s.status === "failed") ? previous.failures + 1 : 0;
        state.cursor = collection.cursor ?? previous.cursor;
      } else {
        for (const scope of Object.keys(state.scopes)) state.scopes[scope] = { ...state.scopes[scope],
          status: "failed", complete: false, failure: error, lastAttemptAt: iso(now) };
        if (!Object.keys(state.scopes).length) state.scopes.live = { providerCode: code, scope: "live", status: "failed", complete: false,
          failure: error, lastAttemptAt: iso(now) };
        state.failures = previous.failures + 1;
      }
      state.records = state.records.filter((r) => now - Date.parse(r.observedAt) <= BROADCAST_REGISTRY_LIMITS.retention);
      const delay = cadence(supportedFixtures(code, fixtures), now, Math.max(cycle.reads, 1), descriptor.maxRequestsPerDay);
      const independentTV = code === "reviewedtv" && healthyReviewedTVExpiry(state, now);
      const retryDelay = state.failures && !independentTV ? Math.max(delay, Math.min(60 * minute, 5 * minute * 2 ** Math.min(4, state.failures - 1))) : delay;
      if (state.kickoffCheckpoint?.takenAt === now) state.kickoffCheckpoint = { ...state.kickoffCheckpoint,
        postponedUntil: state.kickoffCheckpoint.ordinaryDue + retryDelay };
      state.nextAttemptAt = iso(Math.max(state.kickoffCheckpoint?.postponedUntil ?? 0, now + retryDelay));
      stored.providers[code] = state;
    }
    if (selected.length && this.providers.length) {
      const last = this.providers.findIndex((p) => p.providerCode === selected.at(-1).providerCode);
      stored.cursor = (last + 1) % this.providers.length;
    }
    // Validate the entire candidate before one durable commit. A capacity or
    // shape failure preserves accepted records while reservations stay spent.
    let snapshot;
    try {
      validateState(stored);
      snapshot = await this.snapshot(stored, fixtures, this.now());
    } catch (error) {
      // A capacity/invalid candidate cannot erase accepted sibling records.
      // Keep the independently persisted request ledger and expose a finite
      // source failure instead of publishing a truncated positive inventory.
      stored.providers = accepted;
      for (const { descriptor } of results) {
        const code = descriptor.providerCode;
        const old = stored.providers[code] ?? { scopes: {}, records: [], failures: 0, cursor: 0 };
        const held = { ...old, scopes: { ...old.scopes }, failures: old.failures + 1,
          lastAttemptAt: iso(now), nextAttemptAt: iso(Math.max(now + 60 * minute, old.kickoffCheckpoint?.postponedUntil ?? 0)) };
        if (!Object.keys(held.scopes).length) held.scopes.live = { providerCode: code, scope: "live" };
        for (const scope of Object.keys(held.scopes)) held.scopes[scope] = { ...held.scopes[scope], status: "failed", complete: false,
          failure: error?.message === "capacity-exceeded" ? "capacity-exceeded" : "invalid-collection", lastAttemptAt: iso(now) };
        stored.providers[code] = held;
      }
      snapshot = await this.snapshot(stored, fixtures, this.now());
    }
    await this.state.storage.put(KEY, stored);
    await this.continueIfDue(stored, this.now(), fixtures);
    return snapshot;
  }
  async alarm() {
    try { await this.enqueue(() => this.refresh()); }
    catch {
      // Official-registry/storage failure is retried by the existing cloud
      // cron. Do not create an unbounded alarm retry loop or probe providers.
      await this.state.storage.deleteAlarm?.();
    }
  }
  async fetch(request) {
    const path = new URL(request.url).pathname;
    try {
      if (request.method === "POST" && path === "/refresh") return Response.json(await this.enqueue(() => this.refresh()));
      if (request.method === "GET" && path === "/snapshot") return Response.json(await this.enqueue(async () => this.snapshot(await this.stored(), await this.fixtures(), this.now())));
      return Response.json({ error: "Not found" }, { status: 404 });
    } catch (error) {
      return Response.json({ schemaVersion: 1, complete: false,
        error: BROADCAST_REASONS.includes(error?.message) ? error.message : "source-unavailable" }, { status: 503 });
    }
  }
}
