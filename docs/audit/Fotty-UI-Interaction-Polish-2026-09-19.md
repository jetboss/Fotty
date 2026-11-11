# UI interaction polish — 19 September 2026

Scope: first application of the Apple UI design standard, source-only. No new
navigation architecture, data policy, playback engine, assets or release.

## Screen contract

- **Home:** keep the approved sports artwork, badges, three-column phone grid,
  compact adjacent Watch action and existing large-text/iPad reflow. Make taps on
  branded controls visibly register without movement or a new loading delay.
- **Settings:** every actionable grouped row has the same visible pressed fill
  in both appearances. Informational rows, toggles and special controls keep their
  semantics; no new settings or routine explanatory text.
- **Search:** fixture and channel results share one grouped surface and a common
  12-point content inset. Do not nest a second card around channels.
- **Matchday:** consequential schedule-change/unavailable notes align with the
  card content and wrap. Preserve their wording, conditions and visibility.

This is a bounded correction to the existing design, not a new unapproved visual
direction. FPL navigation typography and replacing the custom root tab structure
need separate visual/lifecycle assessment; neither is changed here.

## Implementation and scope checks

- `FottyPressButtonStyle` supplies stationary, immediate feedback to explicitly
  opted-in Home controls, Home result information and shared Watch/reminder
  buttons. Its visual overlay cannot receive touches; disabled controls have a
  distinct appearance and do not display a pressed treatment. It adds no gesture,
  blur, timer, scale transition or animation. Button callbacks remain unchanged.
- Shared `MatchStartControls` consumers include Home, Search, Matchday,
  `LiveEventCard` and Match Hub. Source selection and player-owned controls are
  untouched. No whole-screen gesture or playback overlay was added.
- Settings styling is explicitly assigned to twelve row NavigationLinks, plus
  existing action rows. There is no section-wide button-style inheritance that
  would restyle toggles, backup controls or the owner-status gesture.
- Search owns the group surface; fixture rows receive the single outer inset and
  channel rows retain the card component's existing internal inset.
- Matchday groups only the existing conditional schedule notes and gives them
  the same horizontal inset as the card, plus bottom breathing room.

## Evidence and acceptance

| Surface/state | Intended/reference | Evidence identity | Result/open gap |
| --- | --- | --- | --- |
| Home and shared actions | Existing composition; immediate nonmoving feedback | Current source; scoped caller inventory | Source checked. Actual touch, scroll cancellation and device press feedback remain open. |
| Settings rows | Existing grouped settings, consistent press state | Current source; both theme tokens | Source checked. Physical navigation, toggle and press verification remain open. |
| Search mixed results | One aligned group | Current source | Source checked. Mixed result/large-text device visual review remains open. |
| Matchday notes | Match-content alignment, truthful uncertainty | Current source | Source checked. Rescheduled/missing-schedule device visual review remains open. |

### Local qualification

- Official Xcode 27, explicitly selected via `DEVELOPER_DIR`; no simulators.
- 137 focused Catalyst unit/render tests pass, zero failures/skips:
  `HomeDiscoveryTests`, `BetaUsabilityTests`, `MatchReminderTests` and
  `MatchdayJourneyTests`. The iOS Release compile also passes, unsigned.
- New render checks distinguish resting, pressed and disabled appearances while
  retaining the same label bounds; a palette regression checks that Settings'
  pressed fill differs from its group in light and dark.
- Independently reviewed source preserves action predicates, callbacks, reminder
  conditions, accessibility identifiers and layout insets. Masthead labels now
  explicitly include their padded rectangular tap area.
- Inspected offscreen Watch state renders in both appearances, normal/stacked
  match/channel examples and phone/wide-iPad composition samples. These show
  visible feedback without movement and preserved compact Watch placement.
- Inspection found an existing sample-clock mismatch: the Home fixture used a
  fixed schedule date but let its control use wall-clock time. The test now passes
  that same fixed date to the row. The isolated grid render also gets an explicit
  opaque dark background instead of misleading transparent compositing.
- After those test-harness-only corrections, all 38 Home tests pass again with
  refreshed component attachments. No application source changed after the
  passing 137-test and iOS Release gate.
- These Catalyst samples exercise layout branches, not physical iOS text scaling.
  They do not establish full Dynamic Type acceptance; that remains device work.
- The first compile rejected a test-only attempt to override Apple's read-only
  Reduce Motion environment value. The unsupported injection was removed before
  the passing run. No animation/scale/timer exists in the new feedback; actual
  accessibility-setting interaction remains open.
- All task-owned build/result directories and the 1.6 MB render review output
  were removed after inspection, including the failed test-build output. Final
  available disk space: 61 GiB. Existing caches and user artifacts were preserved.

Offscreen SwiftUI component renders are not a current full-screen iPhone/iPad
capture and cannot establish hit testing, gesture cancellation or decoded playback.
Jet iPad reports installed build 98 through CoreDevice, but the screenshot tool
could not access the device. No app was launched or replaced to obtain evidence.

## Apple grounding

Reviewed current [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
guidance, including its custom press-state, coherent control sizing and touch-area
recommendations. The documentation's structured JSON was used where the HTML
requires JavaScript. See also the project's
[UI design standard](../FOTTY-UI-DESIGN-STANDARD.md) and its dated Apple baseline.
These guide the design; they are not a claim of App Review certification.
