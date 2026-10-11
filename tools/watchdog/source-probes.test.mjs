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
