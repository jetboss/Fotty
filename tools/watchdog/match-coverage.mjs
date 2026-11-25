// Pure catalog-binding evidence from already fetched, admitted metadata. This
// neither requests streams nor certifies native admission or decoded playback.
import { canonicalFootballClubId } from "../../web/src/lib/football-competition-catalog.generated.ts";
import { selectCSCatalogMatch, selectCSDeliveryFixture } from "./delivery-contract.mjs";
import { supportsCSCricketFixture, selectCSCricketCatalogMatch } from "./cricket-catalog-binding.mjs";
import { EXPECTED_VERSIONS } from "./manifest.mjs";

export const MATCH_COVERAGE_KEY = "watchdog-match-coverage-v1";
export const MATCH_COVERAGE_SOURCE = "match-coverage";
export const MATCH_COVERAGE_SCOPES = Object.freeze(["premier-league", "champions-league", "cpl", "west-indies", "icc"]);
const FRESH = 30 * 60_000, FUTURE = 5 * 60_000, MAX_ROWS = 3000, MAX_BYTES = 8192;
const outcomes = new Set(["inactive", "unknown", "failure", "success"]);
const id = (v) => typeof v === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$/.test(v);
const label = (v) => typeof v === "string" && v.length > 0 && v.length <= 512 && !/[\u0000-\u001f\u007f]/u.test(v);
const normal = (v) => typeof v === "string" ? v.normalize("NFD").replace(/\p{Diacritic}/gu, "")
  .toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ") : "";
function instant(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(value)) return null;
  const time = Date.parse(value), date = new Date(value.slice(0, 10) + "T00:00:00Z");
  return Number.isFinite(time) && Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value.slice(0, 10)
    && Number(value.slice(11, 13)) < 24 && Number(value.slice(14, 16)) < 60 && Number(value.slice(17, 19)) < 60 ? time : null;
}
const fresh = (v, now) => { const t = instant(v); return t !== null && now - t <= FRESH && t - now <= FUTURE; };
function snapshotReady(snapshot, scope, now) {
  if (snapshot?.schemaVersion !== 1 || snapshot.complete !== true || !["verified", "partial"].includes(snapshot.sourceStatus)
    || !fresh(snapshot.checkedAt, now) || !Array.isArray(snapshot.fixtures) || snapshot.fixtures.length > MAX_ROWS
    || !Array.isArray(snapshot.coverage) || snapshot.coverage.length > 100) return false;
  return snapshot.coverage.filter((row) => row?.competitionId === scope).length === 1;
}
function teamKey(name, football) {
  const value = normal(name);
  if (!value || /\b(?:tbd|tbc|unknown)\b/.test(value)
    || football && /\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2})\b/.test(value)) return null;
  return football ? canonicalFootballClubId(value) || value : value;
}
function pair(names, football) {
  if (!Array.isArray(names) || names.length !== 2 || !names.every(label)) return null;
  const keys = names.map((name) => teamKey(name, football));
  return keys.every(Boolean) && keys[0] !== keys[1] ? keys.sort().join("::") : null;
}
function titlePair(title, football) {
  if (!label(title) || /[|•·()\[\]:\n\r\t<>]/.test(title) || / [-–—] /.test(title)) return null;
  const pieces = title.split(/\s+(?:vs\.?|v\.?|versus|@)\s+/i);
  return pair(pieces, football);
}
function squadQualifiers(raw) {
  // Mirror ReviewedSportsFixtureMatcher's finite qualifier vocabulary and
  // subset rule. Competition copy cannot silently reclassify unsuffixed teams.
  const text = normal(typeof raw === "string" ? raw.normalize("NFKC") : raw);
  return new Set([...text.matchAll(/\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b/g)]
    .map(([value]) => {
      const token = value.replace(/ /g, "");
      return ["women", "womens", "ladies", "w"].includes(token) ? "women"
        : ["reserve", "reserves"].includes(token) ? "reserves" : token.replace("under", "u");
    }));
}
function cricketEligible(row, snapshot, scope, now) {
  if (!id(row?.id) || !row.id.startsWith(scope === "cpl" ? "cpl:" : "icc:")
    || row.competitionId !== scope || row.status !== "live" || !["T20", "ODI", "T10", "Test"].includes(row.format)
    || !id(row.home?.id) || !id(row.away?.id) || row.home.id === row.away.id
    || !pair([row.home.name, row.away.name], false) || !label(row.competitionName) || !fresh(row.source?.observedAt, now)
    || instant(row.source.observedAt) > instant(snapshot.checkedAt)) return false;
  const participantSquads = new Set([...squadQualifiers(row.home.name), ...squadQualifiers(row.away.name)]);
  if ([...squadQualifiers(row.competitionName)].some((token) => !participantSquads.has(token))) return false;
  const covered = snapshot.coverage.find((item) => item.competitionId === scope);
  if (Object.hasOwn(row.source, "verification") ? row.source.verification !== "verified" : covered.status !== "covered") return false;
  const start = instant(row.start);
  if (start === null || start > now + FUTURE || now - start > (row.format === "Test" ? 24 : 8) * 3600_000) return false;
  // Both source matchers inherit these accepted live/fresh/squad gates. Breaks
  // and later Test days cannot become active play from a matching catalog row.
  const phase = row.context?.phase;
  if (phase != null && phase !== "in-play") return false;
  if (row.format === "Test" && !(phase === "in-play" && (row.context.day == null || row.context.day === 1))) return false;
  return supportsCSCricketFixture(row) || supportsASCricketFixture(row);
}
function supportsASCricketFixture(row) {
  // AS retains its narrower native contract; a CS ODI/T10 capability never
  // authorizes borrowing a format from an AS team pair or opaque identifier.
  return row.format === "T20" && /\bT20I\b/i.test(row.competitionName)
    || row.format === "Test" && row.context?.phase === "in-play" && (row.context.day == null || row.context.day === 1);
}
function eligible(row, snapshot, scope, now, duplicates) {
  if (duplicates.has(row?.id)) return false;
  if (["premier-league", "champions-league"].includes(scope)) {
    return selectCSDeliveryFixture({ ...snapshot, fixtures: [row] }, now)?.id === row.id;
  }
  return cricketEligible(row, snapshot, scope, now);
}
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function asUTC(raw) {
  const m = /^(0?[1-9]|[12][0-9]|3[01]) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([0-9]{4}) · ([01][0-9]|2[0-3]):([0-5][0-9]) UTC$/.exec(raw || "");
  if (!m) return null;
  const value = Date.UTC(Number(m[3]), MONTHS.indexOf(m[2]), Number(m[1]), Number(m[4]), Number(m[5]));
  const date = new Date(value);
  return date.getUTCFullYear() === Number(m[3]) && date.getUTCMonth() === MONTHS.indexOf(m[2]) && date.getUTCDate() === Number(m[1]) ? value : null;
}
function qualifier(raw, requireTestDay = false) {
  const m = /^([1-9][0-9]?)(st|nd|rd|th) (T20I|Test)(?: Day ([1-5]))?$/.exec(raw || "");
  if (!m) return null;
  const number = Number(m[1]), suffix = number % 100 >= 11 && number % 100 <= 13 ? "th"
    : ({ 1: "st", 2: "nd", 3: "rd" }[number % 10] || "th");
  return m[2] === suffix && (m[3] !== "Test" || m[4] === "1" || m[4] == null && !requireTestDay)
    && (m[3] === "Test" || m[4] == null)
    ? { format: m[3] === "Test" ? "Test" : "T20", ordinal: number, day: m[4] ? Number(m[4]) : null } : null;
}
function asIdentity(entry, football) {
  if (!entry || typeof entry.id !== "string" || entry.id.length > 240 || entry.type !== "tv" || !label(entry.name)
    || typeof entry.description !== "string" || entry.description.length > 1024
    || ["released", "releaseInfo", "date", "startTime", "kickoff", "videos", "behaviorHints"].some((key) => Object.hasOwn(entry, key))
    || !new RegExp(`^plaviohdtv-sfly-streamed:${football ? "football" : "cricket"}-[a-z0-9][a-z0-9-]*$`).test(entry.id)
    || JSON.stringify(entry.genres) !== JSON.stringify([football ? "Sports" : "Cricket"])) return null;
  const lines = entry.description.split("\n"), start = asUTC(lines[1]);
  if (lines.length !== 2 || start === null) return null;
  // Native's football descriptor uses an exact unpadded day round trip;
  // cricket's separately reviewed date contract allows either spelling.
  if (football) return lines[0] === entry.name && !lines[1].startsWith("0")
    ? { pair: titlePair(entry.name, true), start, format: null, ordinal: null } : null;
  if (!label(lines[0]) || !entry.name.startsWith(lines[0] + " - ")) return null;
  const q = qualifier(entry.name.slice(lines[0].length + 3), true);
  return q ? { pair: titlePair(lines[0], false), start, ...q } : null;
}
function asMatch(fixture, packet, football) {
  const rows = packet.catalog.metas, target = pair(football ? fixture.participants.map((p) => p.name) : [fixture.home.name, fixture.away.name], football);
  const start = instant(fixture.start), parsed = rows.map((entry) => ({ entry, identity: asIdentity(entry, football) }));
  const q = football ? [] : [...String(fixture.competitionName || "").matchAll(/\b([0-9]+(?:st|nd|rd|th) (?:T20I?|ODI|Test)(?: Day [0-9]+)?)\b/gi)];
  const officialQ = q.length === 1 ? qualifier(q[0][1]) : null;
  if (q.length > 1 || q.length === 1 && (!officialQ || officialQ.format !== fixture.format)) return "unverifiable";
  const matched = parsed.filter(({ identity: i }) => i?.pair === target && (football ? Math.abs(i.start - start) <= 15 * 60_000
    : i.start === start && i.format === fixture.format && (officialQ == null || i.ordinal === officialQ.ordinal)));
  for (const found of matched) if (parsed.some((row) => row.entry?.id === found.entry.id
    && JSON.stringify(row.identity) !== JSON.stringify(found.identity))) return "conflicting";
  if (new Set(matched.map((row) => row.entry.id)).size > 1) return "conflicting";
  // The watchdog has no budget for AS's optional meta join. A clock-only or
  // changed-family row is unverifiable here, not proof the provider lacks it.
  return matched.length ? "matched" : rows.length === 0 ? "missing" : "unverifiable";
}
function currentPacket(catalogs, source, scope, now) {
  const rows = catalogs.filter((row) => row?.source === source && row.scope === scope);
  return rows.length === 1 && Number.isSafeInteger(rows[0].checkedAt) && now - rows[0].checkedAt >= -FUTURE
    && now - rows[0].checkedAt <= FRESH && Array.isArray(rows[0].catalog?.metas) && rows[0].catalog.metas.length <= 600 ? rows[0] : null;
}
function matchState(fixture, scope, catalogs, now) {
  const football = ["premier-league", "champions-league"].includes(scope);
  const cs = currentPacket(catalogs, "cs", "mixed", now);
  const as = currentPacket(catalogs, "as", football ? "football" : "cricket", now);
  const csResult = cs ? (football ? selectCSCatalogMatch(fixture, cs.catalog) : selectCSCricketCatalogMatch(fixture, cs.catalog)).outcome : "unverifiable";
  const asResult = as && (football || supportsASCricketFixture(fixture)) ? asMatch(fixture, as, football) : "unverifiable";
  if ([csResult, asResult].includes("matched")) return "matched";
  if ([csResult, asResult].includes("conflicting")) return "conflicting";
  // Missing in CS's mixed catalog is only an observed gap: native has other
  // reviewed catalog/search/meta routes. Do not call it no-stream availability.
  return csResult === "missing" || asResult === "missing" ? "missing" : "unverifiable";
}

export function matchCoverageReceipt({ sportsSnapshot, cricketSnapshot, catalogs = [], now = Date.now() } = {}) {
  if (!Number.isSafeInteger(now) || now < 0 || !Array.isArray(catalogs) || catalogs.length > 3) throw new Error("Invalid coverage input");
  const competitions = MATCH_COVERAGE_SCOPES.map((scope) => {
    const football = ["premier-league", "champions-league"].includes(scope), snapshot = football ? sportsSnapshot : cricketSnapshot;
    const counts = { scope, monitorScope: football ? "football-catalog-bindings" : "cs-as-cricket-catalog-bindings",
      liveFixtureCount: 0, matchedFixtureCount: 0, missingFixtureCount: 0,
      unverifiableFixtureCount: 0, conflictingFixtureCount: 0, unassessedLiveFixtureCount: 0, monitorLimitedFixtureCount: 0, outcome: "unknown" };
    if (!snapshotReady(snapshot, scope, now)) return counts;
    const cohort = snapshot.coverage.find((row) => row.competitionId === scope);
    if (["offseason", "unsupported"].includes(cohort.status)) {
      counts.unassessedLiveFixtureCount = snapshot.fixtures.filter((row) => row?.competitionId === scope && row.status === "live").length;
      if (!football) counts.monitorLimitedFixtureCount = counts.unassessedLiveFixtureCount;
      counts.outcome = counts.unassessedLiveFixtureCount ? "unknown" : "inactive";
      return counts;
    }
    const seen = new Map();
    for (const row of snapshot.fixtures) seen.set(row?.id, (seen.get(row?.id) || 0) + 1);
    const duplicates = new Set([...seen].filter(([, n]) => n > 1).map(([key]) => key));
    for (const fixture of snapshot.fixtures.filter((row) => row?.competitionId === scope && row.status === "live")) {
      if (!eligible(fixture, snapshot, scope, now, duplicates)) {
        counts.unassessedLiveFixtureCount++;
        if (!football) counts.monitorLimitedFixtureCount++;
        continue;
      }
      counts.liveFixtureCount++;
      const state = matchState(fixture, scope, catalogs, now);
      counts[state + "FixtureCount"]++;
      if (!football && state !== "matched") counts.monitorLimitedFixtureCount++;
    }
    counts.outcome = counts.liveFixtureCount ? counts.matchedFixtureCount === counts.liveFixtureCount && !counts.unassessedLiveFixtureCount
      ? "success" : football ? "failure" : "unknown" : counts.unassessedLiveFixtureCount || cohort.status !== "covered" ? "unknown" : "inactive";
    return counts;
  });
  const result = { schema: 1, evidence: "catalog-only", checkedAt: now, competitions };
  validateMatchCoverageReceipt(result);
  return result;
}
export function validateMatchCoverageReceipt(value) {
  const top = ["schema", "evidence", "checkedAt", "competitions"];
  if (!value || Object.keys(value).some((key) => !top.includes(key)) || value.schema !== 1 || value.evidence !== "catalog-only"
    || !Number.isSafeInteger(value.checkedAt) || value.checkedAt < 0 || !Array.isArray(value.competitions)
    || value.competitions.length !== MATCH_COVERAGE_SCOPES.length
    || new TextEncoder().encode(JSON.stringify(value)).length > MAX_BYTES) throw new Error("Invalid match coverage receipt");
  for (const [index, row] of value.competitions.entries()) {
    const keys = ["scope", "monitorScope", "liveFixtureCount", "matchedFixtureCount", "missingFixtureCount", "unverifiableFixtureCount",
      "conflictingFixtureCount", "unassessedLiveFixtureCount", "monitorLimitedFixtureCount", "outcome"];
    if (!row || Object.keys(row).length !== keys.length || Object.keys(row).some((key) => !keys.includes(key))
      || row.scope !== MATCH_COVERAGE_SCOPES[index] || !outcomes.has(row.outcome)
      || row.monitorScope !== (index < 2 ? "football-catalog-bindings" : "cs-as-cricket-catalog-bindings")
      || keys.filter((key) => key.endsWith("Count")).some((key) => !Number.isSafeInteger(row[key]) || row[key] < 0 || row[key] > MAX_ROWS)
      || row.matchedFixtureCount + row.missingFixtureCount + row.unverifiableFixtureCount + row.conflictingFixtureCount !== row.liveFixtureCount
      || row.liveFixtureCount + row.unassessedLiveFixtureCount > MAX_ROWS
      || row.monitorLimitedFixtureCount !== (index < 2 ? 0 : row.unassessedLiveFixtureCount + row.liveFixtureCount - row.matchedFixtureCount)
      || row.outcome === "success" && (!row.liveFixtureCount || row.matchedFixtureCount !== row.liveFixtureCount || row.unassessedLiveFixtureCount)
      || row.outcome === "inactive" && (row.liveFixtureCount || row.unassessedLiveFixtureCount)
      || row.outcome === "failure" && (index >= 2 || !row.liveFixtureCount
        || row.matchedFixtureCount === row.liveFixtureCount && !row.unassessedLiveFixtureCount)) {
      throw new Error("Invalid match coverage cohort");
    }
  }
  return value;
}
export function matchCoverageObservations(value, environment = "production") {
  validateMatchCoverageReceipt(value);
  return value.competitions.map((row) => ({ environment, source: MATCH_COVERAGE_SOURCE, stage: "catalog-match",
    failureClass: "unverified-current-coverage", outcome: row.outcome, observedAt: value.checkedAt,
    versions: { ...EXPECTED_VERSIONS }, facts: { scope: row.scope, dimension: "catalog-binding" } }));
}
