import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { collectSportsSource, SPORTS_SOURCES } from "../../playback/src/sports-fixture-sources.mjs";
import { EXPECTED_VERSIONS, COLLECTION_INTERVAL_MS } from "../../../../tools/watchdog/manifest.mjs";
import { MATCH_COVERAGE_KEY } from "../../../../tools/watchdog/match-coverage.mjs";

const directory = dirname(fileURLToPath(import.meta.url)), require = createRequire(import.meta.url);
const runtimeRequire = createRequire(require.resolve("wrangler/package.json", { paths: [resolve(directory, "../../..")] }));
const { build } = runtimeRequire("esbuild"), { Miniflare, convertV4MiniflareOptions, Log, LogLevel } = runtimeRequire("miniflare");
const NOW = Date.parse("2026-09-30T16:00:00Z");
async function factorySnapshot() {
  const source = SPORTS_SOURCES.find((row) => row.id === "football-data");
  const normalized = await collectSportsSource(source, new Date(NOW), { FOOTBALL_DATA_API_KEY: "offline-placeholder" }, async (url) => Response.json({
    filters: { dateFrom: url.searchParams.get("dateFrom"), dateTo: url.searchParams.get("dateTo"), competitions: url.searchParams.get("competitions") },
    resultSet: { count: 1 }, matches: [{ id: 111, utcDate: new Date(NOW - 1800_000).toISOString(), status: "IN_PLAY", lastUpdated: new Date(NOW).toISOString(),
      competition: { code: "PL" }, homeTeam: { id: 1, name: "Liverpool" }, awayTeam: { id: 2, name: "Chelsea" } }] }));
  return { schemaVersion: 1, complete: true, revision: "offline-factory", sourceStatus: "verified", checkedAt: new Date(NOW).toISOString(), fixtures: normalized.fixtures,
    coverage: SPORTS_SOURCES.filter((s) => s.id !== "wnba").flatMap((s) => s.competitions.map((c) => ({ competitionId: c.id, competitionName: c.name,
      sport: c.sport, status: "covered", checkedAt: new Date(NOW).toISOString(),
      fixtureCount: normalized.fixtures.filter((f) => f.competitionId === c.id).length, pendingFixtureCount: 0, sync: { consecutiveFailures: 0 } }))) };
}
async function runtime(t) {
  const owned = await mkdtemp(join(process.env.FOTTY_MATCH_COVERAGE_TEST_TEMP || process.env.RUNNER_TEMP || tmpdir(), "match-coverage-runtime-"));
  const config = await readFile(join(directory, "../wrangler.toml"), "utf8"), base = await factorySnapshot();
  const contents = `
    import handler,{WatchdogState as Base} from './index.mjs';
    export default handler;
    let clock=${NOW}, mode='gap'; Date.now=()=>clock;
    const source=${JSON.stringify(base)};
    const hosts=new Set(['fotty-playback-v3.adaptive-rhubarb.workers.dev','nuviosports.xyz','addon.plavio.site','www.streamex.net','streamex.sh','streamed.pk','www.score808live.tv']);
    let requests=[];
    globalThis.fetch=async(raw)=>{
      const u=new URL(raw);if(!hosts.has(u.hostname)||/\\.m3u8|\\.ts$/.test(u.pathname))throw new Error('Unreviewed request');
      requests.push(u.hostname+u.pathname);
      if(u.pathname==='/health')return Response.json({service:'fotty-playback',sourceVersion:'${EXPECTED_VERSIONS.deploymentRevision}',sportsFixtureServiceEnabled:true,cricketFixtureRegistryConfigured:false});
      if(u.pathname==='/api/sports/fixtures'){
        const body=structuredClone(source),stamp=new Date(clock).toISOString();body.checkedAt=stamp;
        for(const f of body.fixtures){f.source.observedAt=stamp;f.source.updatedAt=stamp;}
        for(const c of body.coverage)c.checkedAt=stamp;
        return Response.json(body);
      }
      if(u.hostname==='nuviosports.xyz'){
        if(u.pathname==='/manifest.json')return Response.json({id:'community.nuvio.live-sports',version:'1',resources:['catalog','stream'],catalogs:[{id:'nuvio_sports_live',type:'tv'}]});
        if(u.pathname.startsWith('/stream/'))return Response.json({streams:[]});
        return Response.json({metas:mode==='matched'?[{id:'nuvio_sport_current',type:'tv',name:'LIVE: Liverpool vs Chelsea',genres:['FOOTBALL'],cast:['Liverpool','Chelsea'],released:source.fixtures[0].start}]:[]});
      }
      if(u.hostname==='addon.plavio.site')return Response.json(u.pathname==='/manifest.json'?{id:'community.plaviohd.private',version:'1.9.98',types:['tv'],resources:['catalog',{name:'stream',types:['tv'],idPrefixes:['plaviohdtv-']}],catalogs:[{id:'plaviohd-football',type:'tv'},{id:'plaviohd-cricket',type:'tv'}]}:{metas:[]});
      if(u.hostname==='www.score808live.tv')return new Response('<div class="elfsight-app-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"></div>',{headers:{'Content-Type':'text/html'}});
      return Response.json([]);
    };
    export class WatchdogState extends Base{
      constructor(state,env){
        const storage={get:(...a)=>state.storage.get(...a),transaction:(change)=>state.storage.transaction(tx=>change({get:(...a)=>tx.get(...a),put:async(key,value)=>{
          if(mode==='fail-coverage'&&key==='${MATCH_COVERAGE_KEY}')throw new Error('synthetic coverage write failure');
          return tx.put(key,value);
        }}))};
        super({storage},env);this.actualStorage=state.storage;
      }
      async fetch(request){
        const path=new URL(request.url).pathname;
        if(path==='/__test_run'){const p=await request.json();clock=p.at;mode=p.mode||'gap';return this.run(clock);}
        if(path==='/__test_read')return Response.json({main:await this.actualStorage.get('watchdog-observation-v1'),coverage:await this.actualStorage.get('${MATCH_COVERAGE_KEY}'),requests});
        return super.fetch(request);
      }
    }`;
  const script = (await build({ stdin: { contents, resolveDir: directory, sourcefile: "coverage-runtime-fixture.mjs" }, bundle: true,
    format: "esm", platform: "neutral", write: false, logLevel: "silent" })).outputFiles[0].text;
  const options = { modules: true, script, compatibilityDate: config.match(/^compatibility_date\s*=\s*"([\d-]+)"/m)[1],
    compatibilityFlags: [...config.match(/^compatibility_flags\s*=\s*\[([^\]]*)\]/m)[1].matchAll(/"([a-z0-9_]+)"/g)].map((m) => m[1]),
    log: new Log(LogLevel.NONE), cf: false, resourcePersistencePath: join(owned, "state"), isolatedResourcePersistencePath: join(owned, "isolated"), resourceTmpPath: join(owned, "runtime"),
    unsafeEphemeralDurableObjects: true, durableObjects: { WATCHDOG_STATE: { className: "WatchdogState", useSQLite: true } },
    bindings: { FOTTY_WATCHDOG_ENABLED: "1", FOTTY_WATCHDOG_ACTIVATED_AT: "2026-09-01T00:00:00.000Z", FOTTY_OWNER_EMAIL_ENABLED: "0" },
    outboundService: () => { throw new Error("No external network is permitted"); } };
  const mf = new Miniflare(typeof convertV4MiniflareOptions === "function" ? convertV4MiniflareOptions(options) : options);
  t.after(async () => { try { await mf.dispose(); } finally { await rm(owned, { recursive: true, force: true }); } });
  const ns = await mf.getDurableObjectNamespace("WATCHDOG_STATE"), stub = ns.get(ns.idFromName("production-observation-v1"));
  const call = async (path, body) => stub.fetch("https://test.invalid/" + path, body ? { method: "POST", body: JSON.stringify(body) } : undefined);
  return { call };
}
test("real SQLite: catalog-only aggregate commits separately with original completion, no additional request inventory", { timeout: 20_000 }, async (t) => {
  const { call } = await runtime(t);
  assert.equal((await (await call("__test_run", { at: NOW })).json()).committed, true);
  const first = await (await call("__test_read")).json();
  assert.equal(first.main.runtime.lastCompletedAt, NOW); assert.equal(first.coverage.checkedAt, NOW);
  assert.equal(first.coverage.competitions[0].outcome, "failure"); assert.equal(first.requests.length, 8);
  assert.equal(first.requests.filter((p) => p.startsWith("nuviosports.xyz")).length, 2);
  assert.equal(first.requests.filter((p) => p.startsWith("addon.plavio.site")).length, 3);
  assert.equal(first.main.ledger.outbox.length, 0, "One observation cannot confirm a coverage gap");
  const status = await (await call("status")).json();
  assert.deepEqual(status.matchCoverage, first.coverage);
  for (const raw of ["Liverpool", "Chelsea", "nuvio_sport", "https://"]) assert.equal(JSON.stringify(status.matchCoverage).includes(raw), false);
  const after = await (await call("__test_read")).json();
  assert.deepEqual(after, first, "Read-only status cannot refresh coverage or spend provider budget");
});
test("real SQLite: aggregate write failure cannot commit new ledger notice/completion or replace prior receipt", { timeout: 20_000 }, async (t) => {
  const { call } = await runtime(t);
  assert.equal((await (await call("__test_run", { at: NOW })).json()).committed, true);
  const before = await (await call("__test_read")).json();
  const response = await call("__test_run", { at: NOW + COLLECTION_INTERVAL_MS, mode: "fail-coverage" });
  assert.equal(response.status, 503); assert.equal((await response.json()).committed, false);
  const after = await (await call("__test_read")).json();
  assert.deepEqual(after.coverage, before.coverage);
  assert.deepEqual(after.main.ledger, before.main.ledger, "The would-be second failure and notice must roll back atomically");
  assert.equal(after.main.runtime.lastCompletedAt, before.main.runtime.lastCompletedAt);
  assert.equal(after.main.runtime.lastAttemptedAt, NOW + COLLECTION_INTERVAL_MS);
  assert.ok(after.main.runtime.lease, "Failed commit must not erase its owned durable lease");
});
