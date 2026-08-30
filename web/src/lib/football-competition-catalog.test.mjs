import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import {
  FOOTBALL_COMPETITIONS,
  currentCompetitionOfficialNames,
  isCurrentCompetitionClub,
  isCurrentCompetitionPair,
  isFootballReferenceFresh,
} from "./football-competition-catalog.generated.ts";

test("generated football catalogs match the reviewed shared manifest", () => {
  execFileSync(process.execPath, ["../tools/generate-football-competition-catalog.mjs", "--check"], {
    cwd: process.cwd(),
    stdio: "pipe",
  });
});

test("shared provider identity payloads pass the release classifier", () => {
  execFileSync(process.execPath, ["../tools/audit-provider-football-identity.mjs"], {
    cwd: process.cwd(),
    stdio: "pipe",
  });
});

test("every competition has its declared membership and unique official names", () => {
  for (const competition of Object.values(FOOTBALL_COMPETITIONS)) {
    assert.equal(competition.clubs.length, competition.expectedClubCount);
    assert.equal(new Set(competition.clubs.map((club) => club.name.toLowerCase())).size, competition.expectedClubCount);
    assert.match(competition.officialSource, /^https:\/\//);
  }
  assert.equal(Object.keys(FOOTBALL_COMPETITIONS).length, 7);
  assert.deepEqual(FOOTBALL_COMPETITIONS.championsLeague.providerAliases, ["Champions League"]);
  assert.deepEqual(FOOTBALL_COMPETITIONS.europaLeague.providerAliases, ["Europa League"]);
  assert.equal(isFootballReferenceFresh(new Date("2027-06-30T23:59:59Z")), true);
  assert.equal(isFootballReferenceFresh(new Date("2027-07-01T00:00:00Z")), false);
});

test("2026/27 Premier League membership includes promoted clubs and rejects relegated clubs", () => {
  assert.equal(currentCompetitionOfficialNames("premierLeague").length, 20);
  for (const club of ["Coventry", "Hull City", "Leeds United", "Sunderland"]) {
    assert.equal(isCurrentCompetitionClub("premierLeague", club), true, club);
  }
  for (const club of ["Norwich City", "Burnley", "West Ham United", "Wolverhampton Wanderers"]) {
    assert.equal(isCurrentCompetitionClub("premierLeague", club), false, club);
  }
  assert.equal(isCurrentCompetitionPair("premierLeague", "Coventry City", "Arsenal"), true);
  assert.equal(isCurrentCompetitionPair("premierLeague", "Norwich City", "Arsenal"), false);
});

test("domestic memberships recognize current replacements rather than prior-season clubs", () => {
  const examples = [
    ["laLiga", "Málaga CF", "Girona"],
    ["serieA", "Frosinone", "Empoli"],
    ["bundesliga", "Schalke 04", "Wolfsburg"],
    ["ligue1", "Troyes", "Nantes"],
  ];
  for (const [competition, currentClub, oldClub] of examples) {
    assert.equal(isCurrentCompetitionClub(competition, currentClub), true, `${competition}: ${currentClub}`);
    assert.equal(isCurrentCompetitionClub(competition, oldClub), false, `${competition}: ${oldClub}`);
  }
});
