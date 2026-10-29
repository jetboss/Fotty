import assert from "node:assert/strict";
import test from "node:test";
import { collectBroadcastCatalog, normalizeBroadcastRows } from "./broadcast-catalog.mjs";
import worker from "./index.js";

const row = { id: "exact-a", title: "Home vs Away", category: "football", date: 1793303100000,
  teams: { home: { name: "Home" }, away: { name: "Away" } }, sources: [{ source: "delta", id: "advertised-a" }] };

test("normalization keeps advertised identities but strips injected Fotty authority and deliveries", () => {
  const [r] = normalizeBroadcastRows({ matches: [{ ...row, _fottySportsFixture: { status: "LIVE" },
    _fottyIdentityConflict: false, url: "https://unreviewed.invalid/stream" }] });
  assert.equal(r.id, row.id); assert.deepEqual(r.sources, row.sources);
  assert.equal(r._fottySportsFixture, undefined); assert.equal(r.url, undefined);
});
test("normalization preserves existing relative artwork and opaque badge tokens", () => {
  const [r] = normalizeBroadcastRows([{ ...row, poster: "/api/images/poster/p.webp",
    teams: { home: { name: "Home", badge: "opaque badge/token+" },
      away: { name: "Away", badge: "https://example.test/team.png" } } }]);
  assert.equal(r.poster, "/api/images/poster/p.webp");
  assert.equal(r.teams.home.badge, "opaque badge/token+");
  assert.equal(r.teams.away.badge, "https://example.test/team.png");
});
test("HTTP200 HTML scalar, serialized HTML, malformed sources and oversized rows are not empty success", () => {
  for (const body of ["<html>closed</html>", JSON.stringify([row]), {}, { matches: "wrong" },
    [{ ...row, sources: [{ source: "https://evil.invalid", id: "a" }] }],
    [{ ...row, date: "2026-10-29" }], Array(4001).fill(row)]) {
    assert.throws(() => normalizeBroadcastRows(body));
  }
});
test("one broken family profile does not discard a healthy mirror; mirrors remain one family", async () => {
  const result = await collectBroadcastCatalog({ fetcher: async (url, options) => {
    assert.equal(options.redirect, "manual");
    if (new URL(url).hostname === "streamex.sh") return Response.json([row]);
    return Response.json("<html>unavailable</html>");
  } });
  assert.equal(result.schemaVersion, 1); assert.equal(result.independentFamilies, 1);
  assert.equal(result.providers[0].outcome, "unavailable");
  assert.equal(result.providers[1].outcome, "available");
  assert.equal(result.providers[1].matches[0].id, row.id);
});
test("valid empty catalog is honest empty and does not fan out into complements", async () => {
  let requests = 0;
  const r = await collectBroadcastCatalog({ fetcher: async () => { requests++; return Response.json([]); } });
  assert.equal(requests, 3);
  assert.ok(r.providers.every((p) => p.outcome === "empty" && p.matches.length === 0));
});
test("redirects stay blocked, complementary evidence preserves partiality, duplicates are retained for native conflict checks", async () => {
  const r = await collectBroadcastCatalog({ fetcher: async (url) => {
    const u = new URL(url);
    if (u.hostname === "streamex.sh" && u.pathname.endsWith("/live")) return Response.json([row, { ...row, title: "Different vs Teams" }]);
    return new Response(null, { status: 302, headers: { location: "http://127.0.0.1/private" } });
  } });
  assert.equal(r.providers[1].outcome, "partial"); assert.equal(r.providers[1].matches.length, 2);
  assert.equal(r.providers[0].outcome, "unavailable");
});
test("slow live complement cannot prevent healthy upcoming from being requested", async () => {
  let started = 0;
  const waiters = [];
  const r = await collectBroadcastCatalog({ fetcher: async (url) => {
    if (url.endsWith("/all")) return Response.json({ error: "down" });
    if (url.endsWith("/live")) return await new Promise((resolve) => waiters.push(resolve));
    started++;
    if (started === 3) for (const release of waiters) release(new Response(null, { status: 503 }));
    return Response.json([row]);
  } });
  assert.equal(started, 3);
  assert.ok(r.providers.every((p) => p.outcome === "partial" && p.matches[0].id === row.id));
});
test("stable route rejects arbitrary upstream queries and serves a versioned failure envelope", async (t) => {
  let count = 0;
  t.mock.method(globalThis, "fetch", async () => { count++; return new Response("bad", { status: 503 }); });
  assert.equal((await worker.fetch(new Request("https://test.invalid/api/live/catalog?url=https://evil.invalid"), {})).status, 400);
  assert.equal(count, 0);
  const res = await worker.fetch(new Request("https://test.invalid/api/live/catalog"), {});
  const b = await res.json();
  assert.equal(res.status, 200); assert.equal(b.schemaVersion, 1);
  assert.equal(b.providers.length, 3); assert.ok(b.providers.every((p) => p.outcome === "unavailable"));
  assert.equal(count, 9);
});
