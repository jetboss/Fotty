// Shared, metadata-only broadcast association. This module performs no I/O,
// selects no upstream and never carries media locations or credentials.
import { canonicalFootballClubId } from "../../../src/lib/football-competition-catalog.generated.ts";
export const BROADCAST_REGISTRY_SCHEMA = 1;
export const BROADCAST_REGISTRY_LIMITS = Object.freeze({ collectionRecords: 1500, collectionBytes: 1024 * 1024,
  records: 4000, links: 4000, snapshotBytes: 4 * 1024 * 1024, sourceLifetime: 4 * 60 * 60_000,
  programmeLifetime: 10 * 60_000, retention: 24 * 60 * 60_000 });
export const BROADCAST_PROVIDER_CODES = Object.freeze(["streamex", "score808", "communitysports", "plaviosports", "cncsports", "flixstreams", "streamvix", "reviewedtv"]);
export const BROADCAST_SCOPES = Object.freeze(["football", "cricket", "basketball", "baseball", "hockey", "american-football", "rugby", "fight", "motorsport", "golf", "tennis", "darts", "college", "other", "live", "networks"]);
export const BROADCAST_REASONS = Object.freeze(["source-unavailable", "budget-exhausted", "invalid-collection", "incomplete-catalog", "catalog-conflict", "stale-source", "identity-conflict", "time-conflict", "squad-conflict", "competition-conflict", "format-conflict", "ordinal-conflict", "day-conflict", "missing-date", "missing-participants", "missing-programme", "unverified-fixture", "terminal-fixture", "missing-test-authority", "unsupported-scope", "capacity-exceeded"]);
const providers = new Set(BROADCAST_PROVIDER_CODES), scopes = new Set(BROADCAST_SCOPES), reasons = new Set(BROADCAST_REASONS);
const kinds = new Set(["event", "channel", "programme"]), formats = new Set(["Test", "T20", "ODI", "T10"]);
const channels = new Set(["cricket-channel:willow", "cricket-channel:fox-cricket"]);
const reviewedTVFootballCompetitions = new Set(["premier-league", "champions-league", "la-liga", "serie-a", "bundesliga", "ligue-1"]);
export function isReviewedTVFootballAssignment(row, providerCode = row?.providerCode) {
  const match = /^sports-channel:(espn(?:[2-7])?-latinamerica-south)$/u.exec(row?.channelID ?? "");
  return providerCode === "reviewedtv" && row?.scope === "football" && row.sport === "football" && row.kind === "event"
    && /^reviewed-tv:assignment:[a-f0-9]{64}$/u.test(row.providerEventID ?? "") && !!match
    && row.streamID === "reviewed-tv:" + match[1] && row.stationMarket === "UY" && stamp(row.start) !== null && row.end === undefined
    && reviewedTVFootballCompetitions.has(row.competitionID) && row.squad?.gender === "men" && row.squad?.ageGroup === "senior";
}
export function isReviewedTVScheduledAssignment(row, providerCode = row?.providerCode) {
  if (isReviewedTVFootballAssignment(row, providerCode)) return true;
  const station = /^sports-channel:(espn(?:[2-7])?-latinamerica-south)$/u.exec(row?.channelID ?? "");
  return providerCode === "reviewedtv" && row?.scope === row?.sport && row.kind === "event"
    && (row.sport === "baseball" && row.competitionID === "mlb" || row.sport === "hockey" && row.competitionID === "nhl") && row.squad?.gender === "men" && row.squad?.ageGroup === "senior" && row.format === undefined && !!station
    && row.streamID === "reviewed-tv:" + station[1] && row.stationMarket === "UY" && row.end === undefined
    && stamp(row.start) !== null && /^reviewed-tv:assignment:[a-f0-9]{64}$/u.test(row.providerEventID ?? "");
}
// This producer synthesizes released from Date.now() for dynamic FanCode
// entries. Retain the clock for audit; it has no kickoff/date authority.
export function isCurrentCricketListing(row, providerCode = row?.providerCode) {
  return providerCode === "communitysports" && row?.startBasis === "current-listing"
    && /^nuvio_sport_sktech_sktech_ev_fancode_[0-9]+$/u.test(row.providerEventID ?? "")
    && row.streamID === row.providerEventID && row.resourceType === "tv" && row.kind === "event"
    && row.sport === "cricket" && ["cricket", "live"].includes(row.scope)
    && /^🔴 LIVE: /u.test(row.title ?? "")
    && same(pair(String(row.title).slice("🔴 LIVE: ".length).split(/\s+(?:vs\.?|v\.?|versus)\s+/iu), "cricket"), pair(row.participants, "cricket"))
    && pair(row.participants, "cricket") !== null && row.format === undefined && row.matchOrdinal === undefined
    && row.day === undefined && row.end === undefined && row.channelID === undefined && row.competitionID === undefined
    && row.stationMarket === undefined && row.squad === undefined && stamp(row.start) !== null;
}
const minute = 60_000, day = 86_400_000;
const object = (v) => v && typeof v === "object" && !Array.isArray(v);
const bytes = (v) => new TextEncoder().encode(JSON.stringify(v)).length;
function text(v, max = 512) { return typeof v === "string" && v.length > 0 && v.length <= max
  && v === v.trim() && !/[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069<>]/u.test(v) && !v.includes("://"); }
function reference(v, max = 4096) { return text(v, max) && /^[\p{L}\p{N}_.:~=\-]+$/u.test(v)
  && !/^(?:https?|file|data|javascript):/iu.test(v); }
function stamp(v) {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(v)) return null;
  const n = Date.parse(v), date = v.slice(0, 10);
  return Number.isFinite(n) && new Date(n).toISOString().slice(0, 10) === date
    && Number(v.slice(11, 13)) < 24 && Number(v.slice(14, 16)) < 60 && Number(v.slice(17, 19)) < 60 ? n : null;
}
const iso = (n) => new Date(n).toISOString();
const normal = (v) => v.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase().replace(/&/g, " and ")
  .replace(/[^\p{L}\p{N}]+/gu, " ").trim().replace(/\s+/g, " ");
const placeholders = new Set(["home", "away", "tbd", "tbc", "unknown", "teams to be confirmed"]);
const squadPattern = /\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b/gu;
function teamKey(value, sport) {
  const normalized = normal(value);
  // Reviewed club aliases and squad identity are independent. Resolve only
  // literal aliases of the base club, then restore every explicit qualifier.
  const qualifiers = [...new Set([...normalized.matchAll(squadPattern)].map(([token]) => {
    const compact = token.replace(/ /g, "");
    return ["women", "womens", "ladies", "w"].includes(compact) ? "women"
      : ["reserve", "reserves"].includes(compact) ? "reserves" : compact.replace(/^under/u, "u");
  }))].sort();
  const base = normalized.replace(squadPattern, " ").trim().replace(/\s+/g, " ");
  if (!base || placeholders.has(base)) return null;
  const reviewedClub = sport === "football" ? canonicalFootballClubId(base) : undefined;
  const canonical = reviewedClub ? `football|${reviewedClub}` : base;
  return qualifiers.length ? `${canonical}|${qualifiers.join(",")}` : canonical;
}
function pair(v, sport) {
  if (!Array.isArray(v) || v.length !== 2 || !v.every((x) => text(x, 256))) return null;
  const keys = v.map((name) => teamKey(name, sport));
  return keys.every(Boolean) && keys[0] !== keys[1] ? keys.sort() : null;
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function squad(v) { return object(v) && ["men", "women", "mixed", "unknown"].includes(v.gender)
  && text(v.ageGroup, 32) ? { gender: v.gender, ageGroup: v.ageGroup } : null; }
function ordinal(v, max) { return Number.isSafeInteger(v) && v >= 1 && v <= max; }
export async function broadcastRegistryHash(value) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(value))))]
    .map((v) => v.toString(16).padStart(2, "0")).join("");
}

/// The same advertised event may appear in a sport and Live cohort. Equivalent
/// identity facts are one record; contradictory current facts remain a veto.
export function mergeBroadcastRecords(records, at = new Date(), coverage = []) {
  const now = Number(at), statuses = new Map(coverage.map((r) => [r.providerCode + ":" + r.scope, r.status]));
  const groups = new Map();
  for (const row of records) groups.set(row.id, [...(groups.get(row.id) ?? []), row]);
  const identity = (r) => ({ providerCode: r.providerCode, providerEventID: r.providerEventID, streamID: r.streamID,
    kind: r.kind, sport: r.sport, participants: pair(r.participants, r.sport), startBasis: r.startBasis,
    start: isCurrentCricketListing(r) ? undefined : r.start, end: r.end,
    competitionID: r.competitionID, squad: r.squad, format: r.format, matchOrdinal: r.matchOrdinal,
    day: r.day, channelID: r.channelID, stationMarket: r.stationMarket, verification: r.verification });
  return [...groups.values()].map((rows) => {
    const current = rows.filter((r) => Date.parse(r.expiresAt) > now), eligible = current.length ? current : rows;
    eligible.sort((a, b) => Number(["available", "partial"].includes(statuses.get(b.providerCode + ":" + b.scope)))
      - Number(["available", "partial"].includes(statuses.get(a.providerCode + ":" + a.scope)))
      || Date.parse(b.observedAt) - Date.parse(a.observedAt) || a.scope.localeCompare(b.scope));
    const first = eligible[0];
    if (eligible.some((r) => !same(identity(r), identity(first)))) {
      const conflicting = { ...first, verification: "conflicting", issues: [...new Set([...first.issues, "catalog-conflict"])].sort() };
      if (!isReviewedTVFootballAssignment(conflicting)) delete conflicting.stationMarket;
      return conflicting;
    }
    return first;
  });
}

export async function normalizeBroadcastCollection(providerCode, input, at = new Date()) {
  const now = Number(at), observed = stamp(input?.observedAt);
  if (!providers.has(providerCode) || !object(input) || input.providerCode !== providerCode || !Number.isFinite(now)
    || !Array.isArray(input.broadcasts) || input.broadcasts.length > BROADCAST_REGISTRY_LIMITS.collectionRecords
    || bytes(input) > BROADCAST_REGISTRY_LIMITS.collectionBytes || observed === null || observed > now + 5 * minute
    || observed < now - day || !Array.isArray(input.scopes) || input.scopes.length > BROADCAST_SCOPES.length) throw new Error("invalid-collection");
  const coverage = [], seenScopes = new Set();
  for (const scope of input.scopes) {
    if (!object(scope) || !scopes.has(scope.scope) || seenScopes.has(scope.scope)
      || !["available", "partial", "empty", "failed", "unsupported"].includes(scope.status)
      || typeof scope.complete !== "boolean" || scope.failure !== undefined && !reasons.has(scope.failure)
      || ["available", "empty"].includes(scope.status) && !scope.complete) throw new Error("invalid-collection");
    seenScopes.add(scope.scope);
    const scopeObserved = stamp(scope.observedAt ?? input.observedAt);
    if (scopeObserved === null || scopeObserved > observed + 5 * minute || scopeObserved < now - day) throw new Error("invalid-collection");
    coverage.push({ providerCode, scope: scope.scope, status: scope.status, complete: scope.complete,
      observedAt: iso(scopeObserved), ...(scope.failure ? { failure: scope.failure } : {}) });
  }
  const records = [];
  for (const row of input.broadcasts) {
    if (!object(row) || !seenScopes.has(row.scope) || !reference(row.providerEventID) || !reference(row.streamID ?? row.providerEventID)
      || row.resourceType !== "tv" || !kinds.has(row.kind) || !text(row.title)
      || ![...BROADCAST_SCOPES.filter((s) => !["live", "networks"].includes(s)), "unknown"].includes(row.sport)
      || !Array.isArray(row.participants) || row.participants.length > 2 || row.participants.some((p) => !text(p, 256))) throw new Error("invalid-collection");
    const reviewedAssignment = isReviewedTVFootballAssignment(row, providerCode);
    if (providerCode === "reviewedtv" && !reviewedAssignment && (row.scope !== "cricket" || row.sport !== "cricket" || row.kind !== "programme"
      || row.channelID !== "cricket-channel:willow" || row.streamID !== "reviewed-tv:willow-main"
      || !/^reviewed-tv:programme:[a-f0-9]{64}$/u.test(row.providerEventID))) throw new Error("invalid-collection");
    const receipt = stamp(row.observedAt ?? input.observedAt), expiry = stamp(row.expiresAt);
    const lifetime = row.kind === "programme" || reviewedAssignment ? BROADCAST_REGISTRY_LIMITS.programmeLifetime : BROADCAST_REGISTRY_LIMITS.sourceLifetime;
    if (receipt === null || expiry === null || receipt > now + 5 * minute || receipt > observed + 5 * minute
      || receipt < now - day || expiry <= receipt || expiry - receipt > lifetime) throw new Error("invalid-collection");
    const issues = new Set(Array.isArray(row.issues) ? row.issues.filter((r) => reasons.has(r)) : []);
    let verification = ["dated", "undated", "conflicting"].includes(row.verification) ? row.verification : "undated";
    const record = { id: "br:" + await broadcastRegistryHash([providerCode, row.providerEventID, row.streamID ?? row.providerEventID]),
      providerCode, providerEventID: row.providerEventID, streamID: row.streamID ?? row.providerEventID,
      resourceType: "tv", scope: row.scope, kind: row.kind, sport: row.sport, title: row.title,
      participants: row.participants, observedAt: iso(receipt), expiresAt: iso(expiry) };
    for (const key of ["start", "end"]) if (row[key] !== undefined) {
      const time = stamp(row[key]);
      if (time === null) { verification = "conflicting"; issues.add("time-conflict"); }
      else record[key] = iso(time);
    }
    if (record.end && record.start && record.end <= record.start) { verification = "conflicting"; issues.add("time-conflict"); }
    if (row.startBasis !== undefined) {
      if (!isCurrentCricketListing({ ...row, streamID: row.streamID ?? row.providerEventID }, providerCode)
        || row.verification !== "undated" || !record.start
        || Date.parse(record.start) > receipt + 5 * minute
        || receipt - Date.parse(record.start) > BROADCAST_REGISTRY_LIMITS.sourceLifetime) throw new Error("invalid-collection");
      record.startBasis = row.startBasis;
    }
    if (row.competitionID !== undefined) {
      if (!reference(row.competitionID, 128)) throw new Error("invalid-collection");
      record.competitionID = row.competitionID;
    }
    if (row.squad !== undefined) {
      const value = squad(row.squad);
      if (!value) { verification = "conflicting"; issues.add("squad-conflict"); }
      else record.squad = value;
    }
    if (row.format !== undefined) {
      if (!formats.has(row.format)) { verification = "conflicting"; issues.add("format-conflict"); }
      else record.format = row.format;
    }
    for (const [key, max, reason] of [["matchOrdinal", 99, "ordinal-conflict"], ["day", 6, "day-conflict"]]) {
      if (row[key] === undefined) continue;
      if (!ordinal(row[key], max) || key === "day" && row.format !== "Test"
        || key === "matchOrdinal" && !formats.has(row.format)) { verification = "conflicting"; issues.add(reason); }
      else record[key] = row[key];
    }
    if (row.channelID !== undefined) {
      if (!reviewedAssignment && (!channels.has(row.channelID) || row.sport !== "cricket")) { verification = "conflicting"; issues.add("identity-conflict"); }
      else record.channelID = row.channelID;
    }
    if (row.stationMarket !== undefined) {
      if (!reviewedAssignment && (row.stationMarket !== "US" || providerCode !== "communitysports" || row.kind !== "channel"
        || !["networks", "cricket", "live"].includes(row.scope) || row.sport !== "cricket" || row.channelID !== "cricket-channel:willow")) throw new Error("invalid-collection");
      record.stationMarket = row.stationMarket;
    }
    if (row.kind === "channel" && (!record.channelID || row.participants.length || record.start || record.end)) {
      verification = "conflicting"; issues.add("identity-conflict");
    }
    if (row.kind !== "channel" && !pair(record.participants, record.sport)) { verification = "conflicting"; issues.add("missing-participants"); }
    if (verification === "dated" && !record.start) { verification = "undated"; issues.add("missing-date"); }
    if (row.kind === "programme" && (!record.channelID || !record.start || !record.end)) {
      verification = "conflicting"; issues.add("missing-programme");
    }
    record.verification = verification;
    if (verification === "conflicting" && !reviewedAssignment) delete record.stationMarket;
    record.issues = [...issues].sort();
    records.push(record);
  }
  const broadcasts = mergeBroadcastRecords(records, at, coverage);
  for (const scope of coverage) {
    if (["failed", "unsupported", "empty"].includes(scope.status) && broadcasts.some((b) => b.scope === scope.scope)) throw new Error("invalid-collection");
  }
  return { providerCode, observedAt: iso(observed), complete: input.complete === true, scopes: coverage,
    broadcasts, ...(ordinal(input.cursor, 65535) || input.cursor === 0 ? { cursor: input.cursor } : {}) };
}

export function normalizeRegistryFixtures(rows, at = new Date()) {
  const now = Number(at);
  if (!Array.isArray(rows) || rows.length > 3000 || !Number.isFinite(now)) throw new Error("invalid-fixtures");
  const result = [], duplicates = new Set(), seen = new Set();
  for (const row of rows) { if (seen.has(row.fixtureID)) duplicates.add(row.fixtureID); seen.add(row.fixtureID); }
  for (const row of rows) {
    if (!object(row) || duplicates.has(row.fixtureID) || !reference(row.fixtureID, 512) || !pair(row.participants, row.sport)
      || !BROADCAST_SCOPES.includes(row.sport) || ["live", "networks"].includes(row.sport)
      || row.verified !== true || !["live", "scheduled"].includes(row.status)) continue;
    const start = stamp(row.start), observed = stamp(row.observedAt);
    if (start === null || observed === null || observed > now + 5 * minute || start > now + 14 * day
      || now - observed > (row.status === "scheduled" && start >= now ? day : 30 * minute)) continue;
    const fingerprint = { fixtureID: row.fixtureID, sport: row.sport, start: iso(start), participants: row.participants };
    if (row.competitionID !== undefined) { if (!reference(row.competitionID, 128)) continue; fingerprint.competitionID = row.competitionID; }
    if (row.squad !== undefined) { const value = squad(row.squad); if (!value) continue; fingerprint.squad = value; }
    if (row.format !== undefined) { if (!formats.has(row.format)) continue; fingerprint.format = row.format; }
    if (row.matchOrdinal !== undefined) { if (!["Test", "ODI", "T20"].includes(row.format) || !ordinal(row.matchOrdinal, 99)) continue; fingerprint.matchOrdinal = row.matchOrdinal; }
    if (row.day !== undefined) { if (row.format !== "Test" || !ordinal(row.day, 6)) continue; fingerprint.day = row.day; }
    if (row.end !== undefined) {
      const end = stamp(row.end);
      if (end === null || end <= start || row.format === "Test" && end - start > 6 * day) continue;
      fingerprint.end = iso(end);
    }
    if (row.status === "live" && fingerprint.end && Date.parse(fingerprint.end) <= now) continue;
    result.push({ ...fingerprint, status: row.status, observedAt: iso(observed), verified: true });
  }
  return result;
}

export function associateBroadcasts({ fixtures, broadcasts, providers: coverage = [], now = new Date() }) {
  const time = Number(now), admitted = normalizeRegistryFixtures(fixtures, now), links = [];
  if (!Array.isArray(broadcasts) || broadcasts.length > BROADCAST_REGISTRY_LIMITS.records) throw new Error("capacity-exceeded");
  const scopeState = new Map(coverage.map((r) => [r.providerCode + ":" + r.scope, r]));
  // The reviewed alias resolver scans a finite generated catalog. Normalize
  // each broadcast once, not once for every fixture in this bounded batch.
  const broadcastPairs = new Map(broadcasts.map((row) => [row, pair(row.participants, row.sport)]));
  // An early coverage start is not a rewritten official kickoff. Only one
  // accepted limited-overs fixture may own this exact pair/date/format.
  const earlyKey = (row) => JSON.stringify([pair(row.participants, row.sport), row.start?.slice(0, 10), row.format]);
  const earlyOwners = new Map();
  for (const fixture of admitted) if (fixture.sport === "cricket" && ["ODI", "T20"].includes(fixture.format)) {
    const key = earlyKey(fixture);
    earlyOwners.set(key, (earlyOwners.get(key) ?? 0) + 1);
  }
  // Unqualified current listings cannot distinguish two same-pair occurrences.
  // Include terminal/rejected siblings in ambiguity checks; they cannot lend
  // authority, but must not disappear and make a different match look unique.
  const uniqueCurrentOwner = (fixture) => fixtures.filter((f) => f?.sport === "cricket"
    && same(pair(f.participants, "cricket"), pair(fixture.participants, "cricket"))
    && stamp(f.start) !== null && Math.abs(Date.parse(f.start) - Date.parse(fixture.start)) < day).length === 1;
  const limitedOversRelation = (fixture, start) => {
    const limit = fixture.format === "ODI" ? 12 * 60 * minute : 6 * 60 * minute;
    const delta = start - Date.parse(fixture.start);
    return time - Date.parse(fixture.observedAt) <= 10 * minute && uniqueCurrentOwner(fixture)
      && (fixture.status === "live" && Date.parse(fixture.start) <= time && time - Date.parse(fixture.start) <= limit
        && delta >= -60 * minute && delta <= limit
        || fixture.status === "scheduled" && delta >= -60 * minute && delta <= 0
          && Date.parse(fixture.start) - time <= 60 * minute);
  };
  const assignmentKey = (row) => JSON.stringify([pair(row.participants, row.sport), row.start?.slice(0, 10), row.competitionID, row.squad]);
  const assignmentOwners = new Map();
  for (const fixture of admitted) if (fixture.sport === "football" && reviewedTVFootballCompetitions.has(fixture.competitionID) && fixture.squad
    || fixture.sport === "baseball" && fixture.competitionID === "mlb" || fixture.sport === "hockey" && fixture.competitionID === "nhl") {
    const key = assignmentKey(fixture); assignmentOwners.set(key, (assignmentOwners.get(key) ?? 0) + 1);
  }
  for (const fixture of admitted) {
    const expected = pair(fixture.participants, fixture.sport);
    const fingerprint = { ...fixture }; delete fingerprint.status; delete fingerprint.observedAt; delete fingerprint.verified;
    for (const broadcast of broadcasts) {
      if (broadcast.kind === "channel" || broadcast.sport !== fixture.sport || !same(broadcastPairs.get(broadcast), expected)) continue;
      const assignment = isReviewedTVScheduledAssignment(broadcast);
      if (broadcast.providerCode === "reviewedtv" && broadcast.kind !== "programme" && !assignment) continue;
      const currentListing = isCurrentCricketListing(broadcast);
      let state = "listed", reason, startRelation, method = currentListing ? "current-event" : assignment ? "channel-assignment" : broadcast.kind === "programme" ? "programme" : "exact";
      const fail = (next, value) => { if (state === "listed" || next === "conflicting") { state = next; reason = value; } };
      if (!providers.has(broadcast.providerCode) || stamp(broadcast.observedAt) === null || stamp(broadcast.expiresAt) === null) continue;
      if (broadcast.verification === "conflicting" || currentListing && broadcast.issues?.length) fail("conflicting", broadcast.issues?.[0] ?? "catalog-conflict");
      const scope = scopeState.get(broadcast.providerCode + ":" + broadcast.scope);
      // A failed catalog refresh cannot revoke an unexpired accepted listing.
      // It permits only a fresh same-ID descriptor check, never old media reuse.
      const retained = scope?.status === "failed" && stamp(scope.lastSuccessAt) !== null
        && scope.lastSuccessAt === scope.observedAt && stamp(scope.expiresAt) !== null
        && Date.parse(scope.expiresAt) > time && time - Date.parse(scope.observedAt) <= BROADCAST_REGISTRY_LIMITS.sourceLifetime;
      if (!["available", "partial"].includes(scope?.status) && !retained) fail("needsVerification", "source-unavailable");
      if (Date.parse(broadcast.expiresAt) <= time || Date.parse(broadcast.observedAt) > time + 5 * minute) fail("needsVerification", "stale-source");
      if ((!currentListing && broadcast.verification !== "dated") || !broadcast.start) fail("needsVerification", "missing-date");
      if (broadcast.competitionID && fixture.competitionID && broadcast.competitionID !== fixture.competitionID) fail("conflicting", "competition-conflict");
      if (broadcast.squad && fixture.squad && !same(broadcast.squad, fixture.squad)) fail("conflicting", "squad-conflict");
      if (fixture.sport === "cricket") {
        if ((!currentListing && !broadcast.format) || !fixture.format) fail("needsVerification", "format-conflict");
        else if (!currentListing && broadcast.format !== fixture.format) fail("conflicting", "format-conflict");
      }
      if (currentListing) {
        if (fixture.status !== "live" || !["ODI", "T20"].includes(fixture.format)
          || !limitedOversRelation(fixture, time)) fail("needsVerification", "unverified-fixture");
      } else if (broadcast.kind === "programme" && ["ODI", "T20"].includes(fixture.format)) {
        if (!limitedOversRelation(fixture, Date.parse(broadcast.start))) fail("conflicting", "time-conflict");
        if (!fixture.matchOrdinal || !broadcast.matchOrdinal) fail("needsVerification", "ordinal-conflict");
        else if (fixture.matchOrdinal !== broadcast.matchOrdinal) fail("conflicting", "ordinal-conflict");
      } else if (assignment) {
        const lead = Date.parse(fixture.start) - Date.parse(broadcast.start);
        if (!fixture.competitionID || fixture.competitionID !== broadcast.competitionID) fail("conflicting", "competition-conflict");
        if (!fixture.squad || !same(fixture.squad, broadcast.squad)) fail("conflicting", "squad-conflict");
        if (broadcast.start?.slice(0, 10) !== fixture.start.slice(0, 10) || !Number.isFinite(lead) || lead < 0 || lead > 60 * minute) fail("conflicting", "time-conflict");
        if (assignmentOwners.get(assignmentKey(fixture)) !== 1) fail("conflicting", "catalog-conflict");
        if (Date.parse(broadcast.expiresAt) - Date.parse(broadcast.observedAt) > BROADCAST_REGISTRY_LIMITS.programmeLifetime) fail("needsVerification", "stale-source");
        startRelation = "channel-coverage";
      } else if (fixture.format === "Test" && broadcast.format === "Test") {
        // Whole-match listings keep the ordinary exact original-start path.
        // A day-qualified occurrence instead needs current official Test-day
        // authority; optional score context must not disable the exact path.
        if (fixture.matchOrdinal && broadcast.matchOrdinal && fixture.matchOrdinal !== broadcast.matchOrdinal) fail("conflicting", "ordinal-conflict");
        if (broadcast.day !== undefined || broadcast.kind !== "event") {
          if (!fixture.matchOrdinal || !fixture.day || !fixture.end || !broadcast.matchOrdinal || !broadcast.day
            || time - Date.parse(fixture.observedAt) > 10 * minute) fail("needsVerification", "missing-test-authority");
          else if (fixture.day !== broadcast.day) fail("conflicting", "day-conflict");
          else if (!broadcast.start || broadcast.start < fixture.start || broadcast.start >= fixture.end
            || broadcast.end && broadcast.end > fixture.end) fail("conflicting", "time-conflict");
          else if (broadcast.kind !== "programme") method = "test-period";
        } else if (broadcast.start && Math.abs(Date.parse(broadcast.start) - Date.parse(fixture.start)) > 15 * minute) fail("conflicting", "time-conflict");
      } else if (fixture.format !== "Test" && broadcast.start && Math.abs(Date.parse(broadcast.start) - Date.parse(fixture.start)) > 15 * minute) {
        const lead = Date.parse(fixture.start) - Date.parse(broadcast.start);
        if (fixture.sport === "cricket" && broadcast.kind === "event" && ["ODI", "T20"].includes(fixture.format)
          && broadcast.format === fixture.format && lead > 15 * minute && lead <= 60 * minute
          && broadcast.start.slice(0, 10) === fixture.start.slice(0, 10) && earlyOwners.get(earlyKey(fixture)) === 1) {
          startRelation = "early-coverage";
        } else fail("conflicting", "time-conflict");
      }
      if (broadcast.kind === "programme" && (!channels.has(broadcast.channelID) || !broadcast.end
        || Date.parse(broadcast.end) <= time || Date.parse(broadcast.start) > time)) fail("needsVerification", "missing-programme");
      const fixtureLifetime = currentListing || broadcast.kind === "programme" || fixture.format === "Test" && broadcast.day !== undefined
        ? 10 * minute : fixture.status === "scheduled" && Date.parse(fixture.start) >= time ? day : 30 * minute;
      const expiry = Math.min(Date.parse(broadcast.expiresAt), Date.parse(fixture.observedAt) + fixtureLifetime,
        broadcast.kind === "programme" && broadcast.end ? Date.parse(broadcast.end) : Infinity);
      links.push({ fixtureID: fixture.fixtureID, broadcastID: broadcast.id, providerCode: broadcast.providerCode,
        state, matchMethod: method, fixtureFingerprint: fingerprint, expiresAt: iso(expiry), ...(startRelation && state === "listed" ? { startRelation } : {}), ...(reason ? { reason } : {}) });
      if (links.length > BROADCAST_REGISTRY_LIMITS.links) throw new Error("capacity-exceeded");
    }
  }
  const owners = new Map();
  for (const link of links) if (link.state === "listed") {
    const ids = owners.get(link.broadcastID) ?? new Set(); ids.add(link.fixtureID); owners.set(link.broadcastID, ids);
  }
  for (const link of links) if (link.state === "listed" && owners.get(link.broadcastID)?.size > 1) {
    link.state = "conflicting"; link.reason = "catalog-conflict";
  }
  return links;
}

export async function buildBroadcastSnapshot({ providers: coverage, broadcasts, links, now = new Date() }) {
  if (!Array.isArray(coverage) || coverage.length > BROADCAST_PROVIDER_CODES.length * BROADCAST_SCOPES.length
    || !Array.isArray(broadcasts) || broadcasts.length > BROADCAST_REGISTRY_LIMITS.records
    || !Array.isArray(links) || links.length > BROADCAST_REGISTRY_LIMITS.links) throw new Error("capacity-exceeded");
  const stable = { providers: [...coverage].sort((a, b) => (a.providerCode + a.scope).localeCompare(b.providerCode + b.scope)),
    broadcasts: [...broadcasts].sort((a, b) => a.id.localeCompare(b.id)),
    links: [...links].sort((a, b) => (a.fixtureID + a.broadcastID).localeCompare(b.fixtureID + b.broadcastID)) };
  const snapshot = { schemaVersion: 1, revision: await broadcastRegistryHash(stable), generatedAt: new Date(now).toISOString(), ...stable };
  if (bytes(snapshot) > BROADCAST_REGISTRY_LIMITS.snapshotBytes) throw new Error("capacity-exceeded");
  return snapshot;
}
