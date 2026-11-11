# Fotty 2.0.0 (81) — reconciled reliability candidate

Date: 2026-09-07. Status: **Internal / Testing for `Fotty Internal Smoke`;
physical-device acceptance pending**.

## Outcome

Build 81 reconciles the current working product into one reproducible candidate
and closes a real FPL squad-editing integrity gap. Duplicate or unchanged player
replacement attempts are rejected with accessible feedback, while a valid
replacement remains saved after navigation. Automated FPL fixtures cannot be
invalidated by production account-freshness checks.

The build also adds stable accessibility identities to the Home interests,
sport/event, match-start and squad controls used by release qualification. UI
failures retain focused evidence, while contrast qualification relies on the
existing numeric colour contracts instead of unreliable Catalyst screenshot
sampling for known system-rendered labels.

## Verification and distribution

- App Store Connect independently showed 2.0.0 (80) as the latest completed
  build, so 81 is the next unused build number across the app and Live Activity
  extension.
- The exact candidate replayed from clean `origin/main` ancestry with no omitted
  tracked or untracked files; candidate and replay trees both resolved to
  `a0ac45da174e3bbfa18496ff6380cd06f17ef6ba` before the version and release-note
  allocation.
- Gitleaks found no secret in that exact candidate. Two ignored local credential
  helper files were deliberately excluded from the candidate and never printed.
- All 22 durable-memory tests passed, and `git diff --check` passed.
- Public Xcode 26.6 passed the complete simulator-free policy/unit gate and
  signed generic-iOS Release compile.
- Xcode 27 passed all 20 sequential Catalyst UI journeys, covering Dashboard,
  Matchday, Settings, Match Center, Player, FPL, Dynamic Type, contrast,
  foreground recovery, filtering, cricket discovery and saved squad changes.
- No simulator or physical-device install was used for shared-release
  qualification. Disposable build and UI evidence was removed after each gate.
- The public-Xcode 26.6 archive reports app and Live Activity extension version
  `2.0.0 (81)`, expected bundle identifiers and valid strict nested signatures.
  The archived app executable SHA-256 is
  `e531066136bb5681c335c17f8d687ce1f891dbd41f5ab6886376812ca0a63e9a`.
- Xcode reported `Upload succeeded` at approximately 22:54 AST. Apple completed
  processing, accepted the established none-of-the-listed-encryption
  declaration, saved the focused English (U.K.) What to Test notes and shows
  build 81 **Internal / Testing** for the unchanged seven-person
  `Fotty Internal Smoke` group.
- No tester, role, external-testing group, physical device, data container,
  production Worker or Git history changed. The owned archive/export root and
  Xcode distribution log were removed; free disk returned to about 50 GiB.

## Open gates

- Install the exact TestFlight build on a supported iPhone and iPad and verify
  version 2.0.0 (81), preserved preferences, Home, Matchday, Settings and FPL.
- During a real Champions League match, verify listing transition, startup,
  retry, source switching, pause/play, audio and Picture in Picture on both
  devices. Metadata and resolved embed URLs do not prove decoded playback.
- Build 80 remains the rollback until build 81 completes those checks.
