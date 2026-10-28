import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import workerHandler, { WatchdogState } from "./index.mjs";
import { EXPECTED_VERSIONS, COLLECTION_INTERVAL_MS, observerPolicyOptions } from "../../../../tools/watchdog/manifest.mjs";
import { createPolicy, emptyLedger, applyObservation } from "../../../../tools/watchdog/incident-policy.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const runtimeRequire = createRequire(require.resolve("wrangler/package.json", { paths: [resolve(directory, "../../..")] }));
const { build } = runtimeRequire("esbuild");
const { Miniflare, convertV4MiniflareOptions, Log, LogLevel } = runtimeRequire("miniflare");
const admittedHosts = new Set(["nuviosports.xyz", "hd.plavio.site", "www.streamex.net", "streamex.sh", "streamed.pk", "www.score808live.tv", "fotty-playback-v3.adaptive-rhubarb.workers.dev"]);
function synthetic(request, mode = "valid") {
  const url = new URL(request.url || request);
  assert.ok(admittedHosts.has(url.hostname), "no real network/unreviewed host");
  assert.ok(!/\.m3u8|\.ts|\/stream\//.test(url.pathname), "no media or unbound stream probe");
  if (url.pathname === "/health") return Response.json({ service: "fotty-playback", sourceVersion: EXPECTED_VERSIONS.deploymentRevision,
    sportsFixtureServiceEnabled: false, cricketFixtureRegistryConfigured: false });
  if (mode === "redirect" && url.hostname === "www.streamex.net") return new Response(null, { status: 302, headers: { Location: "https://not-reviewed.invalid/feed" } });
  if (mode === "failure" && url.hostname === "nuviosports.xyz") return new Response(null, { status: 530 });
  if (url.hostname === "hd.plavio.site") return Response.json(url.pathname === "/manifest.json"
    ? { id: "community.plaviohd", version: "1.9.62", types: ["tv"], resources: ["catalog", { name: "stream", types: ["tv"], idPrefixes: ["plaviohdtv-"] }],
      catalogs: [{ type: "tv", id: "plaviohd-live-sports" }, { type: "tv", id: "plaviohd-cricket" }] }
    : { metas: [{ id: "plaviohdtv-synthetic", type: "tv", name: "Synthetic event", description: "Synthetic event", genres: ["Sports"] }] });
  if (url.pathname === "/manifest.json") return Response.json({ id: "community.nuvio.live-sports", version: "1", resources: ["catalog", "stream"], catalogs: [{ type: "tv", id: "nuvio_sports_live" }] });
  if (url.pathname === "/catalog/tv/nuvio_sports_live.json") return Response.json({ metas: [{ id: "synthetic", name: "Synthetic event", type: "tv" }] });
  if (url.hostname === "www.score808live.tv") return new Response('<div class="elfsight-app-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"></div>', { headers: { "Content-Type": "text/html" } });
  return Response.json([{ id: "synthetic", title: "Synthetic event", sources: [{ source: "alpha", id: "1" }] }]);
}
async function runtime(t, mode = "valid", enabled = "1", activatedAt = new Date().toISOString(), legacySeed) {
  const taskTemp = await mkdtemp(join(tmpdir(), "fotty-watchdog-test-"));
  const config = await readFile(join(directory, "../wrangler.toml"), "utf8");
  const compatibilityDate = config.match(/^compatibility_date\s*=\s*"([\d-]+)"/m)[1];
  const compatibilityFlags = [...config.match(/^compatibility_flags\s*=\s*\[([^\]]*)\]/m)[1].matchAll(/"([a-z0-9_]+)"/g)].map((match) => match[1]);
  // Test-only subclass seeds/reads real workerd storage. These endpoints never
  // exist in the production bundle or deployed source.
  const input = legacySeed ? { stdin: { resolveDir: directory, sourcefile: "legacy-storage-test.mjs", contents: `
    import handler, {WatchdogState as Base} from './index.mjs';
    export default handler;
    export class WatchdogState extends Base {
      async fetch(request) {
        if(new URL(request.url).pathname==='/__test_seed') { await this.state.storage.put('watchdog-observation-v1', ${JSON.stringify(legacySeed)}); return new Response('seeded'); }
        if(new URL(request.url).pathname==='/__test_read') return Response.json(await this.state.storage.get('watchdog-observation-v1'));
        return super.fetch(request);
      }
    }` } } : { entryPoints: [join(directory, "index.mjs")] };
  const script = (await build({ ...input, bundle: true, format: "esm", platform: "neutral", write: false, logLevel: "silent" })).outputFiles[0].text;
  const requests = [];
  const options = { modules: true, script, compatibilityDate, compatibilityFlags, log: new Log(LogLevel.NONE), cf: false,
    resourcePersistencePath: join(taskTemp, "state"), isolatedResourcePersistencePath: join(taskTemp, "isolated"), resourceTmpPath: join(taskTemp, "runtime"),
    unsafeEphemeralDurableObjects: true, durableObjects: { WATCHDOG_STATE: { className: "WatchdogState", useSQLite: true } },
    bindings: { FOTTY_WATCHDOG_ENABLED: enabled,
      ...(activatedAt === null ? {} : { FOTTY_WATCHDOG_ACTIVATED_AT: activatedAt }) },
    outboundService: (request) => { requests.push(new URL(request.url).hostname); return synthetic(request, mode); } };
  const miniflare = new Miniflare(typeof convertV4MiniflareOptions === "function" ? convertV4MiniflareOptions(options) : options);
  t.after(async () => { try { await miniflare.dispose(); } finally { await rm(taskTemp, { recursive: true, force: true }); } });
  const namespace = await miniflare.getDurableObjectNamespace("WATCHDOG_STATE");
  const stub = namespace.get(namespace.idFromName("production-observation-v1"));
  return { miniflare, stub, requests };
}
test("actual workerd: inactive observer and public POST make zero metadata reads", { timeout: 20000 }, async (t) => {
  const { miniflare, stub, requests } = await runtime(t, "valid", "0");
  assert.equal((await miniflare.dispatchFetch("https://test.invalid/run", { method: "POST" })).status, 404);
  assert.equal((await (await stub.fetch("https://internal.invalid/run", { method: "POST" })).json()).activation, "pending");
  assert.equal(requests.length, 0);
});
test("actual workerd: enabled flag without valid past activation cannot lease or read metadata", { timeout: 60000 }, async (t) => {
  for (const [name, activatedAt] of [["missing", null], ["malformed", "not-a-date"],
    ["impossible date", "2026-02-30T00:00:00Z"], ["future", "2099-01-01T00:00:00Z"]]) {
    await t.test(name, async (subtest) => {
      const { miniflare, stub, requests } = await runtime(subtest, "valid", "1", activatedAt);
      assert.equal((await (await stub.fetch("https://internal.invalid/run", { method: "POST" })).json()).activation, "pending");
      const status = await (await miniflare.dispatchFetch("https://test.invalid/status")).json();
      assert.equal(status.activation, "pending"); assert.equal(status.activatedAt, null);
      assert.equal(status.lastAttemptedAt, null); assert.equal(status.lastCompletedAt, null);
      assert.equal(status.nextAt, null); assert.equal(requests.length, 0);
    });
  }
});
test("actual workerd: overlapping scheduler calls acquire one durable collector lease", { timeout: 20000 }, async (t) => {
  const { miniflare, stub, requests } = await runtime(t);
  const runs = await Promise.all(Array.from({ length: 4 }, () => stub.fetch("https://internal.invalid/run", { method: "POST" }).then((result) => result.json())));
  assert.equal(runs.filter((result) => result.committed).length, 1);
  assert.equal(requests.length, 10);
  assert.equal(requests.filter((host) => host === "hd.plavio.site").length, 3);
  const status = await (await miniflare.dispatchFetch("https://test.invalid/status")).json();
  assert.ok(status.lastAttemptedAt && status.lastCompletedAt);
  assert.equal(status.streamDelivery, "not-probed");
  assert.equal(status.nativeEvidence, "private-device-canary-only");
  assert.equal(JSON.stringify(status).includes("Synthetic event"), false);
});
test("actual workerd: unreviewed redirect rejected without following and sibling still checked", { timeout: 20000 }, async (t) => {
  const { stub, requests } = await runtime(t, "redirect");
  await stub.fetch("https://internal.invalid/run", { method: "POST" });
  const status = await (await stub.fetch("https://internal.invalid/status")).json();
  assert.ok(status.incidents.some((row) => row.source === "streamex-primary" && row.failureClass === "redirect-rejected"));
  assert.ok(requests.includes("streamed.pk"));
  assert.equal(requests.includes("not-reviewed.invalid"), false);
});
test("actual workerd: historical confirmed ledger remains readable without erasing incidents or notices", { timeout: 20000 }, async (t) => {
  const options = observerPolicyOptions(), expected = { ...EXPECTED_VERSIONS,
    configurationRevision: '2026-10-11.admitted-metadata-1', deploymentRevision: '2026-10-06.cricket-isolation-1' };
  const oldPolicy = createPolicy({ ...options, admittedSources: options.admittedSources.map((entry) => ({ ...entry, expected })), failureWindows: 3 });
  let ledger = emptyLedger(oldPolicy); const start = Date.now() - 15 * 60_000;
  for (let n = 0; n < 3; n++) { const at = start + n * 5 * 60_000; ledger = applyObservation(ledger,
    { environment: 'production', source: 'cs', stage: 'manifest', failureClass: 'http-530', facts: {}, outcome: 'failure', observedAt: at, versions: expected }, oldPolicy, at).state; }
  assert.equal(Object.values(ledger.incidents)[0].failureCount, 3);
  const seed = { ledger, runtime: { fence: 0, lease: null, nextAt: 0, budget: {}, lastAttemptedAt: start, lastCompletedAt: start } };
  const { miniflare, stub } = await runtime(t, 'valid', '1', new Date(start - 60_000).toISOString(), seed);
  await stub.fetch('https://internal.invalid/__test_seed', { method: 'POST' });
  const status = await (await miniflare.dispatchFetch('https://test.invalid/status')).json();
  assert.equal(status.notifications.length, 1); assert.equal(status.notifications[0].id, ledger.outbox[0].id);
  assert.equal(status.incidents[0].generation, 1); assert.equal(status.incidents[0].state, 'confirmed');
  assert.deepEqual(await (await stub.fetch('https://internal.invalid/__test_read')).json(), seed);
});

// Deterministic storage failure/clock tests complement the real deployment
// runtime. No secrets, files, upstream requests or repair actions are involved.
function fakeState() {
  let stored, writes = 0, failAt = Infinity, failWhen = () => false;
  return { state: { storage: { get: async () => structuredClone(stored), transaction: async (change) => {
    let staged = structuredClone(stored);
    const result = await change({ get: async () => structuredClone(staged), put: async (_key, value) => { staged = structuredClone(value); } });
    if (++writes === failAt || failWhen(staged)) throw new Error("synthetic write failure");
    stored = staged; return result;
  } } }, read: () => stored, writes: () => writes, fail: (value) => { failAt = value; }, failWhen: (predicate) => { failWhen = predicate; } };
}
const activeEnv = (activatedAt = "2026-10-11T00:00:00Z") => ({ FOTTY_WATCHDOG_ENABLED: "1", FOTTY_WATCHDOG_ACTIVATED_AT: activatedAt });
test("activation fails closed before Durable Object lease or scheduler dispatch", async () => {
  const oldNow = Date.now, oldFetch = globalThis.fetch;
  const clock = Date.parse("2026-10-11T12:00:00Z");
  Date.now = () => clock;
  globalThis.fetch = async () => { throw new Error("inactive configuration must not fetch"); };
  try {
    const invalid = [undefined, null, "", "not-a-date", "2026-10-11", "2026-02-30T00:00:00Z", "2026-10-11T24:00:00Z",
      "2026-10-11T12:00:01Z", "2026-10-11T00:00:00+24:00", 1791719999000];
    for (const activatedAt of invalid) {
      const fake = fakeState(), env = { FOTTY_WATCHDOG_ENABLED: "1", FOTTY_WATCHDOG_ACTIVATED_AT: activatedAt };
      const worker = new WatchdogState(fake.state, env);
      assert.deepEqual(await (await worker.run(clock)).json(), { activation: "pending" });
      assert.equal(fake.writes(), 0); assert.equal(fake.read(), undefined);
      let dispatches = 0;
      workerHandler.scheduled(null, { ...env, WATCHDOG_STATE: {
        idFromName() { throw new Error("inactive scheduler must not access DO"); },
      } }, { waitUntil() { dispatches++; } });
      assert.equal(dispatches, 0);
    }
    for (const enabled of ["0", "true", undefined]) {
      const fake = fakeState();
      assert.equal((await (await new WatchdogState(fake.state, { ...activeEnv(), FOTTY_WATCHDOG_ENABLED: enabled }).run(clock)).json()).activation, "pending");
      assert.equal(fake.writes(), 0);
    }
  } finally { Date.now = oldNow; globalThis.fetch = oldFetch; }
});
test("a valid RFC3339 activation normalizes status and permits the scheduler", async () => {
  const oldNow = Date.now;
  Date.now = () => Date.parse("2026-10-11T12:00:00Z");
  try {
    const env = activeEnv("2026-10-11T07:00:00-04:00");
    const status = await (await new WatchdogState(fakeState().state, env).fetch(new Request("https://internal.invalid/status"))).json();
    assert.equal(status.activation, "active"); assert.equal(status.activatedAt, "2026-10-11T11:00:00.000Z");
    const calls = [], pending = [];
    workerHandler.scheduled(null, { ...env, WATCHDOG_STATE: {
      idFromName(name) { return name; }, get(name) { return { async fetch(url, options) {
        calls.push({ name, url, method: options.method }); return new Response(null, { status: 200 });
      } }; },
    } }, { waitUntil(promise) { pending.push(promise); } });
    await Promise.all(pending);
    assert.equal(calls.length, 1); assert.equal(calls[0].method, "POST");
  } finally { Date.now = oldNow; }
});
test("request reservation uses actual UTC day across midnight, not run-start day", async () => {
  const fake = fakeState(), oldFetch = globalThis.fetch, oldNow = Date.now;
  const start = Date.parse("2026-10-11T23:59:59Z");
  Date.now = () => start + 2000;
  globalThis.fetch = async (url) => synthetic(url);
  try {
    const worker = new WatchdogState(fake.state, activeEnv());
    assert.equal((await worker.run(start)).status, 200);
    assert.equal(fake.read().runtime.budget.day, "2026-10-12");
  } finally { globalThis.fetch = oldFetch; Date.now = oldNow; }
});
test("failed final storage commit never advances completion or emits an incident announcement", async () => {
  const fake = fakeState(), oldFetch = globalThis.fetch, oldLog = console.log, oldNow = Date.now;
  const logs = [];
  let clock = Date.parse("2026-10-11T12:00:00Z");
  Date.now = () => clock;
  globalThis.fetch = async (url) => synthetic(url, "failure");
  console.log = (message) => logs.push(message);
  try {
    const worker = new WatchdogState(fake.state, activeEnv());
    assert.equal((await worker.run()).status, 200); clock += COLLECTION_INTERVAL_MS;
    const completedBefore = fake.read().runtime.lastCompletedAt;
    // Fail the real confirmation commit by its staged semantic change, not an
    // implementation-specific reservation/write count.
    fake.failWhen((staged) => staged.runtime.lastCompletedAt > completedBefore);
    assert.equal((await worker.run()).status, 503);
    assert.equal(fake.read().runtime.lastCompletedAt, completedBefore);
    assert.equal(fake.read().ledger.outbox.length, 0);
    assert.equal(logs.length, 0);
  } finally { globalThis.fetch = oldFetch; console.log = oldLog; Date.now = oldNow; }
});
test("durably confirmed source notification exposes only safe scalars and hashed identity", async () => {
  const fake = fakeState(), oldFetch = globalThis.fetch, oldLog = console.log, oldNow = Date.now;
  let clock = Date.parse("2026-10-11T12:00:00Z");
  Date.now = () => clock; globalThis.fetch = async (url) => synthetic(url, "failure"); console.log = () => {};
  try {
    const worker = new WatchdogState(fake.state, activeEnv());
    for (let index = 0; index < 2; index++) { assert.equal((await worker.run()).status, 200); clock += COLLECTION_INTERVAL_MS; }
    const status = await (await worker.fetch(new Request("https://internal.invalid/status"))).json();
    const notices = status.notifications.filter((row) => row.source === "cs" && row.failureClass === "http-530");
    assert.equal(notices.length, 1);
    assert.ok(status.notifications.every((row) => row.source === "cs"));
    const notice = notices[0];
    assert.equal(notice.type, "confirmed"); assert.equal(notice.source, "cs"); assert.equal(notice.failureClass, "http-530");
    assert.match(notice.incidentId, /^[a-f0-9]{64}$/); assert.equal(notice.key, undefined);
    assert.equal(JSON.stringify(notice).includes("https://"), false);
    assert.equal(JSON.stringify(status).includes("Synthetic event"), false);
  } finally { globalThis.fetch = oldFetch; console.log = oldLog; Date.now = oldNow; }
});
