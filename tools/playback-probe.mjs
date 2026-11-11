#!/usr/bin/env node
// Cloud playback probe (watch-first roadmap, Month 1). For every match the
// live broadcast registry currently lists for the Premier League, Champions
// League or cricket, ask that source for its stream descriptor and check that
// the HLS playlist answers with a playable playlist (a master with a reachable
// media playlist, or a media playlist with segments). Segments are never
// downloaded. The repository is public: reports carry only competition,
// source family, outcome and timing — never URLs, IDs, headers or titles.
//
//   node tools/playback-probe.mjs [--out report.json] [--summary]
//   node tools/playback-probe.mjs --daily DIR [--out daily.json] [--summary]
import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const WORKER = process.env.FOTTY_WORKER_ORIGIN || "https://fotty-playback-v3.adaptive-rhubarb.workers.dev";
// Public add-on sources the app resolves itself. Account sources (Highfly) and
// guide/channel rows (reviewed TV) are not probed from the cloud.
export const PROBED_ORIGINS = Object.freeze({
  communitysports: "https://nuviosports.xyz",
  plaviosports: "https://addon.plavio.site",
  cncsports: "https://cncverse.dpdns.org",
  flixstreams: "https://free.flixnest.app",
});
export const FAMILY = Object.freeze({ communitysports: "CS", plaviosports: "AS", cncsports: "CNC", flixstreams: "FS" });
const COMPETITIONS = new Set(["premier-league", "champions-league"]);
const REGISTRY_HEADERS = {
  "X-Fotty-Broadcast-Capabilities": "reviewedtv-programme-v1",
  "X-Fotty-Broadcast-Assignments": "reviewedtv-programme-v2",
  "X-Fotty-Cricket-Matching": "current-listing-v1",
  "X-Fotty-Fox-Programmes": "fox-cricket-v1",
};
const ALLOWED_REQUEST_HEADERS = new Set(["origin", "referer", "user-agent"]);
const LIMITS = Object.freeze({ links: 24, streamsPerLink: 3, descriptorBytes: 256 * 1024, playlistBytes: 256 * 1024, timeoutMs: 10_000 });

/** Competition bucket for a registry link, or null when out of scope. */
export function competitionOf(link) {
  const f = link?.fixtureFingerprint;
  if (f?.sport === "cricket") return "cricket";
  if (f?.sport === "football" && COMPETITIONS.has(f.competitionID)) return f.competitionID;
  return null;
}

/** Listed, in-scope links joined to their broadcast, one per fixture and source. */
export function selectTargets(registry, limit = LIMITS.links) {
  const broadcasts = new Map((registry?.broadcasts ?? []).map((b) => [b.id, b]));
  const seen = new Set(), targets = [];
  for (const link of registry?.links ?? []) {
    const competition = competitionOf(link), broadcast = broadcasts.get(link.broadcastID);
    if (link.state !== "listed" || !competition || !broadcast || broadcast.kind === "channel") continue;
    const key = link.fixtureID + "\n" + broadcast.providerCode;
    if (seen.has(key)) continue;
    seen.add(key);
    targets.push({ competition, providerCode: broadcast.providerCode, streamID: broadcast.streamID });
    if (targets.length >= limit) break;
  }
  return targets;
}

/** Classifies an HLS playlist body. */
export function inspectPlaylist(text) {
  if (typeof text !== "string" || !text.replace(/^﻿/u, "").startsWith("#EXTM3U")) return { kind: "invalid" };
  const lines = text.split(/\r?\n/u).map((line) => line.trim());
  const variants = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].startsWith("#EXT-X-STREAM-INF")) {
      const next = lines.slice(i + 1).find((line) => line && !line.startsWith("#"));
      if (next) variants.push(next);
    }
  }
  if (variants.length) return { kind: "master", firstVariant: variants[0] };
  const segments = lines.filter((line) => line.startsWith("#EXTINF")).length;
  return segments > 0 ? { kind: "media", segments } : { kind: "invalid" };
}

/** Only https playlist URLs and the three reviewed request headers. */
export function streamRequest(stream) {
  let url;
  try { url = new URL(stream?.url); } catch { return null; }
  if (url.protocol !== "https:" || url.username || url.password) return null;
  const raw = stream?.behaviorHints?.proxyHeaders?.request ?? {};
  const headers = {};
  for (const [name, value] of Object.entries(typeof raw === "object" && raw ? raw : {})) {
    if (ALLOWED_REQUEST_HEADERS.has(name.toLowerCase()) && typeof value === "string" && value.length <= 512) headers[name] = value;
  }
  return { url, headers };
}

async function boundedText(response, maximum) {
  const reader = response.body?.getReader();
  if (!reader) return "";
  const chunks = []; let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maximum) { await reader.cancel(); throw new Error("oversized"); }
    chunks.push(value);
  }
  return new TextDecoder().decode(Buffer.concat(chunks));
}

async function get(url, { headers = {}, maximum, fetchImpl = fetch }) {
  const response = await fetchImpl(url, { headers, redirect: "follow", signal: AbortSignal.timeout(LIMITS.timeoutMs) });
  if (!response.ok) throw Object.assign(new Error("http"), { status: response.status });
  return boundedText(response, maximum);
}

/** Probes one target; returns an outcome with no URLs or identifiers. */
export async function probeTarget(target, { fetchImpl = fetch, now = () => Date.now() } = {}) {
  const origin = PROBED_ORIGINS[target.providerCode];
  const base = { competition: target.competition, family: FAMILY[target.providerCode] ?? target.providerCode };
  if (!origin) return { ...base, outcome: "not-probed" };
  const started = now();
  let streams;
  try {
    const text = await get(`${origin}/stream/tv/${encodeURIComponent(target.streamID)}.json`,
      { maximum: LIMITS.descriptorBytes, fetchImpl });
    streams = JSON.parse(text)?.streams;
  } catch { return { ...base, outcome: "descriptor-failed" }; }
  const requests = (Array.isArray(streams) ? streams : []).map(streamRequest).filter(Boolean).slice(0, LIMITS.streamsPerLink);
  if (!requests.length) return { ...base, outcome: "no-stream" };
  let last = "playlist-failed";
  for (const { url, headers } of requests) {
    try {
      const playlist = inspectPlaylist(await get(url, { headers, maximum: LIMITS.playlistBytes, fetchImpl }));
      if (playlist.kind === "media") return { ...base, outcome: "playable", ms: now() - started };
      if (playlist.kind === "master") {
        const media = inspectPlaylist(await get(new URL(playlist.firstVariant, url), { headers, maximum: LIMITS.playlistBytes, fetchImpl }));
        if (media.kind === "media") return { ...base, outcome: "playable", ms: now() - started };
      }
      last = "playlist-invalid";
    } catch { last = "playlist-failed"; }
  }
  return { ...base, outcome: last };
}

/** Totals per competition and source family. */
export function summarize(results) {
  const rows = new Map();
  for (const r of results) {
    const key = r.competition + "\n" + r.family;
    const row = rows.get(key) ?? { competition: r.competition, family: r.family, checks: 0, playable: 0, outcomes: {}, ms: [] };
    row.checks++; row.outcomes[r.outcome] = (row.outcomes[r.outcome] ?? 0) + 1;
    if (r.outcome === "playable") { row.playable++; if (Number.isFinite(r.ms)) row.ms.push(r.ms); }
    rows.set(key, row);
  }
  return [...rows.values()].map(({ ms, ...row }) => ({ ...row,
    medianMs: ms.length ? ms.sort((a, b) => a - b)[Math.floor(ms.length / 2)] : null }))
    .sort((a, b) => a.competition.localeCompare(b.competition) || a.family.localeCompare(b.family));
}

export function markdown(title, rows, note) {
  const lines = [`### ${title}`, ""];
  if (!rows.length) return [...lines, note ?? "No listed Premier League, Champions League or cricket match to check.", ""].join("\n");
  lines.push("| Competition | Source | Checks | Playable | Median time to playlist | Other outcomes |", "| --- | --- | ---: | ---: | ---: | --- |");
  for (const r of rows) {
    const other = Object.entries(r.outcomes).filter(([k]) => k !== "playable").map(([k, v]) => `${k} ${v}`).join(", ") || "—";
    lines.push(`| ${r.competition} | ${r.family} | ${r.checks} | ${r.playable} (${Math.round(100 * r.playable / r.checks)}%) | ${r.medianMs == null ? "—" : `${(r.medianMs / 1000).toFixed(1)} s`} | ${other} |`);
  }
  return [...lines, ""].join("\n");
}

async function probeNow(args) {
  const response = await fetch(`${WORKER}/api/live/broadcasts`, { headers: REGISTRY_HEADERS, signal: AbortSignal.timeout(20_000) });
  if (!response.ok) throw new Error(`Registry returned ${response.status}`);
  const registry = JSON.parse(await boundedText(response, 4 * 1024 * 1024));
  const targets = selectTargets(registry);
  const results = [];
  for (const target of targets) results.push(await probeTarget(target)); // sequential: gentle on sources
  const report = { schema: 1, checkedAt: new Date().toISOString(), registryGeneratedAt: registry.generatedAt, results };
  if (args.out) await writeFile(args.out, JSON.stringify(report, null, 2) + "\n");
  if (args.summary) process.stdout.write(markdown(`Playback probe ${report.checkedAt.slice(0, 16).replace("T", " ")} UTC`, summarize(results)));
}

async function daily(args) {
  const files = (await readdir(args.daily)).filter((name) => name.endsWith(".json"));
  const results = [], runs = [];
  for (const name of files) {
    const report = JSON.parse(await readFile(path.join(args.daily, name), "utf8"));
    if (report?.schema !== 1 || !Array.isArray(report.results)) continue;
    runs.push(report.checkedAt); results.push(...report.results);
  }
  const rows = summarize(results);
  if (args.out) await writeFile(args.out, JSON.stringify({ schema: 1, runs: runs.sort(), rows }, null, 2) + "\n");
  if (args.summary) process.stdout.write(markdown(`Daily playback report (${runs.length} runs)`, rows,
    runs.length ? "No listed Premier League, Champions League or cricket match was on during today's runs." : "No probe runs today."));
}

function parse(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--summary") args.summary = true;
    else if (argv[i] === "--out") args.out = argv[++i];
    else if (argv[i] === "--daily") args.daily = argv[++i];
    else throw new Error(`Unknown argument: ${argv[i]}`);
  }
  return args;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = parse(process.argv.slice(2));
  (args.daily ? daily(args) : probeNow(args)).catch((error) => {
    // Public logs: the message never contains a URL or provider identifier.
    process.stderr.write(`playback-probe failed: ${error.message.replace(/https?:\/\/\S+/gu, "<url>")}\n`);
    process.exitCode = 1;
  });
}
