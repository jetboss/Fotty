import test from "node:test";
import assert from "node:assert/strict";
import {
  deterministicFplScoringResponse,
  isFplScoringQuestion,
  resolveFplScoring,
} from "./fpl-scoring.mjs";

function player(id, name, elementType, team) {
  return { id, web_name: name, element_type: elementType, team };
}

function liveRow(id, points, minutes = 90) {
  return { id, stats: { total_points: points, minutes, played: minutes > 0 } };
}

function scoringFixture({ fixtureComplete = true, firstBenchType = 2 } = {}) {
  const players = [
    player(1, "Starting keeper", 1, 1),
    player(2, "Pedro Porro", 2, 2),
    player(3, "Captain", 2, 3),
    player(4, "Defender", 2, 4),
    player(5, "Midfielder 1", 3, 5),
    player(6, "Midfielder 2", 3, 6),
    player(7, "Midfielder 3", 3, 7),
    player(8, "Midfielder 4", 3, 8),
    player(9, "Forward 1", 4, 9),
    player(10, "Forward 2", 4, 10),
    player(11, "Forward 3", 4, 11),
    player(12, "Kelleher", 1, 12),
    player(13, "Wieffer", 2, 13),
    player(14, "Bench midfielder", 3, 14),
    player(15, "Bench forward", 4, 15),
  ];
  const starting = players.slice(0, 11).map((item, index) => ({
    element: item.id,
    position: index + 1,
    multiplier: item.id === 3 ? 2 : 1,
    is_captain: item.id === 3,
    is_vice_captain: item.id === 5,
  }));
  const outfieldBench = firstBenchType === 3
    ? [
        { element: 14, position: 13, multiplier: 0, is_captain: false, is_vice_captain: false },
        { element: 13, position: 14, multiplier: 0, is_captain: false, is_vice_captain: false },
        { element: 15, position: 15, multiplier: 0, is_captain: false, is_vice_captain: false },
      ]
    : [
        { element: 13, position: 13, multiplier: 0, is_captain: false, is_vice_captain: false },
        { element: 14, position: 14, multiplier: 0, is_captain: false, is_vice_captain: false },
        { element: 15, position: 15, multiplier: 0, is_captain: false, is_vice_captain: false },
      ];
  const picks = {
    active_chip: null,
    entry_history: { points: 50, event_transfers_cost: 0 },
    automatic_subs: [],
    picks: [
      ...starting,
      { element: 12, position: 12, multiplier: 0, is_captain: false, is_vice_captain: false },
      ...outfieldBench,
    ],
  };
  const live = {
    elements: [
      liveRow(1, 0, 0),
      liveRow(2, 0, 0),
      ...Array.from({ length: 9 }, (_, offset) => liveRow(offset + 3, 5)),
      liveRow(12, 7),
      liveRow(13, 7),
      liveRow(14, 8),
      liveRow(15, 2),
    ],
  };
  const fixtures = Array.from({ length: 7 }, (_, index) => ({
    event: 1,
    team_h: index * 2 + 1,
    team_a: index * 2 + 2,
    finished: false,
    finished_provisional: fixtureComplete,
  }));
  return {
    event: { id: 1, finished: false, data_checked: false },
    picks,
    live,
    fixtures,
    players,
  };
}

test("projects the goalkeeper and first legal outfield autosubs without asking the model", () => {
  const scoring = resolveFplScoring(scoringFixture());

  assert.equal(scoring.official_current_points, 50);
  assert.equal(scoring.computed_published_points, 50);
  assert.equal(scoring.projected_points_after_safe_autosubs, 64);
  assert.equal(scoring.displayed_points, 64);
  assert.deepEqual(
    scoring.projected_automatic_subs.map((substitution) => [substitution.in_name, substitution.out_name]),
    [["Kelleher", "Starting keeper"], ["Wieffer", "Pedro Porro"]]
  );

  const response = deterministicFplScoringResponse(scoring, "2026-08-24T12:00:00.000Z");
  assert.match(response.answer, /official snapshot currently shows \*\*50 points\*\*/i);
  assert.match(response.answer, /projects \*\*64 points\*\*/i);
  assert.equal(response.model, "Fotty FPL Rules Engine");
  assert.equal(response.usage.totalTokens, 0);
});

test("missing or invalid picked-player evidence never becomes a non-appearance or projection", () => {
  const mutations = [
    (input) => { input.live.elements = input.live.elements.filter((row) => row.id !== 1); },
    (input) => { input.live.elements = []; },
    (input) => { delete input.live.elements[0].stats.minutes; },
    (input) => { input.live.elements[0].stats.total_points = null; },
    (input) => { input.live.elements[0].stats.minutes = -1; },
    (input) => { input.live.elements.push(input.live.elements[0]); },
    (input) => { input.players = input.players.filter((row) => row.id !== 1); },
    (input) => { input.players.push(input.players[0]); },
    (input) => { input.picks.picks[1] = input.picks.picks[0]; },
  ];
  for (const mutate of mutations) {
    const input = scoringFixture();
    mutate(input);
    const scoring = resolveFplScoring(input);
    assert.equal(scoring.has_complete_scoring_data, false);
    assert.equal(scoring.displayed_points, 50, "Only the independently published total remains available");
    assert.equal(scoring.computed_published_points, null);
    assert.equal(scoring.projected_points_after_safe_autosubs, null);
    assert.deepEqual(scoring.projected_automatic_subs, []);
    assert.equal(scoring.projected_captain, null);
    const response = deterministicFplScoringResponse(scoring, new Date().toISOString());
    assert.equal(response.confidence, "low");
    assert.equal(response.officialDataStatus, "incomplete");
    assert.match(response.answer, /incomplete/i);
    assert.equal(response.usage.totalTokens, 0);
  }
});

test("unknown points stay unknown, while a genuine published zero remains zero", () => {
  for (const points of [undefined, null, "", "50"]) {
    const input = scoringFixture();
    input.live.elements = [];
    input.picks.entry_history.points = points;
    const scoring = resolveFplScoring(input);
    assert.equal(scoring.official_current_points, null);
    assert.equal(scoring.displayed_points, null);
    assert.doesNotMatch(deterministicFplScoringResponse(scoring).answer, /(?:null|undefined|0) points/);
  }
  const input = scoringFixture();
  input.live.elements = [];
  input.picks.entry_history.points = 0;
  assert.equal(resolveFplScoring(input).displayed_points, 0);
});

test("missing scoring produces a zero-token unavailable answer, not a model fallback", () => {
  const response = deterministicFplScoringResponse(null, new Date().toISOString());
  assert.equal(response.officialDataStatus, "unavailable");
  assert.equal(response.confidence, "low");
  assert.equal(response.usage.totalTokens, 0);
  assert.match(response.answer, /cannot verify/i);
});

test("a previous gameweek's picks cannot authorize a current total", () => {
  const input = scoringFixture();
  input.picks.entry_history.event = 2;
  assert.equal(resolveFplScoring(input), null);
});

test("a remaining double-gameweek fixture blocks a premature keeper autosub", () => {
  const input = scoringFixture();
  input.fixtures.push({ event: 1, team_h: 1, team_a: 15, finished: false, finished_provisional: false });
  const scoring = resolveFplScoring(input);
  assert.equal(scoring.players.find((row) => row.id === 1).confirmed_no_appearance, false);
  assert.equal(scoring.projected_automatic_subs.some((row) => row.out_id === 1), false);
});

test("Triple Captain preserves the threefold vice-captain inheritance", () => {
  const input = scoringFixture();
  input.picks.active_chip = "3xc";
  input.picks.picks.find((pick) => pick.is_captain).multiplier = 3;
  input.live.elements.find((row) => row.id === 3).stats = liveRow(3, 0, 0).stats;
  const scoring = resolveFplScoring(input);
  assert.equal(scoring.projected_captain.multiplier, 3);
  assert.equal(scoring.projected_captain.id, 5);
});

test("skips an earlier midfielder when a defender is required to preserve formation", () => {
  const input = scoringFixture({ firstBenchType: 3 });
  input.live.elements = input.live.elements.map((row) => row.id === 1 ? liveRow(1, 4) : row);
  input.picks.entry_history.points = 54;
  const scoring = resolveFplScoring(input);

  assert.deepEqual(scoring.projected_automatic_subs.map((substitution) => substitution.in_name), ["Wieffer"]);
  assert.equal(scoring.projected_automatic_subs[0].out_name, "Pedro Porro");
  assert.equal(scoring.projected_points_after_safe_autosubs, 61);
});

test("does not predict a substitution while the non-player still has a fixture remaining", () => {
  const scoring = resolveFplScoring(scoringFixture({ fixtureComplete: false }));

  assert.equal(scoring.projected_points_after_safe_autosubs, null);
  assert.deepEqual(scoring.projected_automatic_subs, []);
  assert.equal(scoring.displayed_points, 50);
});

test("does not override the official total after the gameweek is data-checked", () => {
  const input = scoringFixture();
  input.event.finished = true;
  input.event.data_checked = true;
  const scoring = resolveFplScoring(input);

  assert.equal(scoring.projected_points_after_safe_autosubs, null);
  assert.deepEqual(scoring.projected_automatic_subs, []);
  assert.equal(scoring.displayed_points, 50);
  assert.equal(scoring.status, "official-final");
});

test("promotes the vice-captain even when no bench replacement is available", () => {
  const input = scoringFixture();
  input.live.elements = input.live.elements.map((row) => {
    if (row.id === 3) return liveRow(3, 0, 0);
    if (row.id === 5) return liveRow(5, 6, 90);
    if (row.id === 1 || row.id === 2) return liveRow(row.id, 3, 90);
    if (row.id >= 12) return liveRow(row.id, 0, 0);
    return row;
  });
  input.picks.entry_history.points = 47;
  const scoring = resolveFplScoring(input);

  assert.deepEqual(scoring.projected_automatic_subs, []);
  assert.equal(scoring.projected_captain.name, "Midfielder 1");
  assert.equal(scoring.projected_captain.multiplier, 2);
  assert.equal(scoring.projected_points_after_safe_autosubs, 53);
  assert.equal(scoring.status, "provisional-rules");

  const response = deterministicFplScoringResponse(scoring, "2026-08-24T12:00:00.000Z");
  assert.match(response.answer, /inherits the captain multiplier/i);
  assert.equal(response.usage.totalTokens, 0);
});

test("bench boost scores the published bench without creating autosubs", () => {
  const input = scoringFixture();
  input.picks.active_chip = "bboost";
  input.picks.entry_history.points = 67;
  const scoring = resolveFplScoring(input);

  assert.deepEqual(scoring.projected_automatic_subs, []);
  assert.equal(scoring.projected_points_after_safe_autosubs, null);
  assert.equal(scoring.official_current_points, 67);
});

test("published official autosubs prevent a competing projection", () => {
  const input = scoringFixture();
  input.picks.automatic_subs = [{ element_in: 12, element_out: 1 }];
  input.picks.entry_history.points = 57;
  const scoring = resolveFplScoring(input);

  assert.equal(scoring.projected_points_after_safe_autosubs, null);
  assert.deepEqual(scoring.projected_automatic_subs, []);
  assert.equal(scoring.official_automatic_subs[0].in_name, "Kelleher");
  assert.equal(scoring.displayed_points, 57);
});

test("deducts transfer cost from a provisional rules total", () => {
  const input = scoringFixture();
  input.picks.entry_history.points = 46;
  input.picks.entry_history.event_transfers_cost = 4;
  const scoring = resolveFplScoring(input);

  assert.equal(scoring.transfer_cost, 4);
  assert.equal(scoring.computed_published_points, 46);
  assert.equal(scoring.projected_points_after_safe_autosubs, 60);
});

test("routes current total and automatic-substitution questions to deterministic scoring", () => {
  assert.equal(isFplScoringQuestion("Why is my correct total 50 when my bench should replace two non-players?"), true);
  assert.equal(isFplScoringQuestion("Will Kelleher auto sub for my goalkeeper?"), true);
  assert.equal(isFplScoringQuestion("Who should I captain next week?"), false);
});

test("direct current-score wording stays factual without swallowing future strategy", () => {
  for (const query of ["What is my current total?", "What are my current points?", "Show my live score", "What's my live gameweek total?", "What’s my current total?"]) {
    assert.equal(isFplScoringQuestion(query), true, query);
  }
  for (const query of ["How can I improve my score next week?", "What is my projected total next week?", "Who should I captain?", "Should I roll or take a hit?"]) {
    assert.equal(isFplScoringQuestion(query), false, query);
  }
});
