// Source-owned schedule facts only. Never fixture identity, LIVE authority,
// decoded-programme proof, a media location or a provider activation switch.
export const REVIEWED_TV_GUIDE_KEY = "shared-broadcast-tv-guide-v1";
export const REVIEWED_TV_GUIDE_LIFETIME = 4 * 60 * 60_000;
const sports = new Set(["football", "baseball", "basketball", "american-football", "rugby", "tennis", "hockey"]);
const safe = (s) => typeof s === "string" && s.length > 0 && s.length <= 400 && s === s.trim()
  && !/[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069<>]/u.test(s) && !s.includes("://");
export function validateReviewedTVGuide(rows, at = new Date()) {
  const now = +new Date(at), seen = new Set();
  if (!Number.isFinite(now) || !Array.isArray(rows) || rows.length > 300
    || new TextEncoder().encode(JSON.stringify(rows)).length > 256 * 1024) throw new Error("invalid-tv-guide");
  for (const row of rows) {
    if (!row || Object.keys(row).sort().join() !== "channelID,expiresAt,id,market,observedAt,sport,start,title"
      || !/^tv-guide:[a-f0-9]{64}$/u.test(row.id) || seen.has(row.id)
      || !/^sports-channel:espn(?:[2-7])?-latinamerica-south$/u.test(row.channelID)
      || row.market !== "UY" || !sports.has(row.sport) || !safe(row.title)) throw new Error("invalid-tv-guide");
    for (const key of ["start", "observedAt", "expiresAt"]) {
      if (typeof row[key] !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(row[key])
        || !Number.isFinite(Date.parse(row[key])) || new Date(row[key]).toISOString() !== row[key]) throw new Error("invalid-tv-guide");
    }
    const start = Date.parse(row.start), observed = Date.parse(row.observedAt), expiry = Date.parse(row.expiresAt);
    if (![start, observed, expiry].every(Number.isFinite) || observed > now + 300_000
      || expiry <= observed || expiry - observed > REVIEWED_TV_GUIDE_LIFETIME
      || start < observed - 8 * 86400_000 || start > observed + 9 * 86400_000) throw new Error("invalid-tv-guide");
    seen.add(row.id);
  }
  // Ambiguous simultaneous station claims are omitted as a group. They never
  // invalidate unrelated match associations or choose a winner by row order.
  return rows.filter((row) => !rows.some((other) => other.id !== row.id
    && other.channelID === row.channelID && other.start === row.start));
}
export function currentReviewedTVGuide(rows, at = new Date()) {
  return validateReviewedTVGuide(rows, at).filter((row) => Date.parse(row.expiresAt) > +new Date(at));
}
