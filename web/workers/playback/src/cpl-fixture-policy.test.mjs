import assert from "node:assert/strict";
import test from "node:test";

import cplFixtureFallback from "../../../public/data/cpl-2026-fixtures.json" with { type: "json" };
import worker from "./index.js";
import { cplFixtureSources, resolveCPLManifest, validateCPLManifest } from "./cpl-fixture-policy.mjs";

const teamNames = {
  antigua: "Antigua and Barbuda Falcons",
  barbados: "Barbados Tridents",
  guyana: "Guyana Amazon Warriors",
  jamaica: "Jamaica Kingsmen",
  saintLucia: "Saint Lucia Kings",
  stKitts: "St Kitts and Nevis Patriots",
  trinbago: "Trinbago Knight Riders",
};

function ordinal(number) {
  const mod100 = number % 100;
  if (mod100 >= 11 && mod100 <= 13) return `${number}th`;
  return `${number}${number % 10 === 1 ? "st" : number % 10 === 2 ? "nd" : number % 10 === 3 ? "rd" : "th"}`;
}

function verifierHTML(manifest, changes = new Map([[28, "2026-09-06T19:00:00Z"]])) {
  return manifest.fixtures.map((fixture) => {
    const description = fixture.number <= 35 ? `${ordinal(fixture.number)} Match` : fixture.stage;
    const team1 = fixture.team1 ? teamNames[fixture.team1] : "TBC";
    const team2 = fixture.team2 ? teamNames[fixture.team2] : "TBC";
    const start = Date.parse(changes.get(fixture.number) ?? fixture.start);
    return JSON.stringify({
      matchId: Number(fixture.upstreamId), seriesId: 12123,
      seriesName: "Caribbean Premier League 2026", matchDesc: description,
      matchFormat: "T20", startDate: String(start), endDate: String(start + 12_600_000),
      state: "Upcoming", team1: { teamId: 1, teamName: team1 }, team2: { teamId: 2, teamName: team2 },
    });
  }).join("\n");
}

function publishedHTML(manifest) {
  return manifest.fixtures.map((fixture) => {
    const local = new Date(Date.parse(fixture.start) - 4 * 3600 * 1000);
    const month = local.getUTCMonth() === 7 ? "Aug" : "Sep";
    const hour24 = local.getUTCHours();
    const hour12 = hour24 % 12 || 12;
    const time = `${hour12}${hour24 >= 12 ? "pm" : "am"}`;
    const match = fixture.number <= 35
      ? `${teamNames[fixture.team1]} vs ${teamNames[fixture.team2]}`
      : `${fixture.stage} (teams to be confirmed)`;
    return `<tr class="prezly-slate-table-row"><td>Fri ${local.getUTCDate()} ${month}</td><td>${match}</td><td>${time}</td><td>Guyana</td></tr>`;
  }).join("\n");
}

const correctionJSON = {
  acf: {
    description: "Jamaica Kingsmen now playing at Queen's Park Oval on Saturday 29 August; Guyana Amazon Warriors on Monday 31 August.",
  },
};

test("reviewed CPL manifest is complete and the known verifier conflict fails closed to official time", () => {
  const verifiedAt = new Date("2026-09-06T16:30:00Z");
  validateCPLManifest(cplFixtureFallback);
  const resolved = resolveCPLManifest({
    fallback: cplFixtureFallback,
    publishedHTML: publishedHTML(cplFixtureFallback),
    correctionJSON,
    verifierHTML: verifierHTML(cplFixtureFallback),
    now: verifiedAt,
  });
  assert.equal(resolved.authoritativeChanges.length, 0);
  assert.equal(resolved.reviewedVerifierChanges.length, 1);
  assert.equal(resolved.manifest.revision, cplFixtureFallback.revision);
  assert.equal(resolved.manifest.checkedAt, "2026-09-06T16:30:00Z");
  assert.equal(resolved.manifest.fixtures[27].start, "2026-09-06T14:00:00Z");
});

test("all three exact reviewed verifier disagreements retain the official schedule", () => {
  const fallbackBefore = structuredClone(cplFixtureFallback);
  const knownChanges = new Map([
    [21, "2026-08-31T23:00:00Z"],
    [22, "2026-09-01T21:00:00Z"],
    [28, "2026-09-06T19:00:00Z"],
  ]);
  const resolved = resolveCPLManifest({
    fallback: cplFixtureFallback,
    publishedHTML: publishedHTML(cplFixtureFallback),
    correctionJSON,
    verifierHTML: verifierHTML(cplFixtureFallback, knownChanges),
    now: new Date("2026-09-30T16:00:00Z"),
  });
  assert.equal(resolved.authoritativeChanges.length, 0);
  assert.deepEqual(resolved.reviewedVerifierChanges.map((change) => change.number), [21, 22, 28]);
  assert.deepEqual(resolved.manifest.fixtures, fallbackBefore.fixtures);
  assert.equal(resolved.manifest.revision, fallbackBefore.revision);
  assert.deepEqual(cplFixtureFallback, fallbackBefore, "reviewing exceptions must not mutate the durable receipt");

  for (const number of [21, 22, 28]) {
    const changed = new Map(knownChanges);
    changed.set(number, new Date(Date.parse(changed.get(number)) + 86_400_000).toISOString().replace(".000Z", "Z"));
    assert.throws(() => resolveCPLManifest({
      fallback: cplFixtureFallback,
      publishedHTML: publishedHTML(cplFixtureFallback),
      correctionJSON,
      verifierHTML: verifierHTML(cplFixtureFallback, changed),
      now: new Date("2026-09-30T16:00:00Z"),
    }), /1 current-verifier change\(s\) need human review/, `a different date for match ${number} must not inherit an exception`);
  }
});

test("manifest validation accepts a complete future season without 2026 fixture topology", () => {
  const future = {
    schemaVersion: 1,
    competitionId: "cpl",
    season: 2027,
    revision: "2027-reviewed",
    checkedAt: "2027-07-01T00:00:00Z",
    sources: [{ kind: "published", url: "https://example.test/one" }, { kind: "verification", url: "https://example.test/two" }],
    verificationExceptions: [],
    teamNames: { tobago: "Tobago Test XI" },
    fixtures: [
      { number: 1, upstreamId: "200001", start: "2027-08-01T23:00:00Z", team1: "trinbago", team2: "tobago" },
      { number: 2, upstreamId: "200002", start: "2027-08-02T23:00:00Z", team1: "guyana", team2: "jamaica" },
      { number: 3, upstreamId: "200003", start: "2027-09-01T23:00:00Z", stage: "Final" },
    ],
  };
  assert.doesNotThrow(() => validateCPLManifest(future));
});

test("an incomplete or newly conflicting verifier cannot replace the trusted schedule", () => {
  assert.throws(() => resolveCPLManifest({
    fallback: cplFixtureFallback,
    publishedHTML: publishedHTML(cplFixtureFallback),
    correctionJSON,
    verifierHTML: verifierHTML(cplFixtureFallback).split("\n").slice(0, 38).join("\n"),
  }), /38 fixtures instead of 39/);

  assert.throws(() => resolveCPLManifest({
    fallback: cplFixtureFallback,
    publishedHTML: publishedHTML(cplFixtureFallback),
    correctionJSON,
    verifierHTML: verifierHTML(cplFixtureFallback, new Map([[25, "2026-09-04T00:00:00Z"], [28, "2026-09-06T19:00:00Z"]])),
  }), /need human review/);
});

test("an official change confirmed by the current verifier becomes a new revision", () => {
  const changed = structuredClone(cplFixtureFallback);
  changed.fixtures[24].start = "2026-09-04T00:00:00Z";
  const resolved = resolveCPLManifest({
    fallback: cplFixtureFallback,
    publishedHTML: publishedHTML(changed),
    correctionJSON,
    verifierHTML: verifierHTML(changed),
    now: new Date("2026-09-03T14:00:00Z"),
  });
  assert.equal(resolved.authoritativeChanges.length, 1);
  assert.equal(resolved.manifest.checkedAt, "2026-09-03T14:00:00Z");
  assert.equal(resolved.manifest.fixtures[24].start, "2026-09-04T00:00:00Z");
});

test("confirmed playoff participants replace a stage-only placeholder", () => {
  const stageOnly = structuredClone(cplFixtureFallback);
  delete stageOnly.fixtures[38].team1;
  delete stageOnly.fixtures[38].team2;
  const current = structuredClone(stageOnly);
  current.fixtures[38].team1 = "antigua";
  current.fixtures[38].team2 = "jamaica";
  const resolved = resolveCPLManifest({
    fallback: stageOnly,
    publishedHTML: publishedHTML(stageOnly),
    correctionJSON,
    verifierHTML: verifierHTML(current),
    now: new Date("2026-09-20T15:00:00Z"),
  });
  assert.equal(resolved.manifest.fixtures[38].stage, "Final");
  assert.equal(resolved.manifest.fixtures[38].team1, "antigua");
  assert.equal(resolved.manifest.fixtures[38].team2, "jamaica");
  assert.match(resolved.authoritativeChanges[0].message, /teams/);
});

test("Worker CPL route returns a complete official schedule without requiring app secrets", async (t) => {
  const requestedAt = Date.now();
  t.mock.method(globalThis, "fetch", async (input) => {
    const url = String(input);
    if (url === cplFixtureSources.live) return new Response(verifierHTML(cplFixtureFallback));
    if (url === cplFixtureSources.published) return new Response(publishedHTML(cplFixtureFallback));
    if (url === cplFixtureSources.correction) return Response.json(correctionJSON);
    throw new Error(`Unexpected URL ${url}`);
  });
  const response = await worker.fetch(new Request("https://test.invalid/api/cricket/cpl-fixtures"), {});
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.sourceStatus, "verified");
  assert.ok(Date.parse(body.checkedAt) >= requestedAt - 1_000, "successful verification must report a current receipt time");
  assert.equal(body.fixtures.length, 39);
  assert.equal(body.fixtures[27].start, "2026-09-06T14:00:00Z");
});

test("Worker preserves the last-known-good verification time when live sources are unavailable", async (t) => {
  t.mock.method(globalThis, "fetch", async () => {
    throw new Error("offline");
  });
  const response = await worker.fetch(new Request("https://test.invalid/api/cricket/cpl-fixtures"), {});
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.sourceStatus, "last-known-good");
  assert.equal(body.checkedAt, cplFixtureFallback.checkedAt);
  assert.equal(body.fixtures.length, 39);
  assert.match(body.warnings[0], /last reviewed CPL schedule/);
});

test("Worker labels a two-source runtime change separately from the durable fallback", async (t) => {
  const changed = structuredClone(cplFixtureFallback);
  changed.fixtures[24].start = "2026-09-04T00:00:00Z";
  t.mock.method(globalThis, "fetch", async (input) => {
    const url = String(input);
    if (url === cplFixtureSources.live) return new Response(verifierHTML(changed));
    if (url === cplFixtureSources.published) return new Response(publishedHTML(changed));
    if (url === cplFixtureSources.correction) return Response.json(correctionJSON);
    throw new Error(`Unexpected URL ${url}`);
  });
  const response = await worker.fetch(new Request("https://test.invalid/api/cricket/cpl-fixtures"), {});
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.sourceStatus, "live-verified");
  assert.equal(body.fixtures[24].start, "2026-09-04T00:00:00Z");
  assert.match(body.warnings.at(-1), /Durable fallback review is pending/);
});
