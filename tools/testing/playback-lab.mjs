#!/usr/bin/env node
// Read-only selection of real XCTest scenarios. This never builds, launches,
// installs or contacts a provider; the owner runs the selected physical gate.
import { constants, open } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const playbackLab = [
  { id: "slow-start", evidence: "transport-integration", tests: [
    "LocalStreamProxyTests/testPlaybackLabHeldManifestCompletesRealValidationWithoutInventingStartupFailure",
    "LivePlayerRetryLifecycleTests/testLateStartupProgressCancelsPendingStartupRetry",
    "NativePlaybackEvidenceTests/testNativeStartupPreservesBufferingBeyondTheFormerThreeSecondCutoff",
    "NativePlaybackEvidenceTests/testNativeStartupRepeatedWaitingCannotRenewTheSharedDeadline"
  ] },
  { id: "http-expiry-and-recovery", evidence: "transport-integration", tests: [
    "LocalStreamProxyTests/testPlaybackLabActualRelayHTTPFailuresRemainTypedAtNativeValidationBoundary",
    "LocalStreamProxyTests/testPlaybackLabValidManifestDoesNotProveSegmentPlaybackAndSameCapabilityCanRecover",
    "LocalStreamProxyTests/testPlaybackLabRangedSegmentPreservesResponseAndDoesNotInheritManifestCredentials",
    "LocalStreamProxyTests/testConcurrentRelayFailureAndOtherResourceCompletionStaySeparateObservations"
  ] },
  { id: "redirect-scope", evidence: "transport-integration", tests: [
    "LocalStreamProxyTests/testRealRedirectDelegateRebuildsCredentialsAndEnforcesHopBudget",
    "LocalStreamProxyTests/testRealRedirectDelegateRevalidatesDNSAndCancellationBeforeFollowing"
  ] },
  { id: "stale-work-and-source-switch", evidence: "state-ownership", tests: [
    "LivePlayerRetryLifecycleTests/testPlaybackLabSourceRoundTripRejectsOldFailureEvenWhenSelectedSourceIDMatchesAgain",
    "LivePlayerRetryLifecycleTests/testSourceSelectionInvalidatesPendingRetry",
    "LocalStreamProxyTests/testPlaybackLabCancelledValidationAndStoppedRelayCannotReviveHeldRequest",
    "LocalStreamProxyTests/testRelayRequestEvidenceIsBoundedOpaqueAndDoesNotWriteTheQualityStorePerRequest",
    "LocalStreamProxyTests/testRelayResourceIdentityIsPerRelayAndNeverTheCapability",
    "LocalStreamProxyTests/testRelaySnapshotInvalidMonotonicSamplesStayUnknownAndSummaryRemainsBounded"
  ] },
  { id: "buffering-and-pause", evidence: "state-ownership", tests: [
    "LivePlayerRetryLifecycleTests/testDecodedRecoveryKeepsSameAttemptWithoutReloading",
    "LivePlayerRetryLifecycleTests/testExplicitPauseCancelsRetryAndLateStartedMessageCannotResumeIt",
    "LivePlayerRetryLifecycleTests/testRepeatedBridgeFailureDoesNotExhaustThePendingRetry"
  ] },
  { id: "native-fullscreen", evidence: "state-ownership", tests: [
    "NativeFullscreenPlaybackTests/testRepeatedExitAndReentryPreservePlayerItemAttemptSourceAndPausedIntent",
    "NativeFullscreenPlaybackTests/testSuccessfulRetainedRestorationRebindsControlsWithoutChangingPausedTransport"
  ] },
  { id: "picture-in-picture", evidence: "state-ownership", tests: [
    "NativeFullscreenPlaybackTests/testRetainedPiPPauseSurvivesBackgroundStopAndForegroundWithoutNewPlay",
    "NativeFullscreenPlaybackTests/testRetainedPiPPlayPreservesTransportAndRejectsStaleLeaseWithoutDuplicatePlay",
    "PlaybackPolicyTests/testWebPictureInPictureWinsBackgroundSuspensionRace"
  ] },
  { id: "watch-two", evidence: "state-ownership", tests: [
    "ViewingSessionCoordinatorTests/testAtomicWebAudioChangeRetiresBothBeforeAnyNativeStartAndPreservesLogicalLayout",
    "ViewingSessionCoordinatorTests/testFailedOrCancelledActualWebRetirementCannotAdoptOrStartEitherNativePane",
    "NativeWatchTwoTransitionTests/testDeliberatelyPausedPaneRemainsPausedThroughoutNativeCommitAndStart"
  ] }
];

export const physicalGates = [
  "First decoded frame and a continuous displayed clock on an authorized stream",
  "Native fullscreen entry, pause/play and inline return retain the same player/item/attempt",
  "PiP continues outside Fotty for at least 60 seconds, then restores without duplicate audio",
  "Watch Two has two advancing pictures, usable independent sources and verified selected audio",
  "A real compatible Web/Web to native/native conversion is separately qualified; safe refusal is not a pass"
];

export function selectionFor(scenarios = playbackLab) {
  if (!Array.isArray(scenarios) || scenarios.length < 1 || scenarios.length > 32) throw new Error("Invalid lab scenarios");
  const ids = new Set(), selectors = new Set();
  for (const scenario of scenarios) {
    if (!/^[a-z][a-z0-9-]{0,63}$/.test(scenario.id) || ids.has(scenario.id)) throw new Error("Invalid or duplicate scenario");
    if (!["transport-integration", "state-ownership"].includes(scenario.evidence)) throw new Error("Unreviewed evidence claim");
    if (!Array.isArray(scenario.tests) || scenario.tests.length < 1 || scenario.tests.length > 16) throw new Error("Missing or oversized scenario tests");
    ids.add(scenario.id);
    for (const selector of scenario.tests) {
      if (typeof selector !== "string" || !/^[A-Za-z][A-Za-z0-9]{0,127}Tests\/test[A-Za-z0-9]{1,255}$/.test(selector)) throw new Error("Invalid XCTest selector");
      selectors.add(selector);
    }
  }
  return [...selectors].map((selector) => `FottyTests/${selector}`);
}

export async function checkLab(root, scenarios = playbackLab) {
  const selectors = selectionFor(scenarios), sources = new Map();
  for (const selector of selectors) {
    const [, suite, method] = selector.split("/");
    if (!sources.has(suite)) {
      const filename = path.join(root, "FottyTests", `${suite}.swift`);
      // One handle for the check and the read; O_NOFOLLOW refuses a symbolic link.
      const handle = await open(filename, constants.O_RDONLY | constants.O_NOFOLLOW)
        .catch(() => { throw new Error(`Unsafe or oversized test source: ${suite}`); });
      try {
        const info = await handle.stat();
        if (!info.isFile() || info.size > 512 * 1024) throw new Error(`Unsafe or oversized test source: ${suite}`);
        sources.set(suite, await handle.readFile("utf8"));
      } finally {
        await handle.close();
      }
    }
    const source = sources.get(suite);
    if (!new RegExp(`\\bclass\\s+${suite}\\s*:`).test(source)
        || !new RegExp(`\\bfunc\\s+${method}\\s*\\(`).test(source)) {
      throw new Error(`Missing XCTest implementation: ${selector}`);
    }
  }
  return { scenarios: scenarios.length, selectedTests: selectors.length, selectors,
    xctestExecutionVerified: false, decodedPlaybackVerified: false, physicalGates };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const mode = process.argv[2] ?? "--check";
    if (process.argv.length > 3 || !["--check", "--list", "--xcode-arguments"].includes(mode)) throw new Error("Usage: playback-lab.mjs [--check|--list|--xcode-arguments]");
    const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
    const result = await checkLab(root);
    if (mode === "--xcode-arguments") console.log(result.selectors.map((test) => `-only-testing:${test}`).join("\n"));
    else if (mode === "--list") console.log(JSON.stringify({ ...result, coverage: playbackLab }, null, 2));
    else console.log(`Playback lab source selection checked: ${result.scenarios} scenarios / ${result.selectedTests} tests. XCTest and physical playback remain unverified until executed.`);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
