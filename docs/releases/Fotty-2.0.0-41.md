# Fotty 2.0.0 (41) — compact match actions

Status: installed and visually checked on the owner's iPad. TestFlight remains
at the last verified 2.0.0 (35); this build has not been uploaded.

## Change

The owner approved restoring the compact layout after build 40 made match rows
taller. Home, full-lineup and My Matchday rows now put team information/badges
on the left and Watch on the right. A measured layout falls back to stacking
only for insufficient width or accessibility text; it does not duplicate
stateful countdown/reminder controls to test alternative layouts.

Save/Remove from My Matchday is in the native long-press menu and accessibility
actions, not a permanent bookmark beside Watch. Upcoming countdowns and opt-in
reminders remain visible. Help and optional setup guidance explain the menu.
Saving alone stays silent; opt-in reminders still save the event, bell cancellation
keeps it saved, and removing the saved match revokes its reminder.

Reminder outcomes, notification-settings guidance and failed-lookup explanations
retain the full row width. Compact channel rows say Watch (accessibility: Watch
channel), and a failed lookup has Retry plus its explanation. Two-minute playback
guards, provider controls/recovery, stored data and theme preferences are unchanged.

## Verification

- Final complete Catalyst unit suite: **184 passed**, one optional HLS soak
  skipped, zero failures/runtime warnings. Includes the existing timer, source,
  reminder-race, permission, routing, FPL and playback policy checks.
- New layout checks assert that actual Home, lineup and channel Watch buttons
  stay on the right and normal test rows remain below 150 points at 320/375/820
  widths in Light/Dark. Future states, long names and accessibility fallback
  are also rendered and visually inspected. These are component/Catalyst checks,
  not physical iPhone or Dynamic Type certification.
- Two final scoped Catalyst UI tests pass: Home sport filtering/full lineup,
  silent context-menu save, saved Matchday return/removal, and cricket-channel
  save/return with clipping/description audits. The beta Mac reports two
  main-thread runtime warnings during those UI runs; the unit suite has none.
- Initial pixel measurement wrongly included gold LIVE text; it now detects
  continuous button fill, and the repeated suite passes. Initial native-menu
  queries used SwiftUI IDs/labels; captured hierarchy/screens showed NSMenu's
  title identifiers, and the corrected test exercises the actual menu items.
- Sequential normal Release, ReviewSafeRelease and signed Debug iOS builds
  pass. App and extension both report 2.0.0 (41), and both strict signatures
  verify. The sorted source/config/test fingerprint is unchanged across the
  final build gate.
- Signed app executable SHA-256:
  `1f7edbd1b1757adc943794d6ab1587276d41d6f04f284c3938bfed9ddb598e38`.
  Sorted source manifest SHA-256:
  `4472f5191f9220cfa70284d0c6adeda8f050906612f58837013c3f54d9491230`.
- The exact signed app installed on the physical iPad Air 4, independently
  reported 2.0.0 (41), and passed an argument-free 20-second launch hold.
  The 1640×2360 portrait capture shows three Now & next rows with Watch to
  the right, no permanent bookmarks, intact basketball flags/baseball badges,
  and two future countdown/reminder rows. The masthead and status bar do not
  overlap in this captured Home state. No physical tap is inferred from it.

## Boundaries

Only the normal iPad app is authorized for physical diagnostics. No simulator,
physical UI-test helper, iPhone install, TestFlight upload, tester change, Git
publication or new API/provider polling is included. Real iPad long-press/bell
touch, locked-device reminder delivery and notification-tap return need their own
interaction evidence; a process hold or screenshot is not a substitute.

The cleanup trap removed the single **1.4 GB** DerivedData/build/test/capture tree,
including failed-run recordings and all preview/device screenshots. Its absence
was verified; free disk returned to **40 GiB** (40 GiB before the gate). No temporary
app process remained. Installed iPad software and source/release records are kept;
the removed build products can be regenerated.
