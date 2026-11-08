# Fotty 2.0.0 (98) — private CS playback integration check

Installed 2026-09-13. Status updated 2026-09-14: **CS2 playback, controls and PiP owner-accepted**.
Owner authorized the private device gate after the source-only CS audit.
No iPhone installation, TestFlight upload or tester changes are authorized here.

## Included corrections

- Correct native-versus-web routing for CS endpoints, shared with MultiView.
- Retry direct CS HLS natively once rather than inventing a web fallback.
- Prevent late native validation from taking over after switching or closing.
- Preserve responsive native controls with deferred PiP commands and teardown
  of discarded playback surfaces.
- Find exact matches through the advertised Live catalog when the sport catalog
  is absent/unavailable; reject contradictory reused fixture/video IDs.
- Keep CS1/CS2 labels and retain private source attribution across native handoff.

See `docs/audit/Fotty-CS-Playback-Integration-2026-09-13.md` for the detailed
findings and limitations. This gate changes only app/extension build numbers
from 97 to 98; no further functional code changes are made.

## Evidence

- The preceding source gate passed 181 focused Catalyst tests, zero failures,
  with one explicitly opt-in live HLS soak skipped; generic iOS Release passed.
- Fresh preflight identified connected/unlocked Jet iPad, iPad Air 4, and its
  installed build 97. The saved CS module flag was read as enabled. No app data
  was reset; the temporary preference copy was removed immediately.
- Signed optimized iOS Release compilation and strict nested signature checks
  passed. App and Live Activity extension both report 2.0.0 (98).
- CoreDevice confirms the in-place installation and launch of build 98 on Jet
  iPad only. Home rendered in landscape; the saved CS enabled flag remained true.
- PID 4806 stayed present over the 54-second check from 03:03:54 to 03:04:48 UTC
  on 14 September (13 September local). Only the existing build-95 watchdog was
  listed before/after; no new incident appeared in this observation window.
- The build directory, temporary screenshot and targeted preferences copy were
  removed. Free disk remained 70 GiB. No UI-test helper was installed, simulator
  launched, app data reset or TestFlight upload performed.

## Owner acceptance — 2026-09-14

The owner reported that a match plays, explicitly identified the selected source
as CS2, then answered “all work” to the focused check of pause/resume, reopening
Sources and switching back to StreamEx. These user-observed checks pass for the
tested CS2 session on Jet iPad build 98. This closes the reported frozen-controls
reproduction for that session; it is not blanket qualification of every CS source.
The exact fixture, native/web ownership and elapsed playback duration were not
independently captured. Do not infer those from the position label CS2.
The owner subsequently confirmed “pip works”; PiP is now owner-accepted too.
Lock/unlock behaviour and a timed background soak were not separately reported.

## Remaining physical acceptance

Remaining coverage: lock/unlock and a timed background soak, another CS variant,
source changes during loading, close/reopen, and both native/web delivery where
available. These were not separately confirmed. No TestFlight promotion follows
automatically from private acceptance.
