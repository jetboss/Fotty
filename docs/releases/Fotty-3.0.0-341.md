# Fotty 3.0.0 (341) — internal TestFlight

Released 21 November 2026, about 09:40 Tobago. Upload succeeded. Apple reports
the build VALID with the What to Test note set, and the upload tool added it to
the existing Fotty Internal Smoke group, which notifies its testers. This shows
the build is available, not that testers received or installed it.

## What to Test

Fixed a match you're watching sometimes showing "Start unconfirmed".
When Watch can't find a stream you now get Try again and Match details instead of a pop-up.
Sources show whether each one played for this match. Search is on Matchday too.
Match alerts open a score page with Find in Fotty.

## Contents since 338

- `5050b55`: a playing match no longer shows "Start unconfirmed" from a
  pre-kickoff score status (owner saw it on Man City vs Fulham); schedules keep
  refreshing on any tab while a match plays.
- `f5b1dbe`: the notification match page has no Watch of its own; "Find in
  Fotty" hands the team to Search and the shared Watch.
- `b028f61`: Search button on Matchday.
- `46cef23`: source rows say how each source did for this match.
- `602847c`: removed Home/Matchday's unused second lookup.
- `fe8e04c`: a failed Watch shows an inline panel instead of an alert.
- Earlier baseline commits since 338: FPL source cleanup, privacy manifests,
  broadcast-registry cache file, Watch Two deletion (see Decisions-Log).
- `27d4717`: build number 341.

## Qualification

- Full unmodified `tools/ios-ci.sh` on the release source `27d4717` passed:
  native versions 3.0.0 (341), pinned visual regression and all FottyTests
  (2,653 executed, 2,641 passed, 12 opt-in skips, 0 failures), generic unsigned
  Release build.
- Physical: Jet builds 339/340 (same app source before the status fix and the
  build bump) showed Matchday Search, source status lines, Watch fallback
  CS1→Willow and Fox Cricket playback. The failure panel, the match page's
  Find in Fotty and the status fix were not observed on a device.

## Source and packaging

- Pre-archive source receipt `backups/release-source/3.0.0-341`: 2,025 files,
  verified; the comparison immediately before upload passed. Values are in
  `Fotty-3.0.0-341.json`. Release checkout `27d4717`.
- Archive built without local API keys. Package checks: app and extension both
  3.0.0/341, strict signature verified, no XCTest bundles, 2 dSYMs, background
  audio and AppIcon present, 2 privacy manifests, encryption flag false, all
  three embedded API-key fields empty.
- Archive, DerivedData and export output were removed afterwards. No new
  tester or group change.
