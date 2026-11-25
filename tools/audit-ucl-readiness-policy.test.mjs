import test from "node:test";
import assert from "node:assert/strict";
import { currentFixtureSources, hasUsableDescriptor } from "./audit-ucl-readiness-policy.mjs";

const now = Date.parse("2026-11-25T17:40:00Z"), match = { id: 575404, homeTeam: { name: "Sabah FK" }, awayTeam: { name: "FC Barcelona" }, utcDate: "2026-11-25T17:45:00Z" };
const fixtureID = "sports-fixture:champions-league:" + match.id;
const expiresAt = new Date(now + 60_000).toISOString();
const broadcast = { id: "b1", providerCode: "communitysports", sport: "football", kind: "event", streamID: "football:sample", expiresAt };
const link = { fixtureID, broadcastID: "b1", state: "listed", expiresAt, providerCode: "communitysports",
  fixtureFingerprint: { fixtureID, competitionID: "champions-league", sport: "football", participants: ["Sabah FK", "FC Barcelona"], start: match.utcDate } };
const check = (broadcasts, links) => currentFixtureSources({ broadcasts, links }, match, now);

test("one fresh official fixture association yields one reviewed origin descriptor URL", () => {
  assert.deepEqual([...check([broadcast], [link, link]).descriptors], [["https://nuviosports.xyz/stream/tv/football%3Asample.json", "communitysports"]]);
});
test("expired, mismatched, unresolved and guide-only rows cannot prove public descriptor readiness", () => {
  for (const change of [{ fixtureID: "other" }, { providerCode: "plaviosports" }, { expiresAt: new Date(now).toISOString() },
    { state: "ambiguous" }, { fixtureFingerprint: { ...link.fixtureFingerprint, participants: ["Other Club", "FC Barcelona"] } }, { fixtureFingerprint: { ...link.fixtureFingerprint, start: "2026-11-25T20:00:00Z" } }]) {
    assert.equal(check([broadcast], [{ ...link, ...change }]).descriptors.size, 0);
  }
  for (const change of [{ expiresAt: "" }, { kind: "channel" }, { streamID: "" }]) {
    assert.equal(check([{ ...broadcast, ...change }], [link]).descriptors.size, 0);
  }
  assert.equal(check([{ ...broadcast, providerCode: "score808" }], [{ ...link, providerCode: "score808" }]).descriptors.size, 0);
});
test("a descriptor must advertise an HTTPS stream rather than an obsolete embed or a listing", () => {
  assert.equal(hasUsableDescriptor({ streams: [{ url: "https://media.example/fixture.m3u8" }] }), true);
  for (const body of [{}, { streams: [{ embedUrl: "https://embed.example" }] }, { streams: [{ url: "http://media.example/live" }] },
    { streams: [{ url: "https://name:password@media.example/live" }] }]) assert.equal(hasUsableDescriptor(body), false);
});

test("a verified TV assignment is visible separately from cloud-resolvable descriptors", () => {
  const result = check([{ ...broadcast, providerCode: "reviewedtv", channelID: "sports-channel:espn-latinamerica-south" }],
    [{ ...link, providerCode: "reviewedtv" }]);
  assert.equal(result.deviceStations.size, 1);
  assert.equal(result.descriptors.size, 0);
});
