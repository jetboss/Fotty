const teamAliases = new Map([
  ["antigua and barbuda falcons", "antigua"], ["antigua & barbuda falcons", "antigua"],
  ["barbados tridents", "barbados"], ["barbados royals", "barbados"],
  ["guyana amazon warriors", "guyana"], ["jamaica kingsmen", "jamaica"],
  ["saint lucia kings", "saintLucia"], ["st lucia kings", "saintLucia"],
  ["st kitts and nevis patriots", "stKitts"], ["st kitts & nevis patriots", "stKitts"],
  ["trinbago knight riders", "trinbago"],
]);
const teamKeys = new Set(teamAliases.values());
const playoffStages = new Map([[36, "Eliminator"], [37, "Qualifier 1"], [38, "Qualifier 2"], [39, "Final"]]);

export const cplFixtureSources = Object.freeze({
  live: "https://www.cricbuzz.com/cricket-series/12123/caribbean-premier-league-2026/matches",
  published: "https://cplt20.prezly.com/republic-bank-cpl-fixtures-confirmed-for-2026",
  correction: "https://wp.cplt20.com/wp-json/wp/v2/news/20232",
});

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function normalizeTeam(name) {
  return teamAliases.get(name.trim().toLowerCase());
}

export function validateCPLManifest(manifest) {
  requireValue(manifest.schemaVersion === 1, "CPL manifest schemaVersion must be 1.");
  requireValue(manifest.competitionId === "cpl" && manifest.season === 2026, "CPL manifest has the wrong competition or season.");
  requireValue(Number.isFinite(Date.parse(manifest.checkedAt)), "CPL manifest checkedAt must be ISO-8601.");
  requireValue(Array.isArray(manifest.sources) && manifest.sources.length >= 2, "CPL manifest needs published and current verification sources.");
  requireValue(Array.isArray(manifest.verificationExceptions), "CPL manifest verificationExceptions must be an array.");
  requireValue(Array.isArray(manifest.fixtures) && manifest.fixtures.length === 39, "CPL manifest must contain exactly 39 fixtures.");

  const numbers = new Set();
  const upstreamIDs = new Set();
  let previousStart = 0;
  for (const fixture of manifest.fixtures) {
    requireValue(Number.isInteger(fixture.number) && fixture.number >= 1 && fixture.number <= 39, `Invalid fixture number ${fixture.number}.`);
    requireValue(!numbers.has(fixture.number), `Duplicate fixture number ${fixture.number}.`);
    numbers.add(fixture.number);
    requireValue(typeof fixture.upstreamId === "string" && /^\d+$/.test(fixture.upstreamId), `Fixture ${fixture.number} has no stable upstream id.`);
    requireValue(!upstreamIDs.has(fixture.upstreamId), `Duplicate upstream id ${fixture.upstreamId}.`);
    upstreamIDs.add(fixture.upstreamId);
    const start = Date.parse(fixture.start);
    requireValue(Number.isFinite(start) && new Date(start).getUTCFullYear() === manifest.season, `Fixture ${fixture.number} has an invalid start.`);
    requireValue(start >= previousStart, `Fixture ${fixture.number} is out of chronological order.`);
    previousStart = start;
    if (fixture.number <= 35) {
      requireValue(teamKeys.has(fixture.team1) && teamKeys.has(fixture.team2) && fixture.team1 !== fixture.team2, `Fixture ${fixture.number} has invalid teams.`);
      requireValue(fixture.stage === undefined, `League fixture ${fixture.number} must not have a playoff stage.`);
    } else {
      requireValue(fixture.stage === playoffStages.get(fixture.number), `Fixture ${fixture.number} has the wrong playoff stage.`);
      requireValue(fixture.team1 === undefined && fixture.team2 === undefined, `Playoff fixture ${fixture.number} must not invent participants.`);
    }
  }
  requireValue([...numbers].sort((a, b) => a - b).every((number, index) => number === index + 1), "CPL fixture numbers must be contiguous.");
  for (const exception of manifest.verificationExceptions) {
    requireValue(numbers.has(exception.number), `Verification exception references unknown fixture ${exception.number}.`);
    requireValue(["start", "teams", "upstreamId", "stage"].includes(exception.field), `Fixture ${exception.number} has an invalid exception field.`);
    requireValue(typeof exception.expected === "string" && typeof exception.observed === "string" && exception.reason?.length > 20, `Fixture ${exception.number} has an incomplete verification exception.`);
  }
}

function plainText(html) {
  return html.replaceAll("&amp;", "&").replaceAll("&nbsp;", " ")
    .replaceAll("&#8211;", "-").replaceAll("&#8217;", "'")
    .replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

export function parseCPLLiveSchedule(html) {
  const decoded = html.replaceAll('\\"', '"');
  const pattern = /"matchId":(\d+),"seriesId":12123,"seriesName":"[^"]+","matchDesc":"([^"]+)","matchFormat":"T20","startDate":"(\d+)"[\s\S]*?"team1":\{"teamId":\d+,"teamName":"([^"]+)"[\s\S]*?"team2":\{"teamId":\d+,"teamName":"([^"]+)"/g;
  const byUpstreamID = new Map();
  for (const match of decoded.matchAll(pattern)) {
    const [, upstreamId, description, startMilliseconds, rawTeam1, rawTeam2] = match;
    if (byUpstreamID.has(upstreamId)) continue;
    const numbered = description.match(/^(\d+)(?:st|nd|rd|th) Match$/);
    const stage = numbered ? undefined : description;
    const number = numbered ? Number(numbered[1]) : [...playoffStages.entries()].find(([, expected]) => expected === stage)?.[0];
    requireValue(number !== undefined, `Unknown live CPL match description: ${description}.`);
    const fixture = { number, upstreamId, start: new Date(Number(startMilliseconds)).toISOString().replace(".000Z", "Z") };
    if (number <= 35) {
      fixture.team1 = normalizeTeam(rawTeam1);
      fixture.team2 = normalizeTeam(rawTeam2);
      requireValue(fixture.team1 && fixture.team2, `Fixture ${number} contains an unknown live team: ${rawTeam1} / ${rawTeam2}.`);
    } else {
      fixture.stage = stage;
    }
    byUpstreamID.set(upstreamId, fixture);
  }
  const fixtures = [...byUpstreamID.values()].sort((a, b) => a.number - b.number);
  requireValue(fixtures.length === 39, `Live CPL response yielded ${fixtures.length} fixtures instead of 39.`);
  return fixtures;
}

export function parseCPLPublishedSchedule(html, correctionJSON, upstreamFixtures) {
  const rows = [...html.matchAll(/<tr class="prezly-slate-table-row">([\s\S]*?)<\/tr>/g)]
    .map((row) => [...row[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map((cell) => plainText(cell[1])))
    .filter((cells) => cells.length === 4 && /^\w{3} \d{1,2} \w{3}$/.test(cells[0]));
  requireValue(rows.length === 39, `Official CPL page yielded ${rows.length} fixtures instead of 39.`);
  const monthNumbers = new Map([["Aug", "08"], ["Sep", "09"]]);
  const upstreamByNumber = new Map(upstreamFixtures.map((fixture) => [fixture.number, fixture.upstreamId]));
  const fixtures = rows.map((cells, index) => {
    const number = index + 1;
    const [, day, monthName] = cells[0].split(" ");
    const time = cells[2].match(/^(\d{1,2})(am|pm)$/i);
    requireValue(time && monthNumbers.has(monthName), `Official fixture ${number} has an unreadable date or time.`);
    let hour = Number(time[1]) % 12;
    if (time[2].toLowerCase() === "pm") hour += 12;
    const offset = cells[3] === "Jamaica" ? "-05:00" : "-04:00";
    const localStart = `2026-${monthNumbers.get(monthName)}-${day.padStart(2, "0")}T${String(hour).padStart(2, "0")}:00:00${offset}`;
    const fixture = { number, upstreamId: upstreamByNumber.get(number), start: new Date(localStart).toISOString().replace(".000Z", "Z") };
    requireValue(fixture.upstreamId, `Official fixture ${number} has no matched upstream id.`);
    if (number <= 35) {
      const [rawTeam1, rawTeam2] = cells[1].split(" vs ");
      fixture.team1 = normalizeTeam(rawTeam1 ?? "");
      fixture.team2 = normalizeTeam(rawTeam2 ?? "");
      requireValue(fixture.team1 && fixture.team2, `Official fixture ${number} contains an unknown team: ${cells[1]}.`);
    } else {
      fixture.stage = playoffStages.get(number);
    }
    return fixture;
  });
  const correction = plainText(correctionJSON.acf?.description ?? correctionJSON.content?.rendered ?? "");
  requireValue(correction.includes("Jamaica Kingsmen now playing") && correction.includes("Saturday 29 August") && correction.includes("Guyana Amazon Warriors on Monday 31 August"), "The official 27 July opponent correction could not be verified.");
  fixtures[19] = { ...fixtures[19], team1: "trinbago", team2: "jamaica" };
  fixtures[21] = { ...fixtures[21], team1: "trinbago", team2: "guyana" };
  return fixtures;
}

function sameTeams(left, right) {
  return left.team1 === right.team1 && left.team2 === right.team2 || left.team1 === right.team2 && left.team2 === right.team1;
}

export function cplFixtureDifferences(current, candidate) {
  const byNumber = new Map(current.map((fixture) => [fixture.number, fixture]));
  const changes = [];
  for (const incoming of candidate) {
    const fixture = byNumber.get(incoming.number);
    if (!fixture) {
      changes.push({ number: incoming.number, field: "fixture", expected: "present", observed: "missing", message: `match ${incoming.number}: missing locally` });
      continue;
    }
    if (fixture.upstreamId !== incoming.upstreamId) changes.push({ number: incoming.number, field: "upstreamId", expected: fixture.upstreamId, observed: incoming.upstreamId, message: `match ${incoming.number}: upstream id ${fixture.upstreamId} -> ${incoming.upstreamId}` });
    if (fixture.start !== incoming.start) changes.push({ number: incoming.number, field: "start", expected: fixture.start, observed: incoming.start, message: `match ${incoming.number}: start ${fixture.start} -> ${incoming.start}` });
    if (incoming.number <= 35 && !sameTeams(fixture, incoming)) changes.push({ number: incoming.number, field: "teams", expected: `${fixture.team1}/${fixture.team2}`, observed: `${incoming.team1}/${incoming.team2}`, message: `match ${incoming.number}: teams ${fixture.team1}/${fixture.team2} -> ${incoming.team1}/${incoming.team2}` });
    if (incoming.number > 35 && fixture.stage !== incoming.stage) changes.push({ number: incoming.number, field: "stage", expected: fixture.stage, observed: incoming.stage, message: `match ${incoming.number}: stage ${fixture.stage} -> ${incoming.stage}` });
  }
  return changes;
}

function isReviewedException(change, manifest) {
  return manifest.verificationExceptions.some((exception) => exception.number === change.number && exception.field === change.field && exception.expected === change.expected && exception.observed === change.observed);
}

export function resolveCPLManifest({ fallback, publishedHTML, correctionJSON, verifierHTML, now = new Date() }) {
  validateCPLManifest(fallback);
  const live = parseCPLLiveSchedule(verifierHTML);
  const published = parseCPLPublishedSchedule(publishedHTML, correctionJSON, live);
  const authoritativeChanges = cplFixtureDifferences(fallback.fixtures, published);
  const verifierChanges = cplFixtureDifferences(published, live);
  const reviewedVerifierChanges = verifierChanges.filter((change) => isReviewedException(change, fallback));
  const unreviewedVerifierChanges = verifierChanges.filter((change) => !isReviewedException(change, fallback));
  requireValue(unreviewedVerifierChanges.length === 0, `${unreviewedVerifierChanges.length} current-verifier change(s) need human review; no schedule was overwritten.`);
  const manifest = authoritativeChanges.length === 0 ? fallback : {
    ...fallback,
    revision: now.toISOString(),
    checkedAt: now.toISOString().replace(/\.\d{3}Z$/, "Z"),
    fixtures: published,
  };
  validateCPLManifest(manifest);
  return { manifest, authoritativeChanges, reviewedVerifierChanges };
}
