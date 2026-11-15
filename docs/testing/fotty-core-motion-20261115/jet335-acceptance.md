# Jet335 — core UI polish physical follow-up

15 November 2026. Owner authorized installation and transition/Watch-feedback
checks on Jet iPad, fixes with actual Claude, unchanged ranking, no phone and no
TestFlight. Normal signed **3.0.0 (335)** from `b693a0166861930d7cc147269936e46b078cb4da`
was installed over 334 and left on Jet. No source change or second build was
needed during this physical gate. All 320 captured source/config hashes still
matched after the checks. [Build receipt](jet335-build.json).

The source pass's **261 focused Catalyst tests, zero failures/skips**, apply to
this unchanged candidate. They were not relabelled as physical-device tests or
rerun for this documentation-only follow-up. The signed iOS Release compile and
strict signing verification passed. Only Jet was installed/launched/controlled.

## Observed UI results

Device Hub observations covered landscape on Jet iPad Air (4th generation),
iPadOS 27.2.1, first at the owner's text size and System/light appearance, then
largest standard text in light and dark. Remote frames can lag touch input;
the following are visible interaction/end-state results, not frame timing.

| Check | Evidence and scope |
| --- | --- |
| Home hero Watch | Tap retains Watch wording, capsule footprint and text position; spinner replaces play glyph. Active control remains readable; other Watch controls dim while team information stays readable. Repeated pending taps produced one recorded Watch request in the initial sample. |
| Cancellation | Initial hero lookup was cancelled; the outcome is `cancelled`, Home recovered, and no late player appeared during more than 20 seconds of further observation. Later samples resolved before remote Cancel reached them; those are **not** additional cancellation passes. |
| Home On Air | Same stable wording, footprint, spinner and disabled treatment. Sky Sports Premier League reached technical playing in 8,162 ms, then visible moving video. |
| Home compact match row | Finland–San Marino's Watch showed stable wording and inline spinner with Reduce Motion on; names remained readable and other Watch buttons dimmed. The player subsequently opened; this is not a correct-programme or audio qualification. |
| Home disclosures | Spain's future row and the bottom Dallas–Florida row expanded/collapsed. With moving video in the mini-player, the bottom row settled without returning to the top, hiding the mini-player or leaving a blank details gap. Remaining details could be scrolled above it. |
| Repeated disclosure input | Home future row ended closed after `clickCount: 2`. Shared channel card ended with one expanded panel after two taps from expanded, and a single collapse returned its original footprint. No leftover panel was observed. Sub-300-ms reversal and intermediate frame overlap were not measured. |
| Shared LiveEventCard | Home → See all → Full lineup → Willow channel: inline details opened/closed; Watch retained wording/size with spinner; the other channel Watch dimmed. TV1 subsequently showed moving Willow video, with technical playing recorded at 13,541 ms. No saved fixture was created to manufacture this route. |
| Mini-player/navigation | Channel video continued visibly after minimising while Home disclosures and scrolling were exercised. Home/Matchday/Full lineup navigation remained responsive. Closing the player returned to the list. No fullscreen/PiP retest was added because those paths did not change. |
| Reduce Motion | Temporarily enabled, compact Watch and disclosure actions remained usable, with no stuck intermediate state; restored off. Exact fade suppression was source-checked but cannot be quantified from the remote snapshots. |
| Larger text/light/dark | At the rightmost standard text step, with Larger Accessibility Sizes off, hero idle/pending remained legible and stable in both appearances. No Watch reflow or clipped team identity was observed. Original text step and System appearance restored. |
| Failure feedback | Hero lookup returned “Broadcast not ready / No playable stream is available for this match right now.” Dismissal restored the play glyph and enabled controls. Full lineup offered Retry. This closes feedback/reset behavior, not match supply. |

## Playback observations kept separate

This gate tests UI behavior using the real app. It does not certify source supply.
Sky TV25 and Willow TV1 displayed video; Device Hub does not relay audio. There
was no official programme corroboration or new 90-second source qualification.
The Belarus–Albania sample opened a player but remained buffering until closed
after roughly 28 seconds, with one failover recorded. It is **not** a playback
pass. Hero discovery returned no playable stream twice. These outcomes are
retained in [allowlisted Watch records](jet335-watch-results.json); no source
ranking, provider eligibility, transport, recovery or player-owner code changed.

## Actual Claude review

[Round 1](claude-jet335-round-1.md) and [round 2](claude-jet335-round-2.md) used the
existing subscription-authenticated, read-only Claude bridge with frozen source
and reported observations. Both completed successfully without permission
denials. Claude found **no confirmed source defect** and kept source approval;
its acceptance is limited to observed cases, not a blanket visual/performance pass.

After round 2, the coordinator completed text-size restoration, observed the
spinner reset following the unavailable alert and checked the shared channel
LiveEventCard. Those are coordinator observations, not claims that Claude drove
the device. The live-fixture LiveEventCard in My Matchday was not exercised:
there was no current saved/followed live fixture, and owner data was preserved.

## Limits retained honestly

- No usable performance recording: the 45-second Animation Hitches trace stalled
  during finalisation; bounded export returned `Document Missing Template Error`.
  Its owned recording was stopped and removed. [Trace receipt](jet335-trace.json).
  There is no measured FPS, hitch-rate or tap-to-feedback latency claim.
- Phone layout/resting-width comparison, portrait/narrow iPad windows, spoken
  VoiceOver focus, AX3 text and forced hero score increase/correction/fixture-swap
  remain physically unverified. Existing source/hosted checks are separate.
- Restoring System appearance changed Home immediately while the already-open
  Settings sheet retained its previous dark presentation until dismissal. No
  colour-scheme ownership changed in this pass; this is a recorded cosmetic
  observation, not a confirmed regression or reason to widen the motion task.

## Preservation and exit

App theme restored to its original `system`; Reduce Motion restored off; the
original third standard text-size step restored with Larger Accessibility Sizes
off. Orientation remained landscape. [Settings observations](jet335-settings.json).
All sample playback was closed and normal build335 was left on Home.

The [strict comparator](jet335-preservation-raw.json) reported differences; the
[semantic follow-up](jet335-preservation-explained.json) explains them separately.
All source/appearance/interest preferences are equal. The one saved fixture
retains its identity, saved time and other fields, with only its observed time
advancing. Followed-team owner fields are equal; only Core Data revision metadata
changed. All other protected tables and database checks passed.

The strict result is retained, not rewritten as a pass;
runtime cache/history and refreshed observation changes are not erased to create
a byte-identical result. Saved identities, reminder settings, source preferences,
club follows and protected owner fields are checked independently. The final
redacted preservation and cleanup receipts accompany this document.

No phone interaction, Git publication, cloud deployment, source opt-in change,
ranking-policy change, FPL/Watch Two work or TestFlight release occurred.
