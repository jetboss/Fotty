import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import worker, { BroadcastRegistry, enabledBroadcastProviders, broadcastRegistryEnabled,
  loadBroadcastRegistryFixtures } from "./index.js";
import { SPORTS_SOURCES } from "./sports-fixture-sources.mjs";
import { refreshSportsSource } from "./sports-fixture-registry.mjs";

const origin = "https://test.invalid", route = "/api/live/broadcasts";
function binding(reply = { schemaVersion: 1, revision: "accepted", generatedAt: new Date().toISOString(), providers: [], broadcasts: [], links: [] }) {
  const calls = [];
  return { calls, idFromName(name) { assert.equal(name, "shared-broadcast-registry-v1"); return name; },
    get() { return { async fetch(request) { calls.push(request instanceof Request ? { url: request.url, method: request.method }
      : { url: String(request), method: "GET" }); return Response.json(reply); } }; } };
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
  for (const verification of ["held", null, false, "unverified"]) {
    assert.deepEqual(await loadBroadcastRegistryFixtures(fixturesEnv(corrupted, { ...cricket, source: { ...cricket.source, verification } })), []);
  }
  const noContext = { ...cricket }; delete noContext.context;
  const missing = (await loadBroadcastRegistryFixtures(fixturesEnv(corrupted, noContext)))[0];
  assert.equal(missing.day, undefined); assert.equal(missing.end, undefined); assert.equal(missing.matchOrdinal, undefined);
}));

test("owner-approved deployment configuration is explicitly ON and gives the new registry its own binding/migration", async () => {
  const config = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
  assert.match(config, /^FOTTY_BROADCAST_REGISTRY_ENABLED = "1"$/m);
  assert.match(config, /name = "BROADCAST_REGISTRY"\s+class_name = "BroadcastRegistry"/);
  assert.match(config, /tag = "broadcast-registry-v1"\s+new_sqlite_classes = \[ "BroadcastRegistry" \]/);
  const providers = enabledBroadcastProviders({ FOTTY_BROADCAST_REGISTRY_SOURCES: "communitysports,plaviosports,score808" });
  assert.deepEqual(providers.map((p) => [p.providerCode, p.maxRequestsPerDay]), [["score808", 96], ["communitysports", 288], ["plaviosports", 288]]);
});
