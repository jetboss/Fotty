import test from "node:test";
import assert from "node:assert/strict";
import { REVIEWED_TV_PROGRAMME_SOURCE, reviewedTVProgrammeURL, parseReviewedTVProgrammes as parse } from "./reviewed-tv-programmes.mjs";

const now = new Date("2026-10-30T13:30:00Z");
const attributes = (values) => Object.entries(values).map(([key, value]) => `${key}="${String(value).replaceAll("&", "&amp;").replaceAll('"', "&quot;")}"`).join(" ");
const row = (changes = {}) => `<div ${attributes({ "data-callsign": "Willow", "data-st": "2026-10-30 09:00:00", "data-et": "",
  "data-duration": "120", "data-listdatetime": "2026-10-30 09:00:00", "data-listingid": "123",
  "data-showname": "Test Cricket", "data-episodetitle": "South Africa vs. Australia", "data-description": "3rd Test, Day 4.",
  "data-live": "1", "data-repeat": "", ...changes })}></div>`;
const page = (rows = row(), zone = "America/Port_of_Spain", heading = "TV Schedule for Willow Cricket") => `<h1>${heading}</h1>
  <select id="timezone_selector"><option value="America/New_York">Eastern</option><option value="${zone}" selected>Selected</option></select>${rows}`;

test("fixed URL is the reviewed main station and uses an explicit UTC calendar date", () => {
  assert.equal(reviewedTVProgrammeURL(new Date("2026-10-31T01:00:00Z")), "https://www.tvpassport.com/tv-listings/stations/willow-cricket/15964/2026-10-31");
  for (const value of ["2026-10-30", new Date("invalid"), new Date("1999-12-31T00:00:00Z")]) assert.throws(() => reviewedTVProgrammeURL(value), /invalid-collection/u);
});

test("observed contract emits a current Test programme with station-bound hashed identity and no raw listing ID", async () => {
  const result = await parse(page(), { now }), [record] = result.broadcasts;
  assert.equal(result.providerCode, "reviewedtv"); assert.deepEqual(result.scopes, [{ scope: "cricket", status: "available", complete: true }]);
  assert.equal(result.guideTimeZone, "America/Port_of_Spain");
  assert.deepEqual(record.participants, ["South Africa", "Australia"]); assert.equal(record.format, "Test");
  assert.equal(record.matchOrdinal, 3); assert.equal(record.day, 4);
  assert.equal(record.start, "2026-10-30T13:00:00.000Z"); assert.equal(record.end, "2026-10-30T15:00:00.000Z");
  assert.equal(record.observedAt, now.toISOString()); assert.equal(record.expiresAt, "2026-10-30T13:40:00.000Z");
  assert.equal(record.channelID, "cricket-channel:willow"); assert.equal(record.streamID, "reviewed-tv:willow-main");
  assert.match(record.providerEventID, /^reviewed-tv:programme:[a-f0-9]{64}$/u);
  assert.equal(record.kind, "programme"); assert.equal(record.verification, "dated");
  assert.ok(!JSON.stringify(result).includes('"123"')); assert.ok(!JSON.stringify(result).includes("https://"));
  const changedRawID = await parse(page(row({ "data-listingid": "unretained-other-id" })), { now });
  assert.equal(changedRawID.broadcasts[0].providerEventID, record.providerEventID);
});

test("observed main-Willow T20I and ODI shows retain explicit format and ordinal", async () => {
  // Labels were observed in the publisher's 1/4 November main-Willow guide;
  // the fixed interval here is a parser fixture, not live playback evidence.
  for (const [show, description, format] of [
    ["T20 Cricket", "3rd T20I.", "T20"],
    ["T20 Cricket", "3rd T20.", "T20"],
    ["One-Day International Cricket", "1st ODI.", "ODI"],
  ]) {
    const result = await parse(page(row({ "data-showname": show, "data-description": description,
      "data-episodetitle": "Afghanistan vs. Zimbabwe" })), { now });
    assert.equal(result.broadcasts.length, 1);
    const record = result.broadcasts[0];
    assert.deepEqual(record.participants, ["Afghanistan", "Zimbabwe"]);
    assert.equal(record.format, format); assert.equal(record.matchOrdinal, format === "ODI" ? 1 : 3);
    assert.equal(record.day, undefined);
    assert.equal(record.kind, "programme"); assert.equal(record.channelID, "cricket-channel:willow");
    assert.equal(record.start, "2026-10-30T13:00:00.000Z");
    assert.equal(record.end, "2026-10-30T15:00:00.000Z");
  }
});

test("limited-overs programme identity rejects mismatched format, invalid ordinal and Test-day claims", async () => {
  for (const [show, description] of [
    ["T20 Cricket", "3rd ODI."], ["One-Day International Cricket", "3rd T20I."],
    ["T20 Cricket", "3th T20I."], ["One-Day International Cricket", "11st ODI."],
    ["T20 Cricket", "T20I."], ["One-Day International Cricket", "ODI."],
    ["T20 Cricket", "3rd T20I, Day 1."], ["One-Day International Cricket", "3rd ODI, Day 1."],
    ["T20 Cricket", "3rd T20I. Replay"], ["One-Day International Cricket", "1st ODI. Highlights"],
    ["Cricket Preview", "3rd T20I."], ["Cricket Review", "1st ODI."],
  ]) assert.equal((await parse(page(row({ "data-showname": show, "data-description": description })), { now })).broadcasts.length, 0);
  const women = await parse(page(row({ "data-showname": "One-Day International Cricket", "data-description": "2nd ODI.",
    "data-episodetitle": "India Women vs. Zimbabwe Women" })), { now });
  assert.deepEqual(women.broadcasts[0].participants, ["India Women", "Zimbabwe Women"]);
});

test("limited-overs shows keep exact station, current interval, LIVE and repeat fences", async () => {
  const match = { "data-showname": "One-Day International Cricket", "data-description": "5th ODI.",
    "data-episodetitle": "Namibia vs. Ireland" };
  for (const change of [{ "data-live": "" }, { "data-repeat": "1" }, { "data-episodetitle": "Namibia vs. Ireland Review" }])
    assert.equal((await parse(page(row({ ...match, ...change })), { now })).broadcasts.length, 0);
  assert.equal((await parse(page(row(match)), { now: new Date("2026-10-30T15:00:00Z") })).broadcasts.length, 0);
  await assert.rejects(parse(page(row({ ...match, "data-callsign": "WillowExtra" })), { now }), /invalid-collection/u);
  await assert.rejects(parse(page(row({ ...match, "data-st": "2026-10-30 24:00:00" })), { now }), /invalid-collection/u);
  await assert.rejects(parse(page(row(match) + row({ ...match, "data-listingid": "456", "data-description": "4th ODI." })), { now }), /invalid-collection/u);
});

test("only the current interval is emitted, and expiry cannot outlive the programme", async () => {
  assert.equal((await parse(page(), { now: new Date("2026-10-30T12:59:59Z") })).broadcasts.length, 0);
  assert.equal((await parse(page(), { now: new Date("2026-10-30T13:00:00Z") })).broadcasts.length, 1);
  assert.equal((await parse(page(), { now: new Date("2026-10-30T14:58:00Z") })).broadcasts[0].expiresAt, "2026-10-30T15:00:00.000Z");
  const ended = await parse(page(), { now: new Date("2026-10-30T15:00:00Z") });
  assert.equal(ended.broadcasts.length, 0); assert.equal(ended.scopes[0].status, "empty");
  const midnight = await parse(page(), { now: new Date("2026-10-31T01:00:00Z") });
  assert.equal(midnight.guideTimeZone, "America/Port_of_Spain", "Collector can derive the actual selected local retrieval date even for an empty interval");
  assert.equal(midnight.broadcasts.length, 0);
});

test("actual selected IANA timezone is required, with no abbreviation or UTC fallback", async () => {
  for (const zone of ["", "EST", "-04:00", "invalid/zone"]) await assert.rejects(parse(page(row(), zone), { now }), /invalid-collection/u);
  await assert.rejects(parse(page().replace(" selected", ""), { now }), /invalid-collection/u);
  await assert.rejects(parse(page().replace('value="America/New_York"', 'selected value="America/New_York"'), { now }), /invalid-collection/u);
  await assert.rejects(parse(page().replace('id="timezone_selector"', 'id="other"'), { now }), /invalid-collection/u);
});

test("DST conversion follows the explicit IANA zone and rejects gap/fold clocks", async () => {
  const make = (stamp) => page(row({ "data-st": stamp, "data-listdatetime": stamp }), "America/New_York");
  const summer = await parse(make("2026-07-01 09:00:00"), { now: new Date("2026-07-01T13:30:00Z") });
  assert.equal(summer.broadcasts[0].start, "2026-07-01T13:00:00.000Z");
  const winter = await parse(make("2026-12-01 09:00:00"), { now: new Date("2026-12-01T14:30:00Z") });
  assert.equal(winter.broadcasts[0].start, "2026-12-01T14:00:00.000Z");
  for (const stamp of ["2026-03-08 02:30:00", "2026-11-01 01:30:00"]) await assert.rejects(parse(make(stamp), { now }), /invalid-collection/u);
});

test("station heading and per-row callsign cannot impersonate main Willow", async () => {
  for (const heading of ["TV Schedule for Willow Extra", "TV Schedule for Willow Sports", "TV Schedule for Willow Cricket HD"])
    await assert.rejects(parse(page(row(), undefined, heading), { now }), /invalid-collection/u);
  for (const callsign of ["WillowExtra", "Willow Sports FAST", "Willow2", ""]) await assert.rejects(parse(page(row({ "data-callsign": callsign })), { now }), /invalid-collection/u);
});

test("review, highlights, preview and replay never prove a live match despite LIVE markers", async () => {
  for (const name of ["Cricket Review", "Cricket Highlights", "Test Cricket Preview", "Test Cricket Replay", "One-Day International Cricket", "T20 Cricket"])
    assert.equal((await parse(page(row({ "data-showname": name })), { now })).broadcasts.length, 0);
  for (const changes of [{ "data-repeat": "1" }, { "data-live": "" }, { "data-description": "3rd Test, Day 4. Replay" },
    { "data-episodetitle": "South Africa vs. Australia Highlights" }]) assert.equal((await parse(page(row(changes)), { now })).broadcasts.length, 0);
});

test("format ordinal day and both literal participants must be explicit and valid", async () => {
  for (const description of ["3 Test series", "3th Test, Day 4.", "3rd Test, Day 0.", "3rd Test, Day 7.", "3rd Test.", "Test, Day 4.", "3rd ODI, Day 4."])
    assert.equal((await parse(page(row({ "data-description": description })), { now })).broadcasts.length, 0);
  for (const episode of ["South Africa", "South Africa vs. TBC", "Australia vs. Australia", "South Africa vs. Australia vs. India", "South Africa vs. https://private.invalid", "South Africa vs. Australia\u202e"])
    assert.equal((await parse(page(row({ "data-episodetitle": episode })), { now })).broadcasts.length, 0);
  const women = await parse(page(row({ "data-episodetitle": "South Africa Women vs. Australia Women" })), { now });
  assert.deepEqual(women.broadcasts[0].participants, ["South Africa Women", "Australia Women"], "Never remove squad qualifiers");
});

test("strict published dates and bounded durations reject rollover and conflicting time fields", async () => {
  for (const changes of [{ "data-st": "2026-02-30 09:00:00", "data-listdatetime": "2026-02-30 09:00:00" },
    { "data-st": "2026-10-30 24:00:00" }, { "data-st": "2026-10-30T09:00:00Z" }, { "data-duration": "0" },
    { "data-duration": "721" }, { "data-duration": "120.5" }, { "data-duration": "-60" }, { "data-listdatetime": "2026-10-29 09:00:00" },
    { "data-et": "2026-10-30 12:00:00" }]) await assert.rejects(parse(page(row(changes)), { now }), /invalid-collection/u);
});

test("malformed duplicates and contradictory simultaneous programmes fail closed", async () => {
  const exactDuplicate = await parse(page(row() + row()), { now }); assert.equal(exactDuplicate.broadcasts.length, 1);
  await assert.rejects(parse(page(row() + row({ "data-description": "3rd Test, Day 3." })), { now }), /invalid-collection/u);
  await assert.rejects(parse(page(row() + row({ "data-listingid": "456", "data-episodetitle": "India vs. New Zealand" })), { now }), /invalid-collection/u);
  await assert.rejects(parse(page(row() + row({ "data-listingid": "456", "data-showname": "Cricket Review" })), { now }), /invalid-collection/u);
});

test("inert scripts cannot contribute authority, duplicate attributes and oversized HTML are bounded", async () => {
  const fake = `<script type="text/javascript">${page()}</script>`;
  await assert.rejects(parse(fake, { now }), /invalid-collection/u);
  assert.equal((await parse(fake + page(), { now })).broadcasts.length, 1);
  await assert.rejects(parse(page(row().replace('data-callsign="Willow"', 'data-callsign="Willow" data-callsign="Willow2"')), { now }), /invalid-collection/u);
  await assert.rejects(parse(" ".repeat(REVIEWED_TV_PROGRAMME_SOURCE.maxBytes + 1), { now }), /invalid-collection/u);
  await assert.rejects(parse(page(), { now: new Date("invalid") }), /invalid-collection/u);
});

test("inactive template and noscript ancestors cannot lend programme or station authority", async () => {
  for (const tag of ["template", "noscript"]) {
    assert.equal((await parse(page(`<${tag}>${row()}</${tag}>`), { now })).broadcasts.length, 0);
    await assert.rejects(parse(`<${tag}>${page()}</${tag}>${row()}`, { now }), /invalid-collection/u);
    assert.equal((await parse(`<${tag}>${page(row({ "data-callsign": "Willow2" }))}</${tag}>${page()}`, { now })).broadcasts.length, 1);
  }
});

test("hidden inert and aria-hidden ancestors suppress their rows until their actual closing range", async () => {
  for (const attribute of ["hidden", 'hidden="false"', "inert", 'aria-hidden="true"']) {
    const inactive = `<div ${attribute}><section>${row({ "data-description": "3rd Test, Day 3." })}</section></div>`;
    assert.equal((await parse(page(inactive), { now })).broadcasts.length, 0);
    const visible = await parse(page(inactive + row()), { now });
    assert.equal(visible.broadcasts.length, 1); assert.equal(visible.broadcasts[0].day, 4);
    await assert.rejects(parse(`<div ${attribute}>${page()}</div>${row()}`, { now }), /invalid-collection/u);
  }
});

test("explicit inline non-display ancestors are excluded without executing style or script", async () => {
  for (const style of ["display:none", "color:red; DISPLAY : none !important;", "visibility: hidden", "visibility:collapse", "display/**/:/**/none"])
    assert.equal((await parse(page(`<div style="${style}">${row()}</div>`), { now })).broadcasts.length, 0);
  assert.equal((await parse(page(`<div style="display:block">${row()}</div>`), { now })).broadcasts.length, 1);
});

test("hidden void elements do not suppress following visible programme or heading text", async () => {
  assert.equal((await parse(page(`<input hidden>${row()}`), { now })).broadcasts.length, 1);
  const heading = page().replace("TV Schedule for Willow Cricket", 'TV Schedule for Willow <span hidden>Extra</span>Cricket');
  assert.equal((await parse(heading, { now })).broadcasts.length, 1);
  assert.equal((await parse(page(`<div hidden/>${row()}</div>`), { now })).broadcasts.length, 0,
    "A self-closing slash cannot escape a non-void hidden HTML ancestor");
});
