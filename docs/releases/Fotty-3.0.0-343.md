# Fotty 3.0.0 (343) — internal TestFlight

Released 21 November 2026, about 13:35 Tobago. Upload succeeded; Apple reports
the build VALID with the What to Test note set, and the upload tool added it to
Fotty Internal Smoke, which notifies its testers.

## What to Test

Live matches no longer show "Start unconfirmed" next to a running score.
When a stream drops, Fotty gives Highfly time to reconnect.
Live scores keep updating while you watch from any tab.

## Contents since 342

- `d2abee2`: live or paused score evidence overrides "Start unconfirmed".
  Jet (341) showed "1–3 · 69' · Official FPL · Start unconfirmed" while the
  Worker held correct Premier League rows during a correction window.
- `20e0f14` (Worker, deployed separately): coverage names held and
  conflicted public fixture IDs, and terminal-rollback names its fixture. The
  Premier League hold cleared itself at the 16:34 UTC sync (covered, five
  matches live and verified).
- `616383f`: build number 343.

## Qualification

- Release source `616383f`. First full `tools/ios-ci.sh` run: one failure in
  `MediaAudioSessionOwnerTests.testColdSingleForegroundReentersFirstDisplay…`
  (timing-sensitive; passed in every earlier run). Unchanged re-run passed:
  2,659 executed, 2,647 passed, 12 opt-in skips, 0 failures; visual regression
  passed. Treat that test as flaky until stabilised.
- Worker: 663 web unit tests on the baseline lineage, 659 on the deployed one.
- Not observed on a device.

## Source and packaging

- Pre-archive receipt `backups/release-source/3.0.0-343`: 2,028 files,
  verified; comparison before upload passed.
- Key-free archive; app and extension 3.0.0/343, strict signature verified,
  no XCTest bundles, 2 dSYMs, background audio, AppIcon, 2 privacy manifests,
  encryption flag false, API-key fields empty. Executable SHA-256
  cf2a5bd3b11b06fc05bbe40e4b951b8eb664d5625d6a8693b19b8d69cd75e8e8.
- Archive, DerivedData and export output removed.
