import test from "node:test";
import assert from "node:assert/strict";
import { normalizeBroadcastCollection, normalizeRegistryFixtures, associateBroadcasts, buildBroadcastSnapshot,
  BROADCAST_REGISTRY_LIMITS } from "./broadcast-registry-policy.mjs";

const now = new Date("2026-10-30T11:30:00.000Z"), stamp = (offset = 0) => new Date(+now + offset).toISOString();
const fixture = (changes = {}) => ({ fixtureID: "sports-fixture:premier-league:123", sport: "football",
  participants: ["Liverpool", "Chelsea"], start: stamp(-30 * 60_000), competitionID: "premier-league",
  squad: { gender: "men", ageGroup: "senior" }, status: "live", observedAt: stamp(), verified: true, ...changes });
const row = (changes = {}) => ({ providerEventID: "nuvio_sport_match", streamID: "nuvio_sport_match", resourceType: "tv",
  scope: "football", kind: "event", sport: "football", title: "Liverpool vs Chelsea", participants: ["Liverpool", "Chelsea"],
  start: stamp(-30 * 60_000), verification: "dated", observedAt: stamp(), expiresAt: stamp(20 * 60_000), ...changes });
const collection = (rows = [row()], changes = {}) => ({ providerCode: "communitysports", observedAt: stamp(), complete: true,
  scopes: [{ scope: "football", status: "available", complete: true }], broadcasts: rows, ...changes });
async function joined(rows = [row()], fixtures = [fixture()], changes = {}) {
  const source = await normalizeBroadcastCollection("communitysports", collection(rows, changes), now);
  return { source, links: associateBroadcasts({ fixtures, broadcasts: source.broadcasts, providers: source.scopes, now }) };
}

test("wire text retains171-char participants and harmlessZWJ/tagemoji while C1/bidi never enter a snapshot", async () => {
  const england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}";
  const source = await normalizeBroadcastCollection("communitysports", collection([
    row(), row({ providerEventID: "long_name", streamID: "long_name", participants: ["A".repeat(171), "Other Team"] }),
    row({ providerEventID: "zwj", streamID: "zwj", title: "Family 👨\u200D👩\u200D👧\u200D👦" }),
    row({ providerEventID: "tag", streamID: "tag", title: "England " + england }),
  ]), now);
  assert.equal(source.broadcasts.length, 4);
  assert.ok(source.broadcasts.some((r) => r.participants[0].length === 171));
  assert.ok(source.broadcasts.some((r) => r.title === "England " + england));
  for (const scalar of ["\u0085", "\u061c", "\u200e", "\u200f", "\u202a", "\u202e", "\u2066", "\u2069"])
    await assert.rejects(normalizeBroadcastCollection("communitysports", collection([row({ title: "Fixture" + scalar + "Title" })]), now), /invalid-collection/u);
  for (const scalar of ["\u0085", "\u200d", "\u{E0067}"])
    await assert.rejects(normalizeBroadcastCollection("communitysports", collection([row({ providerEventID: "source" + scalar + "event" })]), now), /invalid-collection/u);
});

test("normalized registry retains bounded identity facts and strips every unrelated raw location/credential", async () => {
  const { source, links } = await joined([row({ url: "https://private.example/media?token=secret", headers: { Authorization: "secret" },
    description: "https://another.example/private", token: "secret" })]);
  assert.equal(source.broadcasts[0].id.length, 67);
  assert.match(source.broadcasts[0].id, /^br:[a-f0-9]{64}$/);
  assert.equal(links[0].state, "listed");
  assert.equal(links[0].matchMethod, "exact");
  assert.equal(links[0].fixtureFingerprint.start, fixture().start);
  const text = JSON.stringify(source);
  assert.equal(text.includes("https://"), false); assert.equal(text.includes("secret"), false);
  await assert.rejects(normalizeBroadcastCollection("communitysports", collection([row({ providerEventID: "https://private.example/token" })]), now), /invalid-collection/);
});

test("exact pairing, scope, squad and date conflicts never become listed broadcasts", async () => {
  assert.equal((await joined([row({ participants: ["Liverpool", "Arsenal"] })])).links.length, 0);
  for (const [changes, reason] of [[{ start: stamp(-46 * 60_000) }, "time-conflict"],
    [{ competitionID: "champions-league" }, "competition-conflict"],
    [{ squad: { gender: "women", ageGroup: "senior" } }, "squad-conflict"]]) {
    const { links } = await joined([row(changes)]);
    assert.equal(links[0].state, "conflicting"); assert.equal(links[0].reason, reason);
  }
  const missing = (await joined([row({ start: undefined, verification: "undated" })])).links[0];
  assert.equal(missing.state, "needsVerification"); assert.equal(missing.reason, "missing-date");
});

test("reviewed football club aliases preserve exact pairs and explicit squad identity", async () => {
  for (const [official, published] of [
    [["Brighton & Hove Albion", "Manchester United"], ["Brighton", "Man Utd"]],
    [["Wolverhampton Wanderers", "Tottenham Hotspur"], ["Wolves", "Tottenham"]],
    [["Manchester United Women", "Brighton & Hove Albion Women"], ["Man Utd Ladies", "Brighton W"]],
    [["Manchester United Under-19", "Brighton & Hove Albion U19"], ["Man Utd U 19", "Brighton Under 19"]],
  ]) {
    const women = official.some((name) => /\bWomen\b/u.test(name)), youth = official.some((name) => /(?:Under-19|U19)/u.test(name));
    const result = await joined([row({ participants: published })], [fixture({ participants: official,
      squad: { gender: women ? "women" : "men", ageGroup: youth ? "u19" : "senior" } })]);
    assert.equal(result.links[0]?.state, "listed", published.join(" / "));
    assert.deepEqual(result.links[0].fixtureFingerprint.participants, official, "Fingerprint keeps the actual official names");
  }
  for (const published of [["Brighton Women", "Man Utd Women"], ["Brighton U19", "Man Utd Under-19"],
    ["Brighton Reserves", "Man Utd Reserve"], ["Brighton Academy", "Man Utd Academy"],
    ["Brighton", "Manchester City"], ["Brighton Albion B", "Man Utd"]]) {
    assert.equal((await joined([row({ participants: published })],
      [fixture({ participants: ["Brighton & Hove Albion", "Manchester United"] })])).links.length, 0, published.join(" / "));
  }
  assert.deepEqual(normalizeRegistryFixtures([fixture({ participants: ["Man Utd", "Manchester United"] })], now), [],
    "Two aliases for one club are not two opponents");
});

test("football aliases do not cross sports or conceal conflicting duplicate squads", async () => {
  const source = await joined([row(), row({ scope: "live", participants: ["Liverpool Women", "Chelsea Women"] })], [fixture()],
    { scopes: [{ scope: "football", status: "available", complete: true }, { scope: "live", status: "available", complete: true }] });
  assert.equal(source.source.broadcasts[0].verification, "conflicting");
  assert.notEqual(source.links[0]?.state, "listed");
  const cricket = fixture({ fixtureID: "cricket-fixture:icc:alias", sport: "cricket", competitionID: "icc", squad: undefined,
    format: "T20", participants: ["West Indies", "Australia"] });
  const opts = { scopes: [{ scope: "cricket", status: "available", complete: true }] };
  const common = row({ scope: "cricket", sport: "cricket", format: "T20", competitionID: "icc" });
  assert.equal((await joined([{ ...common, participants: cricket.participants }], [cricket], opts)).links[0]?.state, "listed");
  assert.equal((await joined([{ ...common, participants: ["West Indies Women", "Australia Women"] }], [cricket], opts)).links.length, 0);
  assert.equal((await joined([{ ...common, participants: ["WI", "Australia"] }], [cricket], opts)).links.length, 0,
    "No new country alias is invented when no reviewed shared JavaScript country table exists");
});

test("malformed or conflicting duplicate observations remain vetoes rather than first-row positives", async () => {
  const { source, links } = await joined([row(), row({ start: stamp(-2 * 60 * 60_000) })]);
  assert.equal(source.broadcasts.length, 1);
  assert.equal(source.broadcasts[0].verification, "conflicting");
  assert.equal(links[0].state, "conflicting");
  const malformed = await joined([row({ start: "2026-02-30T11:00:00Z" })]);
  assert.equal(malformed.source.broadcasts[0].verification, "conflicting");
  assert.notEqual(malformed.links[0].state, "listed");
});

test("terminal, unverified, stale and contradictory official facts cannot lend fixture authority", async () => {
  for (const changes of [{ status: "finished" }, { status: "cancelled" }, { status: "postponed" }, { verified: false },
    { observedAt: stamp(-31 * 60_000) }]) assert.equal((await joined([row()], [fixture(changes)])).links.length, 0);
  assert.deepEqual(normalizeRegistryFixtures([fixture(), fixture({ start: stamp(-29 * 60_000) })], now), []);
  const stale = await joined([row({ observedAt: stamp(-25 * 60_000), expiresAt: stamp(-5 * 60_000) })]);
  assert.equal(stale.links[0].state, "needsVerification"); assert.equal(stale.links[0].reason, "stale-source");
});

test("Test occurrence joins explicit source UTC with official same day, ordinal and canonical period only", async () => {
  const official = fixture({ fixtureID: "cricket-fixture:icc:269792", sport: "cricket", participants: ["South Africa", "Australia"],
    competitionID: "icc", squad: undefined, format: "Test", matchOrdinal: 3, day: 4,
    start: "2026-10-27T08:30:00.000Z", end: "2026-10-31T15:30:00.000Z" });
  const broadcast = row({ scope: "cricket", sport: "cricket", title: "South Africa vs Australia, 3rd Test Day 4",
    participants: official.participants, format: "Test", matchOrdinal: 3, day: 4, start: "2026-10-30T08:00:00.000Z" });
  const opts = { scopes: [{ scope: "cricket", status: "available", complete: true }] };
  const { links } = await joined([broadcast], [official], opts);
  assert.equal(links[0].state, "listed"); assert.equal(links[0].matchMethod, "test-period");
  assert.equal(links[0].fixtureFingerprint.start, official.start);
  for (const [changes, reason] of [[{ day: 3 }, "day-conflict"], [{ matchOrdinal: 2 }, "ordinal-conflict"],
    [{ start: "2026-11-01T08:00:00.000Z" }, "time-conflict"], [{ format: "T20", day: undefined, matchOrdinal: undefined }, "format-conflict"]]) {
    const wrong = await joined([{ ...broadcast, ...changes }], [official], opts);
    assert.equal(wrong.links[0].state, "conflicting"); assert.equal(wrong.links[0].reason, reason);
  }
  const noEnd = await joined([broadcast], [{ ...official, end: undefined }], opts);
  assert.equal(noEnd.links[0].state, "needsVerification"); assert.equal(noEnd.links[0].reason, "missing-test-authority");
  const staleDay = await joined([broadcast], [{ ...official, observedAt: stamp(-11 * 60_000) }], opts);
  assert.equal(staleDay.links[0].state, "needsVerification"); assert.equal(staleDay.links[0].reason, "missing-test-authority");
  const agingDay = await joined([broadcast], [{ ...official, observedAt: stamp(-5 * 60_000) }], opts);
  assert.equal(agingDay.links[0].expiresAt, stamp(5 * 60_000), "A listed link cannot outlive its official Test-day authority");
  assert.equal("dailyStart" in links[0].fixtureFingerprint, false);
});

test("whole-Test event uses exact original start without optional daily context, while daily occurrences retain authority checks", async () => {
  const official = fixture({ fixtureID: "cricket-fixture:icc:whole-test", sport: "cricket", participants: ["South Africa", "Australia"],
    competitionID: "icc", squad: undefined, format: "Test", start: "2026-10-27T08:30:00.000Z" });
  const broadcast = row({ scope: "cricket", sport: "cricket", title: "South Africa vs Australia, Test",
    participants: official.participants, format: "Test", start: official.start });
  const opts = { scopes: [{ scope: "cricket", status: "available", complete: true }] };
  const exact = (await joined([broadcast], [official], opts)).links[0];
  assert.equal(exact.state, "listed"); assert.equal(exact.matchMethod, "exact");
  assert.equal((await joined([{ ...broadcast, start: "2026-10-27T08:45:00.000Z" }], [official], opts)).links[0].state, "listed");
  assert.equal((await joined([{ ...broadcast, start: "2026-10-27T08:45:01.000Z" }], [official], opts)).links[0].reason, "time-conflict");
  const later = (await joined([{ ...broadcast, start: "2026-10-30T08:00:00.000Z" }], [official], opts)).links[0];
  assert.equal(later.state, "conflicting"); assert.equal(later.reason, "time-conflict");
  const daily = (await joined([{ ...broadcast, matchOrdinal: 3, day: 4 }], [official], opts)).links[0];
  assert.equal(daily.state, "needsVerification"); assert.equal(daily.reason, "missing-test-authority");
  const wrongOrdinal = (await joined([{ ...broadcast, matchOrdinal: 2 }], [{ ...official, matchOrdinal: 3 }], opts)).links[0];
  assert.equal(wrongOrdinal.state, "conflicting"); assert.equal(wrongOrdinal.reason, "ordinal-conflict");
  const current = { ...official, matchOrdinal: 3, day: 4, end: "2026-10-31T15:30:00.000Z" };
  assert.equal((await joined([broadcast], [current], opts)).links[0].state, "listed");
  const programme = { ...broadcast, kind: "programme", channelID: "cricket-channel:willow", end: stamp(60 * 60_000), expiresAt: stamp(10 * 60_000) };
  assert.notEqual((await joined([programme], [official], opts)).links[0].state, "listed", "A whole-match start does not authorize a current linear programme");
});

test("generic channels never prove a fixture but an explicitly dated exact programme may link", async () => {
  const official = fixture({ fixtureID: "cricket-fixture:icc:123", sport: "cricket", participants: ["India", "England"],
    competitionID: "icc", squad: undefined, format: "T20" });
  const channel = row({ scope: "networks", kind: "channel", sport: "cricket", title: "Willow Cricket",
    participants: [], start: undefined, verification: "undated", channelID: "cricket-channel:willow" });
  const opts = { scopes: [{ scope: "networks", status: "available", complete: true }] };
  assert.equal((await joined([channel], [official], opts)).links.length, 0);
  const programme = { ...channel, providerEventID: "programme1", streamID: "programme1", kind: "programme", title: "India vs England",
    participants: official.participants, start: official.start, end: stamp(60 * 60_000), format: "T20", verification: "dated", expiresAt: stamp(10 * 60_000) };
  const admitted = (await joined([programme], [official], opts)).links[0];
  assert.equal(admitted.state, "listed"); assert.equal(admitted.matchMethod, "programme");
  for (const changed of [{ ...programme, channelID: undefined }, { ...programme, participants: [] }]) {
    assert.equal((await joined([changed], [official], opts)).links.some((link) => link.state === "listed"), false);
  }
});

test("partial positive cohorts remain useful while held source failure never renews them", async () => {
  const partial = await joined([row()], [fixture()], { complete: false, scopes: [{ scope: "football", status: "partial", complete: false }] });
  assert.equal(partial.links[0].state, "listed");
  const held = associateBroadcasts({ fixtures: [fixture()], broadcasts: partial.source.broadcasts,
    providers: [{ providerCode: "communitysports", scope: "football", status: "failed" }], now });
  assert.equal(held[0].state, "needsVerification"); assert.equal(held[0].reason, "source-unavailable");
  const retainedScope = { providerCode: "communitysports", scope: "football", status: "failed",
    observedAt: stamp(), lastSuccessAt: stamp(), expiresAt: stamp(20 * 60_000), failure: "source-unavailable" };
  const retained = associateBroadcasts({ fixtures: [fixture()], broadcasts: partial.source.broadcasts,
    providers: [retainedScope], now });
  assert.equal(retained[0].state, "listed", "Catalog failure alone must not erase an accepted exact source identity");
  assert.equal(retained[0].expiresAt, partial.source.broadcasts[0].expiresAt, "Failure never renews original listing expiry");
  assert.equal(associateBroadcasts({ fixtures: [fixture()], broadcasts: partial.source.broadcasts,
    providers: [{ ...retainedScope, expiresAt: stamp(-1) }], now })[0].state, "needsVerification");
});

test("one unmarked broadcast cannot belong to two competing canonical fixtures", async () => {
  const other = fixture({ fixtureID: "sports-fixture:champions-league:other", competitionID: "champions-league" });
  const ambiguous = await joined([row()], [fixture(), other]);
  assert.equal(ambiguous.links.length, 2);
  assert.ok(ambiguous.links.every((link) => link.state === "conflicting" && link.reason === "catalog-conflict"));
  const explicit = await joined([row({ competitionID: "premier-league" })], [fixture(), other]);
  assert.equal(explicit.links.filter((link) => link.state === "listed").length, 1);
  assert.equal(explicit.links.find((link) => link.state === "listed").fixtureID, fixture().fixtureID);
});

test("equivalent sport and Live source entries share one identity without losing contradiction vetoes", async () => {
  const scopes = [{ scope: "football", status: "available", complete: true }, { scope: "live", status: "available", complete: true }];
  const equivalent = await joined([row(), row({ scope: "live", title: "Live: Liverpool vs Chelsea" })], [fixture()], { scopes });
  assert.equal(equivalent.source.broadcasts.length, 1);
  assert.equal(equivalent.links[0].state, "listed");
  const contradiction = await joined([row(), row({ scope: "live", participants: ["Liverpool", "Arsenal"] })], [fixture()], { scopes });
  assert.equal(contradiction.source.broadcasts.length, 1);
  assert.equal(contradiction.source.broadcasts[0].verification, "conflicting");
  assert.notEqual(contradiction.links[0]?.state, "listed");
});

test("stable event lookup facts have four-hour ceiling while programme currentness remains ten minutes", async () => {
  const stable = await joined([row({ expiresAt: stamp(4 * 60 * 60_000) })]);
  assert.equal(stable.links[0].state, "listed");
  assert.equal(stable.links[0].expiresAt, stamp(30 * 60_000), "Fresh official LIVE authority remains the shorter fence");
  await assert.rejects(normalizeBroadcastCollection("communitysports", collection([row({ expiresAt: stamp(4 * 60 * 60_000 + 1) })]), now), /invalid-collection/);
  const programme = row({ kind: "programme", sport: "cricket", scope: "networks", channelID: "cricket-channel:willow",
    end: stamp(60 * 60_000), expiresAt: stamp(10 * 60_000 + 1) });
  await assert.rejects(normalizeBroadcastCollection("communitysports", collection([programme],
    { scopes: [{ scope: "networks", status: "available", complete: true }] }), now), /invalid-collection/);
});

test("content revision is deterministic without renewing source observations and caps never truncate identities", async () => {
  const { source, links } = await joined();
  const first = await buildBroadcastSnapshot({ providers: source.scopes, broadcasts: source.broadcasts, links, now });
  const second = await buildBroadcastSnapshot({ providers: source.scopes, broadcasts: source.broadcasts, links, now: new Date(+now + 1000) });
  assert.equal(first.revision, second.revision); assert.notEqual(first.generatedAt, second.generatedAt);
  assert.equal(second.broadcasts[0].observedAt, stamp());
  await assert.rejects(buildBroadcastSnapshot({ providers: [], broadcasts: Array(BROADCAST_REGISTRY_LIMITS.records + 1).fill(source.broadcasts[0]), links: [], now }), /capacity-exceeded/);
  await assert.rejects(normalizeBroadcastCollection("communitysports", collection(Array(1501).fill(row())), now), /invalid-collection/);
});
