import { PROVIDERS, EXPECTED_VERSIONS } from "./manifest.mjs";

const STAGE_LIMITS = { manifest: 128 * 1024, catalog: 1024 * 1024 };
// CS recovery must satisfy the native consumer's catalog body ceiling, not
// merely the larger generic metadata probe limit used by other providers.
const CS_CATALOG_BYTES = 700 * 1024;
const safeID = (value) => typeof value === "string" && /^[a-zA-Z0-9._:-]{1,180}$/.test(value);
const receipt = (source, stage, outcome, failureClass, now, environment) => ({ environment, source, stage,
  outcome, failureClass, facts: {}, observedAt: now, versions: { ...EXPECTED_VERSIONS } });

// No redirects, credentials, body logging, scripts, media requests or automatic
// domain replacement. A successful probe proves only the described metadata.
export async function readMetadata(url, { request = fetch, maxBytes, accept = "application/json", signal } = {}) {
  const response = await request(url, { method: "GET", headers: { Accept: accept, "User-Agent": "Fotty metadata watchdog/1.0" },
    redirect: "manual", signal: signal || AbortSignal.timeout(10_000) });
  if (response.status >= 300 && response.status < 400) { await response.body?.cancel(); return { failure: "redirect-rejected" }; }
  if (response.status !== 200) { await response.body?.cancel(); return { failure: response.status === 429 ? "rate-limited" : `http-${response.status}` }; }
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) { await response.body?.cancel(); return { failure: "body-limit" }; }
  if (!response.body) return { failure: "missing-body" };
  const reader = response.body.getReader();
  const decoder = new TextDecoder(); let bytes = 0, text = "";
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) { await reader.cancel(); return { failure: "body-limit" }; }
      text += decoder.decode(value, { stream: true });
    }
    return { text: text + decoder.decode(), contentType: response.headers.get("content-type") || "" };
  } finally { reader.releaseLock(); }
}

function parsedJSON(result) {
  if (result.failure) return result;
  if (!/(?:application\/(?:[a-z.+-]*\+)?json)\b/i.test(result.contentType)) return { failure: "non-json" };
  try { return { body: JSON.parse(result.text) }; } catch { return { failure: "invalid-json" }; }
}
export function validateCSManifest(body) {
  return body && body.id === "community.nuvio.live-sports" && typeof body.version === "string" && body.version.length > 0 && body.version.length <= 80
    && Array.isArray(body.resources) && body.resources.includes("catalog") && body.resources.includes("stream")
    && Array.isArray(body.catalogs) && body.catalogs.length <= 600
    && body.catalogs.some((row) => row?.type === "tv" && row.id === "nuvio_sports_live");
}
export function validateCSCatalog(body) {
  if (!body || !Array.isArray(body.metas) || body.metas.length > 600) return false;
  const seen = new Set();
  return body.metas.every((row) => row && safeID(row.id) && !seen.has(row.id) && seen.add(row.id)
    && typeof row.name === "string" && row.name.trim().length > 0 && row.name.length <= 512
    && (row.type === undefined || row.type === "tv"));
}
export function validateStreamExCatalog(body) {
  const rows = Array.isArray(body) ? body : body?.matches;
  if (!Array.isArray(rows) || rows.length > 2000) return false;
  const seen = new Set();
  return rows.every((row) => row && safeID(row.id) && !seen.has(row.id) && seen.add(row.id)
    && typeof row.title === "string" && row.title.trim().length > 0 && row.title.length <= 512
    && Array.isArray(row.sources) && row.sources.length <= 100
    && row.sources.every((source) => source && safeID(source.source) && safeID(source.id)));
}
export function validateScore808Listing(text) {
  // Same single public calendar boundary as the native consumer. A new widget
  // layout is a contract failure, not permission to search arbitrary calendars.
  const visible = text.replace(/<!--[\s\S]*?-->/g, "").replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, "");
  const ids = new Set([...visible.matchAll(/\belfsight-app-([a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12})\b/gi)].map((m) => m[1].toLowerCase()));
  return ids.size === 1;
}

export async function probeProvider(descriptor, { request = fetch, now = Date.now(), environment = "production", reserve = async () => true } = {}) {
  // Only static, reviewed descriptors can authorize network reads.
  const reviewed = PROVIDERS.find((row) => row.source === descriptor?.source);
  if (!reviewed || JSON.stringify(descriptor) !== JSON.stringify(reviewed)) throw new Error("Unreviewed metadata source");
  const observations = [];
  const stage = descriptor.kind === "cs" ? "manifest" : "catalog";
  async function read(path, currentStage, json = true) {
    if (!await reserve(descriptor.source)) return { failure: "budget-exhausted", unknown: true };
    try {
      const maxBytes = descriptor.kind === "cs" && currentStage === "catalog"
        ? CS_CATALOG_BYTES : STAGE_LIMITS[currentStage];
      const result = await readMetadata(new URL(path, descriptor.origin), { request, maxBytes,
        accept: json ? "application/json" : "text/html" });
      return json ? parsedJSON(result) : result;
    } catch (error) { return { failure: error?.name === "TimeoutError" || error?.name === "AbortError" ? "deadline" : "transport" }; }
  }
  function record(result, currentStage, valid) {
    observations.push(receipt(descriptor.source, currentStage, result.unknown ? "unknown" : result.failure || !valid ? "failure" : "success",
      result.failure || (!valid ? "schema" : "metadata-contract"), now, environment));
  }
  const first = await read(descriptor.path, stage, descriptor.kind !== "score808");
  const valid = !first.failure && (descriptor.kind === "cs" ? validateCSManifest(first.body)
    : descriptor.kind === "score808" ? validateScore808Listing(first.text) : validateStreamExCatalog(first.body));
  record(first, stage, valid);
  if (descriptor.kind === "cs" && valid) {
    const catalog = await read("/catalog/tv/nuvio_sports_live.json", "catalog");
    record(catalog, "catalog", !catalog.failure && validateCSCatalog(catalog.body));
  }
  return observations;
}

export async function probeSources(options = {}) {
  const receipts = [];
  // Two bounded metadata requests at a time, with no compounded retries.
  for (let index = 0; index < PROVIDERS.length; index += 2) receipts.push(...(await Promise.all(
    PROVIDERS.slice(index, index + 2).map((source) => probeProvider(source, options)))).flat());
  return receipts;
}
