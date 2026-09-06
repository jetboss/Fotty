#!/usr/bin/env node

const baseURL = process.env.FOTTY_FOOTBALL_FIXTURE_URL
  || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api/football/matches";
const now = new Date();
const season = now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1;
const competitions = ["PL", "CL"];

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

async function auditCompetition(code) {
  const url = new URL(baseURL);
  url.searchParams.set("competition", code);
  url.searchParams.set("season", String(season));
  const response = await fetch(url, {
    headers: { Accept: "application/json", "User-Agent": "Fotty fixture monitor/1.0" },
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
  requireValue(response.ok, `${code} fixture feed returned HTTP ${response.status}.`);
  const bodyText = await response.text();
  requireValue(bodyText.length <= 5_000_000, `${code} fixture feed exceeded 5 MB.`);
  const body = JSON.parse(bodyText);
  requireValue(body?.competition?.code === code, `${code} response has the wrong competition.`);
  requireValue(body?.filters?.season === season, `${code} response has the wrong season.`);
  requireValue(Array.isArray(body.matches) && body.matches.length > 0, `${code} response has no fixtures.`);

  const ids = new Set();
  for (const match of body.matches) {
    requireValue(Number.isInteger(match.id) && !ids.has(match.id), `${code} has a missing or duplicate fixture id.`);
    ids.add(match.id);
    const kickoff = new Date(match.utcDate);
    requireValue(Number.isFinite(kickoff.valueOf()), `${code} fixture ${match.id} has an invalid kickoff.`);
    requireValue(
      kickoff.getUTCFullYear() === season || kickoff.getUTCFullYear() === season + 1,
      `${code} fixture ${match.id} is outside season ${season}.`,
    );
    requireValue(match.competition?.code === code, `${code} fixture ${match.id} is misclassified.`);
    requireValue(match.homeTeam?.name?.trim() && match.awayTeam?.name?.trim(), `${code} fixture ${match.id} has missing teams.`);
  }
  const ordered = [...body.matches].sort((left, right) => Date.parse(left.utcDate) - Date.parse(right.utcDate));
  console.log(`${code} ${season}/${season + 1}: ${body.matches.length} fixtures, ${ordered[0].utcDate} through ${ordered.at(-1).utcDate}.`);
}

try {
  for (const competition of competitions) await auditCompetition(competition);
  console.log("Premier League and Champions League fixture feeds passed the live freshness contract.");
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
