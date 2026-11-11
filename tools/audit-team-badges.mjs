#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const referencePath = path.join(root, "shared/reference-data/football-competitions-2026-27.json");
const timeoutMs = 30_000;
const concurrency = 8;
const sportsDBDelayMs = Number.parseInt(process.env.FOTTY_SPORTSDB_DELAY_MS ?? "1100", 10);
const footballESPNLeagues = [
  "eng.1", "esp.1", "ita.1", "ger.1", "fra.1",
  "uefa.champions", "uefa.europa", "aut.1", "nor.1", "isr.1"
];
let sportsDBQueue = Promise.resolve();
let nextSportsDBRequestAt = 0;
let sportsDBRequestCount = 0;

if (!Number.isFinite(sportsDBDelayMs) || sportsDBDelayMs < 250) {
  throw new Error("FOTTY_SPORTSDB_DELAY_MS must be an integer of at least 250ms.");
}

const normalize = (value = "") => value
  .normalize("NFKD")
  .replace(/[\u0300-\u036f]/g, "")
  .toLowerCase()
  .replace(/&/g, " and ")
  .replace(/[^a-z0-9]+/g, " ")
  .trim()
  .replace(/\s+/g, " ");

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function fetchJSON(url) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, { headers: { accept: "application/json" } });
      if (response.ok) return response.json();

      const error = new Error(`HTTP ${response.status}`);
      error.status = response.status;
      const retryAfter = Number.parseInt(response.headers.get("retry-after") ?? "", 10);
      error.retryAfterMs = Number.isFinite(retryAfter) ? retryAfter * 1_000 : null;
      const transient = response.status === 408 || response.status >= 500;
      if (!transient || attempt === 2) throw error;
    } catch (error) {
      const transient = error?.status === 408 || error?.status >= 500 || error?.name === "AbortError";
      if (!transient || attempt === 2) throw error;
    }

    await delay(1_000 * (attempt + 1));
  }

  throw new Error("Badge metadata request exhausted its retry budget.");
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function fetchSportsDBJSON(url) {
  const request = sportsDBQueue.then(async () => {
    const wait = Math.max(0, nextSportsDBRequestAt - Date.now());
    if (wait) await delay(wait);
    nextSportsDBRequestAt = Date.now() + sportsDBDelayMs;

    for (let attempt = 0; attempt < 4; attempt += 1) {
      try {
        const payload = await fetchJSON(url);
        sportsDBRequestCount += 1;
        if (sportsDBRequestCount % 25 === 0) {
          console.log(`Resolved ${sportsDBRequestCount} rate-limited SportsDB requests…`);
        }
        return payload;
      } catch (error) {
        if (error?.status !== 429 || attempt === 3) throw error;
        const retryDelay = error.retryAfterMs ?? (15_000 * (attempt + 1));
        console.warn(`SportsDB rate limit reached; pausing ${Math.ceil(retryDelay / 1000)}s before retry ${attempt + 2}/4…`);
        await delay(retryDelay);
        nextSportsDBRequestAt = Date.now() + sportsDBDelayMs;
      }
    }
    return {};
  });
  sportsDBQueue = request.catch(() => {});
  return request;
}

function imageSignature(bytes) {
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "png";
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";
  if (bytes.length >= 6 && String.fromCharCode(...bytes.slice(0, 6)).startsWith("GIF8")) return "gif";
  if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") return "webp";
  return null;
}

async function validateImage(url) {
  try {
    const response = await fetchWithTimeout(url, {
      headers: { accept: "image/*", range: "bytes=0-63" },
      redirect: "follow"
    });
    if (!response.ok) return { ok: false, reason: `HTTP ${response.status}` };
    const bytes = new Uint8Array(await response.arrayBuffer());
    const signature = imageSignature(bytes);
    const contentType = response.headers.get("content-type") ?? "";
    if (!signature && !contentType.toLowerCase().startsWith("image/")) {
      return { ok: false, reason: `not an image (${contentType || "unknown type"})` };
    }
    return { ok: true, format: signature ?? contentType.replace("image/", "") };
  } catch (error) {
    return { ok: false, reason: error instanceof Error ? error.message : String(error) };
  }
}

async function mapLimit(values, limit, transform) {
  const results = new Array(values.length);
  let next = 0;
  async function worker() {
    while (true) {
      const index = next++;
      if (index >= values.length) return;
      results[index] = await transform(values[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, worker));
  return results;
}

function sportsDBNames(team) {
  return [team.strTeam, team.strTeamShort, team.strTeamAlternate]
    .filter(Boolean)
    .flatMap((value) => String(value).split(/[,;/]/))
    .map(normalize)
    .filter(Boolean);
}

async function resolveSportsDBClub(club) {
  const accepted = new Set([club.name, ...(club.aliases ?? [])].map(normalize));
  let providerError = null;
  for (const query of [club.name, ...(club.aliases ?? [])]) {
    try {
      const url = new URL("https://www.thesportsdb.com/api/v1/json/3/searchteams.php");
      url.searchParams.set("t", query);
      const payload = await fetchSportsDBJSON(url);
      const match = (payload.teams ?? []).find((team) => sportsDBNames(team).some((name) => accepted.has(name)));
      if (match?.strBadge) {
        return { name: club.name, aliases: club.aliases ?? [], badgeURL: match.strBadge, providerName: match.strTeam ?? query };
      }
    } catch (error) {
      providerError = error instanceof Error ? error.message : String(error);
      // A later alias may still resolve. The final report keeps unresolved teams explicit.
    }
  }
  return { name: club.name, aliases: club.aliases ?? [], badgeURL: null, providerName: null, providerError };
}

async function espnLeague(sport, league, group = league.toUpperCase()) {
  const payload = await fetchJSON(`https://site.api.espn.com/apis/site/v2/sports/${sport}/${league}/teams?limit=100`);
  const teams = payload.sports?.[0]?.leagues?.[0]?.teams ?? [];
  return teams.map(({ team }) => ({
    name: team?.displayName ?? "Unknown team",
    badgeURL: team?.logos?.[0]?.href ?? null,
    providerName: team?.displayName ?? null,
    providerNames: [team?.displayName, team?.shortDisplayName, team?.name, team?.abbreviation, team?.slug].filter(Boolean),
    group
  }));
}

function resolveFromProviderTeams(club, providerTeams) {
  const accepted = new Set([club.name, ...(club.aliases ?? [])].map(normalize));
  const match = providerTeams.find((team) => team.providerNames?.some((name) => accepted.has(normalize(name))));
  if (!match?.badgeURL) return null;
  return {
    name: club.name,
    aliases: club.aliases ?? [],
    badgeURL: match.badgeURL,
    providerName: match.providerName,
    provider: "ESPN league catalog"
  };
}

async function sportsDBLeague(name, group) {
  const url = new URL("https://www.thesportsdb.com/api/v1/json/3/search_all_teams.php");
  url.searchParams.set("l", name);
  const payload = await fetchSportsDBJSON(url);
  return (payload.teams ?? []).map((team) => ({
    name: team.strTeam ?? "Unknown team",
    badgeURL: team.strBadge ?? null,
    providerName: team.strTeam ?? null,
    group
  }));
}

function uniqueFootballClubs(reference) {
  const byName = new Map();
  for (const competition of reference.competitions ?? []) {
    for (const club of competition.clubs ?? []) {
      const key = normalize(club.name);
      const existing = byName.get(key);
      const aliases = new Set([...(existing?.aliases ?? []), ...(club.aliases ?? [])]);
      byName.set(key, { name: existing?.name ?? club.name, aliases: [...aliases], groups: [...new Set([...(existing?.groups ?? []), competition.displayName])] });
    }
  }
  return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name));
}

function printFailures(title, rows, field = "reason") {
  if (!rows.length) return;
  console.log(`\n${title} (${rows.length})`);
  for (const row of rows) console.log(`- ${row.group ? `${row.group}: ` : ""}${row.name}: ${row[field] ?? "missing artwork"}`);
}

const reference = JSON.parse(await readFile(referencePath, "utf8"));
const football = uniqueFootballClubs(reference);
console.log(`Auditing ${football.length} unique source-controlled football clubs for ${reference.season}…`);

const footballProviderTeams = (await Promise.all(
  footballESPNLeagues.map((league) => espnLeague("soccer", league, `Football/${league}`))
)).flat();
const footballResolved = await mapLimit(football, concurrency, async (club) => (
  resolveFromProviderTeams(club, footballProviderTeams) ?? resolveSportsDBClub(club)
));
const providerGroups = await Promise.all([
  espnLeague("basketball", "nba"),
  espnLeague("basketball", "wnba"),
  espnLeague("baseball", "mlb"),
  espnLeague("hockey", "nhl"),
  sportsDBLeague("Caribbean Premier League", "CPL"),
  sportsDBLeague("Indian Premier League", "IPL")
]);

const allResolved = [
  ...footballResolved.map((club) => ({ ...club, group: "Football" })),
  ...providerGroups.flat()
];
const missing = allResolved.filter((team) => !team.badgeURL);
const providerFailures = missing.filter((team) => team.providerError);
const withArtwork = allResolved.filter((team) => team.badgeURL);
console.log(`Validating ${withArtwork.length} resolved artwork URLs without retaining image files…`);
const validated = await mapLimit(withArtwork, concurrency, async (team) => ({ ...team, ...(await validateImage(team.badgeURL)) }));
const broken = validated.filter((team) => !team.ok);

const urls = new Map();
for (const team of validated.filter((row) => row.ok)) {
  const teams = urls.get(team.badgeURL) ?? [];
  teams.push(team);
  urls.set(team.badgeURL, teams);
}
const sameKnownIdentity = (lhs, rhs) => {
  const lhsNames = new Set([lhs.name, ...(lhs.aliases ?? [])].map(normalize));
  return [rhs.name, ...(rhs.aliases ?? [])].map(normalize).some((name) => lhsNames.has(name));
};
const sharedArtwork = [...urls.entries()]
  .filter(([, teams]) => teams.length > 1)
  .map(([url, teams]) => ({
    name: teams.map((team) => `${team.group}: ${team.name}`).join(" / "),
    reason: url,
    isKnownAlias: teams.every((team, index) => index === 0 || sameKnownIdentity(teams[0], team))
  }));
const expectedSharedArtwork = sharedArtwork.filter((row) => row.isKnownAlias);
const suspiciousSharedArtwork = sharedArtwork.filter((row) => !row.isKnownAlias);

const groupSummary = new Map();
for (const team of allResolved) {
  const summary = groupSummary.get(team.group) ?? { total: 0, resolved: 0, valid: 0 };
  summary.total += 1;
  if (team.badgeURL) summary.resolved += 1;
  if (validated.some((row) => row.group === team.group && row.name === team.name && row.ok)) summary.valid += 1;
  groupSummary.set(team.group, summary);
}

console.log("\nBadge audit summary");
for (const [group, summary] of groupSummary) {
  console.log(`- ${group}: ${summary.valid}/${summary.total} valid images (${summary.resolved} resolved)`);
}
printFailures("Missing provider artwork; Fotty will use its monogram window", missing);
printFailures("Provider requests that did not complete", providerFailures, "providerError");
printFailures("Broken artwork URLs", broken);
if (expectedSharedArtwork.length) {
  console.log(`\nVerified ${expectedSharedArtwork.length} shared artwork URLs as source-controlled aliases of the same clubs.`);
}
printFailures("Suspicious shared artwork URLs requiring review", suspiciousSharedArtwork);

if (providerFailures.length) process.exitCode = 2;
else if (broken.length || suspiciousSharedArtwork.length) process.exitCode = 1;
