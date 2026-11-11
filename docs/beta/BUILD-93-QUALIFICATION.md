# Build 93 — independent private-use evidence

Prepared 2026-09-09. **Not started; entry checks still pending.**
Candidate: TestFlight 2.0.0 (93), not direct iPad 92 or iPhone 90.
Owner coordinates 3–5 volunteers from the existing internal group; this document
does not invite anyone, change roles or confirm receipt of an invitation.

Use the acceptance rules in [Private qualification](PRIVATE-QUALIFICATION-2.0.md).
The older [Round 01 ledger](ROUND-01-ACCEPTANCE.md) remains historical build-45
evidence, not the active test plan. Local post-93 diagnostic changes are **not
in this candidate** and must not be included in its What to Test claims.

## Entry checks — owner/maintainer

Record date, exact build, device/OS class and a redacted evidence reference. A
blank or Pending cell is not a pass. Do not put private IDs, addresses, stream
URLs, passwords or Coach conversations in this file.

| Check | Current evidence | Result / remaining action |
| --- | --- | --- |
| App qualification | Release 93: 538 Catalyst units pass; 2 opt-in skips; iOS Release/archive pass; 4 UI checks pass on rerun | Automated app gate recorded; not physical acceptance |
| Web/Worker and provider gates | Five identity vectors and three-feed metadata audit recorded for 93 | Verify retained web/Worker qualification matches the deployed source; Pending |
| Deployed backend identity | No fresh `/health` receipt taken for this round | Record source version and UTC check time; Pending |
| Exact TestFlight iPhone install | No exact-93 physical evidence recorded | Settings version, launch, retained interests/data; Pending |
| Exact TestFlight iPad install | Private 92 acceptance is earlier evidence only | Version, launch, landscape and retained data; Pending |
| Playback and recovery | Earlier owner PiP acceptance does not certify 93 | Native PiP app-switch/lock/unlock, web controls and live recovery soak; Pending |
| Encrypted backup/restore | Automated tests are not a Files round-trip | Use an expendable test profile; export, wrong password, preview, restore and compare; Pending |
| Changed UI accessibility | Catalyst checks recorded | Real large text, Reduce Motion and VoiceOver on both form factors; Pending |
| Critical-defect review | Known youth/UCL listing-label issue remains outside the animation fix | Reproduce, classify severity, record disposition; do not silently mark fixed |

Do not overwrite an owner's real data for the restore test. A disposable test
profile/device and explicit restore approval are prerequisites. Don't count a
provider outage as successful playback; distinguish it from app-owned failures.

When every required entry gate passes, set the start date and seven-day end
date below. Do not backdate the round based on earlier informal testing.

- Start: Pending
- End: Pending
- Worker source version: Pending
- Participant aliases and device/OS classes: P01–P05, unassigned

## Tester task card — no live coaching

Owner may share this short card after the entry gate. This is a prepared draft,
not a sent message:

> Please use TestFlight build 2.0.0 (93). First check its version in Settings.
> Try these tasks without asking for directions; getting stuck is useful feedback.
> 1. Find and watch a live event that isn't football.
> 2. Find an upcoming event you care about, save it and turn on a reminder.
> 3. Return from that reminder. Tell us why you can or cannot watch yet.
> 4. If you use FPL, connect your own team and tell us which squad is published
>    and which changes are only your plan. We need one willing FPL user for this task.
> 5. Prepare a problem report and send it through TestFlight. Do not include
>    passwords or private information; sharing diagnostics is optional.
> Tell us which task you tried, what happened, your device/OS and the build number.
> If you needed help, say so—we're testing the app, not you.

Results: **Independent**, **Help needed**, **App failure**, **Provider blocked**,
or **Not attempted**. The participant who qualifies all five must be an FPL user;
do not make optional FPL connection a requirement for every sports tester.

| Participant | Find/watch | Save/remind | Reminder return | FPL published/draft | Report delivered |
| --- | --- | --- | --- | --- | --- |
| P01 | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P02 | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P03 | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P04 (optional) | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |
| P05 (optional) | Not attempted | Not attempted | Not attempted | Not attempted | Not attempted |

## Seven days of ordinary use

Keep one candidate stable. Use normal sessions, not daily compulsory scripts.
Across the group cover the daily-use list in Private qualification, including
two additional sports, both appearances, tablet rotation, long playback,
widgets/Live Activities and secondary FPL tools.

| Day | Date | Build / Worker receipt | Sessions or journeys observed | Blockers / report references |
| --- | --- | --- | --- | --- |
| 1 | Pending | Pending | Not recorded | Not reviewed |
| 2 | Pending | Pending | Not recorded | Not reviewed |
| 3 | Pending | Pending | Not recorded | Not reviewed |
| 4 | Pending | Pending | Not recorded | Not reviewed |
| 5 | Pending | Pending | Not recorded | Not reviewed |
| 6 | Pending | Pending | Not recorded | Not reviewed |
| 7 | Pending | Pending | Not recorded | Not reviewed |

If app or backend behavior changes, record exactly what changed and reassess the
candidate; don't silently combine different versions. Critical corrections may
restart the round. A missing crash report or missing Apple performance payload
does not prove there were no crashes or hangs.

## Close the feedback loop

One real report must progress through these states under the correct build:

1. **Prepared** — report text exists. Clipboard/share-sheet success stops here.
2. **Sent (tester-reported)** — tester says TestFlight accepted submission.
3. **Received (verified)** — maintainer sees the report in App Store Connect,
   matches build/device context, records time and a non-private report alias.
4. **Triaged** — reproduce if possible; classify app, provider, data or unclear;
   assign severity and next action. Tell the tester it was received.
5. **Correction prepared**, if needed — link the local change/new candidate;
   this is not a claim that it has been distributed.
6. **Retest verified** — record the exact tested build and outcome before closure.

| Report alias | Participant | Build | State | Evidence / next action |
| --- | --- | --- | --- | --- |
| R01 | Unassigned | 93 | Not prepared | Establish one end-to-end received report |

Do not send acknowledgments or publish fixes without task-scoped authority. The
source-only work on 9 September prepares this process; it does not send reports.

## Exit decision

**Pending.** Require the five independent tasks, entry gates, seven days,
truthful/recoverable provider failures, one verified received TestFlight report
and no unresolved critical/repeated high-severity app defect. Record the owner's
decision before widening the group. This is private-beta qualification, not
public-distribution approval or proof that every provider works.
