# Final source review: approved, no blockers

**Verdict: approved at source level.** The candidate matches the plan we agreed in round 2, and I found no regressions that block it. This approval covers only what I could read. The Catalyst build and tests haven't run yet, and I make no claim they pass. Smoothness on a physical phone is still open.

## Checked against the agreement

**Pending Watch**
- The text stays the same and only the icon swaps for a spinner (`MatchStartControls.swift`, `PendingWatchLabel`). The icon area is a fixed, text-size-scaled frame and is hidden from VoiceOver.
- Every place that shows a pending state keeps full opacity through `dimsWhenDisabled: !isPendingWatch` / `!openingWatch`, while staying `.disabled`. That covers the three places in `MatchStartControls`, the two hero buttons and On Air.
- The "Opening broadcast" accessibility values are unchanged.

**Rows stay readable**
- Only the row-information buttons use `dimsWhenDisabled: false`.
- Ordinary disabled controls still dim. The pixel test asserts both cases.
- **Arena:** The whole card is never disabled. The busy flag only feeds the environment (`ArenaDiscoveryView.swift:343-345`), and there is no `.disabled` on any `LiveEventCard`.
- **Multi-select:** The card's selection button keeps its default dimming (`DashboardMatchList.swift:258-259`). The card inside it has no callbacks, so the new flag does nothing there.

**Release fade**
- The animation is attached inside the overlay only: an always-present overlay whose opacity changes, with `nil` while pressed (`Components.swift` diff lines 58-64).
- The label swap and the disabled state that change at the same moment as the release can't get caught in it.

**Disclosure**
- `withAnimation(FottyInteractionMotion.disclosure)` sits inside the three shared toggle closures, so the row tap, the context menu and the VoiceOver action all animate the same way.
- It uses `.transition(.opacity)` only. It is `nil` with Reduce Motion on.
- Resets run in a `Transaction` with `disablesAnimations = true`, which also suppresses any `.animation(value:)` modifiers.
- Given where the mini player sits (H1), this can't move it.

**Hero score**
- Each side has its own `.numericText(value:)` and an `.animation(value:)` scoped to that side only. Both become `.identity`/`nil` with Reduce Motion on.
- `.id(item.event.id)` on `scoreLockup` handles a spotlight fixture swap. Agreed: no policy test that just mirrors the modifier, and the visual check for a fixture swap stays open.
- VoiceOver still reads the score as one combined label, as before.

**Rows:** Static `.monospacedDigit()` only (`LiveEventCard`, `HomeDiscoveryRow` status line).

**Global transactions:** The Save wrappers are removed in both views, along with the filter wrapper. `savedMatchError` is no longer inside an animation. I found no new player or catalog animation.

## Non-blocking notes (fix if convenient)

1. **Stale comment:** `SportsDiscoveryViews.swift:1229` still says On Air "shows 'Opening…'… like the TV tab". The text no longer changes, and Home's On Air now differs from the TV tab, which is out of scope. Update the comment and note the TV difference as accepted.
2. **On Air no longer uses the native style.** It moved from `.borderedProminent` to the custom capsule (`SportsDiscoveryViews.swift` diff lines 425-439). That is what full opacity while pending requires, and it matches the other Watch capsules. But the owner said "keep Apple native controls", so state the trade-off in the handoff. The capsule's padding also changed, from 6 plus system insets to 16 horizontal and 10 vertical.
3. **Idle footprint vs. baseline.** The 18-pt scaled icon frame can make the idle Watch a few points wider than the old caption glyph. The tests prove idle equals pending, not that the new size matches the baseline. A row on a 375-pt phone that used to fit beside the names could now stack. Make this a visual comparison.
4. **Test fidelity.**
   - The `MatchRowLayout` test builds its action with `.fixedSize(horizontal: false…)`. The compact production path uses `horizontal: true` (`MatchStartControls.swift:528`). The label-size test still covers equality between idle and pending, so this is a gap in the test, not a defect.
   - The hero bounds test measures the capsule's pixels. `ImageRenderer` generally can't draw a UIKit-backed `ProgressView`, so whether the spinner actually shows isn't proven by that render.
   - The `expectedHeight` check, with ±1 pt tolerance from a separate hosting measurement, may be flaky. Watch for it in the Catalyst run.

## Open acceptance (not source defects)

- The Catalyst build and the full test run, including the new hosted, layout and pixel tests and the unchanged acknowledgement tests.
- **Phone, at default, xxxLarge and AX3 text, light and dark:**
  - Tap Watch on a borderline row, the hero and On Air. Check there's no reflow, the spinner is visible and nothing dims.
  - Check rows are readable while pending.
  - Compare the idle Watch width to the baseline (note 3).
- Quick double disclosure. Collapsing at the bottom of the scroll with the mini player active (the tab-bar hypothesis from round 2). The Reduce Motion paths.
- Hero: a same-fixture goal and a correction, a spotlight fixture swap, spoiler protection toggling.
- VoiceOver: "dimmed" plus "Opening broadcast" on the pending button, and focus kept after a disclosure.

Labels per the design standard: **source checked** now. **Automated checked** only after the Catalyst run. **Physical interaction checked** remains open.
