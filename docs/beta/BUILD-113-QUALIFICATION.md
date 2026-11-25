# Build 113 private daily use qualification

Prepared 1 October 2026. **Not started.** This is a local source candidate,
2.0.1 (113), not an installed or shared TestFlight build. Shared 111 and owner
iPad 112 remain unchanged. Earlier informal tests do not qualify this candidate.

The purpose is to establish whether the current app can reliably complete a
normal sports session. Follow [Private qualification](PRIVATE-QUALIFICATION-2.0.md)
after the exact candidate passes every entry gate. Use 3–5 willing volunteers
from the existing group; this record does not contact them or change access.

## Entry evidence

Record the date, exact build, device and OS class, and a redacted evidence
reference. A missing result is not a pass. Source checks do not prove visual
quality, background playback, notification delivery or a real Files restore.

| Gate | Evidence | Status |
| --- | --- | --- |
| Reproducible native source | Owner112 plus ten native/config/test and three gate-tool paths; pre-build receipt in `backups/release-source/2.0.1-113-candidate/` | Captured before build; full post-build comparison and restore pass |
| Native automated qualification | Official Xcode 27: 657 Catalyst passes, two opt-in skips; unsigned generic iOS Release; five provider vectors; 20 offline version/recovery tests | Passed; no physical acceptance implied |
| Deployed backend | PR36, `0416690`; source `2026-10-01.cricket-corrections-1`; health and fixture endpoints checked 20:57 UTC on 1 October | Companion identity verified; no deployment performed |
| Exact iPhone and iPad | Version, launch, retained interests, saves and FPL data on the same candidate | Pending installation authority and physical checks |
| Playback lifecycle | Native and web controls, independent source/audio changes, PiP app-switch and lock/unlock, sustained real-stream recovery | Pending physical evidence |
| Saved match journey | Find, save, opt into reminder, reschedule, return and truthful Watch state | Pending actual notification journey |
| Personal recovery | Encrypted export to Files, wrong password, preview and restore on an approved disposable profile | Pending; do not overwrite owner data |
| Accessibility | Changed surfaces on real phone/tablet with large text, Reduce Motion and VoiceOver | Pending physical evidence |
| Shared availability | Exact candidate uploaded, processed and assigned to unchanged internal group | Not requested; not distributed |

The backend remains deliberately scoped: eight admitted non-cricket competition
lanes and CPL, West Indies and ICC cricket, not every sport or domestic league.
Website and WNBA collection remain off. A schedule does not prove a stream.
The source bundle is a native qualification baseline; its older web/Worker tree
must not be deployed as if it were PR36. See the [candidate record](../releases/Fotty-2.0.1-113.md).

## Five independent tasks

After the entry gates, ask willing testers to use the exact TestFlight candidate
without live coaching. This is a prepared task card, not a sent invitation.

1. Find and watch a live event that is not football.
2. Find an upcoming event, save it and enable its reminder.
3. Return from that reminder and explain why Watch is or is not available.
4. If you use FPL, distinguish your published squad from an on-device draft.
5. Submit a useful, redacted problem report through TestFlight.

Use **Independent**, **Help needed**, **App failure**, **Provider blocked** or
**Not attempted**. One willing FPL user must complete all five; do not require
every sports tester to connect FPL. Diagnostics and sharing remain opt-in.

| Alias | Find and watch | Save and remind | Reminder return | FPL published and draft | Report delivered |
| --- | --- | --- | --- | --- | --- |
| P01 | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P02 | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P03 | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P04 optional | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P05 optional | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |

## Seven day record

Start and end dates are **Pending**. Start only after the coherent shared
candidate passes entry checks. Cover both form factors, at least two additional
sports, appearances, playback recovery, Watch Two, widgets and Live Activities,
saved intent, recovery and accessibility. Record app and Worker identity for
each observation; a changed binary normally restarts the round.

| Day | Date | App and Worker | Journeys observed | Blockers or report aliases |
| --- | --- | --- | --- | --- |
| 1 | Pending | Pending | Not recorded | Not reviewed |
| 2 | Pending | Pending | Not recorded | Not reviewed |
| 3 | Pending | Pending | Not recorded | Not reviewed |
| 4 | Pending | Pending | Not recorded | Not reviewed |
| 5 | Pending | Pending | Not recorded | Not reviewed |
| 6 | Pending | Pending | Not recorded | Not reviewed |
| 7 | Pending | Pending | Not recorded | Not reviewed |

## Received feedback and exit decision

For one actual report, verify receipt in App Store Connect under the correct
build, classify its cause and severity, and record any retest. A prepared report
or a successful share sheet is not evidence that the maintainer received it.

| Report | Participant | Build | State | Next action |
| --- | --- | --- | --- | --- |
| R01 | Unassigned | 113 | Not prepared | Obtain one independently received report |

**Exit decision pending.** Require all entry gates, seven days, the five
independent tasks, one verified received report, truthful recoverable provider
failures and no unresolved critical or repeated high-severity app defect before
expansion. Apple sessions alone cannot establish these outcomes. Do not record
tester addresses, manager IDs, stream URLs, credentials or passwords here.
