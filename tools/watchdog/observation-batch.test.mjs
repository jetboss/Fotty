import test from "node:test";
import assert from "node:assert/strict";
import { applyObservationBatch } from "./observation-batch.mjs";
import { createPolicy, emptyLedger, incidentKey } from "./incident-policy.mjs";

const NOW = Date.UTC(2026, 9, 11);
const versions = { observerRevision: "observer-1", configurationRevision: "config-1", deploymentRevision: "deployment-1" };
const policy = createPolicy({ environment: "qualification", windowMs: 1000, maxReceiptAgeMs: 10_000,
  admittedSources: ["cs", "streamex", "fixtures-service", "fixtures-mlb", "fixtures-icc"].map((source) => ({
    source, stages: ["manifest", "catalog", "integrity"], activation: "active", expected: versions,
  })),
});
const receipt = (window, changes = {}) => ({ environment: policy.environment, source: "cs", stage: "catalog",
  outcome: "failure", failureClass: "http-530", facts: {}, observedAt: NOW + window * 1000, versions, ...changes });
function batch(state, window, receipts) {
  return applyObservationBatch(state, receipts, policy, NOW + window * 1000);
}
function confirmed(changes = {}) {
  let state = emptyLedger(policy);
  for (let window = 0; window < 3; window++) state = batch(state, window, [receipt(window, changes)]).state;
  return state;
}
const success = (window, changes = {}) => receipt(window, { outcome: "success", failureClass: "metadata-contract", ...changes });

test("complete current metadata checks recover only the same provider stage after two distinct windows", () => {
  const key = incidentKey(receipt(0));
  let state = confirmed();
  const wrongPaths = [{ source: "streamex" }, { stage: "manifest" }, { facts: { scope: "other" } }];
  for (const path of wrongPaths) {
    state = batch(state, 3, [success(3, path)]).state;
    assert.equal(state.incidents[key].state, "confirmed");
    assert.equal(state.incidents[key].successCount, 0);
  }
  state = batch(state, 4, [success(4)]).state;
  assert.equal(state.incidents[key].state, "recovering");
  assert.equal(batch(state, 4, [success(4)]).state.incidents[key].successCount, 1);
  const final = batch(state, 5, [success(5)]);
  assert.equal(final.state.incidents[key].state, "resolved");
  assert.deepEqual(final.events.map((row) => row.type), ["resolved"]);
});

test("all three revisions must match; stale or wrong-version healthy checks cannot borrow recovery", () => {
  const state = confirmed(), key = incidentKey(receipt(0));
  for (const field of Object.keys(versions)) {
    const result = batch(state, 3, [success(3, { versions: { ...versions, [field]: "old" } })]);
    assert.equal(result.state.incidents[key].successCount, 0);
    assert.equal(result.state.incidents[key].state, "confirmed");
    assert.equal(result.state.coverage["cs/catalog"].versionMatches, false);
  }
  const stale = batch(state, 20, [success(0)]);
  assert.equal(stale.state.incidents[key].successCount, 0);
  assert.equal(stale.state.incidents[key].state, "confirmed");
});

test("matching failure dominates a contradictory complete check in either batch order", () => {
  const key = incidentKey(receipt(0));
  for (const rows of [[success(3), receipt(3)], [receipt(3), success(3)]]) {
    const result = batch(confirmed(), 3, rows);
    assert.equal(result.state.incidents[key].state, "confirmed");
    assert.equal(result.state.incidents[key].successCount, 0);
    assert.equal(result.events.some((row) => row.type === "resolved"), false);
  }
});

test("normalized exact facts recover independently; healthy sports cannot recover cricket", () => {
  const cricket = { source: "fixtures-service", stage: "integrity", facts: { scope: "cricket" }, failureClass: "coverage-gap" };
  const sports = { source: "fixtures-service", stage: "integrity", facts: { scope: "sports" }, failureClass: "endpoint-unavailable" };
  let state = emptyLedger(policy);
  for (let window = 0; window < 3; window++) state = batch(state, window, [receipt(window, cricket), receipt(window, sports)]).state;
  const cricketKey = incidentKey(receipt(0, cricket)), sportsKey = incidentKey(receipt(0, sports));
  for (let window = 3; window < 5; window++) state = batch(state, window, [success(window, {
    source: "fixtures-service", stage: "integrity", facts: { scope: "SPORTS" },
  })]).state;
  assert.equal(state.incidents[sportsKey].state, "resolved");
  assert.equal(state.incidents[cricketKey].state, "confirmed");
  assert.equal(state.incidents[cricketKey].successCount, 0);
});

for (const failureClass of ["same-upstream-current-omission", "same-upstream-fixture-disagreement",
  "same-upstream-refresh-required", "independent-current-omission", "independent-kickoff-disagreement", "independent-status-disagreement"]) {
  test(`${failureClass} needs its exact checker, not accepted-snapshot recovery`, () => {
    const changes = { source: "fixtures-icc", stage: "integrity", facts: { scope: "cricket", factHash: "a".repeat(64) }, failureClass };
    const key = incidentKey(receipt(0, changes));
    let state = confirmed(changes);
    for (let window = 3; window < 5; window++) state = batch(state, window, [success(window, {
      ...changes, failureClass: "accepted-snapshot",
    })]).state;
    assert.equal(state.incidents[key].state, "confirmed");
    assert.equal(state.incidents[key].successCount, 0);
    state = batch(state, 5, [success(5, changes)]).state;
    state = batch(state, 6, [success(6, changes)]).state;
    assert.equal(state.incidents[key].state, "resolved");
  });
}

test("inactive and unknown checks never create or recover an outage", () => {
  const key = incidentKey(receipt(0));
  for (const outcome of ["inactive", "unknown"]) {
    const empty = batch(emptyLedger(policy), 0, [receipt(0, { outcome })]);
    assert.deepEqual(empty.state.incidents, {});
    let state = confirmed();
    for (let window = 3; window < 5; window++) state = batch(state, window, [receipt(window, { outcome })]).state;
    assert.equal(state.incidents[key].state, "confirmed");
    assert.equal(state.incidents[key].successCount, 0);
  }
});

test("different-class unknown or inactive checks interrupt an in-progress mapped recovery", () => {
  const key = incidentKey(receipt(0));
  for (const [outcome, failureClass] of [["unknown", "budget-exhausted"], ["inactive", "activation-pending"]]) {
    let state = batch(confirmed(), 3, [success(3)]).state;
    assert.equal(state.incidents[key].successCount, 1);
    state = batch(state, 4, [receipt(4, { outcome, failureClass })]).state;
    assert.equal(state.incidents[key].state, "confirmed");
    assert.equal(state.incidents[key].successCount, 0);
    state = batch(state, 5, [success(5)]).state;
    assert.equal(state.incidents[key].state, "recovering");
    assert.equal(state.incidents[key].successCount, 1);
    assert.equal(batch(state, 6, [success(6)]).state.incidents[key].state, "resolved");
  }
});

test("an intervening wrong-revision complete check cannot preserve a mapped recovery count", () => {
  const key = incidentKey(receipt(0));
  for (const field of Object.keys(versions)) {
    let state = batch(confirmed(), 3, [success(3)]).state;
    state = batch(state, 4, [success(4, { versions: { ...versions, [field]: "old" } })]).state;
    assert.equal(state.incidents[key].state, "confirmed");
    assert.equal(state.incidents[key].successCount, 0);
    state = batch(state, 5, [success(5)]).state;
    assert.equal(state.incidents[key].state, "recovering");
    assert.equal(state.incidents[key].successCount, 1);
  }
});

test("observation batches reject oversized input and unadmitted routes", () => {
  assert.throws(() => batch(emptyLedger(policy), 0, Array(101).fill(success(0))), /bound/);
  assert.throws(() => batch(emptyLedger(policy), 0, [success(0, { source: "unreviewed" })]), /Unadmitted/);
});
