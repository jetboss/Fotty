#!/usr/bin/env node

import { REGISTRY_HEADERS } from "./playback-probe.mjs";
import { boundedJSON } from "../web/workers/playback/src/coach-safety.mjs";
import { currentFixtureSources, hasUsableDescriptor } from "./audit-ucl-readiness-policy.mjs";

const valueFor = (name, fallback) => {
  const prefix = `--${name}=`;
  const argument = process.argv.find((value) => value.startsWith(prefix));
  return argument ? argument.slice(prefix.length) : fallback;
};
const now = new Date(valueFor("at", new Date().toISOString()));
const horizonHours = Number(valueFor("horizon-hours", "72"));
const strictWithinMinutes = Number(valueFor("strict-within-minutes", "30"));
const requireAll = process.argv.includes("--require-all");
const resolveDescriptors = process.argv.includes("--resolve");
if (!Number.isFinite(now.valueOf())) throw new Error("--at must be an ISO-8601 date.");
if (!Number.isFinite(horizonHours) || horizonHours <= 0 || horizonHours > 168) {
  throw new Error("--horizon-hours must be between 0 and 168.");
}
if (!Number.isFinite(strictWithinMinutes) || strictWithinMinutes < 0 || strictWithinMinutes > 360) {
  throw new Error("--strict-within-minutes must be between 0 and 360.");
}

const fixtureURL = process.env.FOTTY_FOOTBALL_FIXTURE_URL
  || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api/football/matches";
const registryURL = process.env.FOTTY_BROADCAST_REGISTRY_URL
  || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev/api/live/broadcasts";

async function readJSON(url, maxBytes, headers = {}) {
  const signal = AbortSignal.timeout(10_000);
  const response = await fetch(url, { headers: { Accept: "application/json", "User-Agent": "Fotty UCL readiness audit/2.0", ...headers },
    redirect: "error", signal });
  if (!response.ok) throw new Error(`${new URL(url).host} returned HTTP ${response.status}.`);
  if (!/^application\/(?:[\w.+-]+\+)?json\b/i.test(response.headers.get("content-type") ?? "")) throw new Error("Expected JSON.");
  return boundedJSON(response, maxBytes, signal);
}

async function checkReadiness() {
  const url = new URL(fixtureURL);
  url.searchParams.set("competition", "CL");
  url.searchParams.set("season", String(now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1));
  const schedule = await readJSON(url, 2 * 1024 * 1024);
  if (schedule.competition?.code !== "CL" || !Array.isArray(schedule.matches) || !schedule.matches.length) {
    throw new Error("The official Champions League schedule is unavailable.");
  }
  const terminal = new Set(["FINISHED", "AWARDED", "CANCELLED", "POSTPONED", "SUSPENDED"]);
  const ids = new Set();
  const matches = schedule.matches.filter((match) => {
    const start = Date.parse(match.utcDate);
    if (!Number.isSafeInteger(match.id) || ids.has(match.id) || !Number.isFinite(start)
      || !match.homeTeam?.name || !match.awayTeam?.name) throw new Error("Invalid or duplicate official fixture.");
    ids.add(match.id);
    return !terminal.has(match.status) && start >= +now - 3 * 3600_000 && start <= +now + horizonHours * 3600_000;
  }).sort((a, b) => Date.parse(a.utcDate) - Date.parse(b.utcDate));
  console.log(`${matches.length} upcoming or in-progress Champions League fixtures in the requested window.`);
  if (!matches.length) return;

  const registry = await readJSON(registryURL, 4 * 1024 * 1024, {
    ...REGISTRY_HEADERS, "X-Fotty-TV-Guide": "reviewedtv-guide-v1",
  });
  const generated = Date.parse(registry.generatedAt);
  if (registry.schemaVersion !== 1 || !Number.isFinite(generated) || generated > +now + 300_000
    || generated < +now - 30 * 60_000 || !Array.isArray(registry.broadcasts) || !Array.isArray(registry.links)) {
    throw new Error("The current broadcast registry is unavailable or stale.");
  }
  const cache = new Map(), missing = [];
  let due = 0;
  for (const match of matches) {
    const { descriptors, deviceStations } = currentFixtureSources(registry, match, +now);
    const strict = requireAll || Date.parse(match.utcDate) <= +now + strictWithinMinutes * 60_000;
    let ready = !resolveDescriptors && deviceStations.size > 0;
    if (strict) {
      due++;
      for (const descriptor of descriptors.keys()) {
        if (!resolveDescriptors) { ready = true; break; }
        if (!cache.has(descriptor)) {
          if (cache.size >= 24) throw new Error("Descriptor check limit reached before readiness was established.");
          try { cache.set(descriptor, hasUsableDescriptor(await readJSON(descriptor, 256 * 1024))); }
          catch { cache.set(descriptor, false); }
        }
        if (cache.get(descriptor)) { ready = true; break; }
      }
    }
    const title = match.homeTeam.name + " vs " + match.awayTeam.name;
    const result = !strict ? "outside strict window" : ready ? (resolveDescriptors ? "usable descriptor" : "listed") : "no qualifying source";
    console.log(`${match.utcDate} | ${title} | ${descriptors.size} public descriptor(s), ${deviceStations.size} device-only TV assignment(s) | ${result}`);
    if (strict && !ready) missing.push(title);
  }
  if (missing.length) throw new Error("No qualifying source for " + missing.join(", ") + ".");
  console.log(`${due} fixture(s) due for the strict check.`);
}

try { await checkReadiness(); }
catch (error) { console.error(error.message); process.exitCode = 1; }
