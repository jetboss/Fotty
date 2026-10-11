import { applyObservation, incidentKey, normalizeFacts, sameRevisions, validateLedger } from "./incident-policy.mjs";

// A fresh complete path check can clear only incidents whose exact scope/facts
// it actually checked. Neither sibling providers nor partial/unknown receipts
// qualify recovery. Omission/disagreement receipts require their own recheck.
const EXPLICIT_RECHECK_ONLY = new Set(["same-upstream-current-omission", "same-upstream-fixture-disagreement",
  "same-upstream-refresh-required", "independent-current-omission", "independent-kickoff-disagreement", "independent-status-disagreement"]);
export function applyObservationBatch(input, receipts, policy, now) {
  if (!Array.isArray(receipts) || receipts.length > 100) throw new Error("Observation batch exceeds bound");
  let state = input; const events = [], checked = new Set();
  function apply(receipt) {
    const result = applyObservation(state, receipt, policy, now);
    state = result.state; events.push(...result.events);
    // Stale receipts and capacity-refused writes do not establish a current
    // check. Track exact keys, not just a provider or shared fixture endpoint.
    if (!["stale", "overflow"].includes(result.result)) checked.add(incidentKey(receipt));
  }
  for (const receipt of receipts) {
    apply(receipt);
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
      apply({ ...receipt, outcome: effective, failureClass: incident.failureClass });
    }
  }
  // A collector may stop before dependent stages/cohorts (for example, a bad
  // CS manifest or wrong Worker revision). Silence is not a successful check:
  // break only existing unresolved streaks, retaining their exact facts and
  // policy ownership. Never invent an outage or a receipt for an absent source.
  for (const incident of Object.values(state.incidents)) {
    if (incident.state === "resolved" || checked.has(incident.key)) continue;
    apply({ environment: policy.environment, source: incident.source, stage: incident.stage,
      failureClass: incident.failureClass, facts: incident.facts, outcome: "unknown",
      observedAt: now, versions: policy.sources[incident.source].expected });
  }
  validateLedger(state, policy, input);
  return { state, events };
}
