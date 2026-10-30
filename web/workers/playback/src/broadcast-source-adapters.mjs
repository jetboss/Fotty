// Metadata-only producers for the fixed, already-reviewed native source lanes.
// A retained observation is not a playable URL, current programme or LIVE fact.
import { canonicalFootballClubId } from "../../../src/lib/football-competition-catalog.generated.ts";
export const BROADCAST_SOURCE_CODES = Object.freeze([
  "streamex", "score808", "communitysports", "plaviosports", "cncsports", "flixstreams", "streamvix",
]);
const KiB = 1024, MAX_RECORDS = 1500, MAX_BYTES = 1024 * KiB, LIFETIME = 4 * 3600_000;
const STAGE_LIMITS = { catalog: MAX_BYTES };
const own = (o, k) => Object.hasOwn(o, k);
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const str = (v, n = 512) => typeof v === "string" && v.trim().length > 0 && v.length <= n && !/[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069<>]/u.test(v) && !v.includes("://");
const id = (v) => str(v, 240) && /^[A-Za-z0-9][A-Za-z0-9._:~-]*$/u.test(v) && !/^(?:https?|data|file|javascript):/iu.test(v);
const strings = (v) => Array.isArray(v) && v.length <= 32 && v.every((s) => str(s, 256));
const version = (v) => str(v, 24) && /^[A-Za-z0-9][A-Za-z0-9._-]*$/u.test(v);
const resources = (m) => (m.resources ?? []).map((r) => typeof r === "string" ? r : r?.name);
const sport = (v) => ({ soccer: "football", football: "football", cricket: "cricket", nba: "basketball", basketball: "basketball",
  baseball: "baseball", mlb: "baseball", hockey: "hockey", "ice hockey": "hockey", nhl: "hockey", nfl: "american-football",
  "american football": "american-football", "american-football": "american-football", rugby: "rugby", mma: "fight", fight: "fight",
  motorsport: "motorsport", golf: "golf", tennis: "tennis", darts: "darts", college: "college", other: "other" })[String(v).toLowerCase()] ?? "unknown";
const CS_SCOPES = Object.freeze(["football", "cricket", "basketball", "baseball", "hockey", "american-football", "rugby", "fight", "motorsport", "golf", "tennis", "darts", "college", "other"]);
const CS_SUFFIX = (s) => s === "american-football" ? "american_football" : s === "fight" ? "mma" : s;
const ORIGINS = Object.freeze({ communitysports: "https://nuviosports.xyz", plaviosports: "https://hd.plavio.site",
  cncsports: "https://cncverse.dpdns.org", flixstreams: "https://free.flixnest.app", streamvix: "https://streamvix.hayd.uk" });
const SCORE_LISTING = "https://www.score808live.tv/score808-live-football-scores-real-time-match-updates-results/";
const SV_ORIGINAL = "https://raw.githubusercontent.com/qwertyuiop8899/logo/main/daddyliveSchedule.json";
const AS_ORIGINAL = "https://thedaddy.pk/";
const flags = new Set(("🇿🇦 🇮🇹 🇨🇦 🇺🇸 🇬🇧 🇪🇸 🇫🇷 🇩🇪 🇵🇹 🇳🇱 🇧🇪 🇹🇷 🇨🇿 🇸🇰 🇦🇹 🇨🇭 🇭🇷 🇷🇸 🇩🇰 🇳🇴 🇸🇪 🇫🇮 🇵🇱 🇬🇷 🇷🇴 🇭🇺 🇺🇦 🇨🇾 🇦🇿 🇮🇱 🇮🇪 🇮🇸 🇯🇲 🇹🇹 🇧🇧 🇬🇾 🇱🇨 🇦🇬 🇰🇳 🇻🇨 🇬🇩 🇩🇲 🇳🇿 🇮🇳 🇵🇰 🇧🇩 🇱🇰 🇦🇫 🇿🇼 🇳🇦 🇳🇵 🇦🇪 🇭🇰 🇴🇲 🇵🇬 🇦🇺 🇰🇪 🇺🇬 🇸🇦 🇶🇦 🇲🇽 🇧🇷 🇦🇷 🇨🇱").split(" "));
for (const tail of ["eng", "sct", "wls"]) flags.add("\u{1F3F4}" + [...("gb" + tail)].map((c) => String.fromCodePoint(0xe0000 + c.charCodeAt(0))).join("") + "\u{E007F}");
function cleanFlags(value) {
  if (!str(value, 1024)) return null;
  const result = value.split(/\s+/u).filter((t) => !flags.has(t)).join(" ");
  return /[\p{Regional_Indicator}\p{Cf}]/u.test(result) ? null : result;
}
function pair(value) {
  const clean = cleanFlags(value); if (!clean) return [];
  const parts = clean.replace(/^(?:🔴\s*)?(?:LIVE|UPCOMING):\s*/iu, "").split(/\s+(?:vs\.?|v\.?|versus)\s+/iu);
  return parts.length === 2 && parts.every((s) => str(s, 256)) && parts[0].toLowerCase() !== parts[1].toLowerCase() ? parts.map((s) => s.trim()) : [];
}
function utc(value) {
  if (typeof value !== "string" || !/^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/u.test(value)) return null;
  const d = new Date(value); if (!Number.isFinite(+d)) return null;
  return d.toISOString().replace(/\.000Z$/u, "Z") === value.replace(/\.0{1,3}Z$/u, "Z")
    || d.toISOString() === value ? d.toISOString() : null;
}
function dateParts(year, month, day, hour, minute) {
  const d = new Date(Date.UTC(year, month - 1, day, hour, minute));
  return d.getUTCFullYear() === year && d.getUTCMonth() === month - 1 && d.getUTCDate() === day && d.getUTCHours() === hour
    && d.getUTCMinutes() === minute ? d.toISOString() : null;
}
function englishUTC(value) {
  const m = typeof value === "string" && value.match(/^(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (20\d{2}) · ((?:[01]\d|2[0-3])):([0-5]\d) UTC$/u);
  return m ? dateParts(+m[3], "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ").indexOf(m[2]) + 1, +m[1], +m[4], +m[5]) : null;
}
function cricketLabel(value) {
  const m = typeof value === "string" && value.match(/^([1-9]\d?)(st|nd|rd|th) (Test|T20I|T20|ODI|T10)(?:[ -]day[ -]([1-5]))?$/iu);
  if (!m) return {};
  const n = +m[1], suffix = n % 100 >= 11 && n % 100 <= 13 ? "th" : ({ 1: "st", 2: "nd", 3: "rd" })[n % 10] ?? "th";
  if (m[2].toLowerCase() !== suffix || m[4] && m[3].toLowerCase() !== "test") return {};
  return { format: /^test$/iu.test(m[3]) ? "Test" : m[3].toUpperCase().replace("T20I", "T20"), matchOrdinal: n, ...(m[4] ? { day: +m[4] } : {}) };
}
function squadTokens(value) {
  return new Set((String(value).toLowerCase().match(/\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b/gu) ?? [])
    .map((v) => ["women", "womens", "ladies", "w"].includes(v) ? "women" : v.replace(/\s/gu, "").replace(/^under/u, "u").replace(/^reserve$/u, "reserves")));
}
const normalizedName = (value) => String(value).normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim().replace(/\s+/gu, " ");
function teamKey(value, category = "football") {
  const normalized = normalizedName(value), qualifiers = [...squadTokens(normalized)].sort();
  const base = normalized.replace(/\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b/gu, " ").trim().replace(/\s+/gu, " ");
  const club = category === "football" ? canonicalFootballClubId(base) : undefined;
  return (club ?? base) + "|" + qualifiers.join(",");
}
function sourceTitleParts(value) {
  if (!str(value, 512)) return [];
  const parts = value.split(":"); return parts.length === 2 && parts.every((p) => p.trim()) ? parts.map((p) => p.trim()) : [];
}
function canonicalChannel(title) {
  if (!str(title, 128)) return null;
  const name = title.toLowerCase().replace(/[^a-z0-9]/gu, "");
  if (["willow", "willowtv", "willowcricket", "willowhd", "willowcrickethd", "willowcricket247"].includes(name)) return "cricket-channel:willow";
  return ["foxcricket", "foxcrickethd"].includes(name) ? "cricket-channel:fox-cricket" : null;
}
function record(providerCode, row, scope, now, facts = {}, issues = []) {
  if (!object(row) || !id(row.id)) return null;
  const title = row.name ?? row.title;
  if (!str(title, 512)) issues.push("identity-conflict");
  const streamID = row.behaviorHints?.defaultVideoId ?? row.id;
  if (!id(streamID)) issues.push("identity-conflict");
  const start = facts.start ? utc(facts.start) : null, end = facts.end ? utc(facts.end) : null;
  if (facts.start && !start || facts.end && !end) issues.push("time-conflict");
  const participants = facts.participants ?? [];
  if (!Array.isArray(participants) || participants.length !== 0 && (participants.length !== 2 || !participants.every((s) => str(s, 256)))) return null;
  if (facts.kind !== "channel" && participants.length !== 2) issues.push("missing-participants");
  if (!start && facts.kind !== "channel") issues.push("missing-date");
  return { providerEventID: row.id, streamID: id(streamID) ? streamID : row.id, resourceType: "tv", scope,
    kind: facts.kind ?? "event", sport: facts.sport ?? "unknown", title: str(title, 512) ? title.trim() : "Unverified source entry", participants: participants.map((p) => p.trim()),
    ...(start ? { start } : {}), ...(end ? { end } : {}),
    ...Object.fromEntries(["competitionID", "format", "matchOrdinal", "day", "channelID"].filter((k) => facts[k] != null).map((k) => [k, facts[k]])),
    verification: issues.some((i) => i.endsWith("conflict")) ? "conflicting" : start && !issues.includes("unverified-fixture") && !issues.includes("unsupported-scope") ? "dated" : "undated",
    issues: [...new Set(issues)], observedAt: now.toISOString(), expiresAt: new Date(+now + LIFETIME).toISOString() };
}
function safeRows(body, maximum) {
  if (!object(body) || !Array.isArray(body.metas) || body.metas.length > maximum) throw new Error("invalid-collection");
  return body.metas;
}
function manifest(m, code) {
  const expected = { communitysports: "community.nuvio.live-sports", plaviosports: "community.plaviohd",
    cncsports: "com.cncverse.stremiobridge", flixstreams: "org.flixstreams.free", streamvix: "org.prisonmike.streamvix" }[code];
  if (!object(m) || m.id !== expected || !version(m.version) || m.behaviorHints?.configurationRequired === true
    || !Array.isArray(m.catalogs) || m.catalogs.length > (code === "communitysports" ? 600 : 64)
    || !Array.isArray(m.resources) || !["catalog", "stream"].every((v) => resources(m).includes(v))) throw new Error("invalid-collection");
  const r = resources(m), unique = (a) => new Set(a).size === a.length;
  if (code === "communitysports") {
    if (!m.resources.every((v) => typeof v === "string") || !m.catalogs.some((c) => c?.id === "nuvio_sports_live" && c.type === "tv")) throw new Error("invalid-collection");
  } else if (code === "plaviosports") {
    const allowedTypes = ["movie", "series", "tv"], allowedResources = ["catalog", "meta", "stream", "subtitles"];
    if (!strings(m.types) || !m.types.includes("tv") || !m.types.every((v) => allowedTypes.includes(v)) || !unique(r) || r.length > 16
      || !m.resources.every((v) => typeof v === "string" ? allowedResources.includes(v) : object(v) && allowedResources.includes(v.name)
        && strings(v.types) && unique(v.types) && v.types.length > 0 && v.types.every((t) => allowedTypes.includes(t))
        && strings(v.idPrefixes) && unique(v.idPrefixes) && v.idPrefixes.length > 0 && v.idPrefixes.every((p) => /^[A-Za-z0-9][A-Za-z0-9:_-]{0,127}$/u.test(p)))
      || !m.resources.some((v) => object(v) && v.name === "stream" && v.types?.includes("tv") && v.idPrefixes?.includes("plaviohdtv-"))) throw new Error("invalid-collection");
    for (const key of ["plaviohd-football", "plaviohd-live-sports", "plaviohd-cricket"]) {
      const rows = m.catalogs.filter((c) => c?.id === key);
      if (rows.length > 1 || rows.some((c) => c.type !== "tv")) throw new Error("invalid-collection");
    }
    if (!m.catalogs.some((c) => ["plaviohd-football", "plaviohd-live-sports"].includes(c?.id) && c.type === "tv")) throw new Error("invalid-collection");
  } else if (code === "cncsports") {
    if (!m.resources.every((v) => typeof v === "string") || !unique(r) || !["catalog", "meta", "stream"].every((v) => r.includes(v))
      || !r.every((v) => ["catalog", "meta", "stream", "subtitles"].includes(v)) || !strings(m.types) || !unique(m.types)
      || !m.types.includes("tv") || !m.types.every((t) => ["movie", "series", "other", "tv"].includes(t))) throw new Error("invalid-collection");
  } else if (code === "flixstreams") {
    if (r.length !== 3 || !unique(r) || !["catalog", "meta", "stream"].every((v) => r.includes(v))
      || !m.resources.every((v) => typeof v === "string") || m.types != null && (!strings(m.types) || !m.types.includes("tv")) || m.catalogs.length > 16) throw new Error("invalid-collection");
    const rows = m.catalogs.filter((c) => c?.id === "essential-live-events" && c.type === "tv"), extras = rows[0]?.extra;
    if (rows.length !== 1 || !Array.isArray(extras) || extras.length > 8 || !unique(extras.map((v) => v?.name)) || extras.some((v) => v?.isRequired === true)) throw new Error("invalid-collection");
  } else if (code === "streamvix") {
    if (!strings(m.types) || !m.types.includes("tv") || !["catalog", "meta", "stream"].every((name) => m.resources.some((v) => v === name || v?.name === name && (v.types == null || v.types.includes("tv"))))) throw new Error("invalid-collection");
  }
  return m;
}
function advertised(m, catalogID, extraCheck = () => true) {
  const rows = m.catalogs.filter((c) => c?.id === catalogID);
  if (rows.length !== 1 || rows[0].type !== "tv" || !extraCheck(rows[0])) throw new Error("unsupported-scope");
  return rows[0];
}

// Body, request inventory and final URL are independently bounded. The caller's
// provider-bound reservation owns durable spending/cadence; no read bypasses it.
function reader(code, { fetcher, reserveRequest, signal }) {
  let count = 0;
  const read = async (url, maxBytes = 512 * KiB, html = false) => {
    if (signal?.aborted) throw signal.reason ?? new DOMException("Cancelled", "AbortError");
    if (++count > 8 || await reserveRequest() !== true) throw new Error("budget-exhausted");
    const controller = new AbortController(), cancel = () => controller.abort(signal.reason);
    signal?.addEventListener("abort", cancel, { once: true });
    const timer = setTimeout(() => controller.abort(), code === "score808" ? 6000 : 9000);
    try {
      const response = await fetcher(url, { method: "GET", redirect: "manual", signal: controller.signal,
        headers: { Accept: html ? "text/html" : "application/json", "User-Agent": "Fotty metadata collector/1.0" } });
      if (response.status !== 200 || response.url && response.url !== url) { await response.body?.cancel(); throw new Error("source-unavailable"); }
      const declared = Number(response.headers.get("content-length"));
      if (declared > maxBytes || !response.body) { await response.body?.cancel(); throw new Error("capacity-exceeded"); }
      const type = response.headers.get("content-type") ?? "";
      if (!html && !/(?:application\/(?:[a-z.+-]*\+)?json)\b/iu.test(type)) { await response.body.cancel(); throw new Error("invalid-collection"); }
      const stream = response.body.getReader(), chunks = []; let bytes = 0;
      try {
        for (;;) { const { done, value } = await stream.read(); if (done) break;
          bytes += value.byteLength; if (bytes > maxBytes) { await stream.cancel(); throw new Error("capacity-exceeded"); } chunks.push(value); }
      } finally { stream.releaseLock(); }
      if (signal?.aborted) throw signal.reason ?? new DOMException("Cancelled", "AbortError");
      const body = new Uint8Array(bytes); let offset = 0; for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
      const text = new TextDecoder("utf-8", { fatal: true }).decode(body);
      if (html) return text;
      try { return JSON.parse(text); } catch { throw new Error("invalid-collection"); }
    } catch (error) {
      if (signal?.aborted) throw signal.reason ?? error;
      if (controller.signal.aborted) throw new Error("source-unavailable");
      throw error;
    } finally { clearTimeout(timer); signal?.removeEventListener("abort", cancel); }
  };
  read.count = () => count;
  return read;
}

function csRow(row, scope, now) {
  if (!object(row) || typeof row.id !== "string") return null;
  const category = row.genres?.[0], isChannel = scope === "networks" && category === "NETWORKS" && row.released == null;
  const facts = { kind: isChannel ? "channel" : "event", sport: sport(category), participants: [], ...(row.released ? { start: row.released } : {}) };
  if (isChannel && canonicalChannel(row.name)) { facts.channelID = canonicalChannel(row.name); facts.sport = "cricket"; }
  const issues = [];
  if (row.type != null && row.type !== "tv" || !row.id?.startsWith("nuvio_sport_")) issues.push("identity-conflict");
  if (isChannel && (row.type !== "tv" || row.genres.length !== 1 || row.cast != null && (!Array.isArray(row.cast) || row.cast.length > 0)
    || ["released", "date", "startTime", "kickoff", "videos"].some((k) => own(row, k)))) issues.push("identity-conflict");
  if (!isChannel) {
    const named = pair(row.name), cast = strings(row.cast) && row.cast.length === 2 ? row.cast.map(cleanFlags) : [];
    facts.participants = cast.length === 2 && cast.every(Boolean) ? cast : named;
    if (named.length === 2 && cast.length === 2 && named.map((x) => x.toLowerCase()).sort().join("|") !== cast.map((x) => x?.toLowerCase()).sort().join("|")) issues.push("identity-conflict");
  }
  if (!isChannel && facts.sport === "cricket" && typeof row.description === "string") {
    const label = row.description.split("\n").find((line) => line.startsWith("🏆 League: "))?.slice("🏆 League: ".length);
    Object.assign(facts, cricketLabel(label));
  }
  return record("communitysports", row, scope, now, facts, issues);
}
function asRow(row, scope, now, originals = []) {
  if (!object(row) || typeof row.id !== "string") return null;
  const observationScope = scope;
  if (scope === "live" && pair(row.name).length === 2 && /^plaviohdtv-sfly-streamed:[A-Za-z0-9][A-Za-z0-9_-]*$/u.test(row.id) && JSON.stringify(row.genres) === '["Sports"]') scope = "football";
  const name = typeof row.name === "string" ? row.name : "";
  const issues = [], facts = { sport: scope === "football" || scope === "cricket" ? scope : "unknown", participants: [] };
  if (row.type !== "tv" || !row.id?.startsWith("plaviohdtv-") || !strings(row.genres)) issues.push("identity-conflict");
  if (["released", "releaseInfo", "date", "startTime", "kickoff", "videos", "behaviorHints"].some((k) => own(row, k))) issues.push("identity-conflict");
  const lines = typeof row.description === "string" ? row.description.split("\n") : [];
  if (scope === "cricket") {
    if (JSON.stringify(row.genres) !== '["Cricket"]') issues.push("identity-conflict");
    if (lines.length === 2 && name.startsWith(lines[0] + " - ")) {
      facts.participants = pair(lines[0]); Object.assign(facts, cricketLabel(row.name.slice((lines[0] + " - ").length)));
      facts.start = englishUTC(lines[1]);
      if (!facts.format || facts.format === "Test" && !facts.day) issues.push("format-conflict");
      if (!/^plaviohdtv-sfly-streamed:cricket-[a-z0-9][a-z0-9-]*$/u.test(row.id ?? "")) issues.push("unverified-fixture");
    } else { // Retain the changed clock-only envelope; never derive its date.
      const split = sourceTitleParts(row.name);
      if (split.length === 2) { Object.assign(facts, cricketLabel(split[0])); facts.participants = pair(split[1]); }
      issues.push("missing-date");
    }
  } else if (scope === "football") {
    facts.participants = pair(row.name);
    if (lines.length === 2 && lines[0] === row.name && JSON.stringify(row.genres) === '["Sports"]'
      && /^plaviohdtv-sfly-streamed:football-[a-z0-9][a-z0-9-]*$/u.test(row.id ?? "")) facts.start = englishUTC(lines[1]);
    if (!facts.start && /^plaviohdtv-dlhd-ev-[a-z0-9]{1,32}$/u.test(row.id ?? "")) {
      if (JSON.stringify(row.genres) !== '["Football"]') issues.push("identity-conflict");
      const title = sourceTitleParts(row.name);
      const clock = typeof row.description === "string" && row.description.match(/^Starts ((?:[01]\d|2[0-3]):[0-5]\d) \(UK time\) · [1-9]\d{0,2} channels$/u)?.[1];
      if (title?.length === 2 && clock) {
        facts.participants = pair(title[1]);
        const matches = originals.filter((o) => normalizedName(o.competition) === normalizedName(title[0]) && samePair(o.participants, facts.participants));
        facts.competitionID = ({ "england premier league": "premier-league", "uefa champions league": "champions-league", "england league cup": "carabao-cup" })[normalizedName(title[0])];
        if (matches.length === 1 && matches[0].start && matches[0].clock === clock) {
          const london = wallParts(+new Date(matches[0].start), "Europe/London"), localClock = `${String(london.hour).padStart(2, "0")}:${String(london.minute).padStart(2, "0")}`;
          if (localClock === clock) facts.start = matches[0].start; else issues.push("time-conflict");
        }
        else if (matches.length > 1) issues.push("time-conflict");
      }
    }
  } else { facts.participants = pair(row.name); facts.kind = facts.participants.length ? "event" : "channel";
    if (facts.kind === "channel" && canonicalChannel(row.name)) { facts.channelID = canonicalChannel(row.name); facts.sport = "cricket"; } }
  return record("plaviosports", row, observationScope, now, facts, issues);
}
const samePair = (a, b, category = "football") => a.length === 2 && b.length === 2 && a.map((v) => teamKey(v, category)).sort().join("\n") === b.map((v) => teamKey(v, category)).sort().join("\n");
function fsRow(row, scope, now) {
  if (!object(row)) return null;
  const issues = [], lines = typeof row.description === "string" ? row.description.split("\n") : [];
  const category = scope === "football" ? "All Soccer Events ⚽" : "Cricket 🏏", prefix = scope === "football" ? "⚽ " : "🏏 ";
  const title = cleanFlags(row.name), parts = title?.startsWith(prefix) ? title.slice(prefix.length).split(" : ") : [];
  const facts = { sport: scope, participants: parts?.length === 2 ? pair(parts[1]) : [] };
  if (row.type !== "tv" || !/^dlstreams:event:[a-f0-9]{12}$/u.test(row.id ?? "") || JSON.stringify(row.genres) !== JSON.stringify(["Live TV", "Sports", category])) issues.push("identity-conflict");
  if (parts?.length === 2) facts.competitionID = ({ "England - Premier League": "premier-league", "UEFA Champions League": "champions-league", "Europe - UEFA Champions League": "champions-league", "Italy - Serie A": "serie-a" })[parts[0]];
  if (scope === "football" && !facts.competitionID) issues.push("unsupported-scope");
  if (title && /\b(?:xtra\s*time|extra\s*time|watch\s*along|watchalong|preview|highlights?|replays?|simulcast|multicast)\b/iu.test(title)) issues.push("unverified-fixture");
  if (parts?.length === 2 && [...squadTokens(parts[0])].some((q) => !facts.participants.every((p) => squadTokens(p).has(q)))) issues.push("squad-conflict");
  if (lines.length === 4 && lines[0] === "Category: " + category && /^Date: 20\d{2}-\d{2}-\d{2} \(UTC\)$/u.test(lines[1])
    && /^Time: (?:[01]\d|2[0-3]):[0-5]\d$/u.test(lines[2]) && /^Channels: .+/u.test(lines[3])) facts.start = lines[1].slice(6, 16) + "T" + lines[2].slice(6) + ":00Z";
  if (["released", "releaseInfo", "cast"].some((k) => own(row, k))) issues.push("identity-conflict");
  if (own(row, "behaviorHints") && (!object(row.behaviorHints) || Object.keys(row.behaviorHints).join() !== "defaultVideoId" || row.behaviorHints.defaultVideoId !== row.id)) issues.push("identity-conflict");
  if (own(row, "videos")) {
    const v = row.videos?.[0];
    if (!Array.isArray(row.videos) || row.videos.length !== 1 || !object(v) || Object.keys(v).sort().join() !== "episode,id,released,season,title"
      || v.id !== row.id || v.title !== "Live Stream" || !Number.isInteger(v.season) || !Number.isInteger(v.episode)
      || !facts.start || utc(v.released) !== utc(facts.start)) issues.push("time-conflict");
  }
  return record("flixstreams", row, scope, now, facts, issues);
}
async function cncRow(row, now) {
  if (!object(row)) return null;
  if (typeof row.id !== "string" || row.id.length > 4096 || !/^cnc:[A-Za-z0-9_-]+={0,2}$/u.test(row.id)) return null;
  const issues = [], participants = pair(typeof row.name === "string" ? row.name.replace(/^(?:🔴|🔜|✅) /u, "") : ""), hints = row.behaviorHints;
  if (row.type !== "tv" || !object(hints) || Object.keys(hints).join() !== "defaultVideoId" || hints.defaultVideoId !== row.id) issues.push("identity-conflict");
  // CNC's advertised identifier encodes a provider object. Persist only an
  // observation fingerprint, never that embedded payload or executable route.
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(row.id)));
  const reference = "cnc-observation:" + [...hash].map((b) => b.toString(16).padStart(2, "0")).join("");
  return record("cncsports", { id: reference, name: row.name }, "hockey", now, { sport: "hockey", participants, competitionID: "nhl" }, issues);
}

const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
function gmtDay(header, clock, as = false) {
  const match = typeof header === "string" && header.length <= 128 && header.match(as
    ? /^(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday) ([1-9]|[12]\d|3[01])(?:st|nd|rd|th|h) ([A-Za-z]+) (20\d{2}) - Schedule Time UK GMTT?$/u
    : /^(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday) (\d{1,2})(st|nd|rd|th)? ([A-Za-z]+) (20\d{2}) - Schedule Time UK GMT$/u);
  if (!match || typeof clock !== "string" || !/^(?:[01]\d|2[0-3]):[0-5]\d$/u.test(clock) || as && +clock.slice(0, 2) < 6) return null;
  const day = +match[2], monthText = as ? match[3] : match[4], year = +(as ? match[4] : match[5]);
  const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  const month = monthNames.findIndex((m) => m === monthText || m.slice(0, 3) === monthText || m === "September" && monthText === "Sept") + 1;
  if (!as && match[3]) { const suffix = day % 100 >= 11 && day % 100 <= 13 ? "th" : ({ 1: "st", 2: "nd", 3: "rd" })[day % 10] ?? "th"; if (match[3] !== suffix) return null; }
  const result = dateParts(year, month, day, +clock.slice(0, 2), +clock.slice(3));
  return result && weekdays[new Date(result).getUTCDay()] === match[1] ? result : null;
}
function wallParts(ms, zone) {
  const formatter = new Intl.DateTimeFormat("en-GB", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  return Object.fromEntries(formatter.formatToParts(new Date(ms)).filter((p) => p.type !== "literal").map((p) => [p.type, +p.value]));
}
function zonedDate(day, clock, zone) {
  if (typeof zone !== "string" || zone.length > 80 || !/^20\d{2}-\d{2}-\d{2}$/u.test(day ?? "") || !/^(?:[01]\d|2[0-3]):[0-5]\d$/u.test(clock ?? "")) return null;
  const [year, month, date] = day.split("-").map(Number), [hour, minute] = clock.split(":").map(Number);
  const literal = dateParts(year, month, date, hour, minute); if (!literal) return null;
  const base = +new Date(literal), candidates = new Set();
  try {
    // Both sides of a clock transition supply possible offsets; round-tripping
    // rejects nonexistent or ambiguous local instants instead of guessing DST.
    for (const delta of [-86400_000, 0, 86400_000]) {
      const sample = base + delta, p = wallParts(sample, zone), offset = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute) - sample;
      const candidate = base - offset, actual = wallParts(candidate, zone);
      if (actual.year === year && actual.month === month && actual.day === date && actual.hour === hour && actual.minute === minute) candidates.add(candidate);
    }
  } catch { return null; }
  return candidates.size === 1 ? new Date([...candidates][0]).toISOString() : null;
}
function svOriginals(body) {
  if (!object(body) || Object.keys(body).length > 8) throw new Error("invalid-collection");
  const result = [];
  for (const [header, groups] of Object.entries(body)) {
    if (!object(groups) || Object.keys(groups).length > 64) throw new Error("invalid-collection");
    if (!own(groups, "All Soccer Events ⚽")) continue;
    const rows = groups["All Soccer Events ⚽"];
    if (!Array.isArray(rows) || rows.length > 600) throw new Error("invalid-collection");
    for (const row of rows) {
      if (!object(row) || !str(row.event, 1024)) throw new Error("invalid-collection");
      for (const competition of ["England - Premier League", "UEFA Champions League"]) {
        const prefix = "⚽ " + competition + " : "; if (!row.event.startsWith(prefix)) continue;
        if (!gmtDay(header, "00:00")) throw new Error("invalid-collection");
        const pairTitle = row.event.slice(prefix.length), participants = pair(pairTitle);
        result.push({ competition, participants, pairTitle, start: gmtDay(header, row.time), category: competition.startsWith("England") ? "premierleague" : "coppe" });
      }
    }
  }
  return result;
}
function svRow(row, genre, now, originals) {
  if (!object(row)) return null;
  const category = genre === "Premier League" ? "premierleague" : "coppe", issues = [];
  const clean = cleanFlags(row.name), titlePair = clean?.replace(/ ⏰ \d{2}:\d{2} - \d{2}\/\d{2}$/u, "");
  const participants = pair(titlePair), derived = utc(row.eventStart);
  const facts = { sport: "football", participants, competitionID: category === "premierleague" ? "premier-league" : "champions-league", ...(derived ? { start: derived } : {}) };
  if (row.type !== "tv" || row.category !== category || row._dynamic !== true || !id(row.id)
    || ["behaviorHints", "videos", "released", "startTime", "eventstart"].some((k) => own(row, k))
    || ["genre", "genres"].some((k) => own(row, k) && JSON.stringify(row[k]) !== JSON.stringify([category]))) issues.push("identity-conflict");
  const candidates = originals.filter((o) => o.category === category && samePair(o.participants, participants));
  const matched = [];
  for (const original of candidates) {
    if (!derived || !original.start) continue;
        const rome = zonedDate(original.start.slice(0, 10), original.start.slice(11, 16), "Europe/Rome");
    if (derived !== original.start && derived !== rome) continue;
    const display = wallParts(+new Date(derived), "Europe/Rome"), clock = `${String(display.hour).padStart(2, "0")}:${String(display.minute).padStart(2, "0")}`;
    const dm = `${String(display.day).padStart(2, "0")}/${String(display.month).padStart(2, "0")}`;
    const sourceTitle = `⏰ ${clock} : ${original.pairTitle} - ${genre === "Premier League" ? "Premier League" : "UEFA Champions League"} ${dm}`;
    const slug = sourceTitle.toLowerCase().replace(/[^a-z0-9]+/gu, "-").replace(/^-|-$/gu, "").slice(0, 60);
    const target = "tv:" + slug + "-" + derived.slice(0, 10).replaceAll("-", "");
    const expectedName = `${cleanFlags(original.pairTitle)} ⏰ ${clock} - ${dm}`;
    const expectedDescription = `🔴 Inizio: ${clock} - ${cleanFlags(original.pairTitle)} - ${genre === "Premier League" ? "Premier League" : "UEFA Champions League"} - ${dm}`;
    if (row.id === target && clean === expectedName && cleanFlags(row.description) === expectedDescription
      && (!own(row, "_originalName") || cleanFlags(row._originalName) === cleanFlags(sourceTitle))) matched.push(original.start);
  }
  const unique = [...new Set(matched)];
  if (unique.length === 1) {
    for (const other of originals) {
      if (!other.start) continue;
      const possibilities = [other.start, zonedDate(other.start.slice(0, 10), other.start.slice(11, 16), "Europe/Rome")].filter(Boolean);
      for (const date of possibilities) {
        const d = wallParts(+new Date(date), "Europe/Rome"), clock = `${String(d.hour).padStart(2, "0")}:${String(d.minute).padStart(2, "0")}`;
        const dm = `${String(d.day).padStart(2, "0")}/${String(d.month).padStart(2, "0")}`;
        const title = `⏰ ${clock} : ${other.pairTitle} - ${other.category === "premierleague" ? "Premier League" : "UEFA Champions League"} ${dm}`;
        const target = "tv:" + title.toLowerCase().replace(/[^a-z0-9]+/gu, "-").replace(/^-|-$/gu, "").slice(0, 60) + "-" + date.slice(0, 10).replaceAll("-", "");
        if (target === row.id && (other.start !== unique[0] || other.category !== category || !samePair(other.participants, participants))) issues.push("identity-conflict");
      }
    }
  }
  if (unique.length === 1 && issues.length === 0) facts.start = unique[0]; else issues.push(candidates.length ? "time-conflict" : "unverified-fixture");
  return record("streamvix", row, "football", now, facts, issues);
}

// Port of the native Daddy schedule's balanced visibility scopes. Script,
// template, hidden descendants and malformed paired rows cannot supply dates.
function htmlNodes(raw) {
  const html = raw.replace(/<(script|style)\b[^>]*>.*?<\/\1\s*>|<!--[\s\S]*?(?:-->|$)/gisu, "");
  const nodes = [], stack = [], tags = [...html.matchAll(/<(\/?)([A-Za-z][A-Za-z0-9]*)\b([^<>]{0,4096})>/gu)];
  if (tags.length > 24000) throw new Error("capacity-exceeded");
  const voids = new Set("area base br col embed hr img input link meta param source track wbr".split(" "));
  let skip = 0;
  for (const match of tags) {
    if (match.index < skip) continue;
    const tag = match[2].toLowerCase();
    if (match[1]) {
      const position = stack.findLastIndex((i) => nodes[i].tag === tag); if (position < 0) continue;
      if (position !== stack.length - 1) for (const i of stack) nodes[i].valid = false;
      const node = nodes[stack[position]]; node.contentEnd = match.index; node.closeEnd = match.index + match[0].length; stack.splice(position); continue;
    }
    const attrs = match[3], classes = new Set((attrs.match(/(?:^|\s)class\s*=\s*(["'])([^"']*)\1/iu)?.[2] ?? "").split(/\s+/u));
    const hidden = stack.length > 0 && nodes[stack.at(-1)].hidden || ["template", "noscript", "textarea", "script", "style"].includes(tag)
      || /(?:^|\s)(?:hidden|inert)(?=\s|=|\/|$)|(?:^|\s)aria-hidden\s*=\s*(?:["']true["']|true(?:\s|$))|(?:^|\s)style\s*=\s*["'][^"']*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))/iu.test(attrs);
    const node = { tag, classes, start: match.index, end: match.index + match[0].length, parent: stack.at(-1), hidden, valid: true }; nodes.push(node); const index = nodes.length - 1;
    if (classes.has("schedule__day") && stack.some((i) => nodes[i].classes.has("schedule__day"))) { node.valid = false; for (const i of stack) nodes[i].valid = false; }
    if (["noscript", "textarea", "script", "style"].includes(tag)) {
      const close = new RegExp("</" + tag + "\\s*>", "iu").exec(html.slice(node.end));
      if (close) { node.contentEnd = node.end + close.index; node.closeEnd = node.contentEnd + close[0].length; skip = node.closeEnd; }
      else { node.valid = false; skip = html.length; }
    } else if (voids.has(tag) || /\/\s*$/u.test(attrs)) { node.contentEnd = node.end; node.closeEnd = node.end; }
    else { if (stack.length >= 96) throw new Error("capacity-exceeded"); stack.push(index); }
  }
  const classNodes = new Map(), ancestry = new Map();
  for (let i = 0; i < nodes.length; i++) for (const klass of nodes[i].classes) {
    if (!classNodes.has(klass)) classNodes.set(klass, []); classNodes.get(klass).push(i);
  }
  const ancestor = (index, klass) => {
    const key = index + ":" + klass; if (ancestry.has(key)) return ancestry.get(key);
    for (let p = nodes[index].parent; p != null; p = nodes[p].parent) if (nodes[p].classes.has(klass)) { ancestry.set(key, p); return p; }
    ancestry.set(key, null); return null;
  };
  const hiddenRoots = nodes.filter((n) => n.hidden && (n.parent == null || !nodes[n.parent].hidden));
  const text = (index) => {
    const node = nodes[index]; if (node.hidden || !node.valid || node.contentEnd == null) return null;
    let value = html.slice(node.end, node.contentEnd);
    let lo = 0, hi = hiddenRoots.length;
    while (lo < hi) { const mid = (lo + hi) >>> 1; if (hiddenRoots[mid].start < node.end) lo = mid + 1; else hi = mid; }
    const hidden = []; for (let i = lo; i < hiddenRoots.length && hiddenRoots[i].start < node.contentEnd; i++) if (hiddenRoots[i].closeEnd <= node.contentEnd) hidden.push(hiddenRoots[i]);
    for (const child of hidden.reverse())
      value = value.slice(0, child.start - node.end) + value.slice(child.closeEnd - node.end);
    if (value.length > 4096) return null;
    value = value.replace(/<[^>]*>/gu, " ");
    for (const [from, to] of [["&amp;", "&"], ["&nbsp;", " "], ["&#039;", "'"], ["&#39;", "'"], ["&quot;", '"']]) value = value.replaceAll(from, to);
    if (/&(?:#[0-9A-Za-z]+|[A-Za-z][A-Za-z0-9]+);/u.test(value)) return null;
    return value.trim().replace(/\s+/gu, " ");
  };
  return { nodes, classNodes, ancestor, text };
}
function dlhdOriginals(raw) {
  const { nodes, classNodes, ancestor, text } = htmlNodes(raw), days = nodes.filter((n) => n.classes.has("schedule__day") && !n.hidden);
  if (!days.length || days.length > 16) throw new Error("invalid-collection");
  const fields = new Map();
  for (const [klass, scope] of [["schedule__eventTitle", "schedule__event"], ["schedule__time", "schedule__event"], ["schedule__dayTitle", "schedule__day"], ["card__meta", "schedule__category"]]) {
    for (const index of classNodes.get(klass) ?? []) {
      if (nodes[index].hidden) continue;
      const key = klass + ":" + ancestor(index, scope); if (!fields.has(key)) fields.set(key, []); fields.get(key).push(index);
    }
  }
  const field = (klass, owner) => { const found = fields.get(klass + ":" + owner) ?? []; return found.length === 1 ? text(found[0]) : null; };
  const result = [];
  for (let index = 0; index < nodes.length; index++) {
    const n = nodes[index]; if (n.hidden || !n.classes.has("schedule__event")) continue;
    const day = ancestor(index, "schedule__day"), category = ancestor(index, "schedule__category");
    if (day == null || category == null || ancestor(category, "schedule__day") !== day) continue;
    if (result.length >= 2000) throw new Error("capacity-exceeded");
    const title = field("schedule__eventTitle", index, "schedule__event"), clock = field("schedule__time", index, "schedule__event");
    const parts = title?.split(":").map((v) => v.trim()), header = field("schedule__dayTitle", day, "schedule__day");
    const visible = [n, nodes[day], nodes[category]].every((v) => v.valid && v.contentEnd != null && !v.hidden);
    result.push({ competition: parts?.length === 2 ? parts[0] : "", participants: parts?.length === 2 ? pair(parts[1]) : [], clock,
      start: visible && field("card__meta", category, "schedule__category")?.toLowerCase() === "all soccer events" ? gmtDay(header, clock, true) : null });
  }
  return result;
}

async function collectScore808({ read, now, cohort }) {
  await cohort("football", async () => {
    const listing = await read(SCORE_LISTING, MAX_BYTES, true), widget = score808WidgetID(listing);
    if (typeof widget !== "string") throw new Error("invalid-collection");
    const boot = new URL("https://core.service.elfsight.com/p/boot/"); boot.searchParams.set("w", widget); boot.searchParams.set("page", SCORE_LISTING);
    const body = await read(boot.href, MAX_BYTES), selected = body?.data?.widgets?.[widget];
    const settings = selected?.data?.settings;
    if (body?.status !== 1 || selected?.status !== 1 || settings?.selectedEventsProvider !== "manual" || !Array.isArray(settings.events) || settings.events.length > 1000) throw new Error("invalid-collection");
    const rows = settings.events.map((e) => ({ ...e, _widget: widget }));
    for (const row of rows) {
      const pages = Array.isArray(row.actions) && row.actions.length <= 10 ? row.actions.filter((a) => a?.type === "link" && a.primary === true
        && a.text?.trim().toLowerCase() === "watch now" && a.link?.type === "url" && safeScorePage(a.link.value)).map((a) => a.link.value) : [];
      if (pages.length !== 1) continue;
      const key = new URL(pages[0]).pathname.replace(/^\/+|\/+$/gu, "");
      const start = zonedDate(row.start?.date, row.start?.time, row.timeZone), end = zonedDate(row.end?.date, row.end?.time, row.timeZone);
      row._pageKey = key; row._start = start; row._end = end;
    }
    for (const row of rows) row._pageConflict = row._pageKey != null && rows.some((other) => other !== row && other._pageKey === row._pageKey
      && row._start && row._end && other._start && other._end && row._start < other._end && other._start < row._end);
    return rows;
  }, (row) => {
    if (!object(row) || !id(row.id) || !str(row.name, 256)) return null;
    const issues = [], start = row.start?.type === "datetime" ? zonedDate(row.start.date, row.start.time, row.timeZone) : null;
    const end = row.end?.type === "datetime" ? zonedDate(row.end.date, row.end.time, row.timeZone) : null;
    const visible = !own(row, "visible") || row.visible === true;
    if (!visible || row.repeatPeriod !== "noRepeat" || !start || !end || +new Date(end) <= +new Date(start) || +new Date(end) - +new Date(start) > 4 * 3600_000) issues.push("time-conflict");
    const actions = Array.isArray(row.actions) && row.actions.length <= 10 ? row.actions.filter((a) => a?.type === "link" && a.primary === true && a.text?.trim().toLowerCase() === "watch now" && a.link?.type === "url") : [];
    if (actions.length !== 1 || !safeScorePage(actions[0]?.link?.value) || row._pageConflict) issues.push("identity-conflict");
    return record("score808", { id: "score808:" + row._widget + ":" + row.id, name: row.name }, "football", now,
      { sport: "football", participants: pair(row.name), ...(start ? { start } : {}), ...(end ? { end } : {}) }, issues);
  });
}
function safeScorePage(value) {
  try { const u = new URL(value); return u.protocol === "https:" && ["score808live.tv", "www.score808live.tv"].includes(u.hostname)
    && !u.port && !u.username && !u.password && !u.search && !u.hash && u.pathname !== "/"; } catch { return false; }
}

export const broadcastSourceParsers = Object.freeze({ csRow, asRow, fsRow, cncRow, svRow, svOriginals, dlhdOriginals, zonedDate });

function scopeResult(scope, records, complete, failure) {
  return { scope, status: failure ? "failed" : complete ? records.length ? "available" : "empty" : "partial", complete,
    ...(failure ? { failure } : {}) };
}
const reason = (error) => ["budget-exhausted", "unsupported-scope", "capacity-exceeded", "invalid-collection"].includes(error?.message) ? error.message : "source-unavailable";

function retrievalHints(fixtures, now) {
  if (!Array.isArray(fixtures) || fixtures.length > 3000) return [];
  const rank = (f) => ["premier-league", "champions-league"].includes(f.competitionID) ? 0 : f.sport === "cricket" ? 1 : 2;
  return fixtures.filter((f) => object(f) && f.verified === true && CS_SCOPES.includes(f.sport)
    && Array.isArray(f.participants) && f.participants.length === 2 && f.participants.every((p) => str(p, 256))
    && utc(f.observedAt) && +now - Date.parse(f.observedAt) >= -300_000 && +now - Date.parse(f.observedAt) <= 30 * 60_000
    && utc(f.start) && (f.status === "live" || f.status === "scheduled" && Math.abs(Date.parse(f.start) - +now) <= 30 * 60_000))
    .sort((a, b) => rank(a) - rank(b) || Number(b.status === "live") - Number(a.status === "live")
      || Math.abs(Date.parse(a.start) - +now) - Math.abs(Date.parse(b.start) - +now));
}
function asEnriched(row, scope, meta, now, originals) {
  const base = asRow(row, scope, now, originals);
  if (!base) return null;
  const conflict = () => ({ ...base, verification: "conflicting", issues: [...new Set([...base.issues, "identity-conflict"])] });
  if (!object(meta) || meta.id !== row.id || meta.type !== "tv" || !str(meta.name, 512) || typeof meta.description !== "string"
    || meta.description.length > 1024 || own(meta, "genres") && JSON.stringify(meta.genres) !== JSON.stringify(row.genres)
    || ["released", "releaseInfo", "date", "startTime", "kickoff", "videos", "behaviorHints"].some((k) => own(meta, k))) return conflict();
  if (/^plaviohdtv-dlhd-ev-/u.test(row.id) && (meta.name !== row.name || meta.description !== row.description)) return conflict();
  const candidate = asRow({ ...row, name: meta.name, description: meta.description }, scope, now, originals);
  if (!candidate || !samePair(base.participants, candidate.participants, base.sport)
    || ["format", "matchOrdinal", "day"].some((k) => base[k] != null && candidate[k] != null && base[k] !== candidate[k])) return conflict();
  // The already-reviewed Sfly Live meta route can add its explicit dated
  // description. The official fixture was only a retrieval hint, never a date.
  if (base.sport === "football" && /^plaviohdtv-sfly-streamed:[A-Za-z0-9][A-Za-z0-9_-]*$/u.test(row.id)) {
    const lines = meta.description.split("\n"), published = lines.length === 2 && lines[0] === meta.name ? englishUTC(lines[1]) : null;
    if (published && candidate.verification !== "conflicting") return { ...candidate, start: published, verification: "dated",
      issues: candidate.issues.filter((i) => !["missing-date", "unverified-fixture"].includes(i)) };
  }
  return candidate;
}
function searchableCatalog(m, scope) {
  for (const key of ["nuvio_sports_" + CS_SUFFIX(scope), "nuvio_sports_live"]) {
    const rows = m.catalogs.filter((r) => r?.id === key);
    if (rows.length === 1 && rows[0].type === "tv" && rows[0].extra?.some((e) => e?.name === "search")) return key;
  }
  return null;
}
function searchHint(name, category) {
  if (!str(name, 96)) return null;
  let entered = name.trim().replace(/\s+/gu, " ");
  if (category === "football") {
    const shorter = entered.split(" ").filter((t) => !["fc", "afc", "cf"].includes(t.toLowerCase())).join(" ");
    if (shorter !== entered && canonicalFootballClubId(shorter)) entered = shorter;
  }
  return encodeURIComponent(entered).replace(/[!'()*]/gu, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}

export async function collectBroadcastSource(providerCode, { now = new Date(), reserveRequest = async () => false,
  fetcher = fetch, signal, cursor = 0, fixtures = [] } = {}) {
  if (!BROADCAST_SOURCE_CODES.includes(providerCode) || !Number.isFinite(+new Date(now))) throw new Error("invalid-collection");
  now = new Date(now);
  const read = reader(providerCode, { fetcher, reserveRequest, signal }), broadcasts = [], scopes = [], hints = retrievalHints(fixtures, now);
  const cohort = async (scope, load, parse, complete = true) => {
    try {
      const rows = await load(), parsed = (await Promise.all(rows.map(parse))).filter(Boolean);
      const valid = parsed.length === rows.length;
      if (broadcasts.length + parsed.length > MAX_RECORDS) throw new Error("capacity-exceeded");
      broadcasts.push(...parsed); scopes.push(scopeResult(scope, parsed, complete && valid));
      return true;
    } catch (error) {
      if (signal?.aborted || error?.name === "AbortError") throw error;
      const failure = reason(error); scopes.push(failure === "unsupported-scope" ? { scope, status: "unsupported", complete: false, failure } : scopeResult(scope, [], false, failure));
      return false;
    }
  };
  try {
    if (providerCode === "streamex") {
      const profiles = [["https://www.streamex.net", "/api/live/matches"], ["https://streamex.sh", "/api/live/matches"], ["https://streamed.pk", "/api/matches"]];
      for (const [origin, prefix] of profiles) {
        const ok = await cohort("live", async () => {
          const body = await read(origin + prefix + "/all", 4 * MAX_BYTES); const rows = Array.isArray(body) ? body : body?.matches;
          if (!Array.isArray(rows) || rows.length > 2000) throw new Error("invalid-collection"); return rows;
        }, (row) => {
          if (!object(row)) return null;
          const ms = Number.isSafeInteger(row.date) ? row.date > 10_000_000_000 ? row.date : row.date * 1000 : NaN;
          const validDate = Number.isFinite(ms) && ms >= 946684800_000 && ms <= 4102444800_000;
          return record(providerCode, row, "live", now, { sport: sport(row.category), participants: row.teams?.home?.name && row.teams?.away?.name
            ? [row.teams.home.name, row.teams.away.name] : pair(row.title), ...(validDate ? { start: new Date(ms).toISOString() } : {}) },
            row.date != null && !validDate ? ["time-conflict"] : []);
        });
        if (ok) break;
      }
    } else if (providerCode === "score808") {
      await collectScore808({ read, now, cohort });
    } else {
      const m = manifest(await read(ORIGINS[providerCode] + "/manifest.json", 128 * KiB), providerCode);
      if (providerCode === "communitysports") {
        const rotating = CS_SCOPES.slice(2).filter((scope) => m.catalogs.some((c) => c?.id === "nuvio_sports_" + CS_SUFFIX(scope) && c.type === "tv"));
        const safeCursor = Number.isInteger(cursor) && cursor >= 0 && cursor <= 65535 ? cursor : 0;
        const offset = rotating.length ? (safeCursor & 255) % rotating.length : 0;
        for (const scope of CS_SCOPES.slice(2).filter((s) => !rotating.includes(s))) scopes.push({ scope, status: "unsupported", complete: false, failure: "unsupported-scope" });
        let advanced = 0;
        const readScope = async (scope) => {
          const name = "nuvio_sports_" + CS_SUFFIX(scope);
          return await cohort(scope, async () => { advertised(m, name); return safeRows(await read(ORIGINS[providerCode] + "/catalog/tv/" + name + ".json", 700 * KiB), 600); },
            (row) => csRow(row, scope, now), false);
        };
        for (const scope of ["live", "networks", "football", "cricket"]) await readScope(scope);
        const uncovered = hints.filter((f) => searchableCatalog(m, f.sport) && !broadcasts.some((b) => b.kind !== "channel" && b.verification === "dated"
          && b.sport === f.sport && samePair(b.participants, f.participants, f.sport)
          && (f.format === "Test" ? b.format === "Test" && b.matchOrdinal === f.matchOrdinal && b.day === f.day && b.start >= f.start && f.end && b.start < f.end
            : Math.abs(Date.parse(b.start) - Date.parse(f.start)) <= 15 * 60_000)));
        let hintAdvanced = 0;
        if (uncovered.length) {
          const target = uncovered[(safeCursor >>> 8) % uncovered.length], key = searchableCatalog(m, target.sport);
          for (const participant of target.participants) {
            if (read.count() >= 8) break;
            const query = searchHint(participant, target.sport); if (!query) continue;
            const ok = await cohort(target.sport, async () => safeRows(await read(ORIGINS[providerCode] + "/catalog/tv/" + key + "/search=" + query + ".json", 700 * KiB), 600),
              (row) => csRow(row, target.sport, now), false);
            if (ok) hintAdvanced = 1;
          }
        }
        for (let n = 0; n < Math.min(3, rotating.length) && read.count() < 8; n++) if (await readScope(rotating[(offset + n) % rotating.length])) advanced++;
        cursor = (((safeCursor >>> 8) + hintAdvanced) % 256) * 256 + (rotating.length ? (offset + advanced) % rotating.length : 0);
      } else if (providerCode === "plaviosports") {
        let originals = [], originalRead = false; const rawRows = [];
        for (const scope of ["football", "cricket", "live"]) {
          const name = scope === "football" ? m.catalogs.some((c) => c.id === "plaviohd-football") ? "plaviohd-football" : "plaviohd-live-sports"
            : scope === "cricket" ? "plaviohd-cricket" : "plaviohd-live-sports";
          await cohort(scope, async () => {
            advertised(m, name); const rows = safeRows(await read(ORIGINS[providerCode] + "/catalog/tv/" + name + ".json", 512 * KiB), 600);
            rawRows.push(...rows.map((row) => ({ row, scope })));
            if (scope === "football" && rows.some((r) => /^plaviohdtv-dlhd-ev-/u.test(r?.id ?? "")) && !originalRead) {
              originalRead = true;
              try { originals = dlhdOriginals(await read(AS_ORIGINAL, MAX_BYTES, true)); }
              catch (error) { if (signal?.aborted || error?.name === "AbortError") throw error; scopes.push(scopeResult("football", [], false, reason(error))); }
            }
            return rows;
          }, (row) => asRow(row, scope, now, originals), false);
        }
        const candidates = [];
        for (const { row, scope } of rawRows) {
          if (!id(row?.id) || candidates.some((c) => c.row.id === row.id)) continue;
          const base = asRow(row, scope, now, originals);
          if (!base || base.verification !== "undated" || base.kind !== "event" || !hints.some((f) => f.sport === base.sport && samePair(f.participants, base.participants, f.sport))) continue;
          const knownID = /^plaviohdtv-(?:dlhd-ev-[a-z0-9]{1,32}|sfly-streamed:[A-Za-z0-9][A-Za-z0-9_-]*)$/u.test(row.id);
          if (!knownID || !m.resources.some((r) => object(r) && r.name === "meta" && r.types?.includes("tv") && r.idPrefixes?.some((p) => row.id.startsWith(p)))) continue;
          const identity = (r) => JSON.stringify([r.type, r.name, r.description, r.genres, ["released", "releaseInfo", "date", "startTime", "kickoff", "videos", "behaviorHints"].filter((k) => own(r, k))]);
          const siblings = rawRows.filter((s) => s.row?.id === row.id);
          if (siblings.some((s) => identity(s.row) !== identity(row))) {
            for (let i = 0; i < broadcasts.length; i++) if (broadcasts[i].providerEventID === row.id) broadcasts[i] = { ...broadcasts[i], verification: "conflicting", issues: [...new Set([...broadcasts[i].issues, "identity-conflict"])] };
            continue;
          }
          candidates.push({ row, scope, siblings });
        }
        const offset = candidates.length && Number.isInteger(cursor) && cursor >= 0 ? cursor % candidates.length : 0;
        let advanced = 0;
        for (let n = 0; n < Math.min(2, candidates.length) && read.count() < 8; n++) {
          const candidate = candidates[(offset + n) % candidates.length];
          try {
            const document = await read(ORIGINS[providerCode] + "/meta/tv/" + encodeURIComponent(candidate.row.id) + ".json", 512 * KiB);
            for (const sibling of candidate.siblings) {
              const enriched = asEnriched(sibling.row, sibling.scope, document?.meta, now, originals);
              if (enriched) for (let i = 0; i < broadcasts.length; i++) if (broadcasts[i].providerEventID === sibling.row.id && broadcasts[i].scope === sibling.scope) broadcasts[i] = enriched;
            }
            advanced++;
          } catch (error) { if (signal?.aborted || error?.name === "AbortError") throw error; scopes.push(scopeResult(candidate.scope, [], false, reason(error))); }
        }
        cursor = candidates.length ? (offset + advanced) % candidates.length : 0;
      } else if (providerCode === "cncsports") {
        await cohort("hockey", async () => { advertised(m, "cnc_LivXowLiveEvents_tv"); return safeRows(await read(ORIGINS[providerCode] + "/catalog/tv/cnc_LivXowLiveEvents_tv.json", 512 * KiB), 600); }, (row) => cncRow(row, now), false);
      } else if (providerCode === "flixstreams") {
        advertised(m, "essential-live-events", (c) => c.extra?.some((e) => e.name === "skip" && e.isRequired !== true)
          && c.extra?.some((e) => e.name === "genre" && e.isRequired !== true && e.options?.includes("soccer") && e.options?.includes("cricket")));
        for (const scope of ["football", "cricket"]) await cohort(scope, async () => {
          const rows = [];
          for (const skip of [0, 40, 80]) rows.push(...safeRows(await read(ORIGINS[providerCode] + "/catalog/tv/essential-live-events/genre="
            + (scope === "football" ? "soccer" : "cricket") + (skip ? "&skip=" + skip : "") + ".json", 512 * KiB), 40));
          return rows;
        }, (row) => fsRow(row, scope, now), false);
      } else if (providerCode === "streamvix") {
        advertised(m, "streamvix_eventi", (c) => c.extra?.some((e) => e.name === "genre" && e.isRequired === true
          && e.options?.includes("Premier League") && e.options?.includes("Coppe")));
        let originals = [];
        try { originals = svOriginals(await read(SV_ORIGINAL, MAX_BYTES)); }
        catch (error) { if (signal?.aborted || error?.name === "AbortError") throw error; scopes.push(scopeResult("football", [], false, reason(error))); }
        for (const genre of ["Premier League", "Coppe"]) await cohort("football", async () => safeRows(await read(ORIGINS[providerCode]
          + "/catalog/tv/streamvix_eventi/genre=" + encodeURIComponent(genre) + ".json", 512 * KiB), 200), (row) => svRow(row, genre, now, originals), false);
      }
    }
  } catch (error) {
    if (signal?.aborted || error?.name === "AbortError") throw error;
    scopes.push(scopeResult("live", [], false, reason(error)));
  }
  // Several fixed profiles/genres can share a logical cohort. A healthy
  // sibling stays positive, while an incomplete/failed sibling forbids absence.
  const combinedScopes = [...new Set(scopes.map((s) => s.scope))].map((scope) => {
    const entries = scopes.filter((s) => s.scope === scope), complete = entries.every((s) => s.complete);
    const rows = broadcasts.filter((b) => b.scope === scope), healthy = entries.some((s) => ["available", "empty", "partial"].includes(s.status));
    if (entries.every((s) => s.status === "unsupported")) return entries[0];
    const failure = entries.find((s) => s.failure)?.failure;
    return { scope, complete, status: complete ? rows.length ? "available" : "empty" : healthy ? "partial" : "failed", ...(failure ? { failure } : {}) };
  });
  const result = { providerCode, observedAt: now.toISOString(), complete: combinedScopes.length > 0 && combinedScopes.every((s) => s.complete), scopes: combinedScopes, broadcasts,
    ...(["communitysports", "plaviosports"].includes(providerCode) ? { cursor } : {}) };
  if (new TextEncoder().encode(JSON.stringify(result)).byteLength > MAX_BYTES) return { providerCode, observedAt: now.toISOString(), complete: false,
    scopes: scopes.map((s) => scopeResult(s.scope, [], false, "capacity-exceeded")), broadcasts: [] };
  return result;
}

function score808WidgetID(text) {
  // Extract a narrow metadata contract; never sanitize or render HTML. Only a
  // literal widget class on a div outside prohibited/explicitly hidden markup
  // is evidence. This is not proof of browser/CSS visibility or stream delivery.
  // Unsupported, malformed or ambiguous HTML fails closed instead of being
  // repaired like a browser document. Limits are also enforced for direct calls.
  if (typeof text !== "string" || text.length > STAGE_LIMITS.catalog || text.includes("\0")
    || new TextEncoder().encode(text).byteLength > STAGE_LIMITS.catalog) return false;
  const space = (char) => char === " " || char === "\t" || char === "\n" || char === "\r" || char === "\f";
  const letter = (char) => char !== undefined && /[a-z]/i.test(char);
  const nameChar = (char) => char !== undefined && /[a-z0-9:-]/i.test(char);
  const boundary = (char) => char === ">" || char === "/" || space(char);
  const voidTags = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
  const rawTags = new Set(["script", "style", "title", "textarea", "xmp", "iframe", "noembed", "noframes"]);
  const prohibited = new Set(["head", "template", "noscript", "svg", "math", "select", "datalist", "option", "optgroup",
    "canvas", "audio", "video", "object", "frameset", ...rawTags]);
  const closesParagraph = new Set(["address", "article", "aside", "blockquote", "details", "dialog", "div", "dl", "fieldset", "figcaption", "figure",
    "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "search", "section", "table", "ul"]);
  const retainsParagraph = new Set(["a", "audio", "del", "ins", "map", "noscript", "video"]);
  const stack = [], ids = new Set(); let offset = 0, tokens = 0;

  function tagAt(start) {
    let index = start + 1, closing = false;
    if (text[index] === "/") { closing = true; index++; }
    if (!letter(text[index])) return null;
    const nameStart = index++;
    while (nameChar(text[index])) index++;
    const name = text.slice(nameStart, index).toLowerCase(), attributes = new Map();
    if (!boundary(text[index])) return null;
    while (index < text.length) {
      const beforeSpace = index;
      while (space(text[index])) index++;
      if (text[index] === ">") return { name, closing, attributes, end: index + 1, selfClosing: false };
      if (text[index] === "/" && text[index + 1] === ">") {
        // HTML ignores non-void self-closing flags; treating them as closed can
        // expose a candidate that is actually still inside script/hidden markup.
        if (closing || !voidTags.has(name)) return null;
        return { name, closing, attributes, end: index + 2, selfClosing: true };
      }
      if (closing || beforeSpace === index || attributes.size >= 128) return null;
      const attributeStart = index;
      while (index < text.length && !space(text[index]) && !["=", "/", ">"].includes(text[index])) {
        if (["<", "\"", "'", "`"].includes(text[index])) return null;
        index++;
      }
      if (index === attributeStart) return null;
      const attribute = text.slice(attributeStart, index).toLowerCase();
      if (attributes.has(attribute)) return null;
      const attributeEnd = index;
      while (space(text[index])) index++;
      let value = "";
      if (text[index] === "=") {
        index++; while (space(text[index])) index++;
        const quote = text[index] === "\"" || text[index] === "'" ? text[index++] : null;
        const valueStart = index;
        if (quote) {
          while (index < text.length && text[index] !== quote) index++;
          if (index === text.length) return null;
          value = text.slice(valueStart, index++);
          if (!space(text[index]) && text[index] !== ">" && !(text[index] === "/" && text[index + 1] === ">")) return null;
        } else {
          while (index < text.length && !space(text[index]) && text[index] !== ">") {
            if (["<", "\"", "'", "`", "="].includes(text[index])) return null;
            index++;
          }
          if (index === valueStart) return null;
          value = text.slice(valueStart, index);
        }
      } else index = attributeEnd;
      attributes.set(attribute, value);
    }
    return null;
  }

  function rawEnd(name, start) {
    const endPrefix = `</${name}`, startPrefix = `<${name}`;
    for (let index = text.indexOf("<", start); index !== -1; index = text.indexOf("<", index + 1)) {
      // Script escaped/double-escaped states require browser tokenization.
      // Reject that unsupported grammar, rather than ending raw text too soon.
      if (name === "script" && (text.startsWith("<!--", index)
        || text.slice(index, index + startPrefix.length).toLowerCase() === startPrefix && boundary(text[index + startPrefix.length]))) return null;
      if (text.slice(index, index + endPrefix.length).toLowerCase() !== endPrefix || !boundary(text[index + endPrefix.length])) continue;
      const end = tagAt(index);
      return end?.closing && end.name === name ? end : null;
    }
    return null;
  }

  while (offset < text.length) {
    const next = text.indexOf("<", offset);
    if (next === -1) break;
    if (++tokens > 50_000) return false;
    if (text.startsWith("<!--", next)) {
      const end = text.indexOf("-->", next + 4);
      if (end === -1) return false;
      // Nested/alternate comment delimiters are not repaired or re-scanned.
      const comment = text.slice(next + 4, end);
      if (comment.includes("<!--") || comment.includes("--!>")) return false;
      offset = end + 3; continue;
    }
    if (text.slice(next, next + 9).toLowerCase() === "<!doctype") {
      const end = text.indexOf(">", next + 9);
      if (end === -1 || text.slice(next + 9, end).trim().toLowerCase() !== "html" || stack.length) return false;
      offset = end + 1; continue;
    }
    const tag = tagAt(next);
    if (!tag || tag.name === "plaintext") return false;
    offset = tag.end;
    if (tag.closing) {
      // The reviewed listing omits </p> immediately before its parent closes.
      // This limited optional-end-tag case is defined by the HTML standard;
      // other misnesting is still unsupported, never repaired speculatively.
      if (stack.at(-1)?.name === "p" && stack.at(-2)?.name === tag.name
        && !retainsParagraph.has(tag.name) && !tag.name.includes("-")) stack.pop();
      if (voidTags.has(tag.name) || stack.at(-1)?.name !== tag.name) return false;
      stack.pop(); continue;
    }
    if (stack.at(-1)?.name === "p" && closesParagraph.has(tag.name)) stack.pop();
    const attributes = tag.attributes, classes = attributes.get("class") || "", style = attributes.get("style") || "";
    const ariaHidden = attributes.get("aria-hidden") || "";
    // Entity/escape/comment spellings can change class or inline visibility in
    // the browser. They are outside this literal reviewed listing contract.
    if (classes.includes("&") || ariaHidden.includes("&") || style.includes("\\") || style.includes("/*") || style.includes("&")) return false;
    const hidden = stack.at(-1)?.hidden || prohibited.has(tag.name) || attributes.has("hidden") || attributes.has("inert")
      || ariaHidden.trim().toLowerCase() === "true"
      // Recognize simple CSS zero spellings (including percentages/exponents),
      // not calc(), variables or computed CSS. Unit-bearing/unfinished tokens
      // are invalid opacity values and must not be mistaken for numeric zero.
      || /(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse)|opacity\s*:\s*[+-]?(?:0+(?:\.0+)?|\.0+)(?:e[+-]?[0-9]+)?%?)\s*(?:!\s*important\s*)?(?:;|$)/i.test(style);
    if (tag.name === "div" && !hidden) {
      for (const token of classes.split(/[\t\n\r\f ]+/)) {
        if (!token.toLowerCase().startsWith("elfsight-app-")) continue;
        if (!/^elfsight-app-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(token)) return false;
        ids.add(token.slice("elfsight-app-".length).toLowerCase());
      }
    }
    if (rawTags.has(tag.name)) {
      const end = rawEnd(tag.name, offset);
      if (!end) return false;
      offset = end.end;
    } else if (!voidTags.has(tag.name)) {
      if (stack.length >= 256) return false;
      stack.push({ name: tag.name, hidden });
    }
  }
  return stack.length === 0 && ids.size === 1 ? [...ids][0] : null;
}

