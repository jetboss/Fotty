import test from "node:test";
import assert from "node:assert/strict";
import { auditSportsHistory, collectESPNLiveMismatches } from "./sports-fixture-watchdog.mjs";

const now = Date.parse("2026-11-21T18:40:00Z");
const at = (minutes) => new Date(now - minutes * 60_000).toISOString();

test("history flags a group that is failing or failed repeatedly inside the window", () => {
  const findings = auditSportsHistory({ sources: {
    "football-data": [{ at: at(20), outcome: "covered" }, { at: at(15), outcome: "unavailable" }, { at: at(10), outcome: "covered" }],
    "efl-carabao-cup": [{ at: at(10), outcome: "unavailable" }, { at: at(5), outcome: "unavailable" }],
    mlb: [{ at: at(300), outcome: "unavailable" }, { at: at(5), outcome: "covered" }],
    nhl: { readFailure: "timeout" },
  } }, { now });
  assert.deepEqual(findings, [
    { code: "recent-lane-failure", competitionId: "football-data", actionable: false },
    { code: "recent-lane-failure", competitionId: "efl-carabao-cup", actionable: true },
    { code: "history-unreadable", actionable: false, competitionId: "nhl" },
  ]);
  assert.deepEqual(auditSportsHistory(null, { now }), []);
});

const espn = (state, home = "Arsenal", away = "Leeds United", date = "2026-11-21T17:30Z") => ({ leagues: [{ slug: "eng.1" }], events: [{
  date, status: { type: { state, completed: state === "post" } },
  competitions: [{ competitors: [{ homeAway: "home", team: { displayName: home } }, { homeAway: "away", team: { displayName: away } }] }],
}] });
const feed = (status) => ({ fixtures: [{ competitionId: "premier-league", eventKind: "match", status, start: "2026-11-21T17:30:00.000Z",
  participants: [{ name: "Arsenal FC", role: "home" }, { name: "Leeds United FC", role: "away" }] }] });

test("ESPN in-play match that the feed does not show live is actionable", async () => {
  const fetchJSON = async () => espn("in");
  assert.deepEqual(await collectESPNLiveMismatches(feed("scheduled"), { now, fetchJSON }),
    [{ code: "espn-live-mismatch", actionable: true, competitionId: "premier-league" }]);
  assert.deepEqual(await collectESPNLiveMismatches(feed("live"), { now, fetchJSON }), []);
  assert.deepEqual(await collectESPNLiveMismatches(feed("scheduled"), { now, fetchJSON: async () => espn("post") }), []);
  assert.deepEqual(await collectESPNLiveMismatches(feed("scheduled"), { now, fetchJSON: async () => espn("in", "Leeds United", "Arsenal") }), [],
    "Reversed roles are not the same fixture");
  assert.deepEqual(await collectESPNLiveMismatches(feed("scheduled"), { now: Date.parse("2026-11-21T17:35:00Z"), fetchJSON }), [],
    "Inside the first ten minutes the feed may still be catching up");
  assert.deepEqual(await collectESPNLiveMismatches(feed("scheduled"), { now, fetchJSON: async () => { throw new Error("down"); } }),
    [{ code: "espn-comparison-unavailable", actionable: false, competitionId: "premier-league" }]);
});
