import test from "node:test";
import assert from "node:assert/strict";
import { collectBroadcastSource, broadcastSourceParsers } from "./broadcast-source-adapters.mjs";
import { normalizeBroadcastCollection, associateBroadcasts } from "./broadcast-registry-policy.mjs";
import { foxCricketBroadcasts, isFoxCricketProgramme } from "./fox-cricket-programmes.mjs";
import { createRequire } from "node:module";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const now = new Date("2026-11-05T04:50:00Z");

test("CS Fox market proof comes from explicit original Australian NETWORKS metadata, never its title alone", async () => {
  const row = { id: "nuvio_sport_fox", type: "tv", name: "📺 FOX Cricket", genres: ["NETWORKS"],
    behaviorHints: { defaultVideoId: "nuvio_sport_fox" },
    description: "🏆 League: Australia\n📅 Category: NETWORKS\n⏰ Status: 24/7 Live Network" };
  for (const scope of ["networks", "cricket", "live"]) {
    const parsed = broadcastSourceParsers.csRow(row, scope, now);
    assert.equal(parsed.stationMarket, "AU");
    const normalized = await normalizeBroadcastCollection("communitysports", { providerCode: "communitysports", observedAt: now.toISOString(),
      broadcasts: [parsed], scopes: [{ scope, complete: false, status: "partial" }] }, now);
    assert.equal(normalized.broadcasts[0].stationMarket, "AU");
  }
  for (const country of ["Sports", "United Kingdom", "AU", "Australia / New Zealand"]) {
    assert.equal(broadcastSourceParsers.csRow({ ...row, description: row.description.replace("Australia", country) }, "networks", now).stationMarket, undefined);
  }
  assert.equal(broadcastSourceParsers.csRow({ ...row, name: "📺 Willow Cricket" }, "networks", now).stationMarket, undefined);
});
const fox = (title = "Live: WBBL: Strikers v Heat") => `<div class="epg-channel-logo"><img alt="501 FOX CRICKET HD" src="https://www.foxtel.com.au/content/dam/foxtel/shared/channel/FS1/FS1_290x170.png"></div>
<div id="epg-channel-events"><a class="epg-channel-event-row" href="Programme/183882957" data-scheduled-date="${Date.parse("2026-11-05T04:40:00Z")}"><div class="epg-event-description">${title}<div>Strikers v Heat</div></div></a>
<a class="epg-channel-event-row" href="Programme/183882958" data-scheduled-date="${Date.parse("2026-11-05T08:00:00Z")}"><div class="epg-event-description">Live: WBBL: Thunder v Scorchers<div>Thunder v Scorchers</div></div></a></div>`;
const willow = `<h1>TV Schedule for Willow Cricket</h1><select id="timezone_selector"><option value="Etc/UTC" selected>UTC</option></select>
<div data-callsign="Willow" data-st="2026-11-05 04:00:00" data-duration="120" data-showname="Test Cricket" data-episodetitle="South Africa vs. Australia" data-description="3rd Test, Day 4." data-live="1" data-repeat=""></div>`;
const html = (body) => new Response(body, { headers: { "content-type": "text/html" } });
const fixture = (changes = {}) => ({ fixtureID: "cricket-fixture:ca:40630", verified: true, sport: "cricket", competitionID: "wbbl",
  participants: ["Adelaide Strikers Women", "Brisbane Heat Women"], format: "T20", matchOrdinal: 10,
  status: "live", start: "2026-11-05T04:40:00.000Z", observedAt: now.toISOString(), ...changes });
async function collect({ enabled = true, cap = 8, foxReply = () => html(fox()), willowReply = () => html(willow) } = {}) {
  let reserved = 0; const calls = [];
  const result = await collectBroadcastSource("reviewedtv", { now, foxProgrammes: enabled,
    reserveRequest: async () => ++reserved <= cap, fetcher: async (url, init) => {
      assert.equal(init.redirect, "manual"); assert.equal(init.headers.Accept, "text/html");
      calls.push(url);
      if (url === "https://www.foxtel.com.au/tv-guide.html/channel/FOX-CRICKET-HD/FS1/2026/11/05") return foxReply();
      assert.equal(url, "https://www.tvpassport.com/tv-listings/stations/willow-cricket/15964/2026-11-05");
      return willowReply();
    } });
  return { result, calls, reserved, normalized: await normalizeBroadcastCollection("reviewedtv", result, now) };
}

test("staged Fox collection requires explicit activation and uses the existing reservation ledger", async () => {
  const disabled = await collect({ enabled: false });
  assert.equal(disabled.calls.length, 1); assert.equal(disabled.result.broadcasts.length, 1);
  const both = await collect();
  assert.equal(both.calls.length, 2); assert.equal(both.reserved, 2);
  assert.equal(both.result.broadcasts.length, 2); assert.equal(both.normalized.broadcasts.length, 2);
  assert.deepEqual(both.result.scopes, [{ scope: "cricket", complete: true, status: "available" }]);
  assert.ok(!JSON.stringify(both.result).includes("https://"), "Programme evidence must not contain a fabricated media location");
});

test("deployed Worker runtime collects Fox and Willow while rejecting every Fox redirect", { timeout: 20000 }, async (t) => {
  const directory = dirname(fileURLToPath(import.meta.url)), require = createRequire(import.meta.url);
  const deploymentRequire = createRequire(require.resolve("wrangler/package.json"));
  const { build } = deploymentRequire("esbuild");
  const { Miniflare, convertV4MiniflareOptions, Log, LogLevel } = deploymentRequire("miniflare");
  const config = await readFile(join(directory, "../wrangler.toml"), "utf8");
  const compatibilityDate = config.match(/^compatibility_date\s*=\s*"([\d-]+)"/m)?.[1];
  const flags = config.match(/^compatibility_flags\s*=\s*\[([^\]]*)\]/m)?.[1];
  assert.ok(compatibilityDate); assert.notEqual(flags, undefined);
  const compatibilityFlags = [...flags.matchAll(/"([a-z0-9_]+)"/g)].map(m => m[1]);
  const bundle = await build({ stdin: { contents: `
    import {collectBroadcastSource} from './broadcast-source-adapters.mjs';
    import {normalizeBroadcastCollection,associateBroadcasts} from './broadcast-registry-policy.mjs';
    export default {async fetch() {
      const now=new Date('2026-11-05T04:50:00Z'); let reservations=0;
      const raw=await collectBroadcastSource('reviewedtv',{now,foxProgrammes:true,reserveRequest:async()=>++reservations<=3});
      const normalized=await normalizeBroadcastCollection('reviewedtv',raw,now);
      return Response.json({reservations,...normalized,links:associateBroadcasts({now,broadcasts:normalized.broadcasts,
        providers:normalized.scopes,fixtures:[${JSON.stringify(fixture())}]})});
    }};`, resolveDir: directory }, bundle: true, write: false, format: "esm", platform: "browser" });
  const owned = await mkdtemp(join(tmpdir(), "fotty-fox-runtime-"));
  let runtime, status = 200, requests = [];
  t.after(async () => { try { await runtime?.dispose(); } finally { await rm(owned, { recursive: true, force: true }); } });
  const options = { modules: true, script: bundle.outputFiles[0].text, compatibilityDate, compatibilityFlags,
    log: new Log(LogLevel.NONE), cf: false, resourcePersistencePath: join(owned, "state"),
    isolatedResourcePersistencePath: join(owned, "isolated"), resourceTmpPath: join(owned, "runtime"),
    outboundService: async request => {
      const url = new URL(request.url); requests.push(url.hostname);
      if (url.hostname === "www.tvpassport.com") return html(willow);
      assert.equal(url.hostname, "www.foxtel.com.au");
      assert.equal(url.pathname, "/tv-guide.html/channel/FOX-CRICKET-HD/FS1/2026/11/05");
      return status === 200 ? html(fox()) : new Response(null, { status, headers: { Location: "https://unreviewed.invalid/redirect" } });
    } };
  runtime = new Miniflare(typeof convertV4MiniflareOptions === "function" ? convertV4MiniflareOptions(options) : options);
  const accepted = await (await runtime.dispatchFetch("http://localhost/")).json();
  assert.equal(accepted.broadcasts.length, 2); assert.equal(accepted.reservations, 2);
  assert.equal(accepted.links.length, 1); assert.equal(accepted.links[0].state, "listed");
  for (const redirect of [301, 302, 303, 307, 308]) {
    status = redirect; requests = [];
    const rejected = await (await runtime.dispatchFetch("http://localhost/")).json();
    assert.deepEqual(requests, ["www.tvpassport.com", "www.foxtel.com.au"]);
    assert.equal(rejected.broadcasts.length, 1); assert.equal(rejected.broadcasts[0].channelID, "cricket-channel:willow");
    assert.equal(rejected.scopes[0].status, "partial"); assert.equal(rejected.links.length, 0);
  }
});

test("a verified timezone hint fits Willow, Fox and ESPN into three reads without renewing cached programmes", async () => {
  const edge = new Date("2026-11-05T02:00:00Z");
  const markup = willow.replace("Etc/UTC", "America/Port_of_Spain").replace("2026-11-05 04:00:00", "2026-11-04 21:00:00");
  const run = async (programmeContext) => {
    const paths = []; let reservations = 0;
    const result = await collectBroadcastSource("reviewedtv", { now: edge, foxProgrammes: true, programmeContext,
      fixtures: [{ sport: "football", competitionID: "premier-league", verified: true }],
      reserveRequest: async () => ++reservations <= 3, fetcher: async (url) => {
        const u = new URL(url); paths.push({ host: u.hostname, path: u.pathname });
        if (u.hostname === "www.tvpassport.com") return html(markup);
        if (u.hostname === "www.foxtel.com.au") return html(fox());
        return new Response(null, { status: 503 }); // Independent ESPN failure still spends its existing slot.
      } });
    return { paths, reservations, result };
  };
  const cold = await run();
  assert.equal(cold.reservations, 3); assert.equal(cold.paths.length, 3);
  assert.ok(!cold.paths.some((p) => p.host === "www.foxtel.com.au"));
  assert.equal(cold.result.programmeContext.willowGuideTimeZone, "America/Port_of_Spain");
  assert.equal(cold.result.scopes[0].status, "partial");
  const warm = await run(cold.result.programmeContext);
  assert.equal(warm.reservations, 3); assert.equal(warm.paths.length, 3);
  assert.equal(warm.paths.filter((p) => p.host === "www.tvpassport.com").length, 1);
  assert.ok(warm.paths[0].path.endsWith("2026-11-04")); assert.ok(warm.paths.some((p) => p.host === "www.foxtel.com.au"));
  for (const context of [{ ...cold.result.programmeContext, observedAt: "2026-11-04T00:00:00Z" },
    { ...cold.result.programmeContext, willowGuideTimeZone: "Europe/London" },
    { ...cold.result.programmeContext, willowGuideTimeZone: "Invalid/Timezone" }]) {
    const checked = await run(context);
    assert.equal(checked.reservations, 3);
    assert.equal(checked.paths.filter((p) => p.host === "www.tvpassport.com").length, 2);
    assert.equal(checked.result.programmeContext.willowGuideTimeZone, "America/Port_of_Spain", "The freshly fetched selector outranks the hint");
  }
});

test("Fox and Willow failures are isolated without converting partial coverage into exhaustive absence", async () => {
  const failedFox = await collect({ foxReply: () => new Response(null, { status: 503 }) });
  assert.equal(failedFox.normalized.broadcasts.length, 1);
  assert.equal(failedFox.normalized.broadcasts[0].channelID, "cricket-channel:willow");
  assert.equal(failedFox.result.scopes[0].status, "partial"); assert.equal(failedFox.result.scopes[0].complete, false);
  const failedWillow = await collect({ willowReply: () => new Response(null, { status: 503 }) });
  assert.equal(failedWillow.normalized.broadcasts.length, 1);
  assert.equal(failedWillow.normalized.broadcasts[0].channelID, "cricket-channel:fox-cricket");
  assert.equal(failedWillow.result.scopes[0].status, "partial");
  const bothFailed = await collect({ foxReply: () => new Response(null, { status: 503 }), willowReply: () => new Response(null, { status: 503 }) });
  assert.equal(bothFailed.result.scopes[0].status, "failed"); assert.equal(bothFailed.result.broadcasts.length, 0);
  const capped = await collect({ cap: 1 });
  assert.equal(capped.calls.length, 1); assert.equal(capped.result.scopes[0].failure, "budget-exhausted");
  assert.equal(capped.normalized.broadcasts[0].channelID, "cricket-channel:willow");
});

test("malformed, oversized and redirected Fox responses cannot remove healthy Willow programmes", async () => {
  for (const foxReply of [() => html("wrong channel"), () => html("x".repeat(524289)),
    () => new Response(null, { status: 302, headers: { location: "https://elsewhere.invalid/" } })]) {
    const r = await collect({ foxReply });
    assert.equal(r.calls.length, 2); assert.equal(r.result.scopes[0].status, "partial");
    assert.equal(r.normalized.broadcasts.length, 1); assert.equal(r.normalized.broadcasts[0].channelID, "cricket-channel:willow");
  }
});

test("only current explicit live Fox programmes produce short-lived programme references", async () => {
  const rows = await foxCricketBroadcasts(fox(), { now });
  assert.equal(rows.length, 1); assert.equal(isFoxCricketProgramme(rows[0], "reviewedtv"), true);
  assert.equal(rows[0].expiresAt, "2026-11-05T05:00:00.000Z");
  assert.equal(rows[0].matchOrdinal, undefined); assert.equal(rows[0].status, undefined);
  assert.equal((await foxCricketBroadcasts(fox("WBBL: Strikers v Heat"), { now })).length, 0);
  assert.equal((await foxCricketBroadcasts(fox(), { now: new Date("2026-11-05T04:39:59Z") })).length, 0);
  const end = await foxCricketBroadcasts(fox(), { now: new Date("2026-11-05T07:59:00Z") });
  assert.equal(end[0].expiresAt, "2026-11-05T08:00:00.000Z");
  assert.equal((await foxCricketBroadcasts(fox(), { now: new Date("2026-11-05T08:00:00Z") })).length, 0, "Unknown final-programme end supplies no current authority");
});

test("reviewed Fox matching makes no entitlement claim and explicit access restrictions still override it", async () => {
  const { normalized: source } = await collect({ willowReply: () => new Response(null, { status: 503 }) });
  const f = fixture(), parameters = { fixtures: [f], broadcasts: source.broadcasts, providers: source.scopes, now };
  const matched = associateBroadcasts(parameters)[0];
  assert.equal(matched.state, "listed"); assert.equal(matched.access, undefined);
  // Explicit policies remain independent of matching and override its default.
  const programmePolicies = new Map([[JSON.stringify(["cricket-channel:fox-cricket", f.fixtureID]), {
    entitlement: "cleared", use: "event-playback", territory: "worldwide", reviewID: "test-only-policy",
    expiresAt: "2026-11-05T05:00:00.000Z",
  }]]);
  const accepted = associateBroadcasts({ ...parameters, programmePolicies })[0];
  assert.equal(accepted.state, "listed"); assert.equal(accepted.matchMethod, "programme");
  assert.equal(accepted.fixtureFingerprint.matchOrdinal, 10); assert.equal(source.broadcasts[0].matchOrdinal, undefined);
  for (const changes of [{ status: "finished" }, { format: "ODI" }, { squad: { gender: "men", ageGroup: "senior" } },
    { observedAt: "2026-11-05T04:00:00Z" }, { competitionID: "bbl" }]) {
    assert.ok(associateBroadcasts({ ...parameters, fixtures: [fixture(changes)], programmePolicies }).every((l) => l.state !== "listed"));
  }
  for (const access of [{ entitlement: "unknown", use: "unknown", territory: "unknown" },
    { entitlement: "denied", use: "event-playback", territory: "worldwide" }]) {
    const restricted = associateBroadcasts({ ...parameters, programmePolicies: new Map([[JSON.stringify(["cricket-channel:fox-cricket", f.fixtureID]), access]]) });
    assert.ok(restricted.every((l) => l.state !== "listed"));
  }
  const ambiguous = associateBroadcasts({ ...parameters, fixtures: [f, fixture({ fixtureID: "cricket-fixture:ca:40632" })], programmePolicies });
  assert.ok(ambiguous.every((l) => l.state !== "listed"));
});
