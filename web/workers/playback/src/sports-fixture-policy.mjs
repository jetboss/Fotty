// Fixture facts are independent from broadcast/source availability. This module
// admits bounded publisher records; it never manufactures streams or live state.
export const SPORTS_FIXTURE_SCHEMA = 1;
export const SPORTS_FIXTURE_MAX_ROWS = 3000;
const MINUTE = 60_000;
const DAY = 86_400_000;
const SPORTS = new Set(["football", "basketball", "baseball", "hockey", "american-football", "cricket", "tennis", "golf", "motorsport", "motor-sports", "fight", "rugby", "afl", "darts"]);
const STATUSES = new Set(["scheduled", "live", "finished", "postponed", "cancelled", "unknown"]);
const KINDS = new Set(["match", "session", "tournament", "card"]);
const GENDERS = new Set(["men", "women", "mixed", "unknown"]);
const AGES = new Set(["senior", "u19", "college", "unknown"]);
const TERMINAL = new Set(["finished", "cancelled"]);

function requireValue(value, message) { if (!value) throw new Error(message); }
function boundedString(value, max = 256) { return typeof value === "string" && value.trim().length > 0 && value.length <= max && !/[\u0000-\u001f]/.test(value); }
export function fixtureInstant(value) {
  requireValue(typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value), "Fixture time is not explicit UTC");
  const time = Date.parse(value);
  requireValue(Number.isFinite(time) && new Date(time).toISOString().slice(0, 19) === value.slice(0, 19), "Fixture time is invalid");
  return time;
}

export function fixtureWindow(now) {
  const midnight = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return { start: midnight - DAY, end: midnight + 8 * DAY };
}

export function descriptorCompetitions(descriptor) {
  const competitions = descriptor.competitions ?? (descriptor.competitionId
    ? [{ id: descriptor.competitionId, name: descriptor.competitionName, sport: descriptor.sport }]
    : (descriptor.competitionIds || []).map((id) => ({ id, name: descriptor.competitionName, sport: descriptor.sport })));
  requireValue(Array.isArray(competitions) && competitions.length > 0 && competitions.length <= 16, "Source competition scope missing");
  const ids = new Set();
  for (const competition of competitions) {
    requireValue(boundedString(competition.id, 80) && boundedString(competition.name) && SPORTS.has(competition.sport || descriptor.sport)
      && !ids.has(competition.id), "Source competition scope invalid");
    ids.add(competition.id);
  }
  return competitions;
}

export function validateSportsFixture(fixture, now, descriptor) {
  requireValue(fixture && typeof fixture === "object", "Fixture record missing");
  const competitions = descriptorCompetitions(descriptor);
  const competition = competitions.find((row) => row.id === fixture.competitionId);
  requireValue(competition && fixture.competitionName === competition.name && fixture.sport === (competition.sport || descriptor.sport), "Fixture competition mismatch");
  requireValue(boundedString(fixture.id, 180) && fixture.id.startsWith(`sports-fixture:${fixture.competitionId}:`)
    && boundedString(fixture.title) && STATUSES.has(fixture.status) && KINDS.has(fixture.eventKind), "Fixture identity/status invalid");
  const start = fixtureInstant(fixture.start);
  const window = fixtureWindow(now);
  const pastBoundary = fixture.status === "live" && fixture.eventKind !== "match" ? window.start - 6 * DAY : window.start;
  requireValue(start >= pastBoundary && start < window.end, "Fixture outside bounded window");
  requireValue(fixture.status !== "live" || start <= now.getTime() + 30 * MINUTE, "Future fixture cannot be live");
  requireValue(fixture.status !== "finished" || start <= now.getTime() + 5 * MINUTE, "Future fixture cannot be finished");
  requireValue(fixture.squad && GENDERS.has(fixture.squad.gender) && AGES.has(fixture.squad.ageGroup), "Fixture squad identity missing");
  requireValue(Array.isArray(fixture.participants) && fixture.participants.length <= 64, "Fixture participants invalid");
  if (fixture.eventKind === "match") requireValue(fixture.participants.length === 2, "Match requires two participants");
  const participantIDs = new Set();
  for (const participant of fixture.participants) {
    requireValue(boundedString(participant.id, 100) && boundedString(participant.name) && !participantIDs.has(participant.id)
      && !/^(?:tbd|tbc|unknown|winner\b|loser\b|team\s*\d+$)/i.test(participant.name.trim()), "Unresolved/duplicate participant");
    participantIDs.add(participant.id);
  }
  requireValue(fixture.source && boundedString(fixture.source.name, 100), "Fixture provenance missing");
  const url = new URL(fixture.source.url);
  requireValue(url.protocol === "https:" && !url.username && !url.password && !url.hash && fixture.source.url.length <= 1500, "Fixture source link invalid");
  const observedAt = fixtureInstant(fixture.source.observedAt);
  requireValue(observedAt <= now.getTime() + 5 * MINUTE && observedAt >= now.getTime() - 10 * MINUTE, "Collector receipt invalid");
  if (fixture.source.updatedAt !== undefined) {
    const updatedAt = fixtureInstant(fixture.source.updatedAt);
    requireValue(updatedAt <= now.getTime() + 5 * MINUTE, "Publisher timestamp is in future");
    if (fixture.status === "live") requireValue(updatedAt >= now.getTime() - 30 * MINUTE, "Publisher live evidence stale");
  }
  if (fixture.source.correctionConfirmedAt !== undefined) requireValue(fixtureInstant(fixture.source.correctionConfirmedAt) <= observedAt,
    "Correction confirmation is newer than its source receipt");
  return fixture;
}

function identity(fixture) {
  return JSON.stringify([fixture.sport, fixture.competitionId, fixture.eventKind, fixture.squad,
    fixture.participants.map((row) => [row.id, row.role || null]).sort((a, b) => a[0].localeCompare(b[0]))]);
}

// A real correction needs a repeat current-source observation. On the first
// contradictory observation retain the accepted receipt and alert the monitor.
export function admitSportsCollection(collection, previous, descriptor, now, priorConflict) {
  requireValue(collection && Array.isArray(collection.fixtures) && collection.fixtures.length <= 500, "Source fixture count invalid");
  const observedAt = fixtureInstant(collection.observedAt);
  requireValue(observedAt <= now.getTime() + 5 * MINUTE && observedAt >= now.getTime() - 10 * MINUTE, "Source receipt invalid");
  requireValue(Number.isInteger(collection.pendingFixtureCount) && collection.pendingFixtureCount >= 0 && collection.pendingFixtureCount <= 10000,
    "Pending count invalid");
  if (collection.pendingByCompetition !== undefined) {
    const pending = collection.pendingByCompetition;
    const competitions = descriptorCompetitions(descriptor);
    requireValue(pending !== null && typeof pending === "object" && !Array.isArray(pending)
      && Object.keys(pending).length === competitions.length
      && competitions.every(({ id }) => Object.hasOwn(pending, id)
        && Number.isInteger(pending[id]) && pending[id] >= 0 && pending[id] <= 10000), "Pending competition scope invalid");
    requireValue(competitions.reduce((total, { id }) => total + pending[id], 0) === collection.pendingFixtureCount,
      "Pending competition count mismatch");
  }
  const ids = new Set();
  const fixtures = collection.fixtures.map((fixture) => {
    validateSportsFixture(fixture, now, descriptor);
    requireValue(fixture.source.observedAt === collection.observedAt && !ids.has(fixture.id), "Source duplicate/receipt mismatch");
    ids.add(fixture.id);
    return fixture;
  }).sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
  const byID = new Map(fixtures.map((fixture) => [fixture.id, fixture]));
  let needsConfirmation = false;
  for (const old of previous?.fixtures || []) {
    const current = byID.get(old.id);
    const oldStart = Date.parse(old.start);
    const previousWindow = fixtureWindow(now);
    const oldPastBoundary = old.status === "live" && old.eventKind !== "match" ? previousWindow.start - 6 * DAY : previousWindow.start;
    const inWindow = oldStart >= oldPastBoundary && oldStart < previousWindow.end;
    if (!current && inWindow && !TERMINAL.has(old.status)) throw new Error("Accepted fixture disappeared without cancellation evidence");
    if (!current) continue;
    requireValue(!(TERMINAL.has(old.status) && !TERMINAL.has(current.status)), "Terminal fixture status regressed");
    if (identity(old) !== identity(current) || old.start !== current.start || old.status === "live" && current.status === "scheduled") needsConfirmation = true;
  }
  const correction = JSON.stringify(fixtures.map((fixture) => ({ id: fixture.id, identity: identity(fixture), start: fixture.start,
    liveRollback: (previous?.fixtures || []).some((old) => old.id === fixture.id && old.status === "live" && fixture.status === "scheduled") })));
  if (needsConfirmation && !(priorConflict?.content === correction && observedAt > Date.parse(priorConflict.observedAt) + 4 * MINUTE)) {
    return { conflict: { content: correction, observedAt: collection.observedAt } };
  }
  const oldByID = new Map((previous?.fixtures || []).map((fixture) => [fixture.id, fixture]));
  const admitted = fixtures.map((fixture) => {
    const old = oldByID.get(fixture.id);
    const changed = old && (identity(old) !== identity(fixture) || old.start !== fixture.start || old.status === "live" && fixture.status === "scheduled");
    const confirmation = changed ? collection.observedAt : old?.source.correctionConfirmedAt;
    return confirmation ? { ...fixture, source: { ...fixture.source, correctionConfirmedAt: confirmation } } : fixture;
  });
  return { accepted: { ...collection, fixtures: admitted } };
}

export function nextSportsRefresh(fixtures, now) {
  if (fixtures.some((fixture) => fixture.status === "live" || (fixture.status === "scheduled"
    && Date.parse(fixture.start) >= now.getTime() - 15 * MINUTE && Date.parse(fixture.start) <= now.getTime() + 30 * MINUTE))) return 5 * MINUTE;
  if (fixtures.some((fixture) => fixture.status === "scheduled" && Date.parse(fixture.start) > now.getTime()
    && Date.parse(fixture.start) <= now.getTime() + DAY)) return 15 * MINUTE;
  return 4 * 60 * MINUTE;
}

export async function sportsRevision(fixtures, coverage = []) {
  const content = fixtures.map(({ source, ...fixture }) => ({ ...fixture, source: { name: source.name, url: source.url } }));
  // Unsupported/failed coverage changes must propagate even if fixture content
  // does not. Successful check times alone must not churn the app's catalog.
  const states = coverage.map(({ competitionId, status, pendingFixtureCount }) => ({ competitionId, status, pendingFixtureCount }));
  const bytes = new TextEncoder().encode(JSON.stringify([content, states]));
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
