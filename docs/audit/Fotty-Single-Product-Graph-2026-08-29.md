# Fotty single-product-graph correction — 2026-08-29

## Outcome

Fotty now has one iOS product graph. The alternate review-safe implementation,
its compile-time configurations, its launch-time StoreKit distribution unlock,
and its substitute vocabulary are removed. Debug, Release and TestFlight use the
same sports names, catalog path, playback implementation and navigation labels.

Current local source is 2.0.0 (46). It is not installed or uploaded by this work.
TestFlight build 45 remains the distributed build and is not an acceptance
candidate because physical installation exposed the restricted vocabulary.

## Why build 45 regressed when build 44 did not

Build 44 was a normal Debug device build and entered the full app directly.
Build 45 introduced a StoreKit `AppTransaction` migration for Release. Every
Release launch deliberately began in restricted mode while an asynchronous
environment check ran. That state selected hard-coded aliases such as `Field
Events`, `Reference`, `Division A` and `Series C`, disabled normal discovery and
playback paths, and could remain visible when the check failed or when launch
state was not refreshed. This was a distribution-gate defect, not a provider or
catalog labeling change.

## Removed

- `IntegrityService`, `LicenseManager` and the StoreKit environment policy.
- `AppDistributionMode`, runtime review state, distribution overrides and live
  sports capability gates.
- `APP_REVIEW_SAFE` wrappers and `ReviewSafeSubstitutions.swift`.
- `ReviewSafeDebug` / `ReviewSafeRelease`, `Info-ReviewSafe.plist`, and their
  generated Xcode project references.
- Alternate Home, sport, league, empty-state, hero and playback vocabulary.
- Review-safe branches in Home, Matchday/social, reminders, player lifecycle,
  stream validation, search, live activities and MultiView.

The retired P2P provider remains excluded by the existing active-provider
allowlist; removing the review graph does not reactivate it.

## Regression protection

- A unit test requires Football, Basketball, Cricket, Premier League and
  Champions League to retain their real names.
- The Home Catalyst UI test now requires the Home tab and Football sport control
  and rejects the two reported substitute labels.
- The physical-device release gate scans the app, project source and build
  settings for retired review-safe symbols and vocabulary before compiling.
- Release documentation now requires the single production graph.

## Verification and limits

- Final-source `FottyTests` Mac Catalyst suite: pass, no simulator.
- Focused vocabulary regression: pass.
- Final-source generic iOS Release build with signing disabled: pass, no
  simulator.
- App/project retired-symbol scan, shell syntax check and `git diff --check`:
  pass.
- The targeted Home Catalyst UI test compiled, but macOS failed to initialize
  UI automation twice before executing the test (`Timed out while enabling
  automation mode`). This is recorded as unperformed, not a product assertion
  failure and not a UI pass.
- No physical device install, TestFlight upload, provider probe, paid model call,
  server deployment, tester change, external submission or Git publication.

Before build 46 replaces 45 for testers, physically confirm after a cold launch
that the tab says Home, sports and leagues use their real names, Watch is present
for a source-backed live event, and Matchday/FPL remain available.

## Storage

Every Xcode gate used one bounded `/private/tmp/Fotty*46.*` root with an
exit/interruption cleanup trap. All owned roots were removed after pass or
failure. No archive, result bundle, simulator data or duplicate app was retained;
the data volume reports about 52 GiB free after verification.
