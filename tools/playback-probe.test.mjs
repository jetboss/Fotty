import test from "node:test";
import assert from "node:assert/strict";
import { selectTargets, inspectPlaylist, streamRequest, probeTarget, summarize, markdown } from "./playback-probe.mjs";

const link = (fixtureID, broadcastID, fingerprint, state = "listed") => ({ fixtureID, broadcastID, state, fixtureFingerprint: fingerprint });
const registry = {
  broadcasts: [
    { id: "b1", providerCode: "communitysports", kind: "event", streamID: "cs-1" },
    { id: "b2", providerCode: "plaviosports", kind: "event", streamID: "as-1" },
    { id: "b3", providerCode: "communitysports", kind: "channel", streamID: "willow" },
    { id: "b4", providerCode: "reviewedtv", kind: "programme", streamID: "fox-guide" },
  ],
  links: [
    link("f1", "b1", { sport: "football", competitionID: "premier-league" }),
    link("f1", "b1", { sport: "football", competitionID: "premier-league" }),          // duplicate
    link("f2", "b2", { sport: "cricket" }),
    link("f3", "b1", { sport: "football", competitionID: "la-liga" }),                  // out of scope
    link("f4", "b1", { sport: "football", competitionID: "champions-league" }, "conflicting"),
    link("f5", "b3", { sport: "cricket" }),                                             // channel
    link("f6", "b4", { sport: "cricket" }),
  ],
};

test("targets are listed, in-scope, de-duplicated and never channels", () => {
  assert.deepEqual(selectTargets(registry), [
    { competition: "premier-league", providerCode: "communitysports", streamID: "cs-1" },
    { competition: "cricket", providerCode: "plaviosports", streamID: "as-1" },
    { competition: "cricket", providerCode: "reviewedtv", streamID: "fox-guide" },
  ]);
  assert.equal(selectTargets(registry, 1).length, 1);
});

test("playlists: master needs a variant, media needs segments", () => {
  assert.deepEqual(inspectPlaylist("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nlow/index.m3u8\n"), { kind: "master", firstVariant: "low/index.m3u8" });
  assert.deepEqual(inspectPlaylist("#EXTM3U\n#EXTINF:4,\na.ts\n#EXTINF:4,\nb.ts\n"), { kind: "media", segments: 2 });
  for (const body of ["", "<html>", "#EXTM3U\n", "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n"]) assert.equal(inspectPlaylist(body).kind, "invalid");
});

test("stream requests keep https and only Origin, Referer and User-Agent", () => {
  const request = streamRequest({ url: "https://cdn.example/live.m3u8", behaviorHints: { proxyHeaders: { request: {
    Referer: "https://site.example/", "User-Agent": "UA", Cookie: "secret", Authorization: "x" } } } });
  assert.deepEqual(request.headers, { Referer: "https://site.example/", "User-Agent": "UA" });
  for (const url of ["http://cdn.example/a.m3u8", "https://user:pw@cdn.example/a.m3u8", "not a url", undefined]) assert.equal(streamRequest({ url }), null);
});

function fakeFetch(routes, calls = []) {
  return async (url) => {
    const key = String(url); calls.push(key);
    const route = routes[key];
    if (route === undefined) return new Response("missing", { status: 404 });
    return new Response(typeof route === "string" ? route : JSON.stringify(route), { status: 200 });
  };
}

test("a master playlist with a reachable media playlist is playable; reports carry no URLs", async () => {
  let t = 0; const now = () => (t += 500);
  const calls = [];
  const fetchImpl = fakeFetch({
    "https://nuviosports.xyz/stream/tv/cs-1.json": { streams: [{ externalUrl: "https://web.example" },
      { url: "https://cdn.example/live/master.m3u8", behaviorHints: { proxyHeaders: { request: { Referer: "https://r.example/" } } } }] },
    "https://cdn.example/live/master.m3u8": "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n720/index.m3u8\n",
    "https://cdn.example/live/720/index.m3u8": "#EXTM3U\n#EXTINF:4,\nseg1.ts\n",
  }, calls);
  const result = await probeTarget({ competition: "premier-league", providerCode: "communitysports", streamID: "cs-1" }, { fetchImpl, now });
  assert.equal(result.outcome, "playable"); assert.equal(result.family, "CS"); assert.equal(result.ms, 500);
  assert.equal(calls.some((c) => c.endsWith(".ts")), false, "Segments are never downloaded");
  assert.equal(/https?:|cs-1|cdn\.example/u.test(JSON.stringify(result)), false);
});

test("failures are classified without leaking identifiers", async () => {
  const target = { competition: "cricket", providerCode: "plaviosports", streamID: "as-1" };
  assert.equal((await probeTarget(target, { fetchImpl: fakeFetch({}) })).outcome, "descriptor-failed");
  assert.equal((await probeTarget(target, { fetchImpl: fakeFetch({ "https://addon.plavio.site/stream/tv/as-1.json": { streams: [] } }) })).outcome, "no-stream");
  assert.equal((await probeTarget(target, { fetchImpl: fakeFetch({ "https://addon.plavio.site/stream/tv/as-1.json":
    { streams: [{ url: "https://cdn.example/a.m3u8" }] }, "https://cdn.example/a.m3u8": "<html>blocked</html>" }) })).outcome, "playlist-invalid");
  assert.equal((await probeTarget(target, { fetchImpl: fakeFetch({ "https://addon.plavio.site/stream/tv/as-1.json":
    { streams: [{ url: "https://cdn.example/a.m3u8" }] } }) })).outcome, "playlist-failed");
  assert.equal((await probeTarget({ ...target, providerCode: "reviewedtv" })).outcome, "not-probed");
});

test("summary totals per competition and source, with median time and other outcomes", () => {
  const rows = summarize([
    { competition: "cricket", family: "CS", outcome: "playable", ms: 900 },
    { competition: "cricket", family: "CS", outcome: "playable", ms: 300 },
    { competition: "cricket", family: "CS", outcome: "playlist-failed" },
    { competition: "premier-league", family: "AS", outcome: "no-stream" },
  ]);
  assert.deepEqual(rows[0], { competition: "cricket", family: "CS", checks: 3, playable: 2,
    outcomes: { playable: 2, "playlist-failed": 1 }, medianMs: 900 });
  const text = markdown("Report", rows);
  assert.match(text, /\| cricket \| CS \| 3 \| 2 \(67%\) \| 0\.9 s \| playlist-failed 1 \|/u);
  assert.match(markdown("Empty", []), /No listed/u);
});
