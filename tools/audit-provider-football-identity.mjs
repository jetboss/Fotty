#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  isCurrentCompetitionPair,
} from "../web/src/lib/football-competition-catalog.generated.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const vectorsPath = resolve(root, "shared/reference-data/provider-football-identity-vectors.json");
const vectors = JSON.parse(await readFile(vectorsPath, "utf8"));
const runLive = process.argv.includes("--live");
const allowUnavailable = process.argv.includes("--allow-unavailable");

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
  return [event.id, event.title, ...sourceIds].filter(Boolean).join(" ").toLowerCase();
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

if (runLive) {
  const endpoints = [
    "https://www.streamex.net/api/live/matches/all",
    "https://streamex.sh/api/live/matches/all",
    "https://streamed.pk/api/matches/all",
  ];
  const payloads = [];
  for (const endpoint of endpoints) {
    try {
      const response = await fetch(endpoint, {
        headers: { Accept: "application/json", Referer: new URL(endpoint).origin },
        signal: AbortSignal.timeout(8_000),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const body = await response.json();
      const events = Array.isArray(body) ? body : body.matches;
      if (!Array.isArray(events)) throw new Error("response was not an event array");
      payloads.push({ host: new URL(endpoint).host, events });
    } catch (error) {
      console.warn(`Provider metadata unavailable (${new URL(endpoint).host}): ${error.message}`);
    }
  }
  if (payloads.length === 0 && !allowUnavailable) {
    throw new Error("No provider metadata endpoint was reachable; release identity drift audit cannot be completed.");
  }

  const failures = new Map();
  for (const payload of payloads) {
    for (const event of payload.events) {
      if ((event.category || "").toLowerCase() !== "football") continue;
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
  if (failures.size > 0) {
    for (const failure of failures.values()) {
      console.error(`Unresolved provider identity: ${failure.competition} | ${failure.home} vs ${failure.away} | ${failure.host}`);
    }
    throw new Error(`${failures.size} live provider competition identity conflict(s) found.`);
  }
  console.log(`Live provider identity audit passed across ${payloads.length} reachable feed(s).`);
}
