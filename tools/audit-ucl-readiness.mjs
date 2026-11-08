#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  supportedUCLSourceCodes,
  usableWorkerVariantCount,
} from "./audit-ucl-readiness-policy.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(await readFile(
  resolve(root, "shared/reference-data/football-competitions-2026-27.json"),
  "utf8",
));
const championsLeague = manifest.competitions.find((item) => item.id === "championsLeague");
if (!championsLeague) throw new Error("The reviewed Champions League catalog is missing.");

const valueFor = (name, fallback) => {
  const prefix = `--${name}=`;
  const argument = process.argv.find((value) => value.startsWith(prefix));
  return argument ? argument.slice(prefix.length) : fallback;
};
const now = new Date(valueFor("at", new Date().toISOString()));
const horizonHours = Number(valueFor("horizon-hours", "72"));
const strictWithinMinutes = Number(valueFor("strict-within-minutes", "30"));
const requireAll = process.argv.includes("--require-all");
const resolveVariants = process.argv.includes("--resolve");
if (!Number.isFinite(now.valueOf())) throw new Error("--at must be an ISO-8601 date.");
if (!Number.isFinite(horizonHours) || horizonHours <= 0 || horizonHours > 168) {
  throw new Error("--horizon-hours must be between 0 and 168.");
}
if (!Number.isFinite(strictWithinMinutes) || strictWithinMinutes < 0 || strictWithinMinutes > 360) {
  throw new Error("--strict-within-minutes must be between 0 and 360.");
}

const fixtureURL = process.env.FOTTY_FOOTBALL_FIXTURE_URL
  || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api/football/matches";
const streamURL = process.env.FOTTY_STREAM_LOOKUP_URL
  || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api/live/streams";
const providerURLs = [
  "https://www.streamex.net/api/live/matches/all",
  "https://streamex.sh/api/live/matches/all",
  "https://streamed.pk/api/matches/all",
];
const supportedSources = new Set(supportedUCLSourceCodes);
const ignoredTokens = new Set([
  "fc", "afc", "cf", "ac", "club", "sc", "sv", "rc", "rcd", "ud", "losc",
  "ogc", "estac", "stade", "olympique", "and",
]);

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function normalizedKey(value) {
  return String(value || "").normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase()
    .split(/[^a-z0-9]+/).filter((token) => token && !ignoredTokens.has(token))
    .map((token) => token === "utd" ? "united" : token).join("");
}

const aliases = new Map();
for (const club of championsLeague.clubs) {
  const canonical = normalizedKey(club.name);
  for (const value of [club.name, ...club.aliases]) {
    const key = normalizedKey(value);
    const existing = aliases.get(key);
    requireValue(!existing || existing === canonical, `Champions League alias collision for ${value}.`);
    aliases.set(key, canonical);
  }
}

function canonicalClub(value) {
  return aliases.get(normalizedKey(value));
}

function eventTeams(event) {
  return {
    home: event.teams?.home?.name?.trim() || "",
    away: event.teams?.away?.name?.trim() || "",
  };
}

function eventKickoff(event) {
  const value = Number(event.date);
  return new Date(value > 10_000_000_000 ? value : value * 1000);
}

function sourceKey(source) {
  return `${String(source.source || "").toLowerCase()}|${source.id || ""}`;
}

async function fetchJSON(url, timeout = 15_000) {
  const response = await fetch(url, {
    headers: { Accept: "application/json", "User-Agent": "Fotty UCL readiness audit/1.0" },
    redirect: "error",
    signal: AbortSignal.timeout(timeout),
  });
  requireValue(response.ok, `${new URL(url).host} returned HTTP ${response.status}.`);
  return response.json();
}

async function fixtureSchedule() {
  const season = now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1;
  const url = new URL(fixtureURL);
  url.searchParams.set("competition", "CL");
  url.searchParams.set("season", String(season));
  const body = await fetchJSON(url);
  requireValue(body?.competition?.code === "CL", "The fixture service returned the wrong competition.");
  requireValue(Array.isArray(body.matches) && body.matches.length > 0, "The Champions League schedule is empty.");
  return body.matches;
}

async function providerCatalog() {
  const snapshots = await Promise.all(providerURLs.map(async (url) => {
    try {
      const body = await fetchJSON(url, 8_000);
      const events = Array.isArray(body) ? body : body.matches;
      requireValue(Array.isArray(events), `${new URL(url).host} did not return an event array.`);
      return events;
    } catch (error) {
      console.warn(`Provider metadata unavailable (${new URL(url).host}): ${error.message}`);
      return [];
    }
  }));
  requireValue(snapshots.some((events) => events.length > 0), "No provider metadata endpoint was reachable.");

  const byID = new Map();
  for (const event of snapshots.flat()) {
    if (String(event.category || "").toLowerCase() !== "football" || !event.id) continue;
    const existing = byID.get(event.id);
    if (!existing) {
      byID.set(event.id, event);
      continue;
    }
    const sources = [...(existing.sources || []), ...(event.sources || [])];
    const unique = [...new Map(sources.map((source) => [sourceKey(source), source])).values()];
    byID.set(event.id, { ...existing, sources: unique });
  }
  return [...byID.values()];
}

function matchingProviderEvents(match, events) {
  const officialHome = canonicalClub(match.homeTeam?.name);
  const officialAway = canonicalClub(match.awayTeam?.name);
  requireValue(officialHome && officialAway, `Official club identity is unreviewed: ${match.homeTeam?.name} vs ${match.awayTeam?.name}.`);
  const kickoff = new Date(match.utcDate);
  return events.filter((event) => {
    const teams = eventTeams(event);
    const providerKickoff = eventKickoff(event);
    return canonicalClub(teams.home) === officialHome
      && canonicalClub(teams.away) === officialAway
      && Number.isFinite(providerKickoff.valueOf())
      && Math.abs(providerKickoff.valueOf() - kickoff.valueOf()) <= 15 * 60 * 1000;
  });
}

const variantCache = new Map();
async function variantCount(events) {
  const sources = [...new Map(events.flatMap((event) => event.sources || [])
    .filter((source) => supportedSources.has(String(source.source || "").toLowerCase()))
    .map((source) => [sourceKey(source), source])).values()];
  if (!resolveVariants) return sources.length;
  let count = 0;
  for (const source of sources) {
    const key = sourceKey(source);
    if (!variantCache.has(key)) {
      const lookup = new URL(streamURL);
      lookup.searchParams.set("source", source.source);
      lookup.searchParams.set("id", source.id);
      variantCache.set(key, fetchJSON(lookup, 10_000)
        .then(usableWorkerVariantCount)
        .catch(() => 0));
    }
    count += await variantCache.get(key);
  }
  return count;
}

try {
  const [matches, events] = await Promise.all([fixtureSchedule(), providerCatalog()]);
  const start = now.valueOf() - 3 * 60 * 60 * 1000;
  const end = now.valueOf() + horizonHours * 60 * 60 * 1000;
  const windowMatches = matches.filter((match) => {
    const kickoff = Date.parse(match.utcDate);
    return kickoff >= start && kickoff <= end;
  }).sort((left, right) => Date.parse(left.utcDate) - Date.parse(right.utcDate));

  const rows = [];
  for (const match of windowMatches) {
    const providers = matchingProviderEvents(match, events);
    rows.push({
      fixture: `${match.homeTeam.name} vs ${match.awayTeam.name}`,
      kickoff: match.utcDate,
      providerRows: providers.length,
      variants: await variantCount(providers),
    });
  }

  const failures = rows.filter((row) => {
    const minutesUntil = (Date.parse(row.kickoff) - now.valueOf()) / 60_000;
    const strict = requireAll || (minutesUntil >= -180 && minutesUntil <= strictWithinMinutes);
    return strict && row.variants === 0;
  });
  const missing = rows.filter((row) => row.providerRows === 0);
  const duplicates = rows.filter((row) => row.providerRows > 1);
  const resolved = rows.filter((row) => row.variants > 0);

  console.log(`UCL readiness at ${now.toISOString()}: ${windowMatches.length} official fixture(s) inside ${horizonHours}h.`);
  console.log(`${resolved.length} fixture(s) have ${resolveVariants ? "resolved" : "advertised"} supported variants; ${missing.length} are not in provider metadata yet.`);
  for (const row of rows) {
    console.log(`${row.kickoff} | ${row.fixture} | provider rows ${row.providerRows} | variants ${row.variants}`);
  }
  if (duplicates.length > 0) {
    console.warn(`Duplicate provider identities (collapsed by Fotty): ${duplicates.map((row) => row.fixture).join(", ")}`);
  }
  if (failures.length > 0) {
    throw new Error(`No usable source inside the strict window: ${failures.map((row) => row.fixture).join(", ")}`);
  }
  console.log(`Champions League readiness contract passed${requireAll ? " for the full requested window" : " for imminent fixtures"}.`);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
