// Fixed ESPN South weekly metadata, never an IPTV playlist or playback URL.
// ESPN labels each country's listings in local time. Only the reviewed Uruguay
// section is interpreted, using IANA rules rather than a feed CSV's timezone.
export const REVIEWED_TV_ESPN_SOURCE = Object.freeze({
  feedURL: "https://latinamerica.espnpressroom.com/feed/?s=programaci%C3%B3n+destacada",
  origin: "https://latinamerica.espnpressroom.com", market: "UY", timeZone: "America/Montevideo",
  maxBytes: 1024 * 1024, lifetime: 10 * 60_000,
});
const source = REVIEWED_TV_ESPN_SOURCE, day = 86_400_000;
const invalid = () => { throw new Error("invalid-collection"); };
const normal = (v) => v.normalize("NFKD").replace(/\p{M}/gu, "").replace(/\s+/gu, " ").trim();
const months = "ENERO FEBRERO MARZO ABRIL MAYO JUNIO JULIO AGOSTO SEPTIEMBRE OCTUBRE NOVIEMBRE DICIEMBRE".split(" ");
const weekdays = "DOMINGO LUNES MARTES MIERCOLES JUEVES VIERNES SABADO".split(" ");
const englishMonths = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ");
const englishWeekdays = "Sun Mon Tue Wed Thu Fri Sat".split(" ");
const competitions = Object.freeze({ "Premier League": "premier-league", "UEFA Champions League": "champions-league",
  "LaLiga": "la-liga", "Serie A": "serie-a", "Bundesliga": "bundesliga", "Ligue 1": "ligue-1" });
// Literal ESPN Uruguay wording verified against its dated UCL assignment and
// accepted official PAE AEK identity. This is not a fuzzy/global club alias.
const uclSourceAliases = Object.freeze({ "AEK Athenas": "AEK Athens" });
const safe = (v) => typeof v === "string" && v.length > 0 && v.length <= 256
  && !/[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069<>]/u.test(v) && !v.includes("://");
function decode(v) {
  return v.replace(/&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt|nbsp);/giu, (raw, entity) => {
    if (!entity.startsWith("#")) return ({ amp: "&", quot: '"', apos: "'", lt: "<", gt: ">", nbsp: " " })[entity.toLowerCase()] ?? raw;
    const p = /^#x/iu.test(entity) ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
    return p > 0 && p <= 0x10ffff && !(p >= 0xd800 && p <= 0xdfff) ? String.fromCodePoint(p) : "\u0000";
  });
}

// Small bounded tokenizer shared by the XML envelope and literal article HTML.
// CDATA is text in RSS; scripts/inert/hidden HTML cannot supply programme facts.
function document(markup, xml = false) {
  if (typeof markup !== "string" || new TextEncoder().encode(markup).length > source.maxBytes || /<!DOCTYPE/iu.test(markup)) return invalid();
  const root = { tag: "root", children: [], attrs: new Map() }, stack = [root];
  const voids = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
  let index = 0, count = 0;
  const append = (v) => { if (!stack.at(-1).hidden) stack.at(-1).children.push(v); };
  while (index < markup.length) {
    const start = markup.indexOf("<", index);
    append(decode(markup.slice(index, start < 0 ? markup.length : start)));
    if (start < 0) break;
    if (markup.startsWith("<![CDATA[", start)) {
      const end = markup.indexOf("]]>", start + 9); if (!xml || end < 0) return invalid();
      append(markup.slice(start + 9, end)); index = end + 3; continue;
    }
    if (markup.startsWith("<!--", start)) {
      const end = markup.indexOf("-->", start + 4); if (end < 0) return invalid(); index = end + 3; continue;
    }
    let end = start + 1, quote = null;
    for (; end < markup.length && end - start < 16_384; end++) {
      const c = markup[end];
      if (quote) { if (c === quote) quote = null; }
      else if (c === '"' || c === "'") quote = c;
      else if (c === ">") break;
    }
    if (markup[end] !== ">" || ++count > 20_000) return invalid();
    index = end + 1;
    const token = markup.slice(start + 1, end);
    if (/^\?xml\b/u.test(token) && xml) continue;
    const match = /^\s*(\/?)\s*([a-zA-Z][a-zA-Z0-9:-]*)([\s\S]*)$/u.exec(token); if (!match) return invalid();
    const tag = match[2].toLowerCase();
    if (match[1]) {
      const pos = stack.findLastIndex((n) => n.tag === tag); if (pos < 1) return invalid();
      if (xml && pos !== stack.length - 1) return invalid();
      stack.splice(pos); continue;
    }
    const attrs = new Map(); let tail = match[3];
    while (tail.trim() && tail.trim() !== "/") {
      const attr = /^\s*([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/u.exec(tail);
      if (!attr || attrs.has(attr[1].toLowerCase())) return invalid();
      attrs.set(attr[1].toLowerCase(), decode(attr[2] ?? attr[3] ?? attr[4] ?? "")); tail = tail.slice(attr[0].length);
    }
    if (!xml && ["script", "style", "textarea"].includes(tag)) {
      const close = new RegExp(`<\\/\\s*${tag}\\s*>`, "giu"); close.lastIndex = index;
      if (!close.exec(markup)) return invalid(); index = close.lastIndex; continue;
    }
    const style = (attrs.get("style") ?? "").replace(/\/\*[\s\S]*?\*\//gu, "");
    const hidden = stack.at(-1).hidden || !xml && (["template", "noscript"].includes(tag) || attrs.has("hidden") || attrs.has("inert")
      || attrs.get("aria-hidden")?.toLowerCase() === "true" || /(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))\s*(?:!important\s*)?(?:;|$)/iu.test(style));
    const node = { tag, attrs, children: [], hidden };
    if (!hidden) append(node);
    if (!(xml ? /\/\s*$/u.test(tail) : voids.has(tag) || /\/\s*$/u.test(tail))) {
      if (stack.length >= 80) return invalid(); stack.push(node);
    }
  }
  if (xml && stack.length !== 1) return invalid();
  return root;
}
const children = (n, tag) => n.children.filter((c) => typeof c !== "string" && c.tag === tag);
const plain = (n) => typeof n === "string" ? n : n.tag === "br" ? "\n" : n.children.map(plain).join("");
function only(node, tag) { const all = children(node, tag); return all.length === 1 ? plain(all[0]).trim() : invalid(); }
function descendants(node, tag, result = []) {
  if (node.tag === tag) result.push(node);
  for (const child of node.children) if (typeof child !== "string") descendants(child, tag, result);
  return result;
}
function date(year, month, number) {
  const value = new Date(Date.UTC(year, month - 1, number));
  return value.getUTCFullYear() === year && value.getUTCMonth() === month - 1 && value.getUTCDate() === number ? value : null;
}
function publication(value) {
  const m = /^(Sun|Mon|Tue|Wed|Thu|Fri|Sat), (\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (20\d{2}) ([01]\d|2[0-3]):([0-5]\d):([0-5]\d) \+0000$/u.exec(value);
  if (!m) return invalid();
  const d = date(+m[4], englishMonths.indexOf(m[3]) + 1, +m[2]);
  if (!d || englishWeekdays[d.getUTCDay()] !== m[1]) return invalid();
  d.setUTCHours(+m[5], +m[6], +m[7]); return d;
}
function range(title, published) {
  const m = /^PROGRAMACION DESTACADA DEL (\d{1,2})(?: DE ([A-Z]+))? AL (\d{1,2}) DE ([A-Z]+)(?: DE (20\d{2}))?$/u.exec(normal(title).toUpperCase());
  if (!m) return null;
  const startMonth = months.indexOf(m[2] ?? m[4]) + 1, endMonth = months.indexOf(m[4]) + 1;
  if (!startMonth || !endMonth) return null;
  const candidates = [];
  for (const year of [published.getUTCFullYear() - 1, published.getUTCFullYear(), published.getUTCFullYear() + 1]) {
    const a = date(year, startMonth, +m[1]), b = date(year + (endMonth < startMonth ? 1 : 0), endMonth, +m[3]);
    if (!a || !b || m[5] && +m[5] !== b.getUTCFullYear() || +b - +a < 2 * day || +b - +a > 8 * day
      || +a - +published < -2 * day || +a - +published > 7 * day) continue;
    candidates.push([a, b]);
  }
  return candidates.length === 1 ? candidates[0] : null;
}
function localDay(now) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: source.timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(now);
  const part = (type) => parts.find((p) => p.type === type).value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}
function localUTC(dateString, hour, minute) {
  const target = Date.parse(dateString + `T${hour}:${minute}:00Z`), fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: source.timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  const matches = [];
  // Derive possible offsets from IANA on the actual date, rejecting gaps/folds.
  const offsets = new Set();
  for (const delta of [-day, 0, day]) {
    const at = new Date(target + delta), p = fmt.formatToParts(at), get = (k) => p.find((x) => x.type === k).value;
    offsets.add(Date.parse(`${get("year")}-${get("month")}-${get("day")}T${get("hour")}:${get("minute")}:00Z`) - +at);
  }
  for (const offset of offsets) {
    const at = new Date(target - offset), p = fmt.formatToParts(at), get = (k) => p.find((x) => x.type === k).value;
    if (`${get("year")}-${get("month")}-${get("day")}` === dateString && get("hour") === hour && get("minute") === minute) matches.push(at.toISOString());
  }
  return matches.length === 1 ? matches[0] : invalid();
}
async function hash(value) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(value))))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function parseReviewedTVESPNFeed(xml, { now = new Date() } = {}) {
  if (!(now instanceof Date) || !Number.isFinite(+now)) return invalid();
  const rss = document(xml, true), top = children(rss, "rss");
  if (top.length !== 1 || children(top[0], "channel").length !== 1) return invalid();
  const channel = children(top[0], "channel")[0];
  if (only(channel, "link") !== source.origin + "/") return invalid();
  const items = children(channel, "item"); if (!items.length || items.length > 20) return invalid();
  const current = [];
  for (const item of items) {
    const title = only(item, "title"); if (!/^PROGRAMACI[ÓO]N DESTACADA DEL /u.test(title)) continue;
    const published = publication(only(item, "pubdate")); if (+published > +now + 300_000 || +now - +published > 11 * day) continue;
    const url = new URL(only(item, "link"));
    if (url.origin !== source.origin || url.username || url.password || url.search || url.hash || !/^\/press-releases\/20\d{2}\/\d{2}\/programacion-destacada-[a-z0-9-]+\/$/u.test(url.pathname)
      || url.pathname.split("/")[2] !== String(published.getUTCFullYear()) || +url.pathname.split("/")[3] !== published.getUTCMonth() + 1) return invalid();
    const window = range(title, published); if (!window) return invalid();
    if (localDay(now) < window[0].toISOString().slice(0, 10) || localDay(now) > window[1].toISOString().slice(0, 10)) continue;
    current.push({ title, published, path: url.pathname, window, body: only(item, "content:encoded") });
  }
  if (!current.length) return invalid();
  current.sort((a, b) => +b.published - +a.published);
  const article = current[0];
  if (current.some((v) => +v.published === +article.published && (v.path !== article.path || v.body !== article.body))) throw new Error("catalog-conflict");
  const body = document(article.body), headings = descendants(body, "h2"), chosen = headings.filter((h) => h.attrs.get("id") === "URUGUAY" && normal(plain(h)) === "URUGUAY");
  if (chosen.length !== 1 || headings.filter((h) => normal(plain(h)) === "URUGUAY" || h.attrs.get("id") === "URUGUAY").length !== 1) return invalid();
  // The maintained article places country h2 and programme paragraphs in one
  // literal container. Never widen to text from Argentina or another section.
  const owner = (node) => node.children.includes(chosen[0]) ? node : node.children.filter((c) => typeof c !== "string").map(owner).find(Boolean);
  const container = owner(body); if (!container) return invalid();
  const start = container.children.indexOf(chosen[0]), section = [];
  for (const node of container.children.slice(start + 1)) {
    if (typeof node !== "string" && node.tag === "h2") break;
    if (typeof node !== "string" && node.tag === "p") section.push(plain(node).split("\n").map((v) => v.replace(/\s+/gu, " ").trim()).filter(Boolean));
  }
  if (!section.flat().some((line) => normal(line) === normal(article.title))) return invalid();
  const calendar = new Map();
  for (let at = +article.window[0]; at <= +article.window[1]; at += day) {
    const d = new Date(at); calendar.set(`${weekdays[d.getUTCDay()]} ${d.getUTCDate()}`, d.toISOString().slice(0, 10));
  }
  const rows = [], seenDays = new Set();
  for (const paragraph of section) {
    // The maintained source uses one date-headed paragraph per day. A later
    // undated block must not inherit yesterday's date if its markup changes.
    let dateString = null;
    for (const line of paragraph) {
      const header = /^([A-Z]+) (\d{1,2})$/u.exec(normal(line).toUpperCase());
      if (header && weekdays.includes(header[1])) {
        dateString = calendar.get(`${header[1]} ${+header[2]}`); if (!dateString || seenDays.has(dateString)) return invalid();
        seenDays.add(dateString); continue;
      }
      // Only exact linear assignments qualify. "ESPN en Disney+" is not a TV
      // channel even when another country's row assigns the same game to ESPN.
      const m = /^([01]\d|2[0-3]):([0-5]\d) (ESPN(?:[2-7])?) y Disney\+ Plan Premium \/ ([^–]+?) #([1-9]\d?) [–−-] (.+) vs\. (.+)$/u.exec(line);
      if (!m || !Object.hasOwn(competitions, m[4])) continue;
      if (!dateString || !safe(m[6]) || !safe(m[7]) || m[6] === m[7]) return invalid();
      const channelStem = m[3].toLowerCase() + "-latinamerica-south", coverageStart = localUTC(dateString, m[1], m[2]);
      const identity = [article.path, "URUGUAY", dateString, m[1] + ":" + m[2], channelStem, competitions[m[4]], m[6], m[7]];
      const participants = [m[6], m[7]].map((name) => competitions[m[4]] === "champions-league"
        && Object.hasOwn(uclSourceAliases, name) ? uclSourceAliases[name] : name);
      rows.push({ providerEventID: "reviewed-tv:assignment:" + await hash(identity), streamID: "reviewed-tv:" + channelStem,
        resourceType: "tv", scope: "football", kind: "event", sport: "football", title: `${m[6]} vs ${m[7]}`,
        participants, start: coverageStart, competitionID: competitions[m[4]], squad: { gender: "men", ageGroup: "senior" },
        channelID: "sports-channel:" + channelStem, stationMarket: "UY", verification: "dated", issues: [],
        observedAt: now.toISOString(), expiresAt: new Date(+now + source.lifetime).toISOString() });
    }
  }
  const unique = new Map(rows.map((r) => [r.providerEventID, r]));
  if (unique.size > 300) throw new Error("capacity-exceeded");
  // One channel cannot promise two distinct events at the same coverage start.
  // Preserve both conflicts and every unrelated valid sibling for diagnosis.
  const broadcasts = [...unique.values()].map((r, _, all) => all.some((b) => b !== r && b.channelID === r.channelID && b.start === r.start)
    ? { ...r, verification: "conflicting", issues: ["catalog-conflict"] } : r);
  return { broadcasts, scopes: [{ scope: "football", status: "partial", complete: false }], complete: false };
}
