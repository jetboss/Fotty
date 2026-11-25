# Fotty 2.0.0 (82) — private calm-Home UI test

Date: 2026-09-08. Installed on Jelani's iPhone only; not uploaded to TestFlight.

- Compact Home header, interests control and shared match rows; badges, side
  Watch actions and opt-in reminders remain.
- Contextual freshness warnings with optional check-time details. CPL notices
  follow the displayed events; Retry alone does not make stale data fresh.
- The broader FPL/Settings/iPad concept is not included as native changes.

The preceding batch passed six Catalyst UI checks, focused catalog/usability
tests and an unsigned generic-iOS Release compile. This deployment additionally
passed a signed optimized Release build and strict nested signature validation.
CoreDevice confirms version 2.0.0, build 82 on Jelani's iPhone (15 Pro Max).
Installation was in place, without uninstalling or resetting the app container.
Automatic launch was denied because the phone was locked; owner visual and
functional acceptance remains pending.

TestFlight remains build 81. No other device, simulator, upload, service or Git
history change. Task-owned build output was removed by the cleanup trap.

## Owner checks

Check Home spacing, full team names and badges; Watch beside the names; interests
filters and reminders; and optional update details when a real warning appears.
Repeat in light mode and with larger text if used.
