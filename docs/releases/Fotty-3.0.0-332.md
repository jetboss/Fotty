# Fotty 3.0.0 (332) — internal TestFlight

Released 14 November 2026, 23:13 Tobago. Apple confirms VALID and IN_BETA_TESTING, encryption declaration false, only the existing Fotty Internal Smoke group assigned (13 existing testers), and automatic tester notification enabled. This proves availability, not inbox arrival or installation.

## What to Test

Removed the FPL tools to focus on watching sports.
Temporarily removed Watch Two while we focus on single-stream viewing.
Bug fixes and stability improvements.

## Qualification

Claude approved the retirement change. Full Catalyst: 2,687 passed, 12 known opt-in/physical skips, zero failures. Signed normal Jet332 played the correct live WBBL match via CNC/LS1 for 91 seconds with zero recorded stalls. Pause/Sources/resume, navigation, legacy FPL routing and saved-data preservation passed. Exact limits are in [the physical receipt](../testing/fotty332-watch-first-retirement/README.md): no audible-audio, all-provider, PL/UCL or new failover claim. Ranking and the phone remain untouched.

The distribution archive uses the same native source inventory as the tested app. App and extension both report 3.0.0/332; strict signatures, dSYMs, no XCTest bundles, background audio, icons and empty embedded API-key fields were verified. Internal-only upload uses the existing Xcode account. Apple accepted the upload at 23:10:40 Tobago.

## Source and packaging

Pre-archive source receipt: `backups/release-source/3.0.0-332`, 1,986 files, restore-verified, followed by an immediate successful pre-upload comparison. Snapshot and Apple evidence are in `Fotty-3.0.0-332.json`. Native qualification commit `9ed8744`; release checkout `0174472` adds only documentation and a release-tool checksum proof update. Eighteen release snapshot tests passed. The scanner still rejects unproven digests; the two new named validation receipts contain hashes verified against the actual copied source.

One packaging attempt validated but closed before upload and cleaned its archive. The corrected runner rebuilt the unchanged app and performed the only upload. Owned archives, DerivedData, export output and keep-awake process were cleaned. No Git push, cloud deployment, device reinstall, new tester or group change.
