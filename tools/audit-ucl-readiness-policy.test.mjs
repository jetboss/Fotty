import assert from "node:assert/strict";
import test from "node:test";

import {
  listedRegistryLinkCount,
  supportedUCLSourceCodes,
} from "./audit-ucl-readiness-policy.mjs";

test("the readiness policy includes every catalog source accepted by playback", () => {
  assert.ok(supportedUCLSourceCodes.includes("admin"));
  assert.ok(supportedUCLSourceCodes.includes("hotel"));
});

test("only listed registry links for the exact official fixture count as ready", () => {
  const fixtureID = "sports-fixture:champions-league:551234";
  const snapshot = { links: [
    { fixtureID, broadcastID: "br:a", state: "listed" },
    { fixtureID, broadcastID: "br:a", state: "listed" },
    { fixtureID, broadcastID: "br:b", state: "expired" },
    { fixtureID, broadcastID: "br:c", state: "ambiguous" },
    { fixtureID: "sports-fixture:champions-league:551235", broadcastID: "br:d", state: "listed" },
    null,
  ] };
  assert.equal(listedRegistryLinkCount(snapshot, fixtureID), 1);
});

test("an unavailable or malformed registry is never proof of readiness", () => {
  assert.equal(listedRegistryLinkCount(null, "x"), 0);
  assert.equal(listedRegistryLinkCount({ links: "nope" }, "x"), 0);
  assert.equal(listedRegistryLinkCount({ schemaVersion: 1, activation: "pending" }, "x"), 0);
});
