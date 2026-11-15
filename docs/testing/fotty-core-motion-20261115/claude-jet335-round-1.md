# Actual Claude review — Jet335, round 1

Read-only review of the frozen source and coordinator-reported observations. Claude did not control Jet or rerun tests.

I found no source blocker in b693a01. Build 335 is accepted for the cases the observations close, but physical acceptance is not complete. I read the source only. I didn't rerun tests, and the failed trace means there's no hitch or frame-rate claim.

## 1. Source-level defects

**Confirmed defects: none.**

- **Changes since the prior approval:** The commit has the agreed shape. The stale On Air comment from that approval is fixed (`SportsDiscoveryViews.swift:1228-1230`).
- **Pending Watch readability:** The hero (`SportsDiscoveryViews.swift:828`, `:851`), On Air (`:448` in the diff) and the three Watch buttons in `MatchStartControls` stay at full opacity only for the match being opened. Every other disabled Watch still dims to 0.45, as intended (`Components.swift`, `FottyPressFeedback`).
- **Disclosure resets:** When a row's match is replaced, the details panel closes with animations switched off, in all three rows (`LiveEventCard.swift`, `SportsDiscoveryViews.swift:521-527` and `:1062-1068` in the diff). Row taps and the long-press menu go through the same animated toggle, which is off under Reduce Motion.
- **Hero score:** Each side animates separately and is plain under Reduce Motion (`SportsDiscoveryViews.swift:949-957`). `.id(item.event.id)` at `:984` resets the score display when a different match takes the hero slot, so it shouldn't count from the old score to the new one.

**Hypotheses (not confirmed, need a physical check):**

- **H1, collapse at the bottom of the scroll:** The tab bar is set to minimise on scroll-down (`MainTabView.swift:322`) and the mini-player sits above it (`:323-325`). Collapsing a row at the very bottom shrinks the content, and the system may read that as an upward scroll and re-expand the tab bar and mini-player. That would be system behaviour, not app code, and on iPad it may not happen in the same way.
- **H2, quick double tap:** Tapping details twice quickly may briefly draw the closing and opening panels on top of each other. This is cosmetic.
- **H3, score width:** Going from 9 to 10 makes the score wider. The animation only covers the digit text, so the dash and the team columns would jump while the digits roll. This is cosmetic and probably rare.
- **Notes still open from the prior approval:**
  - Note 2: On Air no longer uses the native button style. That trade-off still needs to go in the handoff.
  - Note 3: Nobody has compared the resting Watch width to the old build. The observations come from iPad, so whether a borderline phone row now stacks is untested.

## 2. What the reported observations close

| Case | Status |
|---|---|
| Pending Watch keeps its text and size and shows a spinner (Home hero, Home On Air) | **Closed** on Jet, at the text size and appearance used, which wasn't reported |
| Other Watch buttons disabled while row text stays readable | **Closed** (Home) |
| Cancelled lookup does not open a player late (more than 20 s) | **Closed** for one manual run |
| Normal expand and collapse of a Home upcoming row | **Closed** |
| Pending Watch in a list row (Home schedule row, Matchday card) | Open: only the hero and On Air were reported |
| Matchday details (Arena card) | Open: only Home rows were reported |
| Quick double tap; collapse at the bottom with the mini-player showing | Open |
| Reduce Motion | Open |
| VoiceOver: pending wording and focus after a disclosure | Open |
| Hero score going up or being corrected; a different match taking the hero slot; spoiler toggle | Open, see the note below |
| xxxLarge and AX3 text, light and dark, resting width vs the old build | Open |
| Quantified smoothness | Open: the trace failed to export ("Document MissingTemplate") |
| Phone | Open: the phone was not touched |

The TV25 picture playing and surviving minimise is relevant only as context for the retained mini-player. It doesn't establish audible commentary, live-match qualification, source independence or playback reliability.

**Score cases can't be run on demand with build 335.** The existing debug score replay only provides one fixed football score. Nothing in this build can raise or correct a hero score, or swap the hero to a different match, on cue. These cases stay checked only at source level. A live goal could be observed opportunistically, but that isn't repeatable. Classify them as "source checked, physically open" rather than making a new build just to get a pass.

## 3. Remaining physical checklist for build 335 on Jet, in priority order

1. **Pending Watch in list rows.**
   - Tap Watch on a Home schedule row, then on a Matchday (Arena) card.
   - Pass: the wording and capsule size don't change, the spinner appears where the play icon was, nothing nearby moves, the row text stays at full strength, and only the other Watch buttons dim.
   - Fail: any reflow, the text changes to "Opening…", or the tapped button dims.
2. **Quick double tap.**
   - Double-tap a Home upcoming row in under 0.3 s, then do the same on a Matchday card.
   - Pass: the panel ends in the expected state (closed after two taps), with no leftover or doubled panel, no blank gap and no jump in scroll position.
3. **Collapse at the bottom of the scroll, with the mini-player showing.**
   - Start playback and minimise it. Scroll Home to the very bottom, expand the last row, then collapse it.
   - Pass: the mini-player stays visible and usable, the list settles without a visible jump past the end, and the list doesn't jump back to the top.
   - Note: the tab bar re-expanding is H1 system behaviour. Record it, but it's not an app failure unless the mini-player disappears or covers the last row.
4. **VoiceOver.**
   - Focus the hero Watch and activate it. Pass: VoiceOver says "Watch <match>", then "Opening broadcast" and "dimmed".
   - Expand a row with VoiceOver. Pass: focus stays on that row, and it now reads "Expanded".
   - Collapse it. Pass: it reads "Collapsed", and focus doesn't jump to the top of the screen or the tab bar.
5. **Reduce Motion.** Turn it on, repeat a single expand and collapse, and repeat a Watch press.
   - Pass: the panel appears and disappears with no fade, the press highlight clears with no fade, and the spinner still shows.
   - Then turn Reduce Motion off again. Pass: the setting is back to its original value, and that's recorded.
6. **Larger text (if allowed).** At xxxLarge or AX3, with one light and one dark pass, repeat item 1 on the hero.
   - Pass: no reflow and the spinner is visible.
   - The resting width can only be compared with the old build if a screenshot from before 335 exists. Otherwise mark it open.

Everything else stays open and named: hero score increase, correction, match swap and spoiler (no way to trigger them in this build), quantified smoothness (no usable trace), and the phone (not touched, needed for the width comparison and for H1 on iPhone).
