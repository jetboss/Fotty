# H1 resolved: row-local disclosure is safe for this placement

**Verdict:** H1 is resolved, with one small check to run on a device. Your plan is agreed, provided the three conditions below go into the diff. This is still a review of the plan, not of finished work. I only read the round-2 files; nothing was run.

## Why the mini player is safe

- **Where it lives:** `ViewingMiniPlayer` is mounted only through `.tabViewBottomAccessory` (`MainTabView.swift:323-325`). Its slot is the 78×44 `ViewingSurfaceSlot` (`ViewingExperienceView.swift:49`).
- **Rows can't reach it:** The tab content sits beside the media layer inside `ViewingSessionShell`, not around it (`MainTabView.swift:98`, `ViewingSessionShell.swift:20-31`). Changing a row's height inside Home's scroll view changes the content size, not the accessory's position. So the slot bounds `ViewingSessionShell` reads don't move, and the retained surface can't drift during a disclosure.
- **Expanded player:** `ViewingExperienceView` covers Home, and Home is made inaccessible and non-tappable underneath (`ViewingSessionShell.swift:22-23`). Its own animations (`ViewingExperienceView.swift:379-382`, `:399`, `:406`) already exist and aren't touched by this patch.
- **No outer animation:** Nothing in the full `SportsDashboardView` wraps the list or the coordinator state in an animation. The only `withAnimation` calls left are the `scrollTo` at `:566`, which already checks Reduce Motion, and the Save one at `:1752`, which you've agreed to remove.
- **Not yet animated:** The `StreamResolutionPanel` `.transition(.opacity)` (`StreamResolutionOverlay.swift:109`) never runs because nothing animates the change. It still appears instantly, which is correct for this patch's scope.

**Remaining hypothesis (not a blocker):**
- **Setup:** The tab bar shrinks on scroll down (`MainTabView.swift:322`).
- **Trigger:** Collapse a row while scrolled to the very bottom. The content gets shorter, so the scroll view pulls the offset up.
- **Possible effect:** The system may read that as scrolling and re-expand the accessory.
- **Already happens today:** Collapsing does this now without animation, so it isn't new. Just include it in the device check.

## Disclosure in the actual Home layout

`HomeScheduleRow` toggles in place, and "More details" opens the sheet through `onDetails` (`SportsDashboardView.swift:1357`). The rows sit in three kinds of container:
- plain VStacks inside `overviewMatchGroup` (`:1334-1346`)
- the two-column `HomeOverviewLayout` (`:1284`)
- `discoveryRow` cells, which are clipped by `HomeMatchGroupShape` and joined with negative top padding (`:1377-1392`)

An opacity insertion stays inside the clip, which a `.move` would not. A height change in one column only changes the overview's maximum height. So the plan holds: opacity insertion, a no-bounce snappy animation, `nil` under Reduce Motion, and resets with animations disabled.

## Three conditions before implementation

**1. Hero score transition must be keyed to the fixture.**
- `liveSpotlight(item)` is rendered without an `.id` (`SportsDashboardView.swift:1286`, `:1234-1246`). When a different fixture becomes the spotlight, SwiftUI reuses the same view, and the numeric roll would animate from the old match's score to the new one.
- The fix: put `.id(item.event.id)` on the score lockup, or only animate when the fixture ID is unchanged.
- Add a test for "spotlight swaps fixture → no transition".

**2. The spinner-only fallback still changes width unless the icon slot is fixed.**
- A small `ProgressView` is wider than a caption-size `play.fill` or `arrow.clockwise` (`MatchStartControls.swift:791-792`). Keeping the Watch/Retry text alone won't stop reflow.
- Give the icon a fixed, text-size-scaled frame in both states.
- Measure that the size is the same with and without the spinner at default, xxxLarge and AX3 text, alongside your measurement of the text footprint.

**3. Decide what happens to On Air.**
- `HomeOnAirSection` uses `.borderedProminent` and is disabled whenever `pendingEventID != nil` (`SportsDiscoveryViews.swift:1257-1261`). Its own Opening… state therefore gets the system's disabled look, which isn't full opacity, and it changes width (`:1247-1252`).
- Either bring it into the same contract (shared `PendingWatchLabel`, fixed footprint, pending shown at full opacity) or list it in the diff as explicitly excluded. Don't leave it unmentioned.

## Agreed as you stated it

- Pending is instant and full opacity, with "Opening broadcast" as the accessibility value.
- Pending buttons and row information stay disabled, so VoiceOver still reports them as dimmed. Rows stay readable through a style option that skips the 0.45 opacity, not by removing `.disabled`.
- Rows get static monospaced digits. Only the hero score gets a transition.
- No transactions on the player or the global catalog.

**Gap for the diff review:** Arena's `LiveEventCard` rows may also dim while a Watch is pending, through `fottyStreamLookupBusy`, but Arena's environment wiring isn't in the packet. Include it in the diff, or say Arena is out of scope.

No other blockers. Send the final diff.
