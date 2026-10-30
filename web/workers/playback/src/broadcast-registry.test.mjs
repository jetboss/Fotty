import test from "node:test";
import assert from "node:assert/strict";
import { BroadcastRegistry, DEFAULT_BROADCAST_REGISTRY_PROVIDERS } from "./broadcast-registry.mjs";

const initial = Date.parse("2026-10-30T11:30:00.000Z"), key = "shared-broadcast-registry-v1";
function harness({ providers = DEFAULT_BROADCAST_REGISTRY_PROVIDERS.slice(0, 2), collect, failWrites = false, fixtures: fixtureLoader } = {}) {
  let now = initial, alarm = null, reads = 0, enabled = true;
  const values = new Map(), calls = [];
  const storage = { get: async (id) => structuredClone(values.get(id)), put: async (id, value) => {
    if (failWrites) throw new Error("write-failed"); values.set(id, structuredClone(value));
  }, setAlarm: async (at) => { alarm = at; }, deleteAlarm: async () => { alarm = null; } };
  const fixtures = () => fixtureLoader ? fixtureLoader(now) : [{ fixtureID: "sports-fixture:premier-league:123", sport: "football", participants: ["Liverpool", "Chelsea"],
    start: new Date(now - 30 * 60_000).toISOString(), status: "live", observedAt: new Date(now).toISOString(), verified: true }];
  const reply = (code, changes = {}) => ({ providerCode: code, observedAt: new Date(now).toISOString(), complete: true,
    scopes: [{ scope: "football", status: "available", complete: true }], cursor: 1,
    broadcasts: [{ providerEventID: code + "_one", streamID: code + "_one", resourceType: "tv", scope: "football", kind: "event", sport: "football",
      title: "Liverpool vs Chelsea", participants: ["Liverpool", "Chelsea"], start: fixtures()[0].start,
      verification: "dated", observedAt: new Date(now).toISOString(), expiresAt: new Date(now + 30 * 60_000).toISOString() }], ...changes });
  const options = { providers, enabled: () => enabled, clock: () => new Date(now), loadFixtures: async () => fixtures(),
    collect: async (code, context) => {
      calls.push(code);
      if (!fixtureLoader) {
        assert.equal(context.fixtures[0].fixtureID, "sports-fixture:premier-league:123");
        assert.deepEqual(context.fixtures[0].participants, ["Liverpool", "Chelsea"]);
        assert.equal(context.fixtures[0].verified, true);
      }
      if (collect) return collect(code, context, { reply, values, read: () => { reads++; }, now: () => now });
      assert.equal(await context.reserveRequest(), true);
      assert.ok(values.get(key).budgets[code].count >= 1, "The durable reservation precedes its HTTP read");
      reads++;
      return reply(code);
    } };
  const create = () => new BroadcastRegistry({ storage }, {}, options);
  return { create, values, calls, reply, get now() { return now; }, set now(value) { now = value; },
    get alarm() { return alarm; }, get reads() { return reads; }, set enabled(value) { enabled = value; } };
}

test("durable refresh serializes duplicate owners and reads never start before durable budget reservation", async () => {
  const h = harness(), registry = h.create();
  const [first, second] = await Promise.all([registry.fetch(new Request("https://internal/refresh", { method: "POST" })),
    registry.fetch(new Request("https://internal/refresh", { method: "POST" }))]);
  assert.equal(first.status, 200); assert.equal(second.status, 200);
  assert.equal(h.reads, 2); assert.equal(h.calls.length, 2);
  const snapshot = await first.json(); assert.equal(snapshot.links.length, 2);
  assert.ok(snapshot.links.every((l) => l.state === "listed"));
  assert.equal(h.values.get(key).providers.streamex.cursor, 1);
  const before = h.reads;
  const read = await registry.fetch(new Request("https://internal/snapshot"));
  assert.equal(read.status, 200); assert.equal(h.reads, before, "Snapshot GET never initiates provider HTTP collection");
});

test("bounded alarm continuation covers seven providers without duplicate collection or a busy loop", async () => {
  const h = harness({ providers: DEFAULT_BROADCAST_REGISTRY_PROVIDERS }), registry = h.create();
  await registry.refresh(); assert.equal(h.calls.length, 2); assert.equal(h.alarm, h.now + 15_000);
  for (const count of [4, 6, 7]) {
    h.now = h.alarm;
    await registry.alarm(); assert.equal(h.calls.length, count);
  }
  assert.equal(h.alarm, null);
  await registry.alarm(); assert.equal(h.calls.length, 7);
  assert.equal(new Set(h.calls).size, 7);
  for (const budget of Object.values(h.values.get(key).budgets)) assert.equal(budget.count, 1);
});

test("actual HTTP caps survive restart, failed collection and duplicate alarms", async () => {
  const h = harness({ providers: [{ providerCode: "communitysports", maxRequestsPerDay: 1 }],
    collect: async (_code, context, state) => {
      assert.equal(await context.reserveRequest(), true); state.read();
      assert.equal(await context.reserveRequest(), false);
      throw new Error("budget-exhausted");
    } });
  await h.create().refresh(); assert.equal(h.reads, 1);
  const record = h.values.get(key).providers.communitysports;
  assert.equal(record.scopes.live.failure, "budget-exhausted");
  await h.create().alarm(); assert.equal(h.reads, 1); assert.equal(h.alarm, null);
  h.now += 24 * 60 * 60_000;
  await h.create().refresh(); assert.equal(h.reads, 2);
  assert.equal(h.values.get(key).budgets.communitysports.count, 1);
});

test("one failed provider preserves accepted records and healthy independent sibling progress", async () => {
  let failing = false;
  const h = harness({ providers: [{ providerCode: "communitysports", maxRequestsPerDay: 288 }, { providerCode: "plaviosports", maxRequestsPerDay: 288 }],
    collect: async (code, context, state) => {
      assert.equal(await context.reserveRequest(), true); state.read();
      if (failing && code === "communitysports") throw new Error("source-unavailable");
      return state.reply(code);
    } });
  const first = await h.create().refresh(), original = first.broadcasts.find((b) => b.providerCode === "communitysports");
  failing = true; h.now += 5 * 60_000;
  const next = await h.create().refresh();
  const kept = next.broadcasts.find((b) => b.providerCode === "communitysports");
  assert.deepEqual(kept, original);
  assert.equal(next.providers.find((p) => p.providerCode === "communitysports").failure, "source-unavailable");
  const retainedLink = next.links.find((p) => p.providerCode === "communitysports");
  assert.equal(retainedLink.state, "listed", "A catalog failure alone does not revoke a still-current accepted identity");
  assert.ok(Date.parse(retainedLink.expiresAt) <= Date.parse(original.expiresAt), "No old listing receipt is renewed");
  assert.equal(next.links.find((p) => p.providerCode === "plaviosports").state, "listed");
  assert.notEqual(next.broadcasts.find((b) => b.providerCode === "plaviosports").observedAt, original.observedAt);
});

test("partial catalogs refresh only observed IDs and never infer disappearance or renew unobserved rows", async () => {
  let partial = false;
  const h = harness({ providers: [{ providerCode: "communitysports", maxRequestsPerDay: 288 }],
    collect: async (code, context, state) => {
      assert.equal(await context.reserveRequest(), true); state.read();
      const response = state.reply(code), sibling = { ...response.broadcasts[0], providerEventID: "second", streamID: "second" };
      if (partial) return { ...response, complete: false, scopes: [{ scope: "football", status: "partial", complete: false }] };
      return { ...response, broadcasts: [...response.broadcasts, sibling] };
    } });
  const first = await h.create().refresh(), sibling = first.broadcasts.find((b) => b.providerEventID === "second");
  partial = true; h.now += 5 * 60_000;
  const next = await h.create().refresh();
  assert.equal(next.broadcasts.length, 2);
  assert.equal(next.providers[0].status, "partial");
  assert.deepEqual(next.broadcasts.find((b) => b.providerEventID === "second"), sibling);
  assert.ok(next.links.every((l) => l.state === "listed"));
});

test("failed reservation writes fence all upstream reads and corrupt budget state fails closed", async () => {
  const h = harness({ failWrites: true });
  const response = await h.create().fetch(new Request("https://internal/refresh", { method: "POST" }));
  assert.equal(response.status, 503); assert.equal(h.reads, 0);
  const bad = harness();
  bad.values.set(key, { version: 1, cursor: 0, providers: {}, budgets: { communitysports: { day: "bad", count: 0, lastAt: initial } } });
  assert.equal((await bad.create().fetch(new Request("https://internal/snapshot"))).status, 503);
  assert.equal(bad.reads, 0);
  const poisoned = harness();
  await poisoned.create().refresh();
  const state = poisoned.values.get(key);
  state.providers.streamex.records[0].url = "https://private.example/media?token=secret";
  poisoned.values.set(key, state);
  const response2 = await poisoned.create().fetch(new Request("https://internal/snapshot"));
  assert.equal(response2.status, 503);
  assert.equal((await response2.text()).includes("private.example"), false, "Unexpected stored media fields never reach a public snapshot");
});

test("clock rollback never resets daily allowances or schedules repeated immediate retries", async () => {
  const h = harness({ providers: [{ providerCode: "communitysports", maxRequestsPerDay: 288 }] });
  await h.create().refresh(); const before = structuredClone(h.values.get(key).budgets);
  h.now -= 60_000;
  await h.create().alarm();
  assert.equal(h.reads, 1); assert.deepEqual(h.values.get(key).budgets, before); assert.equal(h.alarm, null);
});

test("capacity rejection preserves accepted siblings, reports the rejected source and keeps spent reads", async () => {
  const h = harness({ providers: DEFAULT_BROADCAST_REGISTRY_PROVIDERS.slice(0, 3),
    collect: async (code, context, state) => {
      assert.equal(await context.reserveRequest(), true); state.read();
      const response = state.reply(code), template = response.broadcasts[0];
      return { ...response, broadcasts: Array.from({ length: 1500 }, (_, index) => ({ ...template,
        providerEventID: `${code}_${index}`, streamID: `${code}_${index}` })) };
    } });
  const first = await h.create().refresh();
  assert.equal(first.broadcasts.length, 3000);
  h.now += 15_000;
  const next = await h.create().refresh();
  assert.equal(next.broadcasts.length, 3000);
  assert.deepEqual(next.broadcasts, first.broadcasts);
  const rejected = next.providers.find((p) => p.providerCode === "communitysports");
  assert.equal(rejected.failure, "capacity-exceeded"); assert.equal(rejected.status, "failed");
  assert.equal(h.values.get(key).budgets.communitysports.count, 1);
  assert.equal(h.values.get(key).providers.communitysports.records.length, 0);
});

test("each source cycle has an independent eight-read ceiling before its daily allowance", async () => {
  const h = harness({ providers: [{ providerCode: "communitysports", maxRequestsPerDay: 288 }],
    collect: async (code, context, state) => {
      for (let index = 0; index < 8; index++) { assert.equal(await context.reserveRequest(), true); state.read(); }
      assert.equal(await context.reserveRequest(), false);
      return state.reply(code);
    } });
  await h.create().refresh(); assert.equal(h.reads, 8); assert.equal(h.values.get(key).budgets.communitysports.count, 8);
});

test("disabling collection fences a pending alarm without erasing accepted records or budgets", async () => {
  const h = harness({ providers: DEFAULT_BROADCAST_REGISTRY_PROVIDERS }), registry = h.create();
  await registry.refresh(); assert.equal(h.reads, 2); assert.ok(h.alarm);
  const before = structuredClone(h.values.get(key));
  h.enabled = false; h.now += 15_000;
  await registry.alarm();
  assert.equal(h.reads, 2); assert.equal(h.alarm, null); assert.deepEqual(h.values.get(key), before);
});

test("a late published football listing is found at the grouped pre-kickoff checkpoint by moving, not adding, the next cycle", async () => {
  const kickoff = initial + 21 * 60_000;
  const h = harness({ providers: [{ providerCode: "plaviosports", maxRequestsPerDay: 288 }],
    fixtures: (now) => [
      { fixtureID: "sports-fixture:premier-league:123", sport: "football", competitionID: "premier-league",
        participants: ["Liverpool", "Chelsea"], start: new Date(kickoff).toISOString(), status: "scheduled", observedAt: new Date(now).toISOString(), verified: true },
      { fixtureID: "sports-fixture:premier-league:456", sport: "football", competitionID: "premier-league",
        participants: ["Everton", "Arsenal"], start: new Date(kickoff).toISOString(), status: "scheduled", observedAt: new Date(now).toISOString(), verified: true },
    ],
    collect: async (code, context, state) => {
      assert.ok(context.fixtures.every((f) => f.status === "scheduled"), "Scheduling never upgrades kickoff into LIVE");
      for (let index = 0; index < 6; index++) { assert.equal(await context.reserveRequest(), true); state.read(); }
      return state.now() < kickoff - 20 * 60_000
        ? state.reply(code, { broadcasts: [], scopes: [{ scope: "football", status: "empty", complete: true }] })
        : state.reply(code);
    } });
  const first = await h.create().refresh();
  assert.equal(first.links.length, 0); assert.equal(h.reads, 6);
  assert.equal(Date.parse(h.values.get(key).providers.plaviosports.nextAttemptAt), initial + 30 * 60_000);
  h.now = kickoff - 6 * 60_000;
  await h.create().refresh(); assert.equal(h.reads, 6, "The checkpoint cannot run before its window");
  h.now = kickoff - 5 * 60_000;
  const found = await h.create().refresh();
  assert.equal(found.links.filter((l) => l.state === "listed").length, 1); assert.equal(h.reads, 12);
  const source = h.values.get(key).providers.plaviosports;
  assert.equal(source.kickoffCheckpoint.start, kickoff);
  assert.equal(source.kickoffCheckpoint.takenAt, h.now);
  assert.equal(Date.parse(source.nextAttemptAt), initial + 60 * 60_000,
    "The old30-minute slot is skipped to repay the one early cycle");
  h.now += 60_000;
  await Promise.all([h.create().refresh(), h.create().fetch(new Request("https://internal/snapshot"))]);
  assert.equal(h.reads, 12, "Restart and duplicate delivery do not repeat either match's grouped checkpoint");
  h.now = initial + 30 * 60_000;
  await h.create().refresh(); assert.equal(h.reads, 12, "There is no extra collection in the moved background slot");
  h.now = initial + 60 * 60_000;
  await h.create().refresh(); assert.equal(h.reads, 18, "At the next ordinary slot the total equals three original cycles");
});

test("a live cricket Test does not accelerate football-only, UCL-only or NHL-only provider collection", async () => {
  const codes = ["score808", "streamvix", "cncsports", "plaviosports"];
  const h = harness({ providers: codes.map((providerCode) => ({ providerCode, maxRequestsPerDay: providerCode === "plaviosports" ? 288 : 96 })),
    fixtures: (now) => [{ fixtureID: "cricket-fixture:icc:123", sport: "cricket", competitionID: "icc", format: "Test",
      participants: ["South Africa", "Australia"], start: new Date(initial - 2 * 86_400_000).toISOString(),
      status: "live", observedAt: new Date(now).toISOString(), verified: true }] });
  await h.create().refresh();
  h.now = h.alarm; await h.create().alarm();
  const sources = h.values.get(key).providers;
  for (const code of codes.slice(0, 3)) assert.equal(Date.parse(sources[code].nextAttemptAt) - Date.parse(sources[code].lastAttemptAt), 4 * 60 * 60_000);
  assert.equal(Date.parse(sources.plaviosports.nextAttemptAt) - Date.parse(sources.plaviosports.lastAttemptAt), 5 * 60_000);
  h.now = initial + 6 * 60_000;
  await h.create().refresh();
  assert.equal(h.calls.filter((code) => code !== "plaviosports").length, 3);
});

test("checkpoint debt survives failed collection, restart, clock rollback and disable/re-enable without refunding reads", async () => {
  const kickoff = initial + 21 * 60_000;
  let fail = false;
  const h = harness({ providers: [{ providerCode: "communitysports", maxRequestsPerDay: 288 }],
    fixtures: (now) => [{ fixtureID: "sports-fixture:premier-league:123", sport: "football", competitionID: "premier-league",
      participants: ["Liverpool", "Chelsea"], start: new Date(kickoff).toISOString(), status: "scheduled", observedAt: new Date(now).toISOString(), verified: true }],
    collect: async (code, context, state) => {
      if (fail) {
        const committed = state.values.get(key).providers[code];
        assert.equal(committed.kickoffCheckpoint.start, kickoff, "The window is durably consumed before any checkpoint HTTP read");
        assert.equal(Date.parse(committed.nextAttemptAt), initial + 80 * 60_000);
      }
      for (let index = 0; index < 8; index++) { assert.equal(await context.reserveRequest(), true); state.read(); }
      if (fail) throw new Error("source-unavailable");
      return state.reply(code);
    } });
  await h.create().refresh();
  fail = true; h.now = kickoff - 5 * 60_000;
  await h.create().refresh(); assert.equal(h.reads, 16);
  const spent = structuredClone(h.values.get(key));
  assert.equal(Date.parse(spent.providers.communitysports.nextAttemptAt), initial + 80 * 60_000);
  h.now -= 60_000;
  await h.create().alarm(); assert.equal(h.reads, 16); assert.equal(h.alarm, null);
  assert.deepEqual(h.values.get(key).budgets, spent.budgets);
  h.enabled = false; await h.create().alarm();
  h.enabled = true; h.now = kickoff - 60_000;
  await h.create().refresh();
  assert.equal(h.reads, 16); assert.deepEqual(h.values.get(key).providers.communitysports.kickoffCheckpoint, spent.providers.communitysports.kickoffCheckpoint);
});

test("an ordinary due collection in the checkpoint window consumes that group without another early repeat", async () => {
  const kickoff = initial + 5 * 60_000;
  const h = harness({ providers: [{ providerCode: "communitysports", maxRequestsPerDay: 288 }],
    fixtures: (now) => [{ fixtureID: "sports-fixture:premier-league:123", sport: "football", competitionID: "premier-league",
      participants: ["Liverpool", "Chelsea"], start: new Date(kickoff).toISOString(), status: "scheduled", observedAt: new Date(now).toISOString(), verified: true }],
    collect: async (code, context, state) => {
      for (let index = 0; index < 8; index++) { assert.equal(await context.reserveRequest(), true); state.read(); }
      return state.reply(code);
    } });
  await h.create().refresh();
  h.now += 60_000; await h.create().refresh();
  assert.equal(h.reads, 8, "First admission must not create a second pre-kickoff read");
  assert.equal(Date.parse(h.values.get(key).providers.communitysports.nextAttemptAt), initial + 40 * 60_000);
});
