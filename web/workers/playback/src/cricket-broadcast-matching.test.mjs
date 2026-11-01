import test from "node:test";
import assert from "node:assert/strict";
import { normalizeBroadcastCollection, normalizeRegistryFixtures, associateBroadcasts } from "./broadcast-registry-policy.mjs";

const now = new Date("2026-11-01T12:00:00.000Z");
const minute = 60_000, hour = 60 * minute;
const stamp = (offset = 0, at = now) => new Date(+at + offset).toISOString();
const fixture = (changes = {}, at = now) => ({
  fixtureID: "cricket-fixture:icc:test-fifth-odi", sport: "cricket", participants: ["Namibia", "Ireland"],
  start: "2026-11-01T07:30:00.000Z", competitionID: "icc", format: "ODI", matchOrdinal: 5, status: "live",
  observedAt: stamp(-minute, at), verified: true, ...changes,
});
const cs = (changes = {}, at = now) => ({
  providerEventID: "nuvio_sport_sktech_sktech_ev_fancode_4250335",
  streamID: "nuvio_sport_sktech_sktech_ev_fancode_4250335", resourceType: "tv", scope: "cricket",
  kind: "event", sport: "cricket", title: "🔴 LIVE: Ireland vs Namibia", participants: ["Ireland", "Namibia"],
  start: "2026-11-01T10:08:39.913Z", startBasis: "current-listing", verification: "undated", issues: [],
  observedAt: stamp(-2 * minute, at), expiresAt: stamp(hour, at), ...changes,
});
const programme = (changes = {}, at = now) => ({
  providerEventID: "reviewed-tv:programme:" + "a".repeat(64), streamID: "reviewed-tv:willow-main",
  resourceType: "tv", scope: "cricket", kind: "programme", sport: "cricket", title: "Namibia vs. Ireland",
  participants: ["Namibia", "Ireland"], format: "ODI", matchOrdinal: 5,
  start: stamp(-30 * minute, at), end: stamp(hour, at), channelID: "cricket-channel:willow",
  verification: "dated", issues: [], observedAt: stamp(-minute, at), expiresAt: stamp(9 * minute, at), ...changes,
});
async function source(rows, providerCode = "communitysports", at = now) {
  return normalizeBroadcastCollection(providerCode, { providerCode, observedAt: stamp(0, at), complete: true,
    scopes: [...new Set(rows.map((r) => r.scope))].map((scope) => ({ scope, status: "available", complete: true })),
    broadcasts: rows }, at);
}
async function joined(rows = [cs()], fixtures = [fixture()], providerCode = "communitysports", at = now) {
  const normalized = await source(rows, providerCode, at);
  return { source: normalized, links: associateBroadcasts({ fixtures, broadcasts: normalized.broadcasts,
    providers: normalized.scopes, now: at }) };
}
const listed = (result) => result.links.filter((link) => link.state === "listed");

test("CS synthetic current-listing time is retained separately from the one fresh live official kickoff", async () => {
  const result = await joined();
  assert.equal(result.source.broadcasts[0].startBasis, "current-listing");
  assert.equal(result.source.broadcasts[0].start, "2026-11-01T10:08:39.913Z");
  assert.equal(result.source.broadcasts[0].verification, "undated");
  assert.equal(result.source.broadcasts[0].format, undefined, "Official ODI is not fabricated as a provider claim");
  assert.equal(listed(result).length, 1);
  assert.equal(listed(result)[0].matchMethod, "current-event");
  assert.equal(listed(result)[0].fixtureFingerprint.start, fixture().start);
  assert.equal(listed(result)[0].fixtureFingerprint.format, "ODI");
  const refreshedClock = await joined([cs({ start: stamp(-10_000) })]);
  assert.equal(listed(refreshedClock).length, 1);
  assert.equal(listed(refreshedClock)[0].fixtureFingerprint.start, fixture().start);
  assert.equal(refreshedClock.source.broadcasts[0].id, result.source.broadcasts[0].id);
});

test("CS Live and Cricket cohorts may refresh one synthetic clock while retaining one exact event identity", async () => {
  const result = await joined([
    cs({ scope: "live", observedAt: stamp(-3 * minute) }),
    cs({ scope: "cricket", observedAt: stamp(-2 * minute), start: stamp(-minute) }),
  ]);
  assert.equal(result.source.broadcasts.length, 1);
  assert.equal(result.source.broadcasts[0].verification, "undated");
  assert.equal(result.source.broadcasts[0].start, stamp(-minute));
  assert.equal(listed(result).length, 1);
  const contradiction = await joined([
    cs({ scope: "live", observedAt: stamp(-3 * minute) }),
    cs({ scope: "cricket", observedAt: stamp(-2 * minute), start: stamp(-minute),
      title: "🔴 LIVE: Ireland vs Scotland", participants: ["Ireland", "Scotland"] }),
  ]);
  assert.equal(contradiction.source.broadcasts.length, 1);
  assert.equal(contradiction.source.broadcasts[0].verification, "conflicting");
  assert.ok(contradiction.source.broadcasts[0].issues.includes("catalog-conflict"));
  assert.equal(listed(contradiction).length, 0);
});

test("CS current-listing cannot promote scheduled, terminal, stale or unverified cricket fixtures", async () => {
  for (const change of [{ status: "scheduled" }, { status: "finished" }, { status: "cancelled" },
    { observedAt: stamp(-10 * minute - 1) }, { verified: false }, { start: stamp(minute) }]) {
    assert.equal(listed(await joined([cs()], [fixture(change)])).length, 0, JSON.stringify(change));
  }
});

test("CS current-listing needs one eligible occurrence and preserves women/youth and opponent identity", async () => {
  for (const fixtures of [
    [fixture(), fixture({ fixtureID: "cricket-fixture:icc:other", start: stamp(-hour) })],
    [fixture(), fixture({ fixtureID: "cricket-fixture:icc:earlier", status: "finished", start: stamp(-8 * hour) })],
    [fixture(), fixture()],
    [fixture({ participants: ["Namibia Women", "Ireland Women"] })],
    [fixture({ participants: ["Namibia U19", "Ireland U19"] })],
    [fixture({ participants: ["Namibia", "Netherlands"] })],
  ]) assert.equal(listed(await joined([cs()], fixtures)).length, 0);
  const women = await joined([cs({ title: "🔴 LIVE: Ireland Women vs Namibia Women", participants: ["Ireland Women", "Namibia Women"] })],
    [fixture({ participants: ["Namibia Women", "Ireland Women"] })]);
  assert.equal(listed(women).length, 1, "Explicit same-squad women fixtures remain supported");
});

test("CS current-listing is bounded to actual limited-overs windows and never acquires Test-day authority", async () => {
  for (const [format, limit] of [["ODI", 12 * hour], ["T20", 6 * hour]]) {
    assert.equal(listed(await joined([cs()], [fixture({ format, start: stamp(-limit + 1) })])).length, 1);
    assert.equal(listed(await joined([cs()], [fixture({ format, start: stamp(-limit - 1) })])).length, 0);
  }
  for (const format of ["Test", "T10"]) assert.equal(listed(await joined([cs()], [fixture({ format })])).length, 0);
});

test("the CS current-listing marker cannot be injected into another provider, ID, kind or claimed format", async () => {
  for (const changes of [
    { startBasis: "kickoff" }, { providerEventID: "nuvio_sport_ak47_match", streamID: "nuvio_sport_ak47_match" },
    { providerEventID: "nuvio_sport_sktech_sktech_ev_fancode_4250335_replay", streamID: "nuvio_sport_sktech_sktech_ev_fancode_4250335_replay" },
    { kind: "channel" }, { kind: "programme" }, { sport: "football" }, { scope: "networks" },
    { title: "Ireland vs Namibia" }, { title: "🔴 LIVE: Ireland vs Namibia Highlights" },
    { verification: "dated" }, { format: "ODI" }, { day: 1 }, { matchOrdinal: 5 },
  ]) await assert.rejects(source([cs(changes)]), /invalid-collection/u, JSON.stringify(changes));
  await assert.rejects(source([cs()], "plaviosports"), /invalid-collection/u);
  assert.equal(listed(await joined([cs({ scope: "live" })])).length, 1, "The reviewed Live cohort retains the same event identity");
});

test("CS missing or conflicting source evidence does not become Watch availability", async () => {
  for (const change of [
    { expiresAt: stamp(-1) }, { verification: "conflicting", issues: ["catalog-conflict"] },
    { issues: ["identity-conflict"] },
  ]) {
    let result;
    try { result = await joined([cs(change)]); }
    catch (error) { assert.match(error.message, /invalid-collection/u); continue; }
    assert.equal(listed(result).length, 0, JSON.stringify(change));
  }
  const ordinary = await joined([cs({ startBasis: undefined, verification: "dated", format: "ODI" })]);
  assert.equal(listed(ordinary).length, 0, "Ordinary explicit start timestamps still obey the existing time fence");
});

test("CS synthetic clock is bounded by its observation receipt instead of being treated as a future kickoff", async () => {
  const receipt = stamp(-2 * minute);
  for (const start of [stamp(-2 * minute + 5 * minute), stamp(-2 * minute - 4 * hour)]) {
    const result = await joined([cs({ observedAt: receipt, start })]);
    assert.equal(listed(result).length, 1);
    assert.equal(result.source.broadcasts[0].start, start);
    assert.equal(listed(result)[0].fixtureFingerprint.start, fixture().start);
  }
  for (const start of [stamp(-2 * minute + 5 * minute + 1), stamp(-2 * minute - 4 * hour - 1)])
    await assert.rejects(source([cs({ observedAt: receipt, start })]), /invalid-collection/u);
});

test("main-Willow limited-overs programme can start during its matching live fixture without rewriting either interval", async () => {
  const result = await joined([programme()], [fixture()], "reviewedtv");
  assert.equal(listed(result).length, 1);
  assert.equal(listed(result)[0].matchMethod, "programme");
  assert.equal(listed(result)[0].fixtureFingerprint.start, fixture().start);
  assert.equal(result.source.broadcasts[0].start, stamp(-30 * minute));
  assert.equal(result.source.broadcasts[0].matchOrdinal, 5);
  assert.equal(listed(result)[0].fixtureFingerprint.matchOrdinal, 5, "Only the separately verified official ordinal enters its fingerprint");
  const t20 = await joined([programme({ format: "T20", matchOrdinal: 3 })], [fixture({ format: "T20", matchOrdinal: 3 })], "reviewedtv");
  assert.equal(listed(t20).length, 1);
});

test("main-Willow ODI/T20 programme must agree with the separately verified official match ordinal", async () => {
  for (const [format, officialOrdinal] of [["ODI", 5], ["T20", 3]]) {
    const official = fixture({ format, matchOrdinal: officialOrdinal });
    const correct = await joined([programme({ format, matchOrdinal: officialOrdinal })], [official], "reviewedtv");
    assert.equal(listed(correct).length, 1);
    assert.equal(listed(correct)[0].fixtureFingerprint.matchOrdinal, officialOrdinal);
    const wrong = await joined([programme({ format, matchOrdinal: officialOrdinal - 1 })], [official], "reviewedtv");
    assert.equal(listed(wrong).length, 0);
    assert.equal(wrong.links[0].state, "conflicting"); assert.equal(wrong.links[0].reason, "ordinal-conflict");
    for (const [missing, rows] of [
      [fixture({ format, matchOrdinal: undefined }), [programme({ format, matchOrdinal: officialOrdinal })]],
      [official, [programme({ format, matchOrdinal: undefined })]],
    ]) {
      const result = await joined(rows, [missing], "reviewedtv");
      assert.equal(listed(result).length, 0); assert.equal(result.links[0].state, "needsVerification");
      assert.equal(result.links[0].reason, "ordinal-conflict");
    }
  }
  const current = await joined([cs()], [fixture()]);
  assert.equal(listed(current).length, 1, "CS does not invent a source ordinal from the official fixture");
  assert.equal(current.source.broadcasts[0].matchOrdinal, undefined);
  assert.equal(listed(current)[0].fixtureFingerprint.matchOrdinal, 5);
});

test("official registry ordinal normalization accepts only bounded typed Test/ODI/T20 ordinals", () => {
  for (const format of ["Test", "ODI", "T20"]) for (const matchOrdinal of [1, 5, 99]) {
    const rows = normalizeRegistryFixtures([fixture({ format, matchOrdinal })], now);
    assert.equal(rows.length, 1); assert.equal(rows[0].matchOrdinal, matchOrdinal);
  }
  for (const matchOrdinal of [0, -1, 100, 1.5, "5", null])
    assert.equal(normalizeRegistryFixtures([fixture({ matchOrdinal })], now).length, 0);
  assert.equal(normalizeRegistryFixtures([fixture({ format: "T10", matchOrdinal: 1 })], now).length, 0);
  const missing = normalizeRegistryFixtures([fixture({ matchOrdinal: undefined })], now);
  assert.equal(missing.length, 1); assert.equal(missing[0].matchOrdinal, undefined, "No ordinal inferred from fixture ID, pair, date or title");
});

test("main-Willow interval matching requires fresh current official status, format, pair and a unique occurrence", async () => {
  for (const fixtures of [
    [fixture({ status: "scheduled" })], [fixture({ status: "finished" })],
    [fixture({ observedAt: stamp(-10 * minute - 1) })], [fixture({ format: "T20" })],
    [fixture({ participants: ["Namibia Women", "Ireland Women"] })],
    [fixture(), fixture({ fixtureID: "cricket-fixture:icc:other", start: stamp(-hour) })],
    [fixture({ start: stamp(-12 * hour - 1) })],
  ]) assert.equal(listed(await joined([programme()], fixtures, "reviewedtv")).length, 0, JSON.stringify(fixtures));
});

test("main-Willow never borrows a future, ended, stale or contradictory programme interval", async () => {
  for (const change of [
    { start: stamp(minute) }, { end: stamp(-1) },
    { observedAt: stamp(-11 * minute), expiresAt: stamp(-minute) },
    { verification: "conflicting", issues: ["catalog-conflict"] },
    { format: "ODI", day: 1 },
  ]) {
    const result = await joined([programme(change)], [fixture()], "reviewedtv");
    assert.equal(listed(result).length, 0, JSON.stringify(change));
  }
});

test("main-Willow coverage up to sixty minutes early remains a separate programme interval", async () => {
  for (const lead of [0, 15, 30, 60]) {
    const official = fixture({ status: "scheduled", start: stamp(lead * minute) });
    const result = await joined([programme({ start: stamp(0) })], [official], "reviewedtv");
    assert.equal(listed(result).length, 1, String(lead));
    assert.equal(listed(result)[0].fixtureFingerprint.start, official.start);
    assert.equal(result.source.broadcasts[0].start, stamp(0));
  }
  const tooEarly = await joined([programme({ start: stamp(0) })], [fixture({ status: "scheduled", start: stamp(60 * minute + 1) })], "reviewedtv");
  assert.equal(listed(tooEarly).length, 0);
});

test("current limited-overs programme may cross UTC midnight only inside its bounded official match window", async () => {
  const at = new Date("2026-11-02T00:15:00.000Z");
  const official = fixture({ start: "2026-11-01T20:00:00.000Z" }, at);
  const coverage = programme({ start: "2026-11-01T23:30:00.000Z", end: "2026-11-02T01:00:00.000Z" }, at);
  assert.equal(listed(await joined([coverage], [official], "reviewedtv", at)).length, 1);
  assert.equal(listed(await joined([coverage], [fixture({ start: "2026-10-31T20:00:00.000Z" }, at)], "reviewedtv", at)).length, 0);
});
