import test from "node:test";
import assert from "node:assert/strict";
import { selectCSDeliveryFixture, selectCSCatalogMatch, classifyCSDeliveryDescriptor, probeCSDeliveryContract } from "./delivery-contract.mjs";
import { createPolicy, emptyLedger } from "./incident-policy.mjs";
import { applyObservationBatch } from "./observation-batch.mjs";
import { EXPECTED_VERSIONS } from "./manifest.mjs";

const NOW = Date.parse("2026-10-28T21:00:00Z"), iso = (time = NOW) => new Date(time).toISOString();
const copy = (value) => structuredClone(value);
function fixture(overrides = {}) { return { id: "sports-fixture:carabao-cup:fixture", sport: "football", competitionId: "carabao-cup",
  competitionName: "Carabao Cup", status: "live", eventKind: "match", start: "2026-10-28T20:00:00.000Z",
  participants: [{ id: "liverpool", name: "Liverpool" }, { id: "chelsea", name: "Chelsea" }],
  squad: { gender: "men", ageGroup: "senior" }, source: { observedAt: iso(), name: "Official", url: "https://official.example/schedule" }, ...overrides }; }
function snapshot(row = fixture()) { return { schemaVersion: 1, complete: true, checkedAt: iso(), sourceStatus: "verified",
  fixtures: [row], coverage: [{ competitionId: row.competitionId, sport: "football", status: "covered", checkedAt: row.source.observedAt }] }; }
const manifest = { resources: ["catalog", "stream"] };
function catalog(entry = {}) { return { metas: [{ id: "nuvio_sport_fixture", type: "tv", name: "🔴 LIVE: Liverpool vs Chelsea",
  cast: ["Liverpool", "Chelsea"], genres: ["FOOTBALL"], released: "2026-10-28T20:00:00.000Z", ...entry }] }; }
function wrapper(target = "https://video.example/live/master.m3u8?signature=fixture", path = "/api/manifest.m3u8", extra = {}) {
  return { url: `https://nuviosports.xyz${path}?url=${encodeURIComponent(target)}`, _source: "daddylive", ...extra };
}
const descriptor = (streams = [wrapper()]) => ({ streams });
async function probe(overrides = {}, response = descriptor()) {
  const calls = [];
  const rows = await probeCSDeliveryContract({ sportsSnapshot: snapshot(), catalog: catalog(), manifest, now: NOW,
    read: async (...args) => { calls.push(args); return { body: response }; }, ...overrides });
  return { rows, calls };
}

test("current fixture authority is explicit LIVE and fresh, never elapsed kickoff", () => {
  assert.equal(selectCSDeliveryFixture(snapshot(), NOW)?.competitionId, "carabao-cup");
  for (const status of ["scheduled", "finished", "postponed", "cancelled", "unknown"]) {
    assert.equal(selectCSDeliveryFixture(snapshot(fixture({ status })), NOW), null, status);
  }
  for (const changes of [
    { source: { observedAt: iso(NOW - 31 * 60_000) } },
    { source: { observedAt: iso(), updatedAt: iso(NOW - 31 * 60_000) } },
    { source: { observedAt: iso(NOW + 6 * 60_000), verification: "verified" } },
    { source: { observedAt: iso(), verification: "held" } },
    { source: { observedAt: iso(), verification: null } },
    { squad: { gender: "women", ageGroup: "senior" } }, { squad: { gender: "men", ageGroup: "u19" } },
    { start: iso(NOW - 5 * 3600_000) }, { start: "2026-10-28T24:00:00Z" },
  ]) assert.equal(selectCSDeliveryFixture(snapshot(fixture(changes)), NOW), null);
  const stale = snapshot(); stale.checkedAt = iso(NOW - 31 * 60_000);
  assert.equal(selectCSDeliveryFixture(stale, NOW), null);
  const duplicated = snapshot(); duplicated.fixtures.push(copy(duplicated.fixtures[0]));
  assert.equal(selectCSDeliveryFixture(duplicated, NOW), null);
});

test("partial cohorts require the explicit verified row rather than borrowing coverage", () => {
  const s = snapshot(); s.sourceStatus = "partial"; s.coverage[0].status = "unavailable";
  s.coverage[0].checkedAt = iso(NOW - 24 * 3600_000);
  assert.equal(selectCSDeliveryFixture(s, NOW), null);
  s.fixtures[0].source.verification = "verified";
  assert.ok(selectCSDeliveryFixture(s, NOW));
  s.sourceStatus = "last-known-good";
  assert.equal(selectCSDeliveryFixture(s, NOW), null);
});

test("catalog matching uses reviewed club aliases and explicit dated identity", () => {
  const f = fixture({ participants: [{ id: "bournemouth", name: "AFC Bournemouth" }, { id: "united", name: "Manchester United" }] });
  const c = catalog({ name: "LIVE: Bournemouth vs Man Utd", cast: ["Bournemouth", "Man Utd"] });
  assert.equal(selectCSCatalogMatch(f, c).outcome, "matched");
  assert.equal(selectCSCatalogMatch(fixture(), catalog({ released: "2026-10-29T01:00:00+05:00" })).outcome, "matched");
  for (const released of ["2026-10-29T20:00:00Z", "LIVE NOW", "2026-10-28T20:00:00", "2026-10-28T24:00:00Z"]) {
    assert.equal(selectCSCatalogMatch(fixture(), catalog({ released })).outcome, "missing", released);
  }
  const unknown = fixture({ participants: [{ id: "mystery", name: "Mystery FC" }, { id: "chelsea", name: "Chelsea" }] });
  assert.equal(selectCSCatalogMatch(unknown, catalog({ name: "Mystery vs Chelsea", cast: ["Mystery", "Chelsea"] })).outcome, "missing");
});

test("catalog title/cast squads and conflict siblings cannot be discarded", () => {
  for (const name of ["Liverpool Women vs Chelsea Women", "Liverpool U19 vs Chelsea U19", "Liverpool vs Chelsea | Final",
    "Liverpool vs Chelsea vs Arsenal", "Liverpool vs Arsenal"]) {
    assert.equal(selectCSCatalogMatch(fixture(), catalog({ name })).outcome, "missing", name);
  }
  const duplicated = catalog(); duplicated.metas.push(copy(duplicated.metas[0]));
  assert.equal(selectCSCatalogMatch(fixture(), duplicated).outcome, "matched");
  for (const mutation of [{ released: "2026-10-29T20:00:00Z" }, { genres: ["CRICKET"] }, { name: "Liverpool Women vs Chelsea Women" }, { cast: [42, "Chelsea"] }]) {
    const conflict = catalog(); conflict.metas.push({ ...copy(conflict.metas[0]), ...mutation });
    assert.equal(selectCSCatalogMatch(fixture(), conflict).outcome, "conflicting");
  }
  const differentID = catalog(); differentID.metas.push({ ...copy(differentID.metas[0]), id: "nuvio_sport_other" });
  assert.equal(selectCSCatalogMatch(fixture(), differentID).outcome, "conflicting");
});

test("old and new exact wrapper spellings are compatible candidate shapes without rewriting signatures", async () => {
  const old = wrapper(undefined, "/api/manifest"), alias = wrapper();
  const before = JSON.stringify([old, alias]);
  assert.deepEqual(await classifyCSDeliveryDescriptor(descriptor([old, alias])), {
    schemaValid: true, entryCount: 2, compatibleShapeCount: 2, compatibleHLSShapeCount: 2,
    compatibleWebShapeCount: 0, unsafeShapeCount: 0, unknownShapeCount: 0 });
  assert.equal(JSON.stringify([old, alias]), before);
});

test("same-origin alias must not launder HTTP, private, credential or exceptional-port targets", async () => {
  const targets = ["http://video.example:8008/live.m3u8", "http://video.example:2122/live.m3u8", "http://video.example/live.m3u8",
    "https://video.example:8443/live.m3u8", "https://user:secret@video.example/live.m3u8", "https://127.0.0.1/live.m3u8",
    "https://2130706433/live.m3u8", "https://[::1]/live.m3u8", "https://[2001:db8::1]/live.m3u8", "https://video.example/live.m3u8#"];
  const result = await classifyCSDeliveryDescriptor(descriptor(targets.map((target) => wrapper(target))));
  assert.equal(result.compatibleShapeCount, 0); assert.equal(result.unsafeShapeCount, targets.length);
  const duplicate = wrapper(); duplicate.url += "&URL=" + encodeURIComponent("https://video.example/other.m3u8");
  assert.equal((await classifyCSDeliveryDescriptor(descriptor([duplicate]))).unsafeShapeCount, 1);
});

test("lookalikes, normalized traversal and other delivery origins are unreviewed rather than admitted", async () => {
  const paths = ["/API/manifest.m3u8", "/api/%6danifest.m3u8", "/api/other/../manifest.m3u8", "/api/manifest.m3u8/",
    "/api/manifest.mpd", "/api/manifest.m3u8.evil", "/api//manifest.m3u8"];
  const rows = paths.map((path) => wrapper(undefined, path));
  rows.push({ url: "https://other.example/api/manifest.m3u8", _source: "daddylive" });
  const result = await classifyCSDeliveryDescriptor(descriptor(rows));
  assert.equal(result.compatibleShapeCount, 0); assert.equal(result.unknownShapeCount, rows.length);
});

test("reviewed direct CS route requires its existing exact public provenance headers", async () => {
  const direct = { url: "https://dai-fancode.pages.dev/mumbai/fixture_123/index.m3u8", _source: "sktech",
    behaviorHints: { proxyHeaders: { request: { Referer: "https://fancode.com/", "User-Agent": "ReactNativeVideo/9.11.1" } } } };
  assert.equal((await classifyCSDeliveryDescriptor(descriptor([direct]))).compatibleShapeCount, 1);
  for (const row of [{ ...direct, _source: "unknown" }, { ...direct, url: direct.url + "?token=fixture" },
    { ...direct, url: direct.url.replace(".dev/", ".dev:8443/") }, { ...direct, behaviorHints: {} },
    { ...direct, behaviorHints: { proxyHeaders: { request: { Cookie: "untrusted" } } } }]) {
    assert.equal((await classifyCSDeliveryDescriptor(descriptor([row]))).compatibleShapeCount, 0);
  }
  for (const behaviorHints of [[], "invalid", { proxyHeaders: { request: null } }, { proxyHeaders: { response: { "Access-Control-Allow-Origin": "*" } } }]) {
    assert.equal((await classifyCSDeliveryDescriptor(descriptor([{ ...wrapper(), behaviorHints }]))).unsafeShapeCount, 1);
  }
});

test("existing8443 exception requires its exact pinned host, attribution and three bound public headers", async () => {
  const row = wrapper("https://643t8a.7odxv0l067ka.net:8443/live/master.m3u8");
  const header = { Referer: "https://embed.example/player", Origin: "https://embed.example", "User-Agent": "Fixture Player" };
  row.url += "&referer=" + encodeURIComponent(header.Referer) + "&origin=" + encodeURIComponent(header.Origin);
  row.behaviorHints = { proxyHeaders: { request: header } };
  assert.equal((await classifyCSDeliveryDescriptor(descriptor([row]))).compatibleShapeCount, 1);
  for (const change of [{ _source: "unknown" }, { behaviorHints: {} }, { url: row.url.replace("643t8a.7odxv0l067ka.net", "other.example") }]) {
    assert.equal((await classifyCSDeliveryDescriptor(descriptor([{ ...row, ...change }]))).compatibleShapeCount, 0);
  }
});

test("descriptor candidate alternatives and hundred-row limit follow bounded native-like selection", async () => {
  const valid = wrapper(); valid.externalUrl = valid.url; valid.url = "http://unreviewed.example/live.m3u8";
  assert.equal((await classifyCSDeliveryDescriptor(descriptor([valid]))).compatibleShapeCount, 1);
  const result = await classifyCSDeliveryDescriptor(descriptor([...Array(100).fill({ url: "https://unknown.example/live.m3u8" }), wrapper()]));
  assert.equal(result.entryCount, 100); assert.equal(result.compatibleShapeCount, 0);
});

test("one current exact match permits only one fixed descriptor metadata request and redacted receipts", async () => {
  const { rows, calls } = await probe();
  assert.deepEqual(calls, [["/stream/tv/nuvio_sport_fixture.json", "delivery-contract"]]);
  assert.equal(rows[0].outcome, "success"); assert.equal(rows[0].failureClass, "delivery-contract-drift");
  assert.equal(rows[0].facts.dimension, "candidate-shape");
  assert.doesNotMatch(JSON.stringify(rows), /https:|Liverpool|Chelsea|nuvio_sport_|signature|decoded/);
  const s = snapshot(); s.fixtures.unshift(fixture({ id: "sports-fixture:carabao-cup:earlier", start: "2026-10-28T19:30:00Z",
    participants: [{ id: "arsenal", name: "Arsenal" }, { id: "everton", name: "Everton" }] }));
  const sample = await probe({ sportsSnapshot: s }); assert.equal(sample.calls.length, 1);
});

test("no eligible fixture, missing catalog pair, conflicts or unadvertised stream resource never request descriptors", async () => {
  for (const changes of [{ sportsSnapshot: snapshot(fixture({ status: "scheduled" })) }, { catalog: catalog({ released: "2026-10-29T20:00:00Z" }) },
    { catalog: { metas: [] } }, { manifest: { resources: ["catalog"] } }]) {
    const result = await probe(changes); assert.equal(result.calls.length, 0); assert.equal(result.rows[0].outcome, "unknown");
  }
  const c = catalog(); c.metas.push({ ...copy(c.metas[0]), released: "2026-10-29T20:00:00Z" });
  const result = await probe({ catalog: c }); assert.equal(result.calls.length, 0); assert.equal(result.rows[0].outcome, "unknown");
});

test("empty and budget-limited descriptors are UNKNOWN, while nonempty all-rejected deliveries flag stable drift", async () => {
  for (const body of [{ streams: [] }, {}, { streams: null }]) assert.equal((await probe({}, body)).rows[0].outcome, "unknown");
  const unknown = await probe({ read: async () => ({ failure: "budget-exhausted", unknown: true }) });
  assert.ok(unknown.rows.every((row) => row.outcome === "unknown"));
  const first = await probe({}, descriptor([{ url: "https://unreviewed.example/live.m3u8" }]));
  const next = await probe({}, descriptor([wrapper("http://video.example:2122/live.m3u8"), { url: "https://unreviewed.example/other" }]));
  assert.equal(first.rows[0].outcome, "failure"); assert.equal(next.rows[0].outcome, "failure");
  assert.deepEqual(first.rows[0].facts, next.rows[0].facts);
  const malformed = await probe({}, { streams: "not-a-list" });
  assert.equal(malformed.rows[0].outcome, "failure"); assert.equal(malformed.rows[0].failureClass, "descriptor-schema");
});

test("two actual descriptor transport or schema failures confirm without an UNKNOWN resetting their streak", async () => {
  const policy = createPolicy({ environment: "production", windowMs: 15 * 60_000, failureWindows: 2,
    admittedSources: [{ source: "cs", stages: ["delivery-contract"], activation: "active", expected: EXPECTED_VERSIONS }] });
  for (const kind of ["transport", "schema"]) {
    let state = emptyLedger(policy), events = [];
    for (let index = 0; index < 2; index++) {
      const at = NOW + index * 15 * 60_000;
      const result = await probe({ now: at, read: async () => kind === "transport" ? { failure: "deadline" } : { body: { streams: "invalid" } } });
      assert.equal(result.rows.length, 1); assert.equal(result.rows[0].outcome, "failure");
      const applied = applyObservationBatch(state, result.rows, policy, at);
      state = applied.state; events.push(...applied.events);
    }
    assert.equal(events.filter((event) => event.type === "confirmed").length, 1, kind);
    assert.equal(Object.values(state.incidents)[0].failureCount, 2, kind);
  }
});

test("web-only fallback is UNKNOWN and cannot claim native HLS contract recovery", async () => {
  const web = { url: "https://nuviosports.xyz/watch?fixture=published", _source: "web" };
  const shape = await classifyCSDeliveryDescriptor(descriptor([web]));
  assert.equal(shape.compatibleHLSShapeCount, 0); assert.equal(shape.compatibleWebShapeCount, 1);
  assert.equal((await probe({}, descriptor([web]))).rows[0].outcome, "unknown");
  assert.equal((await probe({}, descriptor([web, { url: "https://unreviewed.example/unknown" }]))).rows[0].outcome, "unknown");
  assert.equal((await probe({}, descriptor([web, wrapper()]))).rows[0].outcome, "success");
});

test("a confirmed route-shape incident survives empty/web-only windows and recovers only on two fresh HLS checks", async () => {
  const policy = createPolicy({ environment: "production", windowMs: 15 * 60_000, failureWindows: 2, recoveryWindows: 2,
    admittedSources: [{ source: "cs", stages: ["delivery-contract"], activation: "active", expected: EXPECTED_VERSIONS }] });
  let state = emptyLedger(policy); const events = [];
  const bodies = [descriptor([{ url: "https://unreviewed.example/live.m3u8" }]), descriptor([wrapper("http://video.example:8008/live.m3u8")]),
    descriptor([]), descriptor([{ url: "https://nuviosports.xyz/watch?fixture=published" }]), descriptor(), descriptor()];
  for (let index = 0; index < bodies.length; index++) {
    const at = NOW + index * 15 * 60_000, current = snapshot();
    current.checkedAt = iso(at); current.fixtures[0].source.observedAt = iso(at); current.coverage[0].checkedAt = iso(at);
    const result = await probe({ now: at, sportsSnapshot: current }, bodies[index]);
    const applied = applyObservationBatch(state, result.rows, policy, at); state = applied.state; events.push(...applied.events);
    if (index === 2 || index === 3) assert.equal(Object.values(state.incidents)[0].state, "confirmed");
    if (index === 4) assert.equal(Object.values(state.incidents)[0].state, "recovering");
  }
  assert.deepEqual(events.map((event) => event.type), ["confirmed", "resolved"]);
});
