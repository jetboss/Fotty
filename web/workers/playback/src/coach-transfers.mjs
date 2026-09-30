// Optional structured proposals are validation inputs, never commands. Nothing
// here parses prose, submits transfers or reconstructs private selling values.
const id = (value) => Number.isSafeInteger(value) && value > 0;
const money = (value) => Number.isSafeInteger(value) && value >= 0;

export function coachTransferContext({ bootstrap, picks, manager, context = {} }) {
  const published = (picks?.picks || []).map((pick) => ({ id: pick.element, sellingPrice: pick.selling_price }));
  const local = (context.squad || []).map((pick) => ({ id: pick.id, sellingPrice: pick.sellingPrice }));
  const isDraft = context.isLocalDraft === true;
  const sameIDs = local.length === published.length && local.every((pick) => published.some((item) => item.id === pick.id));
  return {
    players: bootstrap?.elements || [], elementTypes: bootstrap?.element_types || [], settings: bootstrap?.game_settings || {},
    picks: isDraft ? local : published,
    baselineSource: isDraft ? "client local draft" : "published official lineup",
    baselineUncertain: !isDraft && local.length > 0 && !sameIDs,
    // Public bank is a last-deadline observation, not proof of today's private
    // post-transfer balance. A draft must supply its own adjusted assumption.
    bank: isDraft ? context.planningBank : picks?.entry_history?.bank ?? manager?.last_deadline_bank,
    budgetBasis: isDraft ? "client-supplied adjusted draft bank" : "published last-deadline bank",
  };
}

export function validateCoachTransfers(proposal, context) {
  const unverified = (reason) => ({ status: "unverified", structureChecked: false, budgetStatus: "unknown", reasons: [reason] });
  const invalid = (reason) => ({ status: "invalid", structureChecked: false, budgetStatus: "unknown", reasons: [reason] });
  if (proposal === undefined || proposal === null || (Array.isArray(proposal) && proposal.length === 0)) {
    return { status: "not_provided", structureChecked: false, budgetStatus: "unknown",
      reasons: ["No structured transfer route was supplied. Prose suggestions have not passed whole-squad or budget validation."] };
  }
  if (!Array.isArray(proposal) || proposal.length > 15 || !proposal.every((move) => move && id(move.out) && id(move.in) && move.out !== move.in)) {
    return invalid("The proposed transfer IDs are malformed or exceed the 15-move bound.");
  }
  if (!context?.players?.length || !context.picks?.length) return unverified("Current official player data and a complete baseline squad are required to validate this route.");
  if (context.baselineUncertain) return unverified("The client squad differs from the published squad without an explicit local-draft boundary. Confirm which baseline this route changes.");
  const players = new Map(context.players.map((player) => [player.id, player]));
  const owned = context.picks.map((pick) => pick.id);
  if (owned.length !== 15 || new Set(owned).size !== 15 || owned.some((value) => !players.has(value))) {
    return unverified("The baseline must contain 15 distinct players identified in the current official catalog.");
  }
  const outgoing = proposal.map((move) => move.out), incoming = proposal.map((move) => move.in);
  if (new Set(outgoing).size !== proposal.length || new Set(incoming).size !== proposal.length
    || outgoing.some((value) => incoming.includes(value))) return invalid("A complete route cannot repeat a player or buy and sell the same player.");
  if (outgoing.some((value) => !owned.includes(value))) return invalid("A proposed outgoing player is not owned in the selected baseline squad.");
  if (incoming.some((value) => owned.includes(value))) return invalid("A proposed incoming player is already owned in the selected baseline squad.");
  for (const move of proposal) {
    const out = players.get(move.out), next = players.get(move.in);
    if (!next) return invalid("A proposed incoming ID is missing from the current official catalog.");
    if (next.can_select === false || next.status === "u") return invalid("A proposed incoming player is not currently selectable in official FPL.");
    if (next.element_type !== out.element_type) return invalid("Each transfer must replace a player in the same official position.");
  }
  const finalIDs = owned.filter((value) => !outgoing.includes(value)).concat(incoming);
  const quotas = { 1: 2, 2: 5, 3: 5, 4: 3 };
  for (const type of context.elementTypes || []) if (id(type.id) && money(type.squad_select)) quotas[type.id] = type.squad_select;
  if (Object.values(quotas).reduce((total, value) => total + value, 0) !== 15
    || (context.settings?.squad_squadsize !== undefined && context.settings.squad_squadsize !== 15)) {
    return unverified("Current squad rules differ from the supported 15-player route contract.");
  }
  const positions = new Map(), clubs = new Map();
  for (const value of finalIDs) {
    const player = players.get(value);
    if (!id(player.element_type) || !id(player.team)) return unverified("Current official position or club evidence is missing for a resulting squad player.");
    positions.set(player.element_type, (positions.get(player.element_type) || 0) + 1);
    clubs.set(player.team, (clubs.get(player.team) || 0) + 1);
  }
  if (finalIDs.length !== 15 || new Set(finalIDs).size !== 15
    || Object.entries(quotas).some(([position, count]) => (positions.get(Number(position)) || 0) !== count)
    || [...positions.keys()].some((position) => quotas[position] === undefined)) return invalid("The complete resulting squad violates the official position quotas.");
  const clubLimit = id(context.settings?.squad_team_limit) ? context.settings.squad_team_limit : 3;
  if ([...clubs.values()].some((count) => count > clubLimit)) return invalid(`The combined route exceeds the ${clubLimit}-player limit for one club.`);

  const result = { status: "unverified", structureChecked: true, budgetStatus: "unknown",
    baselineSource: context.baselineSource, reasons: [] };
  if (!money(context.bank)) {
    result.reasons.push("Squad structure passes, but adjusted bank is unknown. Affordability and full route legality remain unverified.");
    return result;
  }
  let remaining = context.bank, usesCatalogSaleEstimate = false;
  for (const move of proposal) {
    const pick = context.picks.find((item) => item.id === move.out);
    const suppliedSale = pick?.sellingPrice;
    const sale = money(suppliedSale) ? suppliedSale : players.get(move.out).now_cost;
    const purchase = players.get(move.in).now_cost;
    if (!money(sale) || !money(purchase)) {
      result.reasons.push("Squad structure passes, but a price is missing. Affordability remains unverified.");
      return result;
    }
    usesCatalogSaleEstimate ||= !money(suppliedSale);
    remaining += sale - purchase;
  }
  result.estimatedBankAfter = remaining;
  result.budgetStatus = remaining < 0 ? "exceeds_estimate" : "passes_estimate";
  result.status = remaining < 0 ? "invalid" : "conditional";
  result.reasons.push(remaining < 0
    ? "The combined route overspends the supplied public/draft budget estimate. Do not present it as an affordable route."
    : "Whole-squad structure and the supplied budget estimate pass; this is conditional, not verified private-account affordability.");
  result.reasons.push(`Budget uses ${context.budgetBasis || "an explicitly supplied bank assumption"}; ${usesCatalogSaleEstimate
    ? "missing selling values are estimated from current catalog prices, not invented purchase history or private selling prices"
    : "available selling values still require confirmation in the official account"}. Verify bank, selling prices, free transfers and hit costs before confirming.`);
  return result;
}
