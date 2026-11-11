// Optional delayed reporting from the already admitted football-data CL rows.
// No requests, live-score authority, fixture/status changes or PL/FPL changes.
const MAX_SCORE_BYTES = 32 * 1024;
const MAX_SNAPSHOT_BYTES = 2 * 1024 * 1024;
const SCORE_KEYS = new Set(["home", "away", "publisherUpdatedAt"]);
const scoreInteger = (value) => Number.isSafeInteger(value) && value >= 0 && value <= 99;
function utc(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)) return undefined;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 19) === value.slice(0, 19)
    ? date.toISOString() : undefined;
}
function scope(fixture) {
  return fixture?.sport === "football" && fixture.competitionId === "champions-league"
    && /^sports-fixture:champions-league:[1-9]\d{0,11}$/.test(fixture.id)
    && fixture.eventKind === "match" && fixture.squad?.gender === "men" && fixture.squad?.ageGroup === "senior"
    && ["live", "finished"].includes(fixture.status) && fixture.source?.name === "football-data.org"
    && Array.isArray(fixture.participants) && fixture.participants.length === 2
    && fixture.participants.filter((team) => team.role === "home").length === 1
    && fixture.participants.filter((team) => team.role === "away").length === 1
    && fixture.participants.every((team) => /^football-data:[1-9]\d{0,11}$/.test(team.id))
    && fixture.participants[0].id !== fixture.participants[1].id;
}
export function validUCLReportedScore(score, fixture) {
  return scope(fixture) && score && typeof score === "object" && !Array.isArray(score)
    && Object.keys(score).every((key) => SCORE_KEYS.has(key))
    && scoreInteger(score.home) && scoreInteger(score.away)
    && utc(score.publisherUpdatedAt) !== undefined
    && utc(score.publisherUpdatedAt) === utc(fixture.source.updatedAt);
}
export function normalizeUCLReportedScore(row, fixture) {
  if (!scope(fixture) || row?.competition?.code !== "CL" || String(row.id) !== fixture.id.split(":").at(-1)
    || !["IN_PLAY", "PAUSED", "FINISHED", "AWARDED"].includes(row.status)
    || fixture.status !== (["IN_PLAY", "PAUSED"].includes(row.status) ? "live" : "finished")
    || row.score?.duration !== "REGULAR") return undefined;
  const home = fixture.participants.find((team) => team.role === "home");
  const away = fixture.participants.find((team) => team.role === "away");
  if (home.id !== `football-data:${row.homeTeam?.id}` || away.id !== `football-data:${row.awayTeam?.id}`) return undefined;
  const publisherUpdatedAt = utc(row.lastUpdated);
  const score = { home: row.score?.fullTime?.home, away: row.score?.fullTime?.away, publisherUpdatedAt };
  return validUCLReportedScore(score, fixture) ? score : undefined;
}
const withoutScore = (fixture) => {
  if (fixture.reportedScore === undefined) return fixture;
  const copy = { ...fixture }; delete copy.reportedScore; return copy;
};
export function boundedUCLReportedScores(snapshot) {
  const fixtures = snapshot.fixtures.map((fixture) => fixture.reportedScore === undefined
    || validUCLReportedScore(fixture.reportedScore, fixture) ? fixture : withoutScore(fixture));
  const base = fixtures.map(withoutScore);
  // Reserve the fixed SHA256 revision's wire size before the caller hashes it.
  const baseBytes = new TextEncoder().encode(JSON.stringify({ ...snapshot, revision: "0".repeat(64), fixtures: base })).length;
  let budget = Math.min(MAX_SCORE_BYTES, Math.max(0, MAX_SNAPSHOT_BYTES - baseBytes));
  return { ...snapshot, fixtures: fixtures.map((fixture, index) => {
    if (fixture.reportedScore === undefined) return fixture;
    const bytes = new TextEncoder().encode(JSON.stringify(fixture)).length
      - new TextEncoder().encode(JSON.stringify(base[index])).length;
    if (bytes > budget) return base[index];
    budget -= bytes; return fixture;
  }) };
}
