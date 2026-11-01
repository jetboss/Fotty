// Fixed, reviewed main-Willow programme metadata. No I/O or media locations.
// A guide interval is programme evidence, not a playable stream descriptor.
export const REVIEWED_TV_PROGRAMME_SOURCE = Object.freeze({
  providerCode: "reviewedtv", station: "willow-cricket/15964",
  channelID: "cricket-channel:willow", streamID: "reviewed-tv:willow-main",
  maxBytes: 1024 * 1024, lifetime: 10 * 60_000, maxDurationMinutes: 720,
});
const SOURCE = REVIEWED_TV_PROGRAMME_SOURCE;
const forbidden = /[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069<>]/u;
const safeText = (value, max) => typeof value === "string" && value.length > 0 && value.length <= max
  && value === value.trim() && !forbidden.test(value) && !value.includes("://");
const invalid = () => { throw new Error("invalid-collection"); };

export function reviewedTVProgrammeURL(date) {
  if (!(date instanceof Date) || !Number.isFinite(+date)) return invalid();
  const day = date.toISOString().slice(0, 10);
  if (!/^20\d{2}-\d{2}-\d{2}$/u.test(day)) return invalid();
  return `https://www.tvpassport.com/tv-listings/stations/${SOURCE.station}/${day}`;
}

function unescapeHTML(value) {
  return value.replace(/&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt|nbsp);/giu, (raw, entity) => {
    if (entity[0] !== "#") return ({ amp: "&", quot: '"', apos: "'", lt: "<", gt: ">", nbsp: " " })[entity.toLowerCase()] ?? raw;
    const point = /^#x/iu.test(entity) ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
    return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff) ? String.fromCodePoint(point) : "\u0000";
  });
}

function attributes(source) {
  const result = new Map();
  let index = 0;
  while (index < source.length) {
    while (/\s/u.test(source[index] ?? "")) index++;
    if (index === source.length || source.slice(index).trim() === "/") break;
    const key = /^[^\s=/>]+/u.exec(source.slice(index));
    if (!key) return invalid();
    index += key[0].length;
    const name = key[0].toLowerCase();
    if (result.has(name)) return invalid();
    while (/\s/u.test(source[index] ?? "")) index++;
    let value = "";
    if (source[index] === "=") {
      index++;
      while (/\s/u.test(source[index] ?? "")) index++;
      const quote = source[index];
      if (quote === '"' || quote === "'") {
        const end = source.indexOf(quote, index + 1);
        if (end < 0) return invalid();
        value = source.slice(index + 1, end); index = end + 1;
      } else {
        const unquoted = /^[^\s>]+/u.exec(source.slice(index));
        if (!unquoted) return invalid();
        value = unquoted[0]; index += value.length;
      }
    }
    result.set(name, unescapeHTML(value));
  }
  return result;
}

// A bounded quote-aware tokenizer avoids evaluating publisher scripts, accepts
// ordinary nested heading markup and rejects duplicate authority attributes.
function guideDocument(html) {
  if (typeof html !== "string" || new TextEncoder().encode(html).length > SOURCE.maxBytes) return invalid();
  let cursor = 0, count = 0, activeHeading = null, zoneSelectors = 0;
  const headings = [], zones = [], rows = [], stack = [];
  const voidTags = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
  const suppressed = () => stack.at(-1)?.hidden === true;
  const hiddenAttributes = (attrs) => {
    if (attrs.has("hidden") || attrs.has("inert") || attrs.get("aria-hidden")?.trim().toLowerCase() === "true") return true;
    const style = (attrs.get("style") ?? "").replace(/\/\*[\s\S]*?\*\//gu, "");
    return /(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))\s*(?:!important\s*)?(?:;|$)/iu.test(style);
  };
  while (cursor < html.length) {
    const opening = html.indexOf("<", cursor);
    const text = unescapeHTML(html.slice(cursor, opening < 0 ? html.length : opening));
    if (activeHeading !== null && !suppressed()) activeHeading.text += text;
    if (opening < 0) break;
    if (html.startsWith("<!--", opening)) {
      const end = html.indexOf("-->", opening + 4);
      if (end < 0) return invalid();
      cursor = end + 3; continue;
    }
    let end = opening + 1, quote = null;
    for (; end < html.length && end - opening <= 16_384; end++) {
      const char = html[end];
      if (quote) { if (char === quote) quote = null; }
      else if (char === '"' || char === "'") quote = char;
      else if (char === ">") break;
    }
    if (html[end] !== ">" || ++count > 20_000) return invalid();
    cursor = end + 1;
    const tag = /^\s*(\/?)\s*([A-Za-z][A-Za-z0-9:-]*)([\s\S]*)$/u.exec(html.slice(opening + 1, end));
    if (!tag) continue;
    const closing = tag[1] === "/", name = tag[2].toLowerCase();
    if (!closing && ["script", "style", "textarea"].includes(name)) {
      const close = new RegExp(`<\\/\\s*${name}\\s*>`, "giu"); close.lastIndex = cursor;
      const match = close.exec(html);
      if (!match) return invalid();
      cursor = close.lastIndex; continue;
    }
    if (closing) {
      const index = stack.findLastIndex((frame) => frame.name === name);
      if (index < 0) continue;
      for (const frame of stack.splice(index)) {
        if (frame.heading) {
          if (name !== "h1") return invalid();
          headings.push(frame.text.replace(/\s+/gu, " ").trim()); activeHeading = null;
        }
        if (frame.select === "zone" && name !== "select") return invalid();
      }
      continue;
    }
    const attrs = attributes(tag[3]);
    const frame = { name, hidden: suppressed() || ["template", "noscript"].includes(name) || hiddenAttributes(attrs) };
    if (name === "h1" && !frame.hidden) {
      if (activeHeading !== null) return invalid();
      frame.heading = true; frame.text = ""; activeHeading = frame;
    }
    if (name === "select" && !frame.hidden) {
      if (stack.some((ancestor) => ancestor.select)) return invalid();
      frame.select = attrs.get("id") === "timezone_selector" ? "zone" : "other";
      if (frame.select === "zone" && ++zoneSelectors > 1) return invalid();
    }
    const parentSelect = stack.findLast((ancestor) => ancestor.name === "select");
    if (!frame.hidden && name === "option" && parentSelect?.select === "zone" && attrs.has("selected")) zones.push(attrs.get("value"));
    if (!frame.hidden && attrs.has("data-showname")) rows.push(Object.fromEntries(attrs));
    // A slash does not self-close ordinary non-void HTML elements. In
    // particular <div hidden/> must not expose the rows that follow it.
    if (!voidTags.has(name)) {
      if (stack.length >= 256) return invalid();
      stack.push(frame);
    }
  }
  if (activeHeading !== null || stack.some((frame) => frame.select) || headings.filter((v) => v === "TV Schedule for Willow Cricket").length !== 1
    || headings.some((v) => /willow/iu.test(v) && v !== "TV Schedule for Willow Cricket") || zones.length !== 1 || rows.length > 256) return invalid();
  return { zone: zones[0], rows };
}

function zoneFormatter(zone) {
  if (typeof zone !== "string" || zone.length > 96 || !/^(?:UTC|[A-Za-z_]+(?:\/[A-Za-z0-9_+\-]+)+)$/u.test(zone)) return invalid();
  try {
    return new Intl.DateTimeFormat("en-GB", { timeZone: zone, calendar: "gregory", numberingSystem: "latn",
      year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
  } catch { return invalid(); }
}
function localParts(formatter, stamp) {
  const values = Object.fromEntries(formatter.formatToParts(stamp).map((p) => [p.type, p.value]));
  return ["year", "month", "day", "hour", "minute", "second"].map((key) => Number(values[key]));
}
const nominalUTC = (p) => Date.UTC(p[0], p[1] - 1, p[2], p[3], p[4], p[5]);
function wallTime(value, formatter) {
  const match = typeof value === "string" && /^(20\d{2})-(\d{2})-(\d{2}) ([01]\d|2[0-3]):([0-5]\d):([0-5]\d)$/u.exec(value);
  if (!match) return null;
  const parts = match.slice(1).map(Number), nominal = nominalUTC(parts), date = new Date(nominal);
  if (date.getUTCFullYear() !== parts[0] || date.getUTCMonth() + 1 !== parts[1] || date.getUTCDate() !== parts[2]) return null;
  const offsets = new Set([-36, -24, -12, 0, 12, 24, 36].map((hours) => {
    const at = nominal + hours * 3600_000;
    return nominalUTC(localParts(formatter, at)) - at;
  }));
  const candidates = [...offsets].map((offset) => nominal - offset)
    .filter((at) => localParts(formatter, at).every((part, i) => part === parts[i]));
  // Neither a nonexistent spring clock nor either interpretation of a folded
  // fall clock has unique published UTC authority.
  return candidates.length === 1 ? candidates[0] : null;
}
function interval(row, formatter) {
  const start = wallTime(row["data-st"], formatter), duration = row["data-duration"];
  if (start === null || !/^[1-9]\d{0,2}$/u.test(duration ?? "") || +duration > SOURCE.maxDurationMinutes) return null;
  const end = start + +duration * 60_000;
  if (row["data-listdatetime"] && row["data-listdatetime"] !== row["data-st"]
    || row["data-et"] && wallTime(row["data-et"], formatter) !== end) return null;
  return { start, end };
}
// These are the publisher's match programmes, not the similarly LIVE-marked
// Preview/Review shows. A format is never inferred from the station or teams.
const cricketShows = new Map([
  ["Test Cricket", "Test"], ["T20 Cricket", "T20"], ["One-Day International Cricket", "ODI"],
]);
function cricketIdentity(row) {
  const disallowed = /\b(?:review|highlights?|preview|replay|repeat|rerun|recorded|delayed)\b/iu;
  const format = cricketShows.get(row["data-showname"]);
  if (!format || row["data-live"] !== "1"
    || row["data-repeat"] && !["0", "false"].includes(row["data-repeat"].toLowerCase())
    || [row["data-showname"], row["data-episodetitle"], row["data-description"]].some((v) => typeof v === "string" && disallowed.test(v))) return null;
  const description = row["data-description"];
  const pattern = format === "Test" ? /^([1-9]\d?)(st|nd|rd|th) Test, Day ([1-6])\.$/u
    : format === "T20" ? /^([1-9]\d?)(st|nd|rd|th) T20I?\.$/u
      : /^([1-9]\d?)(st|nd|rd|th) ODI\.$/u;
  const label = typeof description === "string" && pattern.exec(description);
  if (!label) return null;
  const ordinal = +label[1], suffix = ordinal % 100 >= 11 && ordinal % 100 <= 13 ? "th" : ({ 1: "st", 2: "nd", 3: "rd" })[ordinal % 10] ?? "th";
  if (label[2] !== suffix || !safeText(row["data-episodetitle"], 512)) return null;
  const participants = row["data-episodetitle"].split(/\s+(?:vs\.?|v\.?|versus)\s+/iu);
  if (participants.length !== 2 || participants.some((p) => !safeText(p, 256))
    || participants[0].normalize("NFKC").toLowerCase() === participants[1].normalize("NFKC").toLowerCase()
    || participants.some((p) => /^(?:tbc|tbd|unknown|home|away|teams to be confirmed)$/iu.test(p))) return null;
  return { participants, format, matchOrdinal: ordinal, ...(format === "Test" ? { day: +label[3] } : {}) };
}
async function hash(value) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(value))))]
    .map((v) => v.toString(16).padStart(2, "0")).join("");
}

export async function parseReviewedTVProgrammes(html, { now = new Date() } = {}) {
  if (!(now instanceof Date) || !Number.isFinite(+now)) return invalid();
  const { zone, rows } = guideDocument(html), formatter = zoneFormatter(zone);
  const observedAt = now.toISOString(), current = [], seen = new Map();
  for (const row of rows) {
    if (row["data-callsign"] !== "Willow") return invalid();
    const rawID = row["data-listingid"], signature = JSON.stringify([row["data-st"], row["data-et"], row["data-duration"],
      row["data-showname"], row["data-episodetitle"], row["data-description"], row["data-live"], row["data-repeat"]]);
    if (rawID) { if (seen.has(rawID) && seen.get(rawID) !== signature) return invalid(); seen.set(rawID, signature); }
    const times = interval(row, formatter);
    if (!times) { if (cricketShows.has(row["data-showname"])) return invalid(); continue; }
    if (times.start <= +now && +now < times.end) current.push({ row, ...times, signature });
  }
  // Main Willow has one linear programme. Contradictory overlapping rows must
  // not let a convenient match row override a different current programme.
  const unique = new Map(current.map((r) => [r.signature, r]));
  if (unique.size > 1) return invalid();
  const broadcasts = [];
  for (const { row, start, end } of unique.values()) {
    const identity = cricketIdentity(row);
    if (!identity) continue;
    const startISO = new Date(start).toISOString(), endISO = new Date(end).toISOString();
    const providerEventID = "reviewed-tv:programme:" + await hash([SOURCE.station, startISO, endISO, identity]);
    broadcasts.push({ providerCode: SOURCE.providerCode, providerEventID, streamID: SOURCE.streamID, resourceType: "tv",
      scope: "cricket", kind: "programme", sport: "cricket", title: row["data-episodetitle"],
      ...identity, start: startISO, end: endISO, channelID: SOURCE.channelID, verification: "dated", issues: [],
      observedAt, expiresAt: new Date(Math.min(+now + SOURCE.lifetime, end)).toISOString() });
  }
  return { providerCode: SOURCE.providerCode, observedAt, guideTimeZone: zone, complete: true,
    scopes: [{ scope: "cricket", status: broadcasts.length ? "available" : "empty", complete: true }], broadcasts };
}
