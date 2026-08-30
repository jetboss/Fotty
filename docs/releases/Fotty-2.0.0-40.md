# Fotty 2.0.0 (40) — readable countdowns and opt-in reminders

Status: installed on the owner's iPad only. TestFlight remains 2.0.0 (35).
The owner paused further work to discuss row density and live bookmarks.

Build 40 includes build 39's approved countdown, opt-in reminder, safe pre-start
playback, inline retry and notification-routing changes. It corrects the dimmed
upcoming team names found on the real iPad: future information is plain readable
content, not the label of a disabled button. Playback alone is timing-gated.
No normal provider control, playback recovery or theme preference is changed.

See `docs/audit/Fotty-Countdown-and-Reminders-2026-08-27.md` for behavior and limits.

## Qualification

- Final repeated suite: 181 passed, one optional HLS soak skipped, zero failures
  or runtime warnings. Actual Home-row light/dark/narrow renderings were inspected.
- Sequential normal Release, ReviewSafeRelease and signed Debug iOS builds pass.
  App/extension both report 2.0.0 (40); strict signatures and unchanged sorted
  source hashes were verified.
- Executable SHA-256:
  `d1d2beb2a41ee24b95f9e70c1e73f3c21f91124f4577d46c550f8274446a9c54`.
  Sorted source manifest SHA-256:
  `2a8f074cefb5fdc9ca9213c22ab473ea4bcb45e52e3954c25679b8dd4dfec43d`.
- Installed on the physical iPad and independently version-reported as 40.
  The argument-free 20-second launch hold passed. The owner interrupted before
  a further assistant-captured physical visual check. Real locked-device reminder
  delivery, notification-tap return and final layout acceptance are not certified.
- The single owned 1.1 GB build/test/render/preferences-copy tree was removed
  by its cleanup trap after the interruption. Absence was verified; no simulator,
  device UI-test helper, iPhone install, TestFlight upload or Git publication.

## Owner feedback after installation — discuss before changes

The owner objects to taller match cards and Watch moving below the names instead
of remaining beside them. The shared action stack was too broad, including live
rows. They also question visible bookmarks beside already-watchable matches.
Bookmarking saves a quick-return My Matchday entry, not playback availability;
that secondary action need not compete with Watch. Recommend compact side-by-side
live rows, countdown/bell for upcoming rows, and stacking only when width/text
requires it. No follow-up layout/bookmark edit is authorized by these questions.
