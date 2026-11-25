#!/usr/bin/env node

import { boundedJSON } from "../web/workers/playback/src/coach-safety.mjs";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  isCurrentCompetitionPair,
} from "../web/src/lib/football-competition-catalog.generated.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const vectorsPath = resolve(root, "shared/reference-data/provider-football-identity-vectors.json");
const isMain = Boolean(process.argv[1]) && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
const runLive = process.argv.includes("--live");
const allowUnavailable = process.argv.includes("--allow-unavailable");
const allowNoFootball = process.argv.includes("--allow-no-football");

const domestic = [
  ["premierLeague", ["premier league", "english premier", "premier-league", "epl"]],
  ["laLiga", ["la liga", "laliga", "la-liga"]],
  ["serieA", ["serie a", "serie-a"]],
  ["bundesliga", ["bundesliga"]],
  ["ligue1", ["ligue 1", "ligue-1", "ligue1"]],
];
const nonDomestic = [
  "premier league 2", "premier-league-2", "premier league cup", "premier-league-cup",
  "fa cup", "fa-cup", "efl cup", "efl-cup", "league cup", "carabao",
  "community shield", "championship", "league one", "league-one", "league two",
  "league-two", "bundesliga 2", "2. bundesliga", "copa del rey", "coppa italia", "dfb pokal", "coupe de france",
  "europa league", "conference league", "friendly", " u18", " u19", " u21", " u23",
  "women", "ladies", "youth", "academy", "reserves",
];

function containsAny(text, terms) {
  return terms.some((term) => text.includes(term));
}

function eventTeams(event) {
  if (event.teams?.home?.name && event.teams?.away?.name) {
    return { home: event.teams.home.name.trim(), away: event.teams.away.name.trim() };
  }
  const title = event.title || "";
  for (const separator of [" vs ", " v ", " @ ", " - "]) {
    const parts = title.split(separator);
    if (parts.length === 2) return { home: parts[0].trim(), away: parts[1].trim() };
  }
  return { home: "", away: "" };
}

function eventText(event) {
  const sourceIds = event.sourceIds ?? event.sources?.map((source) => source.id) ?? [];
  return [event.id, event.title, event.tournament, ...sourceIds].filter(Boolean).join(" ").toLowerCase();
}

function classify(event) {
  const text = eventText(event);
  const { home, away } = eventTeams(event);
  if (containsAny(text, ["champions league", "uefa champions", "champions-league", "ucl"])) {
    return { competition: "championsLeague", conflict: false };
  }
  for (const [competition, markers] of domestic) {
    if (!containsAny(text, markers)) continue;
    if (containsAny(text, nonDomestic)) return { competition: "other", conflict: false };
    const currentPair = isCurrentCompetitionPair(competition, home, away);
    return { competition: currentPair ? competition : "other", conflict: !currentPair };
  }
  if (containsAny(text, nonDomestic)) return { competition: "other", conflict: false };
  for (const [competition] of domestic) {
    if (isCurrentCompetitionPair(competition, home, away)) {
      return { competition, conflict: false };
    }
  }
  return { competition: "other", conflict: false };
}

// Counts football rows and identity conflicts. A row without a readable
// sport is counted as unreadable, never skipped: a renamed field once let
// the live audit "pass" while checking zero football listings.
export function auditProviderPayloads(payloads) {
  const failures = new Map();
  let footballCount = 0;
  let unreadableCount = 0;
  for (const payload of payloads) {
    for (const event of payload.events) {
      const sport = event?.sport ?? event?.category;
      if (typeof sport !== "string" || sport.trim() === "") { unreadableCount += 1; continue; }
      if (!["football", "soccer"].includes(sport.trim().toLowerCase())) continue;
      footballCount += 1;
      const text = eventText(event);
      const marker = domestic.find(([, markers]) => containsAny(text, markers));
      if (!marker || containsAny(text, nonDomestic)) continue;
      const result = classify(event);
      if (!result.conflict) continue;
      const { home, away } = eventTeams(event);
      const key = `${marker[0]}|${home}|${away}`;
      failures.set(key, { competition: marker[0], home, away, host: payload.host });
    }
  }
  return { footballCount, unreadableCount, failures: [...failures.values()] };
}

// The release verdict for one live run. Only a run that read every row and
// checked at least one football listing (or was told none is acceptable)
// can pass.
export function liveAuditVerdict({ footballCount, unreadableCount, failures }, { feeds, allowNoFootball = false }) {
  if (failures.length > 0) return { ok: false, kind: "conflict", message: `${failures.length} live provider competition identity conflict(s) found.` };
  if (unreadableCount > 0) return { ok: false, kind: "unreadable", message: `${unreadableCount} provider row(s) had no readable sport field; the feed format may have changed, so identity was not fully checked.` };
  if (footballCount === 0) return { ok: allowNoFootball, kind: "noFootball", message: `No football coverage in ${feeds} reachable feed(s): identity was not checked.` };
  return { ok: true, kind: "passed", message: `Live provider identity audit passed across ${feeds} reachable feed(s) and ${footballCount} football listings.` };
}

async function checkCurrentSchedule() {
  const url = new URL("https://www.streamex.hn/api/live/schedule");
  const signal = AbortSignal.timeout(8_000);
  let response;
  try {
    response = await fetch(url, { headers: { Accept: "application/json", Referer: url.origin, "User-Agent": "Fotty/3.0" },
      redirect: "error", signal });
  } catch (error) {
    if (!allowUnavailable) throw error;
    console.warn("Current schedule unreachable. Skipping live identity check (--allow-unavailable).");
    return;
  }
  if (!response.ok) {
    if (!allowUnavailable) throw new Error(`Current schedule returned HTTP ${response.status}.`);
    console.warn(`Current schedule returned HTTP ${response.status}. Skipping live identity check (--allow-unavailable).`);
    return;
  }
  if (response.headers.get("content-type")?.split(";")[0] !== "application/json") throw new Error("Expected JSON schedule metadata.");
  const { events } = await boundedJSON(response, 4 * 1024 * 1024, signal);
  if (!Array.isArray(events) || events.length > 2_000) throw new Error("Invalid schedule event array.");

  const summary = auditProviderPayloads([{ host: url.host, events }]);
  for (const failure of summary.failures) {
    console.error(`Unresolved provider identity: ${failure.competition} | ${failure.home} vs ${failure.away} | ${failure.host}`);
  }
  const verdict = liveAuditVerdict(summary, { feeds: 1, allowNoFootball });
  if (!verdict.ok) throw new Error(verdict.message);
  console.log(verdict.message);
}

if (isMain) {
  const vectors = JSON.parse(await readFile(vectorsPath, "utf8"));
  if (vectors.schemaVersion !== 1 || !Array.isArray(vectors.cases) || vectors.cases.length === 0) {
    throw new Error("Provider identity regression vectors are missing or invalid.");
  }
  for (const vector of vectors.cases) {
    const actual = classify(vector.event);
    if (actual.competition !== vector.expectedCompetition || actual.conflict !== vector.expectedIdentityConflict) {
      throw new Error(`${vector.name}: expected ${vector.expectedCompetition}/${vector.expectedIdentityConflict}, got ${actual.competition}/${actual.conflict}`);
    }
  }
  console.log(`Provider identity vectors passed (${vectors.cases.length}).`);
  if (runLive) await checkCurrentSchedule();
}
