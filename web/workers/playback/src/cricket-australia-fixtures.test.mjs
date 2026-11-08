import test from "node:test";
import assert from "node:assert/strict";
import { caCricketURL, normalizeCACricket, collectCACricket, refreshCACricket, appendCACricket } from "./cricket-australia-fixtures.mjs";
import { loadBroadcastRegistryFixtures } from "./index.js";
import { associateBroadcasts, normalizeBroadcastCollection } from "./broadcast-registry-policy.mjs";
import { createRequire } from "node:module";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const now = new Date("2026-11-04T10:00:00Z");
const headers = () => new Headers({ date: now.toUTCString(), age: "0" });
const row = (changes = {}) => ({ id: 40629, name: "Match 9", startDateTime: "2026-11-04T08:10:00Z",
  gameTypeId: 41, isLive: true, isCompleted: false, isInProgress: true, isWomensMatch: true,
  competition: { id: 4687, name: "Weber WBBL|12" },
  homeTeam: { id: 96, name: "Hobart Hurricanes Women" }, awayTeam: { id: 101, name: "Melbourne Renegades Women" }, ...changes });
const parse = (rows = [row()], h = headers()) => normalizeCACricket({ fixtures: rows, responseError: null }, h, now);

test("CA request is one reviewed competition, bounded dates and count; season expiry requires review", () => {
  const url = caCricketURL(now);
  assert.equal(url.origin, "https://apiv2.cricket.com.au");
  assert.equal(url.searchParams.get("competitionId"), "4687");
  assert.equal(url.searchParams.get("startDateTime"), "2026-11-03");
  assert.equal(url.searchParams.get("endDateTime"), "2026-11-12");
  assert.equal(url.searchParams.get("limit"), "50");
  assert.throws(() => caCricketURL(new Date("2027-01-01Z")), /season-review-required/);
});
test("WBBL retains official women identity, explicit match number, UTC start and actual status", () => {
  const f = parse().fixtures[0];
  assert.equal(f.id, "ca:40629"); assert.equal(f.competitionId, "wbbl");
  assert.equal(f.home.name, "Hobart Hurricanes Women"); assert.equal(f.matchOrdinal, 9);
  assert.equal(f.status, "live"); assert.equal(f.start, "2026-11-04T08:10:00.000Z");
  assert.equal(parse([row({ isLive: false, isInProgress: false, isCompleted: true })]).fixtures[0].status, "finished");
  assert.equal(parse([row({ isLive: false, isInProgress: false })]).fixtures[0].status, "unknown", "Kickoff is not live authority");
  assert.equal(parse([row({ name: "Final" })]).fixtures[0].matchOrdinal, undefined);
});
test("CA malformed identity, time, scope and contradictory status cannot become fixture facts", () => {
  for (const changes of [{ isWomensMatch: false }, { gameTypeId: 1 }, { competition: { id: 999, name: "WBBL" } },
    { isCompleted: true }, { isLive: "true" }, { name: "Match 09" }, { startDateTime: "2026-11-04T08:10:00" },
    { startDateTime: "2026-11-31T08:10:00Z" }, { homeTeam: { id: 96, name: "Hobart Hurricanes" } },
    { awayTeam: { id: 96, name: "Melbourne Renegades Women" } }, { startDateTime: "2026-11-05T08:10:00Z" }])
    assert.throws(() => parse([row(changes)]), undefined, JSON.stringify(changes));
  assert.throws(() => parse([row(), row()]), /invalid-fixture/);
  assert.throws(() => parse(Array(50).fill(row())), /source-incomplete/);
});
test("cached API response is not a renewed source receipt", () => {
  for (const h of [new Headers(), new Headers({ date: now.toUTCString(), age: "301" }),
    new Headers({ date: now.toUTCString(), age: "bad" }), new Headers({ date: "Wed, 04 Nov 2026 09:00:00 GMT" })])
    assert.throws(() => parse([row()], h), /publisher-stale/);
});
test("collector uses fixed HTTPS, refuses redirects, and bounds payloads", async () => {
  let calls = 0;
  const value = await collectCACricket(now, async (url, options) => {
    calls++; assert.equal(url.origin, "https://apiv2.cricket.com.au"); assert.equal(options.redirect, "manual");
    assert.ok(options.signal); return Response.json({ fixtures: [row()] }, { headers: headers() });
  });
  assert.equal(calls, 1); assert.equal(value.fixtures.length, 1);
  await assert.rejects(collectCACricket(now, async () => new Response("no", { status: 503 })), /upstream-unavailable/);
});

test("deployed Worker runtime collects WBBL and rejects redirects without following them", { timeout: 20_000 }, async (t) => {
  const directory = dirname(fileURLToPath(import.meta.url));
  const require = createRequire(import.meta.url);
  const deploymentRequire = createRequire(require.resolve("wrangler/package.json"));
  const { build } = deploymentRequire("esbuild");
  const { Miniflare, convertV4MiniflareOptions, Log, LogLevel } = deploymentRequire("miniflare");
  const config = await readFile(join(directory, "../wrangler.toml"), "utf8");
  const compatibilityDate = config.match(/^compatibility_date\s*=\s*"([\d-]+)"/m)?.[1];
  const flagText = config.match(/^compatibility_flags\s*=\s*\[([^\]]*)\]/m)?.[1];
  assert.ok(compatibilityDate); assert.notEqual(flagText, undefined);
  const compatibilityFlags = [...flagText.matchAll(/"([a-z0-9_]+)"/g)].map((m) => m[1]);
  const bundle = await build({ stdin: { contents: `
    import {refreshCACricket} from './cricket-australia-fixtures.mjs';
    export default {async fetch() {return Response.json(await refreshCACricket(null, new Date('2026-11-04T10:00:00Z')));}};
  `, resolveDir: directory }, bundle: true, write: false, format: "esm", platform: "browser" });
  const owned = await mkdtemp(join(tmpdir(), "fotty-ca-runtime-"));
  let runtime, status = 200, requests = 0;
  t.after(async () => { try { await runtime?.dispose(); } finally { await rm(owned, { recursive: true, force: true }); } });
  const options = { modules: true, script: bundle.outputFiles[0].text, compatibilityDate, compatibilityFlags,
    log: new Log(LogLevel.NONE), cf: false,
    resourcePersistencePath: join(owned, "state"), isolatedResourcePersistencePath: join(owned, "isolated"), resourceTmpPath: join(owned, "runtime"),
    outboundService: async (request) => {
      requests++;
      assert.equal(new URL(request.url).origin, "https://apiv2.cricket.com.au");
      assert.equal(new URL(request.url).pathname, "/web/fixtures/yearfilter");
      return status === 200 ? Response.json({ fixtures: [row()] }, { headers: headers() })
        : new Response(null, { status, headers: { Location: "https://unreviewed.invalid/redirect" } });
    } };
  runtime = new Miniflare(typeof convertV4MiniflareOptions === "function" ? convertV4MiniflareOptions(options) : options);
  const accepted = await (await runtime.dispatchFetch("http://localhost/")).json();
  assert.equal(accepted.status, "covered");
  assert.equal(accepted.fixtures[0].id, "ca:40629");
  assert.equal(requests, 1, "Real Worker fetch must reach the reviewed origin exactly once");
  for (const redirect of [301, 302, 303, 307, 308]) {
    status = redirect; requests = 0;
    const rejected = await (await runtime.dispatchFetch("http://localhost/")).json();
    assert.equal(rejected.status, "unavailable");
    assert.equal(rejected.failure, "upstream-unavailable");
    assert.equal(requests, 1, "Redirect target must never be requested");
  }
});
test("failed domestic refresh preserves original facts and receipt without lending live authority", async () => {
  const first = await refreshCACricket(null, now, async () => parse());
  const later = new Date(+now + 6 * 60_000);
  const failed = await refreshCACricket(first, later, async () => { throw Error("private url must not escape"); });
  assert.equal(failed.status, "unavailable"); assert.deepEqual(failed.fixtures, first.fixtures);
  assert.equal(failed.observedAt, first.observedAt); assert.equal(failed.failure, "collection-failed");
  assert.equal(await refreshCACricket(first, new Date(+now + 1000), () => assert.fail("backoff")), first);
});
test("domestic rollover, missing active row, changed teams and terminal rollback retain accepted cohort", async () => {
  const first = await refreshCACricket(null, now, async () => parse());
  const later = new Date(+now + 6 * 60_000);
  for (const candidate of [{ observedAt: later.toISOString(), fixtures: [] },
    { ...parse(), fixtures: [{ ...first.fixtures[0], home: { id: "ca:1", name: "Other Women" } }] },
    { ...parse(), observedAt: "2026-11-04T09:00:00Z" }]) {
    const next = await refreshCACricket(first, later, async () => candidate);
    assert.equal(next.status, "unavailable"); assert.deepEqual(next.fixtures, first.fixtures);
  }
  const finished = { ...first, fixtures: [{ ...first.fixtures[0], status: "finished" }] };
  assert.equal((await refreshCACricket(finished, later, async () => parse())).failure, "status-regressed");
  assert.equal((await refreshCACricket(first, new Date("2027-01-01Z"))).failure, "season-review-required");
});
test("projection isolates failures and never renews the base or domestic cohort", async () => {
  const ca = await refreshCACricket(null, now, async () => parse());
  const base = { checkedAt: now.toISOString(), revision: "base", sourceStatus: "verified", fixtures: [],
    coverage: [{ competitionId: "icc", status: "covered", checkedAt: now.toISOString(), fixtureCount: 0 }],
    sync: { consecutiveFailures: 0, lastAttemptAt: now.toISOString() } };
  const copy = structuredClone(base);
  assert.equal(appendCACricket(base, ca).sourceStatus, "verified");
  assert.deepEqual(base, copy);
  const failed = { ...ca, status: "unavailable", failure: "upstream-unavailable" };
  const p = appendCACricket(base, failed);
  assert.equal(p.coverage[0].status, "covered"); assert.equal(p.coverage[1].status, "unavailable");
  assert.equal(p.fixtures[0].source.observedAt, ca.observedAt);
  assert.equal(appendCACricket({ ...base, sourceStatus: "last-known-good" }, ca).coverage[0].status, "unavailable");
});

test("WBBL survives an unavailable international catalog and reaches the real Willow association path", async () => {
  const ca = await refreshCACricket(null, now, async () => parse());
  const base = { schemaVersion: 1, complete: true, checkedAt: now.toISOString(), revision: "base",
    sourceStatus: "unavailable", fixtures: [], coverage: [{ competitionId: "icc", status: "unavailable",
      checkedAt: "1970-01-01T00:00:00Z", fixtureCount: 0 }], sync: { consecutiveFailures: 1 } };
  const snapshot = appendCACricket(base, ca);
  const env = { CRICKET_FIXTURES: { idFromName: () => "test", get: () => ({ fetch: async () => Response.json(snapshot) }) } };
  const { fixtures, siblings } = await loadBroadcastRegistryFixtures(env, { includeAmbiguity: true });
  assert.equal(fixtures.length, 1);
  assert.equal(fixtures[0].fixtureID, "cricket-fixture:ca:40629");
  const providerCode = "reviewedtv";
  const collection = await normalizeBroadcastCollection(providerCode, { providerCode, complete: true,
    observedAt: now.toISOString(), scopes: [{ scope: "cricket", status: "available", complete: true }],
    broadcasts: [{ providerEventID: "reviewed-tv:programme:" + "a".repeat(64), streamID: "reviewed-tv:willow-main",
      resourceType: "tv", scope: "cricket", kind: "programme", sport: "cricket", title: "Hobart Hurricanes vs. Melbourne Renegades",
      participants: ["Hobart Hurricanes Women", "Melbourne Renegades Women"], competitionID: "wbbl",
      squad: { gender: "women", ageGroup: "senior" }, format: "T20", channelID: "cricket-channel:willow",
      start: "2026-11-04T09:30:00Z", end: "2026-11-04T11:00:00Z", verification: "dated", issues: [],
      observedAt: now.toISOString(), expiresAt: "2026-11-04T10:09:00Z" }] }, now);
  const links = associateBroadcasts({ fixtures, ambiguityFixtures: siblings, broadcasts: collection.broadcasts,
    providers: collection.scopes, now });
  assert.equal(links.filter(l => l.state === "listed").length, 1);
  assert.equal(links[0].fixtureFingerprint.matchOrdinal, 9);
  snapshot.fixtures[0].status = "finished";
  const ended = await loadBroadcastRegistryFixtures(env, { includeAmbiguity: true });
  assert.equal(ended.fixtures.length, 0);
  assert.equal(ended.siblings.length, 1, "Terminal occurrences remain ambiguity evidence, not lookup demand");
});

test("expired domestic rows leave the public projection without erasing accepted storage", async () => {
  const ca = await refreshCACricket(null, now, async () => parse());
  const later = { ...ca, lastAttemptAt: "2026-12-06T10:00:00Z", status: "unavailable" };
  const before = structuredClone(later);
  const base = { checkedAt: later.lastAttemptAt, sourceStatus: "verified", fixtures: [], coverage: [], sync: {} };
  const result = appendCACricket(base, later);
  assert.equal(result.fixtures.length, 0);
  assert.equal(result.coverage[0].fixtureCount, 0);
  assert.equal(result.coverage[0].checkedAt, ca.observedAt);
  assert.deepEqual(later, before);
});
