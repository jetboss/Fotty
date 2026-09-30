import { abortable, coachDeadline } from "./coach-safety.mjs";

// Identity is resolved from this request's official bootstrap, never from a
// projection shortlist, assistant prose, historical IDs or fuzzy name distance.
const normalize = (text) => String(text || "").normalize("NFKD").replace(/\p{M}/gu, "")
  .toLowerCase().replace(/(\p{L})[’']s\b/gu, "$1").replace(/[’']/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
const aliases = (player) => [...new Set([player.web_name, player.second_name,
  `${player.first_name || ""} ${player.second_name || ""}`].map(normalize).filter(Boolean))];
const words = new Set(("i me my you your we our he his him they their them it its this that those these a an the "
  + "who what why how when where should could would can do does is are was will not yes no please about "
  + "compare versus vs or and for with from to in on at of out if as instead still more less now next last "
  + "buy sell keep hold start bench captain replace consider swap bring transfer transfers roll plan advice "
  + "budget premium cheap defender defenders midfielder midfielders forward forwards goalkeeper keepers "
  + "player players squad team club chip wildcard free hit points gameweek gw fpl minutes injury injured "
  + "availability form fixtures fixture double blank deadline news price cost scoring autosubs total "
  + "risk option options alternative alternatives current official evidence recheck earlier question "
  + "using same best better safe fit fitnes fitness starting likely expected chance projection full season "
  + "audit whole five gameweeks explain tell suggest analyse analyze check help rebuild rate assess optimize optimise lab ive make avoid week").split(/\s+/));

function possibleUnknownNames(query, matchedAliases, teamNames) {
  const candidates = [];
  const add = (phrase) => {
    const parts = normalize(phrase).split(" ");
    const clean = [];
    for (const part of parts) {
      if (words.has(part) || /^\d+$/.test(part)) break;
      clean.push(part);
    }
    const name = clean.join(" ");
    if (name.length < 3 || clean.length > 4 || teamNames.has(name)) return;
    if (matchedAliases.some((alias) => alias === name || alias.includes(`${name} `)
      || alias.endsWith(` ${name}`) || name.includes(alias))) return;
    candidates.push(name);
  };
  for (const match of query.matchAll(/[“"]([^”"]{2,70})[”"]/gu)) add(match[1]);
  // Capitalized names and common lowercase player-question constructions. This
  // is deliberately not a universal NLP parser: unresolved wording is never
  // advertised as proof that every player mentioned has been identified.
  for (const match of query.matchAll(/\b\p{Lu}[\p{L}’'-]*(?:\s+\p{Lu}[\p{L}’'-]*){0,3}/gu)) add(match[0]);
  for (const match of query.matchAll(/(?:what about|compare|versus|\bvs|\bor|\band|buy|sell|keep|hold|start|bench|captain|replace|consider|bring in)\s+([\p{L}’'-]+(?:\s+[\p{L}’'-]+){0,3})/giu)) add(match[1]);
  if (normalize(query).split(" ").length <= 2) add(query);
  return [...new Set(candidates)].slice(0, 8);
}

export function resolveCoachPlayers({ query, history = [], players = [], teams = [] }) {
  const catalog = players.filter((player) => Number.isSafeInteger(player.id) && player.id > 0);
  const aliasMap = new Map();
  for (const player of catalog) for (const alias of aliases(player)) {
    if (!aliasMap.has(alias)) aliasMap.set(alias, []);
    aliasMap.get(alias).push(player);
  }
  const teamNames = new Set(teams.flatMap((team) => [normalize(team.name), normalize(team.short_name)]));
  const scan = (text) => {
    const normalized = ` ${normalize(text)} `;
    const spans = [];
    for (const [alias, candidates] of aliasMap) {
      let start = normalized.indexOf(` ${alias} `);
      while (start !== -1) {
        spans.push({ start, end: start + alias.length + 2, alias, candidates });
        start = normalized.indexOf(` ${alias} `, start + 1);
      }
    }
    const selected = [];
    for (const span of spans.sort((a, b) => (b.end - b.start) - (a.end - a.start))) {
      if (!selected.some((other) => span.start < other.end - 1 && span.end - 1 > other.start)) selected.push(span);
    }
    const mentions = selected.sort((a, b) => a.start - b.start).map(({ alias, candidates }) => {
      const clubMatches = candidates.filter((player) => {
        const team = teams.find((item) => item.id === player.team);
        return [team?.name, team?.short_name].map(normalize).filter(Boolean)
          .some((name) => normalized.includes(` ${name} `));
      });
      const choices = candidates.length > 1 && clubMatches.length === 1 ? clubMatches : candidates;
      return { mention: alias, status: choices.length === 1 ? "resolved" : "ambiguous",
        candidates: choices.map((player) => ({ id: player.id, name: `${player.first_name || ""} ${player.second_name || player.web_name}`.trim(),
          team: teams.find((team) => team.id === player.team)?.name || player.team,
          selectable: player.can_select !== false && player.status !== "u" })) };
    });
    const unknown = possibleUnknownNames(text, selected.map((item) => item.alias), teamNames);
    mentions.push(...unknown.map((mention) => ({ mention, status: "not_in_current_bootstrap", candidates: [] })));
    const unique = [...new Map(mentions.map((item) => [`${item.status}|${item.mention}`, item])).values()];
    return unique.length > 8 ? [...unique.slice(0, 7), { mention: "more than eight player names", status: "too_many_players", candidates: [] }] : unique;
  };
  let mentions = scan(query);
  let origin = "question";
  const followup = /\b(him|his|he|them|their|they|both|those|same player|that player)\b/i.test(query);
  if (followup && !mentions.some((item) => item.status === "resolved")) {
    // The client includes the current user question in history. Skip it and
    // never promote an assistant's invented name to identity authority.
    const previous = history.filter((item) => item.role === "user" && normalize(item.content) !== normalize(query)).slice(-3).reverse();
    const prior = previous.length ? scan(previous[0].content) : [];
    origin = "previous_user_question";
    const resolved = prior.filter((item) => item.status === "resolved");
    const singular = /\b(him|his|he|same player|that player)\b/i.test(query);
    mentions = prior.length ? prior : [{ mention: "follow-up player", status: "missing_followup_context", candidates: [] }];
    if (singular && resolved.length > 1) {
      mentions = [{ mention: "follow-up player", status: "ambiguous_followup", candidates: resolved.flatMap((item) => item.candidates) }];
    }
  }
  const playerIDs = [...new Set(mentions.filter((item) => item.status === "resolved").map((item) => item.candidates[0].id))];
  return { origin, mentions, playerIDs, complete: mentions.every((item) => item.status === "resolved"),
    scope: "Exact current-bootstrap names only; no fuzzy identity or guaranteed natural-language coverage." };
}

export function coachPlayerClarification(resolution) {
  const unresolved = resolution?.mentions?.filter((item) => item.status !== "resolved") || [];
  if (!unresolved.length) return null;
  return unresolved.map((item) => item.status === "too_many_players" ? "Please narrow the question to at most eight named players (detailed histories are limited to four per question)." : item.candidates.length
    ? `Which ${item.mention} do you mean: ${item.candidates.map((player) => `${player.name} (${player.team})`).join(" or ")}?`
    : `I could not identify “${item.mention}” in the current official player evidence. Please give the player's full name and club; I cannot assume a former or missing player is currently selectable.`).join(" ");
}

export async function collectCoachPlayerHistory(playerIDs, { fetchJSON, signal, budgetMs = 4000, limit = 4, concurrency = 2 }) {
  const ids = [...new Set(playerIDs)].filter((id) => Number.isSafeInteger(id) && id > 0);
  const deadline = coachDeadline(signal, budgetMs);
  const outcomes = new Map(ids.map((id, index) => [id, { id, status: index < limit ? "unavailable" : "not_fetched_budget" }]));
  let cursor = 0;
  try {
    await Promise.all(Array.from({ length: Math.min(concurrency, ids.length, limit) }, async () => {
      while (cursor < Math.min(ids.length, limit) && !deadline.signal.aborted) {
        const id = ids[cursor++];
        try {
          const detail = await abortable(() => fetchJSON(`element-summary/${id}/`, deadline.signal), deadline.signal);
          if (!Array.isArray(detail?.history) || !Array.isArray(detail?.fixtures)) throw new Error("Invalid element summary");
          outcomes.set(id, { id, status: "fetched", checked_at: new Date().toISOString(),
            history: detail.history.slice(-8).map((row) => ({ round: row.round, fixture: row.fixture,
              minutes: row.minutes, starts: row.starts, total_points: row.total_points,
              expected_goals: row.expected_goals, expected_assists: row.expected_assists })),
            fixtures: detail.fixtures.slice(0, 12).map((row) => ({ id: row.id, event: row.event,
              kickoff_time: row.kickoff_time, is_home: row.is_home, difficulty: row.difficulty })) });
        } catch { signal?.throwIfAborted(); }
      }
    }));
    signal?.throwIfAborted();
    return ids.map((id) => outcomes.get(id));
  } finally { deadline.dispose(); }
}

export function coachContextConflicts(players, context) {
  const byID = new Map(players.map((player) => [player.id, player]));
  const rows = [...(context?.squad || []), ...(context?.captains || []),
    ...(context?.transferOptions || []).flatMap((item) => [item.in, item.out])];
  return rows.filter((row) => row?.name && byID.has(row.id) && !aliases(byID.get(row.id)).includes(normalize(row.name)))
    .slice(0, 8).map((row) => `Client label “${String(row.name).slice(0, 80)}” for ID ${row.id} disagrees with current official identity ${byID.get(row.id).web_name}. Use the official ID/name; client facts and projections are not verification.`);
}
