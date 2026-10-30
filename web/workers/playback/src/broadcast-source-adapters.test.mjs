import test from "node:test";
import assert from "node:assert/strict";
import { BROADCAST_SOURCE_CODES, collectBroadcastSource as collect, broadcastSourceParsers as parse } from "./broadcast-source-adapters.mjs";
import { normalizeBroadcastCollection } from "./broadcast-registry-policy.mjs";

const now = new Date("2026-10-30T12:00:00Z");
const json = (v, status = 200) => new Response(JSON.stringify(v), { status, headers: { "content-type": "application/json" } });
const html = (v) => new Response(v, { headers: { "content-type": "text/html" } });
const catalog = (id, extra) => ({ id, type: "tv", ...(extra ? { extra } : {}) });
const csCatalogs = ["live", "networks", "football", "cricket", "basketball", "baseball", "hockey", "american_football", "rugby", "mma", "motorsport", "golf", "tennis", "darts", "college", "other"];
const manifests = {
  communitysports: { id: "community.nuvio.live-sports", version: "3.1.3", resources: ["catalog", "meta", "stream"], catalogs: csCatalogs.map((s) => catalog("nuvio_sports_" + s)) },
  plaviosports: { id: "community.plaviohd", version: "1.9.110", types: ["tv"], resources: ["catalog", "meta", { name: "stream", types: ["tv"], idPrefixes: ["plaviohdtv-"] }], catalogs: ["plaviohd-football", "plaviohd-cricket", "plaviohd-live-sports"].map((s) => catalog(s)) },
  cncsports: { id: "com.cncverse.stremiobridge", version: "1.0.0", types: ["tv"], resources: ["catalog", "meta", "stream"], catalogs: [catalog("cnc_LivXowLiveEvents_tv")] },
  flixstreams: { id: "org.flixstreams.free", version: "1.0.0", types: ["tv"], resources: ["catalog", "meta", "stream"], catalogs: [catalog("essential-live-events", [{ name: "skip" }, { name: "genre", options: ["soccer", "cricket"] }])] },
  streamvix: { id: "org.prisonmike.streamvix", version: "1.0.0", types: ["tv"], resources: ["catalog", "meta", "stream"], catalogs: [catalog("streamvix_eventi", [{ name: "genre", isRequired: true, options: ["Premier League", "Coppe"] }])] },
};
const cs = (changes = {}) => ({ id: "nuvio_sport_sa_aus", type: "tv", name: "🔴 LIVE: South Africa vs Australia", released: "2026-10-30T08:00:00.000Z", genres: ["CRICKET"], cast: ["South Africa", "Australia"], behaviorHints: { defaultVideoId: "nuvio_sport_sa_aus" }, description: "🏆 League: 3rd Test day-3\n📅 Category: CRICKET\n⏰ Status: 🔴 LIVE NOW", ...changes });
function harness(code, response, limit = 8, { allowMeta = false, manifestOverride } = {}) {
  const calls = []; let reserved = 0;
  return { calls, count: () => reserved, run: (options = {}) => collect(code, { now,
    reserveRequest: async () => ++reserved <= limit,
    fetcher: async (url, init) => {
      calls.push({ url, init });
      assert.equal(init.redirect, "manual"); assert.equal(new URL(url).protocol, "https:");
      assert.ok(!new URL(url).pathname.includes("/stream/"), "No descriptors");
      if (!allowMeta) assert.ok(!new URL(url).pathname.includes("/meta/"), "No unrequested meta fan-out");
      if (new URL(url).pathname === "/manifest.json") return json(manifestOverride ?? manifests[code]);
      return await response(url, init);
    }, ...options }) };
}

test("seven source families and the fixed reviewed programme provider are registered; unknown input never fetches", async () => {
  assert.deepEqual(BROADCAST_SOURCE_CODES, ["streamex", "score808", "communitysports", "plaviosports", "cncsports", "flixstreams", "streamvix", "reviewedtv"]);
  await assert.rejects(collect("unreviewed", { fetcher: () => assert.fail("No network") }), /invalid-collection/u);
});

const reviewedProgramme = ({ localStart = "2026-10-30 07:00:00", timeZone = "America/Port_of_Spain", episode = "South Africa vs. Australia" } = {}) =>
  `<h1>TV Schedule for Willow Cricket</h1><select id="timezone_selector"><option value="${timeZone}" selected>Atlantic</option></select>`
  + `<div data-callsign="Willow" data-st="${localStart}" data-duration="120" data-showname="Test Cricket" data-episodetitle="${episode}" data-description="3rd Test, Day 4." data-live="1" data-repeat=""></div>`;
test("reviewed programme collector reads only the fixed dated main-Willow metadata page and preserves short programme expiry", async () => {
  const h = harness("reviewedtv", async () => html(reviewedProgramme()));
  const result = await h.run();
  assert.equal(h.calls.length, 1); assert.equal(h.count(), 1);
  assert.equal(h.calls[0].url, "https://www.tvpassport.com/tv-listings/stations/willow-cricket/15964/2026-10-30");
  assert.equal(h.calls[0].init.headers.Accept, "text/html");
  assert.deepEqual(result.scopes, [{ scope: "cricket", complete: true, status: "available" }]);
  assert.equal(result.broadcasts.length, 1);
  const row = result.broadcasts[0];
  assert.equal(row.kind, "programme"); assert.equal(row.streamID, "reviewed-tv:willow-main");
  assert.equal(row.channelID, "cricket-channel:willow"); assert.equal(row.format, "Test"); assert.equal(row.matchOrdinal, 3); assert.equal(row.day, 4);
  assert.equal(row.start, "2026-10-30T11:00:00.000Z"); assert.equal(row.end, "2026-10-30T13:00:00.000Z");
  assert.equal(row.expiresAt, "2026-10-30T12:10:00.000Z");
  assert.ok(!JSON.stringify(result).includes("https://"), "No playlist/media/guide location becomes a delivery");
  const normalized = await normalizeBroadcastCollection("reviewedtv", result, now);
  assert.equal(normalized.broadcasts.length, 1);
});
test("reviewed programme UTC-date edge uses only the actual selected zone and at most one corrected fixed-date read", async () => {
  const edge = new Date("2026-10-30T02:00:00.000Z"), markup = reviewedProgramme({ localStart: "2026-10-29 21:00:00" });
  const h = harness("reviewedtv", async () => html(markup));
  const result = await h.run({ now: edge });
  assert.equal(h.calls.length, 2); assert.equal(h.count(), 2);
  assert.deepEqual(h.calls.map((r) => r.url), ["https://www.tvpassport.com/tv-listings/stations/willow-cricket/15964/2026-10-30",
    "https://www.tvpassport.com/tv-listings/stations/willow-cricket/15964/2026-10-29"]);
  assert.equal(result.broadcasts.length, 1, "Identical cross-date programme facts are one observation");
  assert.equal(result.broadcasts[0].start, "2026-10-30T01:00:00.000Z");
  assert.equal(result.broadcasts[0].expiresAt, "2026-10-30T02:10:00.000Z");
  const conflict = harness("reviewedtv", async (url) => html(reviewedProgramme({ localStart: "2026-10-29 21:00:00",
    episode: url.endsWith("2026-10-29") ? "India vs. Australia" : "South Africa vs. Australia" })));
  const refused = await conflict.run({ now: edge });
  assert.equal(refused.broadcasts.length, 0); assert.equal(refused.scopes[0].failure, "catalog-conflict");
});
test("reviewed programme malformed HTML, unverified timezone and redirects fail only their cricket metadata cohort", async () => {
  for (const reply of [() => html("<div>No verified station/timezone</div>"), () => html(reviewedProgramme({ timeZone: "Unverified/Timezone" })),
    () => new Response(null, { status: 302, headers: { location: "https://unreviewed.invalid/" } })]) {
    const bad = harness("reviewedtv", async () => reply());
    const result = await bad.run();
    assert.equal(bad.calls.length, 1); assert.equal(result.broadcasts.length, 0);
    assert.equal(result.scopes.length, 1); assert.equal(result.scopes[0].scope, "cricket"); assert.equal(result.scopes[0].status, "failed");
  }
});

test("CS retains unmatched events, actual Test qualifiers and standalone channels within eight actual reads", async () => {
  const h = harness("communitysports", async (url) => {
    const p = new URL(url).pathname;
    return json({ metas: p.includes("_cricket.") ? [cs()] : p.includes("_networks.") ? [cs({ id: "nuvio_sport_willow", name: "📺 Willow Cricket", genres: ["NETWORKS"], released: undefined, cast: undefined, behaviorHints: { defaultVideoId: "nuvio_sport_willow" } })]
      : p.includes("_football.") ? [cs({ id: "nuvio_sport_unmatched", name: "Unmatched Home vs Unmatched Away", genres: ["FOOTBALL"], cast: ["Unmatched Home", "Unmatched Away"], behaviorHints: { defaultVideoId: "nuvio_sport_unmatched" } })] : [] });
  });
  const result = await h.run();
  assert.equal(h.calls.length, 8); assert.equal(h.count(), 8); assert.equal(result.cursor, 3);
  const cricket = result.broadcasts.find((r) => r.sport === "cricket" && r.kind === "event");
  assert.equal(cricket.format, "Test"); assert.equal(cricket.matchOrdinal, 3); assert.equal(cricket.day, 3);
  assert.equal(cricket.start, "2026-10-30T08:00:00.000Z");
  assert.ok(result.broadcasts.some((r) => r.title === "Unmatched Home vs Unmatched Away"));
  assert.equal(result.broadcasts.find((r) => r.kind === "channel").start, undefined);
  assert.equal(result.broadcasts.find((r) => r.kind === "channel").channelID, "cricket-channel:willow");
  assert.equal(result.scopes.find((s) => s.scope === "cricket").complete, false, "No invented absence from truncated catalog");
  assert.ok(!JSON.stringify(result).includes("https://"));
  const normalized = await normalizeBroadcastCollection("communitysports", result, now);
  assert.equal(normalized.broadcasts.find((r) => r.kind === "channel").verification, "undated");
});

test("CS rotates only the finite reviewed sports and preserves an incomplete transport cohort", async () => {
  const h = harness("communitysports", async (url) => new URL(url).pathname.includes("_baseball.") ? json({}, 503) : json({ metas: [] }));
  const result = await h.run({ cursor: 3 });
  assert.ok(h.calls.some((r) => r.url.includes("_american_football.json")));
  assert.ok(!h.calls.some((r) => r.url.includes("_basketball.json")));
  assert.ok(result.scopes.every((r) => ["partial", "failed", "unsupported"].includes(r.status)));
});

test("budget failure prevents HTTP rather than fabricating an empty catalog", async () => {
  const h = harness("communitysports", async () => json({ metas: [] }), 3);
  const result = await h.run();
  assert.equal(h.calls.length, 3);
  assert.ok(result.scopes.some((s) => s.failure === "budget-exhausted"));
  assert.ok(!result.scopes.some((s) => s.status === "empty"));
});

test("CS malformed same-ID sibling is retained as conflict evidence", () => {
  const good = parse.csRow(cs(), "cricket", now), wrong = parse.csRow(cs({ name: undefined, type: "movie" }), "cricket", now);
  assert.equal(good.providerEventID, wrong.providerEventID);
  assert.equal(wrong.verification, "conflicting"); assert.ok(wrong.issues.includes("identity-conflict"));
  assert.equal(parse.csRow(cs({ id: "https://private.invalid/token" }), "cricket", now), null);
});
test("CS pending-clock decoration preserves a corroborated pair/date while real cast and squad conflicts remain vetoes", async () => {
  for (const prefix of ["⏱ ", "⏱️ "]) {
    const raw = cs({ id: "nuvio_sport_vegas_nj", name: prefix + "Vegas Golden Knights vs New Jersey Devils",
      genres: ["HOCKEY"], cast: ["New Jersey Devils", "Vegas Golden Knights"], released: "2026-10-30T22:00:00.000Z" });
    const row = parse.csRow(raw, "hockey", now);
    assert.equal(row.verification, "dated"); assert.deepEqual(row.issues, []);
    assert.equal(row.start, "2026-10-30T22:00:00.000Z");
    assert.deepEqual(row.participants, ["New Jersey Devils", "Vegas Golden Knights"]);
    const normalized = await normalizeBroadcastCollection("communitysports", { providerCode: "communitysports",
      observedAt: now.toISOString(), complete: false, scopes: [{ scope: "hockey", status: "partial", complete: false }], broadcasts: [row] }, now);
    assert.equal(normalized.broadcasts[0].verification, "dated");
    const differentTeam = parse.csRow({ ...raw, cast: ["New Jersey Devils", "Boston Bruins"] }, "hockey", now);
    assert.equal(differentTeam.verification, "conflicting"); assert.ok(differentTeam.issues.includes("identity-conflict"));
    const differentSquad = parse.csRow(cs({ name: prefix + "India Women vs Australia Women", genres: ["CRICKET"],
      cast: ["India", "Australia"] }), "cricket", now);
    assert.equal(differentSquad.verification, "conflicting"); assert.ok(differentSquad.issues.includes("identity-conflict"));
  }
  const competitionPrefix = parse.csRow(cs({ name: "⏱ Some League : India vs Australia", cast: ["India", "Australia"] }), "cricket", now);
  assert.equal(competitionPrefix.verification, "conflicting", "Status decoration is not permission to erase arbitrary title authority");
  const unsafeCast = parse.csRow(cs({ name: "⏱ India vs Australia", cast: ["India 🇷🇺", "Australia"] }), "cricket", now);
  assert.equal(unsafeCast.verification, "conflicting", "A rejected flag/control contract in cast cannot be hidden by a valid title pair");
});
test("malformed scalar row fields do not discard independent accepted siblings", async () => {
  const h = harness("communitysports", async (url) => json({ metas: url.includes("_cricket.json") ? [cs(), { id: 12, name: 42 }] : [] }));
  const result = await h.run(); assert.equal(result.broadcasts.length, 1);
  assert.equal(result.scopes.find((s) => s.scope === "cricket").status, "partial");
  assert.equal(parse.asRow({ id: "plaviohdtv-unknown", name: 42, description: "n/a", genres: [] }, "cricket", now).verification, "conflicting");
});
test("channel identity never ignores explicit fixture participants or competing date authority", () => {
  const row = cs({ id: "nuvio_sport_willow", name: "📺 Willow Cricket", genres: ["NETWORKS"], released: undefined, behaviorHints: { defaultVideoId: "nuvio_sport_willow" } });
  assert.equal(parse.csRow(row, "networks", now).verification, "conflicting");
});
test("a standalone NETWORKS channel never acquires fixture format, ordinal or day from description copy", () => {
  const raw = cs({ id: "nuvio_sport_willow", name: "📺 Willow Cricket", genres: ["NETWORKS"], released: undefined, cast: undefined,
    behaviorHints: { defaultVideoId: "nuvio_sport_willow" }, description: "🏆 League: 3rd Test day-3\n📅 Category: NETWORKS\n⏰ Status: 24/7 Live Network" });
  const row = parse.csRow(JSON.parse(JSON.stringify(raw)), "networks", now);
  assert.equal(row.kind, "channel"); assert.equal(row.verification, "undated");
  assert.equal(row.format, undefined); assert.equal(row.matchOrdinal, undefined); assert.equal(row.day, undefined);
});

test("AS retains clock-only cricket as undated instead of inventing today or rewriting the Test day", () => {
  const row = parse.asRow({ id: "plaviohdtv-cricket-sa-aus", type: "tv", genres: ["Cricket"], name: "3rd Test day-3 : South Africa 🇿🇦 vs Australia 🇦🇺", description: "Starts 08:00 (UK time) · 6 channels" }, "cricket", now);
  assert.equal(row.format, "Test"); assert.equal(row.day, 3); assert.equal(row.verification, "undated");
  assert.equal(row.start, undefined); assert.deepEqual(row.participants, ["South Africa", "Australia"]);
});

const dayHTML = (content, hidden = "") => `<section class="schedule__day" ${hidden}><h3 class="schedule__dayTitle">Friday 30th October 2026 - Schedule Time UK GMT</h3><div class="schedule__category"><span class="card__meta">All Soccer Events</span>${content}</div></section>`;
const eventHTML = (clock = "16:30") => `<div class="schedule__event"><span class="schedule__eventTitle">England - Premier League : Chelsea vs Tottenham Hotspur</span><span class="schedule__time">${clock}</span></div>`;
test("AS native-equivalent original GMT scope supplies dates; hidden/script/template schedules cannot", () => {
  const original = parse.dlhdOriginals(dayHTML(eventHTML()) + dayHTML(eventHTML("17:30"), "hidden"));
  assert.equal(original.length, 1); assert.equal(original[0].start, "2026-10-30T16:30:00.000Z");
  const row = parse.asRow({ id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"], name: "England - Premier League : Chelsea vs Tottenham Hotspur", description: "Starts 16:30 (UK time) · 6 channels" }, "football", now, original);
  assert.equal(row.verification, "dated"); assert.equal(row.start, "2026-10-30T16:30:00.000Z");
  for (const markup of [`<template>${dayHTML(eventHTML())}</template>`, `<script>${dayHTML(eventHTML())}`, `<!-- ${dayHTML(eventHTML())}`]) assert.throws(() => parse.dlhdOriginals(markup), /invalid-collection/u);
});
test("AS actual decorated soccer category keeps its explicit original date without admitting other programme scopes", () => {
  for (const category of ["All Soccer Events ⚽", "  All Soccer Events  ⚽  "]) {
    const source = dayHTML(eventHTML()).replace("All Soccer Events</span>", category + "</span>");
    assert.equal(parse.dlhdOriginals(source)[0].start, "2026-10-30T16:30:00.000Z");
    const hidden = source.replace('class="schedule__category"', 'class="schedule__category" hidden');
    assert.equal(parse.dlhdOriginals(hidden).length, 0);
  }
  for (const category of ["Women's College Soccer ⚽", "All Soccer Events Women", "Cricket 🏏"]) {
    const source = dayHTML(eventHTML()).replace("All Soccer Events</span>", category + "</span>");
    assert.equal(parse.dlhdOriginals(source)[0].start, null, "A soccer icon never grants another category's date authority");
  }
});
test("AS same-ID metadata compares its relevant UK clock, not changing display channel counts", () => {
  const catalog = { id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"],
    name: "England - Premier League : Chelsea vs Tottenham Hotspur", description: "Starts 16:30 (UK time) · 18 channels" };
  const originals = parse.dlhdOriginals(dayHTML(eventHTML()).replace("All Soccer Events</span>", "All Soccer Events ⚽</span>"));
  for (const description of ["Starts 16:30 (UK time)", "Starts 16:30 (UK time) · 6 channels", "Starts 16:30 (UK time) · 18 channels"]) {
    const meta = { ...catalog, description };
    const row = parse.asEnriched(catalog, "football", meta, now, originals);
    assert.equal(row.verification, "dated"); assert.deepEqual(row.issues, []);
    assert.equal(row.start, "2026-10-30T16:30:00.000Z");
    const noOriginal = parse.asEnriched(catalog, "football", meta, now, []);
    assert.equal(noOriginal.start, undefined); assert.equal(noOriginal.verification, "undated", "The same clock does not invent a day");
  }
  for (const changes of [{ description: "Starts 16:31 (UK time)" }, { description: "Starts 16:30 (UTC)" },
    { description: "Starts 16:30 (UK time) · 0 channels" }, { description: "Starts 16:30 (UK time) · 1234 channels" },
    { description: "Starts 16:30 (UK time)\n30 Oct 2026" }, { name: "England - Premier League : Chelsea Women vs Tottenham Hotspur Women" },
    { released: "2026-10-30T16:30:00.000Z" }]) {
    const row = parse.asEnriched(catalog, "football", { ...catalog, ...changes }, now, originals);
    assert.equal(row.verification, "conflicting"); assert.ok(row.issues.includes("identity-conflict"));
  }
});
test("AS same-ID catalog count changes do not suppress bounded metadata verification or supply a missing original date", async () => {
  const catalog = { id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"],
    name: "England - Premier League : Chelsea vs Tottenham Hotspur", description: "Starts 16:30 (UK time) · 18 channels" };
  const h = harness("plaviosports", async (url) => url === "https://thedaddy.pk/" ? html("<div>No dated schedule available</div>")
    : url.includes("/meta/tv/") ? json({ meta: { ...catalog, description: "Starts 16:30 (UK time)" } })
      : json({ metas: url.includes("plaviohd-football") ? [catalog, { ...catalog, description: "Starts 16:30 (UK time) · 6 channels" }] : [] }),
  8, { allowMeta: true, manifestOverride: asMetadataManifest });
  const result = await h.run({ fixtures: [hintedFixture()] });
  assert.equal(h.calls.filter((r) => r.url.includes("/meta/tv/")).length, 1);
  assert.ok(h.calls.length <= 8);
  assert.ok(result.broadcasts.length > 0 && result.broadcasts.every((r) => r.verification === "undated" && !r.start));
  assert.ok(result.broadcasts.every((r) => !r.issues.includes("identity-conflict")));
});
test("AS original duplicate dates and London/GMT conflicts are not concealed by a matching clock", () => {
  const template = { id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"], name: "England - Premier League : Chelsea vs Tottenham Hotspur", description: "Starts 16:30 (UK time) · 6 channels" };
  const originals = parse.dlhdOriginals(dayHTML(eventHTML()));
  assert.equal(parse.asRow(template, "football", now, [...originals, { ...originals[0], clock: "17:30", start: "2026-10-31T17:30:00.000Z" }]).verification, "conflicting");
  const summer = [{ ...originals[0], start: "2026-10-24T16:30:00.000Z" }];
  assert.equal(parse.asRow(template, "football", now, summer).verification, "conflicting");
});

test("AS reads its original schedule once and retains unaffected cricket/channel cohorts", async () => {
  const h = harness("plaviosports", async (url) => url === "https://thedaddy.pk/" ? html(dayHTML(eventHTML())) : json({ metas: url.includes("plaviohd-football") ? [{ id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"], name: "England - Premier League : Chelsea vs Tottenham Hotspur", description: "Starts 16:30 (UK time) · 6 channels" }] : [] }));
  const result = await h.run();
  assert.equal(h.calls.filter((r) => r.url === "https://thedaddy.pk/").length, 1);
  assert.equal(result.broadcasts[0].verification, "dated"); assert.equal(h.calls.length, 5);
});
const hintedFixture = (changes = {}) => ({ fixtureID: "sports-fixture:premier-league:synthetic", sport: "football", competitionID: "premier-league", participants: ["Chelsea", "Tottenham Hotspur"], start: "2026-10-30T12:00:00.000Z", status: "live", observedAt: now.toISOString(), verified: true, ...changes });
const asLiveRow = (changes = {}) => ({ id: "plaviohdtv-sfly-streamed:football-chelsea-tottenham-1", type: "tv", name: "Chelsea vs Tottenham Hotspur", description: "Chelsea vs Tottenham Hotspur\nLIVE NOW", genres: ["Sports"], ...changes });
const asMetadataManifest = { ...manifests.plaviosports, resources: ["catalog", { name: "meta", types: ["tv"], idPrefixes: ["plaviohdtv-"] }, { name: "stream", types: ["tv"], idPrefixes: ["plaviohdtv-"] }] };
test("AS bounds same-ID meta enrichment by fresh whole-fixture hints and uses only the publisher's dated description", async () => {
  const row = asLiveRow();
  const h = harness("plaviosports", async (url) => url.includes("/meta/tv/")
    ? json({ meta: { ...row, description: "Chelsea vs Tottenham Hotspur\n30 Oct 2026 · 12:00 UTC" } })
    : json({ metas: url.includes("plaviohd-cricket") ? [] : [row] }), 8, { allowMeta: true, manifestOverride: asMetadataManifest });
  const result = await h.run({ fixtures: [hintedFixture()] });
  assert.equal(h.calls.filter((r) => r.url.includes("/meta/tv/")).length, 1);
  assert.equal(h.calls.length, 5); assert.equal(result.broadcasts.length, 2);
  assert.ok(result.broadcasts.every((r) => r.verification === "dated" && r.start === "2026-10-30T12:00:00.000Z"));
  const normalized = await normalizeBroadcastCollection("plaviosports", result, now);
  assert.equal(normalized.broadcasts.length, 1); assert.equal(normalized.broadcasts[0].verification, "dated", "Equivalent Live/sport rows upgrade together");
});
test("AS no/stale/squad-mismatched hints cannot trigger metadata lookups", async () => {
  for (const fixtures of [[], [hintedFixture({ observedAt: "2026-10-30T11:29:00.000Z" })], [hintedFixture({ participants: ["Chelsea Women", "Tottenham Hotspur Women"] })]]) {
    const h = harness("plaviosports", async () => json({ metas: [asLiveRow()] }), 8, { allowMeta: true, manifestOverride: asMetadataManifest });
    const result = await h.run({ fixtures });
    assert.equal(h.calls.filter((r) => r.url.includes("/meta/tv/")).length, 0);
    assert.ok(!result.broadcasts.some((r) => r.verification === "dated"));
  }
});
test("AS same-ID metadata cannot change the pair or hide a contradictory catalog sibling", async () => {
  for (const siblingConflict of [false, true]) {
    const h = harness("plaviosports", async (url) => url.includes("/meta/tv/")
      ? json({ meta: { ...asLiveRow(), name: "Arsenal vs Everton", description: "Arsenal vs Everton\n30 Oct 2026 · 12:00 UTC" } })
      : json({ metas: url.includes("plaviohd-cricket") ? [] : [asLiveRow(siblingConflict && url.includes("plaviohd-live-sports") ? { name: "Chelsea Women vs Tottenham Hotspur Women" } : {})] }),
    8, { allowMeta: true, manifestOverride: asMetadataManifest });
    const result = await h.run({ fixtures: [hintedFixture()] });
    assert.ok(result.broadcasts.filter((r) => r.providerEventID === asLiveRow().id).every((r) => r.verification === "conflicting"));
    assert.equal(h.calls.filter((r) => r.url.includes("/meta/tv/")).length, siblingConflict ? 0 : 1);
  }
});
test("AS first-colon and competition punctuation normalization matches the native original-schedule join", () => {
  const original = parse.dlhdOriginals(dayHTML(eventHTML()));
  const row = parse.asRow({ id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"], name: "England Premier League:Chelsea vs Tottenham Hotspur", description: "Starts 16:30 (UK time) · 6 channels" }, "football", now, original);
  assert.equal(row.verification, "dated"); assert.equal(row.start, "2026-10-30T16:30:00.000Z");
});
test("AS dated original joins retain only exact reviewed canonical competition identities, not similarly named leagues", () => {
  const labels = [["England - Premier League", "premier-league"], ["UEFA Champions League", "champions-league"],
    ["England - League Cup", "carabao-cup"], ["Spain - La Liga", "la-liga"], ["Italy - Serie A", "serie-a"],
    ["Germany - Bundesliga", "bundesliga"], ["France - Ligue 1", "ligue-1"]];
  for (const [competition, canonical] of labels) {
    const title = competition + " : Chelsea vs Tottenham Hotspur";
    const original = parse.dlhdOriginals(dayHTML(eventHTML()).replace("England - Premier League :", "⚽ " + competition + " :")
      .replace("All Soccer Events</span>", "All Soccer Events ⚽</span>"));
    const row = parse.asRow({ id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"], name: title,
      description: "Starts 16:30 (UK time) · 6 channels" }, "football", now, original);
    assert.equal(row.competitionID, canonical); assert.equal(row.verification, "dated");
    assert.equal(row.start, "2026-10-30T16:30:00.000Z");
  }
  for (const competition of ["England - Premier League 2", "Bundesliga 2", "Austria - Bundesliga", "Egypt Premier League", "UEFA Europa League"]) {
    const title = competition + " : Chelsea vs Tottenham Hotspur";
    const original = parse.dlhdOriginals(dayHTML(eventHTML()).replace("England - Premier League :", competition + " :"));
    const row = parse.asRow({ id: "plaviohdtv-dlhd-ev-abc", type: "tv", genres: ["Football"], name: title,
      description: "Starts 16:30 (UK time) · 6 channels" }, "football", now, original);
    assert.equal(row.competitionID, undefined); assert.equal(row.verification, "undated"); assert.ok(row.issues.includes("unsupported-scope"));
  }
});
test("CS uses at most two advertised searches for a fresh missing fixture before spending remaining rotation reads", async () => {
  const m = structuredClone(manifests.communitysports); m.catalogs.find((c) => c.id === "nuvio_sports_football").extra = [{ name: "search" }];
  const h = harness("communitysports", async (url) => json({ metas: url.includes("/search=Chelsea.json") ? [cs({ id: "nuvio_sport_chelsea", name: "Chelsea vs Tottenham Hotspur", cast: ["Chelsea", "Tottenham Hotspur"], genres: ["FOOTBALL"], released: "2026-10-30T12:00:00.000Z", behaviorHints: { defaultVideoId: "nuvio_sport_chelsea" } })] : [] }),
    8, { manifestOverride: m });
  const result = await h.run({ fixtures: [hintedFixture()] });
  assert.equal(h.calls.length, 8); assert.equal(h.calls.filter((r) => r.url.includes("/search=")).length, 2);
  assert.equal(result.broadcasts.find((r) => r.providerEventID === "nuvio_sport_chelsea").verification, "dated");
  assert.equal(result.cursor, 257);
});
test("CS never guesses an unadvertised search or uses a stale fixture as a query hint", async () => {
  for (const fixture of [hintedFixture(), hintedFixture({ observedAt: "2026-10-30T11:29:00.000Z" })]) {
    const h = harness("communitysports", async () => json({ metas: [] }));
    await h.run({ fixtures: [fixture] });
    assert.equal(h.calls.filter((r) => r.url.includes("/search=")).length, 0);
  }
});

test("CNC hashes encoded IDs and retains exact undated NHL hints without fetching metadata", async () => {
  const rawID = "cnc:" + "A".repeat(1218) + "==";
  const h = harness("cncsports", async () => json({ metas: [{ id: rawID, type: "tv", name: "Washington Capitals vs Philadelphia Flyers", behaviorHints: { defaultVideoId: rawID } }] }));
  const result = await h.run(), row = result.broadcasts[0];
  assert.match(row.providerEventID, /^cnc-observation:[a-f0-9]{64}$/u); assert.equal(row.streamID, row.providerEventID);
  assert.equal(row.verification, "undated"); assert.ok(!JSON.stringify(result).includes(rawID)); assert.equal(h.calls.length, 2);
});

const fsRow = (scope = "football") => ({ id: "dlstreams:event:aaaaaaaaaaaa", type: "tv", name: scope === "football" ? "⚽ England - Premier League : Chelsea vs Tottenham Hotspur" : "🏏 International : India vs New Zealand",
  description: `Category: ${scope === "football" ? "All Soccer Events ⚽" : "Cricket 🏏"}\nDate: 2026-10-30 (UTC)\nTime: 16:30\nChannels: 2`, genres: ["Live TV", "Sports", scope === "football" ? "All Soccer Events ⚽" : "Cricket 🏏"] });
test("FS retains healthy complete page cohort while a sibling genre page fails", async () => {
  const h = harness("flixstreams", async (url) => url.includes("genre=cricket&skip=40") ? json({}, 503) : json({ metas: url.includes("genre=soccer.json") ? [fsRow()] : [] }));
  const result = await h.run();
  assert.ok(result.broadcasts.some((r) => r.sport === "football" && r.verification === "dated"));
  assert.ok(!result.broadcasts.some((r) => r.sport === "cricket"));
  assert.equal(result.scopes.find((s) => s.scope === "cricket").status, "failed"); assert.ok(h.calls.length <= 7);
});
test("FS rejects competing timestamp/hint/video authority while retaining the identifiable row", () => {
  const row = parse.fsRow({ ...fsRow(), videos: [{ id: "dlstreams:event:aaaaaaaaaaaa", released: "2026-10-31T16:30:00.000Z", title: "Live Stream", season: 1, episode: 1 }] }, "football", now);
  assert.equal(row.verification, "conflicting"); assert.ok(row.issues.includes("time-conflict"));
});
test("FS preserves its explicit Test format/ordinal/day and literal UTC date through wire normalization", async () => {
  const raw = { ...fsRow("cricket"), name: "🏏 3rd Test day-3 : South Africa 🇿🇦 vs Australia 🇦🇺",
    description: "Category: Cricket 🏏\nDate: 2026-10-30 (UTC)\nTime: 08:00\nChannels: 6" };
  const row = parse.fsRow(raw, "cricket", now);
  assert.equal(row.verification, "dated"); assert.equal(row.format, "Test");
  assert.equal(row.matchOrdinal, 3); assert.equal(row.day, 3);
  assert.equal(row.start, "2026-10-30T08:00:00.000Z", "The source's day label never replaces its literal date");
  assert.deepEqual(row.participants, ["South Africa", "Australia"]);
  const normalized = await normalizeBroadcastCollection("flixstreams", { providerCode: "flixstreams", observedAt: now.toISOString(),
    complete: false, scopes: [{ scope: "cricket", status: "partial", complete: false }], broadcasts: [row] }, now);
  assert.equal(normalized.broadcasts[0].format, "Test"); assert.equal(normalized.broadcasts[0].matchOrdinal, 3);
  assert.equal(normalized.broadcasts[0].day, 3, "Keep the actual source day for the separate official-day conflict check");
  const undated = parse.fsRow({ ...raw, description: "Category: Cricket 🏏\nTime: 08:00\nChannels: 6" }, "cricket", now);
  assert.equal(undated.format, "Test"); assert.equal(undated.day, 3);
  assert.equal(undated.start, undefined); assert.equal(undated.verification, "undated");
});
test("FS cricket labels never invent format/ordinal/day from malformed or generic programme text", () => {
  for (const label of ["International", "3th Test day-3", "3rd Test day-7", "3rd ODI day-3", "3rd Test day-3 highlights"]) {
    const row = parse.fsRow({ ...fsRow("cricket"), name: "🏏 " + label + " : India vs New Zealand" }, "cricket", now);
    assert.equal(row.format, undefined); assert.equal(row.matchOrdinal, undefined); assert.equal(row.day, undefined);
  }
  for (const [label, format, ordinal] of [["4th T20I", "T20", 4], ["2nd ODI", "ODI", 2], ["1st T10", "T10", 1]]) {
    const row = parse.fsRow({ ...fsRow("cricket"), name: "🏏 " + label + " : India vs New Zealand" }, "cricket", now);
    assert.equal(row.format, format); assert.equal(row.matchOrdinal, ordinal); assert.equal(row.day, undefined);
  }
});

const svDay = "Saturday 24th October 2026 - Schedule Time UK GMT";
const svOriginal = { [svDay]: { "All Soccer Events ⚽": [{ event: "⚽ England - Premier League : Chelsea vs Tottenham Hotspur", time: "16:30" }] } };
const svEntry = { id: "tv:16-30-chelsea-vs-tottenham-hotspur-premier-league-24-10-20261024", type: "tv", name: "Chelsea vs Tottenham Hotspur ⏰ 16:30 - 24/10", description: "🔴 Inizio: 16:30 - Chelsea vs Tottenham Hotspur - Premier League - 24/10", eventStart: "2026-10-24T14:30:00Z", category: "premierleague", _dynamic: true, _originalName: "⏰ 16:30 : Chelsea vs Tottenham Hotspur - Premier League 24/10" };
test("SV original GMT and actual advertised ID corroborate its unique Rome conversion, not an offset guess", () => {
  const originals = parse.svOriginals(svOriginal), row = parse.svRow(svEntry, "Premier League", now, originals);
  assert.equal(row.verification, "dated"); assert.equal(row.start, "2026-10-24T16:30:00.000Z");
  assert.equal(parse.svRow({ ...svEntry, eventStart: "2026-10-24T15:30:00Z" }, "Premier League", now, originals).verification, "conflicting");
  assert.equal(parse.svRow({ ...svEntry, id: "tv:unadvertised" }, "Premier League", now, originals).verification, "conflicting");
});
test("SV failed UCL catalog cannot erase a healthy Premier League observation", async () => {
  const h = harness("streamvix", async (url) => new URL(url).hostname === "raw.githubusercontent.com" ? json(svOriginal)
    : url.includes("genre=Coppe") ? json({}, 503) : json({ metas: [svEntry] }));
  const result = await h.run(); assert.equal(result.broadcasts.length, 1); assert.equal(result.broadcasts[0].verification, "dated");
  assert.equal(result.scopes.length, 1); assert.equal(result.scopes[0].status, "partial"); assert.equal(h.calls.length, 4);
});
test("SV original-schedule failure retains advertised catalog rows as unverified, not an empty catalog", async () => {
  const h = harness("streamvix", async (url) => new URL(url).hostname === "raw.githubusercontent.com" ? json({}, 503) : json({ metas: url.includes("genre=Coppe") ? [] : [svEntry] }));
  const result = await h.run();
  assert.equal(result.broadcasts.length, 1); assert.equal(result.broadcasts[0].verification, "undated");
  assert.ok(result.broadcasts[0].issues.includes("unverified-fixture")); assert.equal(result.scopes[0].status, "partial");
});
test("SV source slug collision with a different full match remains a veto", () => {
  const long = "A".repeat(70), name = `${long} Club vs Away`, other = `${long} Rovers vs Away`;
  const originals = parse.svOriginals({ [svDay]: { "All Soccer Events ⚽": [{ event: "⚽ England - Premier League : " + name, time: "16:30" }, { event: "⚽ England - Premier League : " + other, time: "16:30" }] } });
  const row = { ...svEntry, id: "tv:" + ("16-30-" + "a".repeat(70) + "-club-vs-away-premier-league-24-10").slice(0, 60) + "-20261024",
    name: name + " ⏰ 16:30 - 24/10", description: `🔴 Inizio: 16:30 - ${name} - Premier League - 24/10`, _originalName: `⏰ 16:30 : ${name} - Premier League 24/10` };
  assert.equal(parse.svRow(row, "Premier League", now, originals).verification, "conflicting");
});

const widget = "12345678-1234-1234-1234-123456789abc";
const listing = `<html><body><div class="elfsight-app-${widget}"></div></body></html>`;
const scoreEvent = (changes = {}) => ({ id: "test-event", name: "Liverpool vs Chelsea", start: { type: "datetime", date: "2026-10-29", time: "01:00" }, end: { type: "datetime", date: "2026-10-29", time: "03:00" }, timeZone: "Asia/Karachi", repeatPeriod: "noRepeat", actions: [{ type: "link", text: "Watch Now", primary: true, link: { type: "url", value: "https://www.score808live.tv/liverpool-live/" } }], ...changes });
const boot = (events) => ({ status: 1, data: { widgets: { [widget]: { status: 1, data: { settings: { selectedEventsProvider: "manual", events } } } } } });
test("Score808 reads one visible widget and fixed boot, preserving literal zoned dates without article URLs", async () => {
  const h = harness("score808", async (url) => new URL(url).hostname === "core.service.elfsight.com" ? json(boot([scoreEvent()])) : html(listing));
  const result = await h.run(); assert.equal(h.calls.length, 2); const row = result.broadcasts[0];
  assert.equal(row.start, "2026-10-28T20:00:00.000Z"); assert.equal(row.end, "2026-10-28T22:00:00.000Z"); assert.equal(row.verification, "dated");
  assert.ok(!JSON.stringify(result).includes("liverpool-live")); assert.equal(result.scopes[0].complete, true);
  const normalized = await normalizeBroadcastCollection("score808", result, now); assert.equal(normalized.broadcasts[0].verification, "dated");
});
test("Score808 actual whitespace decoration cannot poison the whole collection", async () => {
  const h = harness("score808", async (url) => new URL(url).hostname === "core.service.elfsight.com" ? json(boot([scoreEvent({ name: " Liverpool vs Chelsea " })])) : html(listing));
  const normalized = await normalizeBroadcastCollection("score808", await h.run(), now);
  assert.equal(normalized.broadcasts[0].title, "Liverpool vs Chelsea");
});
test("Score808 repeated current article, malformed/duplicate widget and hidden scripts fail closed", async () => {
  const h = harness("score808", async (url) => new URL(url).hostname === "core.service.elfsight.com" ? json(boot([scoreEvent(), scoreEvent({ id: "second", name: "Arsenal vs Everton" })])) : html(listing));
  const result = await h.run(); assert.ok(result.broadcasts.every((r) => r.verification === "conflicting"));
  for (const bad of [`<script>${listing}</script>`, `<div hidden>${listing}</div>`, listing.replace("</body>", '<div class="elfsight-app-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"></div></body>')]) {
    const x = harness("score808", async () => html(bad)); const denied = await x.run(); assert.equal(x.calls.length, 1); assert.equal(denied.broadcasts.length, 0);
  }
});
test("local calendar conversion rejects DST gaps/duplicates and invalid civil dates", () => {
  assert.equal(parse.zonedDate("2026-03-29", "02:30", "Europe/Rome"), null);
  assert.equal(parse.zonedDate("2026-10-25", "02:30", "Europe/Rome"), null);
  assert.equal(parse.zonedDate("2026-02-30", "12:00", "UTC"), null);
});

test("StreamEx fallback profiles remain one family and retain unmatched dated catalog entries", async () => {
  const h = harness("streamex", async (url) => new URL(url).hostname === "www.streamex.net" ? json({}, 503) : json([{ id: "cup-home-away", title: "Home vs Away", category: "football", date: Date.parse("2026-10-30T18:00:00Z"), sources: [{ source: "alpha", id: "opaque" }] }]));
  const result = await h.run(); assert.equal(h.calls.length, 2); assert.equal(result.providerCode, "streamex"); assert.equal(result.broadcasts.length, 1);
  assert.equal(result.broadcasts[0].verification, "dated"); assert.equal(result.scopes[0].status, "partial");
});
test("redirects, non-JSON and oversize metadata never produce a fresh positive", async () => {
  for (const response of [new Response(null, { status: 302, headers: { location: "http://127.0.0.1/" } }),
    new Response("<html>not JSON</html>", { headers: { "content-type": "text/html" } }),
    new Response("{}", { headers: { "content-type": "application/json", "content-length": String(129 * 1024) } })]) {
    let calls = 0; const result = await collect("communitysports", { now, reserveRequest: async () => true, fetcher: async () => { calls++; return response; } });
    assert.equal(calls, 1); assert.equal(result.broadcasts.length, 0); assert.equal(result.complete, false);
  }
});
test("cancellation stops collection rather than publishing a partial fresh receipt", async () => {
  const controller = new AbortController(); let calls = 0;
  await assert.rejects(collect("communitysports", { now, signal: controller.signal, reserveRequest: async () => true,
    fetcher: async () => { calls++; controller.abort(new DOMException("Cancelled", "AbortError")); return json(manifests.communitysports); } }), { name: "AbortError" });
  assert.equal(calls, 1);
});
