// Read-only paired-deployment gate. Never deploys, rolls back or changes state.
// A source-default disabled flag is not safe merely because --keep-vars is used.
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import { readFile, writeFile } from "node:fs/promises";

const digest = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const object = (value) => value && typeof value === "object" && !Array.isArray(value);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const iso = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T.*Z$/.test(value) && Number.isFinite(Date.parse(value));
const healthFlags = ["sportsFixtureServiceEnabled", "sportsFixtureRegistryConfigured", "cricketFixtureRegistryConfigured",
  "sportsEFLEnabled", "sportsPublicWebFeedsEnabled", "sportsWNBAEnabled"];
const flags = ["FOTTY_PLAYBACK_OPEN", "FOTTY_SPORTS_FIXTURES_ENABLED", "FOTTY_SPORTS_EFL_ENABLED",
  "FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED", "FOTTY_SPORTS_WNBA_ENABLED"];
const baselineValid = (value) => object(value) && value.schema === 1 && iso(value.capturedAt)
  && iso(value.activatedAt) && typeof value.sourceVersion === "string" && typeof value.configurationRevision === "string"
  && typeof value.observerRevision === "string" && typeof value.emailEnabled === "boolean"
  && object(value.sourceFlags) && healthFlags.every((key) => typeof value.sourceFlags[key] === "boolean")
  && Array.isArray(value.noticeIDs) && value.noticeIDs.length <= 513
  && value.noticeIDs.every((id) => /^production:notice:[1-9][0-9]{0,14}$/.test(id))
  && new Set(value.noticeIDs).size === value.noticeIDs.length;

// A private resolved Wrangler config may contain recipient addresses. Retain
// only equality fingerprints of configuration, never its values or credentials.
export function configurationFingerprint(config) {
  if (!object(config) || typeof config.name !== "string" || typeof config.account_id !== "string"
    || !object(config.vars) || !Array.isArray(config.durable_objects?.bindings)) throw new Error("Invalid resolved configuration");
  const bindings = config.durable_objects.bindings.map(({ name, class_name, script_name, environment }) =>
    ({ name, class_name, script_name: script_name ?? null, environment: environment ?? null }))
    .sort((a, b) => a.name.localeCompare(b.name));
  if (bindings.some((row) => typeof row.name !== "string" || typeof row.class_name !== "string")
    || new Set(bindings.map((row) => row.name)).size !== bindings.length) throw new Error("Invalid durable bindings");
  const email = config.send_email || [];
  if (!Array.isArray(email)) throw new Error("Invalid mail binding");
  return { worker: config.name, identity: digest([config.name, config.account_id]), durableBindings: digest(bindings),
    migrations: digest(config.migrations || []), mailBindings: digest(email),
    collectorEnabled: config.vars.FOTTY_WATCHDOG_ENABLED ?? null,
    collectorActivatedAt: config.vars.FOTTY_WATCHDOG_ACTIVATED_AT ?? null,
    emailEnabled: config.vars.FOTTY_OWNER_EMAIL_ENABLED ?? null,
    emailTarget: digest([config.vars.FOTTY_OWNER_EMAIL_ACTIVATED_AT ?? null,
      config.vars.FOTTY_OWNER_EMAIL_SENDER ?? null, config.vars.FOTTY_OWNER_EMAIL_RECIPIENT ?? null]),
    playbackFlags: Object.fromEntries(flags.filter((key) => Object.hasOwn(config.vars, key)).map((key) => [key, config.vars[key]])) };
}

export function captureSafetySnapshot(playback, watchdog, { now = Date.now() } = {}) {
  if (!object(playback) || playback.service !== "fotty-playback" || typeof playback.sourceVersion !== "string"
    || !object(watchdog) || watchdog.schema !== 1 || watchdog.activation !== "active" || !iso(watchdog.activatedAt)
    || typeof watchdog.configurationRevision !== "string" || typeof watchdog.observerRevision !== "string"
    || !Array.isArray(watchdog.notifications) || watchdog.notifications.length > 513
    || healthFlags.some((key) => typeof playback[key] !== "boolean")
    || !Number.isSafeInteger(watchdog.lastCompletedAt) || watchdog.lastCompletedAt < 0 || watchdog.lastCompletedAt > now + 30_000
    || now - watchdog.lastCompletedAt > 35 * 60_000 || watchdog.overflow !== false) throw new Error("Live pair is not a fresh qualified baseline");
  const notices = watchdog.notifications.map((row) => row.id).sort();
  if (notices.some((id) => !/^production:notice:[1-9][0-9]{0,14}$/.test(id)) || new Set(notices).size !== notices.length)
    throw new Error("Invalid notice inventory");
  if (watchdog.expectedDeploymentRevision !== playback.sourceVersion) throw new Error("Live pair has release drift");
  return { schema: 1, capturedAt: new Date(now).toISOString(), sourceVersion: playback.sourceVersion,
    configurationRevision: watchdog.configurationRevision, observerRevision: watchdog.observerRevision,
    activatedAt: watchdog.activatedAt, noticeIDs: notices,
    sourceFlags: Object.fromEntries(healthFlags.filter((key) => Object.hasOwn(playback, key)).map((key) => [key, playback[key]])),
    emailEnabled: watchdog.ownerEmail?.enabled === true };
}

export function evaluateDeploymentPreflight(before, baseline, candidate, { now = Date.now() } = {}) {
  const problems = [];
  if (!baselineValid(before) || now - Date.parse(before.capturedAt) > 10 * 60_000
    || Date.parse(before.capturedAt) > now + 30_000) return { ok: false, problems: ["baseline-expired-or-invalid"] };
  for (const [kind, name] of [["playback", "fotty-playback-v3"], ["watchdog", "fotty-watchdog"]]) {
    if (baseline?.[kind]?.worker !== name || candidate?.[kind]?.worker !== name) problems.push(`${kind}-identity-invalid`);
    for (const key of ["identity", "durableBindings", "migrations"]) {
      if (typeof baseline?.[kind]?.[key] !== "string" || baseline[kind][key] !== candidate?.[kind]?.[key]) problems.push(`${kind}-${key}-changed`);
    }
  }
  const target = candidate?.watchdog;
  if (target?.collectorEnabled !== "1") problems.push("collector-would-be-disabled");
  if (target?.collectorActivatedAt !== before.activatedAt) problems.push("collector-activation-would-change");
  if (!same(baseline?.playback?.playbackFlags, candidate?.playback?.playbackFlags)
    || flags.some((key) => !["0", "1"].includes(candidate?.playback?.playbackFlags?.[key]))) problems.push("fixture-or-playback-flags-would-change");
  if (before.emailEnabled && (target?.emailEnabled !== "1" || target?.emailTarget !== baseline?.watchdog?.emailTarget
    || target?.mailBindings !== baseline?.watchdog?.mailBindings)) problems.push("active-email-configuration-would-change");
  return { ok: problems.length === 0, problems };
}

export function evaluateDeploymentAfter(before, playback, watchdog, expected, { now = Date.now(), deployedAt } = {}) {
  const problems = [];
  if (!baselineValid(before) || Date.parse(before.capturedAt) > now + 30_000) return { ok: false, problems: ["baseline-invalid"] };
  let after;
  try { after = captureSafetySnapshot(playback, watchdog, { now }); }
  catch { return { ok: false, problems: ["deployed-pair-invalid-stale-or-disabled"] }; }
  if (after.sourceVersion !== expected?.sourceVersion || after.configurationRevision !== expected?.configurationRevision
    || after.observerRevision !== expected?.observerRevision) problems.push("deployed-release-identity-mismatch");
  if (after.activatedAt !== before?.activatedAt) problems.push("original-activation-lost");
  if (!Array.isArray(before?.noticeIDs) || before.noticeIDs.some((id) => !after.noticeIDs.includes(id))) problems.push("retained-notices-lost");
  if (!same(before?.sourceFlags, after.sourceFlags)) problems.push("fixture-activation-changed");
  if (before?.emailEnabled && !after.emailEnabled) problems.push("active-email-disabled");
  if (!iso(deployedAt) || Date.parse(deployedAt) < Date.parse(before?.capturedAt)
    || Date.parse(deployedAt) > now || watchdog.lastCompletedAt <= Date.parse(deployedAt))
    problems.push("post-deployment-real-collector-completion-missing");
  return { ok: problems.length === 0, problems, notificationCount: after.noticeIDs.length };
}

// Offline CLI consumes explicitly captured JSON; it cannot fetch arbitrary URLs,
// deploy, modify secrets or send email. Inputs remain private and are not echoed.
async function main(args) {
  const [mode, input, output] = args;
  if (!["preflight", "after"].includes(mode) || !input || !output || args.length !== 3) throw new Error("Usage: deployment-safety.mjs preflight|after PRIVATE_INPUT_JSON RECEIPT_JSON");
  const body = JSON.parse(await readFile(input, "utf8"));
  const result = mode === "preflight" ? evaluateDeploymentPreflight(body.before,
    { playback: configurationFingerprint(body.baselinePlaybackConfig), watchdog: configurationFingerprint(body.baselineWatchdogConfig) },
    { playback: configurationFingerprint(body.candidatePlaybackConfig), watchdog: configurationFingerprint(body.candidateWatchdogConfig) })
    : evaluateDeploymentAfter(body.before, body.playback, body.watchdog, body.expected, { deployedAt: body.deployedAt });
  await writeFile(output, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  process.stdout.write(`${result.ok ? "PASS" : "FAIL"}: ${result.problems.join(",") || "paired-deployment-invariants"}\n`);
  if (!result.ok) process.exitCode = 1;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch(() => { process.stderr.write("Deployment safety input/receipt failed; no deployment performed.\n"); process.exitCode = 1; });
}
