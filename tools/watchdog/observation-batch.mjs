import { applyObservation, normalizeFacts, sameRevisions, validateLedger } from "./incident-policy.mjs";

// A fresh complete path check can clear only incidents whose exact scope/facts
// it actually checked. Neither sibling providers nor partial/unknown receipts
// qualify recovery. Omission/disagreement receipts require their own recheck.
const EXPLICIT_RECHECK_ONLY = new Set(["same-upstream-current-omission", "same-upstream-fixture-disagreement",
  "same-upstream-refresh-required", "independent-current-omission", "independent-kickoff-disagreement", "independent-status-disagreement"]);
export function applyObservationBatch(input, receipts, policy, now) {
  if (!Array.isArray(receipts) || receipts.length > 100) throw new Error("Observation batch exceeds bound");
  let state = input; const events = [];
  for (const receipt of receipts) {
    const result = applyObservation(state, receipt, policy, now); state = result.state; events.push(...result.events);
    const effective = !sameRevisions(receipt.versions, policy.sources[receipt.source]?.expected) ? "unknown" : receipt.outcome;
    if (!["success", "unknown", "inactive"].includes(effective)) continue;
    const facts = JSON.stringify(normalizeFacts(receipt.facts));
    for (const incident of Object.values(state.incidents)) {
      if (incident.state === "resolved" || incident.source !== receipt.source || incident.stage !== receipt.stage
        || incident.failureClass === receipt.failureClass || (effective === "success" && EXPLICIT_RECHECK_ONLY.has(incident.failureClass))
        || JSON.stringify(incident.facts) !== facts) continue;
      // Failure dominates success for a path in this entire probe batch.
      if (receipts.some((row) => row.outcome === "failure" && row.source === incident.source && row.stage === incident.stage
        && row.failureClass === incident.failureClass && JSON.stringify(normalizeFacts(row.facts)) === facts)) continue;
      const recovery = applyObservation(state, { ...receipt, outcome: effective, failureClass: incident.failureClass }, policy, now);
      state = recovery.state; events.push(...recovery.events);
    }
  }
  validateLedger(state, policy, input);
  return { state, events };
}
