function integer(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

function hasAppeared(stats) {
  return stats?.played === true || integer(stats?.minutes) > 0;
}

// Ambiguous duplicate rows are unknown, never last-write-wins scoring evidence.
function uniqueRows(items, key) {
  const rows = new Map();
  const duplicates = new Set();
  for (const item of Array.isArray(items) ? items : []) {
    const id = item?.[key];
    if (!Number.isSafeInteger(id) || id <= 0) continue;
    if (rows.has(id)) duplicates.add(id);
    rows.set(id, item);
  }
  for (const id of duplicates) rows.delete(id);
  return rows;
}

function hasScoringStats(stats) {
  return Number.isSafeInteger(stats?.minutes) && stats.minutes >= 0
    && Number.isSafeInteger(stats?.total_points)
    && (stats.played === undefined || typeof stats.played === "boolean");
}

function fixtureState(fixtures, eventId, teamId) {
  const teamFixtures = (fixtures || []).filter((fixture) =>
    integer(fixture?.event) === eventId
      && (integer(fixture?.team_h) === teamId || integer(fixture?.team_a) === teamId)
  );
  if (!teamFixtures.length) return "unknown";
  return teamFixtures.every((fixture) => fixture?.finished === true || fixture?.finished_provisional === true)
    ? "complete"
    : "remaining";
}

function combinations(items, size, start = 0, current = [], result = []) {
  if (current.length === size) {
    result.push([...current]);
    return result;
  }
  for (let index = start; index <= items.length - (size - current.length); index += 1) {
    current.push(items[index]);
    combinations(items, size, index + 1, current, result);
    current.pop();
  }
  return result;
}

function isLegalOutfieldFormation(players) {
  const counts = new Map([[2, 0], [3, 0], [4, 0]]);
  for (const player of players) {
    counts.set(player.elementType, (counts.get(player.elementType) || 0) + 1);
  }
  return players.length <= 10
    && counts.get(2) >= 3 && counts.get(2) <= 5
    && counts.get(3) >= 2 && counts.get(3) <= 5
    && counts.get(4) >= 1 && counts.get(4) <= 3;
}

function preferredOutfieldSubs(activePlayers, eligibleBench, vacancies) {
  const maximum = Math.min(vacancies, eligibleBench.length);
  for (let size = maximum; size >= 0; size -= 1) {
    for (const candidate of combinations(eligibleBench, size)) {
      if (isLegalOutfieldFormation([...activePlayers, ...candidate])) return candidate;
    }
  }
  return [];
}

function pairSubstitutions(missing, incoming) {
  const remaining = [...missing];
  return incoming.map((playerIn) => {
    let outgoingIndex = remaining.findIndex((playerOut) => playerOut.elementType === playerIn.elementType);
    if (outgoingIndex < 0) outgoingIndex = 0;
    const [playerOut] = remaining.splice(outgoingIndex, 1);
    return { playerIn, playerOut };
  }).filter((pair) => pair.playerOut);
}

export function resolveFplScoring({ event, picks, live, fixtures, players }) {
  if (!Array.isArray(picks?.picks) || !picks.picks.length) return null;

  const eventId = integer(event?.id);
  if (!eventId) return null;
  if (picks.entry_history?.event != null && picks.entry_history.event !== eventId) return null;
  const playerById = uniqueRows(players, "id");
  const liveById = uniqueRows(live?.elements, "id");
  const validPicks = picks.picks.length === 15
    && uniqueRows(picks.picks, "element").size === 15
    && uniqueRows(picks.picks, "position").size === 15
    && picks.picks.every((pick) => pick.position <= 15
      && Number.isSafeInteger(pick.multiplier) && pick.multiplier >= 0 && pick.multiplier <= 3);
  const rows = picks.picks
    .map((pick) => {
      const id = integer(pick?.element);
      const player = playerById.get(id);
      if (!player) return null;
      const stats = liveById.get(id)?.stats;
      const statsKnown = hasScoringStats(stats);
      const state = fixtureState(fixtures, eventId, integer(player.team));
      return {
        id,
        name: String(player.web_name || `Player ${id}`),
        team: integer(player.team),
        elementType: integer(player.element_type),
        squadPosition: integer(pick.position),
        benchOrder: integer(pick.position) > 12 ? integer(pick.position) - 12 : null,
        starting: integer(pick.position) <= 11,
        captain: pick.is_captain === true,
        viceCaptain: pick.is_vice_captain === true,
        publishedMultiplier: Math.max(0, integer(pick.multiplier)),
        effectiveMultiplier: Math.max(0, integer(pick.multiplier)),
        statsKnown,
        minutes: statsKnown ? stats.minutes : null,
        played: statsKnown ? hasAppeared(stats) : null,
        points: statsKnown ? stats.total_points : null,
        fixtureState: state,
        confirmedNoAppearance: statsKnown && !hasAppeared(stats) && state === "complete",
      };
    })
    .filter(Boolean)
    .sort((left, right) => left.squadPosition - right.squadPosition);

  const hasCompleteScoringData = validPicks && rows.length === 15
    && rows.every((row) => row.statsKnown && [1, 2, 3, 4].includes(row.elementType) && row.team > 0);
  const transferCost = Math.max(0, integer(picks.entry_history?.event_transfers_cost));
  const computedPublishedPoints = hasCompleteScoringData ? rows.reduce(
    (total, row) => total + row.points * row.publishedMultiplier,
    -transferCost
  ) : null;
  const officialCurrentPoints = Number.isSafeInteger(picks.entry_history?.points)
    ? picks.entry_history.points
    : computedPublishedPoints;
  const officialAutomaticSubs = Array.isArray(picks.automatic_subs) ? picks.automatic_subs : [];
  const benchBoost = String(picks.active_chip || "").toLowerCase() === "bboost";

  let projectedPairs = [];
  let projectedCaptain = null;
  const eventIsFinal = event?.finished === true && event?.data_checked === true;
  if (hasCompleteScoringData && !benchBoost && !eventIsFinal && officialAutomaticSubs.length === 0) {
    const startingGoalkeeper = rows.find((row) => row.starting && row.elementType === 1);
    const benchGoalkeeper = rows.find((row) => !row.starting && row.elementType === 1);
    if (startingGoalkeeper?.confirmedNoAppearance && benchGoalkeeper?.played) {
      projectedPairs.push({ playerIn: benchGoalkeeper, playerOut: startingGoalkeeper });
    }

    const missingOutfield = rows.filter(
      (row) => row.starting && row.elementType !== 1 && row.confirmedNoAppearance
    );
    const activeOutfield = rows.filter(
      (row) => row.starting && row.elementType !== 1 && !row.confirmedNoAppearance
    );
    const eligibleBench = rows.filter(
      (row) => !row.starting && row.elementType !== 1 && row.played
    );
    const selectedBench = preferredOutfieldSubs(activeOutfield, eligibleBench, missingOutfield.length);
    projectedPairs.push(...pairSubstitutions(missingOutfield, selectedBench));
  }

  if (projectedPairs.length) {
    for (const row of rows) row.effectiveMultiplier = row.starting ? 1 : 0;
    for (const pair of projectedPairs) {
      pair.playerOut.effectiveMultiplier = 0;
      pair.playerIn.effectiveMultiplier = 1;
    }
  }

  // Captaincy is independent from whether a bench player can replace the
  // missing captain. It also still applies under Bench Boost. Keep this
  // projection separate until official FPL publishes the effective multiplier.
  if (hasCompleteScoringData && !eventIsFinal && officialAutomaticSubs.length === 0) {
    const captain = rows.find((row) => row.captain);
    const viceCaptain = rows.find((row) => row.viceCaptain);
    const captainMultiplier = Math.max(2, captain?.publishedMultiplier || 2);
    if (captain && captain.effectiveMultiplier > 0 && !captain.confirmedNoAppearance) {
      captain.effectiveMultiplier = captainMultiplier;
    } else if (viceCaptain?.played && viceCaptain.effectiveMultiplier > 0) {
      if (captain) captain.effectiveMultiplier = 0;
      viceCaptain.effectiveMultiplier = captainMultiplier;
      projectedCaptain = viceCaptain;
    }
  }

  const hasProjection = projectedPairs.length > 0 || projectedCaptain !== null;
  const projectedPoints = hasProjection
    ? rows.reduce((total, row) => total + row.points * row.effectiveMultiplier, -transferCost)
    : null;
  const officialSubs = officialAutomaticSubs.map((substitution) => {
    const playerIn = rows.find((row) => row.id === integer(substitution.element_in));
    const playerOut = rows.find((row) => row.id === integer(substitution.element_out));
    return {
      in_id: integer(substitution.element_in),
      in_name: playerIn?.name || `Player ${integer(substitution.element_in)}`,
      out_id: integer(substitution.element_out),
      out_name: playerOut?.name || `Player ${integer(substitution.element_out)}`,
    };
  });
  const projectedSubs = projectedPairs.map(({ playerIn, playerOut }) => ({
    in_id: playerIn.id,
    in_name: playerIn.name,
    in_points: playerIn.points,
    out_id: playerOut.id,
    out_name: playerOut.name,
    out_points: playerOut.points,
  }));

  return {
    gameweek: eventId,
    has_complete_scoring_data: hasCompleteScoringData,
    official_current_points: officialCurrentPoints,
    computed_published_points: computedPublishedPoints,
    projected_points_after_safe_autosubs: projectedPoints,
    displayed_points: projectedPoints ?? officialCurrentPoints,
    transfer_cost: transferCost,
    status: !hasCompleteScoringData ? "incomplete" : eventIsFinal
      ? "official-final"
      : hasProjection ? "provisional-rules" : "official-current",
    projected_captain: projectedCaptain ? {
      id: projectedCaptain.id,
      name: projectedCaptain.name,
      multiplier: projectedCaptain.effectiveMultiplier,
    } : null,
    official_automatic_subs: officialSubs,
    projected_automatic_subs: projectedSubs,
    players: rows.map((row) => ({
      id: row.id,
      name: row.name,
      position: row.elementType,
      squad_position: row.squadPosition,
      bench_order: row.benchOrder,
      starting: row.starting,
      captain: row.captain,
      vice_captain: row.viceCaptain,
      published_multiplier: row.publishedMultiplier,
      effective_multiplier: row.effectiveMultiplier,
      minutes: row.minutes,
      played: row.played,
      points: row.points,
      fixture_state: row.fixtureState,
      confirmed_no_appearance: row.confirmedNoAppearance,
    })),
  };
}

export function isFplScoringQuestion(query) {
  const text = String(query || "").toLowerCase();
  const currentScoreRequest = /\b(?:what(?:['’]s| is| are)|check|verify|show)\s+(?:my|the)\s+(?:current|live)\s+(?:gameweek\s+)?(?:points|total|score)\b/i;
  if (currentScoreRequest.test(text)) return true;
  return /auto(?:matic)?[-\s]?sub|substitut|bench.*(?:point|replace|come on)|(?:point|total|score).*(?:bench|sub|replace|did not play|didn't play|no minutes)|(?:did not play|didn't play|no minutes).*(?:point|total|sub|replace)|how many (?:gameweek )?points|correct (?:gameweek )?(?:points|total)|gameweek points/i.test(text);
}

export function deterministicFplScoringResponse(scoring, verifiedAt) {
  if (!scoring || !scoring.has_complete_scoring_data) {
    const official = scoring?.official_current_points;
    const hasOfficial = Number.isSafeInteger(official);
    return {
      answer: `${hasOfficial ? `The published official snapshot shows **${official} points**, but player-level scoring data is incomplete.` : "I cannot verify your gameweek total because official scoring data is unavailable or incomplete."} Missing data does not mean a player failed to appear. I cannot confirm automatic substitutions or a corrected total until the data is complete.`,
      confidence: "low",
      evidence: hasOfficial ? [`Published official points: ${official}; player-level evidence is incomplete.`] : ["No complete official scoring snapshot is available."],
      assumptions: ["Missing player statistics are unknown, not zero points or a confirmed non-appearance."],
      actions: ["Refresh Live Points and try again when official FPL data is available."],
      source: "Fotty rules engine",
      model: "Fotty FPL Rules Engine",
      verifiedAt: verifiedAt || new Date().toISOString(),
      officialDataStatus: scoring ? "incomplete" : "unavailable",
      usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0, cacheHitTokens: 0, cacheMissTokens: 0, reasoningTokens: 0 },
    };
  }
  const projected = scoring.projected_points_after_safe_autosubs;
  const official = scoring.official_current_points;
  const projectedSubs = scoring.projected_automatic_subs || [];
  const officialSubs = scoring.official_automatic_subs || [];
  const transferNote = scoring.transfer_cost > 0
    ? ` after the ${scoring.transfer_cost}-point transfer cost`
    : "";

  if (Number.isFinite(projected)) {
    const replacementText = projectedSubs
      .map((substitution) => `${substitution.in_name} (${substitution.in_points}) for ${substitution.out_name}`)
      .join("; ");
    const captainText = scoring.projected_captain
      ? `${scoring.projected_captain.name} inherits the captain multiplier`
      : "";
    const changes = [replacementText, captainText].filter(Boolean).join("; ");
    return {
      answer: `The official snapshot currently shows **${official} points**, but that total has not yet applied every proven FPL rule. Fotty's rules engine projects **${projected} points**${transferNote}: ${changes}. The ${projected}-point figure is the correct provisional total if the official live data remains unchanged.`,
      confidence: "high",
      evidence: [
        `Official current points: ${official}.`,
        ...projectedSubs.map((substitution) => `${substitution.in_name} played and scored ${substitution.in_points}; ${substitution.out_name}'s fixture is complete with no appearance.`),
        ...(scoring.projected_captain ? [`${scoring.projected_captain.name} played and inherits the captain multiplier because the published captain is confirmed out.`] : []),
        `Formation and goalkeeper-only substitution rules remain valid${scoring.transfer_cost > 0 ? `; ${scoring.transfer_cost} transfer points are deducted` : ""}.`,
      ],
      assumptions: ["Automatic substitutions and captaincy changes remain provisional until the official picks endpoint publishes them or the gameweek is data-checked."],
      actions: ["Refresh Live Points after FPL processes the pending rules; Fotty will then switch from projected to official."],
      source: "Fotty rules engine",
      model: "Fotty FPL Rules Engine",
      verifiedAt,
      officialDataStatus: "fresh-provisional",
      usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0, cacheHitTokens: 0, cacheMissTokens: 0, reasoningTokens: 0 },
    };
  }

  if (officialSubs.length) {
    const replacements = officialSubs.map((substitution) => `${substitution.in_name} for ${substitution.out_name}`).join("; ");
    return {
      answer: `Official FPL currently records **${official} points**${transferNote}. The published automatic substitutions are: ${replacements}.`,
      confidence: "high",
      evidence: [`Official current points: ${official}.`, `Official automatic substitutions: ${replacements}.`],
      assumptions: scoring.status === "official-final" ? [] : ["Bonus or corrections can still change until the gameweek is data-checked."],
      actions: scoring.status === "official-final" ? [] : ["Refresh after the remaining fixtures and data checks finish."],
      source: "Official FPL + Fotty rules engine",
      model: "Fotty FPL Rules Engine",
      verifiedAt,
      officialDataStatus: scoring.status === "official-final" ? "fresh-final" : "fresh",
      usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0, cacheHitTokens: 0, cacheMissTokens: 0, reasoningTokens: 0 },
    };
  }

  return {
    answer: `Official FPL currently records **${official} points**${transferNote}. Fotty cannot prove another eligible automatic substitution from the completed-fixture evidence yet, so it will not invent a different total.`,
    confidence: "high",
    evidence: [`Official current points: ${official}.`],
    assumptions: scoring.status === "official-final" ? [] : ["Players with a fixture remaining can still appear, and bonus or corrections can still change."],
    actions: scoring.status === "official-final" ? [] : ["Refresh after the relevant fixtures finish or FPL publishes automatic substitutions."],
    source: "Official FPL + Fotty rules engine",
    model: "Fotty FPL Rules Engine",
    verifiedAt,
    officialDataStatus: scoring.status === "official-final" ? "fresh-final" : "fresh",
    usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0, cacheHitTokens: 0, cacheMissTokens: 0, reasoningTokens: 0 },
  };
}
