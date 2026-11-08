// Pure evidence from already-read CS catalog metadata, not source availability,
// stream admission, fixture freshness or decoded playback. No I/O or clocks.
// The participant/title/duplicate rules mirror CommunitySportsAddonClient and
// ReviewedSportsFixtureMatcher. Extra cricket context checks are conservative
// monitor limits, not changes to the native adapter's generic CS admission.
const TOLERANCE = 15 * 60_000;
const SQUAD = /\b(?:women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|w)\b/g;
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v, max = 512) => typeof v === "string" && v.length > 0 && v.length <= max && !/[\u0000-\u001f\u007f]/u.test(v);
const normal = (v) => typeof v === "string" ? v.normalize("NFKD").replace(/\p{M}/gu, "")
  .toLowerCase().replace(/&/g, " and ").replace(/[^\p{L}\p{N}]+/gu, " ").trim().replace(/\s+/g, " ") : "";
const safeID = (v) => typeof v === "string" && /^nuvio_sport_[A-Za-z0-9_.~-]+$/.test(v) && v.length <= 240;
const result = (outcome, reason) => ({ outcome, reason });

function instant(v) {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(v)) return null;
  const [h, m, s] = v.slice(11, 19).split(":").map(Number), offset = v.match(/[+-](\d{2}):(\d{2})$/);
  if (h > 23 || m > 59 || s > 59 || offset && (Number(offset[1]) > 23 || Number(offset[2]) > 59)) return null;
  const day = new Date(v.slice(0, 10) + "T00:00:00Z"), time = Date.parse(v);
  return Number.isFinite(time) && Number.isFinite(day.getTime()) && day.toISOString().slice(0, 10) === v.slice(0, 10) ? time : null;
}

// Only aliases already explicitly present in SportsTeamIdentity.cplNames.
const CPL = new Map([
  ["antigua and barbuda falcons", "antigua and barbuda falcons"], ["antigua falcons", "antigua and barbuda falcons"],
  ["barbados tridents", "barbados tridents"], ["barbados royals", "barbados tridents"],
  ["saint lucia kings", "saint lucia kings"], ["st lucia kings", "saint lucia kings"],
  ["st kitts and nevis patriots", "st kitts and nevis patriots"],
  ["saint kitts and nevis patriots", "st kitts and nevis patriots"], ["st kitts nevis patriots", "st kitts and nevis patriots"],
]);
function team(raw) {
  if (!text(raw)) return null;
  const value = normal(raw), squad = [...new Set([...value.matchAll(SQUAD)].map(([token]) => {
    const compact = token.replace(/ /g, "");
    return ["women", "womens", "ladies", "w"].includes(compact) ? "women"
      : ["reserve", "reserves"].includes(compact) ? "reserves" : compact.replace(/^under/, "u");
  }))].sort();
  const base = value.replace(SQUAD, " ").trim().replace(/\s+/g, " ");
  if (["", "home", "away", "tbd", "tbc", "unknown"].includes(base)) return null;
  const canonical = CPL.get(base) || base;
  return { base: canonical, squad, key: `${canonical}|${squad.join(",")}` };
}
function pair(names) {
  if (!Array.isArray(names) || names.length !== 2) return null;
  const rows = names.map(team);
  return rows.every(Boolean) && rows[0].key !== rows[1].key ? rows.map((r) => r.key).sort().join("::") : null;
}
function catalogPair(entry) {
  if (!text(entry.name) || entry.cast != null && (!Array.isArray(entry.cast) || entry.cast.some((v) => typeof v !== "string"))) return null;
  let title = entry.name.trim();
  const colon = title.indexOf(":");
  if (colon >= 0 && ["live", "upcoming"].includes(normal(title.slice(0, colon)))) title = title.slice(colon + 1).trim();
  const cast = (entry.cast || []).map((v) => v.trim()).filter(Boolean);
  const separators = [...title.matchAll(/\s+(?:vs\.?|v\.?|versus|@)\s+/gi)];
  if (!separators.length) return cast.length === 2 ? pair(cast) : null;
  if (separators.length !== 1 || /[|•·()\[\]:\n\r\t<>]/.test(title) || / [-–—] /.test(title)) return null;
  const split = title.split(/\s+(?:vs\.?|v\.?|versus|@)\s+/i), titleRows = split.map(team);
  if (!pair(split)) return null;
  if (cast.length !== 2) return pair(split);
  const castRows = cast.map(team);
  if (castRows.some((v) => !v) || new Set(titleRows.map((v) => v.base)).size !== 2
    || new Set(castRows.map((v) => v.base)).size !== 2) return null;
  const merged = [];
  for (const row of castRows) {
    const sibling = titleRows.find((v) => v.base === row.base);
    if (!sibling || row.squad.length && sibling.squad.length && row.squad.join() !== sibling.squad.join()) return null;
    merged.push(`${row.base}|${(row.squad.length ? row.squad : sibling.squad).join(",")}`);
  }
  return merged.sort().join("::");
}
function qualifiers(value) {
  if (!text(value, 1024)) return null;
  const formats = new Set();
  for (const [pattern, format] of [[/\b(?:T20I?|T20 International)\b/gi, "T20"], [/\b(?:ODI|One Day International)\b/gi, "ODI"],
    [/\bT10\b/gi, "T10"], [/\bTest\b/gi, "Test"]]) if (pattern.test(value)) formats.add(format);
  if (formats.size > 1 || /\b(?:sixes|6[- ]a[- ]side)\b/i.test(value)) return null;
  const ordinals = [...value.matchAll(/\b([1-9][0-9]?)(st|nd|rd|th)\s+(T20I?|ODI|T10|Test)\b/gi)].map((m) => {
    const n = Number(m[1]), suffix = n % 100 >= 11 && n % 100 <= 13 ? "th" : ({ 1: "st", 2: "nd", 3: "rd" }[n % 10] || "th");
    return m[2].toLowerCase() === suffix ? n : null;
  });
  const days = [...value.matchAll(/\bday[- ]?([1-6])\b/gi)].map((m) => Number(m[1]));
  if (ordinals.includes(null) || new Set(ordinals).size > 1 || new Set(days).size > 1) return null;
  return { format: [...formats][0] || null, ordinal: ordinals[0] ?? null, day: days[0] ?? null };
}
function officialIdentity(fixture) {
  if (!object(fixture) || !text(fixture.id, 256) || !["T20", "ODI", "T10", "Test"].includes(fixture.format)
    || !text(fixture.home?.id, 256) || !text(fixture.away?.id, 256) || fixture.home.id === fixture.away.id
    || !text(fixture.competitionName)
    || object(fixture.source) && Object.hasOwn(fixture.source, "verification") && fixture.source.verification !== "verified") return null;
  const identity = pair([fixture.home.name, fixture.away.name]), time = instant(fixture.start), q = qualifiers(fixture.competitionName);
  if (!identity || time === null || !q || q.format !== null && q.format !== fixture.format) return null;
  // A competition's independent squad qualifier cannot be erased by a canonical
  // pair projection, matching the native request-title bypass's restriction.
  const participantSquads = new Set([fixture.home.name, fixture.away.name].flatMap((v) => team(v).squad));
  if (team(fixture.competitionName)?.squad.some((v) => !participantSquads.has(v))) return null;
  const context = fixture.context;
  if (context != null && (!object(context) || context.phase != null && context.phase !== "in-play"
    || context.day != null && (!Number.isSafeInteger(context.day) || context.day < 1 || context.day > 6))) return null;
  const day = context?.day ?? q.day;
  if (context?.day != null && q.day !== null && context.day !== q.day) return null;
  if (fixture.format === "Test" ? day !== 1 : day != null) return null;
  return { pair: identity, time, format: fixture.format, ordinal: q.ordinal, day: day ?? null };
}

// Capability only. Caller still owns accepted source/status/freshness and a real
// live-window check; this function never interprets elapsed kickoff as LIVE.
export function supportsCSCricketFixture(fixture) { return officialIdentity(fixture) !== null; }

function catalogIdentity(entry) {
  if (!object(entry) || !safeID(entry.id) || entry.type != null && entry.type !== "tv"
    || !Array.isArray(entry.genres) || entry.genres.some((v) => typeof v !== "string") || normal(entry.genres[0]) !== "cricket"
    || entry.behaviorHints != null && !object(entry.behaviorHints)) return null;
  const target = entry.behaviorHints?.defaultVideoId ?? entry.id, time = instant(entry.released), identity = catalogPair(entry);
  if (!safeID(target) || time === null || !identity) return null;
  // Description is additional reviewed monitor evidence. Never parse a date or
  // participants from it; the native released/title/cast authority stays intact.
  const league = typeof entry.description === "string" && entry.description.length <= 2048
    ? entry.description.split("\n").filter((line) => /^\s*🏆 League: /.test(line)).map((line) => line.replace(/^\s*🏆 League: /, "")) : [];
  if (league.length !== 1) return null;
  const q = qualifiers(league[0]);
  if (!q?.format || (q.format === "Test" ? q.day !== 1 : q.day != null)) return null;
  const context = entry.context;
  // Context is not in the reviewed native CS metadata contract. Do not accept
  // a new source authority envelope silently, even when its values look useful.
  if (context != null) return null;
  return { pair: identity, time, target, type: entry.type ?? "tv", ...q };
}

export function selectCSCricketCatalogMatch(fixture, catalog) {
  const requested = officialIdentity(fixture);
  if (!requested) return result("unverifiable", "fixture-identity-unsupported");
  if (!object(catalog) || !Array.isArray(catalog.metas) || catalog.metas.length > 600) return result("unverifiable", "catalog-contract-unverified");
  const candidates = catalog.metas.map((entry) => ({ entry, identity: catalogIdentity(entry) }));
  const samePair = candidates.filter(({ identity: i }) => i?.pair === requested.pair);
  const matches = samePair.filter(({ identity: i }) => Math.abs(i.time - requested.time) <= TOLERANCE && i.format === requested.format
    && (requested.ordinal === null ? i.ordinal === null : i.ordinal === requested.ordinal) && i.day === requested.day);
  for (const row of matches) {
    const siblings = candidates.filter((v) => v.entry?.id === row.entry.id
      || (v.entry?.behaviorHints?.defaultVideoId ?? v.entry?.id) === row.identity.target);
    if (siblings.some((v) => JSON.stringify(v.identity) !== JSON.stringify(row.identity))) return result("conflicting", "duplicate-identity-conflict");
  }
  if (new Set(matches.map((v) => v.entry.id)).size > 1) return result("conflicting", "multiple-catalog-identities");
  if (matches.length) return result("matched", "dated-catalog-binding-only");
  if (samePair.length || candidates.some(({ entry }) => object(entry) && normal(entry.genres?.[0]) === "cricket"
    && catalogPair(entry) === requested.pair)) return result("unverifiable", "date-or-cricket-context-not-corroborated");
  // A partial/mixed catalog omitting this fixture is not provider absence.
  return result("missing", "not-in-sampled-catalog");
}
