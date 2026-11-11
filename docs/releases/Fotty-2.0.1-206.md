# Fotty 2.0.1 (206) — internal TestFlight release

Owner authorized the current update for the existing internal TestFlight group on 31 October 2026. External testing notes must contain exactly **Bug fixes**. No tester/role, phone, FPL or multi-stream changes are authorized by this release.

## Qualification

The final simulator-free gate passed: 2,425 runnable Catalyst tests, nine intentionally skipped physical/live-only checks, and generic unsigned iOS Release compilation. Native membership, version coherence and provider identity checks passed. Snapshot helper tests:17; visual review helper tests:9. These are newly compiled test hosts, not the old installed Mac app.

Older cricket/club-identity test expectations were reconciled to existing accepted behavior. The shared-cache visual fixture is isolated in its own mandatory fresh host process. All ten component captures were individually reviewed for the current Xcode renderer, with unchanged pixel tolerances; original reviewed PNGs were preserved. No shipped Swift source was changed during this release preparation. All237 app/widget/project inputs match the release-start source receipt. Details: `../testing/fotty206-release-2026-10-31/`.

Private Jet206's preceding station-transport acceptance is recorded separately in `../testing/fotty-tv-expansion-2026-10-31/`. Seven ESPN feeds decoded90seconds each; one retry/stall remains recorded. Their shared origin is not independent provider redundancy. Normal live PL/UCL match/programme/fullscreen acceptance remains dependent on the next actual windows; this release does not manufacture those passes or re-enable optional sources. No device was operated during release preparation.

## Immutable source and archive

Final pre-archive snapshot: `backups/release-source/2.0.1-206-testflight-final`,1623 files, one history-free local commit; no remote Git changes.

- Recovery commit `51de10730b05f65b9aec14252f729b72e922ba68`.
- Source SHA256 `0d7cf644712009f13158a57383954d31a24788d2392b20f8cf98d0b3acca49a9`.
- Bundle SHA256 `64ca8e8aab478c6e0063b74234bc9c88aebd74f577d820fdf0fa57000624ac94`.

Both pre-archive and immediate pre-upload source/restore comparisons passed. Signed app and widget versions are2.0.1/206; strict/deep signature and dSYM UUID checks passed. Archive app UUID90BCE74F-F99B-3007-AFE5-CA7572C76879; widget A8610344-13B3-3B81-B9F9-F4E9C4CBE322. App icon/background audio are present; provider API-key fields are empty; no XCTest bundles are included. The development-signed archive contains development entitlements and is re-signed by Xcode's App Store Connect export. Archive fingerprints identify that local archive, not a downloaded Apple-processed executable.

## Upload

The owner completed Apple's updated developer agreement. Xcode's existing automatic signing and internal-only App Store Connect export succeeded at20:00:23Tobago on31October. Upload symbols remained enabled; app/build numbers were preserved. No new group, account, spending or cloud deployment was requested or created.

## Completed internal availability

Apple API and the signed-in page confirm2.0.1(206), build `c3e538c0-cc38-477b-9cb6-3632f6d1666d`, VALID/INTERNAL_ONLY/IN_BETA_TESTING. Only the existing Fotty Internal Smoke group is assigned; the UI shows13testers. The English(U.K.) notes are saved exactly as `Bug fixes`. Existing automatic notification remains true. This confirms availability, not email receipt or installation.

The questionnaire was completed using the actual standard algorithm implementation facts (CryptoKit AES-GCM/HMAC-SHA256 and app-composed RFC8018 PBKDF2) and the owner's previously confirmed outside-France distribution scope. No repeated country question, proprietary algorithm, encryption-source change or global Info.plist declaration was introduced. Apple now reports `usesNonExemptEncryption:false`. This records Apple's accepted questionnaire state, not a new legal guarantee or claim that the app contains no encryption.

Saved proof and redacted API receipt: `../testing/fotty206-release-2026-10-31/testflight206.jpg` and `apple-availability.json`. The release is complete; optional source settings and earlier competition-specific live qualification gates are preserved. No backend deployment, device installation, tester/role change or remote Git publication occurred during this release gate.

## Cleanup

Owned archive, DerivedData, result bundles, candidate captures, Apple distribution logs and temporary helper files were removed. The task-owned keep-awake process ended. Final free disk:14.44GiB. Immutable source receipts and small redacted release evidence remain.
