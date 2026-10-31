import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import worker, { BroadcastRegistry, enabledBroadcastProviders, broadcastRegistryEnabled,
  loadBroadcastRegistryFixtures } from "./index.js";
import { SPORTS_SOURCES } from "./sports-fixture-sources.mjs";
import { refreshSportsSource } from "./sports-fixture-registry.mjs";
import { normalizeBroadcastCollection, associateBroadcasts, broadcastRegistryHash } from "./broadcast-registry-policy.mjs";

const origin = "https://test.invalid", route = "/api/live/broadcasts";
function binding(reply = { schemaVersion: 1, revision: "accepted", generatedAt: new Date().toISOString(), providers: [], broadcasts: [], links: [] }, status = 200) {
  const calls = [];
  return { calls, idFromName(name) { assert.equal(name, "shared-broadcast-registry-v1"); return name; },
    get() { return { async fetch(request) { calls.push(request instanceof Request ? { url: request.url, method: request.method }
      : { url: String(request), method: "GET" }); return Response.json(reply, { status }); } }; } };
}
const envFor = (registry, extra = {}) => ({ BROADCAST_REGISTRY: registry, FOTTY_BROADCAST_REGISTRY_ENABLED: "1",
  FOTTY_BROADCAST_REGISTRY_SOURCES: "communitysports", ...extra });
async function withoutOutbound(operation) {
  const original = globalThis.fetch; let attempts = 0;
  globalThis.fetch = async () => { attempts++; throw new Error("Unexpected external HTTP"); };
  try { const result = await operation(); assert.equal(attempts, 0); return result; }
  finally { globalThis.fetch = original; }
}

test("registry OFF, missing binding and invalid source inventory cannot access its DO or any upstream", async () => withoutOutbound(async () => {
  for (const extra of [{ FOTTY_BROADCAST_REGISTRY_ENABLED: "0" }, { FOTTY_BROADCAST_REGISTRY_ENABLED: true },
    { FOTTY_BROADCAST_REGISTRY_SOURCES: "" }, { FOTTY_BROADCAST_REGISTRY_SOURCES: "communitysports,communitysports" },
    { FOTTY_BROADCAST_REGISTRY_SOURCES: "communitysports,https://unreviewed.example" },
    { FOTTY_BROADCAST_REGISTRY_SOURCES: "not-a-reviewed-source" }, { FOTTY_BROADCAST_REGISTRY_SOURCES: null },
    { BROADCAST_REGISTRY: undefined }]) {
    const stub = binding(), env = envFor(stub, extra);
    const response = await worker.fetch(new Request(origin + route), env);
    assert.equal(response.status, 503); assert.equal((await response.json()).activation, "pending");
    assert.equal(stub.calls.length, 0); assert.equal(broadcastRegistryEnabled(env), false);
  }
}));

test("public registry GET is a bounded read, rejects queries/POST and preserves schema/CORS headers", async () => withoutOutbound(async () => {
  const stub = binding(), env = envFor(stub);
  const response = await worker.fetch(new Request(origin + route), env);
  assert.equal(response.status, 200); assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
  assert.equal(response.headers.get("X-Fotty-Broadcast-Registry-Schema"), "1");
  assert.equal(response.headers.get("Cache-Control"), "public, max-age=30");
  assert.ok(response.headers.get("X-Fotty-Worker-Version"));
  assert.deepEqual(stub.calls.map((call) => call.method), ["GET"]);
  assert.equal(new URL(stub.calls[0].url).pathname, "/snapshot");
  for (const query of ["?source=communitysports", "?refresh=1", "?url=https://unreviewed.example"]) {
    assert.equal((await worker.fetch(new Request(origin + route + query), env)).status, 400);
  }
  assert.equal((await worker.fetch(new Request(origin + route, { method: "POST" }), env)).status, 405);
  assert.equal(stub.calls.length, 1, "Neither query strings nor public POST can invoke refresh");
}));

test("registry defaults to the fixed seven-provider compatibility view and only the exact capability receives reviewed programmes", async () => withoutOutbound(async () => {
  const oldCodes = ["streamex", "score808", "communitysports", "plaviosports", "cncsports", "flixstreams", "streamvix"];
  const expiry = "2026-10-30T18:10:00.000Z", observed = "2026-10-30T18:00:00.000Z";
  const snapshot = { schemaVersion: 1, revision: "f".repeat(64), generatedAt: observed,
    providers: [...oldCodes, "reviewedtv"].map((providerCode) => ({ providerCode, scope: "cricket", status: "available", observedAt: observed, expiresAt: expiry })),
    broadcasts: [{ id: "br:old", providerCode: "communitysports", observedAt: observed, expiresAt: expiry },
      { id: "br:programme", providerCode: "reviewedtv", scope: "cricket", sport: "cricket", kind: "programme",
        channelID: "cricket-channel:willow", streamID: "reviewed-tv:willow-main", providerEventID: "reviewed-tv:programme:" + "a".repeat(64), observedAt: observed, expiresAt: expiry }],
    links: [{ providerCode: "communitysports", fixtureID: "fixture", broadcastID: "br:old", expiresAt: expiry },
      { providerCode: "reviewedtv", fixtureID: "fixture", broadcastID: "br:programme", expiresAt: expiry }] };
  const stub = binding(snapshot), env = envFor(stub), header = "X-Fotty-Broadcast-Capabilities";
  const legacyResponse = await worker.fetch(new Request(origin + route), env), legacy = await legacyResponse.json();
  assert.equal(legacyResponse.status, 200); assert.equal(legacyResponse.headers.get("Vary"), header + ", X-Fotty-Broadcast-Assignments");
  assert.deepEqual(legacy.providers.map((p) => p.providerCode), oldCodes, "An old strict provider enum never sees the eighth provider");
  assert.deepEqual(legacy.broadcasts, [snapshot.broadcasts[0]]); assert.deepEqual(legacy.links, [snapshot.links[0]]);
  assert.equal(legacy.generatedAt, snapshot.generatedAt); assert.equal(legacy.links[0].expiresAt, expiry);
  assert.equal(legacy.broadcasts[0].observedAt, observed);
  assert.equal(legacy.revision, await broadcastRegistryHash([snapshot.revision, "legacy-seven-provider-v1"]));
  assert.notEqual(legacy.revision, snapshot.revision);
  const capableResponse = await worker.fetch(new Request(origin + route, { headers: { [header]: "reviewedtv-programme-v1" } }), env);
  assert.equal(capableResponse.headers.get("Vary"), header + ", X-Fotty-Broadcast-Assignments"); assert.deepEqual(await capableResponse.json(), snapshot);
  for (const value of ["reviewedtv-programme-v1,other", "REVIEWEDTV-PROGRAMME-V1", "communitysports"]) {
    const response = await worker.fetch(new Request(origin + route, { headers: { [header]: value } }), env);
    assert.deepEqual(await response.json(), legacy, "Unrecognized capability values select the same fixed legacy profile");
  }
  assert.equal(stub.calls.length, 5); assert.ok(stub.calls.every((call) => call.method === "GET" && new URL(call.url).pathname === "/snapshot"));
  const before = stub.calls.length;
  assert.equal((await worker.fetch(new Request(origin + route + "?capabilities=reviewedtv-programme-v1"), env)).status, 400);
  assert.equal(stub.calls.length, before, "Queries never select a profile or cause DO work");
  const preflight = await worker.fetch(new Request(origin + route, { method: "OPTIONS" }), env);
  assert.equal(preflight.status, 204); assert.ok(preflight.headers.get("Access-Control-Allow-Headers").includes(header));
  assert.equal(stub.calls.length, before);
  const unrelated = await worker.fetch(new Request(origin + "/health", { method: "OPTIONS" }), env);
  assert.ok(!unrelated.headers.get("Access-Control-Allow-Headers").includes(header), "Unrelated route CORS remains unchanged");
}));

test("registry capability projection keeps failure status/body and the four-MiB successful-body bound", async () => withoutOutbound(async () => {
  const body = { schemaVersion: 1, activation: "unavailable" }, unavailable = binding(body, 503);
  for (const headers of [{}, { "X-Fotty-Broadcast-Capabilities": "reviewedtv-programme-v1" }]) {
    const response = await worker.fetch(new Request(origin + route, { headers }), envFor(unavailable));
    assert.equal(response.status, 503); assert.deepEqual(await response.json(), body);
  }
  assert.equal(unavailable.calls.length, 2);
  const oversized = binding({ schemaVersion: 1, revision: "f".repeat(64), generatedAt: "2026-10-30T18:00:00.000Z",
    providers: [], broadcasts: [], links: [], untrustedPadding: "x".repeat(4 * 1024 * 1024) });
  for (const headers of [{}, { "X-Fotty-Broadcast-Capabilities": "reviewedtv-programme-v1" }]) {
    const response = await worker.fetch(new Request(origin + route, { headers }), envFor(oversized));
    assert.equal(response.status, 503); assert.equal((await response.json()).activation, "unavailable");
  }
  assert.equal(oversized.calls.length, 2, "Each GET is still only one bounded metadata snapshot read");
}));

test("dual-header reviewed assignment negotiation preserves old Willow clients and isolates cache variants", async () => withoutOutbound(async () => {
  const primary = "X-Fotty-Broadcast-Capabilities", secondary = "X-Fotty-Broadcast-Assignments";
  const observed = "2026-10-31T22:00:00.000Z", expiry = "2026-10-31T22:10:00.000Z";
  const snapshot = { schemaVersion: 1, revision: "e".repeat(64), generatedAt: observed,
    providers: [{ providerCode: "communitysports", scope: "football" }, { providerCode: "reviewedtv", scope: "cricket" }, { providerCode: "reviewedtv", scope: "football" }],
    broadcasts: [{ id: "br:old", providerCode: "communitysports", scope: "football" },
      { id: "br:willow", providerCode: "reviewedtv", scope: "cricket", sport: "cricket", kind: "programme", channelID: "cricket-channel:willow",
        streamID: "reviewed-tv:willow-main", providerEventID: "reviewed-tv:programme:" + "a".repeat(64), observedAt: observed, expiresAt: expiry },
      { id: "br:football", providerCode: "reviewedtv", scope: "football", sport: "football", kind: "event", stationMarket: "UY", observedAt: observed, expiresAt: expiry }],
    links: [{ providerCode: "communitysports", broadcastID: "br:old", matchMethod: "exact" },
      { providerCode: "reviewedtv", broadcastID: "br:willow", matchMethod: "programme" },
      { providerCode: "reviewedtv", broadcastID: "br:football", matchMethod: "channel-assignment", startRelation: "channel-coverage" }] };
  const stub = binding(snapshot), env = envFor(stub);
  const read = async (headers) => { const response = await worker.fetch(new Request(origin + route, { headers }), env);
    assert.equal(response.status, 200); assert.equal(response.headers.get("Vary"), primary + ", " + secondary); return response.json(); };
  const legacy = await read({});
  assert.deepEqual(legacy.providers.map((p) => p.providerCode), ["communitysports"]); assert.equal(legacy.broadcasts.length, 1);
  const v1 = await read({ [primary]: "reviewedtv-programme-v1" });
  assert.deepEqual(v1.broadcasts.map((b) => b.id), ["br:old", "br:willow"]); assert.equal(v1.providers.length, 2);
  assert.deepEqual(v1.links.map((l) => l.matchMethod), ["exact", "programme"]);
  assert.equal(v1.revision, await broadcastRegistryHash([snapshot.revision, "reviewedtv-willow-programme-v1"]));
  for (const headers of [{ [primary]: "reviewedtv-programme-v2" },
    { [primary]: "reviewedtv-programme-v1", [secondary]: "reviewedtv-programme-v2" }]) assert.deepEqual(await read(headers), snapshot);
  for (const value of ["reviewedtv-programme-v2,other", "REVIEWEDTV-PROGRAMME-V2", "unrecognized"]) {
    assert.deepEqual(await read({ [primary]: "reviewedtv-programme-v1", [secondary]: value }), v1);
  }
  assert.deepEqual(await read({ [secondary]: "reviewedtv-programme-v2" }), legacy, "A secondary tag alone cannot opt an old client into unfamiliar provider types");
  assert.deepEqual(await read({ [primary]: "unrecognized", [secondary]: "reviewedtv-programme-v2" }), legacy);
  const preflight = await worker.fetch(new Request(origin + route, { method: "OPTIONS" }), env);
  assert.ok(preflight.headers.get("Access-Control-Allow-Headers").includes(secondary));
  assert.equal(stub.calls.length, 9, "Projection does not cause another collection/read for a given request");
  assert.ok(stub.calls.every((r) => r.method === "GET"));
}));

test("cloud scheduler admits only explicit reviewed registry activation and does not replace existing fixture cron", async () => withoutOutbound(async () => {
  for (const enabled of [false, true]) {
    const registry = binding(), waits = [], cricketCalls = [];
    const env = envFor(registry, { FOTTY_BROADCAST_REGISTRY_ENABLED: enabled ? "1" : "0",
      CRICKET_FIXTURES: { idFromName: (name) => name, get: () => ({ async fetch(request) {
        cricketCalls.push(request.method); return Response.json({ ok: true });
      } }) } });
    await worker.scheduled({}, env, { waitUntil: (promise) => waits.push(promise) });
    await Promise.all(waits);
    assert.deepEqual(cricketCalls, ["POST"]);
    assert.equal(registry.calls.length, enabled ? 1 : 0);
    if (enabled) { assert.equal(registry.calls[0].method, "POST"); assert.equal(new URL(registry.calls[0].url).pathname, "/refresh"); }
  }
}));

test("Worker DO wrapper checks current activation even for a previously scheduled alarm", async () => withoutOutbound(async () => {
  let deletions = 0, reads = 0;
  const env = envFor(binding());
  const registry = new BroadcastRegistry({ storage: { get: async () => { reads++; }, put: async () => {},
    deleteAlarm: async () => { deletions++; } } }, env);
  assert.equal(registry.enabled(), true);
  env.FOTTY_BROADCAST_REGISTRY_ENABLED = "0";
  assert.equal(registry.enabled(), false);
  await registry.alarm(); assert.equal(reads, 0); assert.ok(deletions >= 1);
  env.FOTTY_BROADCAST_REGISTRY_ENABLED = "1"; env.FOTTY_BROADCAST_REGISTRY_SOURCES = "unreviewed";
  assert.equal(registry.enabled(), false);
}));

async function admittedSportsFixture() {
  const descriptor = SPORTS_SOURCES.find((s) => s.id === "mlb"), now = new Date();
  const row = { id: "sports-fixture:mlb:fixture", sport: "baseball", competitionId: "mlb", competitionName: descriptor.competitions[0].name,
    title: "Alpha vs Beta", eventKind: "match", start: new Date(+now - 600_000).toISOString(), status: "live",
    squad: { gender: "men", ageGroup: "senior" }, participants: [{ id: "home", name: "Alpha", role: "home" }, { id: "away", name: "Beta", role: "away" }],
    source: { name: descriptor.sourceName, url: descriptor.sourceURL + "?sportId=1", observedAt: now.toISOString() } };
  const accepted = await refreshSportsSource(null, descriptor, now, async () => ({ fixtures: [row], observedAt: now.toISOString(),
    pendingFixtureCount: 0, pendingByCompetition: { mlb: 0 } }));
  return { accepted, now };
}
function fixturesEnv(sportsState, cricketFixture) {
  return { FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0", FOTTY_SPORTS_WNBA_ENABLED: "0", FOTTY_SPORTS_EFL_ENABLED: "0",
    SPORTS_FIXTURES: { idFromName: (name) => name, get: (name) => ({ async fetch() {
      return Response.json(name.endsWith(":mlb") ? sportsState : { consecutiveFailures: 1 });
    } }) },
    CRICKET_FIXTURES: { idFromName: (name) => name, get: () => ({ async fetch() { return Response.json({ schemaVersion: 1,
      sourceStatus: "verified", fixtures: cricketFixture ? [cricketFixture] : [], coverage: [{ competitionId: "icc", status: "covered" }] }); } }) } };
}

test("official mapping accepts genuine legacy covered sports receipts without manufacturing verification", async () => withoutOutbound(async () => {
  const { accepted } = await admittedSportsFixture();
  assert.equal(accepted.accepted.fixtures[0].source.verification, undefined);
  const rows = await loadBroadcastRegistryFixtures(fixturesEnv(accepted));
  assert.equal(rows.length, 1); assert.equal(rows[0].fixtureID, "sports-fixture:mlb:fixture");
  assert.deepEqual(rows[0].participants, ["Alpha", "Beta"]); assert.equal(rows[0].verified, true);
  assert.equal(rows[0].observedAt, accepted.accepted.fixtures[0].source.observedAt);
  for (const value of ["held", null, false, "unverified"]) {
    const changed = structuredClone(accepted); changed.accepted.fixtures[0].source.verification = value;
    assert.deepEqual(await loadBroadcastRegistryFixtures(fixturesEnv(changed)), [], "An explicit marker cannot fall back to legacy coverage admission");
  }
}));

test("failed sports scope cannot erase a separately verified cricket record and Test bounds remain explicit", async () => withoutOutbound(async () => {
  const { accepted, now } = await admittedSportsFixture();
  const cricket = { id: "icc:fixture", competitionId: "icc", format: "Test", status: "live",
    start: new Date(+now - 3 * 86_400_000).toISOString(), home: { name: "South Africa" }, away: { name: "Australia" },
    source: { verification: "verified", observedAt: now.toISOString() },
    context: { day: 4, matchOrdinal: 3, matchEndsAt: new Date(+now + 86_400_000).toISOString() } };
  const corrupted = structuredClone(accepted); corrupted.accepted.fixtures[0].source.verification = "held";
  const rows = await loadBroadcastRegistryFixtures(fixturesEnv(corrupted, cricket));
  assert.equal(rows.length, 1); assert.equal(rows[0].fixtureID, "cricket-fixture:icc:fixture");
  assert.equal(rows[0].day, 4); assert.equal(rows[0].matchOrdinal, 3); assert.equal(rows[0].end, cricket.context.matchEndsAt);
  assert.equal(rows[0].start, cricket.start, "Never substitute a daily date for canonical Test kickoff");
  const source = await normalizeBroadcastCollection("communitysports", { providerCode: "communitysports",
    observedAt: now.toISOString(), complete: true, scopes: [{ scope: "cricket", status: "available", complete: true }],
    broadcasts: [{ providerEventID: "daily-test-source", streamID: "daily-test-source", resourceType: "tv", scope: "cricket",
      kind: "event", sport: "cricket", title: "South Africa vs Australia", participants: rows[0].participants,
      start: new Date(+now - 5 * 60_000).toISOString(), format: "Test", matchOrdinal: 3, day: 4,
      observedAt: now.toISOString(), expiresAt: new Date(+now + 20 * 60_000).toISOString(), verification: "dated" }] }, now);
  const links = associateBroadcasts({ fixtures: rows, broadcasts: source.broadcasts, providers: source.scopes, now });
  assert.equal(links[0].state, "listed"); assert.equal(links[0].matchMethod, "test-period",
    "Actual public fixture context reaches the same association path that normal Watch consumes");
  for (const verification of ["held", null, false, "unverified"]) {
    assert.deepEqual(await loadBroadcastRegistryFixtures(fixturesEnv(corrupted, { ...cricket, source: { ...cricket.source, verification } })), []);
  }
  const noContext = { ...cricket }; delete noContext.context;
  const missing = (await loadBroadcastRegistryFixtures(fixturesEnv(corrupted, noContext)))[0];
  assert.equal(missing.day, undefined); assert.equal(missing.end, undefined); assert.equal(missing.matchOrdinal, undefined);
}));

test("approved registry configuration retains its own binding/migration and enabled scope", async () => {
  const config = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
  assert.match(config, /^FOTTY_BROADCAST_REGISTRY_ENABLED = "1"$/m);
  assert.match(config, /name = "BROADCAST_REGISTRY"\s+class_name = "BroadcastRegistry"/);
  assert.match(config, /tag = "broadcast-registry-v1"\s+new_sqlite_classes = \[ "BroadcastRegistry" \]/);
  const providers = enabledBroadcastProviders({ FOTTY_BROADCAST_REGISTRY_SOURCES: "communitysports,plaviosports,score808" });
  assert.deepEqual(providers.map((p) => [p.providerCode, p.maxRequestsPerDay]), [["score808", 96], ["communitysports", 288], ["plaviosports", 288]]);
});


test("a temporary fixture timeout preserves fresh exact broadcast discovery without renewing status or clearing conflicts", async () => withoutOutbound(async () => {
  const { accepted, now } = await admittedSportsFixture();
  const descriptor = SPORTS_SOURCES.find((s) => s.id === "mlb");
  for (const error of [new DOMException("deadline", "TimeoutError"), new DOMException("aborted", "AbortError"),
    Object.assign(new Error("Sports schedule upstream unavailable"), { fixtureHTTPStatus: 503 })]) {
    const failed = await refreshSportsSource(accepted, descriptor, new Date(+now + 60_000), async () => { throw error; });
    const rows = await loadBroadcastRegistryFixtures(fixturesEnv(failed));
    assert.equal(rows.length, 1, "An unrelated supplier can still resolve this accepted fixture");
    assert.equal(rows[0].observedAt, now.toISOString(), "A failure never renews official status evidence");
    assert.equal(rows[0].status, "live");
    const stale = structuredClone(failed); const old = new Date(+now - 31 * 60_000).toISOString();
    stale.accepted.observedAt = old; stale.accepted.fixtures[0].source.observedAt = old;
    assert.deepEqual(await loadBroadcastRegistryFixtures(fixturesEnv(stale)), [], "Original status expiry still applies");
    assert.deepEqual(await loadBroadcastRegistryFixtures(fixturesEnv({ ...failed, conflict: { content: "disputed" } })), []);
    const held = structuredClone(failed); held.accepted.fixtures[0].source.verification = "held";
    assert.deepEqual(await loadBroadcastRegistryFixtures(fixturesEnv(held)), [], "No upgrade of an explicit held record");
  }
  const invalid = await refreshSportsSource(accepted, descriptor, new Date(+now + 60_000),
    async () => { throw new Error("Sports schedule is not JSON"); });
  assert.deepEqual(await loadBroadcastRegistryFixtures(fixturesEnv(invalid)), [], "Malformed data remains a barrier");
}));
