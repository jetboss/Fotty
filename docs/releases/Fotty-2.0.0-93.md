# Fotty 2.0.0 (93) — shared UI polish batch

2026-09-08. Status: **Internal / Testing for Fotty Internal Smoke;
exact TestFlight device acceptance pending**.
Owner authorized internal TestFlight deployment, not external testing or Git
publication. Existing group membership and previous builds remain unchanged.

## Included

The accumulated private 82–92 batch: compact Home and sport tiles; clearer
grouping across Matchday, FPL, Settings and Search; retained club badges and
equipment artwork; adaptive iPad landscape layouts; optional, off-by-default
kickoff-clash hints; consistent current/upcoming clocks; quieter routine refresh
states; and original shaded, sport-specific loading motion. Champions League
decoration requires explicit competition or matched official fixture evidence.
No playback transport, backend or provider contract changes in this release task.

Build 93 is a version-only successor to the private 92 app source. App/widget
and XcodeGen source versions agree at 2.0.0 (93). Public Xcode 26.6 (17F113) is
the archive/upload toolchain. App Store Connect was independently checked and
showed build 81 as the latest shared build, with eight existing testers in
`Fotty Internal Smoke`; historical seven-person records are not current counts.

## Qualification

- Generated catalog drift and five provider identity vectors pass. The fresh
  metadata-only audit reached three provider feeds and reported no conflicts.
- Full public-Xcode Catalyst unit gate: **538 passed, zero failed, two skipped**.
  The optional reference-HLS soak and live Score808 discovery tests were skipped;
  this is not live decoded playback evidence.
- Private source-exact evidence is retained in releases 89–92: 13 distinct
  iPad/layout Catalyst checks for 89, six clock/discovery checks for 91, and
  dark/light native artwork inspection plus 169 focused checks for 92.
- Generic iOS Release compilation passes. Four refreshed Xcode 27 Catalyst
  checks pass: Home kickoff/resize/navigation, Dashboard Dynamic Type, Settings
  notification grouping and Player Dynamic Type.
- The first kickoff check failed to find Live now. Its captured screen still
  showed the initial test clock/countdowns; an unchanged rerun passed the whole
  transition. Record this intermittent test-clock action failure, not a clean
  first-pass claim or a diagnosed production defect. No app/test code changed
  to obtain the rerun pass. Existing Catalyst audio-session runtime warnings
  remain outside this UI release's ownership.
- `git diff --check` passes. The public-Xcode optimized archive passes strict
  app/widget and nested signatures, matching bundle identifiers and 2.0.0 (93),
  minimum iOS 26.4, Xcode build 17F113 and dSYM presence. Production defaults
  retain the existing Worker; provider credentials are not embedded.
- Archived app executable SHA-256:
  `d7a0d8d3bbd4648069617984ad2d24529eb200ade9d09fac42ba33638e73567e`.
- Upload uses the existing internal-only export plist, preserving build number
  93 and uploading symbols. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**
  at 21:31 AST. Apple processing and existing-group assignment remain separate.

## Distribution

Apple processing completed. The unchanged none-of-the-listed-algorithms export
declaration was accepted; focused English (U.K.) What to Test notes were saved
before assigning the existing `Fotty Internal Smoke` group. The detail page
confirms one Internal group with eight testers, and the build list confirms
**2.0.0 (93), Internal, Testing, eight invitations**. Build 81 remains Testing.
No new tester invitation, role change, external group, direct-device install,
production deployment or Git publication was performed. Email delivery and
actual tester downloads are not established by this availability check.

[App Store Connect build 93](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/bd7af8a7-3d61-43ae-9474-5c10ae62c726)

## Remaining acceptance

Install the exact TestFlight build on iPhone and iPad, check Settings version,
preserved interests and data, portrait/landscape, light/dark, large text, FPL
saved changes, and real stream loading/playback/PiP. Private iPad 92 acceptance
does not certify the distributed 93 artifact. Physical motion/power/hitching
measurement remains open. The known separate youth/UCL listing-label issue is
not fixed by decorative animation filtering. UCL scores/goal alerts remain off.

Build 81 remains the previous shared fallback. No tester is added or removed.

The owned 2.3 GB release root (archive, DerivedData, results, screenshots and
logs) and Xcode's separate distribution log were removed after successful
upload. Approximately 47 GiB is free. Only regenerable task output was removed;
no user data, unrelated caches or tester/device data changed.

## Post-release recovery and independent testing — 2026-09-09

A 17 MB history-free local recovery bundle was captured and restored against its
645-file manifest before later field-feedback app changes. Its purpose is
`post-release-recovery`: build 93 has no pre-archive source manifest, so this
does not establish exact historical binary provenance. The active Git history
was not changed or published. See [source recovery](../operations/SOURCE-RECOVERY.md)
for hashes, limits and the verified private GitHub recovery copy. The owner
subsequently authorized `jetboss/fotty-recovery`; a fresh download/restoration
matches all 645 source files. No automatic backup or new app release is implied.

[Build 93 qualification](../beta/BUILD-93-QUALIFICATION.md) now provides the
entry checks, five independent tasks and received-report ledger. Physical
acceptance and the seven-day round remain unstarted. The subsequent local
performance-summary export is not included in build 93, and no new release or
tester change was made while preparing it.
