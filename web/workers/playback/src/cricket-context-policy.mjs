// Optional score context from the already admitted ICC schedule response.
// This never supplies fixture identity, status, a broadcast or extra collection.
const CONTEXT_BYTES = 64 * 1024;
const SNAPSHOT_BYTES = 512 * 1024;
const PHASES = new Set(["in-play", "break", "innings-break", "stumps", "lunch", "tea", "interrupted",
  "delayed", "finished", "cancelled", "postponed", "scheduled"]);
const KEYS = new Set(["innings", "currentInnings", "battingTeamID", "bowlingTeamID", "day", "session", "phase", "message", "target", "matchOrdinal", "matchEndsAt"]);
const INNINGS_KEYS = new Set(["number", "teamID", "runs", "wickets", "overs"]);
const MAX_OVERS = { T10: 10, T20: 20, ODI: 50, Test: 500 };

function object(value) { return value && typeof value === "object" && !Array.isArray(value); }
function optionalRaw(value) { return value === undefined || value === null || value === ""; }
function integer(value, minimum, maximum) {
  if (!((typeof value === "string" && /^(0|[1-9]\d*)$/.test(value)) || Number.isSafeInteger(value))) throw new Error("Invalid cricket score integer");
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < minimum || number > maximum) throw new Error("Invalid cricket score integer");
  return number;
}
function inningsLimit(format) { return format === "Test" ? 4 : ["T10", "T20", "ODI"].includes(format) ? 2 : 0; }
function testMatchOrdinal(row, fixture) {
  if (fixture.format !== "Test") return undefined;
  // The series title's "3 Test Series" is a count, not this match's ordinal.
  // Admit only two explicit, agreeing fields from the same ICC match record.
  const label = typeof row.match_number === "string"
    ? row.match_number.trim().match(/^([1-9]\d?)(st|nd|rd|th) Test$/i) : undefined;
  if (!label) return undefined;
  try {
    const number = integer(row.match_ordinal, 1, 99);
    const suffix = number % 100 >= 11 && number % 100 <= 13 ? "th"
      : ({ 1: "st", 2: "nd", 3: "rd" }[number % 10] || "th");
    return Number(label[1]) === number && label[2].toLowerCase() === suffix ? number : undefined;
  } catch { return undefined; }
}
function validTestMatchEnd(value, fixture) {
  if (fixture.format !== "Test" || typeof value !== "string"
    || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00\.000Z$/.test(value)) return false;
  const end = Date.parse(value);
  const start = Date.parse(fixture.start);
  return Number.isFinite(end) && Number.isFinite(start) && new Date(end).toISOString() === value
    && end > start && end - start <= 6 * 86_400_000;
}
function testMatchEnd(row, fixture) {
  if (fixture.format !== "Test") return undefined;
  const date = typeof row.end_match_date_gmt === "string"
    ? row.end_match_date_gmt.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/) : undefined;
  const time = typeof row.end_match_time_gmt === "string" ? row.end_match_time_gmt.match(/^(\d{2}):(\d{2})$/) : undefined;
  if (!date || !time) return undefined;
  const [month, day, year, hour, minute] = [date[1], date[2], date[3], time[1], time[2]].map(Number);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return undefined;
  const parsed = new Date(Date.UTC(year, month - 1, day, hour, minute));
  if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day) return undefined;
  const value = parsed.toISOString();
  return validTestMatchEnd(value, fixture) ? value : undefined;
}
function overs(value, format) {
  if (typeof value !== "string" || !/^(0|[1-9]\d{0,2})(?:\.[0-5])?$/.test(value)) throw new Error("Invalid cricket overs");
  const [whole, balls = "0"] = value.split(".");
  if (Number(whole) > MAX_OVERS[format] || (Number(whole) === MAX_OVERS[format] && balls !== "0")) throw new Error("Invalid cricket overs");
  return value;
}
function message(value) {
  if (typeof value !== "string" || value.length > 200 || /[\u0000-\u001f<>]/.test(value) || !value.trim()) throw new Error("Invalid cricket context message");
  return value.trim();
}
function withoutContext(fixture) {
  const copy = { ...fixture };
  delete copy.context;
  return copy;
}
function phase(row, fixture) {
  if (["finished", "cancelled", "postponed", "scheduled"].includes(fixture.status)) return fixture.status;
  const labels = [row.match_status, row.match_display_status].filter((value) => typeof value === "string")
    .map((value) => value.trim().toLowerCase());
  // Breaks override a generic Live display marker; score presence does not.
  const explicit = [["stumps", "stumps"], ["lunch", "lunch"], ["tea", "tea"],
    ["innings break", "innings-break"], ["inningsbreak", "innings-break"],
    ["delayed", "delayed"], ["play delayed", "delayed"], ["interrupted", "interrupted"]];
  for (const [label, result] of explicit) if (labels.includes(label)) return result;
  if (row.is_match_interrupted === true) return "interrupted";
  if (row.is_match_on_break === true) return "break";
  if (fixture.status === "live" && labels.some((label) => ["play in progress", "live"].includes(label))) return "in-play";
  return undefined;
}

export function validCricketContext(context, fixture) {
  try {
    const limit = inningsLimit(fixture.format);
    if (!limit || !["live", "finished"].includes(fixture.status) || !object(context) || Object.keys(context).some((key) => !KEYS.has(key))
      || !Array.isArray(context.innings) || !context.innings.length || context.innings.length > limit) return false;
    const teams = new Set([fixture.home.id, fixture.away.id]);
    const numbers = new Set();
    const counts = new Map();
    for (const inning of context.innings) {
      if (!object(inning) || Object.keys(inning).some((key) => !INNINGS_KEYS.has(key))
        || !Number.isSafeInteger(inning.number) || !Number.isSafeInteger(inning.runs) || !Number.isSafeInteger(inning.wickets)
        || !teams.has(inning.teamID) || numbers.has(inning.number)) return false;
      integer(inning.number, 1, limit); integer(inning.runs, 0, 2000); integer(inning.wickets, 0, 10);
      if (inning.overs !== undefined) overs(inning.overs, fixture.format);
      numbers.add(inning.number);
      counts.set(inning.teamID, (counts.get(inning.teamID) || 0) + 1);
    }
    if ([...numbers].sort((a, b) => a - b).some((number, index) => number !== index + 1)
      || [...counts.values()].some((count) => count > (fixture.format === "Test" ? 2 : 1))) return false;
    if (context.currentInnings !== undefined && (!Number.isSafeInteger(context.currentInnings)
      || context.currentInnings !== Math.max(...numbers))) return false;
    for (const key of ["battingTeamID", "bowlingTeamID"]) if (context[key] !== undefined && !teams.has(context[key])) return false;
    if (context.battingTeamID !== undefined && context.battingTeamID === context.bowlingTeamID) return false;
    const current = context.innings.find((inning) => inning.number === context.currentInnings);
    if (current && context.battingTeamID !== undefined && current.teamID !== context.battingTeamID) return false;
    for (const [key, maximum] of [["day", 6], ["session", 3]]) {
      if (context[key] !== undefined) {
        if (fixture.format !== "Test" || !Number.isSafeInteger(context[key])) return false;
        integer(context[key], 1, maximum);
      }
    }
    if (context.matchOrdinal !== undefined && (fixture.format !== "Test" || !Number.isSafeInteger(context.matchOrdinal)
      || context.matchOrdinal < 1 || context.matchOrdinal > 99)) return false;
    if (context.matchEndsAt !== undefined && !validTestMatchEnd(context.matchEndsAt, fixture)) return false;
    if (context.phase !== undefined && (!PHASES.has(context.phase)
      || (["stumps", "lunch", "tea"].includes(context.phase) && fixture.format !== "Test"))) return false;
    if (context.message !== undefined) message(context.message);
    if (context.target !== undefined) {
      if (!current || !Number.isSafeInteger(context.target)) return false;
      integer(context.target, 1, 5000);
    }
    return true;
  } catch { return false; }
}

export function normalizeICCContext(row, fixture) {
  try {
    const limit = inningsLimit(fixture.format);
    if (!limit || !["live", "finished"].includes(fixture.status) || row.has_super_over === true
      || !Array.isArray(row.scores) || !row.scores.length || row.scores.length > limit) return undefined;
    const group = String(row.league_id);
    const canonical = (value) => {
      if (!/^\d{1,12}$/.test(String(value))) throw new Error("Invalid cricket context team");
      const id = `icc:${group}:${value}`;
      if (id !== fixture.home.id && id !== fixture.away.id) throw new Error("Foreign cricket context team");
      return id;
    };
    // Bind against the enclosing admitted fixture, never a name or a channel.
    if (canonical(row.teama_id) !== fixture.home.id || canonical(row.teamb_id) !== fixture.away.id) return undefined;
    const innings = row.scores.map((score) => {
      if (!object(score)) throw new Error("Invalid cricket innings");
      return { number: integer(score.inning_no, 1, limit), teamID: canonical(score.team_id),
        runs: integer(score.team_runs, 0, 2000), wickets: integer(score.team_wickets, 0, 10),
        ...(optionalRaw(score.team_overs) ? {} : { overs: overs(score.team_overs, fixture.format) }) };
    }).sort((a, b) => a.number - b.number);
    const context = { innings };
    if (!optionalRaw(row.current_innings) && row.current_innings !== "0" && row.current_innings !== 0) context.currentInnings = integer(row.current_innings, 1, limit);
    for (const [raw, key] of [["current_batting_team_id", "battingTeamID"], ["current_bowling_team_id", "bowlingTeamID"]]) {
      if (!optionalRaw(row[raw]) && row[raw] !== "0" && row[raw] !== 0) context[key] = canonical(row[raw]);
    }
    for (const [key, maximum] of [["day", 6], ["session", 3]]) {
      if (!optionalRaw(row[key]) && row[key] !== "0" && row[key] !== 0) context[key] = integer(row[key], 1, maximum);
    }
    const matchOrdinal = testMatchOrdinal(row, fixture);
    if (matchOrdinal !== undefined) context.matchOrdinal = matchOrdinal;
    const matchEndsAt = testMatchEnd(row, fixture);
    if (matchEndsAt !== undefined) context.matchEndsAt = matchEndsAt;
    const observedPhase = phase(row, fixture);
    if (observedPhase !== undefined) context.phase = observedPhase;
    if (!optionalRaw(row.current_status_message)) context.message = message(row.current_status_message);
    const current = row.scores.find((score) => Number(score.inning_no) === context.currentInnings);
    if (current && !optionalRaw(current.target)) context.target = integer(current.target, 1, 5000);
    return validCricketContext(context, fixture) ? context : undefined;
  } catch { return undefined; }
}

/// Bound only additive optional context. Never truncate the accepted fixture
/// registry or make a malformed score erase its schedule/status authority.
export function boundedCricketContexts(snapshot) {
  const fixtures = snapshot.fixtures.map((fixture) => {
    if (fixture.context === undefined || validCricketContext(fixture.context, fixture)) return fixture;
    return withoutContext(fixture);
  });
  const base = fixtures.map(withoutContext);
  const baseBytes = new TextEncoder().encode(JSON.stringify({ ...snapshot, fixtures: base })).length;
  let budget = Math.min(CONTEXT_BYTES, Math.max(0, SNAPSHOT_BYTES - baseBytes));
  const included = new Set();
  const priority = fixtures.map((fixture, index) => ({ fixture, index })).sort((a, b) =>
    Number(b.fixture.status === "live") - Number(a.fixture.status === "live") || a.index - b.index);
  for (const { fixture, index } of priority) {
    if (fixture.context === undefined) continue;
    const size = new TextEncoder().encode(JSON.stringify(fixture)).length
      - new TextEncoder().encode(JSON.stringify(base[index])).length;
    if (size <= budget) { budget -= size; included.add(index); }
  }
  return { ...snapshot, fixtures: fixtures.map((fixture, index) => included.has(index) ? fixture : base[index]) };
}
