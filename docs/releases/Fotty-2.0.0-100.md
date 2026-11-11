# Fotty 2.0.0 (100) — internal CS playback release

2026-09-14. Status: **Internal / Testing — Fotty Internal Smoke, 11 testers**.

## Scope and authority

Owner approved the existing internal TestFlight group and the Xcode update
needed after Apple's rejection of build 99's old beta toolchain. Version-only
successor to 99, preserving the owner-tested private 98 playback behavior.
No device install, new testers, role changes, public distribution, backend
deployment or Git publication. CS remains opt-in and saved source settings stay
unchanged. Build 93 remains available as fallback in Fotty Internal Smoke.

This batch adds CS alternatives in the ordinary source picker, shared native/web
delivery routing, bounded retries, cancelled-attempt protection, responsive
player/PiP callbacks and private source attribution. It also includes the local
post-93 feedback/reminder work recorded in release 99. The iPad acceptance was
CS2 playback, controls, switching back to StreamEx and PiP on private 98; it is
not proof of every CS variant, iPhone behavior or a long background soak.

## Toolchain and verification plan

Official Xcode 27 (27A266a), strict deep signature verification and Gatekeeper
Apple System assessment passed. Owner completed required-component setup;
`-checkFirstLaunchStatus` now passes and generic iOS/Catalyst destinations are
available without the earlier component warning. Pin DEVELOPER_DIR explicitly
to `/Applications/Xcode.app/Contents/Developer` for every release command.
No simulator runtime was selected or simulator booted. Remove the completed
1.9 GiB Xcode_27.xip installer; preserve both older Xcodes and unrelated beta XIP.
Disk reads 66 GiB free before the release gate.

Capture a fresh immutable pre-build source receipt, restore it outside Documents
to avoid expanding test-host file permissions, and run the full simulator-free
CI gate. Reuse one temporary root sequentially for tests, generic iOS Release
and signed archive. Verify identities, versions, SDK, signatures, dSYMs, icons,
manifest bytes, empty provider keys and background audio. Compare restored and
working sources before export. Use internal-only export with unchanged build
number; separately verify Apple processing, notes and existing-group access.
Remove owned temporary output on completion or failure.

## What to Test

Optional CS sources add more broadcast choices alongside your existing sources.
Enable them in Settings > Broadcast Sources > CS sources. Open a live match,
open Sources and try a CS option when available. CS availability varies by match.

Please check:
- Picture and audio start, and pause/resume remain responsive.
- Sources opens and switches between CS and an existing broadcast without freezing.
- Picture in Picture continues when you open another app; also try lock/unlock.
- Try another CS option, closing/reopening playback, and switching while loading.
- Check on iPhone and iPad. Report the build, sport/match, CS label and what failed;
  do not include private stream URLs or credentials.

Existing interests and source settings should remain unchanged after updating.

## Remaining acceptance

Exact TestFlight installation, retained data and playback on both form factors,
other CS variants, native/web coverage and timed background/recovery tests remain
open until exercised. This release does not complete the separate seven-day
private qualification. Automated metadata availability is not decoded playback.

## Qualification and upload evidence

- Official Xcode 27 (27A266a), explicitly pinned for all commands. Full Catalyst
  result: **581 passed, zero failures, two intentional skips** out of 583 tests.
  Skips are the opt-in reference-HLS soak and live Score808 discovery. The
  recorded synchronous audio-session main-thread warning remains unresolved;
  passing units are not an audio-performance guarantee.
- Generic unsigned iOS Release and signed optimized archive pass. No simulator,
  old installed Mac app, physical-device installation or paid Coach call used.
- Live identity audit: five vectors pass and two reachable feeds pass at
  19:01 UTC. A third feed hit its existing eight-second timeout; no false
  all-provider availability claim. Backend health returns HTTP 200, ok true,
  sourceVersion `2026-09-06.fixture-freshness-1`, matching local source. No backend
  deployment. Compared with receipt 99, only version/project and documentation
  files changed, not runtime sources or manifests.
- App/extension identifiers, versions 2.0.0 (100), minimum iOS 26.4, arm64 only,
  SDK iphoneos27.0 and DTXcodeBuild 27A266a verified. Strict nested signatures,
  team 9W3JDBQU39 and both dSYMs match. No bundled tests/test frameworks. The
  archive's development signature is re-signed by automatic distribution export.
- AppIcon entries for phone/iPad and Assets.car exist. All three provider
  manifests match the frozen source byte-for-byte. Background audio remains set;
  all three provider API-key values are empty in the binary's Info.plist.
- Both restored build source and original working tree match the immutable
  receipt immediately before export. Internal-only export preserves build 100
  and uploads symbols. Xcode reports **Upload succeeded / EXPORT SUCCEEDED** at
  15:12:23 AST (19:12:23 UTC). Fresh Apple UI shows build 100 Processing, not yet
  internal tester availability. Build 93 remains Testing in the existing group.

## Receipt and cleanup

Retain `backups/release-source/2.0.0-100/` intentionally for recovery: 658 files,
one history-free commit, no GitHub publication. The pre-build receipt is immutable;
post-upload result notes do not retroactively enter the archived source snapshot.

- Source commit: `1f1ee48f7daf8c0bf15db4f136eb7e8851fe0b87`.
- Source SHA-256: `9a3d10196928679bf6e486d95f2961564b0702b870a731b0de9bf3f30903b19f`.
- Bundle SHA-256: `0a8c953ab391df38dea4878261e4b1304101d3f8039cbb6cec2e97f74f447764`.
- Archived app executable: `d8f3d4ddbf28f476aa945c1f99d47597f1101241e13da94b2864d469057a1651`.
- Archived extension executable: `0829cee92da5b4916251929933a3e9bb22a5edb1d2aeab630c5ac97e031d916a`.
- App/dSYM UUID: `73CD1749-42BA-3204-8D9F-EDD11FE24A9E`.
- Extension/dSYM UUID: `2DD8C8D1-1446-36D7-BB36-5F98F5CF7C99`.

Remove the single 1.1 GiB temporary root (DerivedData, results, restored source,
archive and logs) and the exact separate 640 KiB distribution log after successful
upload. Remove the finished 1.9 GiB Xcode installer after verified setup. No test
app process remains. Disk reads **65 GiB free** after cleanup; no broad cache,
older toolchain or unrelated installer deletion. Global xcode-select still points
to the older beta: release commands explicitly use the new Xcode path, and future
gates must also pin it rather than silently falling back to that default.

## Distribution confirmed

Apple completed processing. Save the declaration for encryption supplied by
Apple's OS/CryptoKit, based on the current implementation and
[Apple's documentation](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
This is not a claim that backups are unencrypted. No new agreement was accepted.
Save the English (U.K.) What to Test text above, then assign only the existing
Fotty Internal Smoke group. The detail page confirms Saved and Group (1),
Internal, 11 testers. A fresh builds-page reload at approximately 15:17 AST
confirms **100 Internal / Testing**, Fotty Internal Smoke and **11 invitations**.
No installation is yet reported; individual email delivery is unverified.
Build 93 remains Testing and available to the same group. No public submission,
new tester invitation, role change, device installation or backend deployment.

[Build 100 in App Store Connect](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/73ad2a13-6f0a-41c3-a14b-093f7f719cfe).
