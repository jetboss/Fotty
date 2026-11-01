import test from "node:test";
import assert from "node:assert/strict";
import { validateReviewedTVGuide, currentReviewedTVGuide } from "./reviewed-tv-guide.mjs";
const now = new Date("2026-10-31T22:00:00Z");
const row = (id = "a", extra = {}) => ({ id: "tv-guide:" + id.repeat(64), channelID: "sports-channel:espn2-latinamerica-south",
  market: "UY", sport: "baseball", title: "MLB – World Series – Game #6 (if necessary)", start: "2026-11-01T00:00:00.000Z",
  observedAt: now.toISOString(), expiresAt: new Date(+now + 4 * 3600000).toISOString(), ...extra });
test("scheduled guide retains source conditionals without inventing a fixture, end or current programme", () => {
  const result = validateReviewedTVGuide([row()], now); assert.equal(result.length, 1);
  assert.equal(result[0].title, row().title); assert.equal(result[0].end, undefined); assert.equal(result[0].fixtureID, undefined);
});
test("unreviewed markets/stations, media locations and malformed receipts reject only the guide contract", () => {
  for (const change of [{market:"US"},{channelID:"sports-channel:espn8-latinamerica-south"},{sport:"unknown"},
    {title:"https://private.example/media"},{title:"Hidden\u202eprogramme"},{start:"bad"},
    {observedAt:new Date(+now+300001).toISOString()},{expiresAt:new Date(+now+4*3600000+1).toISOString()},
    {url:"https://unreviewed.example"},{fixtureID:"invented"}]) assert.throws(()=>validateReviewedTVGuide([row("a",change)],now));
});
test("same-station simultaneous conflicts leave unrelated stations available", () => {
  const rows=[row(),row("b",{title:"Different programme"}),row("c",{channelID:"sports-channel:espn3-latinamerica-south"})];
  assert.deepEqual(validateReviewedTVGuide(rows,now).map(r=>r.id),[rows[2].id]);
});
test("original expiry is preserved and expired guide data cannot be renewed by reading", () => {
  assert.equal(currentReviewedTVGuide([row()],new Date(+now+4*3600000)).length,0);
  assert.equal(currentReviewedTVGuide([row()],new Date(+now+1000))[0].observedAt,now.toISOString());
});
test("bounded metadata rejects duplicate identities and oversized collections", () => {
  assert.throws(()=>validateReviewedTVGuide([row(),row()],now));
  assert.throws(()=>validateReviewedTVGuide(Array(301).fill(row()),now));
});
