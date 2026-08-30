# Round 1 — reliability and independent first use

Target: **Fotty 2.0.0 (45)** through internal TestFlight.
Status: **available to the existing group; build-45 installation and physical task results remain open**.
See [the release record](../releases/Fotty-2.0.0-45.md) for availability.

## Start with the existing group

Update normally through TestFlight; do not delete Fotty or install a cable build
over it unless separately authorized for a specific private diagnostic. Confirm Settings version/build and that saves, follows, FPL identity,
appearance and local plans remain. Use participant aliases in this record; do
not copy tester emails, manager IDs, private stream URLs or prompts into Git.

The owner's iPhone 15 Pro Max on iOS 27.0 and the second tester's iPhone 16 Pro
Max on iOS 26.6 previously showed **Installed 2.0.0 (43)** in App Store Connect,
verified **2026-08-28 13:23 AST**. Build 45 currently shows two invitations but
no installation/session evidence. A supported iPad is also needed.

### Previously owner-only correction: build 44, now consolidated into 45

After reporting FPL draft/official-squad confusion, the owner explicitly
authorized an iPhone-only build 44, without a TestFlight upload. It is installed
in place and independently version-checked; a 20-second normal launch hold
passes. Linked FPL identity, the 15-player local draft, appearance and saved
matches are retained. Actual replacement/refresh/reopen and source-toggle taps
remain open. See [the private release record](../releases/Fotty-2.0.0-44.md).

This exception did not change other testers' builds, roles or notifications.
The correction is now included in shared TestFlight build 45. Record feedback
against the build actually installed—44 for the prior direct app or 45 after the
TestFlight update. Small scoped fixes can still use the phone-first workflow;
shared releases require explicit TestFlight distribution and unique numbers.

### Owner-selected CPL tester

The owner separately approved inviting one trusted CPL-focused participant
(alias **CPL-03**) after the App Store Connect permissions were explained.
The invitation was submitted with Marketing, only Fotty selected, and no
additional Create Apps, admin or signing access. Apple explicitly confirmed it
was sent on 28 August; the fresh user list shows Marketing / Resend Invitation
but labels scope **All Apps**, although Fotty was the only app in the chooser.
Do not claim that future-app restriction is verified. Edit App Access is disabled
for this pending user. After acceptance, verify/narrow app scope before adding
only that participant to Fotty Internal Smoke. CPL-03 is not yet in the eligible
TestFlight-user list.
Do not resend the account invitation or infer mailbox delivery/installation.

Focus: finding CPL matches, schedule/countdown clarity, startup, pause/resume
from the same control, audible unmute, ads obstructing controls, longer-session
recovery and a received TestFlight report. This does not certify rights, provider
availability or score coverage. The app remains full Fotty, not CPL-restricted.

## Outcomes to give a tester without coaching

1. Find something you want to watch, start it, pause and resume it from the same
   control. Explain what you do if the first source is not ready.
2. Save an upcoming match, leave the app, and find the match again. Explain why
   Home and My Matchday contain different things.
3. Set one match reminder intentionally. With the device locked, receive it and
   return to the right saved match without playback starting automatically.
4. Change appearance and check all tabs. Use your normal text/Zoom settings;
   on iPad, rotate and narrow the window.
5. If you play FPL, connect your own team, confirm its identity, ask about points
   and a transfer decision, then ask a follow-up. Explain which totals are
   official/provisional and whether a local plan changed official FPL.
6. Prepare and submit one clearly marked test report through TestFlight. The
   owner must confirm actual receipt under build 45.

For each: ask where they hesitated and what they expected. Classify the outcome
as independent / needed help / app failure / provider blocked / not attempted.
Do not convert a provider-blocked or unattempted task into a pass.

## Longer playback session

On a currently decoding source, aim for a 45–60 minute watch on each supported
form factor. Record actual duration; a shorter run remains a shorter run.

- Note selected broadcast number, start/end time and visible video progression.
- Pause for at least 30 seconds, then resume from the same control. No automated
  restart, unsolicited source switch or duplicate audio may occur while paused.
- Exercise a short, reversible network interruption and background/foreground.
  Distinguish provider failure from Fotty replacing a still-recoverable source.
- Test PiP only after real native handoff; lack of PiP on an incompatible embed
  is a known capability limit, not a failed universal-PiP promise.
- Close the player: no hidden/ticking audio or orphaned activity should remain.
- Record battery before/after, charging state and unusual heat qualitatively.
  Do not invent device-energy or crash-free metrics from a process hold.

No recordings of full broadcasts, raw media URLs, continuous video capture,
simulator or UI-test helper installation is needed.

## Evidence ledger

| Check | Evidence needed | Current result |
| --- | --- | --- |
| Build available | Apple shows 45 Testing in the existing group | Verified 2026-08-29 15:21 AST: Internal / Testing, Fotty Internal Smoke, two invitations; notes saved |
| iPhone update | Settings 45, launch, retained data, usable keyboard/layout | Not run; prior build-43 installations do not certify 45 |
| iPad update | Settings 45, launch, retained data, rotation/layout | Not run |
| iPhone playback | Actual duration, same-control pause/resume and recovery | Not run |
| iPad playback | Actual duration, same-control pause/resume and recovery | Not run |
| Reminder | Locked delivery, right destination, no autoplay | Not run |
| FPL trust | Named data state, official/provisional distinction, useful follow-up | Not run |
| FPL correction | Build 45, retained draft, replace/refresh/reopen and source toggle | Prior 44 install/launch and scoped stored-data retention pass; build-45 physical task taps remain open |
| Feedback | One received TestFlight test report for 45 | Not received/verified |
| Newcomer tasks | Independent outcomes and hesitation notes | Not run |

Record each real result with date, build, device/OS, participant alias, outcome
and a short redacted observation. Store only necessary evidence. Empty TestFlight
metric cells are unknown, not zero; installed does not mean exercised.

## Expansion gate and triage

The owner has explicitly selected CPL-03 as one additional trusted participant;
this is a scoped invitation, not evidence that the broader expansion gate passed.
Do not otherwise widen the group until the exact build passes the core iPhone/iPad paths,
one report is received, and known task-blocking app regressions are resolved.
Use the previous usable TestFlight build if a new app build blocks core tasks;
do not delete local user data. Worker rollback is separate from app rollback.

Prioritize lost data, wrong verified totals, hidden audio, crashes and unusable
controls first; then unreliable task completion; then clarity and visual polish.
The owner selects additional testers and any account-access changes explicitly.
