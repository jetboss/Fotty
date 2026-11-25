import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createPolicy, emptyLedger, applyObservation } from "../../../../tools/watchdog/incident-policy.mjs";
import { observerPolicyOptions, EXPECTED_VERSIONS, COLLECTION_INTERVAL_MS, CONFIRMATION_WINDOWS } from "../../../../tools/watchdog/manifest.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const runtimeRequire = createRequire(require.resolve("wrangler/package.json", { paths: [resolve(directory, "../../..")] }));
const { build } = runtimeRequire("esbuild");
const { Miniflare, convertV4MiniflareOptions, Log, LogLevel } = runtimeRequire("miniflare");
const policy = createPolicy({ ...observerPolicyOptions(), failureWindows: CONFIRMATION_WINDOWS });
function historicalSeed(now) {
  let ledger = emptyLedger(policy), at = now - 4 * 86_400_000;
  for (let cycle = 0; cycle < 61; cycle++) {
    for (const outcome of ["failure", "failure", ...(cycle < 60 ? ["success", "success"] : [])]) {
      ledger = applyObservation(ledger, { environment: "production", source: "cs", stage: "manifest", failureClass: "http-530",
        facts: {}, outcome, observedAt: at, versions: EXPECTED_VERSIONS }, policy, at).state;
      at += COLLECTION_INTERVAL_MS;
    }
  }
  assert.equal(ledger.outbox.length, 121);
  return { ledger, runtime: { fence: 7, lease: null, nextAt: now - 1000 + COLLECTION_INTERVAL_MS,
    lastAttemptedAt: now - 1000, lastCompletedAt: now - 1000,
    budget: { day: new Date(now).toISOString().slice(0, 10), counts: { cs: 23, as: 17 } } } };
}
function appendFresh(seed, now) {
  const next = structuredClone(seed);
  for (const at of [now - COLLECTION_INTERVAL_MS, now]) {
    next.ledger = applyObservation(next.ledger, { environment: "production", source: "cs", stage: "catalog", failureClass: "schema",
      facts: {}, outcome: "failure", observedAt: at, versions: EXPECTED_VERSIONS }, policy, at).state;
  }
  assert.equal(next.ledger.outbox.length, 122); return next;
}
async function runtime(t, now, enabled = "1") {
  const root = await mkdtemp(join(process.env.FOTTY_EMAIL_TEST_TEMP || tmpdir(), "email-runtime-"));
  const config = await readFile(join(directory, "../wrangler.toml"), "utf8");
  // Test-only subclass injects an in-memory email transport and inspection
  // routes. The real production handler retains its read-only public surface.
  const contents = `
    import handler, {WatchdogState as Base} from './index.mjs';
    import {OwnerEmailDelivery, OWNER_EMAIL_KEY} from './owner-email.mjs';
    export default handler;
    let clock=${now}, mode='valid'; Date.now=()=>clock;
    export class WatchdogState extends Base {
      constructor(state,env) {
        const storage={get:(...args)=>state.storage.get(...args), transaction:(change)=>state.storage.transaction((tx)=>change({
          get:(...args)=>tx.get(...args),put:async(key,value)=>{
            if(mode==='ackfail' && key===OWNER_EMAIL_KEY && value.lastOutcome==='submitted') throw new Error('synthetic acknowledgement storage failure');
            return tx.put(key,value);
          }}))};
        const binding={send:async(message)=>{
          const sent=await state.storage.get('test-only-mails')||[];
          sent.push({subject:message.subject,text:message.text,headers:message.headers});
          await state.storage.put('test-only-mails',sent);
          if(mode==='rejected') throw Object.assign(new Error('private error omitted'),{code:'E_RECIPIENT_NOT_ALLOWED'});
          return {messageId:'accepted-'+sent.length};
        }};
        super({storage}, {...env,FOTTY_OWNER_EMAIL_ENABLED:'${enabled}',
          FOTTY_OWNER_EMAIL_ACTIVATED_AT:'${new Date(now - 5000).toISOString()}',
          FOTTY_OWNER_EMAIL_RECIPIENT:'owner@receiver.example',FOTTY_OWNER_EMAIL_SENDER:'watchdog@getfotty.com',FOTTY_OWNER_EMAIL:binding});
        this.actualStorage=state.storage;
      }
      async fetch(request) {
        const path=new URL(request.url).pathname;
        if(path==='/__test_seed') {await this.actualStorage.put('watchdog-observation-v1',await request.json());return new Response('seeded');}
        if(path==='/__test_read') return Response.json({original:await this.actualStorage.get('watchdog-observation-v1'),email:await this.actualStorage.get(OWNER_EMAIL_KEY),sent:await this.actualStorage.get('test-only-mails')||[]});
        if(path==='/__test_run') {const input=await request.json();clock=input.at;mode=input.mode||'valid';
          if(input.flagMode==='missing') delete this.env.FOTTY_OWNER_EMAIL_ENABLED;
          else if(input.flagMode!==undefined) this.env.FOTTY_OWNER_EMAIL_ENABLED=input.flagMode;
          if(input.restart) this.ownerEmail=new OwnerEmailDelivery(this.state.storage,this.env);
          return this.run(clock);}
        return super.fetch(request);
      }
    }`;
  const script = (await build({ stdin: { contents, sourcefile: "owner-email-runtime-fixture.mjs", resolveDir: directory },
    bundle: true, format: "esm", platform: "neutral", write: false, logLevel: "silent" })).outputFiles[0].text;
  const options = { modules: true, script, compatibilityDate: config.match(/^compatibility_date\s*=\s*"([\d-]+)"/m)[1],
    compatibilityFlags: [...config.match(/^compatibility_flags\s*=\s*\[([^\]]*)\]/m)[1].matchAll(/"([a-z0-9_]+)"/g)].map((match) => match[1]),
    log: new Log(LogLevel.NONE), cf: false, resourcePersistencePath: join(root, "state"),
    isolatedResourcePersistencePath: join(root, "isolated"), resourceTmpPath: join(root, "runtime"),
    unsafeEphemeralDurableObjects: true, durableObjects: { WATCHDOG_STATE: { className: "WatchdogState", useSQLite: true } },
    bindings: { FOTTY_WATCHDOG_ENABLED: "1", FOTTY_WATCHDOG_ACTIVATED_AT: "2026-10-11T11:14:52.000Z" },
    outboundService: () => { throw new Error("This acceptance gate permits no external request"); } };
  const miniflare = new Miniflare(typeof convertV4MiniflareOptions === "function" ? convertV4MiniflareOptions(options) : options);
  t.after(async () => { try { await miniflare.dispose(); } finally { await rm(root, { recursive: true, force: true }); } });
  const ns = await miniflare.getDurableObjectNamespace("WATCHDOG_STATE"), stub = ns.get(ns.idFromName("production-observation-v1"));
  const call = async (path, data) => (await stub.fetch(`https://test.invalid/${path}`,
    data === undefined ? undefined : { method: "POST", body: JSON.stringify(data) })).json();
  return { miniflare, stub, call };
}
test("real SQLite: default-OFF email cannot alter historical collector storage or send", { timeout: 20_000 }, async (t) => {
  const now = Date.now(), seed = historicalSeed(now), { stub, call } = await runtime(t, now, "0");
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(seed) });
  assert.equal((await call("__test_run", { at: now })).due, false);
  const read = await call("__test_read"); assert.deepEqual(read.original, seed); assert.equal(read.email, undefined); assert.equal(read.sent.length, 0);
});
test("real production DO: cutover preserves121 notices/leases/budgets, then only fresh committed notice is submitted", { timeout: 20_000 }, async (t) => {
  const now = Date.now(), seed = historicalSeed(now), { miniflare, stub, call } = await runtime(t, now);
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(seed) });
  const first = await call("__test_run", { at: now }); assert.equal(first.ownerEmail.baselineCount, 121);
  let read = await call("__test_read"); assert.equal(read.sent.length, 0); assert.deepEqual(read.original, seed);
  const fresh = appendFresh(seed, now + 1);
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(fresh) });
  assert.equal((await call("__test_run", { at: now + 1, restart: true })).ownerEmail.submittedBatches, 1);
  read = await call("__test_read"); assert.equal(read.sent.length, 1); assert.equal(read.original.ledger.outbox.length, 122);
  assert.deepEqual(read.original, fresh); assert.match(read.sent[0].subject, /1 operational updates/);
  const status = await (await miniflare.dispatchFetch("https://test.invalid/status")).json();
  assert.equal(status.notifications.length, 122); assert.equal(status.ownerEmail.pendingCount, 0);
  assert.ok(!JSON.stringify(status).includes("owner@receiver.example")); assert.ok(!JSON.stringify(status).includes("watchdog@getfotty.com"));
  assert.equal((await miniflare.dispatchFetch("https://test.invalid/email", { method: "POST" })).status, 404);
});
test("real SQLite: failure after external submission retains the lease and retries same batch after restart", { timeout: 20_000 }, async (t) => {
  const now = Date.now(), seed = historicalSeed(now), { stub, call } = await runtime(t, now);
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(seed) });
  await call("__test_run", { at: now }); const fresh = appendFresh(seed, now + 1);
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(fresh) });
  assert.equal((await call("__test_run", { at: now + 1, mode: "ackfail" })).ownerEmail.state, "state-unavailable");
  let read = await call("__test_read"); assert.equal(read.email.pending.length, 1); assert.equal(read.email.submittedBatches, 0);
  assert.equal(read.sent.length, 1); assert.deepEqual(read.original, fresh);
  const result = await call("__test_run", { at: now + 300_001, restart: true });
  assert.equal(result.ownerEmail.ambiguousAttempts, 1); assert.equal(result.ownerEmail.pendingCount, 0);
  read = await call("__test_read"); assert.equal(read.sent.length, 2); assert.equal(read.original.ledger.outbox.length, 122);
  assert.equal(read.sent[0].headers["X-Fotty-Alert-ID"], read.sent[1].headers["X-Fotty-Alert-ID"]);
});
test("real production DO: lost or garbled flag exposes established pending delivery; explicit0 alone pauses it", { timeout: 20_000 }, async (t) => {
  const now = Date.now(), seed = historicalSeed(now), { miniflare, stub, call } = await runtime(t, now);
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(seed) });
  await call("__test_run", { at: now }); const fresh = appendFresh(seed, now + 1);
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(fresh) });
  assert.equal((await call("__test_run", { at: now + 1, mode: "rejected" })).ownerEmail.state, "retry-pending");
  const saved = await call("__test_read"); assert.equal(saved.email.pending.length, 1); assert.equal(saved.sent.length, 1);
  for (const flagMode of ["missing", "garbled"]) {
    const run = await call("__test_run", { at: now + 2, flagMode, restart: true });
    assert.deepEqual(run.ownerEmail, { enabled: true, state: "configuration-mismatch" });
    const status = await (await miniflare.dispatchFetch("https://test.invalid/status")).json();
    assert.deepEqual(status.ownerEmail, run.ownerEmail); assert.deepEqual(await call("__test_read"), saved);
  }
  assert.equal((await call("__test_run", { at: now + 3, flagMode: "0", restart: true })).ownerEmail, undefined);
  const paused = await (await miniflare.dispatchFetch("https://test.invalid/status")).json();
  assert.deepEqual(paused.ownerEmail, { enabled: false, state: "disabled" }); assert.deepEqual(await call("__test_read"), saved);
});
test("real production DO: pristine missing flag stays quiet and does not create email state", { timeout: 20_000 }, async (t) => {
  const now = Date.now(), seed = historicalSeed(now), { miniflare, stub, call } = await runtime(t, now);
  await stub.fetch("https://test.invalid/__test_seed", { method: "POST", body: JSON.stringify(seed) });
  const result = await call("__test_run", { at: now, flagMode: "missing" });
  assert.equal(result.due, false); assert.equal(result.ownerEmail, undefined);
  const status = await (await miniflare.dispatchFetch("https://test.invalid/status")).json();
  assert.deepEqual(status.ownerEmail, { enabled: false, state: "disabled" });
  const read = await call("__test_read"); assert.deepEqual(read.original, seed); assert.equal(read.email, undefined); assert.equal(read.sent.length, 0);
});
