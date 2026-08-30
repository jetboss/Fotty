import assert from "node:assert/strict";
import test from "node:test";

import { estimateMatchClock } from "./match-clock.ts";

const kickoff = "2026-08-24T18:00:00.000Z";
const minute = (value) => Date.parse(kickoff) + value * 60_000;

test("estimates an association-football clock around halftime", () => {
  assert.equal(
    estimateMatchClock({ startsAt: kickoff, sport: "Football", apiStatus: "Live", now: minute(32) }),
    "32'"
  );
  assert.equal(
    estimateMatchClock({ startsAt: kickoff, sport: "Soccer", apiStatus: "Live", now: minute(51) }),
    "HT"
  );
  assert.equal(
    estimateMatchClock({ startsAt: kickoff, sport: "Football", apiStatus: "Live", now: minute(74) }),
    "60'"
  );
});

test("does not invent minute clocks for period, inning, or quarter sports", () => {
  for (const sport of ["Baseball", "Basketball", "Hockey", "American Football", "Cricket"]) {
    assert.equal(
      estimateMatchClock({ startsAt: kickoff, sport, apiStatus: "Live", now: minute(115) }),
      null,
      sport
    );
  }
});

test("does not display an unbounded clock for a stale football live flag", () => {
  assert.equal(
    estimateMatchClock({ startsAt: kickoff, sport: "Football", apiStatus: "Live", now: minute(180) }),
    null
  );
});

test("preserves explicit provider halftime and full-time states", () => {
  assert.equal(estimateMatchClock({ sport: "Baseball", apiStatus: "HT" }), "HT");
  assert.equal(estimateMatchClock({ sport: "Basketball", apiStatus: "Finished" }), "FT");
});
