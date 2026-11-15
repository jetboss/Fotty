# Actual Claude review — Jet335, round 2

Read-only review of the frozen source and coordinator-reported observations. Claude did not control Jet or rerun tests.

## Verdict

**Source approval still holds for b693a01.** The new observations don't point to any defect. On Jet, build 335 now has a useful but limited physical pass for the changed Home Watch feedback and disclosure behaviour. It is not full acceptance.

## 1. What the new observations establish

**Newly closed on Jet:**
- **Pending Watch in a list row:** the Finland row is a Home schedule row, which uses the compact `MatchStartControls` Watch. It stayed readable and the same size while pending, with Reduce Motion on. This was the main gap left after round 1.
- **Collapse at the bottom with the mini-player showing:** on the last Home row (Dallas), the list didn't jump to the top and the mini-player stayed. H1 isn't confirmed on iPad. Whether the tab bar re-expanded wasn't reported, which is fine because it's system behaviour.
- **Hero Watch at the largest standard text size, light and dark:** no reflow, resting or pending.
- **Quick double tap:** the Spain row ended closed with no leftover panel. That's a correct end state, not timing evidence.
- **Reduce Motion:** turned on and then restored to off. The only recorded check under it was the pending Watch. The observations don't say whether a disclosure appeared without a fade, so that remains unobserved, but no source blocker depends on it.
- **No-playable-stream alert:** input stayed responsive. This is useful context but outside the scope of this change. The report doesn't say whether the spinner went back to the play icon afterwards.

## 2. Source blockers

**Confirmed: none.**
- **Appearance modal:** it stayed dark until dismissed while Home was light. Nothing in this commit touches colour-scheme or sheet presentation; the only scheme override is the hero's existing `.environment(\.colorScheme, .dark)` at `SportsDiscoveryViews.swift:761`. Treat it as an existing-behaviour question, not a regression.
- **Remaining hypotheses (all cosmetic, none observed):**
  - H2: the closing and opening panels briefly overlapping on a quick double tap.
  - H3: the dash shifting when a score gains a digit.
  - H1 on iPhone: the tab bar and mini-player re-expanding after a collapse at the bottom.

## 3. Limits to name in the final report

- **Device:** Jet iPad only. The phone was not touched, and the phone layout and the resting Watch width against the old build were not checked.
- **Text size:** the largest standard size, with Larger Accessibility Sizes off. That is not AX3. Restoring the original text size is still in progress.
- **Double tap:** sent as clickCount 2 and checked by end state only. The time between taps wasn't measured, and the absence of any momentary overlap isn't shown.
- **Smoothness:** the trace failed to export (Document MissingTemplate). There's no frame-rate or hitch evidence, and no claim of being hitch-free.
- **Matchday card (`LiveEventCard`):** the check on the shared card through a channel route (Full lineup Cricket channels or a Search channel result) is still in progress. A saved My Matchday fixture can't be checked because none is active, and saved data must not be changed to create one.
- **Reduce Motion:** confirmed for the pending Watch only. Whether disclosures skip the fade wasn't stated.
- **Score:** a goal, a correction, a different match taking the hero slot and the spoiler toggle can't be triggered in build 335. They are checked at source level only.
- **VoiceOver:** what it says and where focus goes are unmeasured.
- **Evidence type:** these are observations reported by the coordinator, not recordings.
- **Playback:** a working picture is not evidence of audible commentary, correct live-match qualification, source independence or playback reliability. Ranking is unchanged.

**Suggested acceptance wording:** "Source checked and automated checked (261 focused tests). Physical interaction checked on Jet iPad, build 335, for Home pending Watch on the hero, On Air and a compact row, Home disclosure including collapse at the bottom with the mini-player retained, the end state after a double tap, and Reduce Motion on the pending Watch, at default and largest standard text in light and dark. Not established: phone, AX3, the Matchday `LiveEventCard` route (in progress), VoiceOver, score transitions, and smoothness measurement."
