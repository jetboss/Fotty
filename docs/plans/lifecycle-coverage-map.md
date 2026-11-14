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
| Token / lease expiry | `LivePlayerRetryLifecycleTests` `testExpiredSingleFlixLeaseRenewsExactQueryTokenBeforeValidatingAnyMedia`, `testUnavailableOrWrongRowFlixRenewalNeverValidatesExpiredLeaseAndKeepsTypedPrivateFailure`, `testCancelledSingleFlixRenewalCannotAdoptOrValidateItsLateFreshResult` |
| App reopen / retained player | `ViewingSessionCoordinatorTests` `testRetainedSingleReopenPreservesPausedTransportWithoutResolverOrReplacement`, `testRetainedSingleReopenRejectsChangedOrConflictingCurrentIdentityAndTerminalStatus`, `testRetainedSingleReopenRejectsFailedAndRetiredModels` |
| Background / foreground | `LivePlayerRetryLifecycleTests` `testBackgroundPiPFatalItemRecordsImmediatelyAndRecoversOnceOnForeground`, `testBackgroundNativeFailureNeverOverridesPauseBeforeOrAfterTheObservation` |
| Network loss while paused | `LivePlayerRetryLifecycleTests` `testNativeExplicitPauseSurvivesDelayedNetworkLossAndRestoration` |

## Gaps found

1. **Viewer feedback conflated "wrong match" and "blocked picture"** — fixed on `claude/viewer-feedback`
   (task 2, first half): separate actions; blocked picture records an ordinary failure, never
   wrong-programme, and leaves that delivery behind without a same-source retry.
2. **Half-time and in-match programme changes** have no player test: a channel or delivery that
   switches programme mid-match is only caught by the viewer. This needs Codex's correctness
   evidence (task Codex 1) before it can be tested meaningfully.
3. **Physical checks** (pause/resume, audible audio, PiP, iPhone player) remain device gates, not
   unit tests.
