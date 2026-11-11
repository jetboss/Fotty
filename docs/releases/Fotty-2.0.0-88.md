# Fotty 2.0.0 (88) — private iPad UI polish review

2026-09-08. Owner-requested update installed and launched on Jet iPad,
iPad Air (4th generation), only. No TestFlight upload or iPhone install.

## Included polish

Build 87's app-wide visual changes plus the verified finishing pass: shared
Matchday reasons once per section, expandable kickoff-clash details, a compact
Settings title with working destination navigation, rounded lazy search groups,
and clearer FPL setup with optional help and unchanged confirmation safeguards.

## Evidence and boundaries

- Fresh signed optimized iOS Release build and strict nested signature check pass.
- CoreDevice confirms com.jelani.Fotty version 2.0.0, bundle version 88, installed
  on the named iPad. Launch succeeds.
- The preceding source gate passed 108 focused usability/FPL trust tests, generic
  iOS Release compilation and five Catalyst navigation/accessibility checks.
  This deployment changes only the app/widget build number, not feature code.
- No uninstall, data reset, preference change or device UI-test runner install.
- Temporary build products removed after install; approximately 48 GiB free.

Owner iPad visual acceptance is pending. Review Home, Matchday, FPL and Settings,
including search and Settings back navigation. Installation/launch evidence is
not proof of real playback or every screen's visual quality. Any FPL identity
confirmation remains the owner's decision. iPhone remains on build 87 and the
recorded TestFlight baseline remains 81.
