import test from "node:test";
import assert from "node:assert/strict";
import { auditProviderPayloads, liveAuditVerdict } from "./audit-provider-football-identity.mjs";

const row = (extra) => ({ id: "m1", title: "Arsenal vs Chelsea", tournament: "Premier League", ...extra });

test("a renamed sport field is unreadable, not a pass over zero football rows", () => {
  const summary = auditProviderPayloads([{ host: "feed", events: [row({ sportName: "football" }), row({ sportName: "football" })] }]);
  assert.equal(summary.footballCount, 0);
  assert.equal(summary.unreadableCount, 2);
  const verdict = liveAuditVerdict(summary, { feeds: 1 });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.kind, "unreadable");
});

test("a readable feed with no football reports no coverage instead of passing", () => {
  const summary = auditProviderPayloads([{ host: "feed", events: [row({ sport: "basketball", title: "Lakers vs Celtics", tournament: "NBA" })] }]);
  assert.deepEqual([summary.footballCount, summary.unreadableCount], [0, 0]);
  assert.equal(liveAuditVerdict(summary, { feeds: 1 }).kind, "noFootball");
  assert.equal(liveAuditVerdict(summary, { feeds: 1 }).ok, false);
  assert.equal(liveAuditVerdict(summary, { feeds: 1, allowNoFootball: true }).ok, true);
});

test("readable football rows pass and are counted", () => {
  const summary = auditProviderPayloads([{ host: "feed", events: [row({ sport: "football" }), row({ category: "Soccer", id: "m2" })] }]);
  assert.equal(summary.footballCount, 2);
  const verdict = liveAuditVerdict(summary, { feeds: 1 });
  assert.equal(verdict.kind, "passed");
  assert.match(verdict.message, /2 football listings/);
});
