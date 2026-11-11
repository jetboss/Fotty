#!/usr/bin/env node

// Validates the exact opaque team-badge tokens arriving in Fotty's live feed.
// It retains no image files and intentionally stays separate from deterministic CI.

const feedURL = process.env.FOTTY_LIVE_BADGE_FEED ?? "https://streamed.pk/api/matches/all";
const badgeBaseURL = "https://streamed.pk/api/images/badge/";
const timeoutMs = 10_000;
const concurrency = 8;

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

function eventArray(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.matches)) return payload.matches;
  throw new Error("Live badge feed did not return an event array.");
}

function imageSignature(bytes) {
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "png";
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";
  if (bytes.length >= 6 && String.fromCharCode(...bytes.slice(0, 6)).startsWith("GIF8")) return "gif";
  if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") return "webp";
  return null;
}

async function mapLimit(values, limit, transform) {
  const results = new Array(values.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await transform(values[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, worker));
  return results;
}

async function validateToken(token) {
  const url = `${badgeBaseURL}${encodeURIComponent(token)}.webp`;
  try {
    const response = await fetchWithTimeout(url, {
      headers: { accept: "image/*", range: "bytes=0-63" },
      redirect: "follow"
    });
    if (!response.ok) return { token, ok: false, reason: `HTTP ${response.status}` };
    const bytes = new Uint8Array(await response.arrayBuffer());
    const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
    const signature = imageSignature(bytes);
    if (!signature && !contentType.startsWith("image/")) {
      return { token, ok: false, reason: `not an image (${contentType || "unknown type"})` };
    }
    return { token, ok: true };
  } catch (error) {
    return { token, ok: false, reason: error instanceof Error ? error.message : String(error) };
  }
}

const feedResponse = await fetchWithTimeout(feedURL, { headers: { accept: "application/json" } });
if (!feedResponse.ok) throw new Error(`Live badge feed returned HTTP ${feedResponse.status}.`);
const events = eventArray(await feedResponse.json());
const tokenSports = new Map();
const emptyBadgeCounts = new Map();

for (const event of events) {
  const sport = event.category ?? "unknown";
  for (const side of ["home", "away"]) {
    const team = event.teams?.[side];
    if (!team?.name) continue;
    if (team.badge) {
      const sports = tokenSports.get(team.badge) ?? new Set();
      sports.add(sport);
      tokenSports.set(team.badge, sports);
    } else {
      emptyBadgeCounts.set(sport, (emptyBadgeCounts.get(sport) ?? 0) + 1);
    }
  }
}

const tokens = [...tokenSports.keys()];
if (!tokens.length) throw new Error("Live feed supplied teams but no provider badge tokens.");
const results = await mapLimit(tokens, concurrency, validateToken);
const failures = results.filter((result) => !result.ok);
const sportsWithTokens = [...new Set([...tokenSports.values()].flatMap((sports) => [...sports]))].sort();

console.log(`Live badge audit: ${events.length} events, ${tokens.length} unique provider tokens.`);
console.log(`Token-backed sports: ${sportsWithTokens.join(", ")}.`);
if (emptyBadgeCounts.size) {
  console.log(`Empty provider badges requiring Fotty fallback (known artwork or monogram): ${[...emptyBadgeCounts].map(([sport, count]) => `${sport}=${count}`).join(", ")}.`);
}

if (failures.length) {
  for (const failure of failures) {
    const sports = [...(tokenSports.get(failure.token) ?? [])].join(", ");
    console.error(`- ${sports}: ${failure.reason}`);
  }
  process.exitCode = 1;
} else {
  console.log(`All ${tokens.length} provider badge tokens returned valid image data.`);
}
