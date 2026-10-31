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
  // Verification is admission output, never a collector-supplied authority.
  requireValue(fixture.source.verification === undefined, "Collector verification marker invalid");
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

function snapshotNameKey(value) {
  return value.normalize("NFKD").toLowerCase().replace(/\p{M}/gu, "").replace(/ß/g, "ss")
    .replace(/&/g, " and ").split(/[^\p{L}\p{N}]+/u).filter(Boolean).join(" ");
}

// Match native snapshot duplicate admission, not opaque publisher IDs. Keep
// participant order and omit a match's display title just as the consumer does.
export function sportsSnapshotIdentity(fixture) {
  return `${fixture.sport}|${fixture.competitionId}|${fixture.eventKind}|${fixtureInstant(fixture.start) / 1000}|`
    + `${fixture.participants.map((row) => row.id).join(",")}|${fixture.squad.gender}|${fixture.squad.ageGroup}|`
    + (fixture.eventKind === "match" ? "" : snapshotNameKey(fixture.title));
}

function footballPublisherID(fixture, descriptor) {
  // Other providers may reuse numeric IDs between leagues. Only this reviewed
  // adapter promises globally unique match IDs across its competition scope.
  if (descriptor.id !== "football-data" || descriptor.adapter !== "football-data") return null;
  const value = fixture.id.slice(`sports-fixture:${fixture.competitionId}:`.length);
  return /^[1-9][0-9]*$/.test(value) ? value : null;
}

function movedPublisherRows(candidate, previous, descriptor) {
  const oldByPublisherID = new Map();
  for (const old of previous?.fixtures || []) {
    const key = footballPublisherID(old, descriptor);
    if (key) oldByPublisherID.set(key, [...(oldByPublisherID.get(key) || []), old]);
  }
  return candidate.fixtures.flatMap((fixture) => {
    const key = footballPublisherID(fixture, descriptor);
    const prior = key ? oldByPublisherID.get(key) || [] : [];
    return prior.some((old) => old.competitionId !== fixture.competitionId) ? [{ fixture, prior }] : [];
  });
}

function resurrectedTerminalRows(candidate, previous) {
  const terminals = new Map();
  for (const old of previous?.fixtures || []) {
    if (!TERMINAL.has(old.status)) continue;
    const key = sportsSnapshotIdentity(old);
    terminals.set(key, [...(terminals.get(key) || []), old]);
  }
  return candidate.fixtures.flatMap((fixture) => {
    if (TERMINAL.has(fixture.status)) return [];
    const prior = (terminals.get(sportsSnapshotIdentity(fixture)) || []).filter((old) => old.id !== fixture.id);
    return prior.length ? [{ fixture, prior }] : [];
  });
}

// A real correction needs a repeat current-source observation. On the first
// contradictory observation retain the accepted receipt and alert the monitor.
function validatedCollection(collection, previous, descriptor, now) {
  requireValue(collection && Array.isArray(collection.fixtures) && collection.fixtures.length <= 500, "Source fixture count invalid");
  const observedAt = fixtureInstant(collection.observedAt);
  requireValue(observedAt <= now.getTime() + 5 * MINUTE && observedAt >= now.getTime() - 10 * MINUTE, "Source receipt invalid");
  requireValue(Number.isInteger(collection.pendingFixtureCount) && collection.pendingFixtureCount >= 0 && collection.pendingFixtureCount <= 10000,
    "Pending count invalid");
  requireValue(descriptorCompetitions(descriptor).length === 1 || collection.pendingByCompetition !== undefined,
    "Pending competition scope invalid");
  if (collection.pendingStartsByCompetition !== undefined) {
    const pending = collection.pendingStartsByCompetition;
    const competitions = descriptorCompetitions(descriptor);
    const window = fixtureWindow(now);
    requireValue(pending !== null && typeof pending === "object" && !Array.isArray(pending)
      && collection.pendingByCompetition !== undefined && Object.keys(pending).length === competitions.length
      && competitions.every(({ id }) => Object.hasOwn(pending, id) && Array.isArray(pending[id])
        && pending[id].length <= collection.pendingByCompetition[id]
        && pending[id].every((start) => { const time = fixtureInstant(start); return time >= window.start && time < window.end; })),
    "Pending timing scope invalid");
  }
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
  const ids = new Set(), identities = new Set(), publisherIDs = new Set();
  const fixtures = collection.fixtures.map((fixture) => {
    validateSportsFixture(fixture, now, descriptor);
    requireValue(fixture.source.observedAt === collection.observedAt && !ids.has(fixture.id), "Source duplicate/receipt mismatch");
    ids.add(fixture.id);
    const semantic = sportsSnapshotIdentity(fixture), publisherID = footballPublisherID(fixture, descriptor);
    requireValue(!identities.has(semantic), "Source duplicate semantic fixture identity");
    requireValue(!publisherID || !publisherIDs.has(publisherID), "Source duplicate publisher fixture identity");
    identities.add(semantic);
    if (publisherID) publisherIDs.add(publisherID);
    return fixture;
  }).sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
  const priorReceipts = [previous?.observedAt, ...(previous?.fixtures || []).map((fixture) => fixture.source.observedAt)]
    .filter(Boolean).map(fixtureInstant);
  const watermark = Math.max(-Infinity, ...priorReceipts);
  requireValue(observedAt >= watermark, "Source receipt regressed");
  return { ...collection, fixtures };
}

function activeInWindow(fixture, now) {
  const window = fixtureWindow(now);
  const boundary = fixture.status === "live" && fixture.eventKind !== "match" ? window.start - 6 * DAY : window.start;
  return Date.parse(fixture.start) >= boundary && Date.parse(fixture.start) < window.end && !TERMINAL.has(fixture.status);
}

function correctionFacts(fixture, old) {
  return JSON.stringify({ id: fixture.id, identity: identity(fixture), start: fixture.start,
    liveRollback: old?.status === "live" && fixture.status === "scheduled" });
}

function priorCorrections(priorConflict) {
  if (priorConflict?.fixtures && typeof priorConflict.fixtures === "object") return priorConflict.fixtures;
  // Preserve an in-flight legacy confirmation when upgrading the durable state.
  try {
    const rows = JSON.parse(priorConflict?.content);
    if (Array.isArray(rows)) return Object.fromEntries(rows.map((row) => [row.id,
      { content: JSON.stringify(row), observedAt: priorConflict.observedAt }]));
  } catch { /* No reviewed prior correction evidence. */ }
  return {};
}

function admitRecord(fixture, old, observedAt, priorCorrection) {
  if (!old) return { fixture };
  requireValue(!(TERMINAL.has(old.status) && !TERMINAL.has(fixture.status)), "Terminal fixture status regressed");
  const changed = identity(old) !== identity(fixture) || old.start !== fixture.start
    || old.status === "live" && fixture.status === "scheduled";
  if (changed) {
    const content = correctionFacts(fixture, old);
    if (!(priorCorrection?.content === content && Date.parse(observedAt) > Date.parse(priorCorrection.observedAt) + 4 * MINUTE)) {
      return { conflict: { content, observedAt } };
    }
  }
  const confirmation = changed ? observedAt : old.source.correctionConfirmedAt;
  return { fixture: confirmation ? { ...fixture, source: { ...fixture.source, correctionConfirmedAt: confirmation } } : fixture };
}

export function admitSportsCollection(collection, previous, descriptor, now, priorConflict) {
  const candidate = validatedCollection(collection, previous, descriptor, now);
  requireValue(!movedPublisherRows(candidate, previous, descriptor).length, "Publisher fixture competition changed");
  requireValue(!resurrectedTerminalRows(candidate, previous).length, "Terminal fixture status regressed");
  const byID = new Map(candidate.fixtures.map((fixture) => [fixture.id, fixture]));
  for (const old of previous?.fixtures || []) {
    const current = byID.get(old.id);
    if (!current && activeInWindow(old, now)) throw new Error("Accepted fixture disappeared without cancellation evidence");
  }
  const oldByID = new Map((previous?.fixtures || []).map((fixture) => [fixture.id, fixture]));
  const prior = priorCorrections(priorConflict), conflicts = {}, fixtures = [];
  for (const fixture of candidate.fixtures) {
    const result = admitRecord(fixture, oldByID.get(fixture.id), candidate.observedAt, prior[fixture.id]);
    if (result.conflict) conflicts[fixture.id] = result.conflict;
    else fixtures.push(result.fixture);
  }
  if (Object.keys(conflicts).length) return { conflict: { observedAt: candidate.observedAt, fixtures: conflicts } };
  return { accepted: { ...candidate, fixtures } };
}

// Strictly validate the complete source before isolating known record conflicts.
// Missing/contradictory facts are retained, never silently cancelled or renewed.
export function admitSportsCollectionIsolated(collection, previous, descriptor, now, priorConflict) {
  const candidate = validatedCollection(collection, previous, descriptor, now);
  const oldByID = new Map((previous?.fixtures || []).map((fixture) => [fixture.id, fixture]));
  const currentIDs = new Set(candidate.fixtures.map((fixture) => fixture.id));
  const prior = priorCorrections(priorConflict), conflicts = {}, issues = new Map(), held = new Map(), fresh = new Map();
  const markIssue = (competitionId, issue) => {
    const previousIssue = issues.get(competitionId);
    issues.set(competitionId, { ...previousIssue, ...issue,
      conflict: Boolean(previousIssue?.conflict || issue.conflict) });
  };
  const retain = (old, issue) => {
    held.set(old.id, { ...old, source: { ...old.source, verification: "held" } });
    markIssue(old.competitionId, issue);
  };
  const moved = movedPublisherRows(candidate, previous, descriptor), blocked = new Set();
  for (const { fixture, prior: oldRows } of moved) {
    const issue = { failure: new Error("Publisher fixture competition changed") };
    blocked.add(fixture.id);
    markIssue(fixture.competitionId, issue);
    for (const old of oldRows) retain(old, issue);
  }
  // Terminal disappearance is ordinarily valid. A different opaque ID cannot
  // use that rule to resurrect the exact accepted event as active, however.
  // This is only an exact semantic contradiction, never an ID alias or a
  // same-team heuristic (different starts/squads/titles stay independent).
  for (const { fixture, prior: oldRows } of resurrectedTerminalRows(candidate, previous)) {
    const issue = { failure: new Error("Terminal fixture status regressed") };
    blocked.add(fixture.id);
    for (const old of oldRows) retain(old, issue);
    const displaced = oldByID.get(fixture.id);
    if (displaced) retain(displaced, issue);
  }
  for (const fixture of candidate.fixtures) {
    if (blocked.has(fixture.id)) continue;
    const old = oldByID.get(fixture.id);
    try {
      const result = admitRecord(fixture, old, candidate.observedAt, prior[fixture.id]);
      if (result.conflict) {
        conflicts[fixture.id] = result.conflict;
        retain(old, { conflict: true });
      } else fresh.set(fixture.id, result.fixture);
    } catch (error) {
      if (error.message !== "Terminal fixture status regressed") throw error;
      retain(old, { failure: error });
    }
  }
  for (const old of previous?.fixtures || []) {
    if (!currentIDs.has(old.id) && !held.has(old.id) && activeInWindow(old, now)) {
      retain(old, { failure: new Error("Accepted fixture disappeared without cancellation evidence") });
    }
  }
  // A publisher can replace an opaque ID without resolving the old record's
  // disappearance. The mixed output must not contain two native identities:
  // keep accepted facts held and withhold ambiguous replacements, never alias.
  // Retaining a displaced existing row can expose another collision. A bounded
  // queue visits each retained/fresh identity once, including those cascades.
  const pendingHeld = [...held.values()];
  const freshByIdentity = new Map([...fresh.values()].map((fixture) => [sportsSnapshotIdentity(fixture), fixture]));
  for (let index = 0; index < pendingHeld.length; index++) {
    const key = sportsSnapshotIdentity(pendingHeld[index]), fixture = freshByIdentity.get(key);
    if (!fixture) continue;
    fresh.delete(fixture.id);
    freshByIdentity.delete(key);
    delete conflicts[fixture.id];
    const issue = { failure: new Error("Accepted fixture identity became ambiguous") };
    markIssue(fixture.competitionId, issue);
    const old = oldByID.get(fixture.id);
    if (old && !held.has(old.id)) {
      retain(old, issue);
      pendingHeld.push(old);
    }
  }
  requireValue(fresh.size + held.size <= 500, "Source fixture count invalid");
  const fixtures = issues.size ? [...fresh.values()].map((fixture) => ({ ...fixture, source: { ...fixture.source, verification: "verified" } }))
    .concat([...held.values()]) : [...fresh.values()];
  fixtures.sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
  // This internal envelope is also the completed-collection replay fence.
  // Held row and cohort receipts remain original; empty success must still
  // advance the fence so an older response cannot resurrect erased records.
  return { accepted: { ...candidate, fixtures }, issues,
    ...(Object.keys(conflicts).length ? { conflict: { observedAt: candidate.observedAt, fixtures: conflicts } } : {}) };
}

export function nextSportsRefresh(fixtures, now, pendingStarts = [], pendingFixtureCount = 0) {
  if (fixtures.some((fixture) => fixture.status === "live" || (fixture.status === "scheduled"
    && Date.parse(fixture.start) >= now.getTime() - 15 * MINUTE && Date.parse(fixture.start) <= now.getTime() + 30 * MINUTE))
    || pendingStarts.some((start) => Date.parse(start) >= now.getTime() - DAY && Date.parse(start) <= now.getTime() + 30 * MINUTE)) return 5 * MINUTE;
  if (fixtures.some((fixture) => fixture.status === "scheduled" && Date.parse(fixture.start) > now.getTime()
    && Date.parse(fixture.start) <= now.getTime() + DAY)
    || pendingStarts.some((start) => Date.parse(start) > now.getTime() && Date.parse(start) <= now.getTime() + DAY)
    || pendingFixtureCount > pendingStarts.length) return 15 * MINUTE;
  return 4 * 60 * MINUTE;
}

export async function sportsRevision(fixtures, coverage = []) {
  const content = fixtures.map(({ source, ...fixture }) => ({ ...fixture, source: { name: source.name, url: source.url,
    ...(source.verification === undefined ? {} : { verification: source.verification }) } }));
  // Unsupported/failed coverage changes must propagate even if fixture content
  // does not. Successful check times alone must not churn the app's catalog.
  const states = coverage.map(({ competitionId, status, pendingFixtureCount }) => ({ competitionId, status, pendingFixtureCount }));
  const bytes = new TextEncoder().encode(JSON.stringify([content, states]));
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
