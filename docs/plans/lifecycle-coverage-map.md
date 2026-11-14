# Viewing-session lifecycle coverage map (Claude task 1)

14 Nov 2026. Claude task 1 ("lifecycle regression coverage") was planned on the assumption that these
scenarios lacked tests. A review of the baseline (d1347dd) shows they are already covered, so no
duplicate tests were added. Gaps found during the review are listed at the end.

| Scenario | Existing tests |
|---|---|
| Pause during descriptor renewal | `NativePlaybackPreparationTests` `testPausedOrCancelledSingleDescriptorRefreshCannotAdoptOrValidateLateResult`, `testExplicitPlayAfterPausedDescriptorResultWasDiscardedReopensOnlyItsLookup`, `testExplicitPlayWhilePausedDescriptorLookupStillWaitsReusesTheSameAttempt` |
| Cancelled discovery | `ViewingSessionCoordinatorTests` `testStoppedSingleDiscoveryCannotPublishLateChoicesOrRevivePlayer`, `testIncrementalOptionalWatchCancellationAndChangedAdmissionCannotMountLateSources`; `LivePlayerRetryLifecycleTests` `testPendingSingleDiscoveryCannotOverridePauseCancelManualSelectionBackgroundOrRetirement` |
| Replaced attempts | `ViewingSessionCoordinatorTests` `testLatestReplacementWinsAndRechecksPresentationAtCommit`; `LivePlayerRetryLifecycleTests` `testManualReloadOfSameSourceInvalidatesEarlierRetry`, `testSourceSelectionInvalidatesPendingRetry` |
| Late recovery callbacks | `LivePlayerRetryLifecycleTests` `testStaleRecoveryCannotCancelTheCurrentAttemptRetry`, `testExplicitPauseCancelsRetryAndLateStartedMessageCannotResumeIt`, `testBackgroundingCancelsRetryAndIgnoresLateProgress` |
| Token / lease expiry (Flix examples; not every provider) | `LivePlayerRetryLifecycleTests` `testExpiredSingleFlixLeaseRenewsExactQueryTokenBeforeValidatingAnyMedia`, `testUnavailableOrWrongRowFlixRenewalNeverValidatesExpiredLeaseAndKeepsTypedPrivateFailure`, `testCancelledSingleFlixRenewalCannotAdoptOrValidateItsLateFreshResult` |
| Retained player reopen (in-process; not a cold relaunch) | `ViewingSessionCoordinatorTests` `testRetainedSingleReopenPreservesPausedTransportWithoutResolverOrReplacement`, `testRetainedSingleReopenRejectsChangedOrConflictingCurrentIdentityAndTerminalStatus`, `testRetainedSingleReopenRejectsFailedAndRetiredModels` |
| Background / foreground | `LivePlayerRetryLifecycleTests` `testBackgroundPiPFatalItemRecordsImmediatelyAndRecoversOnceOnForeground`, `testBackgroundNativeFailureNeverOverridesPauseBeforeOrAfterTheObservation` |
| Network loss while paused | `LivePlayerRetryLifecycleTests` `testNativeExplicitPauseSurvivesDelayedNetworkLossAndRestoration` |

## Gaps found

1. **Viewer feedback conflated "wrong match" and "blocked picture"** — fixed on `claude/viewer-feedback`
   (task 2, first half): separate actions; blocked picture records an ordinary failure, never
   wrong-programme, exhausts that delivery and fails over directly (no transport retry, offline wait
   or Web fallback of the same source). Reports are refused while paused and for stale attempts.
2. **Half-time transport** (a stream pausing or changing at the interval) can be tested now;
   **programme-correctness boundaries and expiry** need Codex 1's evidence types first.
3. **Cold relaunch** and non-Flix lease expiry are not covered by the tests above. *Superseded
   (stage 3 review, 14 Nov):* both are covered, see the stage 3 table below.
4. **Physical checks** (pause/resume, audible audio, PiP, iPhone player) remain device gates, not
   unit tests.

## Stage 3 review (14 Nov 2026, worktree at c76a93d)

Checked against committed code. These were already covered; no tests were added for them:

| Scenario | Existing tests |
|---|---|
| CS renewal / native window renewal | `NativePlaybackPreparationTests` `testCSMatchRenewalAllowsItsMetadataWindowWithinOneNativeDeadline`, `testVerifiedFrozenNativeWindowRenewsDescriptorOnceOnTheSamePlayer`, `testKnownExpiredBoundDeliveryCannotReplayAfterDescriptorRefreshReturnsNil` |
| Reviewed TV renewal | `NativePlaybackPreparationTests` `testReviewedTVAdvancingWindowRenewsTheSelectedStationOnlyOnceWithoutManualRetry` |
| Cold relaunch identity | `LastLiveMatchStoreTests` `testDecodedConfirmationPersistsOneIdentityAndSurvivesColdLaunch`, `testFreshCurrentResultRetainsOnlyItsOwnDeliveryNotStoredSource`, `testFootballFinishedCancelledPostponedSuspendedAndUnavailableScoreCannotReturn` |
| Attempt evidence never restored; evidence expiry | `StreamEvidenceTests` `testRelaunchNeverRestoresAttemptEvidenceEvenWhenGivenSameAttemptUUID`, `testStoredAndCurrentBoundariesAreExclusiveAndEarlierAuthorityCapsEvidence`, `testMetadataTTLAndMaximumRetentionAreExclusive` |

Prepared programme evidence is bound to one attempt and source and ends with every new attempt;
Highfly and PenguPlay always take the relay path that captures it.

**Gap found and repaired:** Wrong match reported while paused (the Sources sheet offers it) recorded
the rejection, but recovery correctly waited for the viewer's Play, and that Play then resumed the
rejected item or page. Explicit Play after Pause on a single-match delivery with wrong-programme
evidence now starts a new attempt, so the existing skip in `loadCurrentSource` fails over or ends
with "No matching broadcast"; that terminal outcome now holds the delivery as a blocked picture is
held (Web page unmounted, late callbacks start nothing). Regressions: `LivePlayerRetryLifecycleTests`
`testPausedWrongMatchKeepsPauseAndExplicitPlayNeverResumesTheRejectedDelivery` (native and Web,
one and two sources; failed on baseline in all four cases) and
`testConnectingToggleWithWrongProgrammeEvidenceKeepsItsExistingSemantics` (negative guard).
**Verified locally (Catalyst):** focused run 261 passed, 0 skipped, 0 failed; full suite 2,785
total, 2,773 passed, 12 opt-in/physical skips, 0 failed. Details in
`docs/testing/fotty-lifecycle-roadmap-20261114/README.md`. **Jet 328:** normal Watch on Haiti–United States, native correct picture, paused Sources and
same-attempt resume checked. The exact rejected-picture report → Play branch remains covered by
regression tests only; no false report was left on a correct owner delivery.

**Unresolved, no change made:** a `NativePlayerAudioIsolationTests` run crashed once under full-suite
load (EXC_BAD_ACCESS in CoreFoundation/MediaToolbox during XCTest teardown, no test identified).
Cause unknown. The 7 unchanged `NativePlayerAudioIsolationTests` passed in the stage 3 focused
run; that does not explain or fix the earlier crash.
