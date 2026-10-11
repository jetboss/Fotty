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
  // Extract a narrow metadata contract; never sanitize or render HTML. Only a
  // literal widget class on a div outside prohibited/explicitly hidden markup
  // is evidence. This is not proof of browser/CSS visibility or stream delivery.
  // Unsupported, malformed or ambiguous HTML fails closed instead of being
  // repaired like a browser document. Limits are also enforced for direct calls.
  if (typeof text !== "string" || text.length > STAGE_LIMITS.catalog || text.includes("\0")
    || new TextEncoder().encode(text).byteLength > STAGE_LIMITS.catalog) return false;
  const space = (char) => char === " " || char === "\t" || char === "\n" || char === "\r" || char === "\f";
  const letter = (char) => char !== undefined && /[a-z]/i.test(char);
  const nameChar = (char) => char !== undefined && /[a-z0-9:-]/i.test(char);
  const boundary = (char) => char === ">" || char === "/" || space(char);
  const voidTags = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
  const rawTags = new Set(["script", "style", "title", "textarea", "xmp", "iframe", "noembed", "noframes"]);
  const prohibited = new Set(["head", "template", "noscript", "svg", "math", "select", "datalist", "option", "optgroup",
    "canvas", "audio", "video", "object", "frameset", ...rawTags]);
  const closesParagraph = new Set(["address", "article", "aside", "blockquote", "details", "dialog", "div", "dl", "fieldset", "figcaption", "figure",
    "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "search", "section", "table", "ul"]);
  const retainsParagraph = new Set(["a", "audio", "del", "ins", "map", "noscript", "video"]);
  const stack = [], ids = new Set(); let offset = 0, tokens = 0;

  function tagAt(start) {
    let index = start + 1, closing = false;
    if (text[index] === "/") { closing = true; index++; }
    if (!letter(text[index])) return null;
    const nameStart = index++;
    while (nameChar(text[index])) index++;
    const name = text.slice(nameStart, index).toLowerCase(), attributes = new Map();
    if (!boundary(text[index])) return null;
    while (index < text.length) {
      const beforeSpace = index;
      while (space(text[index])) index++;
      if (text[index] === ">") return { name, closing, attributes, end: index + 1, selfClosing: false };
      if (text[index] === "/" && text[index + 1] === ">") {
        // HTML ignores non-void self-closing flags; treating them as closed can
        // expose a candidate that is actually still inside script/hidden markup.
        if (closing || !voidTags.has(name)) return null;
        return { name, closing, attributes, end: index + 2, selfClosing: true };
      }
      if (closing || beforeSpace === index || attributes.size >= 128) return null;
      const attributeStart = index;
      while (index < text.length && !space(text[index]) && !["=", "/", ">"].includes(text[index])) {
        if (["<", "\"", "'", "`"].includes(text[index])) return null;
        index++;
      }
      if (index === attributeStart) return null;
      const attribute = text.slice(attributeStart, index).toLowerCase();
      if (attributes.has(attribute)) return null;
      const attributeEnd = index;
      while (space(text[index])) index++;
      let value = "";
      if (text[index] === "=") {
        index++; while (space(text[index])) index++;
        const quote = text[index] === "\"" || text[index] === "'" ? text[index++] : null;
        const valueStart = index;
        if (quote) {
          while (index < text.length && text[index] !== quote) index++;
          if (index === text.length) return null;
          value = text.slice(valueStart, index++);
          if (!space(text[index]) && text[index] !== ">" && !(text[index] === "/" && text[index + 1] === ">")) return null;
        } else {
          while (index < text.length && !space(text[index]) && text[index] !== ">") {
            if (["<", "\"", "'", "`", "="].includes(text[index])) return null;
            index++;
          }
          if (index === valueStart) return null;
          value = text.slice(valueStart, index);
        }
      } else index = attributeEnd;
      attributes.set(attribute, value);
    }
    return null;
  }

  function rawEnd(name, start) {
    const endPrefix = `</${name}`, startPrefix = `<${name}`;
    for (let index = text.indexOf("<", start); index !== -1; index = text.indexOf("<", index + 1)) {
      // Script escaped/double-escaped states require browser tokenization.
      // Reject that unsupported grammar, rather than ending raw text too soon.
      if (name === "script" && (text.startsWith("<!--", index)
        || text.slice(index, index + startPrefix.length).toLowerCase() === startPrefix && boundary(text[index + startPrefix.length]))) return null;
      if (text.slice(index, index + endPrefix.length).toLowerCase() !== endPrefix || !boundary(text[index + endPrefix.length])) continue;
      const end = tagAt(index);
      return end?.closing && end.name === name ? end : null;
    }
    return null;
  }

  while (offset < text.length) {
    const next = text.indexOf("<", offset);
    if (next === -1) break;
    if (++tokens > 50_000) return false;
    if (text.startsWith("<!--", next)) {
      const end = text.indexOf("-->", next + 4);
      if (end === -1) return false;
      // Nested/alternate comment delimiters are not repaired or re-scanned.
      const comment = text.slice(next + 4, end);
      if (comment.includes("<!--") || comment.includes("--!>")) return false;
      offset = end + 3; continue;
    }
    if (text.slice(next, next + 9).toLowerCase() === "<!doctype") {
      const end = text.indexOf(">", next + 9);
      if (end === -1 || text.slice(next + 9, end).trim().toLowerCase() !== "html" || stack.length) return false;
      offset = end + 1; continue;
    }
    const tag = tagAt(next);
    if (!tag || tag.name === "plaintext") return false;
    offset = tag.end;
    if (tag.closing) {
      // The reviewed listing omits </p> immediately before its parent closes.
      // This limited optional-end-tag case is defined by the HTML standard;
      // other misnesting is still unsupported, never repaired speculatively.
      if (stack.at(-1)?.name === "p" && stack.at(-2)?.name === tag.name
        && !retainsParagraph.has(tag.name) && !tag.name.includes("-")) stack.pop();
      if (voidTags.has(tag.name) || stack.at(-1)?.name !== tag.name) return false;
      stack.pop(); continue;
    }
    if (stack.at(-1)?.name === "p" && closesParagraph.has(tag.name)) stack.pop();
    const attributes = tag.attributes, classes = attributes.get("class") || "", style = attributes.get("style") || "";
    const ariaHidden = attributes.get("aria-hidden") || "";
    // Entity/escape/comment spellings can change class or inline visibility in
    // the browser. They are outside this literal reviewed listing contract.
    if (classes.includes("&") || ariaHidden.includes("&") || style.includes("\\") || style.includes("/*") || style.includes("&")) return false;
    const hidden = stack.at(-1)?.hidden || prohibited.has(tag.name) || attributes.has("hidden") || attributes.has("inert")
      || ariaHidden.trim().toLowerCase() === "true"
      // Recognize simple CSS zero spellings (including percentages/exponents),
      // not calc(), variables or computed CSS. Unit-bearing/unfinished tokens
      // are invalid opacity values and must not be mistaken for numeric zero.
      || /(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse)|opacity\s*:\s*[+-]?(?:0+(?:\.0+)?|\.0+)(?:e[+-]?[0-9]+)?%?)\s*(?:!\s*important\s*)?(?:;|$)/i.test(style);
    if (tag.name === "div" && !hidden) {
      for (const token of classes.split(/[\t\n\r\f ]+/)) {
        if (!token.toLowerCase().startsWith("elfsight-app-")) continue;
        if (!/^elfsight-app-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(token)) return false;
        ids.add(token.slice("elfsight-app-".length).toLowerCase());
      }
    }
    if (rawTags.has(tag.name)) {
      const end = rawEnd(tag.name, offset);
      if (!end) return false;
      offset = end.end;
    } else if (!voidTags.has(tag.name)) {
      if (stack.length >= 256) return false;
      stack.push({ name: tag.name, hidden });
    }
  }
  return stack.length === 0 && ids.size === 1;
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
