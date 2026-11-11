# Build 206 release component review — 31 October 2026

This is a release-toolchain/component check, not a new UI redesign or fresh physical-device acceptance. No shipped Swift implementation was changed for this release gate.

The original reviewed set is preserved byte-for-byte at `FottyTests/Fixtures/VisualBaselines-Xcode27A266a/`. Its macOS 27.0 SDK / Xcode 27A266a fingerprint differs from the installed macOS 27.2 SDK / Xcode 27B52. Both runs use host macOS 27.0.1 (26A434), the same synthetic fixture revision, UTC/fixed clock, scale, locale and accessibility settings. The ordinary gate correctly rejected the old renderer fingerprint.

All ten fresh candidates were individually viewed before explicit promotion. The current Home composition includes already-implemented centered sport tiles, full synthetic long-team names and accessibility reflow. Loaded synthetic artwork and honest missing-artwork initials remain distinct. Light/dark variants, primary Watch, secondary controls and source-selection states remain legible, without visible overlap or cropped labels in these captures. No pixel-comparison tolerance was relaxed. Current images and reviewed manifest are under `FottyTests/Fixtures/VisualBaselines/`.

| Capture | Size | Inspection |
| --- | --- | --- |
| home-phone-dark | 375 × 791 | Reviewed |
| home-phone-light | 375 × 791 | Reviewed |
| home-phone-large-text | 375 × 1343 | Reviewed stacked reflow |
| home-ipad-landscape | 1180 × 670 | Reviewed wide composition |
| home-ipad-narrow | 650 × 797 | Reviewed narrow composition |
| sources-phone-dark | 375 × 325 | Reviewed all four source states |
| sources-phone-large-text | 320 × 465 | Reviewed stacked controls |
| controls-dark | 375 × 221 | Reviewed resting/pressed/disabled |
| controls-light | 375 × 221 | Reviewed resting/pressed/disabled |
| badges-loaded-and-missing | 375 × 221 | Reviewed loaded and fallback |

The baseline manifest points to the earlier verified release-source receipt; shipped component inputs did not change during the test reconciliation. The recording run passed the twelve corrected cricket/alias tests and intentionally failed its candidate-recording test. Recording is not visual acceptance or a passing regression run. The full non-recording gate must pass separately before upload.

Two older test oracles were reconciled with existing production behavior: Test-match lifecycle without fresh phase uses neutral “Test in progress”, while the sport aggregate says “1 listed”; club lookup honors reviewed canonical IDs and exact literal aliases. Newer lifecycle tests already required the neutral behavior. No fixture freshness, live authority, matching fence, badge data or application behavior was altered.

The full-suite rerun passed the other 2,424 tests (nine intentional skips), but reproduced immediate NSCache eviction of the synthetic badge and consequent badge-only pixel differences. Focused fresh-process capture retained it. The CI runner now executes the same mandatory visual test in its own fresh host, and explicitly excludes only that already-run class from the remaining full unit invocation. This changes test-process isolation, not application caching or pixel tolerances. Both invocations must succeed before the unsigned Release compile.

Final non-recording gate: the isolated visual test passes, the remaining 2,424 units pass with nine physical/live-only skips, and the generic unsigned iOS Release compile passes. All 237 native app/widget/project inputs still match the original release-start receipt.
