# Fotty 2.0.0 (90) — installed on both owner devices

2026-09-08. Owner authorized installation on Jelani's iPhone and Jet iPad.
The unlocked-device retry installed and launched successfully on both devices.
No TestFlight upload.

## Included

Optional, off-by-default kickoff-clash hints in Settings → Preferences, with
private-backup compatibility and unchanged saved matches/reminders. Includes
the existing adaptive iPad and app-wide UI polish. App/widget and project.yml
build numbers are aligned at 90; no project regeneration or feature rework.

## Evidence

- Preceding source checks: 78 focused unit tests, four Catalyst UI checks and
  unsigned generic-iOS Release compilation pass.
- This attempt: one fresh optimized signed Release artifact, strict nested
  signatures and app/widget version checks pass. No simulator.
- The initial iPhone install failed with CoreDevice error 4000 (disconnect); iPad install
  failed with error 3002/closed remote connection. Subsequent device queries
  confirm iPhone 2.0.0 (87), Jet iPad 2.0.0 (89), both passcodeRequired true.
- The one temporary build directory was trap-cleaned after failure; about
  48 GiB free. No uninstall, data reset, UI-test runner or TestFlight upload.

After the owner unlocked and connected both devices, one fresh signed build 90
was installed on Jelani's iPhone 15 Pro Max and Jet iPad Air 4. CoreDevice verifies
com.jelani.Fotty 2.0.0 (90) on each. Both launch successfully and survive their
30-second process holds. The retry's bounded build directory is also removed;
approximately 48 GiB free. No new feature edits or build-number increment on retry.

This verifies installation/startup, not live playback or every screen's visual
acceptance. The kickoff-clash control remains off by default; no owner settings,
saved matches or FPL identity confirmation were changed by automation.
