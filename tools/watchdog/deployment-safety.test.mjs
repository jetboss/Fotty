import test from "node:test";
import assert from "node:assert/strict";
import { configurationFingerprint, captureSafetySnapshot, evaluateDeploymentPreflight, evaluateDeploymentAfter } from "./deployment-safety.mjs";
const NOW = Date.parse("2026-10-29T23:30:00Z"), at = (delta = 0) => new Date(NOW + delta).toISOString();
const health = () => ({ service: "fotty-playback", sourceVersion: "reviewed-release", sportsFixtureServiceEnabled: true, cricketFixtureRegistryConfigured: true, sportsFixtureRegistryConfigured: true, sportsEFLEnabled: true, sportsPublicWebFeedsEnabled: false, sportsWNBAEnabled: false });
const state = () => ({ schema: 1, activation: "active", activatedAt: "2026-10-11T12:00:00.000Z", configurationRevision: "reviewed-config", observerRevision: "observer-v1",
  expectedDeploymentRevision: "reviewed-release", notifications: Array.from({ length: 121 }, (_, i) => ({ id: `production:notice:${i + 1}` })),
  lastCompletedAt: NOW - 1000, overflow: false, ownerEmail: { enabled: false } });
const config = () => ({ name: "fotty-watchdog", account_id: "reviewed-account", vars: { FOTTY_WATCHDOG_ENABLED: "1", FOTTY_WATCHDOG_ACTIVATED_AT: state().activatedAt,
  FOTTY_OWNER_EMAIL_ENABLED: "0", FOTTY_SPORTS_FIXTURES_ENABLED: "1" }, durable_objects: { bindings: [{ name: "WATCHDOG_STATE", class_name: "WatchdogState" }] },
  migrations: [{ tag: "watchdog-observation-v1", new_sqlite_classes: ["WatchdogState"] }] });
const playbackConfig = () => ({ ...config(), name: "fotty-playback-v3", vars: { FOTTY_PLAYBACK_OPEN: "1", FOTTY_SPORTS_FIXTURES_ENABLED: "1", FOTTY_SPORTS_EFL_ENABLED: "1", FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED: "0", FOTTY_SPORTS_WNBA_ENABLED: "0" } });
const pairConfig = (watchdog = config(), playback = playbackConfig()) => ({ watchdog: configurationFingerprint(watchdog), playback: configurationFingerprint(playback) });
const before = () => captureSafetySnapshot(health(), state(), { now: NOW });

test("preflight rejects source-default disable before any deploy, despite intended keep-vars", () => {
  const baseline = pairConfig();
  for (const value of ["0", undefined, "true"]) {
    const candidate = config(); candidate.vars.FOTTY_WATCHDOG_ENABLED = value;
    const result = evaluateDeploymentPreflight(before(), baseline, pairConfig(candidate), { now: NOW });
    assert.equal(result.ok, false); assert.ok(result.problems.includes("collector-would-be-disabled"));
  }
  assert.equal(evaluateDeploymentPreflight(before(), baseline, baseline, { now: NOW }).ok, true);
});
test("preflight preserves activation and durable identity, flags and migrations", () => {
  const baseline = pairConfig();
  for (const mutate of [c => c.vars.FOTTY_WATCHDOG_ACTIVATED_AT = at(), c => c.name = "different-worker",
    c => c.durable_objects.bindings[0].class_name = "DifferentState", c => c.migrations.push({ tag: "reset" })]) {
    const changed = config(); mutate(changed);
    assert.equal(evaluateDeploymentPreflight(before(), baseline, pairConfig(changed), { now: NOW }).ok, false);
  }
  assert.equal(evaluateDeploymentPreflight(before(), baseline, baseline, { now: NOW + 11 * 60_000 }).ok, false);
});
test("active email cannot silently lose its private target, cutover or restricted binding", () => {
  const c = config(); c.vars.FOTTY_OWNER_EMAIL_ENABLED = "1"; c.vars.FOTTY_OWNER_EMAIL_RECIPIENT = "owner@example.com";
  c.vars.FOTTY_OWNER_EMAIL_SENDER = "watchdog@example.com"; c.vars.FOTTY_OWNER_EMAIL_ACTIVATED_AT = at(-1000);
  c.send_email = [{ name: "FOTTY_OWNER_EMAIL", destination_address: "owner@example.com" }];
  const b = before(); b.emailEnabled = true; const baseline = pairConfig(c);
  assert.equal(JSON.stringify(baseline).includes("owner@example.com"), false);
  for (const mutate of [x => x.vars.FOTTY_OWNER_EMAIL_ENABLED = "0", x => delete x.send_email,
    x => x.vars.FOTTY_OWNER_EMAIL_RECIPIENT = "other@example.com", x => x.vars.FOTTY_OWNER_EMAIL_ACTIVATED_AT = at()]) {
    const changed = structuredClone(c); mutate(changed);
    assert.ok(evaluateDeploymentPreflight(b, baseline, pairConfig(changed), { now: NOW }).problems.includes("active-email-configuration-would-change"));
  }
});
test("post-deploy requires preserved121 notices, active original collector and a later real cron", () => {
  const b = before(), h = health(), s = state(); s.lastCompletedAt = NOW + 1000;
  const expected = { sourceVersion: h.sourceVersion, configurationRevision: s.configurationRevision, observerRevision: s.observerRevision };
  assert.equal(evaluateDeploymentAfter(b, h, s, expected, { now: NOW + 2000, deployedAt: at(500) }).ok, true);
  const missing = structuredClone(s); missing.notifications.shift();
  assert.ok(evaluateDeploymentAfter(b, h, missing, expected, { now: NOW + 2000, deployedAt: at(500) }).problems.includes("retained-notices-lost"));
  assert.ok(evaluateDeploymentAfter(b, h, state(), expected, { now: NOW + 2000, deployedAt: at(500) }).problems.includes("post-deployment-real-collector-completion-missing"));
  for (const mutate of [x => x.activation = "pending", x => x.overflow = true, x => x.expectedDeploymentRevision = "wrong", x => x.lastCompletedAt = NOW - 36 * 60_000]) {
    const changed = structuredClone(s); mutate(changed); assert.equal(evaluateDeploymentAfter(b, h, changed, expected, { now: NOW + 2000, deployedAt: at(500) }).ok, false);
  }
});
test("post-deploy rejects incompatible rollback identity and changed fixture or email activation", () => {
  const b = before(), h = health(), s = state(); s.lastCompletedAt = NOW + 1000;
  const expected = { sourceVersion: h.sourceVersion, configurationRevision: s.configurationRevision, observerRevision: s.observerRevision };
  assert.ok(evaluateDeploymentAfter(b, h, s, { ...expected, configurationRevision: "old-config" }, { now: NOW + 2000, deployedAt: at(500) }).problems.includes("deployed-release-identity-mismatch"));
  assert.ok(evaluateDeploymentAfter(b, { ...h, sportsFixtureServiceEnabled: false }, s, expected, { now: NOW + 2000, deployedAt: at(500) }).problems.includes("fixture-activation-changed"));
  b.emailEnabled = true; assert.ok(evaluateDeploymentAfter(b, h, s, expected, { now: NOW + 2000, deployedAt: at(500) }).problems.includes("active-email-disabled"));
});

test("paired preflight reads real playback flags even when watchdog has no playback variables", () => {
  const w = config(); delete w.vars.FOTTY_SPORTS_FIXTURES_ENABLED;
  const base = pairConfig(w), changed = playbackConfig(); changed.vars.FOTTY_SPORTS_EFL_ENABLED = "0";
  assert.equal(evaluateDeploymentPreflight(before(), base, pairConfig(w, changed), { now: NOW }).ok, false);
  const s = state(); s.lastCompletedAt = NOW + 1000;
  const expected = { sourceVersion: health().sourceVersion, configurationRevision: s.configurationRevision, observerRevision: s.observerRevision };
  assert.ok(evaluateDeploymentAfter(before(), { ...health(), sportsEFLEnabled: false }, s, expected,
    { now: NOW + 2000, deployedAt: at(500) }).problems.includes("fixture-activation-changed"));
});
test("a cron between capture and deploy cannot qualify code deployed later", () => {
  const s = state(); s.lastCompletedAt = NOW + 1000;
  const expected = { sourceVersion: health().sourceVersion, configurationRevision: s.configurationRevision, observerRevision: s.observerRevision };
  assert.ok(evaluateDeploymentAfter(before(), health(), s, expected,
    { now: NOW + 3000, deployedAt: at(2000) }).problems.includes("post-deployment-real-collector-completion-missing"));
  assert.equal(evaluateDeploymentAfter(before(), health(), s, expected, { now: NOW + 3000 }).ok, false);
});
test("missing health flags and a missing baseline timestamp cannot qualify a pair", () => {
  for (const flag of ["sportsEFLEnabled", "sportsFixtureRegistryConfigured", "sportsWNBAEnabled"]) {
    const h = health(); delete h[flag];
    assert.throws(() => captureSafetySnapshot(h, state(), { now: NOW }));
  }
  const b = before(); delete b.capturedAt;
  const s = state(); s.lastCompletedAt = NOW + 1000;
  const expected = { sourceVersion: health().sourceVersion, configurationRevision: s.configurationRevision, observerRevision: s.observerRevision };
  assert.equal(evaluateDeploymentAfter(b, health(), s, expected, { now: NOW + 2000, deployedAt: at(500) }).ok, false);
});
