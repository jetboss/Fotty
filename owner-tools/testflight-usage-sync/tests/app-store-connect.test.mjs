import assert from "node:assert/strict";
import { createVerify, generateKeyPairSync } from "node:crypto";
import test from "node:test";
import {
  buildDashboardSnapshot,
  buildTesterRows,
  classifyParticipation,
  createAppStoreConnectToken,
  fetchAllPages,
  fetchTesterUsage,
} from "../scripts/app-store-connect.mjs";

test("creates a ten-minute ES256 App Store Connect token", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const token = createAppStoreConnectToken({ issuerId: "issuer", keyId: "key", privateKey, now: 1_700_000_000 });
  const [header, payload, signature] = token.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "ES256", kid: "key", typ: "JWT" });
  assert.deepEqual(JSON.parse(Buffer.from(payload, "base64url")), {
    iss: "issuer", iat: 1_700_000_000, exp: 1_700_000_600, aud: "appstoreconnect-v1",
  });
  const verifier = createVerify("SHA256");
  verifier.update(`${header}.${payload}`);
  verifier.end();
  assert.equal(verifier.verify({ key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url")), true);
});

test("uses factual mutually exclusive participation categories", () => {
  assert.equal(classifyParticipation("INSTALLED", 3, 8), "Recently active");
  assert.equal(classifyParticipation("INSTALLED", 0, 2), "Used this month");
  assert.equal(classifyParticipation("INSTALLED", 0, 0), "No recent sessions");
  assert.equal(classifyParticipation("ACCEPTED", 0, 0), "Not installed");
  assert.equal(classifyParticipation("REVOKED", 4, 10), "Revoked");
});

test("joins roster and period metrics by tester ID without inventing missing usage", () => {
  const testers = [{
    id: "tester-1",
    attributes: {
      firstName: "Test",
      lastName: "Person",
      email: "test@example.invalid",
      inviteType: "EMAIL",
      state: "INSTALLED",
      appDevices: [{ appBuildVersion: "111", model: "iPhone", osVersion: "27.0", platform: "IOS" }],
    },
  }, {
    id: "tester-2",
    attributes: { email: "quiet@example.invalid", state: "ACCEPTED", appDevices: [] },
  }];
  const metric = (id, values) => ({
    dimensions: { betaTesters: { data: { id } } },
    dataPoints: [{ values }],
  });
  const rows = buildTesterRows(testers,
    [metric("tester-1", { sessionCount: 2, crashCount: 9, feedbackCount: 9 })],
    [metric("tester-1", { sessionCount: 6, crashCount: 1, feedbackCount: 2 })]);
  assert.deepEqual(rows[0], {
    testerId: "tester-1",
    name: "Test Person",
    email: "test@example.invalid",
    inviteType: "EMAIL",
    invitationState: "INSTALLED",
    participation: "Recently active",
    sessions7d: 2,
    sessions30d: 6,
    crashes30d: 1,
    feedback30d: 2,
    appBuildVersion: "111",
    model: "iPhone",
    osVersion: "27.0",
    platform: "iOS",
  });
  assert.equal(rows[1].participation, "Not installed");
  assert.equal(rows[1].sessions30d, 0);
});

test("follows only App Store Connect pagination links", async () => {
  const responses = [
    { data: [{ id: "1" }], links: { next: "https://api.appstoreconnect.apple.com/v1/betaTesters?cursor=next" } },
    { data: [{ id: "2" }], links: {} },
  ];
  const fetched = [];
  const rows = await fetchAllPages("https://api.appstoreconnect.apple.com/v1/betaTesters", "token", async (url, options) => {
    fetched.push({ url: String(url), authorization: options.headers.Authorization });
    return { ok: true, json: async () => responses.shift() };
  });
  assert.deepEqual(rows.map(({ id }) => id), ["1", "2"]);
  assert.equal(fetched.length, 2);
  assert.equal(fetched[0].authorization, "Bearer token");
  await assert.rejects(() => fetchAllPages("https://example.com/v1/betaTesters", "token"), /unexpected pagination URL/);
});

test("requests the roster plus 7-day and 30-day grouped usage", async () => {
  const urls = [];
  const fetchImpl = async (url) => {
    urls.push(String(url));
    return { ok: true, json: async () => ({ data: [], links: {} }) };
  };
  assert.deepEqual(await fetchTesterUsage({ appId: "6805561883", token: "token", fetchImpl }), []);
  assert.equal(urls.length, 3);
  assert.ok(urls.some((url) => url.includes("filter%5Bapps%5D=6805561883")));
  assert.ok(urls.some((url) => url.includes("period=P7D") && url.includes("groupBy=betaTesters")));
  assert.ok(urls.some((url) => url.includes("period=P30D") && url.includes("groupBy=betaTesters")));
});

test("builds a live snapshot without claiming feature-level telemetry", () => {
  const snapshot = buildDashboardSnapshot({ rows: [], generatedAt: "2026-09-22T12:00:00.000Z", dashboardId: "dashboard:test" });
  assert.equal(snapshot.id, "dashboard:test");
  assert.equal(snapshot.status, "live");
  assert.equal(snapshot.buildStatus, "complete");
  assert.match(snapshot.queries.tester_usage.source.assumptions.join(" "), /do not identify a Fotty feature/);
});
