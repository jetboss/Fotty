# Independent review — Fotty184 native preparation recovery

Date: 28 October 2026 Tobago / 29 October 2026 UTC. Read-only review of the final single-stream preparation patch before the Release 184 device gate.

## Result and boundary

No confirmed defect was found in the reviewed deferred native-preparation path. The review covered `SingleNativePreparation`, `deferSingleNativePreparationForBackgroundIfNeeded`, `resumeDeferredSingleNativePreparationIfNeeded`, their lifecycle integration and seven controlled regressions. It did not change app code, run a build, access a device or fetch network/media data. Source/test review does not establish decoded playback, fullscreen or PiP runtime acceptance.

## Confirmed ownership and lifecycle fences

- A native single-stream preparation records its source and request owner before creating its asynchronous task. Both a background transition during preparation and a load that begins while already backgrounded use the same defer helper.
- Deferral cancels the old task, removes the retired player item, cancels audio preparation and stops its watchdog. Foreground re-entry prepares the current owned source rather than resuming the retired item.
- Descriptor and validator completions recheck cancellation, request and source ownership. A late cancelled lookup cannot replace a newer source or attempt.
- Pause retains the deferred preparation without issuing Play. Only explicit Play can reopen a deliberately paused preparation. Cancellation, cleanup, source replacement and request replacement revoke the deferred lease.
- A refreshed descriptor must retain the selected session identity and a binding matching the current request. An actually expired delivery lease is rejected before URL validation when renewal supplies no usable replacement; metadata freshness is not treated as a signed delivery expiry.
- Reopening a cancelled descriptor negotiation does not reset `nativeStartupRetryAttemptsBySource`. The foreground lifecycle does not replenish transport retry budgets.
- The added preparation behavior is gated by `usesSingleStreamRanking` and the `.single` playback context. No fixture date, squad, stream admission or security rule changed. No multi-stream policy change was found in this patch; multi-stream runtime behavior was not requalified by this review.

## Seven controlled regressions reviewed

1. `testBackgroundedDescriptorPreparationRestartsItsOwnerInsteadOfResumingRetiredItem`
2. `testNativeLoadAlreadyBackgroundedDefersLookupAndRetiredItemUntilForeground`
3. `testDeferredPreparationCannotReplayAnExpiredLeaseWhenFreshLookupReturnsNil`
4. `testForegroundPreparationCannotBeOverwrittenByLateCancelledBackgroundLookup`
5. `testPauseKeepsDeferredNativePreparationPausedUntilExplicitPlay`
6. `testCancellationOrRetirementRevokesDeferredPreparationBeforeLateCompletionAndForeground`
7. `testSourceReplacementRevokesDeferredDescriptorAndCannotAdoptItsLateResult`

The source-replacement fixture uses the admitted synthetic CS4 source. Controlled validators reject before media/audio, and continuations expose delayed completion rather than relying on live providers or timing sleeps.

## Retained aggregate verification

The root agent supplied the existing redacted aggregate receipts; this reviewer copied only these summaries, without inspecting full result bundles or private logs:

- `native-recovery-summary.json`: 75 tests, 75 passed, 0 failed, 0 skipped.
- `cs-date-summary.json`: 117 tests, 117 passed, 0 failed, 0 skipped. This separate run covers CS date-regression proof and does not repair the upstream publication.

Counts are separate runs, not a unique combined total.

## Reviewed source hashes

- `Fotty/Features/Player/LivePlayerViewModel.swift`: `a3f93bd688d3ddd66aa23c2acfeedb4c4f10fc46ddab1f7e67f1a6421b126ede`
- `FottyTests/NativePlaybackPreparationTests.swift`: `1996d4867edd4b408bb93de02c57fdc84500cd5cd13e2907ead9f85fcbf03f0e`
