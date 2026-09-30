const teamAliases = new Map([
  ["antigua and barbuda falcons", "antigua"], ["antigua & barbuda falcons", "antigua"],
  ["barbados tridents", "barbados"], ["barbados royals", "barbados"],
  ["guyana amazon warriors", "guyana"], ["jamaica kingsmen", "jamaica"],
  ["saint lucia kings", "saintLucia"], ["st lucia kings", "saintLucia"],
  ["st kitts and nevis patriots", "stKitts"], ["st kitts & nevis patriots", "stKitts"],
  ["trinbago knight riders", "trinbago"],
]);
const teamKeys = new Set(teamAliases.values());
const cplSeasonPolicies = new Map([[2026, Object.freeze({
  season: 2026,
  seriesId: 12123,
  live: "https://www.cricbuzz.com/cricket-series/12123/caribbean-premier-league-2026/matches",
  published: "https://cplt20.prezly.com/republic-bank-cpl-fixtures-confirmed-for-2026",
  correction: "https://wp.cplt20.com/wp-json/wp/v2/news/20232",
  monthNumbers: new Map([["Aug", "08"], ["Sep", "09"]]),
  applyReviewedCorrections(fixtures, correctionJSON) {
    const correction = plainText(correctionJSON.acf?.description ?? correctionJSON.content?.rendered ?? "");
    requireValue(correction.includes("Jamaica Kingsmen now playing") && correction.includes("Saturday 29 August") && correction.includes("Guyana Amazon Warriors on Monday 31 August"), "The official 27 July opponent correction could not be verified.");
    fixtures[19] = { ...fixtures[19], team1: "trinbago", team2: "jamaica" };
    fixtures[21] = { ...fixtures[21], team1: "trinbago", team2: "guyana" };
  },
})]]);

export const cplFixtureSources = Object.freeze({
  live: cplSeasonPolicies.get(2026).live,
  published: cplSeasonPolicies.get(2026).published,
  correction: cplSeasonPolicies.get(2026).correction,
});

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function normalizeTeam(name) {
  return teamAliases.get(name.trim().toLowerCase());
}

function isPendingParticipant(name) {
  const normalized = name.trim().toLowerCase();
  return normalized === "tbc" || normalized.includes("to be confirmed")
    || normalized.includes("winner") || normalized.includes("loser")
    || normalized.includes("qualifier") || normalized.includes("eliminator");
}

export function validateCPLManifest(manifest) {
  const currentYear = new Date().getUTCFullYear();
  requireValue(manifest.schemaVersion === 1, "CPL manifest schemaVersion must be 1.");
  requireValue(manifest.competitionId === "cpl" && Number.isInteger(manifest.season)
    && manifest.season >= currentYear - 1 && manifest.season <= currentYear + 2,
  "CPL manifest has the wrong competition or season.");
  requireValue(Number.isFinite(Date.parse(manifest.checkedAt)), "CPL manifest checkedAt must be ISO-8601.");
  requireValue(Array.isArray(manifest.sources) && manifest.sources.length >= 2, "CPL manifest needs published and current verification sources.");
  requireValue(Array.isArray(manifest.verificationExceptions), "CPL manifest verificationExceptions must be an array.");
  requireValue(Array.isArray(manifest.fixtures) && manifest.fixtures.length >= 2 && manifest.fixtures.length <= 100, "CPL manifest has an invalid fixture count.");
  if (manifest.fixtureCount != null) {
    requireValue(Number.isInteger(manifest.fixtureCount) && manifest.fixtureCount === manifest.fixtures.length, "CPL manifest fixture count does not match its declared count.");
  }

  const numbers = new Set();
  const upstreamIDs = new Set();
  const stages = new Set();
  let teamFixtureCount = 0;
  let previousStart = 0;
  for (const fixture of manifest.fixtures) {
    requireValue(Number.isInteger(fixture.number) && fixture.number >= 1 && fixture.number <= manifest.fixtures.length, `Invalid fixture number ${fixture.number}.`);
    requireValue(!numbers.has(fixture.number), `Duplicate fixture number ${fixture.number}.`);
    numbers.add(fixture.number);
    requireValue(typeof fixture.upstreamId === "string" && /^\d+$/.test(fixture.upstreamId), `Fixture ${fixture.number} has no stable upstream id.`);
    requireValue(!upstreamIDs.has(fixture.upstreamId), `Duplicate upstream id ${fixture.upstreamId}.`);
    upstreamIDs.add(fixture.upstreamId);
    const start = Date.parse(fixture.start);
    requireValue(Number.isFinite(start) && new Date(start).getUTCFullYear() === manifest.season, `Fixture ${fixture.number} has an invalid start.`);
    requireValue(start >= previousStart, `Fixture ${fixture.number} is out of chronological order.`);
    previousStart = start;
    if (fixture.team1 !== undefined || fixture.team2 !== undefined) {
      const displayName = (key) => teamKeys.has(key) ? key : manifest.teamNames?.[key];
      const team1 = displayName(fixture.team1);
      const team2 = displayName(fixture.team2);
      requireValue(typeof team1 === "string" && typeof team2 === "string"
        && team1.trim().length >= 2 && team1.length <= 64
        && team2.trim().length >= 2 && team2.length <= 64
        && fixture.team1 !== fixture.team2,
      `Fixture ${fixture.number} has invalid teams.`);
      if (fixture.stage !== undefined) {
        requireValue(typeof fixture.stage === "string" && fixture.stage.trim().length > 0 && fixture.stage.length <= 64, `Fixture ${fixture.number} has the wrong playoff stage.`);
        requireValue(!stages.has(fixture.stage.toLowerCase()), `Fixture ${fixture.number} duplicates a playoff stage.`);
        stages.add(fixture.stage.toLowerCase());
      }
      teamFixtureCount++;
    } else {
      requireValue(typeof fixture.stage === "string" && fixture.stage.trim().length > 0 && fixture.stage.length <= 64, `Fixture ${fixture.number} has the wrong playoff stage.`);
      requireValue(!stages.has(fixture.stage.toLowerCase()), `Fixture ${fixture.number} duplicates a playoff stage.`);
      stages.add(fixture.stage.toLowerCase());
      requireValue(fixture.team1 === undefined && fixture.team2 === undefined, `Playoff fixture ${fixture.number} must not invent participants.`);
    }
  }
  requireValue(teamFixtureCount > 0, "CPL manifest must contain team fixtures.");
  requireValue([...numbers].sort((a, b) => a - b).every((number, index) => number === index + 1), "CPL fixture numbers must be contiguous.");
  for (const exception of manifest.verificationExceptions) {
    requireValue(numbers.has(exception.number), `Verification exception references unknown fixture ${exception.number}.`);
    requireValue(["start", "teams", "upstreamId", "stage"].includes(exception.field), `Fixture ${exception.number} has an invalid exception field.`);
    requireValue(typeof exception.expected === "string" && typeof exception.observed === "string" && exception.reason?.length > 20, `Fixture ${exception.number} has an incomplete verification exception.`);
  }
}

function plainText(html) {
  // Decode each supported entity once. Ampersand must be last so input such
  // as `&amp;#8211;` cannot be recursively decoded into a different character.
  return html.replaceAll("&#8211;", "-").replaceAll("&#8217;", "'")
    .replaceAll("&nbsp;", " ").replaceAll("&amp;", "&")
    .replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

export function parseCPLLiveSchedule(html, fallback) {
  const policy = cplSeasonPolicies.get(fallback.season);
  requireValue(policy, `CPL season ${fallback.season} has no reviewed source adapter.`);
  const stagesByName = new Map(fallback.fixtures.filter((fixture) => fixture.stage).map((fixture) => [fixture.stage, fixture.number]));
  const decoded = html.replaceAll('\\"', '"');
  const pattern = /"matchId":(\d+),"seriesId":(\d+),"seriesName":"[^"]+","matchDesc":"([^"]+)","matchFormat":"T20","startDate":"(\d+)"[\s\S]*?"team1":\{"teamId":\d+,"teamName":"([^"]+)"[\s\S]*?"team2":\{"teamId":\d+,"teamName":"([^"]+)"/g;
  const byUpstreamID = new Map();
  for (const match of decoded.matchAll(pattern)) {
    const [, upstreamId, seriesId, description, startMilliseconds, rawTeam1, rawTeam2] = match;
    if (Number(seriesId) !== policy.seriesId) continue;
    if (byUpstreamID.has(upstreamId)) continue;
    const numbered = description.match(/^(\d+)(?:st|nd|rd|th) Match$/);
    const stage = numbered ? undefined : description;
    const number = numbered ? Number(numbered[1]) : stagesByName.get(stage);
    requireValue(number !== undefined, `Unknown live CPL match description: ${description}.`);
    const fixture = { number, upstreamId, start: new Date(Number(startMilliseconds)).toISOString().replace(".000Z", "Z") };
    const team1 = normalizeTeam(rawTeam1);
    const team2 = normalizeTeam(rawTeam2);
    if (numbered) {
      requireValue(team1 && team2, `Fixture ${number} contains an unknown live team: ${rawTeam1} / ${rawTeam2}.`);
      fixture.team1 = team1;
      fixture.team2 = team2;
    } else {
      fixture.stage = stage;
      if (team1 && team2) {
        fixture.team1 = team1;
        fixture.team2 = team2;
      } else {
        requireValue(
          (team1 || isPendingParticipant(rawTeam1)) && (team2 || isPendingParticipant(rawTeam2)),
          `Fixture ${number} contains an unknown playoff participant: ${rawTeam1} / ${rawTeam2}.`,
        );
      }
    }
    byUpstreamID.set(upstreamId, fixture);
  }
  const fixtures = [...byUpstreamID.values()].sort((a, b) => a.number - b.number);
  requireValue(fixtures.length === fallback.fixtures.length, `Live CPL response yielded ${fixtures.length} fixtures instead of ${fallback.fixtures.length}.`);
  return fixtures;
}

export function parseCPLPublishedSchedule(html, correctionJSON, upstreamFixtures, fallback) {
  const policy = cplSeasonPolicies.get(fallback.season);
  requireValue(policy, `CPL season ${fallback.season} has no reviewed source adapter.`);
  const stageByNumber = new Map(fallback.fixtures.filter((fixture) => fixture.stage).map((fixture) => [fixture.number, fixture.stage]));
  const rows = [...html.matchAll(/<tr class="prezly-slate-table-row">([\s\S]*?)<\/tr>/g)]
    .map((row) => [...row[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map((cell) => plainText(cell[1])))
    .filter((cells) => cells.length === 4 && /^\w{3} \d{1,2} \w{3}$/.test(cells[0]));
  requireValue(rows.length === fallback.fixtures.length, `Official CPL page yielded ${rows.length} fixtures instead of ${fallback.fixtures.length}.`);
  const upstreamByNumber = new Map(upstreamFixtures.map((fixture) => [fixture.number, fixture.upstreamId]));
  const fixtures = rows.map((cells, index) => {
    const number = index + 1;
    const [, day, monthName] = cells[0].split(" ");
    const time = cells[2].match(/^(\d{1,2})(am|pm)$/i);
    requireValue(time && policy.monthNumbers.has(monthName), `Official fixture ${number} has an unreadable date or time.`);
    let hour = Number(time[1]) % 12;
    if (time[2].toLowerCase() === "pm") hour += 12;
    const offset = cells[3] === "Jamaica" ? "-05:00" : "-04:00";
    const localStart = `${policy.season}-${policy.monthNumbers.get(monthName)}-${day.padStart(2, "0")}T${String(hour).padStart(2, "0")}:00:00${offset}`;
    const fixture = { number, upstreamId: upstreamByNumber.get(number), start: new Date(localStart).toISOString().replace(".000Z", "Z") };
    requireValue(fixture.upstreamId, `Official fixture ${number} has no matched upstream id.`);
    if (!stageByNumber.has(number)) {
      const [rawTeam1, rawTeam2] = cells[1].split(" vs ");
      fixture.team1 = normalizeTeam(rawTeam1 ?? "");
      fixture.team2 = normalizeTeam(rawTeam2 ?? "");
      requireValue(fixture.team1 && fixture.team2, `Official fixture ${number} contains an unknown team: ${cells[1]}.`);
    } else {
      fixture.stage = stageByNumber.get(number);
    }
    return fixture;
  });
  policy.applyReviewedCorrections(fixtures, correctionJSON);
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
    if (incoming.team1 !== undefined && !sameTeams(fixture, incoming)) changes.push({ number: incoming.number, field: "teams", expected: `${fixture.team1}/${fixture.team2}`, observed: `${incoming.team1}/${incoming.team2}`, message: `match ${incoming.number}: teams ${fixture.team1}/${fixture.team2} -> ${incoming.team1}/${incoming.team2}` });
    if (incoming.stage !== undefined && fixture.stage !== incoming.stage) changes.push({ number: incoming.number, field: "stage", expected: fixture.stage, observed: incoming.stage, message: `match ${incoming.number}: stage ${fixture.stage} -> ${incoming.stage}` });
  }
  return changes;
}

function isReviewedException(change, manifest) {
  return manifest.verificationExceptions.some((exception) => exception.number === change.number && exception.field === change.field && exception.expected === change.expected && exception.observed === change.observed);
}

export function resolveCPLManifest({ fallback, publishedHTML, correctionJSON, verifierHTML, now = new Date() }) {
  validateCPLManifest(fallback);
  const live = parseCPLLiveSchedule(verifierHTML, fallback);
  const published = parseCPLPublishedSchedule(publishedHTML, correctionJSON, live, fallback);
  const liveByNumber = new Map(live.map((fixture) => [fixture.number, fixture]));
  const verified = published.map((fixture) => {
    const current = liveByNumber.get(fixture.number);
    if (!fixture.stage || current?.stage !== fixture.stage || !current.team1 || !current.team2) return fixture;
    return { ...fixture, team1: current.team1, team2: current.team2 };
  });
  const authoritativeChanges = cplFixtureDifferences(fallback.fixtures, verified);
  const verifierChanges = cplFixtureDifferences(verified, live);
  const reviewedVerifierChanges = verifierChanges.filter((change) => isReviewedException(change, fallback));
  const unreviewedVerifierChanges = verifierChanges.filter((change) => !isReviewedException(change, fallback));
  requireValue(unreviewedVerifierChanges.length === 0, `${unreviewedVerifierChanges.length} current-verifier change(s) need human review; no schedule was overwritten.`);
  // `revision` describes the fixture content; `checkedAt` describes the most
  // recent successful multi-source verification. They must not move together:
  // an unchanged schedule can still have been verified moments ago.
  const verifiedAt = now.toISOString().replace(/\.\d{3}Z$/, "Z");
  const manifest = authoritativeChanges.length === 0 ? {
    ...fallback,
    checkedAt: verifiedAt,
  } : {
    ...fallback,
    revision: now.toISOString(),
    checkedAt: verifiedAt,
    fixtures: verified,
  };
  validateCPLManifest(manifest);
  return { manifest, authoritativeChanges, reviewedVerifierChanges };
}
