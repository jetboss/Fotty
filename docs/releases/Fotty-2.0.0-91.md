# Fotty 2.0.0 (91) — private Jet iPad deployment

2026-09-08. Owner requested installation on Jet iPad only. No iPhone installation
or TestFlight upload is authorized by this deployment.

## Included

The verified Home clock/section fix: current fixtures and upcoming countdowns
stay consistent; identified lazy rows preserve section membership and adapt to
window width; normal foreground catalog checks are silent and bounded. Genuine
fetch, partial-catalog and CPL-authority warnings remain available.
See `docs/audit/Fotty-Home-Clock-2026-09-08.md`.

App/widget build numbers are synchronized at 91 in the active Xcode project and
XcodeGen manifest. Marketing version remains 2.0.0. No feature edits during this
deployment, no project regeneration and no production preference changes.

## Qualification and delivery

- Source checks: 137 focused units, six Catalyst UI checks (including the
  strengthened kickoff/resize/navigation journey) and unsigned iOS Release pass.
- Preflight: Jet iPad Air 4 is connected, unlocked, and reports installed build
  90. Approximately 48 GiB free on the Mac.
- Optimized signed Release app and widget both report 91 and pass strict
  signature verification. CoreDevice confirms 2.0.0 (91) installed on Jet iPad.
  Launch and the 30-second process hold pass.
- Actual portrait Home at 20:26 shows Cricket “1 on now” and the 19:00
  Guyana Amazon Warriors / Antigua & Barbuda Falcons fixture once, with Watch
  and a full-width card. The old future countdown and routine stale-catalog
  banner are absent. No stream was opened, so this is not decoding evidence.
- Reuse one trap-cleaned temporary build directory; no simulator or device
  UI-test runner. Physical match-time/foreground/rotation acceptance is distinct
  from installation and a startup hold.

Jelani's iPhone remains on build 90; internal TestFlight remains 81. The existing
youth/UCL labeling seen in upcoming fixtures is outside this deployment's scope.
The owned 303 MB deployment directory, including the screenshot, was removed
after verification. Approximately 48 GiB remains free; no user data was removed.
