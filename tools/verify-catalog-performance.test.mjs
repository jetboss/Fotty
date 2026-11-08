import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, symlink } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { surfaces, primaryScope, testIdentity, requiredMetrics, scrollMetrics, validateBinding,
  validateMetricSamples, validateSurfaceEvidence, summarizeEvidence, readBoundedJSON } from "./verify-catalog-performance.mjs";

const coreDeviceID = "34E32922-73D6-54EA-8556-7904EE7804BD";
const hardwareDeviceID = "00008101-001954E20AC0001E";
const configuration = { configurationId: "1", configurationName: "Test Scheme Action" };
const device = { deviceId: hardwareDeviceID, deviceName: "Jet iPad", platform: "iOS",
  modelName: "iPad Air (4th generation)", osVersion: "27.0.1", osBuildNumber: "24A446" };
function bindingInput() {
  return { build: "131", sourceSHA: "a".repeat(64), executableSHA: "b".repeat(64), coreDeviceID, hardwareDeviceID,
    appsReadback: { info: { outcome: "success", commandType: "devicectl.device.info.apps" },
      result: { deviceIdentifier: coreDeviceID, apps: [{ bundleIdentifier: "com.jelani.Fotty", bundleVersion: "131", builtByDeveloper: true, version: "2.0.1" }] } },
    deviceDetails: { info: { outcome: "success", commandType: "devicectl.device.info.details" },
      result: { identifier: coreDeviceID, properties: { hardware: { udid: hardwareDeviceID, reality: "physical",
        platform: "iOS", marketingName: "iPad Air (4th generation)" } } } } };
}
const binding = validateBinding(bindingInput());
const clone = (value) => structuredClone(value);
function evidence(key = "home") {
  const { surface, scrolling, supplemental } = surfaces[key];
  const identity = testIdentity(key);
  const context = { accessibleRows: 10, osMajor: 27, osMinor: 0, thermalState: 0, uptimeSeconds: 100 };
  const workload = { surface, build: "131", cacheCleared: false, normalProductionFeeds: true,
    includesAutomationOverhead: true, crossBuildComparisonQualified: false,
    externalMetricValidationRequired: true, scrollRestorationOutsideMeasurement: false,
    includesAnchorInspection: scrolling, includesSearchFocusAndClearing: !scrolling,
    measurementBoundary: "automatic_interaction_block",
    metricValidation: "not_qualified_until_xcresult_values_are_verified",
    measuredScrollSwipesPerInvocation: scrolling ? 2 : 0,
    warmupInvocations: 1, retainedIterations: 3, totalInvocations: 4,
    contextBefore: { ...context }, contextAfter: { ...context, uptimeSeconds: 120 },
    ...(supplemental ? { collectorPlan: "scroll_signpost_only_v1" } : {}),
    expectedMetricTags: supplemental ? ["scroll_signpost"] : ["app_cpu", "app_memory", "app_hitch", "wall_clock", ...(scrolling ? ["scroll_signpost"] : [])],
    workloads: [0, 1, 2, 3].map((invocation) => ({ invocation, warmup: invocation === 0, appForeground: true,
      ...(!scrolling ? { queryLength: invocation % 2 === 0 ? 8 : 2 } : {}) })),
    scrollMovement: scrolling ? [0, 1, 2, 3].map((invocation) => ({ invocation, translationPoints: 501 })) : [] };
  const details = { ...identity, testResult: "Passed", hasPerformanceMetrics: true, startTime: 1000, durationInSeconds: 60,
    devices: [device], testPlanConfigurations: [configuration], testRuns: [{ nodeType: "Device", nodeIdentifier: hardwareDeviceID,
      result: "Passed", children: [{ nodeType: "Test Plan Configuration", nodeIdentifier: "1", result: "Passed" }] }] };
  const specs = supplemental ? scrollMetrics : [...requiredMetrics, ...(scrolling ? scrollMetrics : [])];
  const metrics = [{ ...identity, testRuns: [{ device, testPlanConfiguration: configuration,
    metrics: specs.map((spec) => ({ identifier: spec.identifier, unitOfMeasurement: spec.unit,
      measurements: [1, 2, 3] })) }] }];
  const attachment = { deviceId: hardwareDeviceID, configurationName: configuration.configurationName,
    isAssociatedWithFailure: false, timestamp: 1059 };
  return { key, binding, details, metrics, workload, attachment, configurationID: "1" };
}
const metricRows = (sample) => sample.metrics[0].testRuns[0].metrics;

test("actual reviewed metric IDs retain all16 scroll /10Search rows and exactly3values", () => {
  for (const key of Object.keys(surfaces)) {
    const result = validateSurfaceEvidence(evidence(key));
    assert.equal(result.qualified, true);
    assert.equal(result.scalarMetrics.length, surfaces[key].supplemental ? 6 : surfaces[key].scrolling ? 16 : 10);
    assert.ok(result.scalarMetrics.every((row) => row.retainedSamples.length === 3));
    assert.equal(result.frameContinuityQualified, false);
    assert.equal(result.zeroHitchOrSpeedImprovementClaimQualified, false);
  }
});

test("negative before-after memorygrowth and zero hitch/frame counts remain truthful scalar values", () => {
  const sample = evidence();
  metricRows(sample).find((row) => row.identifier.endsWith(".physical")).measurements = [-10, 0, -2];
  for (const row of metricRows(sample).filter((row) => row.identifier.includes("hitch") || row.identifier.endsWith(".frame.count"))) {
    row.measurements = [0, 0, 0];
  }
  assert.equal(validateSurfaceEvidence(sample).qualified, true);
});

test("missing/short/extra retained arrays cannot borrow warmup or averages", () => {
  for (const measurements of [[], [1, 2], [1, 2, 3, 4], undefined]) {
    const sample = evidence(); metricRows(sample)[0].measurements = measurements;
    metricRows(sample)[0].baselineAverage = 3;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("every retained value is finite numeric evidence; booleans/strings/nonfinite values fail", () => {
  for (const invalid of [NaN, Infinity, -Infinity, "3", true, false, null, undefined]) {
    const sample = evidence(); metricRows(sample)[0].measurements[2] = invalid;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("negative durations, unavailable CPU/memory and fractionalcount samples fail", () => {
  for (const [suffix, value] of [[".time", 0], [".physical_peak", 0], [".physical_absolute", -1], [".number", 0.5], [".total.duration", -1]]) {
    const sample = evidence(); metricRows(sample).find((row) => row.identifier.endsWith(suffix)).measurements[1] = value;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("missing metricfamily, duplicateID, unknowncollector, missingID and wrongunit never silently disappear", () => {
  const mutations = [
    (rows) => rows.pop(),
    (rows) => { rows[1].identifier = rows[0].identifier; },
    (rows) => { rows[0].identifier = "unreviewed.collector"; },
    (rows) => { delete rows[0].identifier; },
    (rows) => { rows[0].unitOfMeasurement = "ms"; },
  ];
  for (const mutate of mutations) {
    const sample = evidence(); mutate(metricRows(sample));
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("metricexports require exacttest/device/config and a single unambiguous run", () => {
  const mutations = [
    (sample) => { sample.metrics[0].testIdentifierURL = testIdentity("search").testIdentifierURL; },
    (sample) => { sample.metrics[0].testRuns[0].device.deviceId = "other"; },
    (sample) => { sample.metrics[0].testRuns[0].testPlanConfiguration.configurationId = "2"; },
    (sample) => { sample.metrics[0].testRuns.push(clone(sample.metrics[0].testRuns[0])); },
    (sample) => { sample.metrics.push(clone(sample.metrics[0])); },
  ];
  for (const mutate of mutations) {
    const sample = clone(evidence()); mutate(sample);
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("failed/skipped/no-metric testdetails cannot become a successfulscalar gate", () => {
  for (const result of ["Failed", "Skipped", "Expected Failure"]) {
    const sample = evidence(); sample.details.testResult = result;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
  const sample = evidence(); sample.details.hasPerformanceMetrics = false;
  assert.throws(() => validateSurfaceEvidence(sample));
});

test("retried/merged details and wrongOS workload are rejected", () => {
  const sample = evidence(); sample.details.testRuns[0].children[0].children = [{ nodeType: "Test Case Run", result: "Passed" }];
  assert.throws(() => validateSurfaceEvidence(sample));
  const another = evidence(); another.workload.contextBefore.osMajor = 26;
  assert.throws(() => validateSurfaceEvidence(another));
});

test("public runtimewarning/source-reference children are notmisclassified asretries orvalueproof", () => {
  const sample = evidence();
  sample.details.testRuns[0].children[0].children = [{ nodeType: "Runtime Warning",
    name: "https://secret.invalid/not-for-output", children: [{ nodeType: "Source Code Reference",
      sourceLocation: { filePath: "/private/user-data", lineNumber: 103 } }] }];
  const valid = summarizeEvidence({ scope: ["home"], binding, evidence: { home: sample } });
  assert.equal(valid.selectedScopeQualified, true);
  assert.equal(JSON.stringify(valid).includes("secret.invalid"), false);
  assert.equal(JSON.stringify(valid).includes("private/user-data"), false);
  for (const row of metricRows(sample)) row.measurements = [1];
  const incomplete = summarizeEvidence({ scope: ["home"], binding, evidence: { home: sample } });
  assert.equal(incomplete.selectedScopeQualified, false);
  assert.equal(incomplete.results[0].issue, "Metric units or three retained samples are missing");
});

test("only reviewedwarning metadatachildren areallowed; actualTestCaseRun stillrejects", () => {
  for (const child of [{ nodeType: "Test Case Run", result: "Passed" }, { nodeType: "Future Node" },
    { nodeType: "Runtime Warning", children: [{ nodeType: "Test Case Run", result: "Passed" }] }]) {
    const sample = evidence(); sample.details.testRuns[0].children[0].children = [child];
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("actual workload flags and automatic measurement boundary are required", () => {
  for (const [key, value] of [["cacheCleared", true], ["normalProductionFeeds", false],
    ["includesAutomationOverhead", false], ["crossBuildComparisonQualified", true],
    ["measurementBoundary", "manual"], ["measuredScrollSwipesPerInvocation", 1], ["includesAnchorInspection", false],
    ["scrollRestorationOutsideMeasurement", true], ["externalMetricValidationRequired", false], ["retainedIterations", 2]]) {
    const sample = evidence(); sample.workload[key] = value;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("all4 workload invocations, foreground state and warmup labels must match", () => {
  for (const mutate of [
    (rows) => rows.pop(),
    (rows) => { rows[3].invocation = 2; },
    (rows) => { rows[1].warmup = true; },
    (rows) => { rows[2].appForeground = false; },
  ]) {
    const sample = evidence(); mutate(sample.workload.workloads);
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("movement is required on every invocation, not justsuccessfulswipe APIs", () => {
  for (const invalid of [0, 8, -9, Infinity, "501", undefined]) {
    const sample = evidence(); sample.workload.scrollMovement[2].translationPoints = invalid;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
  const sample = evidence(); sample.workload.scrollMovement[3].invocation = 2;
  assert.throws(() => validateSurfaceEvidence(sample));
});

test("Search receipt requires unchanged4 exactcommitted query lengths, no borrowedscroll evidence", () => {
  const sample = evidence("search"); sample.workload.workloads[1].queryLength = 1;
  assert.throws(() => validateSurfaceEvidence(sample));
  const another = evidence("search"); another.workload.scrollMovement = [{ invocation: 1, translationPoints: 100 }];
  assert.throws(() => validateSurfaceEvidence(another));
});

test("workload attachments must belong to the same successful device/config/timewindow", () => {
  for (const [key, value] of [["deviceId", "other"], ["configurationName", "other"],
    ["isAssociatedWithFailure", true], ["timestamp", 999], ["timestamp", 1066]]) {
    const sample = evidence(); sample.attachment[key] = value;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("verifiedinstalledbuild, explicitphysicaldevice mapping and ownerSHA inputs aremandatory", () => {
  for (const mutate of [
    (input) => { input.sourceSHA = "filename131"; },
    (input) => { input.executableSHA = "a"; },
    (input) => { input.appsReadback.result.apps[0].bundleVersion = "132"; },
    (input) => { input.appsReadback.result.deviceIdentifier = "other"; },
    (input) => { input.deviceDetails.result.properties.hardware.udid = "other"; },
    (input) => { input.deviceDetails.result.properties.hardware.reality = "simulated"; },
    (input) => { input.appsReadback.result.apps.push(clone(input.appsReadback.result.apps[0])); },
  ]) {
    const input = bindingInput(); mutate(input); assert.throws(() => validateBinding(input));
  }
  const sample = evidence(); sample.workload.build = "132";
  assert.throws(() => validateSurfaceEvidence(sample));
});

test("whole-set fail retains qualifiedHome/Matchday but cannot hide missingSearch", () => {
  const report = summarizeEvidence({ binding, evidence: { home: evidence("home"), matchday: evidence("matchday") } });
  assert.equal(report.selectedScopeQualified, false);
  assert.equal(report.fullCatalogPerformanceGateQualified, false);
  assert.deepEqual(report.results.map((row) => row.qualified), [true, true, false]);
  const partial = summarizeEvidence({ scope: ["home", "matchday"], binding,
    evidence: { home: evidence("home"), matchday: evidence("matchday") } });
  assert.equal(partial.selectedScopeQualified, true);
  assert.equal(partial.fullCatalogPerformanceGateQualified, false);
  assert.equal(partial.qualification, "explicit_partial_scalar_workload_set");
});

test("only explicitlycomplete all3surface scope can qualifyfullscalarset; duplicate/unknownscopefail", () => {
  const report = summarizeEvidence({ binding, evidence: Object.fromEntries(Object.keys(surfaces).map((key) => [key, evidence(key)])) });
  assert.equal(report.fullCatalogPerformanceGateQualified, true);
  for (const scope of [[], ["home", "home"], ["home", "future"]]) {
    assert.throws(() => summarizeEvidence({ scope, binding, evidence: {} }));
  }
});

test("boundedreader rejectsoversize/symlink/relative evidence and malformedJSON", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "FottyMetricVerifierTest."));
  try {
    const file = path.join(directory, "sample.json"), link = path.join(directory, "link.json");
    await writeFile(file, "{}"); assert.deepEqual(await readBoundedJSON(file, 2), {});
    await assert.rejects(readBoundedJSON(file, 1)); await assert.rejects(readBoundedJSON("relative.json"));
    await symlink(file, link); await assert.rejects(readBoundedJSON(link));
    await writeFile(file, "not JSON"); await assert.rejects(readBoundedJSON(file));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("direct metric sample validator does not require displaynames/baselines asvalueproof", () => {
  const sample = evidence();
  assert.equal(validateMetricSamples(sample.metrics, "home", binding, configuration).length, 16);
});

test("unknown top/context/invocation/movement fields failwithout echoing names orURLs", () => {
  const secret = "https://secret.invalid/private-player-name";
  for (const mutate of [
    (sample) => { sample.workload.providerURL = secret; },
    (sample) => { sample.workload.contextAfter.userName = secret; },
    (sample) => { sample.workload.workloads[2].fixture = secret; },
    (sample) => { sample.workload.scrollMovement[1].source = secret; },
  ]) {
    const sample = evidence(); mutate(sample);
    const report = summarizeEvidence({ scope: ["home"], binding, evidence: { home: sample } });
    assert.equal(report.selectedScopeQualified, false);
    assert.equal(JSON.stringify(report).includes(secret), false);
  }
});

test("outputprojection cannot retain arbitraryadditional binding/config/metric metadata", () => {
  const secret = "https://secret.invalid/private-player-name";
  const sample = clone(evidence("search"));
  sample.details.testPlanConfigurations[0].privateLabel = secret;
  metricRows(sample)[0].privateLabel = secret;
  sample.details.devices[0].deviceName = secret;
  const report = summarizeEvidence({ scope: ["search"], binding: { ...binding, privateLabel: secret }, evidence: { search: sample } });
  assert.equal(report.selectedScopeQualified, true);
  assert.equal(JSON.stringify(report).includes(secret), false);
  assert.deepEqual(report.results[0].configuration, { configurationId: "1" });
});

function coreEvidence(key = "home") {
  const sample = evidence(key);
  sample.workload.collectorPlan = "app_target_core_v2";
  sample.workload.expectedMetricTags = ["app_cpu", "app_memory", "app_hitch", "wall_clock"];
  sample.metrics[0].testRuns[0].metrics = metricRows(sample).filter((row) => requiredMetrics.some((spec) => spec.identifier === row.identifier));
  return sample;
}

test("explicitV2 requiresall10 coremetrics×3samples andunchangedmovement onprimary journeys", () => {
  const data = Object.fromEntries(primaryScope.map((key) => [key, coreEvidence(key)]));
  const report = summarizeEvidence({ binding, evidence: data });
  assert.equal(report.selectedScopeQualified, true);
  assert.equal(report.primaryAppTargetCoreGateQualified, true);
  assert.equal(report.fullCatalogPerformanceGateQualified, true);
  assert.equal(report.legacyMixedCollectorGateQualified, false);
  assert.equal(report.supplementalScrollSignpostGateQualified, false);
  assert.ok(report.results.every((row) => row.collectorPlan === "app_target_core_v2" && row.scalarMetrics.length === 10));
  assert.equal(report.results[0].scrollMovement.length, 4);
  assert.ok(report.results.every((row) => row.crossBuildComparisonQualified === false));
});

test("unknown/null/blank/explicitlegacy plans arenot inferred ascoreV2", () => {
  for (const plan of [null, "", "future", "legacy_mixed_v1"]) {
    const sample = coreEvidence(); sample.workload.collectorPlan = plan;
    assert.throws(() => validateSurfaceEvidence(sample));
  }
});

test("V2 cannotborrowextra16metrics orsilentlydropwrongtags", () => {
  const extra = coreEvidence(); extra.metrics = evidence().metrics;
  assert.throws(() => validateSurfaceEvidence(extra));
  const wrongTags = coreEvidence(); wrongTags.workload.expectedMetricTags.push("scroll_signpost");
  assert.throws(() => validateSurfaceEvidence(wrongTags));
});

test("V2 incompletecore arrays orstationaryworkload stillfail", () => {
  const missing = coreEvidence(); metricRows(missing)[0].measurements = [1];
  assert.throws(() => validateSurfaceEvidence(missing));
  const stationary = coreEvidence(); stationary.workload.scrollMovement[2].translationPoints = 0;
  assert.throws(() => validateSurfaceEvidence(stationary));
});

test("legacy131/132 planretains strict16rows; removing6withoutanexplicitplan fails", () => {
  assert.equal(validateSurfaceEvidence(evidence()).scalarMetrics.length, 16);
  const missing = coreEvidence(); delete missing.workload.collectorPlan;
  missing.workload.expectedMetricTags.push("scroll_signpost");
  assert.throws(() => validateSurfaceEvidence(missing));
});

test("supplemental6-row signpostset requiresownexacttests andexplicitplan; neverprimarypass", () => {
  const report = summarizeEvidence({ scope: ["home-signpost", "matchday-signpost"], binding,
    evidence: { "home-signpost": evidence("home-signpost"), "matchday-signpost": evidence("matchday-signpost") } });
  assert.equal(report.selectedScopeQualified, true);
  assert.equal(report.supplementalScrollSignpostGateQualified, true);
  assert.equal(report.primaryAppTargetCoreGateQualified, false);
  assert.equal(report.fullCatalogPerformanceGateQualified, false);
  assert.ok(report.results.every((row) => row.scalarMetrics.length === 6 && row.supplemental === true));
  const missingPlan = evidence("home-signpost"); delete missingPlan.workload.collectorPlan;
  assert.throws(() => validateSurfaceEvidence(missingPlan));
  const wrong = evidence("home-signpost"); wrong.workload.collectorPlan = "app_target_core_v2";
  assert.throws(() => validateSurfaceEvidence(wrong));
  const primary = coreEvidence(); primary.workload.collectorPlan = "scroll_signpost_only_v1";
  assert.throws(() => validateSurfaceEvidence(primary));
});

test("missing supplementarysignpost samples orcore10 values cannotfill6-rowcollector", () => {
  const sample = evidence("home-signpost"); metricRows(sample)[2].measurements = [];
  assert.throws(() => validateSurfaceEvidence(sample));
  const extra = evidence("home-signpost"); extra.metrics[0].testRuns[0].metrics.push(...metricRows(coreEvidence()));
  assert.throws(() => validateSurfaceEvidence(extra));
});

test("differentlegacy/core plans cannotqualify acommonprimary baseline", () => {
  const report = summarizeEvidence({ binding, evidence: { home: coreEvidence("home"), matchday: evidence("matchday"), search: coreEvidence("search") } });
  assert.equal(report.selectedScopeQualified, false);
  assert.equal(report.fullCatalogPerformanceGateQualified, false);
  assert.match(report.scopeIssue, /different collector plans/);
});
