import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const directory = dirname(fileURLToPath(import.meta.url));
const workerDirectory = resolve(directory, "..");
const webDirectory = resolve(workerDirectory, "../..");
const require = createRequire(import.meta.url);
// Use the actual installed deployment-tool runtime. No test-only version,
// download, dependency upgrade, credential or real publisher request is needed.
const wranglerRequire = createRequire(require.resolve("wrangler/package.json", { paths: [webDirectory] }));
const { build } = wranglerRequire("esbuild");
const { Miniflare, convertV4MiniflareOptions, Log, LogLevel } = wranglerRequire("miniflare");
const sources = ["football-data", "mlb", "nhl", "wnba"];
const hosts = new Map([
  ["api.football-data.org", "football-data"], ["statsapi.mlb.com", "mlb"],
  ["api-web.nhle.com", "nhl"], ["cdn.wnba.com", "wnba"],
]);
const SYNTHETIC_KEY = "runtime-test-not-a-credential";

let bundle;
async function deploymentRuntime() {
  const config = await readFile(join(workerDirectory, "wrangler.toml"), "utf8");
  const compatibilityDate = config.match(/^compatibility_date\s*=\s*"([\d-]+)"/m)?.[1];
  const flagText = config.match(/^compatibility_flags\s*=\s*\[([^\]]*)\]/m)?.[1];
  assert.match(compatibilityDate || "", /^\d{4}-\d{2}-\d{2}$/);
  assert.notEqual(flagText, undefined);
  const compatibilityFlags = [...flagText.matchAll(/"([a-z0-9_]+)"/g)].map((match) => match[1]);
  assert.ok(compatibilityFlags.includes("enable_request_signal"));
  return { compatibilityDate, compatibilityFlags };
}
async function workerBundle() {
  bundle ||= build({ entryPoints: [join(directory, "index.js")], bundle: true, format: "esm", platform: "neutral",
    target: "esnext", write: false, logLevel: "silent" }).then((result) => result.outputFiles[0].text);
  return bundle;
}
function syntheticResponse(source, url) {
  if (source === "football-data") return Response.json({ filters: { dateFrom: url.searchParams.get("dateFrom"),
    dateTo: url.searchParams.get("dateTo"), competitions: "PL,CL" }, resultSet: { count: 0 }, matches: [] });
  if (source === "mlb") return Response.json({ totalGames: 0, totalItems: 0, totalEvents: 0, dates: [] });
  if (source === "nhl") {
    const date = url.pathname.split("/").at(-1);
    assert.match(date, /^\d{4}-\d{2}-\d{2}$/);
    return Response.json({ numberOfGames: 0, gameWeek: Array.from({ length: 7 }, (_, index) => ({
      date: new Date(Date.parse(`${date}T00:00:00Z`) + index * 86_400_000).toISOString().slice(0, 10), games: [] })) });
  }
  const now = new Date();
  return Response.json({ meta: { time: now.toISOString() }, leagueSchedule: { leagueId: "10", seasonYear: String(now.getUTCFullYear()),
    gameDates: [{ games: [{ gameId: "100", gameDateTimeUTC: new Date(now.getTime() - 60 * 60_000).toISOString(),
      gameStatus: 3, gameStatusText: "Final", postponedStatus: "N", ifNecessary: false,
      homeTeam: { teamId: 1, teamCity: "Alpha", teamName: "Club" }, awayTeam: { teamId: 2, teamCity: "Beta", teamName: "Club" } }] }] } },
  { headers: { "Last-Modified": now.toUTCString() } });
}

async function runtime(t, mode, wnbaEnabled = "1") {
  const taskTemp = await mkdtemp(join(tmpdir(), "fotty-sports-runtime-"));
  let miniflare;
  let disposal;
  const dispose = () => disposal ||= miniflare?.dispose() || Promise.resolve();
  const abort = () => { void dispose().catch(() => {}); };
  t.after(async () => {
    t.signal.removeEventListener("abort", abort);
    try { await dispose(); }
    finally { await rm(taskTemp, { recursive: true, force: true }); }
  });
  const requests = [];
  const options = {
    modules: true, script: await workerBundle(), ...await deploymentRuntime(),
    log: new Log(LogLevel.NONE), cf: false,
    resourcePersistencePath: join(taskTemp, "state"), isolatedResourcePersistencePath: join(taskTemp, "isolated"),
    resourceTmpPath: join(taskTemp, "runtime"), unsafeEphemeralDurableObjects: true,
    durableObjects: { SPORTS_FIXTURES: { className: "SportsFixtureRegistry", useSQLite: true } },
    bindings: { FOOTBALL_DATA_API_KEY: SYNTHETIC_KEY, FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0", FOTTY_SPORTS_WNBA_ENABLED: wnbaEnabled },
    outboundService: async (request) => {
      const url = new URL(request.url);
      const source = hosts.get(url.hostname);
      requests.push({ source: source || "unreviewed", host: url.hostname });
      assert.ok(source, "No real network or unreviewed publisher is allowed in this test");
      assert.equal(request.method, "GET");
      if (source === "football-data") assert.equal(request.headers.get("x-auth-token"), SYNTHETIC_KEY);
      else assert.equal(request.headers.get("x-auth-token"), null);
      if (mode === "redirect") return new Response(null, { status: [301, 302, 307, 308][sources.indexOf(source)],
        headers: { Location: "https://redirect-target.invalid/schedule" } });
      return syntheticResponse(source, url);
    },
  };
  // Current Miniflare exposes the conversion explicitly; older installed
  // Wrangler versions still accept this same documented option shape directly.
  miniflare = new Miniflare(typeof convertV4MiniflareOptions === "function" ? convertV4MiniflareOptions(options) : options);
  t.signal.addEventListener("abort", abort, { once: true });
  return { miniflare, requests };
}
async function refresh(namespace, source) {
  const stub = namespace.get(namespace.idFromName(`shared-sports-fixtures-v1:${source}`));
  const response = await stub.fetch(`https://sports-registry.invalid/refresh?source=${source}`, { method: "POST" });
  assert.equal(response.status, 200);
  return { source, stub, body: await response.json() };
}

test("actual workerd admits every eligible primary source through the exported DO wrapper", { timeout: 20_000 }, async (t) => {
  const { miniflare, requests } = await runtime(t, "valid");
  const namespace = await miniflare.getDurableObjectNamespace("SPORTS_FIXTURES");
  const refreshed = await Promise.all(sources.map((source) => refresh(namespace, source)));
  assert.ok(refreshed.every((result) => result.body.ok === true));
  assert.equal(requests.length, 5); // Football one, MLB one, NHL two, WNBA one.
  assert.deepEqual([...new Set(requests.map((request) => request.source))].sort(), [...sources].sort());
  const response = await miniflare.dispatchFetch("https://runtime-test.invalid/api/sports/fixtures");
  assert.equal(response.status, 200);
  const snapshot = await response.json();
  assert.equal(snapshot.complete, true);
  assert.equal(snapshot.sourceStatus, "verified");
  const covered = snapshot.coverage.filter((row) => row.status === "covered");
  assert.deepEqual(covered.map((row) => row.competitionId).sort(), ["champions-league", "mlb", "nhl", "premier-league", "wnba"]);
  assert.ok(covered.every((row) => row.checkedAt !== null && row.sync.consecutiveFailures === 0));
  assert.equal(snapshot.fixtures.length, 1);
  assert.equal(snapshot.fixtures[0].squad.gender, "women");
});

test("actual workerd reaches each publisher but rejects 3xx without following or admitting an empty source", { timeout: 20_000 }, async (t) => {
  const { miniflare, requests } = await runtime(t, "redirect");
  const namespace = await miniflare.getDurableObjectNamespace("SPORTS_FIXTURES");
  const refreshed = await Promise.all(sources.map((source) => refresh(namespace, source)));
  assert.ok(refreshed.every((result) => result.body.ok === false));
  assert.deepEqual([...new Set(requests.map((request) => request.source))].sort(), [...sources].sort());
  assert.ok(requests.length >= 4 && requests.length <= 5);
  assert.equal(requests.some((request) => request.host === "redirect-target.invalid"), false);
  for (const { source, stub } of refreshed) {
    const response = await stub.fetch(`https://sports-registry.invalid/fixtures?source=${source}`);
    const state = await response.json();
    assert.equal(state.accepted, undefined);
    assert.equal(state.consecutiveFailures, 1);
    assert.notEqual(state.lastAttemptAt, null);
    assert.equal(state.failure.stage, "collection");
    assert.equal(state.failure.code, "upstream-unavailable");
    assert.equal(state.failure.httpStatus, [301, 302, 307, 308][sources.indexOf(source)]);
  }
});

test("actual workerd does not collect the deferred WNBA lane or report it as healthy empty coverage", { timeout: 20_000 }, async (t) => {
  const { miniflare, requests } = await runtime(t, "valid", "0");
  const namespace = await miniflare.getDurableObjectNamespace("SPORTS_FIXTURES");
  const refreshed = await Promise.all(sources.filter((source) => source !== "wnba").map((source) => refresh(namespace, source)));
  assert.ok(refreshed.every((result) => result.body.ok === true));
  const deferred = namespace.get(namespace.idFromName("shared-sports-fixtures-v1:wnba"));
  const deferredResponse = await deferred.fetch("https://sports-registry.invalid/refresh?source=wnba", { method: "POST" });
  assert.equal(deferredResponse.status, 404);
  assert.equal(requests.some((request) => request.source === "wnba"), false);
  const response = await miniflare.dispatchFetch("https://runtime-test.invalid/api/sports/fixtures");
  assert.equal(response.status, 200);
  const snapshot = await response.json();
  const lane = snapshot.coverage.find((row) => row.competitionId === "wnba");
  assert.equal(lane.status, "unsupported");
  assert.equal(lane.checkedAt, null);
  assert.match(lane.reason, /verified source access/);
  assert.equal(snapshot.coverage.filter((row) => row.status === "covered").length, 4);
});
