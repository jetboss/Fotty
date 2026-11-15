# Core-UI motion polish: review of the four proposals

**Verdict:** I agree with the direction, but it needs changes before implementation. I'm not approving any finished work; this is a design and engineering discussion. I only read the frozen packet. I ran no tests, builds or devices, and smoothness on a real device is still unproven.

The biggest problem is in the Watch tap itself, and the brief doesn't mention it: at the moment of the tap, rows dim. Fix that first, inside proposal 2. Proposals 1 and 4 are fine with small changes. Proposal 3 should be narrowed. The Save/filter cleanup should go further than adding a Reduce Motion check.

## Confirmed defects (from reading the source)

**D1. The pending Watch button shows as disabled, and the team names in every playable Home row fade to 45%.**
- **How it happens:** At tap, `resolutionMessage` is set right away (`WatchTapAcknowledgementTests.swift:52-53`). That makes `fottyStreamLookupBusy` true (`SportsDashboardView.swift:160`). Every `.disabled(streamLookupBusy)` then picks up `FottyPressFeedback`'s `.opacity(isEnabled ? 1 : 0.45)` (`Components.swift:437`).
- **What the user sees:**
  - The tapped "Opening…" capsule itself is drawn at 45% (`MatchStartControls.swift:534`, `:709`; hero at `SportsDiscoveryViews.swift:815`).
  - In `HomeDiscoveryRow` and `HomeScheduleRow`, the whole team-name and badge button is disabled the same way (`SportsDiscoveryViews.swift:554`, `:1063`). Every playable row's names fade at once.
  - The comment at `:566-567` says not to dim names, but that only covers the future-fixture branch.
- **Repro:** Open Home with two or more live rows and tap Watch on one. The source says the pending capsule and all live-row names render at 0.45 until resolution finishes.
- **Why it matters:** It's an all-at-once flash at exactly the moment we're trying to make smooth. It also lowers text contrast.

**D2. The width change from "Watch" to "Opening…" can rearrange the layout mid-tap.**
- **Rows:** The compact action uses `.fixedSize(horizontal: true…)` (`MatchStartControls.swift:528`). `MatchRowLayout` re-measures the ideal action width (`:212`, `:222-230`, `:243`). When a row is near the `fitsBeside` limit, the row switches from side-by-side to stacked when tapped.
- **Hero:** It uses `ViewThatFits` with a fixed-size footer (`SportsDiscoveryViews.swift:719-726`). It can fall back to `stackedFooter` and change the card's height.
- **Also affected:** "Retry" and the alternate titles change width too.
- **Missed site:** `HomeOnAirSection` has its own copy of the label and doesn't use `PendingWatchLabel` (`:1247-1252`). A fix in `PendingWatchLabel` won't reach it.

**D3. Row scores aren't monospaced.**
- `LiveEventCard.swift:215` has no `.monospacedDigit()`.
- `HomeDiscoveryRow` puts the score and the live minute in one string (`SportsDiscoveryViews.swift:402`) and renders it without monospacing (`:592-597`). The minute tick makes the line jitter in width.

**D4. The Save and filter springs animate the whole catalog, not just the control.**
- `withAnimation(springSnappy) { myMatchdayStore.toggle }` is at `SportsDashboardView.swift:1752` and `ArenaDiscoveryView.swift:1125-1129`. The Arena version also wraps the error-alert state.
- `showFollowedOnly.toggle()` is at `DashboardMatchList.swift:62-64`.
- These transactions reach every view that observes the store or the filtered list: row insert/remove, moves and section counts. That goes against "no global catalog animation". Arena already turns animation off for projection updates on purpose (`ArenaDiscoveryView.swift:1061-1066`).

## Assessment of each proposal

**1. Inline disclosure: agree, with these details.**
- Keep `withAnimation` inside the shared toggle closures (`LiveEventCard.swift:149`, `SportsDiscoveryViews.swift:539`, `:1055`). That way the row tap, the context menu and the VoiceOver action all behave the same.
- State is row-local, so the transaction stays small. Neighbouring rows sliding down is the native-looking result.
- Use a spring with no bounce, e.g. `.snappy(duration: 0.22)`, because it handles a quick second tap smoothly. Add `.transition(.opacity)` on the inserted `CatalogInlineEventContext` (`LiveEventCard.swift:105-109`, `SportsDiscoveryViews.swift:515-518`, `:1033-1036`).
- Don't use `.move`. Rows aren't clipped, so the moving content would overlap the row above.
- With Reduce Motion on, `nil` (instant). Low Power Mode doesn't need to suppress a one-off short animation.
- Run the `onChange(of: id) { reset() }` resets (`LiveEventCard.swift:116`, `SportsDiscoveryViews.swift:522`, `:1040`) with animations disabled. Otherwise a reused row could animate closed while showing a different fixture.
- Leave focus alone. The existing Expanded/Collapsed value is enough.

**2. Pending label: agree, but fix D1 as part of it.**
- **Footprint:** Put the current title and "Opening…" in one ZStack. Hide the inactive layer and keep it out of accessibility. Give the icon a fixed scaled frame so the spinner and the symbol take the same space.
- **Check first:** A permanently wider Watch can change which rows fit beside the names on a 375-pt phone. That would quietly change the approved hierarchy.
- **Fallback:** If it does change the fit, keep the title text and swap only the icon for a spinner. "Opening broadcast" in the accessibility value and the resolution panel already announce the state.
- **Fade:** Make it ≤0.12 s, scoped to the label. The pending state must still show on the first frame.
- **Dimming:** Keep the pending button disabled for hit-testing, but draw it at full opacity, e.g. a `FottyPressButtonStyle` parameter. Stop dimming the row-information buttons. Other rows' Watch capsules can still dim, with a short local opacity animation on `isEnabled`.
- **On Air:** Move `HomeOnAirSection` onto `PendingWatchLabel`.

**3. Score animation: narrow it.**
- Monospace everywhere (D3).
- Animate only the hero:
  - Split it into home and away `Text`s, each with `.contentTransition(.numericText(value:))`. That rolls in the right direction for corrections like 2–1 → 1–1.
  - Attach `.animation(rm ? nil : .snappy, value: score)` to the score only.
  - Key it with `.id(item.event.id)` so a different fixture taking the spotlight swaps instantly.
- No animation on rows. The `HomeDiscoveryRow` score shares a string with the minute, so any content transition would animate the minute too. Restructuring that string is out of scope.
- Spoiler-protection appear/disappear is an insertion, not a change, so it shouldn't roll.

**4. Release fade: agree, lowest priority, with one hard constraint.**
- The tap action runs as the press is released, in the same update. That's when `onWatch` sets pending and D1's disabled state flips.
- If `.animation(value: isPressed)` sits on `content`, the label swap and the dimming get swept into the fade.
- So put it only on the overlay: always present, opacity driven, `isPressed ? nil : .easeOut(0.15)` (`Components.swift:429-436`). The press stays instant and there's still no scale.

**Save/filter: change "obey Reduce Motion" to "remove the global transaction".**
- Remove both global `withAnimation` wrappers.
- If we want some feel, use a local `.animation(value: isSaved)` plus an opacity transition on `CatalogSavedStateLabel`, and a local animation on the filter chip's fill.
- Move `savedMatchError` outside any animation.
- The list itself updates without animation.

## Hypotheses (need missing files)

- **H1, retained player.** `ViewingSessionShell` places the mini surface from slot bounds it reads after layout (`ViewingSessionShell.swift:49-62`, `:112`, `:134-138`). Those bounds are the final layout values, outside any transaction. If the mini slot sits inside the scrolling content, any animated row height above it would leave the video behind its slot for about 0.2 s. I need the file that sets `ViewingSurfaceBoundsKey` (the slot placement).
- **H2.** `StreamResolutionPanel` appears through `safeAreaInset` with no transition (`SportsDashboardView.swift:163-180`). It may pop in while the label fades. That's worth a follow-up, but its file isn't in the packet.

**Absent from the packet:** `HomeMatchSummaryRow` (named in task.md, defined nowhere in the packet), `CatalogInlineContextState`/`CatalogInlineEventContext`, `StreamResolutionPanel`, the bounds-key producer, and the full Home list container.

## Acceptance plan

1. **Unit tests (hosting-size measurement, no device):**
   - `PendingWatchLabel` gives the same size when pending and idle for Watch, Retry and the alternate titles, at default, xxxLarge and AX3 text sizes.
   - `MatchRowLayout.fitsBeside` gives the same result before and after the footprint reservation at 375 and 393 pt with long names.
2. **Pure-policy tests:**
   - The score animates only when the fixture is the same and the score changed. It never animates for a minute-only change or a fixture swap.
   - The disclosure, score and press animations are `nil` when Reduce Motion is on.
3. **Source check:**
   - No `withAnimation` around `myMatchdayStore.toggle` or `showFollowedOnly`.
   - The press animation is scoped to the overlay.
   - The disabled-but-pending state renders at opacity 1.
   - The existing `WatchTapAcknowledgementTests` pass unchanged. Pending ordering and dedup are untouched.
4. **On a physical phone, later (still open until then):**
   - Tap Watch on a borderline-width row and on the hero: no reflow, nothing dims.
   - Double-tap a disclosure quickly.
   - Expand a row while the mini player is active (H1).
   - Repeat with VoiceOver and with Reduce Motion on.
   - Light and dark appearance.
   - Use the acceptance labels from the design standard: "source checked" now, "physical interaction checked" only after that run.

**Blockers before implementing:** settle D1 inside proposal 2; agree the Save/filter change removes the global transaction; send the slot-placement file so H1 can be checked.
