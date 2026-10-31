import test from "node:test";
import assert from "node:assert/strict";
import { parseReviewedTVESPNFeed as parse, REVIEWED_TV_ESPN_SOURCE as source } from "./reviewed-tv-espn.mjs";
import { normalizeBroadcastCollection, associateBroadcasts } from "./broadcast-registry-policy.mjs";

const now = new Date("2026-10-31T22:00:00Z");
const title = "PROGRAMACIÓN DESTACADA DEL 30 DE OCTUBRE AL 6 DE NOVIEMBRE";
const article = (section = `<p><u><strong>Domingo 1</strong></u><br />13:30 ESPN y Disney+ Plan Premium / Premier League #9 &#8211; Liverpool vs. Arsenal</p>`, changes = {}) =>
  `<h2 id="ARGENTINA">ARGENTINA</h2><p>Domingo 1<br />13:30 ESPN2 y Disney+ Plan Premium / Premier League #9 – Liverpool vs. Arsenal</p>`
  + `<h2 id="${changes.country ?? "URUGUAY"}">${changes.country ?? "URUGUAY"}</h2><p><strong>${changes.title ?? title}</strong></p>${section}<h2 id="PARAGUAY">PARAGUAY</h2>`
  + `<p>Domingo 1<br />13:30 ESPN7 y Disney+ Plan Premium / Premier League #9 – Liverpool vs. Arsenal</p>`;
const item = (body = article(), changes = {}) => `<item><title>${changes.title ?? title}</title><link>${source.origin}${changes.path ?? "/press-releases/2026/10/programacion-destacada-del-30-de-octubre-al-6-de-noviembre/"}</link>`
  + `<pubDate>${changes.published ?? "Thu, 29 Oct 2026 19:23:00 +0000"}</pubDate><content:encoded><![CDATA[${body}]]></content:encoded></item>`;
const feed = (items = item(), origin = source.origin + "/") => `<?xml version="1.0"?><rss xmlns:content="urn:content"><channel><link>${origin}</link>${items}</channel></rss>`;
const dayRows = (rows, dayName = "Martes 3") => `<p><u><strong>${dayName}</strong></u><br />${rows.join("<br />")}</p>`;
const programme = (n, teams = "Barcelona vs. Aston Villa", competition = "UEFA Champions League") =>
  `16:30 ESPN${n === 1 ? "" : n} y Disney+ Plan Premium / ${competition} #4 – ${teams}`;

test("current official RSS supplies only Uruguay's linear assignment, original coverage UTC and bounded event identity", async () => {
  const result = await parse(feed(), { now }), row = result.broadcasts[0];
  assert.equal(result.broadcasts.length, 1); assert.deepEqual(result.scopes, [{ scope: "football", status: "partial", complete: false }]);
  assert.equal(row.channelID, "sports-channel:espn-latinamerica-south"); assert.equal(row.streamID, "reviewed-tv:espn-latinamerica-south");
  assert.equal(row.start, "2026-11-01T16:30:00.000Z"); assert.equal(row.stationMarket, "UY"); assert.equal(row.end, undefined);
  assert.equal(row.kind, "event"); assert.equal(row.competitionID, "premier-league"); assert.deepEqual(row.squad, { gender: "men", ageGroup: "senior" });
  assert.deepEqual(row.participants, ["Liverpool", "Arsenal"]); assert.match(row.providerEventID, /^reviewed-tv:assignment:[a-f0-9]{64}$/u);
  assert.equal(Date.parse(row.expiresAt) - Date.parse(row.observedAt), 600_000); assert.ok(!JSON.stringify(result).includes("://"));
});

test("all seven exact linear channel numbers and reviewed football competitions stay distinct from Disney-only and replay text", async () => {
  const rows = Array.from({ length: 7 }, (_, i) => programme(i + 1, `Home ${i} vs. Away ${i}`));
  rows.push("17:00 ESPN en Disney+ Plan Premium / Premier League #9 – Aston Villa vs. Fulham",
    "17:00 ESPN8 y Disney+ Plan Premium / Premier League #9 – Home vs. Away",
    "17:00 ESPN1 y Disney+ Plan Premium / Premier League #9 – Home vs. Away",
    programme(1, "Home vs. Away", "UEFA Youth League"), "17:00 ESPN y Disney+ Plan Premium / Repetición Premier League #9 – Home vs. Away");
  const result = await parse(feed(item(article(dayRows(rows)))), { now });
  assert.equal(result.broadcasts.length, 7);
  assert.deepEqual(result.broadcasts.map((r) => r.channelID), Array.from({ length: 7 }, (_, i) => `sports-channel:espn${i ? i + 1 : ""}-latinamerica-south`));
  for (const comp of ["LaLiga", "Serie A", "Bundesliga", "Ligue 1"]) {
    const parsed = await parse(feed(item(article(dayRows([programme(1, "Home vs. Away", comp)])))), { now });
    assert.equal(parsed.broadcasts.length, 1);
  }
});

test("date and weekday belong to the selected article range; a missing day or another territory never lends authority", async () => {
  for (const body of [article(dayRows([programme(1)], "Lunes 3")), article(dayRows([programme(1)], "Martes 10")),
    article(`<p>${programme(1)}</p>`), article(undefined, { country: "ARGENTINA" }),
    article() + `<h2 id="URUGUAY">URUGUAY</h2>`, article(undefined, { title: "A different week" })]) {
    await assert.rejects(parse(feed(item(body)), { now }), /invalid-collection/u);
  }
});

test("a later undated or unknown-language paragraph never borrows a previous day's date", async () => {
  for (const block of [`<p>Wednesday 4<br />${programme(2)}</p>`, `<p>${programme(2)}</p>`,
    dayRows([programme(2)], "Martes 3")]) {
    await assert.rejects(parse(feed(item(article(dayRows([programme(1)]) + block))), { now }), /invalid-collection/u);
  }
  const late = await parse(feed(item(article(dayRows(["23:30 ESPN y Disney+ Plan Premium / Premier League #9 – Liverpool vs. Arsenal"], "Domingo 1")))), { now });
  assert.equal(late.broadcasts[0].start, "2026-11-02T02:30:00.000Z", "Country-local dates convert to their actual UTC date rather than preserving the wall date");
});

test("month and year rollover is resolved from original publication and explicit weekly range, without a fixed offset", async () => {
  const t = "PROGRAMACIÓN DESTACADA DEL 30 DE DICIEMBRE AL 6 DE ENERO";
  const body = article(dayRows([programme(1)], "Viernes 1"), { title: t });
  const parsed = await parse(feed(item(body, { title: t, path: "/press-releases/2026/12/programacion-destacada-del-30-de-diciembre-al-6-de-enero/",
    published: "Tue, 29 Dec 2026 19:23:00 +0000" })), { now: new Date("2026-12-31T22:00:00Z") });
  assert.equal(parsed.broadcasts[0].start, "2027-01-01T19:30:00.000Z");
  await assert.rejects(parse(feed(item(body, { title: t, published: "Tue, 29 Dec 2026 19:23:00 +0000" })), { now: new Date("2026-12-31T22:00:00Z") }), /invalid-collection/u);
});

test("latest maintained current article wins overlapping end days; ambiguous same-receipt revisions fail closed", async () => {
  const oldTitle = "PROGRAMACIÓN DESTACADA DEL 23 AL 30 DE OCTUBRE", old = item(article(dayRows([programme(2)], "Viernes 30"), { title: oldTitle }),
    { title: oldTitle, path: "/press-releases/2026/10/programacion-destacada-del-23-al-30-de-octubre/", published: "Thu, 22 Oct 2026 19:23:00 +0000" });
  const parsed = await parse(feed(old + item()), { now: new Date("2026-10-30T22:00:00Z") });
  assert.equal(parsed.broadcasts[0].channelID, "sports-channel:espn-latinamerica-south");
  await assert.rejects(parse(feed(item() + item(article(dayRows([programme(2)])))), { now }), /catalog-conflict/u);
});

test("same-channel simultaneous assignments remain conflicts while unrelated siblings survive", async () => {
  const result = await parse(feed(item(article(dayRows([programme(1), programme(1, "Liverpool vs. Arsenal"), programme(2, "Home vs. Away")])))), { now });
  assert.equal(result.broadcasts.length, 3); assert.equal(result.broadcasts.filter((r) => r.verification === "conflicting").length, 2);
  assert.equal(result.broadcasts.find((r) => r.channelID.includes("espn2-")).verification, "dated");
});

test("verified literal ESPN AEK Athenas alias joins official PAE AEK without altering raw title or weakening UCL/date/squad/time identity", async () => {
  const original = "14:30 ESPN y Disney+ Plan Premium / UEFA Champions League #4 – AEK Athenas vs. Real Madrid";
  const fixture = { fixtureID: "sports-fixture:champions-league:575386", sport: "football", competitionID: "champions-league",
    participants: ["PAE AEK", "Real Madrid CF"], squad: { gender: "men", ageGroup: "senior" }, start: "2026-11-04T17:45:00.000Z",
    status: "scheduled", observedAt: now.toISOString(), verified: true };
  const join = async (line = original, changes = {}) => {
    const parsed = await parse(feed(item(article(dayRows([line], "Miércoles 4")))), { now });
    const collection = await normalizeBroadcastCollection("reviewedtv", { ...parsed, providerCode: "reviewedtv", observedAt: now.toISOString() }, now);
    return { row: collection.broadcasts[0], links: associateBroadcasts({ fixtures: [{ ...fixture, ...changes }], broadcasts: collection.broadcasts, providers: collection.scopes, now }) };
  };
  const good = await join(); assert.deepEqual(good.row.participants, ["AEK Athens", "Real Madrid"]);
  assert.equal(good.row.title, "AEK Athenas vs Real Madrid"); assert.equal(good.row.start, "2026-11-04T17:30:00.000Z");
  assert.equal(good.links[0].state, "listed"); assert.equal(good.links[0].matchMethod, "channel-assignment");
  assert.equal(good.links[0].fixtureFingerprint.start, fixture.start); assert.equal(good.links[0].startRelation, "channel-coverage");
  for (const spelling of ["AEK Athena", "AEK Athenas B", "AEK Athenas U19", "AEK Athenas Women", "AEK Athenas."]) {
    const checked = await join(original.replace("AEK Athenas", spelling));
    assert.equal(checked.row.participants[0], spelling); assert.equal(checked.links.some((l) => l.state === "listed"), false);
  }
  for (const changes of [{ competitionID: "premier-league" }, { squad: { gender: "men", ageGroup: "u19" } },
    { participants: ["PAE AEK U19", "Real Madrid CF U19"] }, { start: "2026-11-05T17:45:00.000Z" },
    { start: "2026-11-04T18:30:00.001Z" }, { start: "2026-11-04T17:29:59.999Z" }]) {
    assert.equal((await join(original, changes)).links.some((l) => l.state === "listed"), false, JSON.stringify(changes));
  }
  const differentCompetition = await join(original.replace("UEFA Champions League", "Premier League"));
  assert.equal(differentCompetition.row.participants[0], "AEK Athenas", "The source-local spelling exception belongs only to the reviewed UCL assignment");
});

test("inert/script/hidden programme text cannot add assignments or replace the country authority", async () => {
  const bad = dayRows([programme(2, "Wrong vs. Teams")]);
  const body = article(`<script>${bad}</script><template>${bad}</template><div hidden>${bad}</div>`
    + `<div style="display:none">${bad}</div>` + dayRows([programme(1)]));
  const result = await parse(feed(item(body)), { now }); assert.equal(result.broadcasts.length, 1); assert.equal(result.broadcasts[0].title, "Barcelona vs Aston Villa");
  await assert.rejects(parse(feed(item(`<template>${article()}</template>`)), { now }), /invalid-collection/u);
  for (const attr of ["hidden", "inert", 'aria-hidden="true"', 'style="display:none"']) {
    await assert.rejects(parse(feed(item(`<div ${attr}>${article()}</div>`)), { now }), /invalid-collection/u);
  }
  await assert.rejects(parse(feed(item(article().replace('id="URUGUAY"', 'id="URUGUAY" id="ARGENTINA"'))), { now }), /invalid-collection/u);
});

test("unbounded, stale, future, malformed, nonofficial and impossible weekly authority is rejected", async () => {
  for (const xml of ["x".repeat(source.maxBytes + 1), feed().replace("<rss", "<!DOCTYPE rss><rss"), feed().replace("</item>", ""), feed().replace("]]>", "]>"),
    feed(item(), "https://not-espn.example/"), feed(item(article(), { path: "/press-releases/2026/10/not-a-reviewed-week/" })),
    feed(item(article(), { published: "Tue, 29 Sep 2026 19:23:00 +0000" })),
    feed(item(article(), { published: "Thu, 05 Nov 2026 19:23:00 +0000" })), feed(item(article(), { published: "Wed, 29 Oct 2026 19:23:00 +0000" })),
    feed(item(article(), { published: "Thu, 29 Oct 2026 24:23:00 +0000" })),
    feed(item(article(), { title: "PROGRAMACIÓN DESTACADA DEL 31 DE FEBRERO AL 6 DE MARZO" }))]) {
    await assert.rejects(parse(xml, { now }));
  }
});
