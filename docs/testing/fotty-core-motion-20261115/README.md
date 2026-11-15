# Core viewing UI motion — 15 November 2026

**Current:** normal signed335 is installed on Jet after the separately authorized
[physical follow-up](jet335-acceptance.md). Watch feedback/disclosures were observed
on-device; quantified motion, VoiceOver and phone limits remain explicit. The
source/local gate below is historical and did not itself authorize installation.

Owner direction: focus on the main match-viewing journey, smooth transitions and
Fotty character; avoid further Sports TV expansion. Actual Claude discussed the
frozen f214db2 baseline in two read-only rounds before the consolidated pass.
The source changes are on codex/ui-motion-20261115. No device or distribution
step was part of that source/local-validation pass; Jet remained on 334 then.

## Screen and motion contract

- Preserve Home, Matchday and Search hierarchy, team artwork, the featured live
  match and the current Watch/source ownership. No new destination or feature.
- A Watch tap retains its text and footprint, displays the spinner immediately,
  and retains the existing opening panel/cancel action and accessibility value.
  Pending controls remain disabled, but the active control and team information
  remain fully readable. Other Watch buttons retain their disabled appearance.
- The icon has one text-scaled slot in both states. The alternative of reserving
  the longer Opening text was rejected because it widens idle buttons and can
  force narrow layouts to stack before a tap. Long alternate labels still wrap.
- Details expand only from the row-local action, with a short non-bouncing
  animation and an opacity insertion. Rapid taps may reverse it. Reused rows
  reset without animation; Reduce Motion makes the change instant.
- Row score/minute strings use monospaced digits without transitions. Only the
  hero's home/away score can roll on an update; a new fixture gets a new score
  identity. No minute-tick or catalog animation.
- Press is immediate; only the non-interactive press overlay fades on release.
  No scaling, added gestures, delay before Watch or player geometry animation.
- Shared Save/filter mutations do not animate the catalog. Existing local
  confirmations and haptics remain. Existing guarded scroll-to behavior remains.
- Light/dark appearance and narrow/wide layouts retain their current composition;
  44pt targets and Dynamic Type wrapping remain. On Air shares the same Watch
  feedback contract without adding TV functionality.

Apple references checked for this pass:
[Motion](https://developer.apple.com/design/human-interface-guidelines/motion),
[Loading](https://developer.apple.com/design/human-interface-guidelines/loading),
[contentTransition](https://developer.apple.com/documentation/swiftui/view/contenttransition(_:)).
Durations and the broadcast-style score treatment are Fotty choices.

## Claude collaboration

- [Round 1](claude-design-round-1.md): found disabled-row dimming, label reflow,
  an overlooked On Air duplicate and global Save/filter transactions. The plan
  was changed in response; this was not approval of finished code.
- [Round 2](claude-design-round-2.md): verified that the retained mini-player
  lives in the native tab accessory, outside row layout. Required fixture-keyed
  score updates, a fixed spinner slot and consistent On Air feedback.
- [Final source review](claude-source-review.md): approved, no source blockers.
  Later corrections are limited to a stale comment and the test harness: remove
  an attempted write to the read-only Reduce Motion environment and mirror the
  compact production action's fixed-size setting. The final focused Catalyst run passes all 261 tests with zero failures/skips.

## Acceptance boundaries

Source and hosted Catalyst results do not prove physical smoothness, native
phone layout, audible playback or VoiceOver operation. Physical follow-up must
check narrow rows/hero with Watch pending; quick disclosure reversal; Reduce
Motion; disclosure collapse at the bottom with the mini-player present; and
light/dark/large text. No source, ranking, transport or player-owner changes are
planned. Phone, source preferences, saved data and TestFlight remain untouched.

## Deliberate trade-offs and old evidence

Home On Air now uses Fotty's existing custom Watch capsule so the pending state
stays readable. Button/disabled/accessibility semantics remain native; playback
controls remain native and untouched. Sports TV's separate row presentation is
not redesigned here. The fixed scaled icon slot can make idle Watch slightly
wider than the old caption glyph; physical narrow-width comparison remains open.

The old six-screen October evidence ledger fails its source-freshness check
(`SportsDashboardView.swift`). Its hash was already stale on f214db2 before this
pass. Historical captures are not rebound or presented as this candidate; this
receipt records only new scoped evidence.

## Verification result

The final Catalyst compile passed. **261 focused tests passed, zero failures and
zero skips**, including all new label/row/hero-boundary and disabled-rendering
checks, unchanged Watch acknowledgement/cancellation/dedup tests, Home projection,
Matchday, reminder and existing inline motion checks. [Validation](validation.json)
retains both failed attempts and the final passing run. The two first-run test
failures were stale exact-string assertions from the earlier planning callback,
not new app failures; their modal-ownership assertion now tolerates whitespace
and the existing planning assignment. No production logic was changed for them.

| Surface/state | Reference | New evidence | Remaining gap |
| --- | --- | --- | --- |
| Hero Watch idle/pending | Stable tap footprint, immediate readable progress | Actual Catalyst component at 288/343/600pt; button bounds equal; 288/600 images inspected and spinner visible | Physical phone/iPad layout and interaction |
| Row Watch/Retry/alternate | Stable width and wrapping | Native hosted sizes at large/xxxLarge/AX3, real row fit threshold ±1 and narrow/wide proposals | Physical Dynamic Type and VoiceOver |
| Pending/ordinary disabled | Pending readable, unavailable controls still dim | Pixel comparisons in light and dark passed | Native touch/VoiceOver semantics |
| Disclosure/score/release | Brief local movement, no catalog/player animation | Source reviewed by Claude; unchanged identity/acknowledgement tests pass | Actual transition, fixture-swap and Reduce Motion observation |

Native component captures are synthetic test content, not an actual live fixture:
[288pt idle](home-footer-watch-288-idle.png),
[288pt pending](home-footer-watch-288-opening.png),
[600pt idle](home-footer-watch-600-idle.png),
[600pt pending](home-footer-watch-600-opening.png).

The source-only gate did not package or install iOS. The later
[Jet335 follow-up](jet335-acceptance.md) records installation and bounded physical
checks separately. Phone, backend and TestFlight remain untouched.
