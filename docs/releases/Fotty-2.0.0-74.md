# Fotty 2.0.0 (74) — three-day personalized Home private iPad candidate

Date: 2026-09-06. Status: installed and launched only on Jet iPad as an
optimized Release build. Jelani's iPhone remains on private build 70 and
TestFlight remains build 55.

## Product change

- When `Only show my interests on Home` is active, Home shows selected live
  fixtures first and then the next 72 hours of selected fixtures. Upcoming rows
  are chronological and capped at three on iPhone or four on iPad.
- The personalized section is labeled `Your next 3 days` or `Next 3 days`, with
  an explicit message when no selected fixture is listed in that window.
- The shared catalog retention boundary is now 72 hours, so day-three fixtures
  are not discarded before Home can present them. Relative kickoff copy uses
  the same boundary.
- The broad Home remains intentionally compact: its featured window is still
  six hours, its later section remains capped at two rows and its prior 48-hour
  later boundary is explicit. Full lineup and Search remain complete within the
  retained provider catalog.
- This does not invent an official schedule. A future fixture can appear only
  if the active provider catalog or an existing reviewed merge supplies it.

## Verification

- The complete simulator-free Catalyst unit suite and generic iOS Release gate
  pass on final source. Regressions cover the exact 72-hour catalog edge, the
  72-hour personalized projection, chronological order, the three/four-row
  device limits, and preservation of the broad Home's 48-hour later boundary.
- One signed optimized Release artifact installed and launched only on Jet
  iPad. CoreDevice independently reports Fotty Sports Hub 2.0.0 (74), and both
  the normal app and Live Activity extension remained running through the final
  process check.
- A fresh iPad screenshot shows `4 selections · showing only yours`, a selected
  CPL live fixture and the new `Next 3 days` heading. The temporary screenshot
  and all owned DerivedData were deleted; approximately 61 GiB remained free.
- No simulator, device UI-test runner, iPhone installation, TestFlight upload,
  provider mutation or backend mutation occurred.

## Physical acceptance

The owner already confirmed on build 73 that selecting Premier League,
Champions League and CPL with the Home-only switch removes unrelated listings
and preserves a relevant fixture about one day away. On build 74, scroll below
`Next 3 days` and confirm any provider-listed day-two/day-three selected fixture
appears in kickoff order, no more than four upcoming rows appear on iPad, and
See all still opens the complete lineup. Disable the switch and confirm the
broad Home remains compact. A day-three item cannot be physically certified
until the current provider catalog actually supplies one.
