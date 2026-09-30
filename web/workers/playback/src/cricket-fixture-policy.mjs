// Official international-cricket fixtures, separate from broadcast availability.
// A successful HTTP response is not enough: completeness and source time matter.
export const CRICKET_COMPETITIONS = Object.freeze([
  { id: "cpl", name: "Caribbean Premier League" },
  { id: "west-indies", name: "West Indies internationals" },
  { id: "icc", name: "International cricket" },
]);
export const ICC_SCHEDULE_ORIGIN = "https://assets-icc.sportz.io";
const ICC_CLIENT = "tPZJbRgIub3Vua93/DWtyQ==";
const DAY = 86_400_000;
const MINUTE = 60_000;
const FORMATS = new Set(["T20", "ODI", "Test", "T10", "unknown"]);
const STATUSES = new Set(["scheduled", "live", "finished", "cancelled", "postponed", "unknown"]);

export function cricketWindow(now) {
  const midnight = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return { from: new Date(midnight - 6 * DAY), to: new Date(midnight + 8 * DAY) };
}

export function iccScheduleURL(now, page = 1) {
  const window = cricketWindow(now);
  const date = (value) => value.toISOString().slice(0, 10).replaceAll("-", "");
  const url = new URL("/cricket/v1/schedule", ICC_SCHEDULE_ORIGIN);
  url.search = new URLSearchParams({ client_id: ICC_CLIENT, feed_format: "json", is_deleted: "false",
    from_date: date(window.from), to_date: date(new Date(window.to.getTime() - DAY)),
    pagination: "true", page_size: "100", page_number: String(page), timezone: "0000" }).toString();
  return url;
}

// Do not delegate the source's US date format to runtime-dependent Date.parse.
function utcParts(year, month, day, hour, minute, second = 0) {
  const value = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  if (value.getUTCFullYear() !== year || value.getUTCMonth() !== month - 1 || value.getUTCDate() !== day
    || hour > 23 || minute > 59 || second > 59) throw new Error("Invalid ICC date");
  return value;
}

export function iccSourceTime(text) {
  const parts = String(text).match(/^(\d{1,2})\/(\d{1,2})\/(\d{4}) (\d{1,2}):(\d{2}):(\d{2}) (AM|PM)$/);
  if (!parts || Number(parts[4]) < 1 || Number(parts[4]) > 12) throw new Error("Invalid ICC receipt");
  const hour = Number(parts[4]) % 12 + (parts[7] === "PM" ? 12 : 0);
  return utcParts(Number(parts[3]), Number(parts[1]), Number(parts[2]), hour, Number(parts[5]), Number(parts[6]));
}

function startTime(row) {
  const parts = String(row.match_date_gmt).match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  const time = String(row.match_time_gmt).match(/^(\d{2}):(\d{2})$/);
  if (!parts || !time) throw new Error("Invalid ICC kickoff");
  return utcParts(Number(parts[3]), Number(parts[1]), Number(parts[2]), Number(time[1]), Number(time[2]));
}

function safeLabel(value) {
  if (typeof value !== "string" || !value.trim() || value.length > 200 || /[\u0000-\u001f<>]/.test(value)) {
    throw new Error("Invalid ICC label");
  }
  return value.trim();
}

function identifier(value) {
  if (!/^\d{1,12}$/.test(String(value))) throw new Error("Invalid ICC identity");
  return String(value);
}

function normalizedTeam(row, side) {
  const group = String(row.league_id);
  let name = safeLabel(row[`team${side}_display_name`] || row[`team${side}`]);
  name = name.replace(/\b(?:Under[- ]?19|U[- ]?19)\b/gi, "U19");
  if (["10", "35"].includes(group) && !/\b(?:Women|Womens|Ladies)\b/i.test(name)) name += " Women";
  if (["9", "35"].includes(group) && !/\bU19\b/i.test(name)) name += " U19";
  return { id: `icc:${group}:${identifier(row[`team${side}_id`])}`, name };
}

function fixtureStatus(row) {
  if (row.is_match_abandoned === true || /cancel|abandon/i.test(row.match_status || "")) return "cancelled";
  if (/postpon/i.test(row.match_status || "")) return "postponed";
  if (row.is_match_ended === true || row.recent === true) return "finished";
  if (row.live === true) return "live";
  if (row.upcoming === true) return "scheduled";
  return "unknown";
}

export function parseICCPage(payload, now) {
  const count = payload?.meta?.count;
  const rows = payload?.data?.matches;
  if (payload?.meta?.app_status_code !== 1 || payload?.meta?.pagination !== true
    || !Number.isSafeInteger(count) || count < 0 || count > 300 || !Array.isArray(rows) || rows.length > 100) {
    throw new Error("Incomplete ICC page");
  }
  const observedAt = iccSourceTime(payload.meta.timestamp?.utc_time);
  const age = now.getTime() - observedAt.getTime();
  if (age < -5 * MINUTE || age > 6 * 60 * MINUTE || (rows.some((r) => r.live === true) && age > 30 * MINUTE)) {
    throw new Error("Stale ICC receipt");
  }
  return { count, rows, observedAt: new Date(Math.min(now.getTime(), observedAt.getTime())).toISOString() };
}

export function normalizeICC(pages, now) {
  if (!pages.length || pages.some((p) => p.count !== pages[0].count)) throw new Error("ICC pagination changed");
  const rows = pages.flatMap((p) => p.rows);
  if (rows.length !== pages[0].count) throw new Error("Truncated ICC schedule");
  const observedAt = pages.map((p) => p.observedAt).sort()[0];
  const window = cricketWindow(now);
  const seen = new Set();
  const fixtures = [];
  const pendingByCompetition = { "west-indies": 0, icc: 0 };
  for (const row of rows) {
    const id = `icc:${identifier(row.match_id)}`;
    if (seen.has(id)) throw new Error("Duplicate ICC fixture");
    seen.add(id);
    if (row.is_deleted === true) continue;
    // The adapter only understands the four documented international groups.
    if (!["1", "10", "9", "35"].includes(String(row.league_id))) throw new Error("Unknown ICC competition group");
    // Provisional dates/teams cannot advertise a precise countdown or pairing.
    const pendingGroup = [row.teama, row.teamb].some((name) => /\bWest Indies\b/i.test(String(name))) ? "west-indies" : "icc";
    if (row.is_provisional_date === true || row.is_provisional_time === true
      || [row.teama, row.teamb].some((name) => /^(T\.?B\.?C\.?|TBD|to be confirmed)$/i.test(String(name)))) {
      pendingByCompetition[pendingGroup]++;
      continue;
    }
    const start = startTime(row);
    if (start < window.from || start >= window.to) throw new Error("ICC fixture outside requested window");
    const home = normalizedTeam(row, "a");
    const away = normalizedTeam(row, "b");
    if (home.id === away.id || /^(tbc|tbd|to be confirmed|winner\b|loser\b)/i.test(home.name)
      || /^(tbc|tbd|to be confirmed|winner\b|loser\b)/i.test(away.name)) continue;
    const westIndies = /\bWest Indies\b/i.test(home.name) || /\bWest Indies\b/i.test(away.name);
    const rawFormat = String(row.match_type).replace(/^Youth\s+/i, "").toUpperCase().replace(/^T20I$/, "T20");
    const format = rawFormat === "TEST" ? "Test" : FORMATS.has(rawFormat) ? rawFormat : "unknown";
    fixtures.push({ id, start: start.toISOString(), format, status: fixtureStatus(row),
      competitionId: westIndies ? "west-indies" : "icc", competitionName: safeLabel(row.series_name), home, away,
      source: { name: "ICC", url: `https://www.icc-cricket.com/matches/${identifier(row.match_id)}`, observedAt },
      // Internal admission evidence; stripped from the public contract below.
      revised: row.is_revised === true });
  }
  return { fixtures, observedAt, pendingByCompetition };
}

export function admitICC(candidate, previous, now) {
  const byId = new Map(candidate.fixtures.map((f) => [f.id, f]));
  const window = cricketWindow(now);
  for (const old of previous || []) {
    if (!old.id.startsWith("icc:")) continue;
    const current = byId.get(old.id);
    if (!current) {
      const start = Date.parse(old.start);
      if ((old.status === "live" || old.status === "scheduled") && start >= window.from.getTime()
        && start < window.to.getTime() && start < now.getTime() + DAY) throw new Error("Active ICC fixture disappeared");
      continue;
    }
    if (current.home.id !== old.home.id || current.away.id !== old.away.id) throw new Error("ICC identity conflict");
    if (current.start !== old.start && !current.revised) throw new Error("Unconfirmed ICC kickoff change");
    if (["finished", "cancelled"].includes(old.status) && ["live", "scheduled"].includes(current.status)) {
      throw new Error("ICC terminal-status regression");
    }
    if (old.status === "live" && ["scheduled", "unknown"].includes(current.status) && !current.revised) {
      throw new Error("ICC live-status regression");
    }
  }
  if (previous?.length && candidate.observedAt < previous.filter((f) => f.id.startsWith("icc:")).map((f) => f.source.observedAt).sort().at(-1)) {
    throw new Error("ICC receipt regressed");
  }
  return { ...candidate, fixtures: candidate.fixtures.map((fixture) => {
    const publicFixture = { ...fixture };
    delete publicFixture.revised;
    return publicFixture;
  }) };
}

export function nextCricketRefresh(fixtures, now) {
  const time = now.getTime();
  if (fixtures.some((f) => f.status === "live" || (f.status === "scheduled"
    && Date.parse(f.start) >= time - 12 * 60 * MINUTE && Date.parse(f.start) <= time + 30 * MINUTE))) return 5 * MINUTE;
  if (fixtures.some((f) => f.status === "scheduled" && Date.parse(f.start) >= time && Date.parse(f.start) < time + DAY)) return 15 * MINUTE;
  return 4 * 60 * MINUTE;
}

export function validateCricketSnapshot(snapshot) {
  if (snapshot?.schemaVersion !== 1 || snapshot.complete !== true || !Array.isArray(snapshot.fixtures)
    || snapshot.fixtures.length > 400 || !Array.isArray(snapshot.coverage) || snapshot.coverage.length !== 3) throw new Error("Invalid cricket snapshot");
  const ids = new Set();
  for (const fixture of snapshot.fixtures) {
    if (ids.has(fixture.id) || typeof fixture.id !== "string" || !FORMATS.has(fixture.format) || !STATUSES.has(fixture.status)
      || !Number.isFinite(Date.parse(fixture.start)) || !Number.isFinite(Date.parse(fixture.source?.observedAt))) throw new Error("Invalid cricket fixture");
    ids.add(fixture.id);
  }
  for (const comp of CRICKET_COMPETITIONS) {
    const coverage = snapshot.coverage.filter((c) => c.competitionId === comp.id);
    if (coverage.length !== 1 || !["covered", "offseason", "unavailable"].includes(coverage[0].status)
      || coverage[0].fixtureCount !== snapshot.fixtures.filter((f) => f.competitionId === comp.id).length) throw new Error("Invalid cricket coverage");
  }
  return snapshot;
}
