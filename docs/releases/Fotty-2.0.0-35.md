# Fotty 2.0.0 (35) — internal TestFlight

Date: 2026-08-27

Status: **Testing — available to Fotty Internal Smoke**, independently verified in App Store Connect at 19:21 AST. Upload and processing are complete, the owner's encryption declaration is accepted, tester notes are saved, and the existing internal group is assigned.

## Distribution scope

- Normal `Fotty` scheme, optimized `Release`; not ReviewSafe.
- App `com.jelani.Fotty`, extension `com.jelani.Fotty.LiveActivityExtension`.
- iPhone and iPad; minimum iOS/iPadOS 26.4.
- Internal-only TestFlight, existing **Fotty Internal Smoke** group (two testers).
- Live App Store Connect preflight showed only `2.0.0 (34)`, with its upload complete. Build 35 was allocated with `tools/set-version.sh`; app, extension and `project.yml` agree.
- No new testers, role changes, external beta/App Store submission, direct device installs or source publication are authorized by this release.

## What to test

UI and first-use improvements across Home, Matchday, FPL and Settings.

1. Find and open a broadcast from Home; check readable club names and Watch live/Open broadcast labels. Save a match and find it in your personal Matchday.
2. Connect your FPL team using its official link or ID and confirm the team name. Move between FPL and the other tabs; check that your tool, scroll position, comparison selections and unsent Coach text remain.
3. Check Squad and Plan on your device, including large text and iPhone Display Zoom. Verify readable player names, numbered fixture difficulty and clearly labelled official/provisional/projected points.
4. Try Settings → Help and Report a problem. Prepare a report, then submit it through TestFlight → Send Beta Feedback. Copying or sharing inside Fotty does not send a report automatically.
5. With a working provider feed, check Play/Pause, the provider's unmute control, source selection and returning after an interruption. Report device, build, expected behaviour and what happened.

Known limits: third-party broadcast availability varies; live scores are Premier League-only; match-update alerts require foreground score fetching; FPL deadline reminders are separate local notifications; Fotty plans do not change official FPL; preferences and drafts are device-local.

## Verification evidence

- Reused exact app-source evidence from [the UI refinement report](../audit/Fotty-UI-Refinement-2026-08-27.md): 122 unit tests passed, one opt-in HLS soak skipped; 14 scoped Catalyst UI checks passed; normal and ReviewSafe generic-iOS builds passed unsigned. The only app/project change for this release is the build-number advance from the local build-33 source to 35; build 34 was already uploaded previously.
- Release-owned whitespace and project/export plist validation passed before archive.
- Xcode 27.0, build 27A5237l. Normal archive uses automatic signing, generic physical iOS and two jobs. Provider API-key build settings are explicitly empty; the active Worker owns credentials.
- Source/config SHA-256: `441e7bbcd42ef00bbfc4741f89197b6d85a3e70ac6907ad65a8784b5ae8a1cac`. This hashes the sorted per-file SHA-256 records for app/extension source/resources, Xcode project/shared scheme, `project.yml` and the internal export plist, excluding `.DS_Store`.
- Archive verification passed: both bundles report `2.0.0 (35)`, the expected bundle IDs and minimum OS 26.4; strict signatures pass and all three provider API-key plist values are empty. Source/config fingerprint remained unchanged across the archive.
- Apple's Xcode upload returned **EXPORT SUCCEEDED** and **Upload succeeded** at 19:12:19 AST. Processing completed without an upload validation failure. After the owner completed the encryption declaration, the build changed from **Missing Compliance** to **Ready to Test**. After group assignment, a fresh builds-page read showed [build 35](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/6a8f3bc1-c18e-4727-9524-e1f732a88d9f) as **Internal / Testing**, assigned to **Fotty Internal Smoke**.
- The encryption form asked about proprietary or separately implemented standard algorithms. No custom crypto implementation/import was found in app/extension Swift code, and the archived executable links only Apple/system frameworks and Swift libraries. The owner was advised to select **None of the algorithms mentioned above**, consistent with [Apple's built-in-encryption guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations), and then reported saving it. The accepted state was independently checked; this does not imply unencrypted networking.
- The What to Test text above was saved in English (U.K.), and App Store Connect confirmed **Saved**. The existing group still has two testers, feedback enabled and **Manual for Xcode Builds** distribution. No new tester, account role or automatic-distribution setting was added or changed. No build-35 installation or received feedback report is claimed by the Testing status.

## Acceptance boundary

Fresh physical-device qualification of the new interface remains a TestFlight task. Previous installed builds do not certify this build's layout, keyboard, accessibility or playback interactions. Confirm a received feedback report before widening the group.

The dirty checkout remains on old Git ancestry. This binary release does not authorize pushing it; clean-ancestry replay remains required for future source publication.

## Resource record

Before and after archive/upload: 41 GiB available. The one owned temporary root (305 MB) containing DerivedData, archive, export and local logs was removed by the successful-exit trap. Xcode's separately created distribution-log bundle was also removed. No simulator, direct install or device UI-test runner was used; only small source/release records remain.
