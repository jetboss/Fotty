# Stage 3 lifecycle: paused Wrong match repair (14 Nov 2026)

Worktree `codex/lifecycle-roadmap-20261114`, based on c76a93d. Claude implemented the change;
Codex reviewed it and ran every build and test. The counts below are the results Codex reported.
The raw receipts are kept outside this repository.

## Defect

The Sources sheet offers Wrong match while paused. `reportWrongMatch` recorded the rejection
(wrong-programme evidence, typed verdict, `viewer_reported_wrong`), but recovery correctly
refused to act while the viewer was paused. The next explicit Play then resumed the same native
item, or sent Play to the same Web page, so the viewer saw the rejected game again.

## Change (`Fotty/Features/Player/LivePlayerViewModel.swift` only)

- In `togglePlayPause`, explicit Play after Pause (`!userWantsPlayback`, not playing or pending)
  on a single-match delivery with wrong-programme evidence calls `loadCurrentSource()` instead of
  resuming. The existing wrong-programme check there fails over to another source on a new
  attempt, or ends with "No matching broadcast".
- With no backup, that terminal branch now sets the existing `viewerExhaustedSourceID` and
  `shouldSuspendWebPlayback`, the same hold a blocked picture uses. The rejected Web page is
  unmounted rather than reloaded under the new attempt ID, and late started, recovered or stall
  callbacks start nothing.
- Unchanged: Pause, toggling while connecting or recovering with playback still wanted, Watch
  Two, channels, Wrong match recording, ranking, provider matching/admission, failover choice,
  source order, FPL, multi-stream and native audio. No new owner or state was added.

## Regression matrix (`FottyTests/LivePlayerRetryLifecycleTests.swift`)

`testPausedWrongMatchKeepsPauseAndExplicitPlayNeverResumesTheRejectedDelivery`:

| Case | Before Play (paused) | After explicit Play |
|---|---|---|
| Native, 1 source | Stale taps ignored; one rejection; same attempt; no Play, lookup or validation | "No matching broadcast"; delivery held; late stall/failure callbacks (old and current attempt) change nothing; Play count 0 |
| Native, 2 sources | Same | Other source on a new attempt; rejected item never receives Play or validation |
| Web, 1 source | Same; page keeps its Pause command | "No matching broadcast"; page suspended and not displayed; late started/recovered/stall callbacks change nothing; no retry, lookup or validation |
| Web, 2 sources | Same | Other source on a new attempt; no Play command to the rejected page |

All cases: exactly one rejection record, none for the new attempt, source order unchanged.
Fixtures use unique fixture IDs and hosts, so they share no provider health with other tests.

`testConnectingToggleWithWrongProgrammeEvidenceKeepsItsExistingSemantics` (native and Web, one
source): toggling while connecting with playback still wanted keeps its existing behaviour (same
attempt, no hold, no error), even when the delivery has wrong-programme evidence.

## Results (Mac Catalyst)

| Run | Result |
|---|---|
| Baseline (before the repair) | Failed as expected: 1 method, 20 assertions, across native/Web × 1/2 sources; pause and stale-tap checks passed |
| Focused (current source) | 261 passed, 0 skipped, 0 failed, including the 7 unchanged `NativePlayerAudioIsolationTests` |
| Full suite | 2,785 total; 2,773 passed; 12 opt-in/physical skips; 0 failed; exit 0 |

WebKit printed runtime diagnostics during the run; none were test failures. An independent
final source review found no remaining P1/P2 issues.

## Jet build 328 normal Watch check

Normal signed Release 3.0.0 (328), app and widget signatures verified, installed in place on free
Jet after the owner unlocked it. This is the committed build 327 source baseline plus the focused
repair; no unrelated dirty primary edits were packaged. Symbols were retained privately for crash
diagnosis; temporary build products and copied preference snapshots are removed after the gate.

Home → Haiti–United States → Watch showed immediate Opening broadcast/Cancel feedback, then
native LS1 (CNC) showed the correct senior men's CONCACAF Nations League quarterfinal, Haiti 0–1
USA, with a first-half running match clock. The official [CONCACAF match page](https://www.concacaf.com/competitions/nations-league/matches/50691fb4fc6140dfb26ed7e240467e27/haiti-vs-united-states)
corroborated the 14 November 21:30 UTC fixture; the existing ESPN fixture publisher returned
in-progress, first half, 24 minutes at 22:01:46 UTC. The football fixture checked earlier in this
session (Sweden–Bosnia) had finished by install time and was not reused as live evidence.

Pause held the picture at 25:07 while Sources was opened and dismissed. The sheet displayed four
choices (LS1 and CS1–CS3); opening it did not resume playback. Explicit Play resumed the same LS1
native attempt and the correct picture advanced. The retained records show 17.721 seconds from Watch to decoded picture (4.115 seconds after the
selected source attempt began). A post-resume native hold advanced 92.575 seconds over 92.575
seconds, 1280×720, zero recorded stalls/dropped frames, with the same attempt through close.
The existing resume recovery completed in 516 ms after its stall-timeout observation; no source
replacement occurred. These timings are this one watch, not a general startup guarantee. Exact
observations are in `physical-watch.json`. No source preference was changed, no app test host installed, and no source
was deliberately mislabeled wrong to manufacture a pass.

## Not covered here

- **Exact paused rejection on physical Jet remains unexercised:** the observed programme was
  correct. Native/Web × one/two sources are proven in the deterministic regression; a future
  genuine wrong-picture observation can exercise the full report → Play flow without leaving a
  false fixture/delivery exclusion on the owner's device.
- Device Hub does not relay audible sound. Audio availability/state is not a listening pass.
- This does not requalify PL, UCL, cricket, all four listed routes, independent failover or PiP.
- The earlier `NativePlayerAudioIsolationTests` crash under full-suite load (EXC_BAD_ACCESS in
  CoreFoundation/MediaToolbox during XCTest teardown, no test named) remains unexplained. It did
  not recur in these runs, and this work does not fix it.
- The roadmap is not complete. Stages 4–7 and the per-provider store-slot follow-up are separate
  and not implemented.

## Integration and resource notes

The earlier approved store-reservation fix 3094b8c was already an ancestor of the primary
baseline; its Claude review receipt was merged locally as c76a93d. This task uses an isolated
branch so the unrelated primary terminal-copy and other edits are not included in build328.
Only owned changes are committed; a scoped preservation stash is restored before integration
is considered complete. No push, cloud deployment, phone interaction or TestFlight occurs.

One owned build directory was reused for Catalyst and signed Release; the owned keep-awake
process, build output and raw copied preferences are cleaned at the end. Only small redacted
receipts and a private symbol archive are retained. `agent-finish.sh` refreshed the local export,
but its doctor stops on the pre-existing Current-State.md 8KB budget violation. The generated
export was not committed or used to replace primary's separate dirty export.
