# Fotty Sports Hub 2.0.1 build 116 — measured Home repair

3 October 2026. Owner-only optimized Release installed on Jet iPad Air 4 /
iPadOS 27.0.1. TestFlight 111 is unchanged. This continues the already-approved
usability/performance and named-device repair gate, not a shared release.

## Confirmed defects and repairs

An app-scoped SwiftUI Instruments recording of installed 115 ran for 45.933
seconds. Home had 13 body updates totalling 2,181.456 ms, with a 214.526 ms
maximum; most expensive updates took approximately 177–188 ms. Four potential
main-thread hangs lasted 316.152, 1,352.345, 686.940 and 729.809 ms, overlapping
these updates. Three app hitches lasted approximately one 16.67 ms frame each.
This establishes a real stall, not a slow Device Hub screenshot. Build 115's
matched symbols were unavailable, so individual function self-cost was not
established. Attempted mirrored scrolling did not visibly move the content and
does not qualify scroll performance.

Source inspection found repeated follow-key/league normalization and major-league
classification in Home's filtering/ranking passes. Build 116 prepares immutable
selection keys once and publishes per-event follow/major-league facts with the
existing discovery projection. Content, score, clock and same-count selection
edits invalidate those facts. Pending revisions use a prepared fallback rather
than stale facts; arbitrary raw-event callers do not use ID-only cached facts.
Inactive interest filters short-circuit. Fixture identity, source eligibility,
matching, ranking rules and persistence writes remain unchanged.

Physical 115 Watch Two testing also confirmed that the narrow secondary Focus
pane wrapped "Source 1" into fragments. The menu still opened; Focus/Equal and
Close returned the expected destinations after failed broadcast startup. Build
116 gives compact panels separate identity and control rows, a single-line
intrinsic source label, scaled 44-point minimum targets and another row for
accessibility text. Headers use allocated panel width rather than the fitted
video width; video retains its 16:9 fit. Transport/source/audio callbacks are
unchanged. These 115 broadcasts did not decode; failure-path interactions are
not proof of two live matches playing.

## Qualification and identity

- 736 Catalyst tests pass; two intentional opt-in skips; zero failures. Nine
  new regression tests cover prepared matching/invalidation and compact chrome
  geometry. An old source-shape assertion was updated to the adaptive persistent
  header and the full suite reran successfully. Six existing Catalyst audio
  warnings are not demonstrated iPad defects.
- Seven offline version tests, generated catalog check and deterministic/live
  provider identity checks across three reachable feeds pass.
- Official Xcode 27, sequential jobs 1, unsigned generic iOS Release, signed
  optimized Release, strict nested signatures and empty embedded provider-key
  checks pass. App/extension/source versions are coherent at 2.0.1 (116).
- Final pre-build receipt: `backups/release-source/2.0.1-116-owner-ipad-r2`;
  988 files, default secret scan/round-trip restore and pre-install compare pass.
  Recovery commit `fe6b7691cb1c0c0492aceb5a6b0f265dffe7a4c0`.
  Source SHA256 `1a0dd10bf92c9b15818b8e2bac9c1e706aabc77f011557deb631acb045ea120a`.
  Bundle SHA256 `e21d501cc3eb9a128189706e6166a9751e9fb937b43fa6099f56d8f288d1981e`.
  The earlier immutable candidate preceded the source-contract test correction
  and was not installed. Later release/memory documentation is outside the
  frozen final pre-build receipt.
- Installed signed executable SHA256:
  `a0b8326279940482dcd84552c9cb3f654c816a6fbf1978c52a2fc3865204c86c`.
  App/dSYM UUID `ECB58EFF-5B3B-3C8F-BFCB-41F711520884` (arm64).
- Exact-device in-place install, launch and CoreDevice installed-116 identity
  pass. Normal PID 2474 remains present after the profiling attempts. Process
  survival is not UI responsiveness proof. No uninstall, data reset, simulator
  or UI-test runner.
- Typed before/after preference comparisons prove unchanged local manager ID,
  manager/season confirmation, interest-filter preference, reminders, appearance
  and existing local review payloads. IDs/payloads are not copied into this note
  or the build. SwiftData follow records were not separately compared.

## Remaining active device gate (historical; see October 4 follow-up below)

The Mac locked during this gate; computer use cannot automatically unlock it.
Jet iPad remains connected/unlocked. CLI SwiftUI attachment cannot resolve the
app by executable name or exact current PID, including with official Xcode
pinned. The installed artifact has `get-task-allow=true`; these failures do not
establish a Release entitlement restriction. GUI Instruments successfully
recorded 115 earlier, but its repeat recording and visual 116 interactions now
require the owner to unlock the Mac. This is operational access, not renewed
repair/install permission.

Next: repeat the 45-second expanded-Home/Matchday/Home/Settings workload on 116
and compare body/hang/hitch costs; inspect and operate the compact Focus source
controls. Do not claim measured improvement, scroll qualification, native 116
visual acceptance or TestFlight readiness before these checks. Existing live
decoding/PiP/two-live-match acceptance remains distinct and source-dependent.

## Resources and boundaries

Packaging-environment/tool-path failures were corrected without weakening any
source, secret, identity or signature gate. Sequential build outputs were
removed on failure and after installation. Owned baseline trace/XML exports,
temporary source checkout, app package, preference copies and logs are removed
after recording their evidence. Approximately 43 GiB remains free. One matched
43 MiB dSYM is deliberately retained under
`backups/performance/owner-2.0.1-116` only for the pending device measurement;
remove it after that gate. Immutable source receipts and unrelated user caches
are preserved. No Git publication, backend deployment, tester change, spending,
FPL feature work or TestFlight upload.

## October 4 device follow-up

The Mac was unlocked and GUI Instruments captured installed 116 successfully.
The first 46.220520 s capture contains Home/feed updates only: mirrored input
did not visibly navigate, so it is not a navigation test. Seven Home bodies
totalled 206.548 ms (61.333 ms maximum), but a separate 883.536 ms main-thread
refresh microhang remained. Matched symbols identified repeated football alias
normalization and fixture formatter construction during catalog refresh work.

A subsequent 45.893685 s recording (07:18:33.718–07:19:19.612 UTC−04:00,
installed PID 2699) exercised actual drag scrolling and repeated
Home/Matchday/Settings transitions: 29 Home bodies, 1,061.237281 ms total,
77.407916 ms maximum; eight potential main-thread hangs, 3,335.806502 ms total,
675.028250 ms maximum; 21 app hitches, 716.627451 ms total, 299.980291 ms maximum.
It confirms residual responsiveness work; do not compare idle and navigation
captures as equivalent workloads.

Physical 116 Watch Two also decoded Motocross of Nations Day 3 on Source 1 and
Source 2. Pause, the source menu, independent source change, secondary-pane
promotion, Focus/Equal/Swap and Close operated; compact Source labels stayed on
one line. The second Sepang broadcast did not decode and showed its retry/error
path, so two-live-video/audio/PiP acceptance remains separate.

The measured catalog repair was built and installed as 117; see
`docs/releases/Fotty-2.0.1-117.md`. The previously retained matched 116 symbols
are no longer needed once the redacted follow-up is recorded.
