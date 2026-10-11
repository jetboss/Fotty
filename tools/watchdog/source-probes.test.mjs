import test from "node:test";
import assert from "node:assert/strict";
import { PROVIDERS } from "./manifest.mjs";
import { probeProvider, probeSources, readMetadata, validateCSManifest, validateCSCatalog, validateStreamExCatalog, validateScore808Listing } from "./source-probes.mjs";
const manifest = { id: "community.nuvio.live-sports", version: "1.0", resources: ["catalog", "stream"], catalogs: [{ type: "tv", id: "nuvio_sports_live" }] };
const cs = PROVIDERS[0];
test("CS failure is independent of successful sibling; manifest530 does not request catalog", async () => {
  const calls = []; const results = await probeSources({ request: async (url) => {
    calls.push(String(url)); if (url.host === "nuviosports.xyz") return new Response("private body", { status: 530 });
    if (url.host === "www.score808live.tv") return new Response('<div class="elfsight-app-12345678-1234-1234-1234-123456789abc"></div>');
    return Response.json([]);
  } });
  assert.equal(calls.length, 5); assert.equal(results.find((row) => row.source === "cs").failureClass, "http-530");
  assert.equal(results.filter((row) => row.outcome === "success").length, 4);
  assert.equal(JSON.stringify(results).includes("private body"), false);
});
test("CS manifest and catalog are separate metadata stages, never decoded proof", async () => {
  const results = await probeProvider(cs, { request: async (url) => Response.json(url.pathname.endsWith("manifest.json") ? manifest : { metas: [] }) });
  assert.deepEqual(results.map((row) => row.stage), ["manifest", "catalog"]);
  assert.ok(results.every((row) => row.outcome === "success" && !Object.hasOwn(row, "decoded")));
});
test("CS catalog acceptance respects the native700KiB boundary, with or without content-length", async () => {
  const limit = 700 * 1024;
  const base = JSON.stringify({ metas: [] });
  for (const declared of [false, true]) {
    for (const size of [limit, limit + 1]) {
      const results = await probeProvider(cs, { request: async (url) => {
        if (url.pathname.endsWith("manifest.json")) return Response.json(manifest);
        return new Response(base + " ".repeat(size - Buffer.byteLength(base)), {
          headers: { "content-type": "application/json", ...(declared ? { "content-length": String(size) } : {}) },
        });
      } });
      assert.equal(results[0].outcome, "success");
      assert.equal(results[1].outcome, size === limit ? "success" : "failure");
      assert.equal(results[1].failureClass, size === limit ? "metadata-contract" : "body-limit");
    }
  }
});
for (const [name, response, expected] of [
  ["HTML200", () => new Response("<html>challenge</html>", { headers: { "content-type": "text/html" } }), "non-json"],
  ["malformedJSON", () => new Response("{", { headers: { "content-type": "application/json" } }), "invalid-json"],
  ["wrong identity", () => Response.json({ ...manifest, id: "unreviewed" }), "schema"],
  ["rate limiting", () => new Response(null, { status: 429 }), "rate-limited"],
  ["redirect", () => new Response(null, { status: 302, headers: { Location: "https://private.invalid" } }), "redirect-rejected"],
]) test(name, async () => { const rows = await probeProvider(cs, { request: async () => response() }); assert.equal(rows[0].failureClass, expected); });
test("body is bounded while streaming even without content-length", async () => {
  let cancelled = false; const stream = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(20)); }, cancel() { cancelled = true; } });
  const result = await readMetadata(new URL("https://example.invalid"), { maxBytes: 10, request: async () => new Response(stream) });
  assert.equal(result.failure, "body-limit"); assert.equal(cancelled, true);
});
test("daily budget refusal is unknown and makes no request", async () => {
  const rows = await probeProvider(cs, { reserve: async () => false, request: async () => { throw new Error("must not fetch"); } });
  assert.equal(rows[0].outcome, "unknown"); assert.equal(rows[0].failureClass, "budget-exhausted");
});
test("descriptors cannot move the watchdog to an unreviewed domain", async () => {
  await assert.rejects(probeProvider({ ...cs, origin: "https://different.invalid" }), /Unreviewed/);
});
test("validators reject duplicate identities and ambiguous calendar changes", () => {
  assert.equal(validateCSManifest(manifest), true); assert.equal(validateCSCatalog({ metas: [{ id: "x", name: "X" }, { id: "x", name: "X" }] }), false);
  assert.equal(validateStreamExCatalog([{ id: "x", title: "A vs B", sources: [{ source: "golf", id: "x" }] }]), true);
  assert.equal(validateStreamExCatalog({ matches: "invalid" }), false);
  assert.equal(validateScore808Listing('<script>elfsight-app-12345678-1234-1234-1234-123456789abc</script>'), false);
});

const calendarID = "e35d5dc2-ac62-48de-bb53-2946ecd35042";
const widget = `<div class="elfsight-app-${calendarID}"></div>`;
const otherWidget = '<div class="elfsight-app-12345678-1234-1234-1234-123456789abc"></div>';

test("Score808 accepts the reviewed literal listing element and bounded document grammar", () => {
  // This exact public widget element was reviewed on the admitted listing page
  // on11Oct2026; this fixture is a small structural extract, not a saved page or
  // completeness/decoded-stream certificate. The publisher omits optional </p>.
  assert.equal(validateScore808Listing(widget), true);
  assert.equal(validateScore808Listing(`<!doctype html><html><head><meta charset=utf-8><title>Football</title>
    <script async src="/public-calendar.js"></script></head><body><article><div><p>Calendar
    </div>${widget}</article></body></html>`), true);
  assert.equal(validateScore808Listing(`<div><p>Intro${widget}</div>`), true);
  assert.equal(validateScore808Listing(`<DIV CLASS='calendar ELFSIGHT-APP-${calendarID.toUpperCase()} other'></DIV>`), true);
  assert.equal(validateScore808Listing(`<div class=elfsight-app-${calendarID}></div>`), true);
  assert.equal(validateScore808Listing(widget + widget), true); // one identity, not an element-count claim
  assert.equal(validateScore808Listing(widget + otherWidget), false);
});

test("Score808 never treats comments, strings, text or unrelated attributes as a widget", () => {
  for (const html of [
    `<!-- ${widget} -->`, `<script>${widget}</script>`, `<script data-note='>'>${widget}</script>`,
    `<script>const identity = "elfsight-app-${calendarID}";</script>`,
    `<style>${widget}</style>`, `<textarea>${widget}</textarea>`, `<title>${widget}</title>`,
    `<iframe>${widget}</iframe>`, `<xmp>${widget}</xmp>`, `<noembed>${widget}</noembed>`, `<noframes>${widget}</noframes>`,
    `<div data-class="elfsight-app-${calendarID}"></div>`, `<span class="elfsight-app-${calendarID}"></span>`,
    `<div title='${widget}'></div>`, `elfsight-app-${calendarID}`, `<div>elfsight-app-${calendarID}</div>`,
  ]) assert.equal(validateScore808Listing(html), false, html);
  assert.equal(validateScore808Listing(`<!-- ${otherWidget} --><script>${otherWidget}</script>${widget}`), true);
  assert.equal(validateScore808Listing(`<script>${otherWidget}</scriptfoo>${otherWidget}</script>${widget}`), true);
});

test("Score808 rejects hidden/inert/template/foreign-context identities", () => {
  for (const html of [
    `<div hidden>${widget}</div>`, `<div hidden class="elfsight-app-${calendarID}"></div>`,
    `<div aria-hidden="true">${widget}</div>`, `<div inert>${widget}</div>`,
    `<div style="display: none">${widget}</div>`, `<div style="visibility:hidden!important">${widget}</div>`,
    `<div style="opacity:0.00">${widget}</div>`, `<template>${widget}</template>`, `<noscript>${widget}</noscript>`,
    `<head>${widget}</head>`, `<svg><foreignObject>${widget}</foreignObject></svg>`, `<math>${widget}</math>`,
    `<select>${widget}</select>`, `<datalist>${widget}</datalist>`, `<canvas>${widget}</canvas>`,
    `<audio>${widget}</audio>`, `<video>${widget}</video>`, `<object>${widget}</object>`, `<frameset>${widget}</frameset>`,
  ]) assert.equal(validateScore808Listing(html), false, html);
  assert.equal(validateScore808Listing(`<div hidden>${otherWidget}</div>${widget}`), true);
  assert.equal(validateScore808Listing(`<div style="opacity:0.5">${widget}</div>`), true);
});

test("Score808 fails closed on CodeQL comment/script end-tag and ambiguous token cases", () => {
  for (const html of [
    `<!--${widget}`, `<!--<!-- -->${widget}`, `<!-- ignored --!>${widget} -->`,
    `<script>${widget}`, `<script>${otherWidget}</script\t\n bar>${widget}`,
    `<script>${otherWidget}</script/>${widget}`, `<script/>${widget}`,
    `<script><!-- <script>${otherWidget}</script>${widget}</script>`,
    `<scr<script>ipt>${widget}</scr<script>ipt>`, `<script data-note="unterminated>${widget}`,
    `<div class="elfsight-app-${calendarID}" CLASS="other"></div>`,
    `<div class="elfsight-app-${calendarID}"class="other"></div>`,
    `<div class="elfsight-app-${calendarID}&#32;other"></div>`,
    `<div class="elfsight-app-${calendarID}-suffix"></div>`,
    `<div style="display/**/:none">${widget}</div>`,
    `<div>${widget}</section>`, `<plaintext>${widget}`, `<div class="elfsight-app-${calendarID}"></div>\0`,
  ]) assert.equal(validateScore808Listing(html), false, html);
});

test("Score808 enforces direct byte, nesting and token bounds without HTML execution", () => {
  assert.equal(validateScore808Listing(null), false);
  assert.equal(validateScore808Listing(widget + " ".repeat(1024 * 1024)), false);
  assert.equal(validateScore808Listing(widget + "é".repeat(600_000)), false);
  assert.equal(validateScore808Listing("<div>".repeat(257) + widget + "</div>".repeat(257)), false);
  assert.equal(validateScore808Listing("<br>".repeat(50_001) + widget), false);
});

test("malformed or script-only Score808 listing records a contract failure, not metadata recovery", async () => {
  const source = PROVIDERS.find((row) => row.kind === "score808");
  for (const html of [`<script>${widget}</script>`, `<script>${otherWidget}</script\t\n bar>${widget}`]) {
    const rows = await probeProvider(source, { request: async () => new Response(html, { headers: { "content-type": "text/html" } }) });
    assert.equal(rows.length, 1); assert.equal(rows[0].outcome, "failure"); assert.equal(rows[0].failureClass, "schema");
    assert.equal(JSON.stringify(rows).includes(calendarID), false);
  }
});
