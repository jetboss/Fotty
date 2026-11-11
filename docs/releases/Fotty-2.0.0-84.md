# Fotty 2.0.0 (84) — native compact Home correction

2026-09-08. Installed and launched on Jelani's iPhone only. TestFlight remains 81.

## What changed

- Home-scoped precise, Dynamic Type-aware typography replaces semantic font
  bucket substitutions for the wordmark, tile titles, interests and team names.
- Smaller equipment and badges; equal measured tiles without reserved empty
  title lines; three phone columns at most, including Pro Max, and adaptive iPad
  capacity. Larger text can still reduce the number of columns.
- A lighter Fotty header and plain Search button. Sports overflow is a header
  action only when needed on phones, not a full extra row above the fixtures.
- Interests, reminders, side-aligned Watch, existing badges and meaningful
  freshness warnings remain. No playback/data-classification code changed.

## Evidence

- Focused BetaUsabilityTests pass after the final column correction, including
  a native-rendered phone grid height budget and the 398-point Pro Max width.
- Large-text and clipping Catalyst UI audits pass. Navigation initially exposed
  redundant iPad overflow; its corrected rerun passes.
- Signed optimized Release build and strict nested signatures pass. CoreDevice
  confirms 2.0.0 (84) installed and launched on Jelani's iPhone.
- Actual iPhone Mirroring inspection of intermediate build 83 caught four
  columns. Final build 84 visibly has three equal columns and three complete
  upcoming fixture rows on the initial screen. Sports overflow opens, selection
  returns to filtered Home, and Cricket shows the CPL schedule with badges.
  Restored All sports after inspection; interests were not edited.

## Boundaries and remaining checks

Owner aesthetic acceptance remains pending. This is an actual Home/shared-row
correction, not implementation of every FPL/Settings/iPad concept. The separately
reported youth/Champions League classification issue is not fixed here. No live
stream, PiP, reminder creation or physical light-mode test was performed.

No uninstall, data reset, other-device install, TestFlight upload, provider
deployment or Git history change. Owned temporary build/test output was removed.
