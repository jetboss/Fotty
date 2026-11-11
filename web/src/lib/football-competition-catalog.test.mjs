import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import {
  FOOTBALL_COMPETITIONS,
  canonicalFootballClubId,
  canonicalFootballTeamKey,
  currentCompetitionOfficialNames,
  isCurrentCompetitionClub,
  isCurrentCompetitionPair,
  isFootballReferenceFresh,
} from "./football-competition-catalog.generated.ts";

const reviewedSourceAliases = [
  ["VfB Stuttgart", "Stuttgart", "vfbstuttgart"],
  ["Red Bull New York", "New York Red Bulls", "redbullnewyork"],
  ["D.C. United", "DC United", "dcunited"],
];
// Official club legal names, reviewed separately from season membership:
// https://www.realsociedad.eus/es/i/aviso-legal
// https://www.udinese.it/legals/note-legali
const reviewedLegalAliases = [
  ["Real Sociedad", "Real Sociedad de Fútbol", "realsociedad"],
  ["Udinese", "Udinese Calcio", "udinese"],
];

test("reviewed source aliases resolve to explicit senior club identities", () => {
  for (const [canonical, alias, expectedID] of [...reviewedSourceAliases, ...reviewedLegalAliases]) {
    for (const name of [canonical, alias]) {
      assert.equal(canonicalFootballClubId(name), expectedID, name);
      assert.equal(canonicalFootballTeamKey(name), expectedID, name);
    }
  }
});

test("reviewed legal names preserve existing competition membership", () => {
  assert.equal(isCurrentCompetitionClub("laLiga", "Real Sociedad de Fútbol"), true);
  assert.equal(isCurrentCompetitionClub("europaLeague", "Real Sociedad de Fútbol"), true);
  assert.equal(isCurrentCompetitionClub("serieA", "Udinese Calcio"), true);
  for (const [, alias] of reviewedLegalAliases) {
    assert.equal(isCurrentCompetitionClub("premierLeague", alias), false, alias);
  }
});

test("Stuttgart has one canonical identity across both reviewed competitions", () => {
  for (const id of ["bundesliga", "championsLeague"]) {
    const club = FOOTBALL_COMPETITIONS[id].clubs.find(row => row.name === "VfB Stuttgart");
    assert.ok(club, id);
    assert.ok(club.aliases.includes("Stuttgart"), id);
    for (const name of [club.name, ...club.aliases]) {
      assert.equal(isCurrentCompetitionClub(id, name), true);
      assert.equal(canonicalFootballClubId(name), "vfbstuttgart");
    }
  }
});

test("additional MLS identities do not grant membership in reviewed European competitions", () => {
  for (const id of Object.keys(FOOTBALL_COMPETITIONS)) {
    for (const [canonical, alias] of reviewedSourceAliases.slice(1)) {
      assert.equal(isCurrentCompetitionClub(id, canonical), false, `${id}: ${canonical}`);
      assert.equal(isCurrentCompetitionClub(id, alias), false, `${id}: ${alias}`);
    }
  }
});

test("reviewed aliases never collapse youth, women, reserve or other squad variants", () => {
  for (const [canonical, alias, expectedID] of [...reviewedSourceAliases, ...reviewedLegalAliases]) {
    for (const name of [canonical, alias]) {
      for (const suffix of ["Women", "W", "U17", "U21", "Under 21", "Reserves", "II", "B", "2"]) {
        const squad = `${name} ${suffix}`;
        assert.equal(canonicalFootballClubId(squad), undefined, squad);
        assert.notEqual(canonicalFootballTeamKey(squad), expectedID, squad);
      }
    }
  }
});

test("reviewed aliases do not admit similar clubs or generic name fragments", () => {
  const seniorIDs = new Set(reviewedSourceAliases.map(([, , id]) => id));
  for (const name of ["Stuttgarter Kickers", "New York City FC", "RB Leipzig", "Red Bull Salzburg",
    "DC Power", "New York", "United", "Red Bull", "Stuttgart City"]) {
    assert.equal(seniorIDs.has(canonicalFootballClubId(name)), false, name);
    assert.equal(seniorIDs.has(canonicalFootballTeamKey(name)), false, name);
  }
});

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
