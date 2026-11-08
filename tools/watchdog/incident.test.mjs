import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { applyObservation, assertRepairFence, claimRepair, createPolicy, emptyLedger, incidentKey,
  listNotifications, missedRunObservations, normalizeFacts, releaseRepair, validateLedger } from './incident-policy.mjs';
import { openIncidentStore } from './incident-store.mjs';

const NOW = Date.UTC(2026, 9, 11);
const versions = { observerRevision: 'observer-1', configurationRevision: 'config-1', deploymentRevision: 'deployed-1' };
function policy(overrides = {}) {
  return createPolicy({ environment: 'qualification', windowMs: 1000, maxReceiptAgeMs: 10000,
    admittedSources: ['cs', 'streamex', 'observer'].map(source => ({ source,
      stages: source === 'observer' ? ['liveness'] : ['manifest', 'catalog', 'stream'], activation: 'active', expected: versions })), ...overrides });
}
function receipt(overrides = {}) {
  return { environment: 'qualification', source: 'cs', stage: 'manifest', failureClass: 'upstream_http',
    facts: { status: 530 }, outcome: 'failure', observedAt: new Date(NOW).toISOString(),
    versions, evidenceHash: 'a'.repeat(64), ...overrides };
}
function observe(state, p, window, changes = {}) {
  const now = NOW + window * 1000;
  return applyObservation(state, receipt({ observedAt: new Date(now).toISOString(), ...changes }), p, now);
}
function confirmed(p = policy()) {
  let state = emptyLedger(p);
  for (let index = 0; index < 3; index++) state = observe(state, p, index).state;
  return state;
}
async function temporary(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'fotty-watchdog-test-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  return directory;
}

test('reviewed published closure confirms on first evidence without security quarantine', () => {
  const p = policy({ admittedSources: [{ source: 'streamex', stages: ['catalog'], activation: 'active', expected: versions,
    immediateFailureClasses: ['published-closure'] }] });
  const out = observe(emptyLedger(p), p, 0, { source: 'streamex', stage: 'catalog', failureClass: 'published-closure', facts: {} });
  assert.equal(out.events.length, 1); assert.equal(Object.values(out.state.incidents)[0].state, 'confirmed');
  assert.equal(Object.values(out.state.incidents)[0].quarantined, false);
});
test('unreviewed source or ordinary failure cannot borrow immediate closure confirmation', () => {
  const p = policy();
  assert.equal(observe(emptyLedger(p), p, 0, { failureClass: 'published-closure' }).events.length, 0);
  const q = policy({ admittedSources: [{ source: 'streamex', stages: ['catalog'], activation: 'active', expected: versions,
    immediateFailureClasses: ['published-closure'] }] });
  assert.equal(observe(emptyLedger(q), q, 0, { source: 'streamex', stage: 'catalog', failureClass: 'non-json', facts: {} }).events.length, 0);
});
test('immediate threshold cannot be expanded to transient HTTP failures', () => {
  assert.throws(() => policy({ admittedSources: [{ source: 'streamex', stages: ['catalog'], activation: 'active', expected: versions,
    immediateFailureClasses: ['http-503'] }] }));
});
test('schema1 historical three-window records load under two-window policy without erasing receipts', () => {
  const old = policy(), next = policy({ failureWindows: 2 });
  const legacy = confirmed(old), frozen = JSON.stringify(legacy);
  assert.equal(Object.values(legacy.incidents)[0].failureCount, 3);
  validateLedger(legacy, next); assert.equal(JSON.stringify(legacy), frozen);
  assert.deepEqual(listNotifications(legacy, next), listNotifications(legacy, old));
  const corrupt = structuredClone(legacy); Object.values(corrupt.incidents)[0].failureCount = 4;
  assert.throws(() => validateLedger(corrupt, next));
  const live = observe(legacy, next, 3).state;
  assert.equal(Object.values(live.incidents)[0].failureCount, 2);
  assert.equal(live.notificationSequence, legacy.notificationSequence);
});
test('historical suspect and resolved records do not announce transitions on policy read', () => {
  const old = policy(), next = policy({ failureWindows: 2 });
  const suspect = observe(observe(emptyLedger(old), old, 0).state, old, 1).state;
  validateLedger(suspect, next); assert.equal(Object.values(suspect.incidents)[0].state, 'suspect');
  assert.equal(listNotifications(suspect, next).length, 0);
  let resolved = confirmed(old);
  for (let n = 3; n <= 4; n++) resolved = observe(resolved, old, n, { outcome: 'success' }).state;
  const frozen = JSON.stringify(resolved); validateLedger(resolved, next);
  assert.equal(JSON.stringify(resolved), frozen); assert.equal(Object.values(resolved.incidents)[0].state, 'resolved');
});
test('configuration change resets a historical suspect and needs two fresh checks', () => {
  const old = policy(), changed = { ...versions, configurationRevision: 'config-2' };
  const next = policy({ failureWindows: 2, admittedSources: ['cs', 'streamex', 'observer'].map(source => ({ source,
    stages: source === 'observer' ? ['liveness'] : ['manifest', 'catalog', 'stream'], activation: 'active', expected: changed })) });
  const legacy = observe(observe(emptyLedger(old), old, 0).state, old, 1).state;
  validateLedger(legacy, next); const initial = JSON.stringify(legacy);
  assert.equal(JSON.stringify(legacy), initial); assert.equal(listNotifications(legacy, next).length, 0);
  const first = observe(legacy, next, 2, { versions: changed });
  assert.equal(first.events.length, 0); assert.equal(Object.values(first.state.incidents)[0].failureCount, 1);
  const second = observe(first.state, next, 3, { versions: changed });
  assert.equal(second.events.length, 1); assert.equal(Object.values(second.state.incidents)[0].generation, 1);
});

test('portable policy has no Node imports, network or native evidence side effects', async () => {
  const source = await fs.readFile(new URL('./incident-policy.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /(?:from\s*['"]node:|\bfetch\s*\(|\bprocess\.)/);
  assert.equal(emptyLedger(policy()).incidents && Object.keys(emptyLedger(policy()).incidents).length, 0);
});

test('stable normalized identity excludes revision/time/hash, separates siblings and disputed facts', () => {
  const base = receipt({ facts: { code: 'TIMEOUT', status: 530 } });
  assert.equal(incidentKey(base), incidentKey({ ...base, observedAt: '2099-01-01', evidenceHash: 'b'.repeat(64), versions: { ...versions, deploymentRevision: 'new' }, facts: { status: 530, code: 'timeout' } }));
  for (const changes of [{ source: 'streamex' }, { stage: 'catalog' }, { failureClass: 'tls' }, { facts: { status: 403 } }, { environment: 'other' }]) {
    assert.notEqual(incidentKey(base), incidentKey({ ...base, ...changes }));
  }
});

test('three distinct matching windows confirm once; duplicate receipt never increments', () => {
  const p = policy(); let state = emptyLedger(p); const key = incidentKey(receipt());
  for (let window = 0; window < 3; window++) {
    const result = observe(state, p, window); state = result.state;
    assert.equal(result.events.length, window === 2 ? 1 : 0);
    const duplicate = observe(state, p, window);
    assert.equal(duplicate.state.incidents[key].failureCount, state.incidents[key].failureCount);
    assert.deepEqual(duplicate.events, []);
  }
  assert.equal(state.incidents[key].state, 'confirmed');
  for (let index = 3; index < 20; index++) state = observe(state, p, index).state;
  assert.equal(state.incidents[key].failureCount, 3);
  assert.equal(Object.keys(state.incidents).length, 1);
});

test('one success between failures never resolves; two new success windows resolve once', () => {
  const p = policy(), key = incidentKey(receipt()); let state = confirmed(p);
  state = observe(state, p, 3, { outcome: 'success' }).state;
  assert.equal(state.incidents[key].state, 'recovering');
  state = observe(state, p, 4).state;
  assert.equal(state.incidents[key].state, 'confirmed');
  assert.equal(state.incidents[key].successCount, 0);
  state = observe(state, p, 5, { outcome: 'success' }).state;
  const recovery = observe(state, p, 6, { outcome: 'success' });
  assert.equal(recovery.state.incidents[key].state, 'resolved');
  assert.deepEqual(recovery.events.map(event => event.type), ['resolved']);
  assert.deepEqual(observe(recovery.state, p, 7, { outcome: 'success' }).events, []);
});

test('same-window contradictory success cannot erase a failure', () => {
  const p = policy(), key = incidentKey(receipt()); const state = confirmed(p);
  const result = observe(state, p, 2, { outcome: 'success' });
  assert.equal(result.result, 'duplicate');
  assert.equal(result.state.incidents[key].successCount, 0);
});

test('suspects and reopened unconfirmed transients resolve quietly', () => {
  const p = policy(), key = incidentKey(receipt()); let state = observe(emptyLedger(p), p, 0).state;
  state = observe(state, p, 1, { outcome: 'success' }).state;
  let result = observe(state, p, 2, { outcome: 'success' });
  assert.equal(result.state.incidents[key].state, 'resolved'); assert.deepEqual(result.events, []);
  state = confirmed(p);
  state = observe(state, p, 3, { outcome: 'success' }).state;
  state = observe(state, p, 4, { outcome: 'success' }).state;
  state = observe(state, p, 5).state;
  assert.equal(state.incidents[key].generation, 2);
  state = observe(state, p, 6, { outcome: 'success' }).state;
  result = observe(state, p, 7, { outcome: 'success' });
  assert.deepEqual(result.events, []);
});

test('unknown, inactive, deferred and off-season never recover or create an outage', () => {
  const p = policy(), key = incidentKey(receipt()); let state = confirmed(p);
  state = observe(state, p, 3, { outcome: 'success' }).state;
  for (const [index, outcome] of ['unknown', 'inactive'].entries()) {
    state = observe(state, p, index + 4, { outcome }).state;
    assert.notEqual(state.incidents[key].state, 'resolved');
    assert.equal(state.incidents[key].successCount, 0);
  }
  for (const activation of ['inactive', 'deferred', 'off-season']) {
    const off = policy({ admittedSources: [{ source: 'cs', stages: ['manifest'], activation, expected: versions }] });
    const result = observe(emptyLedger(off), off, 0);
    assert.equal(result.result, 'inactive'); assert.deepEqual(result.state.incidents, {});
  }
});

test('exact observer/config/deployment fence rejects old success and resets a changed recovery baseline', () => {
  const p = policy(), key = incidentKey(receipt()); const start = confirmed(p);
  for (const name of Object.keys(versions)) {
    let state = observe(start, p, 3, { outcome: 'success', versions: { ...versions, [name]: 'old' } }).state;
    assert.equal(state.incidents[key].successCount, 0);
    assert.equal(state.coverage['cs/manifest'].versionMatches, false);
    state = observe(state, p, 4, { outcome: 'success' }).state;
    assert.notEqual(state.incidents[key].state, 'resolved');
  }
  const newVersions = { ...versions, deploymentRevision: 'deployed-2' };
  const next = policy({ admittedSources: [{ source: 'cs', stages: ['manifest'], activation: 'active', expected: newVersions }] });
  let state = observe(start, next, 3, { outcome: 'success', versions: newVersions }).state;
  assert.equal(state.incidents[key].successCount, 1);
  assert.equal(observe(state, next, 4, { outcome: 'success', versions: newVersions }).state.incidents[key].state, 'resolved');
});

test('stale/future/replayed success does not qualify recovery; sibling success cannot clear CS', () => {
  const p = policy(), key = incidentKey(receipt()), state = confirmed(p);
  const stale = applyObservation(state, receipt({ outcome: 'success', observedAt: new Date(NOW).toISOString() }), p, NOW + 20000);
  assert.equal(stale.result, 'stale'); assert.equal(stale.state.incidents[key].successCount, 0);
  const future = applyObservation(state, receipt({ observedAt: new Date(NOW + 50000).toISOString(), outcome: 'success' }), p, NOW + 3000);
  assert.equal(future.result, 'stale');
  assert.equal(observe(state, p, 3, { source: 'streamex', outcome: 'success' }).state.incidents[key].state, 'confirmed');
  assert.equal(observe(state, p, 1, { outcome: 'success' }).result, 'stale');
  let replay = observe(state, p, 3, { outcome: 'success', checkedAt: new Date(NOW + 3000).toISOString() }).state;
  replay = observe(replay, p, 4, { outcome: 'success', checkedAt: new Date(NOW + 3000).toISOString() }).state;
  assert.equal(replay.incidents[key].successCount, 1);
  assert.notEqual(replay.incidents[key].state, 'resolved');
  assert.equal(observe(state, p, 20, { outcome: 'success', checkedAt: new Date(NOW).toISOString() }).result, 'stale');
});

test('reviewed security evidence immediately confirms quarantine, unknown class does not assert exact cause', () => {
  const p = policy();
  const result = observe(emptyLedger(p), p, 0, { failureClass: 'unsafe_redirect', securityViolation: true });
  assert.equal(Object.values(result.state.incidents)[0].quarantined, true);
  assert.equal(result.events[0].type, 'confirmed');
  const unknown = observe(emptyLedger(p), p, 0, { failureClass: 'unknown' });
  assert.equal(Object.values(unknown.state.incidents)[0].failureClass, 'unknown');
  assert.equal(Object.values(unknown.state.incidents)[0].state, 'suspect');
});

test('raw URLs, headers, names and malformed/future receipts are rejected, never persisted', () => {
  for (const facts of [{ headers: 'public' }, { code: 'https://source.invalid/private?token=secret' },
    { code: 'Bearer secret' }, { teamName: 'Chelsea' }, { status: NaN }, { code: 'a\nsecret' }]) {
    assert.throws(() => normalizeFacts(facts));
  }
  const p = policy(), state = emptyLedger(p);
  for (const changes of [{ source: 'not-admitted' }, { stage: 'native_decoded' }, { environment: 'other' },
    { versions: { ...versions, headers: 'private' } }, { evidenceHash: 'secret' },
    { checkedAt: new Date(NOW + 60000).toISOString() }, { acceptedAt: new Date(NOW + 60000).toISOString() }]) {
    assert.throws(() => observe(state, p, 0, changes));
  }
  assert.equal(JSON.stringify(state).includes('secret'), false);
});

test('checked handler and stale accepted data produce separate observer incidents after grace', () => {
  const spec = { environment: 'qualification', source: 'observer', stage: 'liveness', activation: 'active',
    intervalMs: 1000, graceMs: 500, startedAt: NOW, lastCompletedAt: NOW + 1900,
    lastAttemptedAt: NOW + 1900, lastAcceptedAt: NOW, requiresAccepted: true, versions };
  const outcomes = missedRunObservations(spec, NOW + 2000);
  assert.deepEqual(outcomes.map(item => [item.facts.dimension, item.outcome]), [['completed', 'success'], ['attempted', 'success'], ['accepted', 'failure']]);
  assert.equal(missedRunObservations({ ...spec, lastAcceptedAt: null }, NOW + 1500)[2].outcome, 'unknown');
  assert.equal(missedRunObservations({ ...spec, activation: 'inactive' }, NOW + 9000)[0].outcome, 'inactive');
  assert.equal(missedRunObservations({ ...spec, startedAt: null, lastCompletedAt: null }, NOW + 2000)[0].outcome, 'unknown');
});

test('capacity degrades once, preserves active conflicts and permanently closes new repair claims', () => {
  const p = policy({ limits: { active: 1 } }), original = confirmed(p), key = incidentKey(receipt());
  const overflow = observe(original, p, 3, { facts: { status: 403 } });
  assert.equal(overflow.result, 'overflow'); assert.deepEqual(overflow.events.map(item => item.type), ['overflow']);
  assert.deepEqual(overflow.state.incidents[key], original.incidents[key]);
  assert.equal(Object.keys(overflow.state.incidents).length, 1);
  assert.deepEqual(observe(overflow.state, p, 4, { facts: { status: 404 } }).events, []);
  assert.equal(claimRepair(overflow.state, key, { owner: 'test', baseRevision: 'base', ttlMs: 100 }, p, NOW + 3000).claim, null);
});

test('one global lease, increasing fencing, expiry, exact base and late recovery all fail closed', () => {
  const p = policy(), key = incidentKey(receipt()); let state = confirmed(p);
  let result = claimRepair(state, key, { owner: 'first', baseRevision: 'base-1', ttlMs: 500 }, p, NOW + 3000);
  const old = result.claim; state = result.state;
  assert.equal(claimRepair(state, key, { owner: 'second', baseRevision: 'base-1', ttlMs: 500 }, p, NOW + 3100).result, 'busy');
  assert.throws(() => assertRepairFence(state, old, { baseRevision: 'changed' }, p, NOW + 3100));
  assert.throws(() => assertRepairFence(state, old, { baseRevision: 'base-1' }, p, NOW + 3500));
  result = claimRepair(state, key, { owner: 'second', baseRevision: 'base-1', ttlMs: 500 }, p, NOW + 3600);
  assert.equal(result.claim.token, old.token + 1); state = result.state;
  assert.throws(() => assertRepairFence(state, old, { baseRevision: 'base-1' }, p, NOW + 3700));
  assert.equal(assertRepairFence(state, result.claim, { baseRevision: 'base-1' }, p, NOW + 3700), true);
  state = observe(state, p, 4, { outcome: 'success' }).state;
  assert.throws(() => assertRepairFence(state, result.claim, { baseRevision: 'base-1' }, p, NOW + 4000));
  assert.equal(releaseRepair(state, result.claim, { baseRevision: 'base-1' }, p, NOW + 5000).state.lease, null);
});

test('byte overflow preserves prior active evidence and reserves space for the durable marker', () => {
  const p = policy({ limits: { ledgerBytes: 1500 } });
  let state = observe(emptyLedger(p), p, 0).state;
  const key = incidentKey(receipt());
  const original = structuredClone(state);
  const overflow = observe(state, p, 1, { stage: 'catalog', facts: { status: 404 } });
  assert.equal(overflow.result, 'overflow');
  assert.deepEqual(overflow.state.incidents[key], original.incidents[key]);
  validateLedger(overflow.state, p);
  assert.ok(new TextEncoder().encode(JSON.stringify(overflow.state)).length <= 1500);
});

test('activation and revision changes revoke outstanding repairs without broad permission changes', () => {
  const p = policy(), key = incidentKey(receipt()); const claimed = claimRepair(confirmed(p), key, { owner: 'first', baseRevision: 'base', ttlMs: 500 }, p, NOW + 3000);
  for (const entry of [{ activation: 'inactive', expected: versions }, { activation: 'active', expected: { ...versions, configurationRevision: 'new' } }]) {
    const next = policy({ admittedSources: [{ source: 'cs', stages: ['manifest'], ...entry }] });
    assert.throws(() => assertRepairFence(claimed.state, claimed.claim, { baseRevision: 'base' }, next, NOW + 3100));
  }
  const released = releaseRepair(claimed.state, claimed.claim, { baseRevision: 'base' }, p, NOW + 3100);
  assert.equal(released.state.lease, null); assert.equal(released.state.incidents[key].state, 'confirmed');
});

test('durable restart preserves confirmation, dedup and recovery; metadata never creates native evidence', async t => {
  const directory = await temporary(t), p = policy(); let store = await openIncidentStore(directory, { policy: p });
  for (let index = 0; index < 3; index++) await store.observe(receipt({ observedAt: new Date(NOW + index * 1000).toISOString() }), NOW + index * 1000);
  store = await openIncidentStore(directory, { policy: p });
  let result = await store.observe(receipt({ observedAt: new Date(NOW + 2000).toISOString() }), NOW + 2000);
  assert.deepEqual(result.events, []); assert.equal(result.state.revision, 4);
  await store.observe(receipt({ outcome: 'success', observedAt: new Date(NOW + 3000).toISOString() }), NOW + 3000);
  store = await openIncidentStore(directory, { policy: p });
  result = await store.observe(receipt({ outcome: 'success', observedAt: new Date(NOW + 4000).toISOString() }), NOW + 4000);
  assert.equal(result.state.incidents[incidentKey(receipt())].state, 'resolved');
  assert.deepEqual(result.events.map(item => item.type), ['resolved']);
  assert.equal(JSON.stringify(result.state).includes('decoded'), false);
});

test('concurrent processes obtain exactly one lease and stale writers fail after restart', async t => {
  const directory = await temporary(t), p = policy(), key = incidentKey(receipt());
  const store = await openIncidentStore(directory, { policy: p });
  await store.transact(() => ({ state: confirmed(p) }));
  const module = new URL('./incident-store.mjs', import.meta.url).href;
  const results = await Promise.all(Array.from({ length: 4 }, (_, index) => new Promise((resolve, reject) => {
    const script = `import {openIncidentStore} from ${JSON.stringify(module)}; const store=await openIncidentStore(${JSON.stringify(directory)},{policy:${JSON.stringify(p)}}); const result=await store.claimRepair(${JSON.stringify(key)},{owner:'child-${index}',baseRevision:'base',ttlMs:500},${NOW + 3000}); console.log(JSON.stringify({result:result.result,claim:result.claim}));`;
    const child = spawn(process.execPath, ['--input-type=module', '-e', script], { stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '', error = ''; child.stdout.on('data', data => output += data); child.stderr.on('data', data => error += data);
    child.once('error', reject); child.once('exit', code => code === 0 ? resolve(JSON.parse(output)) : reject(new Error(error)));
  })));
  assert.equal(results.filter(result => result.result === 'claimed').length, 1);
  const old = results.find(result => result.claim).claim;
  const restart = await openIncidentStore(directory, { policy: p });
  const next = await restart.claimRepair(key, { owner: 'next', baseRevision: 'base', ttlMs: 500 }, NOW + 4000);
  assert.equal(next.claim.token, old.token + 1);
  await assert.rejects(() => restart.fenceRepair(old, { baseRevision: 'base' }, NOW + 4100), /transaction failed/);
  assert.equal((await restart.read()).lease.token, next.claim.token);
});

test('malformed store, symlink, orphan lock and unsafe mutation fail closed, preserving accepted state', async t => {
  const directory = await temporary(t), p = policy(), key = incidentKey(receipt());
  const store = await openIncidentStore(directory, { policy: p, lockTimeoutMs: 30 });
  await store.transact(() => ({ state: confirmed(p) }));
  const original = await store.read();
  await assert.rejects(() => store.transact(state => { delete state.incidents[key]; return { state }; }));
  assert.deepEqual(await store.read(), original);
  await assert.rejects(() => store.transact(state => { state.rawUrl = 'private'; return { state }; }));
  assert.deepEqual(await store.read(), original);
  await fs.mkdir(path.join(directory, '.incident-lock'));
  await fs.writeFile(path.join(directory, '.incident-lock', 'owner.json'), JSON.stringify({ pid: 2147483000, nonce: 'dead' }));
  await assert.rejects(() => store.observe(receipt(), NOW), /deadline exceeded/);
  assert.deepEqual(await store.read(), original);
  await fs.unlink(path.join(directory, '.incident-lock', 'owner.json')); await fs.rmdir(path.join(directory, '.incident-lock'));
  await fs.writeFile(path.join(directory, 'incident-ledger.json'), '{corrupt');
  await assert.rejects(() => store.read(), /unreadable/);
  await assert.rejects(() => store.claimRepair(key, { owner: 'bad', baseRevision: 'base' }, NOW));
  await fs.unlink(path.join(directory, 'incident-ledger.json'));
  await fs.symlink(path.join(directory, 'nonexistent'), path.join(directory, 'incident-ledger.json'));
  await assert.rejects(() => store.read(), /unreadable/);
});

test('persisted unadmitted/private/corrupt records are rejected and capacity survives restart', async t => {
  const p = policy(), state = confirmed(p), key = incidentKey(receipt());
  for (const change of [record => record.source = 'other', record => record.rawUrl = 'private', record => record.failureCount = 999,
    record => record.firstFailureAt = 'yesterday', record => record.expected.headers = 'private']) {
    const invalid = structuredClone(state); change(invalid.incidents[key]); assert.throws(() => validateLedger(invalid, p));
  }
  const directory = await temporary(t), small = policy({ limits: { active: 1 } });
  let store = await openIncidentStore(directory, { policy: small });
  await store.transact(() => ({ state: confirmed(small) }));
  await store.observe(receipt({ facts: { status: 403 }, observedAt: new Date(NOW + 3000).toISOString() }), NOW + 3000);
  store = await openIncidentStore(directory, { policy: small });
  assert.ok((await store.read()).overflow);
  assert.equal((await store.claimRepair(key, { owner: 'bad', baseRevision: 'base' }, NOW + 4000)).claim, null);
});

test('fresh observer checks confirm a 75-minute missed heartbeat and recover only fresh matching dimensions', () => {
  const p = policy({ windowMs: 300000, maxReceiptAgeMs: 600000 });
  const spec = { environment: 'qualification', source: 'observer', stage: 'liveness', activation: 'active',
    intervalMs: 3600000, graceMs: 900000, startedAt: NOW, lastCompletedAt: NOW,
    lastAttemptedAt: NOW, lastAcceptedAt: NOW, requiresAccepted: true, versions };
  let state = emptyLedger(p); const events = [];
  for (const elapsed of [4800000, 5100000, 5400000]) {
    for (const observation of missedRunObservations(spec, NOW + elapsed)) {
      assert.equal(observation.checkedAt, observation.observedAt);
      assert.equal(observation.lastHeartbeatAt, new Date(NOW).toISOString());
      const result = applyObservation(state, observation, p, NOW + elapsed);
      assert.notEqual(result.result, 'stale'); state = result.state; events.push(...result.events);
    }
  }
  assert.equal(events.length, 3);
  assert.ok(Object.values(state.incidents).every(record => record.state === 'confirmed'));
  // A fresh completed/attempted heartbeat does not borrow recovery for stale
  // accepted data, even though all three receipts share a source and stage.
  for (const elapsed of [5700000, 6000000]) {
    const fresh = { ...spec, lastCompletedAt: NOW + elapsed, lastAttemptedAt: NOW + elapsed };
    for (const observation of missedRunObservations(fresh, NOW + elapsed)) state = applyObservation(state, observation, p, NOW + elapsed).state;
  }
  const dimensions = Object.fromEntries(Object.values(state.incidents).map(record => [record.facts.dimension, record.state]));
  assert.deepEqual(dimensions, { completed: 'resolved', attempted: 'resolved', accepted: 'confirmed' });
  assert.equal(listNotifications(state, p).filter(event => event.type === 'resolved').length, 2);
});

test('retained notifications survive failed delivery, duplicate probes and restart with exact stable IDs', async t => {
  const directory = await temporary(t), p = policy(); let store = await openIncidentStore(directory, { policy: p });
  for (let index = 0; index < 3; index++) await store.observe(receipt({ observedAt: new Date(NOW + index * 1000).toISOString() }), NOW + index * 1000);
  const pending = listNotifications(await store.read(), p);
  assert.equal(pending.length, 1); assert.equal(pending[0].id, 'qualification:notice:1');
  await assert.rejects(async () => { throw new Error('Synthetic failed issue delivery'); });
  store = await openIncidentStore(directory, { policy: p });
  assert.deepEqual(listNotifications(await store.read(), p), pending);
  await store.observe(receipt({ observedAt: new Date(NOW + 3000).toISOString() }), NOW + 3000);
  assert.deepEqual(listNotifications(await store.read(), p), pending);
  for (const elapsed of [4000, 5000]) await store.observe(receipt({ outcome: 'success', observedAt: new Date(NOW + elapsed).toISOString() }), NOW + elapsed);
  const notices = listNotifications(await store.read(), p);
  assert.deepEqual(notices.map(event => [event.id, event.type]), [['qualification:notice:1', 'confirmed'], ['qualification:notice:2', 'resolved']]);
  assert.deepEqual(Object.keys(notices[0]).sort(), ['failureClass', 'generation', 'id', 'key', 'scope', 'source', 'stage', 'time', 'type']);
  assert.equal(JSON.stringify(notices).includes('a'.repeat(64)), false);
  await assert.rejects(() => store.transact(state => { state.outbox.shift(); return { state }; }));
  assert.deepEqual(listNotifications(await store.read(), p), notices);
});

test('outbox saturation preserves undelivered notices and active facts, emits one durable sticky capacity notice', async t => {
  const directory = await temporary(t), p = policy({ limits: { outbox: 1 } });
  let store = await openIncidentStore(directory, { policy: p });
  await store.transact(() => ({ state: confirmed(p) }));
  await store.observe(receipt({ outcome: 'success', observedAt: new Date(NOW + 3000).toISOString() }), NOW + 3000);
  const prior = await store.read();
  const result = await store.observe(receipt({ outcome: 'success', observedAt: new Date(NOW + 4000).toISOString() }), NOW + 4000);
  assert.equal(result.result, 'overflow'); assert.equal(result.state.overflow.reason, 'outbox_capacity');
  assert.deepEqual(result.state.incidents, prior.incidents);
  assert.deepEqual(result.state.outbox, prior.outbox);
  assert.deepEqual(listNotifications(result.state, p).map(event => [event.id, event.type]), [['qualification:notice:1', 'confirmed'], ['qualification:notice:2', 'overflow']]);
  store = await openIncidentStore(directory, { policy: p });
  assert.equal((await store.observe(receipt({ outcome: 'success', observedAt: new Date(NOW + 5000).toISOString() }), NOW + 5000)).events.length, 0);
  assert.equal((await store.claimRepair(incidentKey(receipt()), { owner: 'denied', baseRevision: 'base' }, NOW + 5000)).claim, null);
  const saved = await store.read();
  for (const change of [state => state.notificationSequence++, state => state.outbox[0].id = saved.overflow.notice.id,
    state => state.outbox[0].scope = 'https://private.invalid', state => state.overflow = null]) {
    const invalid = structuredClone(saved); change(invalid); assert.throws(() => validateLedger(invalid, p, saved));
  }
});

test('resolved summary compaction preserves durable notices and just-resolved transition at equal timestamps', () => {
  const p = policy({ limits: { resolved: 1, resolvedAgeMs: 10000 } });
  let state = confirmed(p);
  state = observe(state, p, 3, { outcome: 'success' }).state;
  state = observe(state, p, 4, { outcome: 'success' }).state;
  const second = receipt({ stage: 'catalog', facts: { status: 403 } });
  for (const elapsed of [5000, 6000, 7000]) {
    state = applyObservation(state, { ...second, observedAt: new Date(NOW + 4000).toISOString(), checkedAt: new Date(NOW + elapsed).toISOString() }, p, NOW + elapsed).state;
  }
  for (const elapsed of [8000, 9000]) {
    state = applyObservation(state, { ...second, outcome: 'success', observedAt: new Date(NOW + 4000).toISOString(), checkedAt: new Date(NOW + elapsed).toISOString() }, p, NOW + elapsed).state;
  }
  assert.equal(Object.keys(state.incidents).length, 1);
  assert.equal(state.incidents[incidentKey(second)].state, 'resolved');
  assert.equal(listNotifications(state, p).length, 4);
  state = applyObservation(state, receipt({ source: 'streamex', outcome: 'success', observedAt: new Date(NOW + 20000).toISOString() }), p, NOW + 20000).state;
  assert.equal(Object.keys(state.incidents).length, 0);
  assert.equal(listNotifications(state, p).length, 4);
});

test('notification projection remains a fixed scalar shape for non-string normalized scope facts', () => {
  const p = policy(); let state = emptyLedger(p);
  for (let elapsed = 0; elapsed < 3; elapsed++) state = observe(state, p, elapsed, { facts: { scope: 2, competition: null, status: 530 } }).state;
  assert.equal(listNotifications(state, p)[0].scope, 'source');
});

test('active capacity also applies when a resolved identity reopens', () => {
  const p = policy({ limits: { active: 1 } }); let state = confirmed(p);
  state = observe(state, p, 3, { outcome: 'success' }).state;
  state = observe(state, p, 4, { outcome: 'success' }).state;
  state = observe(state, p, 5, { facts: { status: 403 } }).state;
  const prior = structuredClone(state);
  const result = observe(state, p, 6);
  assert.equal(result.result, 'overflow'); assert.equal(result.state.overflow.reason, 'active_capacity');
  assert.deepEqual(result.state.incidents, prior.incidents); validateLedger(result.state, p);
});

test('stale precomputed state and failed atomic rename grant no authority or lost accepted ledger', async t => {
  const directory = await temporary(t), p = policy(), store = await openIncidentStore(directory, { policy: p });
  await store.transact(() => ({ state: confirmed(p) }));
  const stale = await store.read();
  await store.observe(receipt({ observedAt: new Date(NOW + 3000).toISOString() }), NOW + 3000);
  const previous = await store.read();
  await assert.rejects(() => store.transact(() => ({ state: stale })), /no repair authority/);
  assert.deepEqual(await store.read(), previous);
  const rename = fs.rename;
  try {
    fs.rename = async () => { throw new Error('Synthetic disk rename failure'); };
    await assert.rejects(() => store.claimRepair(incidentKey(receipt()), { owner: 'no-authority', baseRevision: 'base' }, NOW + 4000), /no repair authority/);
  } finally { fs.rename = rename; }
  assert.deepEqual(await store.read(), previous);
  assert.deepEqual((await fs.readdir(directory)).sort(), ['incident-ledger.json']);
  assert.equal((await store.claimRepair(incidentKey(receipt()), { owner: 'next', baseRevision: 'base' }, NOW + 4000)).result, 'claimed');
});

test('persisted collection types and loose date strings cannot conceal private data or malformed state', () => {
  const p = policy(), state = confirmed(p);
  for (const field of ['incidents', 'coverage', 'lease', 'overflow']) {
    for (const scalar of [true, 1, 'private']) {
      const invalid = structuredClone(state); invalid[field] = scalar;
      assert.throws(() => validateLedger(invalid, p));
    }
  }
  for (const observedAt of ['2026-10-11', '2026-10-11T00:00:00Z (private)', 'yesterday']) {
    assert.throws(() => observe(state, p, 3, { observedAt }));
  }
  assert.equal(applyObservation(emptyLedger(p), receipt({ observedAt: '2026-10-11T00:00:00+00:00' }), p, NOW).result, 'failure');
});
