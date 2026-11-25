# Fotty 2.0.0 (59) — roadmap physical-acceptance candidate

Date: 2026-09-05. Status: installed and launched on Jelani's iPhone and Jet
iPad; hands-on acceptance pending; not uploaded to TestFlight.

## Candidate scope

Build 59 is the first owner-device candidate containing the four local roadmap
batches implemented after build 58:

- protected playback, bounded private Coach access and recoverable FPL planning;
- one connected Home → Matchday → Watch sports journey;
- manager/season/evidence-safe FPL workspaces; and
- retained browsing context, adaptive Settings, truthful persistence failures,
  verified private backup and clearer feedback handoff.

The dated implementation records under `docs/audit/` remain the detailed source
of truth. Paid Coach access stays disabled in the checked-in backend
configuration, and no backend or production configuration was deployed.

## Automated and installation evidence

- The exact final source passed the simulator-free native gate: 486 of 488 tests
  passed, with the two intentional live/soak tests skipped. The generic unsigned
  iOS Release build passed.
- Seven affected Mac Catalyst journeys passed: Settings and Matchday Dynamic
  Type, Home sport retention, rapid navigation, native Help/feedback, cricket
  discovery and Home discovery. An ordered run exposed retained SceneStorage
  leaking between UI-test processes; the final DEBUG-only initialization fixes
  test isolation without changing production restoration.
- The pre-install live provider identity audit passed across all three reachable
  feeds. This verifies identity vectors and reachability, not video decoding.
- One automatically signed universal Debug app passed strict recursive signature
  verification and was installed unchanged on Jelani's iPhone
  (`BB28E60B-9156-56C3-A5E1-1DBC8CABEC3D`) and Jet iPad
  (`34E32922-73D6-54EA-8556-7904EE7804BD`). Both launched normally.
- CoreDevice independently reports `Fotty Sports Hub` 2.0.0 (59) on both devices.
  The main app and Live Activity extension on each device retained the same
  process identifiers through a 60-second hold.
- The signed generic Release smoke passed after both installations.

## Remaining physical acceptance

Installation, launch and process survival do not prove visual or interaction
quality. iPhone Mirroring is available but requires the owner's Touch ID or Mac
password before remote inspection. The owner still needs to authenticate that
session, and iPad checks require direct handling.

Do not mark batch 4 or the private-release entry gate complete until the exact
installed candidate has exercised Light/Dark/System, large text, VoiceOver,
rotation, keyboard dismissal, browsing-position restoration, real Files export,
wrong-password rejection and reviewed restore. Playback/PiP/background audio,
reminder return, Live Activity/widget behavior and one actually received tester
report remain separate physical gates.

No simulator or device UI-test runner was used. The owning build directory,
signed app copy and Release products were deleted after the gate. Available disk
space was approximately 28 GiB afterward. Shared TestFlight remains build 55;
no tester, App Store Connect, Git remote or service state changed.
