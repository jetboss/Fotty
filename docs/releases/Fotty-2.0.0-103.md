# Fotty 2.0.0 (103) — private MultiView video-first iPad candidate

Installed 2026-09-19. Status: **private Jet iPad acceptance candidate**.
The owner authorized the MultiView correction and automated physical verification.
No TestFlight upload, iPhone install, tester change, backend deployment, commit or
Git publication is included.

## Included work

- Replace two tall equal web-player columns with true 16:9 playback viewports.
- Default wide iPad windows to Focus: one 821 × 461 point primary feed and one
  visible 352 × 198 point secondary feed on the tested 1180 × 820 window.
- Make either numbered panel a 44-point promotion control and retain Equal layout
  as an explicit alternative.
- Preserve independent Source and Audio controls for both feeds.
- Extend Fit/Fill to browser-backed video without navigating or rebuilding the
  selected source. Fit remains the safe default so edge scoreboards are visible.
- Respect Reduce Motion when switching layout or focused panel.

## Verification evidence

- The complete simulator-free iOS gate passes after the final source and test
  changes, including executable WebKit monitor coverage for contain-to-cover
  content-mode changes.
- A physical Jet iPad UI journey opens two current catalog matches and verifies:
  focused/equal geometry; both 16:9 viewports; panel promotion; web Fit/Fill/Fit;
  independent Source 2 selection on both panels; audio ownership transfer; and a
  final 12-second two-panel stability hold.
- A signed optimized Release builds, installs in place and launches. CoreDevice
  reports `com.jelani.Fotty` 2.0.0 (103) and a running app/extension process.
- The only listed Fotty crash report is the previously retired 13 September file;
  no fresh build-103 crash file is present.

## Boundaries and cleanup

The physical test establishes layout geometry and control/state behavior. It does
not substitute for owner preference on the Focus composition, human audio-quality
judgment, portrait/compact-iPhone acceptance or a long provider soak. Fotty's UI
test runner is removed after the journey. All bounded build, result and screenshot
output is removed after documentation; the installed Release app and its existing
container remain.
