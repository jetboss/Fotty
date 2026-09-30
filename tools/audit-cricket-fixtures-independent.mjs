const months = Object.freeze({ Jan: 1, Feb: 2, Mar: 3, Apr: 4, May: 5, Jun: 6, Jul: 7, Aug: 8, Sep: 9, Oct: 10, Nov: 11, Dec: 12 });
const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const durationHours = Object.freeze({ T10: 4, T20: 8, ODI: 12 });
const minute = 60_000;
const textEntities = Object.freeze({ "&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&apos;": "'", "&quot;": '"' });

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function textContent(value) {
  const visible = value.replace(/<[^>]*>/g, " ");
  // Decode once: &amp;nbsp; is literal &nbsp; text, not a second entity.
  return visible.replace(/&(?:amp|nbsp|#39|apos|quot);/g, (entity) => textEntities[entity])
    .replace(/\s+/g, " ").trim();
}

function maskHTMLComments(html) {
  const parts = [];
  let cursor = 0;
  while (true) {
    const start = html.indexOf("<!--", cursor);
    if (start === -1) {
      parts.push(html.slice(cursor));
      return parts.join("");
    }
    const end = html.indexOf("-->", start + 4);
    requireValue(end !== -1, "An independent fixture comment is unterminated.");
    parts.push(html.slice(cursor, start), " ".repeat(end + 3 - start));
    cursor = end + 3;
  }
}

function contentForClass(html, className) {
  const pattern = new RegExp(`<div\\b[^>]*class=["']${className}["'][^>]*>([\\s\\S]*?)<\\/div>`, "g");
  return [...html.matchAll(pattern)].map((match) => textContent(match[1]));
}

function fixtureFormat(value) {
  if (/\bT20I?\b/i.test(value)) return "T20";
  if (/\bT10\b/i.test(value)) return "T10";
  if (/\bODI\b/i.test(value)) return "ODI";
  if (/\bTest\b/i.test(value)) return "TEST";
  throw new Error("An independent fixture format is unrecognized.");
}

// CWI supplies both AST and UTC, but the calendar-heading timezone is not
// documented. Same-day clocks are unambiguous; cross-midnight dates need review.
function fixtureStart(date, time) {
  const parsed = /^(\d{2}):(\d{2}) AST \((\d{2}):(\d{2}) UTC\)$/.exec(time);
  requireValue(parsed, "An independent fixture UTC time is missing.");
  const [, astHour, astMinute, utcHour, utcMinute] = parsed.map(Number);
  requireValue(astHour < 24 && utcHour < 24 && astMinute < 60 && utcMinute < 60, "An independent fixture clock is invalid.");
  const localMinutes = astHour * 60 + astMinute;
  const utcMinutes = utcHour * 60 + utcMinute;
  requireValue((utcMinutes - localMinutes + 1440) % 1440 === 240, "Independent fixture UTC and AST clocks disagree.");
  requireValue(utcMinutes >= localMinutes, "Independent fixture calendar-heading timezone is ambiguous.");
  const instant = new Date(`${date}T00:00:00.000Z`).valueOf() + utcMinutes * minute;
  return new Date(instant).toISOString();
}

export function parseIndependentCWIInternationalFixtures(html) {
  requireValue(typeof html === "string" && Buffer.byteLength(html) <= 1024 * 1024, "Independent fixture HTML exceeded the size limit.");
  // Preserve separators and offsets; this is lexical comparison, not HTML output.
  html = maskHTMLComments(html);
  if (/\btemplate-fixturesindexpage\b/.test(html) && /<div\s+class=["']row wi-fixtures["']>\s*<\/div>/.test(html)) return [];
  const tokens = [...html.matchAll(/<h3>\s*<span>\s*(Sun|Mon|Tue|Wed|Thu|Fri|Sat)\s+(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*<\/span>\s*(\d{4})\s*<\/h3>|<div\s+class=["']wi-fixture["']\s*>/g)];
  requireValue(tokens.some((token) => token[1]) && tokens.some((token) => !token[1]), "Independent fixture page structure was not recognized.");
  const fixtures = [];
  const ids = new Set();
  let date;
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token[1]) {
      date = `${token[4]}-${String(months[token[3]]).padStart(2, "0")}-${token[2].padStart(2, "0")}`;
      const parsedDate = new Date(`${date}T00:00:00.000Z`);
      requireValue(Number.isFinite(parsedDate.valueOf()) && parsedDate.toISOString().slice(0, 10) === date
        && weekdays[parsedDate.getUTCDay()] === token[1], "An independent fixture calendar date is invalid.");
      continue;
    }
    requireValue(date, "An independent fixture date group is missing.");
    const block = html.slice(token.index + token[0].length, tokens[index + 1]?.index ?? html.length);
    const teamNames = contentForClass(block, "wi-fixture-team-name");
    const titles = contentForClass(block, "wi-fixture-title");
    const times = contentForClass(block, "wi-fixture-time-inner");
    const matchIds = [...new Set([...block.matchAll(/https:\/\/matchcentre\.windiescricket\.com\/match\/([0-9a-f-]{36})(?:["'\s]|$)/g)].map((match) => match[1]))];
    requireValue(teamNames.length === 2 && teamNames.every((name) => name.length > 0 && name.length <= 256)
      && teamNames[0] !== teamNames[1] && titles.length === 1 && times.length === 1 && matchIds.length === 1,
    "An independent fixture is incomplete or ambiguous.");
    requireValue(!ids.has(matchIds[0]), "Independent fixture identities are duplicated.");
    ids.add(matchIds[0]);
    fixtures.push({
      id: matchIds[0],
      start: fixtureStart(date, times[0]),
      format: fixtureFormat(titles[0]),
      status: contentForClass(block, "wi-fixture-live-text").includes("Live") ? "live" : "scheduled",
      home: { name: teamNames[0] },
      away: { name: teamNames[1] },
    });
  }
  requireValue(fixtures.length > 0 && fixtures.length <= 500, "The independent fixture page did not yield a bounded schedule.");
  return fixtures;
}

function canonicalTeamName(value) {
  let normalized = String(value).normalize("NFKD").replace(/\p{Diacritic}/gu, "").toLowerCase()
    .replace(/women['’]?s?\b/g, "women").replace(/under[ -]?19\b/g, "u19").replace(/[^a-z0-9]/g, "");
  const aliases = { wi: "westindies", windies: "westindies", ind: "india" };
  for (const suffix of ["", "women", "u19", "a"]) {
    for (const [alias, canonical] of Object.entries(aliases)) {
      if (normalized === alias + suffix) normalized = canonical + suffix;
    }
  }
  return normalized;
}

function teamPair(fixture) {
  return [canonicalTeamName(fixture.home.name), canonicalTeamName(fixture.away.name)].sort().join("|");
}

export function independentCurrentFixtures(fixtures, now) {
  return fixtures.filter((fixture) => {
    const start = Date.parse(fixture.start);
    if (fixture.status === "live") return true;
    const hours = durationHours[String(fixture.format).toUpperCase()];
    return hours !== undefined && start <= now + 30 * minute && start >= now - hours * 60 * minute;
  });
}

export function auditIndependentCricketCoverage(body, independentFixtures, { now = Date.now() } = {}) {
  const expected = independentCurrentFixtures(independentFixtures, now);
  const findings = new Map();
  let matchedCount = 0;
  for (const fixture of expected) {
    const format = String(fixture.format).toUpperCase();
    const match = body.fixtures.filter((row) => ["west-indies", "icc"].includes(row.competitionId)
      && String(row.format).toUpperCase() === format && teamPair(row) === teamPair(fixture)
      && Math.abs(Date.parse(row.start) - Date.parse(fixture.start)) <= 60 * minute)
      .sort((left, right) => Math.abs(Date.parse(left.start) - Date.parse(fixture.start))
        - Math.abs(Date.parse(right.start) - Date.parse(fixture.start)))[0];
    if (!match) {
      findings.set("independent-current-omission", { code: "independent-current-omission", actionable: true });
      continue;
    }
    matchedCount += 1;
    if (Math.abs(Date.parse(match.start) - Date.parse(fixture.start)) > 15 * minute) {
      findings.set("independent-kickoff-disagreement", { code: "independent-kickoff-disagreement", actionable: true });
    }
    if (fixture.status === "live" && match.status !== "live") {
      // Official sources can lag each other briefly at the toss/full-time.
      // Report the disagreement, but notify only if the next hourly audit repeats it.
      findings.set("independent-status-disagreement", { code: "independent-status-disagreement", actionable: false });
    }
  }
  return { expectedCurrentCount: expected.length, matchedCurrentCount: matchedCount, findings: [...findings.values()] };
}
