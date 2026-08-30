# Fotty 2.0.0 (39) — countdowns and opt-in reminders

Status: installed iPad diagnostic checkpoint, superseded by the build-40
readability correction. Not uploaded; TestFlight remains 2.0.0 (35).

## Changes

- Inline scheduled-start countdowns, with second precision in the final five
  minutes and a source-backed play attempt from two minutes before the start.
- Device-local five-minute reminders, explicitly enabled per match. Opt-in
  saves the event to My Matchday; bookmarks alone stay silent. Cancel the bell
  without unsaving, or unsave to cancel both.
- Notification return to the matching saved My Matchday row without autoplay.
- Inline not-ready retry, no empty player, guards against premature lookup,
  time-zone-stable triggers, reschedule/cancellation reconciliation, request
  de-duplication and protection from late permission/system responses.
- Updated native help. No new API, stream probes, paid service or model usage.

See `docs/audit/Fotty-Countdown-and-Reminders-2026-08-27.md` for the full behavior,
tests, resource guardrails and remaining notification-delivery limits.

## Qualification

- Final-source suite: 180 unit tests passed, one optional HLS soak skipped,
  zero failures/runtime warnings. Normal Release, ReviewSafeRelease and signed
  Debug generic-iOS builds passed sequentially in one DerivedData directory.
- App/extension 2.0.0 (39), strict signatures and unchanged sorted source hashes
  were verified. Signed executable SHA-256:
  `97e41f351706cd74499c3e6ff9d27cf5e6e853b0c63a1c4ae18def01f80060f0`.
- Installed on the physical iPad Air 4; CoreDevice independently reported 39.
  An ordinary argument-free launch survived 20 seconds. The diagnostic helper
  initially rejected CoreDevice's wired `connected` state; it now accepts that
  state while retaining physical-only, lock-state and installed-app checks.
- The real portrait screen showed Starts in / Remind me on future Fight events
  and Watch on a current listing. The masthead was correctly below the status
  area in this fresh launch. No saved-match preference was present, so no real
  reminder target was available for a notification-return test.
- Physical inspection caught dimmed future names: a disabled row button had
  dimmed its entire label. Build 40 replaces that with plain, fully readable
  information and keeps the countdown/play controls separate. Build 39 is a
  checkpoint, not the final visual acceptance candidate.
- Real bell interaction, locked-device delivery and notification-tap return
  are not claimed. No simulator, device UI-test helper, iPhone install or upload.

Build 40 reuses the same temporary output tree; cleanup is recorded there.
