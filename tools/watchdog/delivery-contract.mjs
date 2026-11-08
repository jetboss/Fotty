// Metadata-only consumer-shape supervision. This never fetches a delivery URL
// and is not native admission, media validation, or decoded-playback proof.
import { canonicalFootballClubId } from "../../web/src/lib/football-competition-catalog.generated.ts";
import { EXPECTED_VERSIONS } from "./manifest.mjs";

const ORIGIN = "https://nuviosports.xyz";
const SCOPES = ["premier-league", "champions-league", "carabao-cup", "la-liga", "serie-a", "bundesliga", "ligue-1"];
const FRESH = 30 * 60_000, FUTURE = 5 * 60_000, TOLERANCE = 15 * 60_000;
const PINNED_8443 = "6f9cf8e38a18ecd21731b9ed9f6328fc9c97fadb5f7e6c911d88eaa49b2e19ce";
const SQUAD = /\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b/g;
const normalized = (value) => typeof value === "string" ? value.normalize("NFD").replace(/\p{Diacritic}/gu, "")
  .toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ") : "";
const scalar = (value, max = 256) => typeof value === "string" && value.length > 0 && value.length <= max;
const safeID = (value) => typeof value === "string" && value.startsWith("nuvio_sport_")
  && value.length <= 240 && /^[A-Za-z0-9_.~-]+$/.test(value);
function instant(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) return null;
  const [hour, minute, second] = value.slice(11, 19).split(":").map(Number);
  if (hour > 23 || minute > 59 || second > 59) return null;
  const offset = value.match(/([+-])(\d{2}):(\d{2})$/);
  if (offset && (Number(offset[2]) > 23 || Number(offset[3]) > 59)) return null;
  const calendar = value.slice(0, 10), date = new Date(`${calendar}T00:00:00Z`);
  const result = Date.parse(value);
  return Number.isFinite(result) && Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === calendar ? result : null;
}
function fresh(value, now) { const time = instant(value); return time !== null && now - time <= FRESH && time - now <= FUTURE; }
function team(raw) {
  const text = normalized(raw), tokens = [...text.matchAll(SQUAD)].map(([token]) => {
    const compact = token.replace(/ /g, "");
    return ["women", "womens", "ladies", "w"].includes(compact) ? "women"
      : ["reserve", "reserves"].includes(compact) ? "reserves" : compact.replace(/^under/, "u");
  });
  const base = text.replace(SQUAD, " ").trim().replace(/\s+/g, " ");
  if (!base) return null;
  const known = canonicalFootballClubId(base), baseKey = known ? `football|${known}` : base;
  const squad = [...new Set(tokens)].sort();
  return { base: baseKey, squad, key: `${baseKey}|${squad.join(",")}` };
}
const pairKey = (names) => {
  const parsed = names.map(team);
  return parsed.length === 2 && parsed.every(Boolean) && parsed[0].key !== parsed[1].key
    ? parsed.map((row) => row.key).sort().join("::") : null;
};
function eligibleFixtures(snapshot, now) {
  if (!Number.isSafeInteger(now) || snapshot?.schemaVersion !== 1 || snapshot.complete !== true
    || !["verified", "partial"].includes(snapshot.sourceStatus) || !fresh(snapshot.checkedAt, now)
    || !Array.isArray(snapshot.fixtures) || snapshot.fixtures.length > 3000
    || !Array.isArray(snapshot.coverage) || snapshot.coverage.length > 100) return [];
  const counts = new Map();
  for (const row of snapshot.fixtures) counts.set(row?.id, (counts.get(row?.id) || 0) + 1);
  return snapshot.fixtures.filter((row) => {
    if (!row || row.sport !== "football" || row.status !== "live" || row.eventKind !== "match"
      || !SCOPES.includes(row.competitionId) || !scalar(row.id) || counts.get(row.id) !== 1
      || !row.id.startsWith(`sports-fixture:${row.competitionId}:`)
      || row.squad?.gender !== "men" || row.squad?.ageGroup !== "senior"
      || !Array.isArray(row.participants) || row.participants.length !== 2
      || !row.participants.every((person) => scalar(person.id) && scalar(person.name))
      || row.participants[0].id === row.participants[1].id) return false;
    const pair = pairKey(row.participants.map((person) => person.name));
    if (!pair || row.participants.some((person) => team(person.name).squad.length)) return false;
    const kickoff = instant(row.start), observed = instant(row.source?.observedAt);
    const coverage = snapshot.coverage.filter((scope) => scope?.competitionId === row.competitionId && scope.sport === "football");
    if (coverage.length !== 1 || kickoff === null || kickoff > now + FUTURE || kickoff < now - 4 * 3600_000
      || observed === null || !fresh(row.source.observedAt, now) || observed > instant(snapshot.checkedAt)
      || row.source.updatedAt != null && !fresh(row.source.updatedAt, now)) return false;
    const explicit = Object.hasOwn(row.source, "verification");
    return explicit ? row.source.verification === "verified" && ["covered", "unavailable"].includes(coverage[0].status)
      : coverage[0].status === "covered" && coverage[0].checkedAt === row.source.observedAt;
  }).sort((a, b) => SCOPES.indexOf(a.competitionId) - SCOPES.indexOf(b.competitionId)
    || instant(a.start) - instant(b.start) || a.id.localeCompare(b.id)).slice(0, 32);
}
export function selectCSDeliveryFixture(snapshot, now = Date.now()) { return eligibleFixtures(snapshot, now)[0] || null; }

function catalogPair(entry) {
  let title = entry.name;
  if (typeof title !== "string" || title.length > 512) return null;
  const colon = title.indexOf(":");
  if (colon >= 0 && ["live", "upcoming"].includes(normalized(title.slice(0, colon)))) title = title.slice(colon + 1).trim();
  const separators = [...title.matchAll(/\s+(?:vs\.?|v\.?|versus|@)\s+/gi)];
  const cast = Array.isArray(entry.cast) ? entry.cast.filter((name) => typeof name === "string" && name.trim()) : [];
  if (!separators.length) return cast.length === 2 ? pairKey(cast) : null;
  if (separators.length !== 1 || /[|•·()\[\]:\n\r\t<>]/.test(title) || / [-–—] /.test(title)) return null;
  const found = title.match(/^(.+?)\s+(?:vs\.?|v\.?|versus|@)\s+(.+?)$/i);
  if (!found) return null;
  const names = [found[1].trim(), found[2].trim()];
  if (cast.length !== 2) return pairKey(names);
  const titleTeams = names.map(team), castTeams = cast.map(team);
  if ([...titleTeams, ...castTeams].some((row) => !row)
    || new Set(titleTeams.map((row) => row.base)).size !== 2
    || new Set(castTeams.map((row) => row.base)).size !== 2) return null;
  const merged = [];
  for (const row of castTeams) {
    const sibling = titleTeams.find((candidate) => candidate.base === row.base);
    if (!sibling || row.squad.length && sibling.squad.length && row.squad.join() !== sibling.squad.join()) return null;
    merged.push(`${row.base}|${(row.squad.length ? row.squad : sibling.squad).join(",")}`);
  }
  return merged.sort().join("::");
}
function identity(entry) {
  if (!scalar(entry?.id, 240) || !entry.id.startsWith("nuvio_sport_")
    || entry.type != null && entry.type !== "tv" || !["football", "soccer"].includes(normalized(entry.genres?.[0]))) return null;
  if (entry.cast != null && (!Array.isArray(entry.cast) || entry.cast.some((name) => typeof name !== "string"))
    || !Array.isArray(entry.genres) || entry.genres.some((name) => typeof name !== "string")
    || entry.behaviorHints != null && (typeof entry.behaviorHints !== "object" || Array.isArray(entry.behaviorHints))) return null;
  const time = instant(entry.released), pair = catalogPair(entry), target = entry.behaviorHints?.defaultVideoId ?? entry.id;
  return time !== null && pair && typeof target === "string" ? { pair, time, target, type: entry.type ?? "tv" } : null;
}
export function selectCSCatalogMatch(fixture, catalog) {
  if (!fixture || !Array.isArray(catalog?.metas) || catalog.metas.length > 600) return { outcome: "missing" };
  const pair = pairKey(fixture.participants.map((person) => person.name)), kickoff = instant(fixture.start);
  const candidates = catalog.metas.map((entry) => ({ entry, identity: identity(entry) }));
  const matching = candidates.filter((row) => row.identity && row.identity.pair === pair && Math.abs(row.identity.time - kickoff) <= TOLERANCE);
  for (const row of matching) {
    const siblings = candidates.filter((candidate) => candidate.entry?.id === row.entry.id
      || (candidate.entry?.behaviorHints?.defaultVideoId ?? candidate.entry?.id) === row.identity.target);
    if (siblings.some((candidate) => !candidate.identity || JSON.stringify(candidate.identity) !== JSON.stringify(row.identity))) return { outcome: "conflicting" };
  }
  if (new Set(matching.map((row) => row.entry.id)).size > 1) return { outcome: "conflicting" };
  return matching.length && safeID(matching[0].identity.target)
    ? { outcome: "matched", entry: matching[0].entry, streamID: matching[0].identity.target } : { outcome: "missing" };
}

function publicIP(host) {
  if (/^\d+(?:\.\d+){3}$/.test(host)) {
    const [a, b, c, d] = host.split(".").map(Number);
    if ([a, b, c, d].some((part) => part > 255)) return false;
    return !(a === 0 || a === 10 || a === 127 || a >= 224 || a === 100 && b >= 64 && b <= 127
      || a === 169 && b === 254 || a === 172 && b >= 16 && b <= 31
      || a === 192 && (b === 168 || b === 0 && (c === 0 || c === 2) || b === 88 && c === 99)
      || a === 198 && (b === 18 || b === 19 || b === 51 && c === 100) || a === 203 && b === 0 && c === 113);
  }
  if (host.includes(":")) {
    const [head, tail] = host.replace(/^\[|\]$/g, "").split("::");
    const left = head ? head.split(":") : [], right = tail ? tail.split(":") : [];
    const groups = tail === undefined ? left : [...left, ...Array(8 - left.length - right.length).fill("0"), ...right];
    if (groups.length !== 8 || groups.some((part) => !/^[a-f0-9]{1,4}$/i.test(part))) return false;
    const [a, b] = groups.map((part) => parseInt(part, 16));
    return a >= 0x2000 && a <= 0x3fff && !(a === 0x2001 && (b < 0x0200 || b === 0x0db8)
      || a === 0x2002 || a === 0x3fff && b < 0x1000);
  }
  return null;
}
function publicURL(url, exceptional = false) {
  if (url.protocol !== "https:" || url.username || url.password || url.href.includes("#") || url.href.length > 8192
    || url.port && url.port !== "443" && !(exceptional && url.port === "8443")) return false;
  const ip = publicIP(url.hostname);
  if (ip !== null) return ip;
  const labels = url.hostname.split(".");
  return labels.length >= 2 && url.hostname.length <= 253
    && !["localhost", "local", "internal", "intranet", "lan", "home", "test", "invalid", "onion"].includes(labels.at(-1))
    && labels.every((label) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label));
}
function parsedURL(raw) { try { return typeof raw === "string" ? new URL(raw) : null; } catch { return null; } }
const rawPath = (raw) => typeof raw === "string" ? raw.match(/^https:\/\/[^/?#]+([^?#]*)/i)?.[1] || "/" : "";
function manifestRoute(url, raw) { return url.origin === ORIGIN && !url.username && !url.password && !url.href.includes("#")
  && rawPath(raw) === url.pathname && ["/api/manifest", "/api/manifest.m3u8"].includes(url.pathname); }
function directRoute(url, hint, raw) { return hint === "sktech" && publicURL(url) && url.hostname === "dai-fancode.pages.dev"
  && !url.href.includes("?") && rawPath(raw) === url.pathname
  && /^\/mumbai\/[A-Za-z0-9][A-Za-z0-9_-]{0,239}\/index\.m3u8$/.test(url.pathname); }
function headers(entry, direct, url) {
  const proxy = entry.behaviorHints?.proxyHeaders;
  if (proxy == null) return direct ? null : {};
  if (typeof proxy !== "object" || Array.isArray(proxy)) return null;
  for (const key of ["request", "response"]) if (Object.hasOwn(proxy, key)
    && (proxy[key] === null || typeof proxy[key] !== "object" || Array.isArray(proxy[key])
      || Object.values(proxy[key]).some((value) => typeof value !== "string"))) return null;
  if (proxy.response && Object.keys(proxy.response).length) return null;
  const raw = proxy.request || {}, result = {};
  if (Object.keys(raw).length > 3) return null;
  for (const [key, value] of Object.entries(raw)) {
    const canonical = { referer: "Referer", origin: "Origin", "user-agent": "User-Agent" }[key.toLowerCase()];
    if (!canonical || Object.hasOwn(result, canonical) || !value || value.length > 512 || /[^\x20-\x7e]/.test(value)) return null;
    result[canonical] = value;
  }
  if (direct) return Object.keys(result).sort().join() === "Referer,User-Agent" && result.Referer === "https://fancode.com/"
    && result["User-Agent"].startsWith("ReactNativeVideo/") && result["User-Agent"].length > 17 ? result : null;
  for (const [key, parameter] of [["Referer", "referer"], ["Origin", "origin"]]) if (result[key]) {
    const values = [...url.searchParams].filter(([name]) => name.toLowerCase() === parameter).map((row) => row[1]);
    const provenance = parsedURL(result[key]);
    if (values.length !== 1 || values[0] !== result[key] || !provenance || !publicURL(provenance)
      || provenance.search || provenance.hash || key === "Origin" && provenance.pathname !== "/") return null;
  }
  if (result.Origin && result.Referer && parsedURL(result.Origin).origin !== parsedURL(result.Referer).origin) return null;
  return result;
}
async function exceptionalTarget(target, entry, header) {
  if (entry._source?.trim().toLowerCase() !== "daddylive" || !publicURL(target, true) || target.port !== "8443"
    || !target.pathname.toLowerCase().endsWith(".m3u8") || Object.keys(header).sort().join() !== "Origin,Referer,User-Agent") return false;
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`https|${target.hostname}|8443`));
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("") === PINNED_8443;
}
async function candidateShape(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) return "unsafe";
  for (const field of ["name", "title", "url", "externalUrl", "resolution", "quality", "_source"])
    if (entry[field] != null && typeof entry[field] !== "string") return "unsafe";
  if (entry.behaviorHints != null && (typeof entry.behaviorHints !== "object" || Array.isArray(entry.behaviorHints))) return "unsafe";
  const hint = entry._source?.trim().toLowerCase();
  let unsafe = false;
  for (const raw of [entry.url, entry.externalUrl]) {
    const url = parsedURL(raw); if (!url) continue;
    if (!publicURL(url) || url.href.includes("#") || /magnet:|acestream|:6878|\/proxy\/acestream\//i.test(url.href)) { unsafe = true; continue; }
    const direct = directRoute(url, hint, raw), wrapped = manifestRoute(url, raw);
    const web = url.origin === ORIGIN && (url.pathname === "/watch" || url.pathname.startsWith("/watch/"));
    if (!direct && !wrapped && !web) continue;
    const header = headers(entry, direct, url);
    if (!header || web && Object.keys(header).length) return "unsafe";
    if (wrapped) {
      const targets = [...url.searchParams].filter(([name]) => name.toLowerCase() === "url").map((row) => row[1]);
      const target = targets.length === 1 ? parsedURL(targets[0]) : null;
      if (!target || !publicURL(target) && !await exceptionalTarget(target, entry, header)) return "unsafe";
    }
    return web ? "web" : "compatible";
  }
  return unsafe ? "unsafe" : "unknown";
}
export async function classifyCSDeliveryDescriptor(body) {
  if (!body || typeof body !== "object" || Array.isArray(body) || body.streams != null && !Array.isArray(body.streams)) return { schemaValid: false };
  const entries = (body.streams || []).slice(0, 100), counts = { schemaValid: true, entryCount: entries.length,
    compatibleShapeCount: 0, compatibleHLSShapeCount: 0, compatibleWebShapeCount: 0, unsafeShapeCount: 0, unknownShapeCount: 0 };
  for (const entry of entries) {
    const shape = await candidateShape(entry);
    if (shape === "compatible" || shape === "web") {
      counts.compatibleShapeCount++;
      counts[shape === "web" ? "compatibleWebShapeCount" : "compatibleHLSShapeCount"]++;
    } else counts[`${shape}ShapeCount`]++;
  }
  return counts;
}

export async function probeCSDeliveryContract({ sportsSnapshot, catalog, manifest, now = Date.now(), environment = "production", read } = {}) {
  const facts = { scope: "football", dimension: "candidate-shape" };
  const observation = (outcome, failureClass = "delivery-contract-drift", extra = {}) => ({ source: "cs", stage: "delivery-contract",
    environment, observedAt: now, checkedAt: now, versions: { ...EXPECTED_VERSIONS }, outcome, failureClass, facts: { ...facts, ...extra } });
  if (!Array.isArray(manifest?.resources) || !manifest.resources.includes("stream")) return [observation("unknown")];
  let match;
  for (const fixture of eligibleFixtures(sportsSnapshot, now)) {
    const selected = selectCSCatalogMatch(fixture, catalog);
    if (selected.outcome === "conflicting") return [observation("unknown")];
    if (selected.outcome === "matched") { match = selected; break; }
  }
  if (!match || typeof read !== "function") return [observation("unknown")];
  let result;
  try { result = await read(`/stream/tv/${encodeURIComponent(match.streamID)}.json`, "delivery-contract"); }
  catch { return [observation("failure", "descriptor-transport")]; }
  if (result?.failure) return [observation(result.unknown ? "unknown" : "failure", "descriptor-transport")];
  const shape = await classifyCSDeliveryDescriptor(result?.body);
  if (!shape.schemaValid) return [observation("failure", "descriptor-schema")];
  if (!shape.entryCount) return [observation("unknown")];
  // A web fallback may still be useful to a user, but it cannot establish that
  // the reviewed native HLS contract has recovered. Do not call it an outage.
  return [observation(shape.compatibleHLSShapeCount ? "success" : shape.compatibleWebShapeCount ? "unknown" : "failure")];
}
