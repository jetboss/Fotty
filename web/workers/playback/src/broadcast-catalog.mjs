import { boundedJSON } from "./coach-safety.mjs";

// A versioned metadata boundary, never a media/HTML proxy. These endpoints are
// the existing reviewed family; mirrors do not count as independent supply.
export const BROADCAST_CATALOG_SCHEMA = 1;
export const BROADCAST_CATALOG_PROVIDERS = Object.freeze([
  { id: "nexus-primary", family: "nexus", origin: "https://www.streamex.net", prefix: "/api/live/matches" },
  { id: "nexus-mirror", family: "nexus", origin: "https://streamex.sh", prefix: "/api/live/matches" },
  { id: "nexus-backup", family: "nexus", origin: "https://streamed.pk", prefix: "/api/matches" },
]);
const LIMIT = 4 * 1024 * 1024;
const MAX_ROWS = 4000;
const text = (v, max) => typeof v === "string" && v.trim().length > 0
  && v.length <= max && !/[\u0000-\u001f\u007f]/u.test(v) ? v : null;

function artwork(value) {
  if (!text(value, 2048)) return null;
  // Native has existing reviewed handling for relative API image paths and
  // opaque provider tokens. Preserve those representations, never turn an
  // arbitrary relative string into a new origin or fetch it at the edge.
  if (value.startsWith("/api/") && !value.includes("..") && !value.includes("\\")) return value;
  if (!value.startsWith("/") && /^[a-zA-Z0-9 _+=/%.-]+$/u.test(value) && !value.includes("..")) return value;
  try {
    const u = new URL(value);
    if (u.protocol !== "https:" || u.username || u.password || (u.port && u.port !== "443")
      || !u.hostname.includes(".") || /^[\d.:\[\]]+$/u.test(u.hostname)
      || /(?:^|\.)(?:localhost|local|internal|invalid)$/iu.test(u.hostname)) return null;
    return u.href;
  } catch { return null; }
}

export function normalizeBroadcastRows(payload) {
  const rows = Array.isArray(payload) ? payload : payload?.matches;
  if (!Array.isArray(rows) || rows.length > MAX_ROWS) throw new Error("invalid-catalog");
  return rows.map((row) => {
    if (!row || typeof row !== "object" || Array.isArray(row)) throw new Error("invalid-row");
    const id = text(row.id, 256), title = text(row.title, 512);
    const category = row.category == null ? null : text(row.category, 64);
    if (!id || !title || (row.category != null && !category)) throw new Error("invalid-identity");
    const date = row.date == null ? null : row.date;
    const seconds = date > 10_000_000_000 ? date / 1000 : date;
    if (date != null && (!Number.isSafeInteger(date) || seconds < 946684800 || seconds > 4102444800)) {
      throw new Error("invalid-date");
    }
    if (row.sources != null && (!Array.isArray(row.sources) || row.sources.length > 64)) throw new Error("invalid-sources");
    const sources = (row.sources ?? []).map((s) => {
      if (!s || typeof s !== "object" || !text(s.source, 64) || !/^[a-zA-Z0-9_-]+$/u.test(s.source)
        || !text(s.id, 512)) throw new Error("invalid-source");
      return { source: s.source, id: s.id };
    });
    const team = (value) => {
      if (value == null) return null;
      if (typeof value !== "object" || Array.isArray(value) || !text(value.name, 256)) throw new Error("invalid-team");
      return { name: value.name, badge: artwork(value.badge) };
    };
    if (row.teams != null && (typeof row.teams !== "object" || Array.isArray(row.teams))) throw new Error("invalid-teams");
    // No incoming _fotty authority, status, URL, credential or arbitrary field
    // survives normalization. Native retains duplicate/conflict reconciliation.
    return { id, title, category, date, popular: row.popular === true,
      poster: artwork(row.poster), teams: row.teams == null ? null : {
        home: team(row.teams.home), away: team(row.teams.away),
      }, sources };
  });
}

async function collectProvider(provider, fetcher) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5500);
  const read = async (part) => {
    const response = await fetcher(`${provider.origin}${provider.prefix}/${part}`, {
      redirect: "manual", signal: controller.signal,
      headers: { Accept: "application/json", Referer: provider.origin },
    });
    if (response.status >= 300 && response.status < 400) throw new Error("redirect-rejected");
    if (!response.ok) throw new Error("http-error");
    return normalizeBroadcastRows(await boundedJSON(response, LIMIT, controller.signal));
  };
  try {
    try {
      const matches = await read("all");
      return { id: provider.id, family: provider.family, outcome: matches.length ? "available" : "empty", matches };
    } catch {
      if (controller.signal.aborted) return { id: provider.id, family: provider.family, outcome: "unavailable", reason: "deadline", matches: [] };
    }
    // Complements remain a single family with explicit partial coverage. A valid
    // empty /all is definitive for this lookup and never triggers extra probes.
    const complements = await Promise.allSettled(["live", "upcoming"].map(read));
    const completed = complements.filter((p) => p.status === "fulfilled");
    const matches = completed.flatMap((p) => p.value), parts = completed.length;
    if (matches.length > MAX_ROWS) return { id: provider.id, family: provider.family,
      outcome: "unavailable", reason: "response-too-large", matches: [] };
    return { id: provider.id, family: provider.family,
      outcome: parts === 2 ? (matches.length ? "available" : "empty") : parts === 1 ? "partial" : "unavailable",
      ...(parts === 0 ? { reason: controller.signal.aborted ? "deadline" : "metadata-unavailable" } : {}), matches };
  } finally { clearTimeout(timer); }
}

export async function collectBroadcastCatalog({ fetcher = fetch, now = new Date() } = {}) {
  const providers = await Promise.all(BROADCAST_CATALOG_PROVIDERS.map((p) => collectProvider(p, fetcher)));
  const envelope = { schemaVersion: BROADCAST_CATALOG_SCHEMA, observedAt: now.toISOString(),
    independentFamilies: 1, providers };
  // Never truncate identities or return an oversized envelope as a partial list.
  if (new TextEncoder().encode(JSON.stringify(envelope)).byteLength > LIMIT) {
    envelope.providers = providers.map(({ id, family }) => ({ id, family, outcome: "unavailable", reason: "response-too-large", matches: [] }));
  }
  return envelope;
}
