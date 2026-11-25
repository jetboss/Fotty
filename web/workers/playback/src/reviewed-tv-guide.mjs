// Source-owned schedule facts only. Never fixture identity, LIVE authority,
// decoded-programme proof, a media location or a provider activation switch.
export const REVIEWED_TV_GUIDE_KEY = "shared-broadcast-tv-guide-v1";
export const REVIEWED_TV_GUIDE_LIFETIME = 4 * 60 * 60_000;
const sports = new Set(["football", "baseball", "basketball", "american-football", "rugby", "tennis", "hockey"]);
const stationID = /^sports-channel:espn(?:[2-7])?-latinamerica-south$/u;
const safe = (s) => typeof s === "string" && s.length > 0 && s.length <= 400 && s === s.trim()
  && !/[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069<>]/u.test(s) && !s.includes("://");

function validGuideRow(row, now) {
  if (!row || Object.keys(row).sort().join() !== "channelID,expiresAt,id,market,observedAt,sport,start,title"
    || typeof row.id !== "string" || !/^tv-guide:[a-f0-9]{64}$/u.test(row.id)
    || typeof row.channelID !== "string" || !stationID.test(row.channelID)
    || row.market !== "UY" || !sports.has(row.sport) || !safe(row.title)) return false;
  for (const key of ["start", "observedAt", "expiresAt"]) {
    if (typeof row[key] !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(row[key])
      || !Number.isFinite(Date.parse(row[key])) || new Date(row[key]).toISOString() !== row[key]) return false;
  }
  const start = Date.parse(row.start), observed = Date.parse(row.observedAt), expiry = Date.parse(row.expiresAt);
  return observed <= now + 300_000 && expiry > observed && expiry - observed <= REVIEWED_TV_GUIDE_LIFETIME
    && start >= observed - 8 * 86400_000 && start <= observed + 9 * 86400_000;
}

function stationSlot(row) {
  // A recognisable timestamp can conflict without gaining admission. Never
  // guess an absent timezone when comparing a malformed sibling's claim.
  if (typeof row?.channelID !== "string" || !stationID.test(row.channelID) || typeof row.start !== "string"
    || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u.test(row.start)) return null;
  const start = Date.parse(row.start);
  return Number.isFinite(start) ? row.channelID + "/" + start : null;
}

export function validateReviewedTVGuide(rows, at = new Date()) {
  const now = +new Date(at);
  if (!Number.isFinite(now) || !Array.isArray(rows) || rows.length > 300
    || new TextEncoder().encode(JSON.stringify(rows)).length > 256 * 1024) throw new Error("invalid-tv-guide");

  const ids = new Map(), slots = new Map();
  for (const row of rows) {
    if (typeof row?.id === "string") ids.set(row.id, (ids.get(row.id) ?? 0) + 1);
    const slot = stationSlot(row);
    if (slot !== null) slots.set(slot, (slots.get(slot) ?? 0) + 1);
  }
  const valid = rows.filter((row) => validGuideRow(row, now));
  // Preserve the last accepted sidecar on a wholly malformed collection.
  if (rows.length && !valid.length) throw new Error("invalid-tv-guide");
  return valid.filter((row) => ids.get(row.id) === 1 && slots.get(stationSlot(row)) === 1);
}
export function currentReviewedTVGuide(rows, at = new Date()) {
  return validateReviewedTVGuide(rows, at).filter((row) => Date.parse(row.expiresAt) > +new Date(at));
}
