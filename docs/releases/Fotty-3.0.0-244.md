# Fotty 3.0.0 (244) — internal TestFlight

Build 244 replaces the football fixture verification warning on Home and Matchday with a progress indicator scoped to an active check. It includes the two reviewed Sports TV channels from private 243. The approved Everton and Champions League live checks are separate from release qualification.

The release gate exposed an upcoming-row layout regression at compact widths. The countdown/reminder row now uses a narrower information threshold while retaining accessibility stacking. Home's busy guard runs before a new tap can cancel a pending lookup. Updated test inputs include TV25/26, a current match and opted-in source candidates for recovery, and a completed native preparation for the paused-owner test. The visual references for the 3.0 Home were reviewed; the prior references are preserved under VisualBaselines-206. The source-backup scanner verified a previously unrecognized documentation checksum against the actual source file. Its 17 tests passed.

Final Catalyst runs: 2,652 passed, 12 skipped, zero failures. Generic unsigned iOS Release passed. Signed archive verification covers the app and the embedded extension versions and dSYMs, the signature, absence of XCTest bundles, and the new/removed fixture strings in the shipped executable. A restore-verified pre-archive snapshot and immediate pre-upload comparison use backups/release-source/3.0.0-244-final. No physical test of 244 was performed as part of distribution.

Xcode reported upload success at 06:46:34 Tobago on 5 November. Export used the existing internal-only profile. Apple processing and group availability are verified separately.

Apple subsequently reported build d4cdfe0e-c873-4a26-a7c3-e19b997d20ba VALID. At the first availability check, internal state was MISSING_EXPORT_COMPLIANCE, notes empty and no beta group assigned. The metrics API key returned 403 for the compliance write. The App Store Connect sign-in page is open for owner authentication. Temporary archives, builds and captures were cleaned up after upload.

Completed after owner sign-in. App Store Connect confirms VALID, usesNonExemptEncryption false, internal state IN_BETA_TESTING, existing group Fotty Internal Smoke, and notes exactly “Bug fixes”. Screenshot: Fotty-3.0.0-244-testflight.jpg.
