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
3. **Cold relaunch** and non-Flix lease expiry are not covered by the tests above.
4. **Physical checks** (pause/resume, audible audio, PiP, iPhone player) remain device gates, not
   unit tests.
