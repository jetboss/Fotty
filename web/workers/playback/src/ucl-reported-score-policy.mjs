// Optional score evidence on admitted fixtures. The historical Champions League
// report has a separate contract and can also accompany a finished fixture.
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
function validLiveDisplay(live, fixture, covered, now) {
  if (fixture.sport !== "football" || fixture.eventKind !== "match" || fixture.status !== "live"
    || fixture.source?.verification === "held" || !covered.has(fixture.competitionId) && fixture.source?.verification !== "verified"
    || !live || typeof live !== "object" || Array.isArray(live)) return false;
  const receipts = [fixture.source.observedAt];
  if (fixture.source.updatedAt !== undefined) receipts.push(fixture.source.updatedAt);
  if (!receipts.every((receipt) => {
    const age = now.getTime() - Date.parse(utc(receipt));
    return age >= -300_000 && age <= 1_800_000;
  })) return false;
  const hasScore = live.home !== undefined || live.away !== undefined;
  const hasClock = live.clock !== undefined;
  return (hasScore || hasClock) && Object.keys(live).every((key) => ["home", "away", "clock"].includes(key))
    && (!hasScore || scoreInteger(live.home) && scoreInteger(live.away))
    && (!hasClock || typeof live.clock === "string" && /^(?:HT|ET|PEN|(?:0|[1-9]\d?|1[0-4]\d|150)(?:\+[1-9]\d?)?′)$/.test(live.clock));
}

export function boundedFixtureScores(snapshot, now) {
  const covered = new Set(snapshot.coverage.filter((lane) => lane.status === "covered").map((lane) => lane.competitionId));
  const base = snapshot.fixtures.map((fixture) => {
    if (fixture.reportedScore === undefined && fixture.footballLive === undefined) return fixture;
    const { reportedScore, footballLive, ...facts } = fixture;
    return facts;
  });
  const encoder = new TextEncoder();
  const bytes = (value) => encoder.encode(JSON.stringify(value)).length;
  // Reserve the fixed SHA256 revision's wire size before the caller hashes it.
  const baseBytes = bytes({ ...snapshot, revision: "0".repeat(64), fixtures: base });
  let budget = Math.min(MAX_SCORE_BYTES, Math.max(0, MAX_SNAPSHOT_BYTES - baseBytes));
  return { ...snapshot, fixtures: snapshot.fixtures.map((fixture, index) => {
    if (fixture === base[index]) return fixture;
    const output = { ...base[index] };
    if (validUCLReportedScore(fixture.reportedScore, fixture)) output.reportedScore = fixture.reportedScore;
    if (validLiveDisplay(fixture.footballLive, fixture, covered, now)) output.footballLive = fixture.footballLive;
    const added = bytes(output) - bytes(base[index]);
    if (added > budget) return base[index];
    budget -= added;
    return output;
  }) };
}
