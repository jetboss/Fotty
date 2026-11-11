#!/usr/bin/env node
// Read-only qualification of Apple's public xcresult scalar exports. No device
// actions, builds, network, AX/URL sampling or attachment export occurs here.
// The reviewed identifiers/units below come from physical build 131, not names
// guessed from display strings. New collector schemas require explicit review.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { constants, lstat, open } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const run = promisify(execFile);
const MAX_INPUT = 1_048_576;
const MAX_RECEIPT = 65_536;
const bundleID = "com.jelani.Fotty";
class EvidenceError extends Error {}
const requireValue = (condition, message) => { if (!condition) throw new EvidenceError(message); };
const safeIssue = (error) => error instanceof EvidenceError ? error.message.slice(0, 240)
  : "Public xcresult export or bounded evidence load failed";
const finite = (value) => typeof value === "number" && Number.isFinite(value);
const positiveInteger = (value) => Number.isInteger(value) && value > 0;
const boundedString = (value, maximum = 128) => typeof value === "string" && value.length > 0 && value.length <= maximum;
const sha256 = (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const coreID = (value) => typeof value === "string" && /^[a-fA-F0-9-]{36}$/.test(value);
const hardwareID = (value) => typeof value === "string" && /^[a-fA-F0-9-]{16,64}$/.test(value);
const record = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const knownKeys = (value, keys) => record(value) && Object.keys(value).every((key) => keys.includes(key));
const contextKeys = ["accessibleRows", "thermalState", "uptimeSeconds", "osMajor", "osMinor"];
const project = (value, keys) => Object.fromEntries(keys.filter((key) => Object.hasOwn(value, key)).map((key) => [key, value[key]]));

export const surfaces = Object.freeze({
  home: Object.freeze({ surface: "Home", method: "testPhysicalProductionHomeScrollMetrics", scrolling: true }),
  matchday: Object.freeze({ surface: "Matchday", method: "testPhysicalProductionMatchdayScrollMetrics", scrolling: true }),
  search: Object.freeze({ surface: "Search", method: "testPhysicalProductionLatestSearchMetrics", scrolling: false }),
  "home-signpost": Object.freeze({ surface: "Home", method: "testPhysicalProductionHomeScrollSignpostMetrics", scrolling: true, supplemental: true }),
  "matchday-signpost": Object.freeze({ surface: "Matchday", method: "testPhysicalProductionMatchdayScrollSignpostMetrics", scrolling: true, supplemental: true }),
});
export const primaryScope = Object.freeze(["home", "matchday", "search"]);
export const supplementalScope = Object.freeze(["home-signpost", "matchday-signpost"]);
export const testIdentity = (key) => ({
  testIdentifier: `CatalogPerformanceUITests/${surfaces[key].method}()`,
  testIdentifierURL: `test://com.apple.xcode/Fotty/FottyUITests/CatalogPerformanceUITests/${surfaces[key].method}`,
});

const metric = (identifier, unit, options = {}) => Object.freeze({ identifier, unit, ...options });
export const requiredMetrics = Object.freeze([
  metric(`com.apple.dt.XCTMetric_CPU-${bundleID}.time`, "s", { positive: true }),
  metric(`com.apple.dt.XCTMetric_CPU-${bundleID}.cycles`, "kC", { positive: true }),
  metric(`com.apple.dt.XCTMetric_CPU-${bundleID}.instructions_retired`, "kI", { positive: true }),
  metric(`com.apple.dt.XCTMetric_Memory-${bundleID}.physical`, "kB", { signed: true }),
  metric(`com.apple.dt.XCTMetric_Memory-${bundleID}.physical_absolute`, "kB", { positive: true }),
  metric(`com.apple.dt.XCTMetric_Memory-${bundleID}.physical_peak`, "kB", { positive: true }),
  metric("com.apple.dt.XCTMetric_Hitch-Fotty.time.ratio", "ms per s"),
  metric("com.apple.dt.XCTMetric_Hitch-Fotty.number", "hitches", { integer: true }),
  metric("com.apple.dt.XCTMetric_Hitch-Fotty.total.duration", "s"),
  metric("com.apple.dt.XCTMetric_Clock.time.monotonic", "s", { positive: true }),
]);
export const scrollMetrics = Object.freeze([
  metric("com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.duration", "s", { positive: true }),
  metric("com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.animation.hitch.time.ratio", "ms per s"),
  metric("com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.animation.hitch.number", "hitches", { integer: true }),
  metric("com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.animation.frame.count", "frames", { integer: true }),
  metric("com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.animation.hitches.total.duration", "ms"),
  metric("com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.animation.frame.rate", "fps"),
]);

export function resolveCollectorPlan(key, explicitPlan) {
  requireValue(Object.hasOwn(surfaces, key), "Unknown measurement surface");
  if (explicitPlan === undefined) {
    requireValue(!surfaces[key].supplemental, "Supplementary signposts require an explicit collector plan");
    return "legacy_mixed_v1"; // Existing 131/132 receipts have no plan field.
  }
  if (explicitPlan === "app_target_core_v2") {
    requireValue(!surfaces[key].supplemental, "Core collectors cannot qualify a supplementary signpost test");
    return explicitPlan;
  }
  if (explicitPlan === "scroll_signpost_only_v1") {
    requireValue(surfaces[key].supplemental === true, "Signpost-only collectors cannot qualify a primary app-target test");
    return explicitPlan;
  }
  throw new EvidenceError("Unknown explicit collector plan requires review");
}

const specsForPlan = (key, plan) => plan === "scroll_signpost_only_v1" ? [...scrollMetrics]
  : [...requiredMetrics, ...(plan === "legacy_mixed_v1" && surfaces[key].scrolling ? scrollMetrics : [])];
const tagsForPlan = (key, plan) => plan === "scroll_signpost_only_v1" ? ["scroll_signpost"]
  : ["app_cpu", "app_memory", "app_hitch", "wall_clock", ...(plan === "legacy_mixed_v1" && surfaces[key].scrolling ? ["scroll_signpost"] : [])];

export function validateBinding({ build, sourceSHA, executableSHA, coreDeviceID, hardwareDeviceID, appsReadback, deviceDetails }) {
  requireValue(typeof build === "string" && /^[0-9]{1,16}$/.test(build), "A verified numeric build is required");
  requireValue(sha256(sourceSHA) && sha256(executableSHA), "Verified source/executable SHA-256 identities are required");
  requireValue(coreID(coreDeviceID) && hardwareID(hardwareDeviceID), "Explicit CoreDevice and hardware identities are required");
  requireValue(appsReadback?.info?.outcome === "success"
    && appsReadback.info.commandType === "devicectl.device.info.apps"
    && appsReadback.result?.deviceIdentifier === coreDeviceID, "Installed-app readback is not for the selected device");
  const apps = appsReadback.result.apps;
  requireValue(Array.isArray(apps) && apps.length <= 1000, "Malformed installed-app readback");
  const matching = apps.filter((app) => app?.bundleIdentifier === bundleID);
  requireValue(matching.length === 1 && matching[0].bundleVersion === build
    && matching[0].builtByDeveloper === true && typeof matching[0].version === "string"
    && /^[0-9]{1,3}(\.[0-9]{1,3}){0,3}$/.test(matching[0].version), "Installed Fotty build does not match the verified build");
  requireValue(deviceDetails?.info?.outcome === "success"
    && deviceDetails.info.commandType === "devicectl.device.info.details"
    && deviceDetails.result?.identifier === coreDeviceID
    && deviceDetails.result.properties?.hardware?.udid === hardwareDeviceID
    && deviceDetails.result.properties.hardware.reality === "physical"
    && deviceDetails.result.properties.hardware.platform === "iOS"
    && boundedString(deviceDetails.result.properties.hardware.marketingName, 64)
    && /^[A-Za-z0-9()., '\-]+$/.test(deviceDetails.result.properties.hardware.marketingName),
  "CoreDevice/hardware mapping is not verified physical hardware");
  return {
    build, version: matching[0].version, bundleID, sourceSHA256: sourceSHA,
    executableSHA256: executableSHA, coreDeviceID, hardwareDeviceID,
    modelName: deviceDetails.result.properties.hardware.marketingName,
    sourceBindingBasis: "owner_verified_prebuild_source_and_signed_executable_SHA; installed_build_readback_checked",
  };
}

function verifyDetails(details, key, binding, configurationID) {
  const identity = testIdentity(key);
  requireValue(record(details) && details.testIdentifier === identity.testIdentifier
    && details.testIdentifierURL === identity.testIdentifierURL, "Test details do not match the exact selected test");
  requireValue(details.testResult === "Passed" && details.hasPerformanceMetrics === true,
    "Test did not pass with returned performance metrics");
  requireValue(finite(details.startTime) && finite(details.durationInSeconds)
    && details.durationInSeconds > 0, "Missing test time bounds");
  requireValue(Array.isArray(details.devices) && details.devices.length === 1
    && details.devices[0].deviceId === binding.hardwareDeviceID
    && details.devices[0].platform === "iOS" && details.devices[0].modelName === binding.modelName
    && typeof details.devices[0].osVersion === "string" && /^[0-9]{1,3}(\.[0-9]{1,3}){1,2}$/.test(details.devices[0].osVersion)
    && typeof details.devices[0].osBuildNumber === "string" && /^[A-Za-z0-9]{1,32}$/.test(details.devices[0].osBuildNumber),
  "Ambiguous/wrong performance device");
  const configurations = details.testPlanConfigurations;
  requireValue(Array.isArray(configurations) && configurations.length === 1
    && configurations[0].configurationId === configurationID
    && boundedString(configurations[0].configurationName), "Ambiguous/wrong test configuration");
  // Refuse combined retries/devices. A successful public test-details record
  // can contain Runtime Warning children with Source Code Reference metadata:
  // build 132 did so when scrolling signposts were missing. Those are not
  // retries. Never retain their text/paths or infer valid samples from them.
  requireValue(Array.isArray(details.testRuns) && details.testRuns.length === 1
    && details.testRuns[0].nodeType === "Device" && details.testRuns[0].nodeIdentifier === binding.hardwareDeviceID
    && details.testRuns[0].result === "Passed" && details.testRuns[0].children?.length === 1,
  "Ambiguous performance test runs");
  const configurationRun = details.testRuns[0].children[0];
  const knownWarningsOnly = configurationRun.children === undefined
    || (Array.isArray(configurationRun.children) && configurationRun.children.length <= 16
      && configurationRun.children.every((child) => {
        if (!record(child) || child.nodeType !== "Runtime Warning") return false;
        if (child.children === undefined) return true;
        return Array.isArray(child.children) && child.children.length <= 4
          && child.children.every((reference) => record(reference) && reference.nodeType === "Source Code Reference"
            && (reference.children === undefined || (Array.isArray(reference.children) && reference.children.length === 0)));
      }));
  requireValue(configurationRun.nodeType === "Test Plan Configuration"
    && configurationRun.nodeIdentifier === configurationID && configurationRun.result === "Passed"
    && knownWarningsOnly,
  "Unreviewed run children or combined retries cannot qualify as one three-iteration test");
  return { device: details.devices[0], configuration: configurations[0] };
}

function verifyContext(context, details) {
  requireValue(knownKeys(context, contextKeys), "Unknown workload context fields are not retained");
  requireValue(Number.isInteger(context.accessibleRows) && context.accessibleRows >= 0
    && context.accessibleRows <= 1_000_000 && Number.isInteger(context.thermalState)
    && context.thermalState >= 0 && context.thermalState <= 3 && finite(context.uptimeSeconds)
    && context.uptimeSeconds > 0 && positiveInteger(context.osMajor)
    && Number.isInteger(context.osMinor) && context.osMinor >= 0, "Missing/invalid bounded workload context");
  const [major, minor] = details.devices[0].osVersion.split(".").map(Number);
  requireValue(context.osMajor === major && context.osMinor === minor, "Workload OS does not match measured device");
}

export function validateWorkload(workload, key, binding, details) {
  const { surface, scrolling } = surfaces[key];
  requireValue(knownKeys(workload, ["surface", "build", "cacheCleared", "normalProductionFeeds", "includesAutomationOverhead",
    "crossBuildComparisonQualified", "externalMetricValidationRequired", "scrollRestorationOutsideMeasurement",
    "includesAnchorInspection", "includesSearchFocusAndClearing", "measurementBoundary", "metricValidation",
    "measuredScrollSwipesPerInvocation", "warmupInvocations", "retainedIterations", "totalInvocations",
    "contextBefore", "contextAfter", "expectedMetricTags", "workloads", "scrollMovement", "requiredReturnedEvidence", "collectorPlan"]),
  "Unknown workload fields are not retained");
  requireValue(record(workload) && workload.surface === surface && workload.build === binding.build,
    "Workload surface/build does not match selected evidence");
  const plan = resolveCollectorPlan(key, workload.collectorPlan);
  const expectedFlags = {
    cacheCleared: false, normalProductionFeeds: true, includesAutomationOverhead: true,
    crossBuildComparisonQualified: false, externalMetricValidationRequired: true,
    scrollRestorationOutsideMeasurement: false, includesAnchorInspection: scrolling,
    includesSearchFocusAndClearing: !scrolling,
  };
  requireValue(Object.entries(expectedFlags).every(([key, value]) => workload[key] === value)
    && workload.measurementBoundary === "automatic_interaction_block"
    && workload.metricValidation === "not_qualified_until_xcresult_values_are_verified"
    && workload.measuredScrollSwipesPerInvocation === (scrolling ? 2 : 0)
    && workload.warmupInvocations === 1 && workload.retainedIterations === 3
    && workload.totalInvocations === 4, "Workload boundaries/qualification flags are missing or changed");
  const tags = tagsForPlan(key, plan);
  requireValue(Array.isArray(workload.expectedMetricTags) && workload.expectedMetricTags.length === tags.length
    && tags.every((tag, index) => workload.expectedMetricTags[index] === tag), "Changed metric workload contract");
  verifyContext(workload.contextBefore, details); verifyContext(workload.contextAfter, details);
  requireValue(workload.contextAfter.uptimeSeconds >= workload.contextBefore.uptimeSeconds,
    "Workload monotonic context moved backwards");
  requireValue(Array.isArray(workload.workloads) && workload.workloads.length === 4
    && new Set(workload.workloads.map((row) => row?.invocation)).size === 4, "Missing/duplicate workload invocations");
  for (let ordinal = 0; ordinal <= 3; ordinal += 1) {
    const row = workload.workloads.find((row) => row?.invocation === ordinal);
    requireValue(knownKeys(row, scrolling ? ["invocation", "appForeground", "warmup"]
      : ["invocation", "appForeground", "warmup", "queryLength"])
      && row.appForeground === true && row.warmup === (ordinal === 0),
      "An invocation did not finish its foreground workload or has incorrect warmup labeling");
    if (!scrolling) requireValue(row.queryLength === (ordinal % 2 === 0 ? 8 : 2), "Incomplete committed Search workload");
  }
  requireValue(Array.isArray(workload.scrollMovement) && workload.scrollMovement.length === (scrolling ? 4 : 0),
    "Missing/extra movement evidence");
  if (scrolling) {
    requireValue(workload.contextBefore.accessibleRows > 0
      && new Set(workload.scrollMovement.map((row) => row?.invocation)).size === 4, "Missing/duplicate production movement workload");
    for (let ordinal = 0; ordinal <= 3; ordinal += 1) {
      const row = workload.scrollMovement.find((row) => row?.invocation === ordinal);
      requireValue(knownKeys(row, ["invocation", "translationPoints"])
        && finite(row.translationPoints) && row.translationPoints > 8
        && row.translationPoints < 1_000_000, "An invocation did not prove actual catalog translation");
    }
  }
  return workload;
}

export function validateMetricSamples(exported, key, binding, configuration, explicitPlan) {
  const identity = testIdentity(key);
  requireValue(Array.isArray(exported) && exported.length === 1
    && exported[0].testIdentifier === identity.testIdentifier
    && exported[0].testIdentifierURL === identity.testIdentifierURL, "Missing/ambiguous exact-test metric export");
  const runs = exported[0].testRuns;
  requireValue(Array.isArray(runs) && runs.length === 1
    && runs[0].device?.deviceId === binding.hardwareDeviceID
    && runs[0].testPlanConfiguration?.configurationId === configuration.configurationId
    && runs[0].testPlanConfiguration.configurationName === configuration.configurationName,
  "Metrics cannot be combined across devices/configurations/runs");
  const expected = specsForPlan(key, resolveCollectorPlan(key, explicitPlan));
  const metrics = runs[0].metrics;
  requireValue(Array.isArray(metrics) && metrics.length === expected.length
    && new Set(metrics.map((row) => row?.identifier)).size === metrics.length,
  "Missing, duplicate or unreviewed metric identifiers; no invalid metrics are silently discarded");
  return expected.map((spec) => {
    const row = metrics.find((row) => row?.identifier === spec.identifier);
    requireValue(record(row) && row.unitOfMeasurement === spec.unit && Array.isArray(row.measurements)
      && row.measurements.length === 3, "Metric units or three retained samples are missing");
    requireValue(row.measurements.every((value) => finite(value)
      && (spec.signed || value >= 0) && (!spec.positive || value > 0)
      && (!spec.integer || Number.isInteger(value))), "A retained metric is nonfinite, malformed or unavailable");
    // Memory growth is a before/after difference and may be negative. Zero
    // hitch counts are valid scalar samples, not proof of frame continuity.
    return { identifier: spec.identifier, unit: spec.unit, retainedSamples: [...row.measurements] };
  });
}

export function validateSurfaceEvidence({ key, details, metrics, workload, attachment, binding, configurationID }) {
  const { device, configuration } = verifyDetails(details, key, binding, configurationID);
  requireValue(attachment?.deviceId === binding.hardwareDeviceID
    && attachment.configurationName === configuration.configurationName
    && attachment.isAssociatedWithFailure === false && finite(attachment.timestamp)
    && attachment.timestamp >= details.startTime
    && attachment.timestamp <= details.startTime + details.durationInSeconds + 5,
  "Workload attachment does not belong to the selected successful run");
  validateWorkload(workload, key, binding, details);
  const collectorPlan = resolveCollectorPlan(key, workload.collectorPlan);
  const scalarMetrics = validateMetricSamples(metrics, key, binding, configuration, workload.collectorPlan);
  return {
    surface: surfaces[key].surface, ...testIdentity(key), qualified: true,
    collectorPlan, supplemental: surfaces[key].supplemental === true,
    qualification: collectorPlan === "scroll_signpost_only_v1"
      ? "finite_scroll_signpost_scalars_with_completed_workload_only"
      : "finite_app_target_scalars_with_completed_workload_only",
    device: { deviceId: device.deviceId, model: device.modelName, platform: device.platform,
      osVersion: device.osVersion, osBuildNumber: device.osBuildNumber },
    configuration: { configurationId: configuration.configurationId },
    warmupInvocations: 1, retainedIterations: 3, totalInvocations: 4,
    measurementBoundary: workload.measurementBoundary,
    cacheCleared: false, normalProductionFeeds: true, includesAutomationOverhead: true,
    crossBuildComparisonQualified: false, frameContinuityQualified: false,
    zeroHitchOrSpeedImprovementClaimQualified: false,
    contextBefore: project(workload.contextBefore, contextKeys), contextAfter: project(workload.contextAfter, contextKeys),
    scrollMovement: workload.scrollMovement.map((row) => project(row, ["invocation", "translationPoints"])),
    workloads: workload.workloads.map((row) => project(row, ["invocation", "appForeground", "warmup", "queryLength"])),
    scalarMetrics,
  };
}

export function summarizeEvidence({ scope = primaryScope, binding, evidence }) {
  requireValue(Array.isArray(scope) && scope.length > 0 && scope.length <= 5
    && new Set(scope).size === scope.length && scope.every((key) => Object.hasOwn(surfaces, key)), "Invalid/duplicate selected scope");
  const results = scope.map((key) => {
    try { return validateSurfaceEvidence({ ...evidence[key], key, binding }); }
    catch (error) { return { surface: surfaces[key].surface, ...testIdentity(key), qualified: false,
      issue: safeIssue(error) }; }
  });
  const primaryResults = primaryScope.map((key) => results.find((row) => row.testIdentifierURL === testIdentity(key).testIdentifierURL));
  const primaryComplete = primaryResults.every((row) => row?.qualified === true);
  const samePrimaryPlan = primaryComplete && new Set(primaryResults.map((row) => row.collectorPlan)).size === 1;
  const primaryRequested = primaryScope.every((key) => scope.includes(key));
  const selectedScopeQualified = results.every((row) => row.qualified) && (!primaryRequested || samePrimaryPlan);
  return { schema: 2, reviewedCollectorSchema: "xcresulttool test-results metrics; physical build 131 identifiers/units; explicit core/signpost plans",
    binding: project(binding, ["build", "version", "bundleID", "sourceSHA256", "executableSHA256",
      "coreDeviceID", "hardwareDeviceID", "modelName", "sourceBindingBasis"]),
    selectedScope: scope, selectedScopeQualified,
    scopeIssue: primaryRequested && primaryComplete && !samePrimaryPlan ? "Primary surfaces use different collector plans; no common baseline qualifies" : null,
    fullCatalogPerformanceGateQualified: primaryComplete && samePrimaryPlan,
    primaryAppTargetCoreGateQualified: primaryComplete && primaryResults.every((row) => row.collectorPlan === "app_target_core_v2"),
    legacyMixedCollectorGateQualified: primaryComplete && primaryResults.every((row) => row.collectorPlan === "legacy_mixed_v1"),
    supplementalScrollSignpostGateQualified: supplementalScope.every((key) => results.some((row) =>
      row.testIdentifierURL === testIdentity(key).testIdentifierURL && row.qualified === true)),
    qualification: selectedScopeQualified ? (primaryComplete && samePrimaryPlan ? "full_primary_scalar_workload_set" : "explicit_partial_scalar_workload_set") : "incomplete",
    limitations: ["Automatic whole interaction blocks include XCTest overhead and retained production cache.",
      "Finite scalar samples do not establish continuous decoded frames, zero hitches, faster search or cross-build improvement.",
      "Core v2 and legacy mixed collector plans are different baselines; supplementary signposts never substitute for core app metrics.",
      "Source/executable SHA identities are verified owner inputs; xcresult does not provide the installed app build identity."],
    results };
}

export async function readBoundedJSON(file, maximumBytes = MAX_INPUT) {
  requireValue(path.isAbsolute(file), "Evidence must use an absolute local path");
  // Check and read through one handle so the file cannot be swapped in between;
  // O_NOFOLLOW refuses a symbolic link.
  let handle;
  try {
    handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  } catch {
    requireValue(false, "Evidence file is not a bounded regular file");
  }
  try {
    const attributes = await handle.stat();
    requireValue(attributes.isFile() && attributes.size > 0
      && attributes.size <= maximumBytes, "Evidence file is not a bounded regular file");
    const bytes = await handle.readFile();
    requireValue(bytes.length <= maximumBytes, "Evidence grew beyond the input bound");
    return JSON.parse(bytes.toString("utf8"));
  } finally {
    await handle.close();
  }
}

async function xcresultJSON(bundle, command, testID) {
  const { stdout } = await run("xcrun", ["xcresulttool", "get", "test-results", command,
    "--path", bundle, "--test-id", testID, "--compact"], { timeout: 20_000, maxBuffer: MAX_INPUT, encoding: "utf8" });
  requireValue(Buffer.byteLength(stdout) <= MAX_INPUT, "xcresult export exceeded the input bound");
  return JSON.parse(stdout);
}

async function main(argv) {
  if (argv.length === 1 && argv[0] === "--help") {
    process.stdout.write("Read-only: node tools/verify-catalog-performance.mjs --bundle ABS.xcresult --attachments ABS_DIR --apps-readback ABS.json --device-details ABS.json --core-device UUID --hardware-device UDID --build NUMBER --source-sha SHA256 --executable-sha SHA256 [--configuration 1] [--scope home,matchday]\n"
      + "Default scope is the three PRIMARY journeys and fails if any is incomplete. Supplemental scope: home-signpost,matchday-signpost; it never substitutes for primary app metrics. Core v2 is a different baseline from old mixed collectors. Explicit partial scope never qualifies the full primary gate. SHA inputs must be verified against pre-build source/signed executable; filenames are not build evidence. Only existing JSON workload attachments are read.\n"); return;
  }
  const accepted = ["--bundle", "--attachments", "--apps-readback", "--device-details", "--core-device", "--hardware-device", "--build", "--source-sha", "--executable-sha", "--configuration", "--scope"];
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index], value = argv[++index];
    requireValue(accepted.includes(key) && args[key] === undefined && boundedString(value, 4096)
      && !value.startsWith("--"), "Unknown, duplicate or incomplete argument"); args[key] = value;
  }
  const bundle = args["--bundle"], attachments = args["--attachments"];
  requireValue(path.isAbsolute(bundle ?? "") && bundle.endsWith(".xcresult") && path.isAbsolute(attachments ?? ""), "Absolute bundle/attachment paths are required");
  for (const directory of [bundle, attachments]) {
    const attributes = await lstat(directory);
    requireValue(attributes.isDirectory() && !attributes.isSymbolicLink(), "Evidence directories must not be symlinks");
  }
  const binding = validateBinding({ build: args["--build"], sourceSHA: args["--source-sha"], executableSHA: args["--executable-sha"],
    coreDeviceID: args["--core-device"], hardwareDeviceID: args["--hardware-device"],
    appsReadback: await readBoundedJSON(args["--apps-readback"] ?? ""), deviceDetails: await readBoundedJSON(args["--device-details"] ?? "") });
  const scope = args["--scope"]?.split(",") ?? [...primaryScope];
  requireValue(scope.length > 0 && scope.length <= 5 && new Set(scope).size === scope.length
    && scope.every((key) => Object.hasOwn(surfaces, key)), "Invalid selected scope");
  const configurationID = args["--configuration"] ?? "1";
  requireValue(/^[0-9]{1,16}$/.test(configurationID), "Invalid configuration identity");
  const manifest = await readBoundedJSON(path.join(attachments, "manifest.json"));
  requireValue(Array.isArray(manifest) && manifest.length <= 1000, "Malformed attachment manifest");
  const evidence = {};
  for (const key of scope) {
    const identity = testIdentity(key);
    try {
      const details = await xcresultJSON(bundle, "test-details", identity.testIdentifierURL);
      // Failed/no-metric tests are reported as incomplete before reading large
      // diagnostic attachments. Never substitute another test's measurements.
      verifyDetails(details, key, binding, configurationID);
      const matches = manifest.filter((row) => row?.testIdentifier === identity.testIdentifier
        && row.testIdentifierURL === identity.testIdentifierURL);
      requireValue(matches.length === 1 && Array.isArray(matches[0].attachments)
        && matches[0].attachments.length <= 1000, "Missing/ambiguous exact-test workload manifest");
      const collectorLabel = surfaces[key].supplemental ? "scroll-signpost" : "app-target";
      const label = `Production ${surfaces[key].surface} ${collectorLabel} metrics; warm-up and workload context labeled_`;
      const workloadAttachments = matches[0].attachments.filter((row) => typeof row?.suggestedHumanReadableName === "string"
        && row.suggestedHumanReadableName.startsWith(label) && row.suggestedHumanReadableName.endsWith(".json")
        && row.deviceId === binding.hardwareDeviceID);
      requireValue(workloadAttachments.length === 1, "Missing/ambiguous workload attachment");
      const attachment = workloadAttachments[0];
      requireValue(typeof attachment.exportedFileName === "string"
        && /^[A-Fa-f0-9-]{36}\.json$/.test(attachment.exportedFileName), "Unsafe workload attachment path");
      const workload = await readBoundedJSON(path.join(attachments, attachment.exportedFileName), MAX_RECEIPT);
      const metrics = await xcresultJSON(bundle, "metrics", identity.testIdentifierURL);
      evidence[key] = { details, metrics, workload, attachment, configurationID };
    } catch (error) {
      // Keep a bounded public error for the requested failed surface, not a
      // fabricated empty metric list or a passing partial whole-set receipt.
      evidence[key] = { loadError: safeIssue(error) };
    }
  }
  const report = summarizeEvidence({ scope, binding, evidence });
  for (let index = 0; index < scope.length; index += 1) {
    if (evidence[scope[index]].loadError) report.results[index].issue = evidence[scope[index]].loadError;
  }
  const output = JSON.stringify(report, null, 2);
  requireValue(Buffer.byteLength(output) <= MAX_RECEIPT, "Scalar receipt exceeds output bound");
  process.stdout.write(`${output}\n`);
  process.exitCode = report.selectedScopeQualified ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(() => {
    // Do not echo arbitrary source/diagnostic text, paths or credentials from
    // failed child processes into a retained receipt.
    process.stderr.write("Catalog metric verification failed before evidence qualification. Check explicit bounded input identities/paths.\n");
    process.exitCode = 1;
  });
}
