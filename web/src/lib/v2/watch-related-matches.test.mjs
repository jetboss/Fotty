import test from "node:test";
import assert from "node:assert/strict";

const GENERIC_COMPETITION_LABELS = new Set([
  "football",
  "soccer",
  "sport",
  "sports",
  "live",
  "other",
  "international",
  "fotty live",
]);

function isGenericCompetitionLabel(value) {
  if (!value?.trim()) return true;
  return GENERIC_COMPETITION_LABELS.has(value.trim().toLowerCase());
}

function watchCompetitionSubtitle(match, leagueFromUrl) {
  for (const candidate of [match?.subtitle, match?.league, leagueFromUrl]) {
    const value = candidate?.trim();
    if (!value || isGenericCompetitionLabel(value)) continue;
    if (/^group\s+[a-l]$/i.test(value)) continue;
    return value;
  }
  return undefined;
}

function relatedWatchMatches(boardMatches, current, options) {
  const currentKey = current?.id || options.matchId || options.cid || "";
  const competition = current?.subtitle?.trim() || current?.league?.trim() || options.league?.trim();
  if (!competition || isGenericCompetitionLabel(competition)) return [];

  return boardMatches
    .filter((match) => {
      if ((match.id || match.cid) === currentKey) return false;
      const matchCompetition = match.subtitle?.trim() || match.league?.trim();
      return matchCompetition === competition;
    })
    .slice(0, 4);
}

function match(partial) {
  return {
    cid: partial.id,
    kind: "fixture",
    status: "Live",
    ...partial,
  };
}

test("watchCompetitionSubtitle hides misleading Group J for Argentina vs Egypt", () => {
  const argentinaEgypt = match({
    id: "arg-egy",
    title: "Argentina vs Egypt",
    league: "Football",
    sport: "Football",
    teams: { home: { name: "Argentina" }, away: { name: "Egypt" } },
  });

  assert.equal(watchCompetitionSubtitle(argentinaEgypt, "Group J"), undefined);
});

test("relatedWatchMatches avoids generic Football bucket", () => {
  const current = match({
    id: "arg-egy",
    title: "Argentina vs Egypt",
    league: "Football",
    teams: { home: { name: "Argentina" }, away: { name: "Egypt" } },
  });
  const board = [
    current,
    match({
      id: "club-1",
      title: "Sabah BA vs Other",
      league: "Football",
      teams: { home: { name: "Sabah BA" }, away: { name: "Other" } },
    }),
  ];

  assert.equal(relatedWatchMatches(board, current, { matchId: current.id }).length, 0);
});

test("relatedWatchMatches groups fixtures by competition label", () => {
  const current = match({
    id: "pl-1",
    title: "Arsenal vs Chelsea",
    league: "Premier League",
    teams: { home: { name: "Arsenal" }, away: { name: "Chelsea" } },
  });
  const sameLeague = match({
    id: "pl-2",
    title: "Liverpool vs Spurs",
    league: "Premier League",
    teams: { home: { name: "Liverpool" }, away: { name: "Spurs" } },
    eventSource: { source: "echo", id: "liverpool-spurs" },
  });
  const otherLeague = match({
    id: "ucl-1",
    title: "Real Madrid vs Bayern",
    league: "Champions League",
    teams: { home: { name: "Real Madrid" }, away: { name: "Bayern" } },
    eventSource: { source: "echo", id: "rm-bayern" },
  });

  const related = relatedWatchMatches([current, sameLeague, otherLeague], current, { matchId: current.id });
  assert.equal(related.length, 1);
  assert.equal(related[0]?.id, "pl-2");
});
