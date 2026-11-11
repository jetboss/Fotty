import assert from "node:assert/strict";
import test from "node:test";
import { FOX_CRICKET_GUIDE, foxCricketGuideURL, parseFoxCricketProgrammes as parse,
  reviewFoxCricketCoverage as review } from "./fox-cricket-programmes.mjs";

const now = new Date("2026-11-04T15:15:00Z");
const event = (title = "Live: WBBL: Strikers v Heat", start = "2026-11-05T04:40:00Z", id = "183882957", subtitle = "Strikers v Heat") =>
  `<a href="Programme/${id}" data-scheduled-date="${Date.parse(start)}" class="row epg-channel-event-row"><div><div class="epg-event-description">${title}<div>${subtitle}</div></div></div></a>`;
const logo = '<div class="epg-channel-logo"><img alt="501 FOX CRICKET HD" src="https://www.foxtel.com.au/content/dam/foxtel/shared/channel/FS1/FS1_290x170.png"></div>';
const page = (rows = event() + event("Live: WBBL: Thunder v Scorchers", "2026-11-05T08:00:00Z", "183882958", "Thunder v Scorchers")) =>
  `<html><body>${logo}<div id="epg-channel-events">${rows}</div></body></html>`;
const fixture = (changes = {}) => ({ fixtureID: "cricket-fixture:ca:1", verified: true, sport: "cricket", competitionID: "wbbl",
  participants: ["Adelaide Strikers Women", "Brisbane Heat Women"], format: "T20", matchOrdinal: 10,
  squad: { gender: "women", ageGroup: "senior" }, status: "scheduled", start: "2026-11-05T04:40:00Z", observedAt: now.toISOString(), ...changes });

test("fixed Fox URL uses Sydney date, including DST, without supplying event time authority", () => {
  assert.equal(foxCricketGuideURL(now), "https://www.foxtel.com.au/tv-guide.html/channel/FOX-CRICKET-HD/FS1/2026/11/05");
  assert.ok(foxCricketGuideURL(new Date("2026-07-04T13:30:00Z")).endsWith("2026/07/04"));
  assert.ok(foxCricketGuideURL(new Date("2026-07-04T14:30:00Z")).endsWith("2026/07/05"));
  for (const date of ["2026-11-04", new Date("invalid"), new Date("1999-01-01")]) assert.throws(() => foxCricketGuideURL(date));
});

test("observed original Fox structure preserves epoch, exact women's identity and a bounded next-programme end", () => {
  const g = parse(page(), { now }), p = g.programmes[0];
  assert.equal(g.channelID, "cricket-channel:fox-cricket"); assert.equal(g.market, "AU");
  assert.equal(p.start, "2026-11-05T04:40:00.000Z"); assert.equal(p.end, "2026-11-05T08:00:00.000Z");
  assert.equal(p.endBasis, "next-published-programme"); assert.equal(g.programmes[1].end, undefined);
  assert.deepEqual(p.match.participants, fixture().participants); assert.equal(p.match.matchOrdinal, undefined);
  assert.equal(p.classification, "live-match-listing"); assert.equal(p.match.squad.gender, "women");
  assert.ok(!JSON.stringify(g).includes("https:")); assert.equal(g.status, undefined);
});

test("replays, mini matches, pregame, unsupported tournaments and ambiguous descriptions cannot become match authority", () => {
  for (const title of ["WBBL: Strikers v Heat", "WBBL Mini: Strikers v Heat", "Live: WBBL: Pre Game", "Live: Test Cricket",
    "Live: WBBL: Strikers U19 v Heat", "Live: BBL: Strikers v Heat", "Live: WBBL: Strikers v Strikers", "Live: WBBL: Unknown v Heat"]) {
    assert.equal(parse(page(event(title)), { now }).programmes[0].match, undefined);
  }
  for (const subtitle of ["Replay", "Highlights", "Strikers v Sixers", "Strikers v Heat Replay", "Strikers <span>v Sixers</span>"]) {
    const p = parse(page(event(undefined, undefined, undefined, subtitle)), { now }).programmes[0];
    assert.equal(p.match, undefined);
  }
  assert.equal(parse(page(event().replace("Heat<div>", "Heat<span> Replay</span><div>")), { now }).programmes[0].match, undefined);
});

test("hidden, template, comment and script programmes cannot lend visible schedule authority", () => {
  for (const wrapper of [(s) => `<div hidden>${s}</div>`, (s) => `<div style="display:none">${s}</div>`,
    (s) => `<template>${s}</template>`, (s) => `<noscript>${s}</noscript>`, (s) => `<!--${s}-->`, (s) => `<script>${s}</script>`]) {
    assert.equal(parse(page(wrapper(event())), { now }).programmes.length, 0);
  }
  assert.equal(parse(page(`<div hidden/>${event()}</div>`), { now }).programmes.length, 0);
});

test("channel and row ancestry, duplicate attributes, bound sizes and actual closing tags are required", () => {
  for (const html of [page().replace("501 FOX CRICKET HD", "502 FOX LEAGUE"), page().replace("FS1_290", "OTHER_290"),
    page().replace(logo, ""), page().replace(logo, logo + logo), page().replace('id="epg-channel-events"', 'id="other"'),
    page().replace('id="epg-channel-events"', 'id="epg-channel-events" id="other"'),
    page().replace("</a>", "</div>"), page().replace("</div></body>", "</body>"),
    page().replace('href="Programme/', 'href="https://other.example/'), page().replace('data-scheduled-date="1', 'data-scheduled-date="0'),
    page().replace('<div id="epg-channel-events">', '<div id="epg-channel-events"><div id="epg-channel-events"></div>'),
    "x".repeat(FOX_CRICKET_GUIDE.maxBytes + 1)]) assert.throws(() => parse(html, { now }), /invalid-fox-guide/u);
});

test("same-ID conflicts and overlapping station slots reject the collection; exact duplicates are harmless", () => {
  assert.equal(parse(page(event() + event()), { now }).programmes.length, 1);
  for (const rows of [event() + event("Live: WBBL: Thunder v Scorchers"),
    event() + event(undefined, "2026-11-05T08:00:00Z"), event() + event(undefined, undefined, "183882999")]) {
    assert.throws(() => parse(page(rows), { now }), /invalid-fox-guide/u);
  }
  assert.throws(() => parse(page(event(undefined, "2026-10-01T04:40:00Z")), { now }));
});

test("official coverage review corroborates one current exact CA occurrence, without granting Watch or inferring live", () => {
  const g = parse(page(), { now }), rows = review(g, [fixture()], now);
  assert.equal(rows[0].result, "corroborated"); assert.equal(rows[0].officialStatus, "scheduled");
  assert.equal(rows[0].coverageLeadMinutes, 0); assert.equal(rows[0].watch, undefined);
  assert.equal(rows[1].result, "missing-official-fixture");
  const thunder = fixture({ fixtureID: "cricket-fixture:ca:2", participants: ["Sydney Thunder Women", "Perth Scorchers Women"], start: "2026-11-05T08:10:00Z" });
  assert.equal(review(g, [thunder], now)[1].coverageLeadMinutes, 10);
  assert.equal(review(g, [fixture(), fixture({ fixtureID: "cricket-fixture:ca:2" })], now)[0].result, "ambiguous-fixture");
});

test("coverage review preserves stale, terminal, squad, format and coverage-time conflicts", () => {
  const g = parse(page(), { now });
  for (const change of [{ verified: false }, { status: "finished" }, { format: "ODI" }, { squad: { gender: "men", ageGroup: "senior" } },
    { squad: { gender: "women", ageGroup: "u19" } }, { fixtureID: "made-up:1" }, { observedAt: "2026-11-03T00:00:00Z" },
    { observedAt: "invalid" }, { start: "2026-11-05T05:41:00Z" }, { start: "2026-11-05T04:39:00Z" }]) {
    assert.equal(review(g, [fixture(change)], now)[0].result, "fixture-conflict-or-stale");
  }
  for (const changes of [{ observedAt: "invalid" }, { expiresAt: "invalid" }, { expiresAt: "2026-11-06T00:00:00Z" }, { channelID: "other" }]) {
    assert.throws(() => review({ ...g, ...changes }, [fixture()], now));
  }
  assert.throws(() => review(g, [fixture()], new Date(+now + 600_001)));
});

test("coverage review validates structured input without depending on property insertion order", () => {
  const g = parse(page(), { now });
  const match = g.programmes[0].match;
  g.programmes[0].match = { participants: match.participants, squad: match.squad, format: match.format, competitionID: match.competitionID };
  assert.equal(review(g, [fixture()], now)[0].result, "corroborated");
  for (const programmes of [[null], [{ ...g.programmes[0], match: { ...match, participants: ["Sydney Sixers Women", "Brisbane Heat Women"] } }],
    [{ ...g.programmes[0], title: null }], [{ ...g.programmes[0], start: 123 }]]) {
    assert.throws(() => review({ ...g, programmes }, [fixture()], now), /invalid-fox-guide/u);
  }
  assert.throws(() => review(g, [null], now), /invalid-fox-guide/u);
  assert.throws(() => review(g, [fixture()], +now), /invalid-fox-guide/u);
});

test("Fox's season/episode prefix and the Abu Dhabi T10 listing resolve; shortened titles need the full episode pair", () => {
  const wbbl = parse(page(event("Live: WBBL: Strikers v Heat", undefined, undefined, "S2024 , Ep14 , Strikers v Heat")), { now }).programmes[0];
  assert.equal(wbbl.classification, "live-match-listing");
  assert.deepEqual(wbbl.match.participants, ["Adelaide Strikers Women", "Brisbane Heat Women"]);
  const t10 = parse(page(event("Live: Abu Dhabi T10 League: Champions v", undefined, undefined, "Champions v Bulls")), { now }).programmes[0];
  assert.equal(t10.classification, "live-match-listing");
  assert.equal(t10.match.competitionID, "abu-dhabi-t10"); assert.equal(t10.match.format, "T10");
  assert.deepEqual(t10.match.squad, { gender: "men", ageGroup: "senior" });
  assert.deepEqual(t10.match.participants, ["Royal Desert Champions", "UAE Bulls"]);
  for (const [title, subtitle] of [
    ["Live: Abu Dhabi T10 League: Champions v", "Aces v Bulls"],        // episode disagrees with the title
    ["Live: Abu Dhabi T10 League: Champ", "Champions v Bulls"],         // title cut inside the first team
    ["Live: Abu Dhabi T10 League: Champions v", "Champions v Strikers"], // other competition's club
    ["Live: Abu Dhabi T10 League: Champions v", "S2024 , Ep3 , Champions v Bulls Replay"],
    ["Abu Dhabi T10 League: Champions v Bulls", "Champions v Bulls"],   // not live
  ]) assert.equal(parse(page(event(title, undefined, undefined, subtitle)), { now }).programmes[0].match, undefined, title + " / " + subtitle);
});
