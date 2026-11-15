import assert from "node:assert/strict";
import test from "node:test";
import { boundedFixtureScores, normalizeUCLReportedScore, validUCLReportedScore } from "./ucl-reported-score-policy.mjs";

const updatedAt = "2026-10-29T17:00:00.000Z";
const fixture = (overrides = {}) => ({ id: "sports-fixture:champions-league:575377", sport: "football",
  competitionId: "champions-league", eventKind: "match", status: "live",
  participants: [{ id: "football-data:100", name: "Home", role: "home" }, { id: "football-data:200", name: "Away", role: "away" }],
  squad: { gender: "men", ageGroup: "senior" }, source: { name: "football-data.org", updatedAt }, ...overrides });
const row = (overrides = {}) => ({ id: 575377, competition: { code: "CL" }, status: "IN_PLAY", lastUpdated: updatedAt,
  homeTeam: { id: 100 }, awayTeam: { id: 200 }, score: { duration: "REGULAR", fullTime: { home: 2, away: 0 } }, ...overrides });
const score = { home: 2, away: 0, publisherUpdatedAt: updatedAt };

test("UCL optional reported score preserves explicit zero and real publisher timestamp", () => {
  assert.deepEqual(normalizeUCLReportedScore(row(), fixture()), score);
  assert.equal(validUCLReportedScore(score, fixture()), true);
  const before = fixture(); normalizeUCLReportedScore(row(), before);
  assert.equal(before.status, "live"); assert.equal(before.reportedScore, undefined);
});
test("prematch real nullable UCL vector never becomes zero-zero or current-live authority", () => {
  const pending = row({ status: "TIMED", score: { winner: null, duration: "REGULAR", fullTime: { home: null, away: null }, halfTime: { home: null, away: null } } });
  assert.equal(normalizeUCLReportedScore(pending, fixture({ status: "scheduled" })), undefined);
  assert.equal(normalizeUCLReportedScore(row({ score: { duration: "REGULAR", fullTime: { home: null, away: 0 } } }), fixture()), undefined);
});
test("wrong competition squad identity source or raw status cannot borrow CL reported score", () => {
  for (const changed of [fixture({ competitionId: "premier-league" }), fixture({ sport: "cricket" }),
    fixture({ eventKind: "session" }), fixture({ squad: { gender: "women", ageGroup: "senior" } }),
    fixture({ squad: { gender: "men", ageGroup: "u19" } }), fixture({ source: { name: "Other", updatedAt } })]) {
    assert.equal(normalizeUCLReportedScore(row(), changed), undefined);
  }
  for (const changed of [row({ competition: { code: "PL" } }), row({ id: 1 }), row({ homeTeam: { id: 900 } }),
    row({ status: "FINISHED" }), row({ score: { duration: "PENALTY_SHOOTOUT", fullTime: { home: 5, away: 4 } } })]) {
    assert.equal(normalizeUCLReportedScore(changed, fixture()), undefined);
  }
});
test("malformed null strings negative goals and absent or mismatched timestamps omit score only", () => {
  for (const value of [null, undefined, "0", -1, 100, 1.2, NaN]) {
    assert.equal(normalizeUCLReportedScore(row({ score: { duration: "REGULAR", fullTime: { home: value, away: 0 } } }), fixture()), undefined);
  }
  for (const lastUpdated of [undefined, null, "2026-10-29T17:00:00", "2026-10-30T17:00:00Z"]) {
    assert.equal(normalizeUCLReportedScore(row({ lastUpdated }), fixture()), undefined);
  }
});
test("fresh same-ID nullable result has no optional score to renew previous goals", () => {
  const previous = { ...fixture(), reportedScore: normalizeUCLReportedScore(row(), fixture()) };
  const fresh = fixture();
  const missing = normalizeUCLReportedScore(row({ score: { duration: "REGULAR", fullTime: { home: null, away: null } } }), fresh);
  if (missing) fresh.reportedScore = missing;
  assert.ok(previous.reportedScore); assert.equal(fresh.reportedScore, undefined);
});
test("budget stripping preserves every fixture and non-score field and ignores malformed optional score", () => {
  const legacy = { ...fixture({ competitionId: "premier-league" }), reportedScore: score };
  const snapshot = { schemaVersion: 1, complete: true, fixtures: [{ ...fixture(), reportedScore: score }, legacy], coverage: [] };
  const output = boundedFixtureScores(snapshot, new Date(updatedAt));
  assert.equal(output.fixtures.length, 2); assert.deepEqual(output.fixtures[0].reportedScore, score);
  assert.equal(output.fixtures[1].reportedScore, undefined); assert.equal(output.fixtures[1].competitionId, "premier-league");
  const full = boundedFixtureScores({ ...snapshot, padding: "x".repeat(2 * 1024 * 1024), fixtures: snapshot.fixtures }, new Date(updatedAt));
  assert.equal(full.fixtures.length, 2); assert.equal(full.fixtures[0].reportedScore, undefined);
  assert.equal(full.padding.length, 2 * 1024 * 1024, "Existing base data is never erased or truncated for scores");
});

test("live projections omit held, regressed-status and stale score evidence; missing fields and roles stay intact", () => {
  const source = { name: "football-data.org", updatedAt, observedAt: updatedAt };
  const footballLive = { home: 0, away: 2, clock: "90+7′" };
  const record = (overrides) => fixture({ source, footballLive, ...overrides });
  const fixtures = [record(), record({ footballLive: { clock: "HT" } }), record({ footballLive: { home: 2, away: 1 } }),
    record({ status: "finished" }), record({ source: { ...source, verification: "held" } }),
    record({ source: { ...source, observedAt: "2026-10-29T15:00:00Z" } }),
    record({ source: { ...source, updatedAt: "2026-10-29T15:00:00Z" } }),
    record({ footballLive: { clock: "151′" } }), record({ footballLive: { home: 0 } })];
  const snapshot = { coverage: [{ status: "covered", competitionId: "champions-league" }], fixtures };
  const output = boundedFixtureScores(snapshot, new Date(updatedAt));
  assert.deepEqual(output.fixtures.map((row) => row.footballLive),
    [footballLive, { clock: "HT" }, { home: 2, away: 1 }, ...Array(6).fill(undefined)]);
  assert.deepEqual(fixtures[4].footballLive, footballLive, "Projection must not modify the stored receipt");
  assert.equal(boundedFixtureScores({ ...snapshot, coverage: [] }, new Date(updatedAt)).fixtures[0].footballLive, undefined);
  const full = boundedFixtureScores({ ...snapshot, padding: "x".repeat(2 * 1024 * 1024) }, new Date(updatedAt));
  assert.equal(full.fixtures.length, fixtures.length);
  assert.ok(full.fixtures.every((row) => row.footballLive === undefined));
});
