# Fotty 2.0.0 (73) — personalized Home private iPad candidate

Date: 2026-09-06. Status: installed and launched on Jet iPad as an optimized
Release build. The new Home entry point is visually present; hands-on preference
editing and filtered-catalog acceptance remain pending. Jelani's iPhone remains
on private build 70 and TestFlight remains build 55.

## Product change

- Home has one compact `Home interests` entry point. It reports whether the
  broad catalog or only saved interests are currently shown and opens the
  editor directly.
- Settings → Sports & Competitions groups the reviewed Premier League,
  Champions League, CPL, NBA, WNBA, MLB, NHL, NFL and other supported
  competition choices by sport. Favorite teams are managed from the same flow.
- `Only show my interests on Home` is opt-in. Existing users continue to see
  all sports until they enable it. When active, Home includes fixtures matching
  a favorite team or selected competition; it does not enable alerts.
- Full lineup and Search stay complete. A personalized empty state offers Edit
  interests and Show everything on Home instead of implying the catalog failed.
- If saved interests are empty or unavailable, filtering fails open to the
  broad Home and the persisted restriction is disabled where the state is
  observed.
- The encrypted private backup includes the Home choice. Older version-one
  backups without that field remain decodable and restore to the broad default.

## Verification

- The complete simulator-free Catalyst unit suite and generic iOS Release gate
  pass after the final source and compatibility-test changes.
- One signed optimized Release artifact installed only on Jet iPad. CoreDevice
  independently reports Fotty Sports Hub 2.0.0 (73), launches the normal app and
  shows its app and Live Activity extension processes.
- A fresh iPad screenshot shows the compact Home interests row with the truthful
  state `1 selection · showing all sports`; the preference did not silently
  alter the existing Home after upgrade.
- Owned DerivedData and screenshot directories were deleted. No simulator,
  device UI-test runner, TestFlight upload, provider/backend mutation or other
  device installation occurred. Approximately 62 GiB remained free.

## Remaining physical acceptance

On Jet iPad, open Home interests, choose Premier League, Champions League and
CPL, enable `Only show my interests on Home`, and return to Home. Confirm
unselected listings disappear, relevant live/upcoming fixtures remain, Edit
returns to the saved choices, and disabling the switch restores the broad Home.
Open Full lineup and Search while personalization is enabled and confirm that
unselected catalog events and cricket channels remain reachable. Remove the
last saved interest and verify Home returns to all sports. Repeat in Light mode,
large text and VoiceOver; this source/build evidence does not certify those
hands-on interactions.
