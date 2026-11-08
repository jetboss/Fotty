# Fotty 2.0.0 (80) — Champions League operational readiness

Date: 2026-09-07. Status: **Internal / Testing for `Fotty Internal Smoke`;
real match-time iPhone/iPad acceptance pending**.

## Outcome

Build 80 presents the official 2026/27 Champions League schedule before stream
providers publish late listings, without promising Watch until a concrete
supported source exists. It recognizes all 36 current clubs, strictly collapses
duplicate provider identities, and ships with protected daily and match-window
readiness monitoring.

## Verification and distribution

- All 17 missing formal club aliases were reviewed and all 36 official team
  names now resolve through the shared generated catalog.
- Protected PR 21 merged as `2f7c6a13`. Its required workflow, secret, iOS, web
  and CodeQL checks passed.
- Hosted runs `34168160389` and `34168205609` passed after merge. The official
  feed reported 380 Premier League, 144 Champions League and 39 CPL fixtures;
  all 18 UCL Matchday 1 fixtures were represented with three concrete resolved
  variants each.
- The monitor includes player-supported Admin/PPV variants and rejects the
  Worker's synthetic Legacy fallback as availability evidence.
- The complete simulator-free Xcode 27 policy/Release gate passed. Public Xcode
  26.6 also passed the signed generic Release compile.
- The internal-only public-Xcode 26.6 archive reports app and Live Activity
  extension version `2.0.0 (80)`, minimum iOS 26.4, expected bundle identifiers
  and valid strict nested signatures. Provider key build settings are empty.
- The uploaded app executable SHA-256 is
  `900e59fdc1fee2ed062da38aacd5ca40b39d82a86e9ac57316917b68017e4ea2`.
- Xcode reported `Upload succeeded` at approximately 19:05 AST. Apple shows the
  upload Complete, accepted the established none-of-the-listed-encryption
  declaration, persisted the focused English (U.K.) What to Test notes, and
  independently shows build 80 **Internal / Testing** for only the unchanged
  seven-person `Fotty Internal Smoke` group.
- Build 79 remains active as rollback. No tester, role, external-testing group,
  device installation, data container or production Worker changed.
- The single archive/export root and separate Xcode distribution log were
  removed. No task-owned build directory remains and free disk stayed about
  50 GiB.

## Open physical gate

During a real Champions League match, update from TestFlight on a supported
iPhone and iPad and verify listing transition, deduplication, startup, retry,
source switching, pause/play, audio and Picture in Picture. Hosted metadata and
resolved embed URLs cannot prove decoded playback.

UCL live scores/minutes and goal/full-time alerts remain deliberately disabled
under the Premier-League-only score policy. Schedule-based match-start reminders
remain available.
