import assert from "node:assert/strict";
import test from "node:test";
import { buildFootballMatchesUpstreamUrl } from "./football-matches-url.ts";

test("football matches proxy builds global schedule URL", () => {
  const result = buildFootballMatchesUpstreamUrl({
    dateFrom: "2026-07-10",
    dateTo: "2026-07-12",
    status: "SCHEDULED,TIMED",
  });
  assert.equal(
    result.url,
    "https://api.football-data.org/v4/matches?dateFrom=2026-07-10&dateTo=2026-07-12&status=SCHEDULED%2CTIMED"
  );
});

test("football matches proxy builds competition URL", () => {
  const result = buildFootballMatchesUpstreamUrl({
    competition: "wc",
    season: "2026",
    limit: "40",
  });
  assert.equal(
    result.url,
    "https://api.football-data.org/v4/competitions/WC/matches?season=2026&limit=40"
  );
});

test("football matches proxy rejects unsafe query values", () => {
  const result = buildFootballMatchesUpstreamUrl({
    dateFrom: "2026-07-10",
    status: "IN_PLAY;drop table",
  });
  assert.equal(result.error, "Invalid status");
});
