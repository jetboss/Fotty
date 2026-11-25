# Fotty 2.0 Private Qualification

Approved: 31 August 2026  
Audience: 3–5 trusted internal testers  
Duration: seven consecutive days of ordinary use

Current prepared ledger: [Build 113 qualification](BUILD-113-QUALIFICATION.md).
It is a local source candidate, not yet installed or shared. Entry gates and the
seven-day clock remain open; do not substitute older private-device evidence.
The unstarted [build93 ledger](BUILD-93-QUALIFICATION.md) remains historical.

## Purpose

This round determines whether Fotty is dependable enough for a larger private
beta. It is not a feature poll and it is not public-release approval. Fotty's
universal promise is live and upcoming sports discovery plus truthful playback;
FPL is a first-class optional power tool.

The checked-in minimum remains iOS/iPadOS 26.4 for this private cycle. Do not
promise older-version support until Fotty can be exercised on real older
hardware. Use the existing internal TestFlight group and add or change testers
only with the owner's explicit approval.

## Candidate entry gate

Begin the seven-day clock only after one coherent TestFlight candidate:

- passes the complete simulator-free iOS, web/Worker and provider identity gates;
- identifies its deployed Worker source version in `/health` and the release record;
- installs and launches as the exact build on a supported iPhone and iPad;
- passes native PiP app-switch and lock/unlock, encrypted Files backup/restore,
  one real live-stream recovery soak, and the changed-surface accessibility pass;
- has no known critical crash, data-loss, duplicate-audio or uncontrollable-player defect.

A private owner-device build may prove a narrow correction, but it does not
start or certify this shared TestFlight round.

## Five uncoached tasks

At least one tester who did not build the app must complete all five without
live direction:

1. Find and watch a live non-football event.
2. Find an upcoming event, save it and opt into its reminder.
3. Return from the reminder and explain why Watch is or is not available.
4. Connect an FPL manager and explain published squad versus planned draft.
5. Prepare and deliver a problem report with enough redacted evidence to diagnose it.

Record each task as completed independently, completed with help, app failure,
provider-blocked or not attempted. Provider availability is not an app pass or
failure by itself; dishonest state, lost controls or unrecoverable navigation is.

## Daily-use coverage

Across the group and week, obtain evidence for:

- iPhone and iPad; portrait/landscape where supported; Light, Dark and System;
- football, cricket and at least two other sports in discovery/search;
- save/remove, countdown, reminder return and My Matchday pruning;
- web and native playback, pause/resume, mute, source change, interruption,
  background/foreground, native PiP and one sustained live session;
- Live Activity/widget start, update, return, natural end and stale cleanup;
- FPL Gameweek, Squad, Coach and at least three secondary tools, checking their
  Official data, Projection, Estimate, Published data, On-device plan or
  Advanced solver label against the result;
- encrypted backup export, wrong-password rejection, preview and restore over an
  existing install without restoring consent, reminders, Coach text or stream routes;
- large text, Reduce Motion and a VoiceOver journey on both form factors.

## Operating rules

- Freeze feature expansion during the seven days. Only critical blockers,
  data-loss, privacy or severe playback corrections may restart the round early.
- Keep automatic analytics off. Use TestFlight crash information and the app's
  opt-in, redacted report export. Never copy manager IDs, Coach prompts, tester
  addresses, stream URLs, credentials or backup passwords into Git.
- Log the exact app build, Worker source version, device/OS class, task, observed
  result, app/provider classification and whether the user needed help.
- A corrected binary is a new candidate and normally restarts the seven-day
  clock. Document an explicit exception only for a non-behavioral metadata note.

## Exit threshold

Expand beyond 3–5 testers only when:

- all five uncoached tasks pass;
- every candidate entry blocker remains closed for the exact build;
- no critical or repeated high-severity app defect remains;
- one TestFlight report is confirmed received under the correct build;
- provider failures remain truthful and recoverable;
- the release record, deployed Worker identity and physical evidence agree.

If the threshold fails, keep the current group, return to private pre-test for
the smallest correction and prepare a new coherent candidate. Do not widen the
group to obtain more noise around an unresolved blocker.
