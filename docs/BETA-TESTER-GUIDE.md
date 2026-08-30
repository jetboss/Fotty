# Fotty closed beta — first-use check

Use one identified TestFlight build for each feedback round. The current data and
platform safety round uses **2.0.0 (45)** for **Fotty Internal Smoke**, verified
**Internal / Testing** at **2026-08-29 15:21 AST**. See
[its release record](releases/Fotty-2.0.0-45.md) for availability and saved tasks.
Build 43 is the prior installed shared baseline; build 44 was an owner-only direct
iPhone correction now consolidated into 45. Neither prior installation certifies
build 45 or establishes that feedback was delivered.

Use [the round-one acceptance ledger](beta/ROUND-01-ACCEPTANCE.md) to record
actual device/task outcomes and the longer playback session. The approved order
and remaining decisions are in [the next-phase plan](NEXT-PHASE-PLAN.md).

Install normal beta updates through TestFlight, including on the owner's devices.
Do not delete Fotty merely to update it; local preferences and drafts should remain
across an ordinary update. Direct cable installs are reserved for separately
requested debugging. Confirm the version/build in Settings after updating.

## Before inviting the next group

- Check supported devices: the current app requires iOS/iPadOS 26.4 or newer.
- Complete the existing-group acceptance first, then have the owner select 5–10 trusted internal testers with different device sizes, sports interests and FPL experience. This guide does not authorize invitations or role changes.
- Confirm the intended build is available to the group and feedback is enabled in App Store Connect.
- Ask one tester to submit a clearly labeled test report. Verify receipt under that build's TestFlight feedback before widening the group. Copying a report or opening a share sheet is not proof of delivery.
- Keep internal users' App Store Connect access limited to what their testing role needs. Do not grant administrator access just to test.

## What to test

Give these outcomes without explaining which buttons to press:

1. Find a match you want to watch. Start it, pause/resume it, then return to the app after a short interruption.
2. Save a match and find it again. Follow a team and explain what belongs in Matchday versus Home.
3. If you play FPL, connect your own team. Try pasting the full Points-page link. Check the name before confirming.
4. Explain which FPL points are confirmed, which are provisional, and whether a saved Fotty transfer plan changed your official team.
5. Report one confusing or broken experience, including what you expected and what happened instead.

For each task ask: **Where did you hesitate? What did you expect to happen?**
Log task-blocking failures and incorrect-data reports before cosmetic preferences.

## Recovery and accessibility checks

- Incorrect or nonexistent FPL ID: edit/retry without getting stuck; an unconfirmed team must not become the selected manager.
- Offline first use, slow team lookup, and switching away during lookup: no endless spinner or late response restoring the wrong team.
- Returning users: followed teams and saved matches remain; disconnecting FPL must not erase manager-scoped drafts/history.
- Large text, narrow supported iPhone, iPad rotation, keyboard dismissal and VoiceOver labels.
- Notification permission declined: app remains usable, and Settings explains how to change the permission.
- Help and report preparation work without the former website or homelab.
- Diagnostics start off, can be previewed, and are only included when chosen. Canceling share preserves the local draft and must not display “sent.”

## Current limits to explain to testers

- Broadcast availability depends on third-party providers. A live listing does not prove its video is playing; retry and source selection stay in Fotty.
- Live scores are intentionally Premier League-only. Other competitions may still have broadcasts.
- Match updates are generated while Home/Matchday fetches scores. They are not reliable background push alerts. Explicitly enabled match reminders and FPL deadline reminders can arrive with Fotty closed, subject to device settings. Saving alone is silent; closed apps cannot learn schedule changes.
- CPL is a dated published schedule, not a live programme guide. A channel listing does not confirm that a particular fixture is airing.
- FPL lineup/transfer changes are local drafts. Complete real changes in official FPL before the deadline.
- Preferences and drafts are on-device, not automatically synced to another device.

## Sending feedback

In Fotty, open **Settings → Report a problem**. Describe the problem, optionally
include diagnostics, preview the report, and choose **Copy report for TestFlight**.
In TestFlight, select Fotty → **Send Beta Feedback**, paste the report and submit it.
For a visual problem, use TestFlight's screenshot-feedback option when offered.
Manually installed testers can use **Share report…** to contact their inviter.

Apple documents [tester feedback](https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/)
and [internal testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).
