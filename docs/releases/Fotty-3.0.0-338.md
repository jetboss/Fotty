# Fotty 3.0.0 (338) — internal TestFlight

Released 15 November 2026, about 17:59 Tobago. Upload succeeded. Apple reports
the build VALID with the What to Test note set, and the upload tool added it to
the existing Fotty Internal Smoke group, which notifies its testers. This shows
the build is available, not that testers received or installed it.

## What to Test

Fixed sound sometimes staying off after a stream failed or you switched matches.
New Sports TV guide for planning what to watch.
Fixed a freeze when starting some games, plus stream reliability improvements.

## Contents since 332

- Codex 333–337: Sports TV guide, Watch health-store deadlock and incomplete
  discovery fixes, UI polish, and Highfly participant corroboration with
  query-safe renewal. Each change has its receipt under `docs/testing/`.
- Claude `a612da1`: a lost WebKit media-suspension ACK no longer leaves the
  single Watch, and every later Watch, muted. A closed page counts as retirement.
  The owner confirmed audio on Jet338.

## Qualification

- Full unmodified `tools/ios-ci.sh` on the release source passed. Checks:
  - native source membership and versions 3.0.0 (338)
  - competition catalog and provider football identity
  - pinned visual regression (Xcode 27B52) and all FottyTests
  - generic unsigned Release build
- On the identical app source, full FottyTests: 2,759 executed, 12 opt-in
  skips, 0 failures.
- Signed normal Release338 installed on Jet (read back 3.0.0/338). The owner
  watched a live match with audio.

## Release tooling changes needed for this build

- `c3ff3fb`: the membership gate now honours literal `.swift` exclusions in
  `project.yml`. The FPL retirement excluded 45 files, so the gate had failed
  since `babb924`, including on the 332 source.
- `8e7c9c8` (owner-approved narrowing): the receipt secret scan also accepts
  test-receipt digests proven against a committed version of the named Swift
  file, and `fotty.*.vN` settings names the app itself uses. Unproven digests
  and every other finding still block. 24 snapshot tests pass, including real
  gitleaks with a planted credential.

## Source and packaging

- Pre-archive source receipt `backups/release-source/3.0.0-338`: 2,072 files,
  restore-verified. A comparison immediately before upload passed. Values are
  in `Fotty-3.0.0-338.json`. Release checkout `99ee2a8`.
- The archive was built without local API keys. Package checks:
  - app and extension both 3.0.0/338
  - strict signature verified, no XCTest bundles, 2 dSYMs
  - background audio and AppIcon present
  - encryption flag false, all three embedded API-key fields empty
- Archive, DerivedData and export output were removed afterwards. No Git push,
  deployment, new tester or group change.
