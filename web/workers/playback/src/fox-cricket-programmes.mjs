// Original Foxtel FOX CRICKET HD schedule facts. No requests, media URLs,
// playback permissions or inferred LIVE fixture status belong in this module.
export const FOX_CRICKET_GUIDE = Object.freeze({
  channelID: "cricket-channel:fox-cricket", market: "AU", maxBytes: 512 * 1024,
  lifetime: 10 * 60_000, maxRows: 128, streamID: "reviewed-tv:fox-cricket-guide",
});
const invalid = () => { throw new Error("invalid-fox-guide"); };
const minute = 60_000, day = 24 * 60 * minute;
const voids = new Set("area base br col embed hr img input link meta param source track wbr".split(" "));
const text = (s) => s.replace(/\s+/gu, " ").trim();
function decode(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt|nbsp);/giu, (_, entity) => {
    if (entity[0] !== "#") return ({ amp: "&", quot: '"', apos: "'", lt: "<", gt: ">", nbsp: " " })[entity.toLowerCase()];
    const n = /^#x/iu.test(entity) ? parseInt(entity.slice(2), 16) : +entity.slice(1);
    return n > 0 && n <= 0x10ffff && !(n >= 0xd800 && n <= 0xdfff) ? String.fromCodePoint(n) : "\u0000";
  });
}
function attrs(source) {
  const result = new Map();
  let rest = source.trim();
  while (rest && rest !== "/") {
    const match = /^([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/u.exec(rest);
    if (!match) return invalid();
    const name = match[1].toLowerCase();
    if (result.has(name)) return invalid();
    result.set(name, decode(match[2] ?? match[3] ?? match[4] ?? ""));
    rest = rest.slice(match[0].length).trimStart();
  }
  return result;
}
const hasClass = (a, name) => (a.get("class") ?? "").split(/\s+/u).includes(name);
const hidden = (a) => a.has("hidden") || a.has("inert") || a.get("aria-hidden")?.toLowerCase() === "true"
  || /(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))\s*(?:!important\s*)?(?:;|$)/iu
    .test((a.get("style") ?? "").replace(/\/\*[\s\S]*?\*\//gu, ""));
const safe = (s) => s.length > 0 && s.length <= 256 && !/[\p{Cc}\p{Cf}<>]/u.test(s) && !s.includes("://");

export function foxCricketGuideURL(now) {
  if (!(now instanceof Date) || !Number.isFinite(+now)) return invalid();
  // The URL is a requested page, never the date authority for its events.
  const date = new Intl.DateTimeFormat("en-CA", { timeZone: "Australia/Sydney", year: "numeric", month: "2-digit", day: "2-digit" });
  const parts = Object.fromEntries(date.formatToParts(now).map((p) => [p.type, p.value]));
  if (!/^20\d{2}$/u.test(parts.year)) return invalid();
  return `https://www.foxtel.com.au/tv-guide.html/channel/FOX-CRICKET-HD/FS1/${parts.year}/${parts.month}/${parts.day}`;
}

function document(html) {
  if (typeof html !== "string" || new TextEncoder().encode(html).length > FOX_CRICKET_GUIDE.maxBytes) return invalid();
  const stack = [], rows = [], logos = [];
  let cursor = 0, tags = 0, lists = 0;
  while (cursor < html.length) {
    const open = html.indexOf("<", cursor), content = decode(html.slice(cursor, open < 0 ? html.length : open));
    const parent = stack.at(-1);
    if (parent?.description && !parent.hidden) parent.title += content;
    const description = stack.findLast((f) => f.description);
    if (description && !parent?.hidden) description.allText += content;
    if (open < 0) break;
    if (html.startsWith("<!--", open)) {
      const end = html.indexOf("-->", open + 4); if (end < 0) return invalid(); cursor = end + 3; continue;
    }
    let end = open + 1, quote;
    for (; end < html.length && end - open < 16_384; end++) {
      const c = html[end];
      if (quote) { if (c === quote) quote = undefined; }
      else if (c === '"' || c === "'") quote = c;
      else if (c === ">") break;
    }
    if (html[end] !== ">" || ++tags > 20_000) return invalid();
    cursor = end + 1;
    const tag = /^\s*(\/?)\s*([A-Za-z][A-Za-z0-9:-]*)([\s\S]*)$/u.exec(html.slice(open + 1, end));
    if (!tag) continue;
    const name = tag[2].toLowerCase();
    if (tag[1]) {
      const i = stack.findLastIndex((f) => f.name === name);
      if (i < 0) continue;
      const removed = stack.splice(i);
      // Authority containers and programme rows require their own closing tags.
      if (removed.some((f) => (f.list || f.row || f.description || f.logo) && f.name !== name)) return invalid();
      for (const frame of removed) {
        if (frame.description) { frame.owner.titles.push(text(frame.title)); frame.owner.contents.push(text(frame.allText)); }
        if (frame.row) rows.push(frame.row);
      }
      continue;
    }
    const a = attrs(tag[3]);
    const frame = { name, hidden: parent?.hidden || hidden(a) || ["template", "noscript"].includes(name) };
    if (description && name === "div" && !frame.hidden) description.allText += " ";
    if (["script", "style", "textarea"].includes(name)) {
      const closing = new RegExp(`<\\/\\s*${name}\\s*>`, "giu"); closing.lastIndex = cursor;
      if (!closing.exec(html)) return invalid(); cursor = closing.lastIndex; continue;
    }
    if (!frame.hidden && hasClass(a, "epg-channel-logo")) frame.logo = true;
    if (!frame.hidden && name === "img" && stack.some((f) => f.logo)) logos.push([a.get("alt"), a.get("src")]);
    if (!frame.hidden && a.get("id") === "epg-channel-events") {
      if (++lists !== 1 || name !== "div") return invalid(); frame.list = true;
    }
    if (!frame.hidden && hasClass(a, "epg-channel-event-row") && stack.some((f) => f.list)) {
      if (name !== "a" || stack.some((f) => f.row)) return invalid();
      const path = /^([A-Za-z0-9-]+)\/([1-9]\d{0,11})$/u.exec(a.get("href") ?? "");
      if (!path || !/^1\d{12}$/u.test(a.get("data-scheduled-date") ?? "")) return invalid();
      frame.row = { programmeID: path[2], start: Number(a.get("data-scheduled-date")), titles: [], contents: [] };
    }
    if (!frame.hidden && hasClass(a, "epg-event-description")) {
      const owner = stack.findLast((f) => f.row)?.row;
      if (owner) { if (description) return invalid(); frame.description = true; frame.owner = owner; frame.title = ""; frame.allText = ""; }
    }
    if (!voids.has(name)) { if (stack.length >= 256) return invalid(); stack.push(frame); }
  }
  if (lists !== 1 || logos.length !== 1 || logos[0][0] !== "501 FOX CRICKET HD"
    || logos[0][1] !== "https://www.foxtel.com.au/content/dam/foxtel/shared/channel/FS1/FS1_290x170.png"
    || stack.some((f) => f.list || f.row || f.description || f.logo) || rows.length > FOX_CRICKET_GUIDE.maxRows) return invalid();
  return rows;
}

const wbblClubs = new Map(Object.entries({ Strikers: "Adelaide Strikers Women", Heat: "Brisbane Heat Women",
  Hurricanes: "Hobart Hurricanes Women", Renegades: "Melbourne Renegades Women", Stars: "Melbourne Stars Women",
  Scorchers: "Perth Scorchers Women", Sixers: "Sydney Sixers Women", Thunder: "Sydney Thunder Women" }));
// Abu Dhabi T10 2026 franchises as Fox's guide shortens them; values are the
// exact ESPN names published by the T10 cricket cohort.
const t10Clubs = new Map(Object.entries({ Aces: "Arabian Aces", Bulls: "UAE Bulls", Champions: "Royal Desert Champions",
  Eagles: "Emirates Eagles", Lions: "Yas Lions", Tigers: "United Tigers" }));
const competitions = [
  { prefix: "Live: WBBL: ", clubs: wbblClubs, competitionID: "wbbl", format: "T20", squad: { gender: "women", ageGroup: "senior" } },
  { prefix: "Live: Abu Dhabi T10 League: ", clubs: t10Clubs, competitionID: "abu-dhabi-t10", format: "T10",
    squad: { gender: "men", ageGroup: "senior" } },
];
// Fox publishes "Live: <competition>: A v B" and repeats the pair as the
// episode line, sometimes after "S2024 , Ep14 ,". Long titles are cut short
// ("Live: Abu Dhabi T10 League: Champions v"), so the episode line must carry
// the full pair and the title must be an exact leading part of it.
function identity(title, content = title + " " + title.replace(/^Live: [^:]+: /u, "")) {
  for (const c of competitions) {
    if (!title.startsWith(c.prefix) || !content.startsWith(title + " ")) continue;
    const episode = content.slice(title.length + 1).replace(/^S20\d{2} , Ep[1-9]\d{0,2} , /u, "");
    const pair = /^([A-Za-z]+) v ([A-Za-z]+)$/u.exec(episode);
    if (!pair || pair[1] === pair[2] || !c.clubs.has(pair[1]) || !c.clubs.has(pair[2])) return null;
    const full = c.prefix + episode;
    if (!full.startsWith(title) || title.length < c.prefix.length + pair[1].length + 2) return null;
    return { competitionID: c.competitionID, format: c.format, squad: { ...c.squad },
      participants: [c.clubs.get(pair[1]), c.clubs.get(pair[2])] };
  }
  return null;
}
function knownMatch(m) {
  const c = competitions.find((x) => x.competitionID === m?.competitionID);
  return !!c && m.format === c.format && m.squad?.gender === c.squad.gender && m.squad?.ageGroup === c.squad.ageGroup
    && Array.isArray(m.participants) && m.participants.length === 2 && m.participants[0] !== m.participants[1]
    && m.participants.every((name) => [...c.clubs.values()].includes(name)) ? c : null;
}

export function parseFoxCricketProgrammes(html, { now = new Date() } = {}) {
  if (!(now instanceof Date) || !Number.isFinite(+now)) return invalid();
  const rows = document(html), ids = new Map(), starts = new Set();
  for (const row of rows) {
    if (row.titles.length !== 1 || !safe(row.titles[0]) || row.start < +now - day || row.start > +now + 8 * day) return invalid();
    const old = ids.get(row.programmeID);
    if (old && (old.start !== row.start || old.titles[0] !== row.titles[0] || old.contents[0] !== row.contents[0])) return invalid();
    if (!old && starts.has(row.start)) return invalid();
    ids.set(row.programmeID, row); starts.add(row.start);
  }
  const ordered = [...ids.values()].sort((a, b) => a.start - b.start);
  return { channelID: FOX_CRICKET_GUIDE.channelID, market: FOX_CRICKET_GUIDE.market,
    observedAt: now.toISOString(), expiresAt: new Date(+now + FOX_CRICKET_GUIDE.lifetime).toISOString(),
    programmes: ordered.map((row, i) => {
      const title = row.titles[0], next = ordered[i + 1];
      const match = typeof row.contents[0] === "string" ? identity(title, row.contents[0]) : null;
      const end = next && next.start - row.start <= 12 * 60 * minute ? new Date(next.start).toISOString() : undefined;
      return { programmeID: row.programmeID, title, start: new Date(row.start).toISOString(),
        ...(end ? { end, endBasis: "next-published-programme" } : {}),
        classification: match ? "live-match-listing" : /^Live: /u.test(title) ? "unresolved-live-programme" : "non-live-programme",
        ...(match ? { match } : {}) };
    }) };
}

// A programme reference is not a TV delivery. It can be joined to a separately
// verified AU Fox channel only by a consumer that understands this guide lane.
export function isFoxCricketProgramme(row, providerCode = row?.providerCode) {
  return providerCode === "reviewedtv" && row?.scope === "cricket" && row.sport === "cricket"
    && row.kind === "programme" && row.channelID === FOX_CRICKET_GUIDE.channelID
    && row.streamID === FOX_CRICKET_GUIDE.streamID
    && /^reviewed-tv:fox-programme:[a-f0-9]{64}$/u.test(row.providerEventID ?? "")
    && knownMatch(row) !== null && row.matchOrdinal === undefined && row.day === undefined
    && row.stationMarket === undefined;
}

export async function foxCricketBroadcasts(html, { now = new Date() } = {}) {
  const guide = parseFoxCricketProgrammes(html, { now });
  const current = guide.programmes.filter((p) => p.classification === "live-match-listing"
    && Date.parse(p.start) <= +now && Date.parse(p.end) > +now);
  if (current.length > 1) return invalid();
  return Promise.all(current.map(async (p) => {
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify([
      "Foxtel", guide.channelID, guide.market, p.programmeID, p.title, p.start, p.end,
    ])));
    const hash = [...new Uint8Array(digest)].map((n) => n.toString(16).padStart(2, "0")).join("");
    return { providerEventID: "reviewed-tv:fox-programme:" + hash, streamID: FOX_CRICKET_GUIDE.streamID,
      resourceType: "tv", scope: "cricket", kind: "programme", sport: "cricket", channelID: guide.channelID,
      title: p.title, ...p.match, start: p.start, end: p.end, verification: "dated",
      observedAt: guide.observedAt, expiresAt: new Date(Math.min(Date.parse(guide.expiresAt), Date.parse(p.end))).toISOString() };
  }));
}

// This audit join identifies coverage and collector gaps. It does not create a
// registry link or confer event-playback permission; existing use checks remain.
export function reviewFoxCricketCoverage(guide, fixtures, now = new Date()) {
  const observed = Date.parse(guide?.observedAt), expires = Date.parse(guide?.expiresAt);
  if (!guide || guide.channelID !== FOX_CRICKET_GUIDE.channelID || guide.market !== "AU"
    || !Array.isArray(guide.programmes) || guide.programmes.length > FOX_CRICKET_GUIDE.maxRows
    || !Array.isArray(fixtures) || fixtures.length > 3000 || !(now instanceof Date) || !Number.isFinite(+now)
    || !Number.isFinite(observed) || !Number.isFinite(expires) || expires <= observed
    || expires - observed > FOX_CRICKET_GUIDE.lifetime
    || observed > +now + 5 * minute || +now - observed > FOX_CRICKET_GUIDE.lifetime
    || expires <= +now) return invalid();
  if (guide.programmes.some((p) => !p || typeof p !== "object")
    || fixtures.some((f) => !f || typeof f !== "object")) return invalid();
  return guide.programmes.filter((p) => p.classification === "live-match-listing").map((p) => {
    const m = p.match, start = Date.parse(p.start);
    const known = knownMatch(m);
    // The structured pair must reproduce Fox's (possibly shortened) title.
    const short = known && m.participants.map((name) => [...known.clubs].find(([, full]) => full === name)?.[0]);
    const expectedTitle = known && known.prefix + short.join(" v ");
    if (!known || typeof p.title !== "string" || !expectedTitle.startsWith(p.title)
      || p.title.length < known.prefix.length + short[0].length + 2
      || typeof p.start !== "string" || !Number.isFinite(start)) return invalid();
    const pair = (names) => Array.isArray(names) && names.length === 2 && [...names].sort().join("\n") === [...m.participants].sort().join("\n");
    const candidates = fixtures.filter((f) => f.sport === "cricket" && f.competitionID === m.competitionID
      && pair(f.participants) && f.start?.slice(0, 10) === p.start.slice(0, 10));
    const f = candidates[0], lead = Date.parse(f?.start) - start;
    const verified = candidates.length === 1 && f.verified === true && /^cricket-fixture:ca:\d+$/u.test(f.fixtureID ?? "")
      && f.format === m.format && f.squad?.gender === m.squad.gender && f.squad?.ageGroup === "senior"
      && Number.isFinite(Date.parse(f.observedAt)) && Math.abs(+now - Date.parse(f.observedAt)) <= 10 * minute
      && ["scheduled", "live"].includes(f.status) && lead >= 0 && lead <= 60 * minute;
    return { programmeID: p.programmeID, title: p.title, start: p.start,
      result: verified ? "corroborated" : candidates.length > 1 ? "ambiguous-fixture" : candidates.length ? "fixture-conflict-or-stale" : "missing-official-fixture",
      ...(verified ? { fixtureID: f.fixtureID, officialStart: f.start, officialStatus: f.status,
        coverageLeadMinutes: lead / minute } : {}) };
  });
}
