import test from "node:test";
import assert from "node:assert/strict";
import { PROVIDERS, observerPolicyOptions, COLLECTION_INTERVAL_MS, CONFIRMATION_WINDOWS } from "./manifest.mjs";
import { probeProvider, probeSources, readMetadata, validateCSManifest, validateCSCatalog, validateASManifest, validateASCatalog, validateStreamExCatalog, validateScore808Listing, isPublishedStreamedClosure } from "./source-probes.mjs";
import { createPolicy, emptyLedger } from "./incident-policy.mjs";
import { applyObservationBatch } from "./observation-batch.mjs";
const manifest = { id: "community.nuvio.live-sports", version: "1.0", resources: ["catalog", "stream"], catalogs: [{ type: "tv", id: "nuvio_sports_live" }] };
const asManifest = { id: "community.plaviohd", version: "1.9.62", types: ["tv"],
  resources: ["catalog", { name: "stream", types: ["tv"], idPrefixes: ["plaviohdtv-"] }],
  catalogs: [{ type: "tv", id: "plaviohd-live-sports" }, { type: "tv", id: "plaviohd-cricket" }] };
const asEntry = { id: "plaviohdtv-sfly-streamed:football-offline", type: "tv", name: "Team A vs Team B",
  description: "Team A vs Team B\n28 Oct 2026 · 20:00 UTC", genres: ["Sports"] };
const csCatalog = { metas: [{ id: "nuvio_sport_offline", name: "Team A vs Team B" }] };
const cs = PROVIDERS[0];
const leaves = (rows) => rows.filter((row) => row.failureClass !== "metadata-unavailable");
test("CS failure is independent of successful sibling; manifest530 does not request catalog", async () => {
  const calls = []; const results = await probeSources({ request: async (url) => {
    calls.push(String(url)); if (url.host === "nuviosports.xyz") return new Response("private body", { status: 530 });
    if (url.host === "www.score808live.tv") return new Response('<div class="elfsight-app-12345678-1234-1234-1234-123456789abc"></div>');
    if (url.host === "hd.plavio.site") return Response.json(url.pathname.endsWith("manifest.json") ? asManifest : { metas: [asEntry] });
    return Response.json([{ id: "offline", title: "A vs B", sources: [{ source: "golf", id: "offline" }] }]);
  } });
  assert.equal(calls.length, 8); assert.equal(results.find((row) => row.source === "cs").failureClass, "http-530");
  assert.equal(leaves(results).filter((row) => row.outcome === "success").length, 7);
  assert.equal(JSON.stringify(results).includes("private body"), false);
});
test("CS manifest and catalog are separate metadata stages, never decoded proof", async () => {
  const results = leaves(await probeProvider(cs, { request: async (url) => Response.json(url.pathname.endsWith("manifest.json") ? manifest : csCatalog) }));
  assert.deepEqual(results.map((row) => row.stage), ["manifest", "catalog", "delivery-contract"]);
  assert.ok(results.slice(0, 2).every((row) => row.outcome === "success" && !Object.hasOwn(row, "decoded")));
  assert.equal(results[2].outcome, "unknown");
});
test("CS catalog acceptance respects the native700KiB boundary, with or without content-length", async () => {
  const limit = 700 * 1024;
  const base = JSON.stringify(csCatalog);
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

test("CS rejects typed metadata drift that prevents native decoding, without requiring a fixture date", () => {
  assert.equal(validateCSCatalog(csCatalog), true);
  assert.equal(validateCSCatalog({ metas: [{ id: "channel", name: "Generic channel", released: null, genres: null }] }), true);
  for (const extra of [{ released: 42 }, { cast: "Team A" }, { genres: [42] },
    { behaviorHints: { defaultVideoId: 42 } }]) {
    assert.equal(validateCSCatalog({ metas: [{ ...csCatalog.metas[0], ...extra }] }), false);
  }
  assert.equal(validateCSManifest({ ...manifest, resources: ["catalog", "stream", 42] }), false);
  assert.equal(validateCSManifest({ ...manifest, catalogs: [...manifest.catalogs, { type: "tv" }] }), false);
});

test("AS native manifest contract rejects unsupported typed resources/configuration and catalog drift", () => {
  assert.equal(validateASManifest(asManifest), true);
  for (const change of [{ id: "other" }, { version: "invalid version" }, { types: ["unknown"] },
    { behaviorHints: { configurationRequired: true } },
    { resources: ["catalog", "stream"] },
    { resources: ["catalog", { name: "stream", types: ["tv"], idPrefixes: ["wrong-"] }] },
    { catalogs: [...asManifest.catalogs, asManifest.catalogs[0]] }]) {
    assert.equal(validateASManifest({ ...asManifest, ...change }), false);
  }
  assert.equal(validateASCatalog({ metas: [asEntry] }), true);
  for (const change of [{ id: null }, { type: null }, { description: null }, { genres: "Sports" }, { behaviorHints: {} }]) {
    assert.equal(validateASCatalog({ metas: [{ ...asEntry, ...change }] }), false);
  }
});

test("AS checks both reviewed advertised catalogs within three reads and the reviewed daily budget", async () => {
  const source = PROVIDERS.find((row) => row.kind === "as");
  assert.equal(source.maxRequestsPerDay, 288);
  assert.equal(COLLECTION_INTERVAL_MS, 15 * 60_000); assert.equal(CONFIRMATION_WINDOWS, 2);
  assert.equal(PROVIDERS.reduce((sum, row) => sum + row.maxRequestsPerDay, 0), 960);
  for (const now of [0, COLLECTION_INTERVAL_MS]) {
    const calls = []; const results = leaves(await probeProvider(source, { now, request: async (url) => {
      calls.push(String(url)); assert.equal(url.origin, "https://hd.plavio.site");
      assert.ok(["/manifest.json", "/catalog/tv/plaviohd-live-sports.json", "/catalog/tv/plaviohd-cricket.json"].includes(url.pathname));
      return Response.json(url.pathname.endsWith("manifest.json") ? asManifest : { metas: [asEntry] });
    } }));
    assert.equal(calls.length, 3); assert.deepEqual(results.map((row) => row.stage), ["manifest", "catalog", "catalog"]);
    assert.deepEqual(results.slice(1).map((row) => row.facts.scope), ["football", "cricket"]);
    assert.ok(results.every((row) => row.outcome === "success"));
  }
});

test("AS optional unadvertised cricket is inactive and makes no catalog request", async () => {
  let calls = 0; const rows = await probeProvider(PROVIDERS.find((row) => row.kind === "as"), {
    now: 30 * 60_000, request: async (url) => { calls++; return Response.json(url.pathname.endsWith("manifest.json")
      ? { ...asManifest, catalogs: [asManifest.catalogs[0]] } : { metas: [asEntry] }); },
  });
  assert.equal(calls, 2); assert.equal(rows[2].outcome, "inactive"); assert.equal(rows[2].failureClass, "catalog-unadvertised");
  assert.equal(rows[2].facts.scope, "cricket");
});

test("AS cricket failure confirms independently and healthy football or empty cricket cannot clear it", async () => {
  const source = PROVIDERS.find((row) => row.kind === "as"), start = Date.UTC(2026, 9, 28);
  const policy = createPolicy({ ...observerPolicyOptions(), windowMs: COLLECTION_INTERVAL_MS,
    failureWindows: CONFIRMATION_WINDOWS }); let ledger = emptyLedger(policy);
  for (let index = 0; index < 4; index++) {
    const now = start + index * COLLECTION_INTERVAL_MS;
    const rows = await probeProvider(source, { now, request: async (url) => {
      if (url.pathname.endsWith("manifest.json")) return Response.json(asManifest);
      if (url.pathname.endsWith("plaviohd-cricket.json")) return Response.json(index < 2 ? "bad schema" : { metas: [] });
      return Response.json({ metas: [asEntry] });
    } });
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
    if (index >= 1) {
      const incident = Object.values(ledger.incidents).find((row) => row.facts.scope === "cricket");
      assert.equal(incident.state, "confirmed"); assert.equal(incident.successCount, 0);
    }
  }
});

test("AS enforces native512KiB metadata ceilings including unannounced streaming bodies", async () => {
  const source = PROVIDERS.find((row) => row.kind === "as"), limit = 512 * 1024;
  for (const stage of ["manifest", "catalog"]) for (const size of [limit, limit + 1]) {
    const rows = await probeProvider(source, { now: 0, request: async (url) => {
      const isManifest = url.pathname.endsWith("manifest.json"), body = JSON.stringify(isManifest ? asManifest : { metas: [asEntry] });
      const padded = (stage === "manifest") === isManifest ? body + " ".repeat(size - Buffer.byteLength(body)) : body;
      return new Response(padded, { headers: { "content-type": "application/json" } });
    } });
    const row = rows.find((row) => row.stage === stage);
    assert.equal(row.outcome, size === limit ? "success" : "failure");
    assert.equal(row.failureClass, size === limit ? "metadata-contract" : "body-limit");
  }
});

test("empty and source-less catalogs are unknown and cannot recover a publisher closure", async () => {
  const source = PROVIDERS.find((row) => row.source === "streamed-backup"), start = Date.UTC(2026, 9, 28);
  const policy = createPolicy({ ...observerPolicyOptions(), windowMs: 30 * 60_000 }); let ledger = emptyLedger(policy);
  for (let i = 0; i < 3; i++) {
    const now = start + i * 30 * 60_000;
    const rows = await probeProvider(source, { now, request: async () => new Response("<html>closed</html>", { headers: { "content-type": "text/html" } }) });
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
  }
  assert.equal(Object.values(ledger.incidents)[0].state, "confirmed");
  for (const [index, body] of [[], { matches: [] }, [{ id: "x", title: "A vs B", sources: [] }]].entries()) {
    const now = start + (index + 3) * 30 * 60_000;
    const rows = await probeProvider(source, { now, request: async () => Response.json(body) });
    assert.equal(rows[0].outcome, "unknown"); assert.equal(rows[0].failureClass, "empty-catalog");
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
    assert.equal(Object.values(ledger.incidents)[0].state, "confirmed");
  }
  for (let i = 6; i < 8; i++) {
    const now = start + i * 30 * 60_000;
    const rows = await probeProvider(source, { now, request: async () => Response.json([{ id: "x", title: "A vs B", sources: [{ source: "golf", id: "x" }] }]) });
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
  }
  assert.equal(Object.values(ledger.incidents)[0].state, "resolved");
});

test("alternating known metadata failures confirm one stable outage and require real same-source recovery", async () => {
  const source = PROVIDERS.find((row) => row.source === "streamed-backup"), start = Date.UTC(2026, 9, 28);
  const sibling = PROVIDERS.find((row) => row.source === "streamex-primary");
  const policy = createPolicy({ ...observerPolicyOptions(), windowMs: COLLECTION_INTERVAL_MS,
    failureWindows: CONFIRMATION_WINDOWS }); let ledger = emptyLedger(policy);
  const payload = [{ id: "x", title: "A vs B", sources: [{ source: "golf", id: "x" }] }];
  for (let index = 0; index < 2; index++) {
    const now = start + index * COLLECTION_INTERVAL_MS;
    const rows = await probeProvider(source, { now, request: async () => index === 0
      ? new Response(null, { status: 503 }) : new Response("<html>unavailable</html>", { headers: { "content-type": "text/html" } }) });
    assert.equal(rows[0].failureClass, index === 0 ? "http-503" : "non-json");
    assert.equal(rows[1].failureClass, "metadata-unavailable");
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
  }
  const aggregate = () => Object.values(ledger.incidents).find((row) => row.failureClass === "metadata-unavailable");
  assert.equal(aggregate().state, "confirmed");
  for (let index = 2; index < 4; index++) {
    const now = start + index * COLLECTION_INTERVAL_MS;
    const rows = [...await probeProvider(sibling, { now, request: async () => Response.json(payload) }),
      ...await probeProvider(source, { now, request: async () => Response.json([]) })];
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
    assert.equal(aggregate().state, "confirmed"); assert.equal(aggregate().successCount, 0);
  }
  for (let index = 4; index < 6; index++) {
    const now = start + index * COLLECTION_INTERVAL_MS;
    ledger = applyObservationBatch(ledger, await probeProvider(source, { now, request: async () => Response.json(payload) }), policy, now).state;
  }
  assert.equal(aggregate().state, "resolved");
});

test("budget unknown interrupts an unconfirmed aggregate failure streak without an extra read", async () => {
  const source = PROVIDERS.find((row) => row.source === "streamed-backup"), start = Date.UTC(2026, 9, 28);
  const policy = createPolicy({ ...observerPolicyOptions(), windowMs: COLLECTION_INTERVAL_MS,
    failureWindows: CONFIRMATION_WINDOWS }); let ledger = emptyLedger(policy);
  for (let index = 0; index < 3; index++) {
    const now = start + index * COLLECTION_INTERVAL_MS; let calls = 0;
    const rows = await probeProvider(source, { now, reserve: async () => index !== 1, request: async () => {
      calls++; return new Response(null, { status: 503 });
    } });
    assert.equal(calls, index === 1 ? 0 : 1);
    ledger = applyObservationBatch(ledger, rows, policy, now).state;
    const aggregate = Object.values(ledger.incidents).find((row) => row.failureClass === "metadata-unavailable");
    assert.equal(aggregate.state, "suspect"); assert.equal(aggregate.failureCount, index === 1 ? 0 : 1);
  }
});

test("CS/AS empty catalogs remain unknown and JSON strings remain typed schema failures", async () => {
  for (const source of PROVIDERS.filter((row) => ["cs", "as"].includes(row.kind))) {
    for (const body of [{ metas: [] }, "Service closed"]) {
      const rows = await probeProvider(source, { now: 0, request: async (url) => Response.json(
        url.pathname.endsWith("manifest.json") ? source.kind === "cs" ? manifest : asManifest : body) });
      assert.equal(rows[1].outcome, typeof body === "string" ? "failure" : "unknown");
      assert.equal(rows[1].failureClass, typeof body === "string" ? "schema" : "empty-catalog");
    }
  }
});

test("only the reviewed publisher title and visible sentence identify explicit closure", async () => {
  const closure = "<!doctype html><html><head><title>Streamed Closure</title></head><body><p>We are no longer operating Streamed.</p></body></html>";
  const source = PROVIDERS.find((row) => row.source === "streamed-backup");
  for (const text of [closure, JSON.stringify(closure)]) {
    assert.equal(isPublishedStreamedClosure(text), true);
    const rows = await probeProvider(source, { request: async () => new Response(text, {
      headers: { "content-type": text.startsWith('"') ? "application/json" : "text/html" },
    }) });
    assert.equal(rows[0].outcome, "failure"); assert.equal(rows[0].failureClass, "published-closure");
    assert.equal(JSON.stringify(rows).includes("We are no longer"), false);
  }
  for (const text of ["<html>closed</html>", JSON.stringify("Service closed"),
    "<title>Other closure</title><p>We are no longer operating Streamed.</p>",
    "<title>Streamed Closure</title><script>We are no longer operating Streamed.</script>",
    "<!--<title>Streamed Closure</title><p>We are no longer operating Streamed.</p>-->",
    "<title>Streamed Closure</title><p>Service unavailable.</p>"]) assert.equal(isPublishedStreamedClosure(text), false);
  const generic = await probeProvider(source, { request: async () => Response.json("Service closed") });
  assert.equal(generic[0].failureClass, "schema");
  const redirected = await probeProvider(source, { request: async () => new Response(closure, { status: 302 }) });
  assert.equal(redirected[0].failureClass, "redirect-rejected");
});

test("CS reuses one fresh official fixture for one bounded descriptor request and never follows a delivery URL", async () => {
  const now = Date.UTC(2026, 9, 28, 21), start = new Date(now - 3600_000).toISOString();
  const checkedAt = new Date(now).toISOString();
  const fixture = { id: "sports-fixture:carabao-cup:offline", sport: "football", competitionId: "carabao-cup",
    eventKind: "match", status: "live", start, squad: { gender: "men", ageGroup: "senior" },
    participants: [{ id: "team:liverpool", name: "Liverpool" }, { id: "team:chelsea", name: "Chelsea" }],
    source: { observedAt: checkedAt, verification: "verified" } };
  const snapshot = { schemaVersion: 1, complete: true, sourceStatus: "verified", checkedAt, fixtures: [fixture],
    coverage: [{ sport: "football", competitionId: "carabao-cup", status: "covered", checkedAt }] };
  const catalog = { metas: [{ id: "nuvio_sport_offline", type: "tv", name: "LIVE: Liverpool vs Chelsea",
    cast: ["Liverpool", "Chelsea"], genres: ["FOOTBALL"], released: start }] };
  const delivery = "https://nuviosports.xyz/api/manifest.m3u8?url=https%3A%2F%2Fcdn.example.net%2Fmatch.m3u8";
  for (const [body, expected] of [[{ streams: [{ url: delivery }] }, "success"], [{ streams: [] }, "unknown"],
    [{ streams: [{ url: "https://nuviosports.xyz/new-unreviewed-route" }] }, "failure"]]) {
    const calls = []; let reserved = 0;
    const rows = await probeProvider(cs, { now, sportsSnapshot: snapshot, reserve: async () => { reserved++; return true; }, request: async (url) => {
      calls.push(url.pathname); assert.equal(url.origin, "https://nuviosports.xyz");
      assert.ok(["/manifest.json", "/catalog/tv/nuvio_sports_live.json", "/stream/tv/nuvio_sport_offline.json"].includes(url.pathname));
      return Response.json(url.pathname === "/manifest.json" ? manifest : url.pathname.startsWith("/catalog/") ? catalog : body);
    } });
    assert.equal(calls.length, 3); assert.equal(reserved, 3);
    const observed = rows.find((row) => row.stage === "delivery-contract"); assert.equal(observed.outcome, expected);
    assert.deepEqual(observed.facts, { scope: "football", dimension: "candidate-shape" });
    assert.equal(JSON.stringify(rows).includes("nuvio_sport_offline"), false);
  }
  for (const sportsSnapshot of [undefined, { ...snapshot, fixtures: [{ ...fixture, status: "scheduled" }] },
    { ...snapshot, fixtures: [{ ...fixture, source: { ...fixture.source, verification: "held" } }] }]) {
    let calls = 0;
    const rows = await probeProvider(cs, { now, sportsSnapshot, request: async (url) => {
      calls++; assert.ok(!url.pathname.startsWith("/stream/"));
      return Response.json(url.pathname === "/manifest.json" ? manifest : catalog);
    } });
    assert.equal(calls, 2); assert.equal(rows.find((row) => row.stage === "delivery-contract").outcome, "unknown");
  }
});

test("generic CS channels do not authorize a descriptor request", async () => {
  const now = Date.UTC(2026, 9, 28, 21), checkedAt = new Date(now).toISOString();
  const sportsSnapshot = { schemaVersion: 1, complete: true, sourceStatus: "verified", checkedAt,
    fixtures: [{ id: "sports-fixture:carabao-cup:offline", sport: "football", competitionId: "carabao-cup",
      eventKind: "match", status: "live", start: new Date(now - 3600_000).toISOString(), squad: { gender: "men", ageGroup: "senior" },
      participants: [{ id: "team:liverpool", name: "Liverpool" }, { id: "team:chelsea", name: "Chelsea" }],
      source: { observedAt: checkedAt, verification: "verified" } }],
    coverage: [{ sport: "football", competitionId: "carabao-cup", status: "covered", checkedAt }] };
  let calls = 0; const rows = await probeProvider(cs, { now, sportsSnapshot, request: async (url) => {
    calls++; assert.ok(!url.pathname.startsWith("/stream/"));
    return Response.json(url.pathname.endsWith("manifest.json") ? manifest : { metas: [{ id: "channel", name: "Generic channel" }] });
  } });
  assert.equal(calls, 2); assert.equal(rows.find((row) => row.stage === "delivery-contract").outcome, "unknown");
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

test("Score808 rejects entity aria-hidden and equivalent simple zero opacity spellings", () => {
  for (const value of ["&#116;rue", "&#x74;rue", "tr&#117;e", "false&amp;other"]) {
    assert.equal(validateScore808Listing(`<div aria-hidden="${value}">${widget}</div>`), false, value);
  }
  for (const value of ["00", "+0", "-0", ".0", "+00.000", "0e0", "-0.0E+2", "00e-4", "0%", "+.00e2%", "0 ! important"]) {
    assert.equal(validateScore808Listing(`<div style="opacity:${value}">${widget}</div>`), false, value);
  }
  // These are nonzero numbers or invalid CSS opacity tokens, not hidden-zero
  // evidence. This fixture does not claim a computed-style/rendering verdict.
  for (const value of ["0.5", ".01", "1e-2", "0px", "00em", "0e", "0e+", "0.", "0e2px", "+ 0"]) {
    assert.equal(validateScore808Listing(`<div style="opacity:${value}">${widget}</div>`), true, value);
  }
  assert.equal(validateScore808Listing(`<div aria-hidden="false">${widget}</div>`), true);
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
    assert.equal(leaves(rows).length, 1); assert.equal(rows[0].outcome, "failure"); assert.equal(rows[0].failureClass, "schema");
    assert.equal(JSON.stringify(rows).includes(calendarID), false);
  }
});
