# Fotty 2.0.0 (47) — private iPad PiP acceptance candidate

Date: 2026-08-30. Status: **installed only on Jet iPad; manual PiP acceptance
open**. This is a locally signed Debug build, not a TestFlight upload.

## Purpose and version boundary

Build 47 carries the merged native Picture in Picture background-continuity
correction, app-wide Home search, and football identity pipeline from current
`main`. It exists so the PiP correction can be identified independently from
Apple's shared internal TestFlight build 46.

The first direct install during this task retained build number 46. It launched
and held successfully, but it reused the TestFlight identifier and therefore is
not acceptance evidence. Before physical acceptance, `tools/set-version.sh`
allocated the next unused number, 2.0.0 (47), and the iPad was immediately
replaced with that uniquely identifiable binary.

Product/version commit: `e1b7f0d56767`. The documentation commits that follow
do not change the built app graph.

## Build and installation evidence

- The reviewed seasonal catalog check, five shared provider identity vectors,
  and live metadata audit pass across three reachable feeds.
- One signed generic-device Debug artifact was built sequentially with two
  Xcode jobs and no simulator.
- Strict code-sign verification passes for the normal Fotty app and its Live
  Activity extension.
- Both bundles independently report marketing version 2.0.0 and build 47.
- CoreDevice independently reports Fotty 2.0.0 (47) installed on Jet iPad.
- The normal app launches and remains present through a 60-second physical
  foreground hold.
- No UI-test runner was built or installed. The connected iPhone was untouched.
- No TestFlight upload, Apple metadata/group change, Worker/web deployment,
  paid Coach request, or simulator use occurred.

## Remaining physical acceptance

Installation and a foreground hold do not prove background PiP continuity. On
an independently decoded stream that successfully hands off to the native
player:

1. Start system Picture in Picture.
2. Open another app for at least 60 seconds.
3. Lock and unlock the iPad once.
4. Confirm the same video continues advancing with audio, without a source
   replacement, foreground-only resume, duplicate audio, or orphaned player.
5. Return to Fotty and confirm the same match/player UI restores correctly.

Record provider availability separately from app behavior. A provider that
does not decode cannot certify or disprove the PiP lifecycle correction.

## Cleanup

The single `/private/tmp/FottyPhysical47.*` build root was removed by its cleanup
trap immediately after installation. No task-owned app, archive, result bundle,
or screenshot remains. The workstation reports approximately 50 GiB free.
