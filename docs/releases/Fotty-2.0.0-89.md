# Fotty 2.0.0 (89) — adaptive private iPad layout

2026-09-08. Installed and launched on Jet iPad (iPad Air 4) only, following the
owner's explicit approval. iPhone remains 87; recorded TestFlight baseline 81
is unchanged. No shared release or tester changes.

## Changes

- Full-width Home, Matchday and Search with two-card rows in wide windows.
- Balanced tablet sports rows; narrow-phone overflow and readable labels remain.
- Side-by-side Settings groups and FPL summary/workspace, using actual window
  width. Narrow windows and accessibility text sizes retain a stacked flow.
- Full hit target for FPL workspace tabs; compact phone tiles keep their existing
  height limit without smaller text or artwork.

No playback, fixture, FPL scoring, paid usage, consent or saved-interest rules
changed. No uninstall, data reset or device UI-test runner.

## Verification

- Final combined Catalyst run: 142 usability/discovery/FPL-trust tests pass,
  zero failures or skips. Thirteen distinct Catalyst navigation/accessibility
  journeys pass across the candidate, including actual wide-to-narrow resizing
  and preserved FPL tool state. No simulators.
- Generated competition data, five provider identity vectors and whitespace
  checks pass. UI summaries retain the previously recorded generic main-thread
  runtime warning; this is not a measured performance improvement.
- Fresh optimized iOS Release compilation and strict nested signatures pass;
  app and widget both report 89. CoreDevice verifies the exact installed app as
  com.jelani.Fotty 2.0.0 (89). Launch and a 30-second process hold pass.
- Actual 2360×1640 Jet iPad landscape screenshot confirms normal full-width
  Home margins, balanced five-plus-five sports and two-column fixture cards,
  retaining badges and side-aligned Watch buttons.
- The single bounded validation directory, build products, result bundles and
  temporary screenshots were trap-cleaned after verification; about 48 GiB free.

Remaining physical acceptance: Matchday, Settings/Notifications, FPL and narrow
windows/light mode/large text. FPL identity confirmation is not bypassed.
The screenshot's football-fixture verification warning remains truthful;
fixture service availability and real playback were not tested in this UI gate.
Detailed evidence: `docs/audit/Fotty-iPad-Layout-2026-09-08.md`.
