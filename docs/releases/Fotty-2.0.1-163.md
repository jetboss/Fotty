# Fotty 2.0.1 (163): single-player ownership repair, private Jet checks

19 October 2026. Private owner build only; no TestFlight, phone activity, remote
Git publication or backend deployment. FPL's 42 source hashes remain unchanged.
The owner explicitly prioritizes stable single-stream playback and reliable
sources. Watch Two/multistream work and physical testing are deferred until last;
existing pair-policy regressions in the full unit suite are not new pair work or
physical acceptance.

## Confirmed repair

162 exposed a real fullscreen ownership defect: a retry/failover can reuse the
same AVPlayer while replacing its item/attempt. The old AVKit presentation then
points at that mutating player, even though callback guards correctly reject its
old lease. Deferred SwiftUI reconciliation is insufficient to detach it first.

163 synchronously retires the exact borrowed fullscreen lease before admitted
source loads, attempt replacement, player replacement or cleanup. The session
permanently revokes observation tickets; its weak, exact-host callback detaches
the controller's player/delegate/observations before dismissal. Retirement is
idempotent and cannot tear down a newer lease. It adds no Play, Pause, seek,
reload, audio activation or source-trust change. Ordinary Done with retained PiP
preserves the same lease until the actual presentation finishes.

Six new regressions use the real AVKit controller/host binding with controlled
items/validators: same-player retry, automatic failover, player replacement and
cancellation, retained-PiP closing/restore, ordinary Done, and stale retirement
against a newer lease. They prove synchronous ownership/detachment, not physical
decode, audible playback or operating-system PiP continuity.

The five earlier foundations are documented in
[release 162](Fotty-2.0.1-162.md): controlled playback lab, ephemeral typed source
contract, preparation extraction and cookie-scoped single handoff, bounded causal
relay receipts, and measured source-health decode caching/Home signposts.

## Local and installation evidence

- Final corrected gate: **1,535 passed, two existing optional skips, zero failures**
  / 1,537 total in a fresh Catalyst unit host, not the installed old Mac app.
- 32 native-source tooling tests, 35 Node lab/performance-verifier tests and five
  provider identity vectors pass. Native membership/version, generic unsigned
  Release, signed Release and strict signature checks pass.
- Initial 163 had one failed new test: the second-lease fixture incorrectly
  assumed an empty composition would remain display-ready after the real host
  correctly published false. The fixture explicitly restores controlled readiness
  after its identity assertions. No production change or weakened assertion was
  used to make that rerun pass.
- Existing MatchReminder FocusState warning remains; new test-host UIWindow
  construction has Catalyst deprecation warnings. These are not hidden failures.
- Exact Jet iPad Air 4 / iPadOS 27.0.1 install, build readback 163 and normal launch
  pass. No simulator or substitute phone was used; the task-owned UI runner is
  absent.
- Frozen pre-build source receipt compares all 1,118 inputs before installation
  and again after physical checks. No remote changes are made.

Provenance for the corrected final r2 binary:

- Source SHA256: `1d54dce1c4c78ad43f9c65d4e11f7cc50b05475c8fb98ac61e604b4295c4ce2c`
- History-free snapshot commit: `5009cd046aab22b1992553018ea07eb20c05e1b4`
- Temporary bundle SHA256: `6038370004a9175602469a35a58fd27203494a30564455250937e65f790d5866`
- Signed executable SHA256: `3b3c20bc53154653c4690d66374e80430d34af56fbdf8ba9b71fbc9376e40728`

These temporary private-test receipts are not a retained shared-distribution
candidate. A future shared build still needs its own retained pre-build receipt.

## Actual 163 single-player evidence

Degerfors–Kalmar CS lookup matches the exact fixture in 1,051 ms and offers eight
total choices. CS1 native attempt `F1838BCB` decodes in 2,026 ms. At 18:44:38.668
UTC, after 33.2 seconds, it fails to play to end with CoreMedia -12312 / segment
URI changed. Same-source attempt `4D681F52` decodes in 1,652 ms. Actual football,
Apple native fullscreen and a floating decoded PiP window are visible, including
the broadcast clock advancing through 87:39 and floating video at 88:15.

At 18:46:16.929 that CS1 retry fails with the same HLS consistency category.
The failed presentation is retired and CS2 attempt `E5038430` starts. CS2 shows
advancing football/fullscreen and floating video at 91:11, but its floating
window disappears during the subsequent Home journey. An initially copied
diagnostic snapshot contained no new failure; a later snapshot records
`stalled` at 18:49:26.432 for that exact CS2 attempt. This later receipt must not
be omitted, nor does it establish the precise cause of the earlier disappearance.

Subsequent CS3 preparation records a URL -1001 timeout, then attempt `545C8BE6`
decodes in 4,228 ms and shows post-match football before the session closes at
18:53:54.583. Source errors and recovery are real; neither a decoded receipt nor
an audio-preparation callback proves uninterrupted background playback. The
403 from the separate 162 Monza session is not the cause of these 163 failures.

A later Getafe–Rayo single Broadcast 1 Web journey shows advancing stadium,
tunnel and football footage. Its receipt records readiness followed by a
20.2-second startup timeout/retry scheduling and decoded progress immediately
afterward. No CS exact fixture is returned for this lookup. No native handoff
option is available in that sampled menu. This is bounded ordinary Web playback
evidence, not native/PiP or a new matching-defect conclusion.

**Still open:** a clean current-build >60-second advancing background PiP hold,
real system Pause/Play/Restore, inline return with retained identity/intent, and
current-build audible acceptance. Source review found no justified new
background-retirement patch from the available evidence. Do not change teardown
or transport policy speculatively, call all CS choices reliable, or claim the
entire single-player gate/TestFlight is ready.

## Measurement, research and cleanup

The physical XCTest/system snapshot waits and failed xctrace attachment in
release 162 remain measurement limitations, not responsiveness passes. No new
CPU/memory/hitch or before/after physical speed claim is made. REA is connected
but native providers are unconfigured; no native REA runtime proof is claimed.
The source shortlist in release 162 remains research only; no new feed, trust
exception, credential flow, paid service or telemetry uploader is enabled.

Test media is stopped; Jet returns to All sports/Home in its original Light
landscape configuration, with keyboard capture off and no floating PiP. The
single reused 1.2 GB task-owned temporary gate was removed after its compact
evidence is recorded; no user caches, saved team or unrelated output are removed.
The task's awake process is stopped; process lookup finds no remaining caffeinate.
Disk space is 29 GiB free after cleanup versus 27 GiB before it. The owned
temporary root is confirmed absent. Shared distribution remains unchanged.
