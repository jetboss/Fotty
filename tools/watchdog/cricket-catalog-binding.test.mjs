import test from "node:test";
import assert from "node:assert/strict";
import { supportsCSCricketFixture, selectCSCricketCatalogMatch as select } from "./cricket-catalog-binding.mjs";

const START = "2026-10-30T07:00:00.000Z";
const fixture = (changes = {}) => ({ id: "icc:reviewed", start: START, format: "T20", competitionName: "India in New Zealand,5T20I Series,2026",
  home: { id: "nz", name: "New Zealand" }, away: { id: "ind", name: "India" }, source: { verification: "verified" }, ...changes });
const row = (changes = {}) => ({ id: "nuvio_sport_redacted", type: "tv", name: "⏱️ New Zealand vs India", genres: ["CRICKET"],
  cast: ["New Zealand", "India"], released: START, behaviorHints: { defaultVideoId: "nuvio_sport_redacted" },
  description: "🏆 League: T20 International\n📅 Category: CRICKET\n⏰ Status: Upcoming", ...changes });
const catalog = (...rows) => ({ metas: rows });

test("reviewed CS dated T20 identity is metadata evidence only and never infers LIVE", () => {
  assert.equal(supportsCSCricketFixture(fixture()), true);
  for (const status of ["scheduled", "live", "finished"]) assert.deepEqual(select(fixture({ status }), catalog(row())),
    { outcome: "matched", reason: "dated-catalog-binding-only" });
  assert.equal(select(fixture(), catalog(row({ name: "🔴 LIVE: India vs New Zealand", cast: ["New Zealand", "India"] }))).outcome, "matched");
});
test("actual29Oct CS future catalog/meta07:30 cannot bind official ICC/BCCI07:00", () => {
  const observed = row({ released: "2026-10-30T07:30:00.000Z", description: "🏆 League: T20 International\n📅 Category: CRICKET\n⏰ Status: ⏱️ Kickoff at7:30AM" });
  assert.equal(select(fixture(), catalog(observed)).outcome, "unverifiable");
  assert.equal(select(fixture(), catalog(row({ released: "2026-10-30T07:15:00Z" }))).outcome, "matched");
  assert.notEqual(select(fixture(), catalog(row({ released: "2026-10-30T07:15:01Z" }))).outcome, "matched");
});
test("explicit offset is UTC authority; local clocks, invalid calendars and LIVE text are not", () => {
  assert.equal(select(fixture(), catalog(row({ released: "2026-10-30T12:30:00+05:30" }))).outcome, "matched");
  for (const released of [undefined, null, "LIVE", "2026-10-30T07:00:00", "2026-02-30T07:00:00Z", "2026-10-30T24:00:00Z", "2026-10-30T07:00:00+25:00"]) {
    assert.equal(select(fixture(), catalog(row({ released }))).outcome, "unverifiable");
  }
});
test("ODI and T10 are separate supported CS contracts, without extending AS's T20/Test rules", () => {
  for (const [format, league] of [["ODI", "One Day International"], ["T10", "T10 International"]]) {
    const f = fixture({ format, competitionName: `${format} Series,2026` });
    assert.equal(supportsCSCricketFixture(f), true);
    assert.equal(select(f, catalog(row({ description: `🏆 League: ${league}` }))).outcome, "matched");
    assert.notEqual(select(f, catalog(row())).outcome, "matched");
  }
  for (const format of ["unknown", "Sixes", "T20I", null]) assert.equal(supportsCSCricketFixture(fixture({ format })), false);
});
test("Test needs explicit initial-day evidence and never substitutes a later Test day", () => {
  const f = fixture({ format: "Test", competitionName: "1st Test", context: { phase: "in-play", day: 1 } });
  const r = row({ description: "🏆 League: 1st Test Day1" });
  assert.equal(select(f, catalog(r)).outcome, "matched");
  for (const context of [undefined, { day: 2, phase: "in-play" }, { day: 1, phase: "stumps" }, { day: 1.5, phase: "in-play" }]) {
    assert.notEqual(select({ ...f, context }, catalog(r)).outcome, "matched");
  }
  for (const description of ["🏆 League: 1st Test", "🏆 League: 1st Test Day2", "🏆 League: 2nd Test Day1", "🏆 League: 1st Test Day1 Day2"]) {
    assert.notEqual(select(f, catalog(row({ description }))).outcome, "matched");
  }
});
test("format/ordinal/context contradictions remain unverified, including unsupported Sixes", () => {
  const f = fixture({ competitionName: "4th T20I" });
  assert.equal(select(f, catalog(row({ description: "🏆 League: 4th T20I" }))).outcome, "matched");
  for (const league of ["3rd T20I", "4th ODI", "4rd T20I", "4th T20I 5th T20I", "T20 International", "HK Sixes2026", "ODI T20I"]) {
    assert.notEqual(select(f, catalog(row({ description: `🏆 League: ${league}` }))).outcome, "matched");
  }
  for (const change of [{ competitionName: "4th ODI" }, { context: { day: 1 } }, { context: { phase: "rain-delay" } },
    { source: { verification: "held" } }, { home: { id: "ind", name: "New Zealand" } }]) {
    assert.equal(supportsCSCricketFixture(fixture(change)), false);
  }
});
test("title/cast disagreements, ambiguous suffixes and squad conflicts cannot borrow another pair", () => {
  for (const changes of [{ cast: ["New Zealand", "Ireland"] }, { name: "New Zealand vs India | T20I" },
    { name: "New Zealand vs India vs England" }, { name: "New Zealand vs India - Final" }, { cast: [42, "India"] },
    { name: "New Zealand Women vs India Women" }, { name: "New Zealand U19 vs India U19" }]) {
    assert.notEqual(select(fixture(), catalog(row(changes))).outcome, "matched");
  }
  const women = fixture({ home: { id: "nzw", name: "New Zealand Women" }, away: { id: "indw", name: "India Women" }, competitionName: "Women's T20I Series" });
  assert.equal(select(women, catalog(row({ name: "New Zealand W vs India W" }))).outcome, "matched");
  assert.notEqual(select(fixture({ competitionName: "Women's T20I Series" }), catalog(row())).outcome, "matched");
  const youth = fixture({ home: { id: "nzu19", name: "New Zealand U19" }, away: { id: "indu19", name: "India U19" }, competitionName: "Under19 T20I Series" });
  assert.equal(select(youth, catalog(row({ name: "New Zealand Under19 vs India Under19" }))).outcome, "matched");
});
test("only existing exact CPL aliases collapse; arbitrary short names are not new aliases", () => {
  const f = fixture({ id: "cpl:fixture", home: { id: "slk", name: "Saint Lucia Kings" }, away: { id: "br", name: "Barbados Tridents" }, competitionName: "CPL T20" });
  assert.equal(select(f, catalog(row({ name: "St Lucia Kings vs Barbados Royals", cast: ["Saint Lucia Kings", "Barbados Tridents"] }))).outcome, "matched");
  assert.notEqual(select(f, catalog(row({ name: "St Lucia vs Barbados", cast: [] }))).outcome, "matched");
});
test("same-ID and effective-target contradictory siblings stay veto evidence in either order", () => {
  const good = row();
  assert.equal(select(fixture(), catalog(good, structuredClone(good))).outcome, "matched");
  for (const changes of [{ released: "2026-10-31T07:00:00Z" }, { released: "LIVE" }, { genres: ["FOOTBALL"] },
    { description: "🏆 League: ODI" }, { cast: [42, "India"] }, { name: "New Zealand Women vs India Women" }]) {
    const bad = row(changes);
    for (const entries of [[good, bad], [bad, good]]) assert.equal(select(fixture(), catalog(...entries)).outcome, "conflicting");
    const shared = { ...bad, id: "nuvio_sport_other" };
    assert.equal(select(fixture(), catalog(good, shared)).outcome, "conflicting");
  }
  const other = row({ id: "nuvio_sport_other", behaviorHints: { defaultVideoId: "nuvio_sport_other" } });
  assert.equal(select(fixture(), catalog(good, other)).outcome, "conflicting");
});
test("mixed/empty omissions are sampled catalog gaps; malformed envelopes stay unverified and bounded", () => {
  assert.deepEqual(select(fixture(), catalog()), { outcome: "missing", reason: "not-in-sampled-catalog" });
  assert.equal(select(fixture(), catalog(row({ genres: ["FOOTBALL"] }))).outcome, "missing");
  for (const value of [null, [], {}, { metas: null }, { metas: Array(601).fill(row()) }]) assert.equal(select(fixture(), value).outcome, "unverifiable");
  const input = catalog(row()), before = JSON.stringify(input);
  const result = select(fixture(), input);
  assert.equal(JSON.stringify(input), before);
  assert.deepEqual(Object.keys(result).sort(), ["outcome", "reason"]);
  assert.ok(!JSON.stringify(result).includes("nuvio_sport_"));
});
test("unknown source format cannot borrow fixture format and unreviewed context cannot create date authority", () => {
  for (const changes of [{ description: undefined }, { description: "🏆 League: International Cricket" },
    { description: "🏆 League: T20 International\n🏆 League: ODI" },
    { context: { phase: "in-play", day: 1 } }, { description: "🏆 League: T20 International\nDate: 30Oct2026 07:00 UTC", released: undefined }]) {
    assert.equal(select(fixture(), catalog(row(changes))).outcome, "unverifiable");
  }
  assert.equal(supportsCSCricketFixture(fixture({ source: { verification: null } })), false);
});
