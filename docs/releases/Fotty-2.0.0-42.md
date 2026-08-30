# Fotty 2.0.0 (42) — internal TestFlight consolidation

Date: 2026-08-28

Status: **Testing — available to Fotty Internal Smoke**, verified in App Store
Connect at **06:18 AST on 2026-08-28**. Upload/processing, the owner-approved
encryption declaration, saved testing notes and existing-group assignment are
complete. The group still has two testers. This confirms availability, not
installation or physical-device acceptance of build 42.

## Scope and version

- The owner requested updating TestFlight, then discussing the next step only.
- Normal `Fotty` / `Release`, internal-only, existing **Fotty Internal Smoke**
  group. Preflight verified its two testers, feedback enabled and manual Xcode
  build assignment. No membership, roles or group settings change.
- App Store Connect's latest upload was 35. Build 41 already reached the
  owner's iPad, so `tools/set-version.sh 2.0.0 42` allocates a fresh number.
  The app, extension and `project.yml` advance together. No feature code changes
  are part of this packaging task.
- No external testing, App Store submission, direct-device installation,
  simulator, server deployment or Git publication. Subsequent product planning
  is discussion-only until separately approved.

## Changes since TestFlight 35

- Compact all-sports Home with activity/next-start tiles, mixed Now & next,
  coming-up events and a full lineup on Home's own navigation stack.
- Team badges and equipment icons; uniform sport tiles, with all sports shown
  inline on iPad. FPL stays in its dedicated section.
- Settings → Appearance offers Dark (default), Light and System. Normal
  Settings no longer exposes Engineering.
- Cricket separates All cricket, CPL and Channels. The CPL schedule has dated
  provenance; a channel listing does not invent a match's broadcast coverage.
- Provider controls retain their taps, pause/resume state and deliberate pause
  protection. Fotty's fallback controls remain bounded at the upper right.
- Inline Starts in countdowns replace premature broadcast actions. Source-backed
  playback attempts become available two minutes before start; failed resolution
  stays inline with Retry instead of opening an empty player.
- Explicit five-minute local reminders also save the match in My Matchday.
  Saving alone stays silent, cancelling a bell keeps the save, and removing a
  saved event cancels its reminder. Notification taps return without autoplay.
- Watch is beside names/badges on ordinary rows. Save/Remove is in the native
  long-press menu and accessibility actions, without a permanent live bookmark.
  Narrow/accessibility layouts may stack, with full-width explanations.

## What to Test

All-sports Home, compact match rows, optional Light mode, playback controls,
countdowns and opt-in reminders.

1. Check Settings reports 2.0.0 (42). Confirm your saved matches, followed teams,
   FPL team and appearance preference survived the update.
2. Explore All sports, a sport filter, See all and Cricket / CPL / Channels.
   Check badges, equal sport tiles and Watch beside team names on iPhone/iPad.
3. Long-press a match to save it, find it in My Matchday, then remove it. Saving
   alone must not ask for notification permission.
4. On an upcoming match, check Starts in and explicitly enable Remind me.
   Test the five-minute alert with the device locked; tapping it should return
   to the saved match without starting playback. Cancelling the bell keeps the
   match saved; removing the match cancels its reminder.
5. With a working feed, pause and resume using the same provider control. Check
   unmute, source selection, interruption/return and that deliberate pauses do
   not switch or restart a stream.
6. Try Settings > Appearance: Light, Dark and System. Check all tabs, iPhone
   Display Zoom/large text, iPad rotation and Coach keyboard dismissal. Send
   device/build, expected behaviour and actual behaviour using TestFlight's
   Send Beta Feedback.

Known limits: provider availability varies; live scores are Premier League-only.
CPL schedule information is a dated snapshot, not a live programme guide.
Local reminders cannot learn reschedules while the app is closed; notification
permissions and Focus can delay/silence them. FPL plans do not change official
FPL. Preferences and drafts are device-local. Preparing/copying a report inside
Fotty does not submit feedback automatically.

## Qualification and provenance

- Before the version-only change, the source/config/test manifest matched the
  qualified build-41 fingerprint exactly:
  `4472f5191f9220cfa70284d0c6adeda8f050906612f58837013c3f54d9491230`.
- Reused [build 41's exact-source evidence](Fotty-2.0.0-41.md): 184 unit passes,
  one optional HLS soak skipped, zero unit runtime warnings; two scoped Catalyst
  interaction passes with two beta-Mac main-thread warnings. Normal Release,
  ReviewSafeRelease and signed Debug generic-iOS builds passed. The iPad launch
  and portrait inspection are prior build-41 evidence, not build-42 installation
  or real reminder/transport touch certification.
- Build-42 source/config/test fingerprint:
  `a225ebe3b1c45621d234c15c114c0279d23aca772d944b6b89580ce9ac07c54b`.
- Release source/config fingerprint (app, extension, Xcode project, `project.yml`
  and internal export plist; excluding `.DS_Store`):
  `b9995cf937bdc8d4ef14992c5204e35c9bd95d6ab3ec79395707ed8306d10d72`.
- Project/export plist lint and release-owned whitespace checks passed. Xcode
  27.0 (27A5237l), automatic signing, generic iOS, two jobs, one temporary root;
  the three provider API-key build settings are explicitly empty.
- The fresh optimized normal Release archive succeeded without warnings/errors
  in its log. App and extension both report 2.0.0 (42), their expected bundle
  identifiers and minimum OS 26.4; strict signatures verify. Archived provider
  API-key values are empty, compiled AppIcon assets are present, and both source
  fingerprints remain unchanged after archive. Normal Release explicitly uses
  `FOTTY_FULL_ACCESS`, not `APP_REVIEW_SAFE`.
- Archived app executable SHA-256:
  `94bef83b6ec05441e4c452ff46404f1dce6c1ba7228c1bd500b5c19e04037dd9`.
- Xcode export/upload returned exit 0, **Upload succeeded** and
  **EXPORT SUCCEEDED** at 00:01:49 AST. Its final state was **Uploaded package is
  processing**. This is accepted upload evidence, not tester availability.
- A fresh App Store Connect read at 00:03 AST showed build 42's upload as
  **Complete**, internal-only eligibility and **Missing Compliance**, without an
  assigned group. [Build 42](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/ac66eafe-72a9-4713-aa5d-6d903ce45dff)
  had finished processing; no rebuild or repeat upload was needed.
- The declaration asks about proprietary or separately implemented standard
  encryption algorithms. The source check found no custom crypto implementation
  or import, and the archived app links Apple/system frameworks and Swift
  libraries only. Recommended answer: **None of the algorithms mentioned above**,
  as for build 35. This is consistent with [Apple's guidance for built-in
  encryption](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations?changes=_7__7&language=objc);
  it does not claim that network traffic is unencrypted or settle any other
  reporting obligations. The owner explicitly approved submitting this answer,
  the notes above and assignment to the unchanged two-tester group.
- At 06:15 AST, the approved radio choice was selected and Save clicked. Apple
  redirected to sign-in before any saved/Ready to Test confirmation could be
  read. No alternate connected browser was available. After the owner signed in,
  a fresh read confirmed the declaration was still missing; the approved answer
  was resubmitted once and **Ready to Test** verified.
- The six What to Test tasks and known limits above were saved in English
  (U.K.); App Store Connect confirmed **Saved**. Only **Fotty Internal Smoke**
  was selected in the build-42 assignment dialog. The resulting build detail
  showed one internal group with its unchanged two testers. The builds page
  then showed **Internal / Testing**, assigned to that group, at 06:18 AST.
  No tester, account role, feedback setting or automatic-distribution setting
  was changed. This is not proof of email delivery, installation or feedback
  receipt; those remain separate tester outcomes.

## Remaining acceptance and resources

Confirm installation/version and preserved data through TestFlight on supported
iPhone and iPad. Physical long-press/bell taps, locked-device reminder delivery
and tap return, current provider transport, appearance persistence and large-text
interaction need their own evidence. One received TestFlight feedback report is
still required before widening the beta.

Preflight and post-upload free disk: **40 GiB**. After upload succeeded, the
cleanup trap removed the one **314 MB** DerivedData/archive/export/log root;
the separately generated **576 KB** Xcode distribution-log bundle was removed
too. Both paths were verified absent. Only small source/release records remain.
The dirty old-ancestry checkout remains uncommitted and must not be pushed.
