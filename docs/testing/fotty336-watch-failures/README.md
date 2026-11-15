# Watch failures — private Jet336 repair gate

15 November 2026. Owner authorized investigation with actual Claude, confirmed
repairs, and one consolidated Jet iPad build. Ranking, phone and TestFlight
remain unchanged. Work branches from `e98f3a0` (normal Jet335 UI candidate).

## Confirmed findings

1. **Playback freeze, not a buffering timeout.** On normal Jet335, Belarus–Albania
   Watch recovered from HF1 startup timeout through LS1 and CS1 failures into HF2.
   After media-ready, the UI stopped responding. iPadOS killed Fotty at
   18:42:36 UTC with a foreground scene-update watchdog violation. The main
   thread waits for `LiveSourceHealthStore.recordSuccess`'s serial queue; that
   queue holds `recordDeliveryMetadata` while `UserDefaults.set` waits for main
   notification delivery. `SportsContinuityBridge` installs the defaults observer
   on the main operation queue. [Redacted stack](jet335-hang.json).
   Existing hosted tests disabled persistent programme evidence, so they did
   not exercise this write/notification path. The new isolated-suite tests
   exercise it without accessing the owner's defaults or Keychain. The repair
   uses Fotty's existing pending-write buffer, drains after releasing the health
   queue, and retains pending reads and newer reentrant updates. No scoring,
   ordering, observation timestamp or success-count formula changes.
2. **Incomplete Highfly reads represented as a definitive miss.** When no rows
   matched, failed supplementary catalog reads still ended as `matchNotFound`.
   The regression fails on baseline. The repair reports an unread/incomplete
   lookup while preserving complete-empty and actual identity-conflict outcomes.
   This is not proof that a playable Suriname stream was hidden: its recorded
   Highfly lookup had no supplementary-read failure and different teams.
3. **Mixed discovery errors hid actionable account/TLS explanations.** An empty
   sibling caused the combined result to discard an account or TLS error. The
   regression fails on baseline. Claude identified an additional edge case in
   the first candidate: unsafe-descriptor rejections must not disable aggregate
   Retry for other sources. The correction distinguishes tagged TLS transport
   failures from descriptor safety rejection; neither transport guards nor
   selection ranking change.

## Supply findings kept separate

- Initial HF2 produced a native picture 8.519 seconds after the recorded Watch
  request, but showed Real Madrid–Crvena Zvezda basketball under Belarus–Albania.
  That is a wrong programme, not a successful match qualification. Seven admitted
  Highfly deliveries had no parseable team evidence in their labels. It does not
  justify inventing a title or relaxing matching. [Reproduction](jet335-belarus-reproduction.json).
- HF1 timed out at 20.106 seconds against its existing 20-second startup budget.
  LS1 then failed during preparation; CS1 returned contract-validation HTTP502.
  No evidence supports changing the recovery timer or declaring these providers
  universally unavailable.
- The earlier Suriname and Belarus records are retained in
  [allowlisted baseline diagnostics](jet335-diagnostics.json).

## Validation status

The exact final source passed the full Catalyst suite: **2,739 passed, 12
existing opt-in/physical tests skipped, zero failures** (2,751 methods total).
[Final test receipt](watch336-final-full.json) and
[compile receipt](watch336-final-compile.json). The earlier run passed its compiled
methods but had a test-only lifetime guard edited during execution; its failed
source-identity gate is retained and superseded by this exact-source rerun.
The initial focused run's incorrect unread-response test expectation and the two
baseline-red discovery methods also remain separate receipts.

[Actual Claude's three-round review](claude-review.md) approves all three repairs.
The subsequent test-only timeout/join guard was independently reviewed by Codex
and included in the final full run. [Ranking comparison](ranking-preservation.json)
confirms unchanged policy bodies after serialization-wrapper normalization.

Normal signed private **build 336 is installed on Jet**. [Release receipt](watch336-release.json)
has the same 320 source/input hashes as the final full suite. Independent final
review also compared those hashes with the working tree; all eight new regression
methods passed. [Physical acceptance](jet336-acceptance.md): normal channel Watch,
real same-delivery automatic recovery, two later 90-second advancing intervals,
Sources, same-attempt Pause/Resume and responsive return to Home passed. The
first stall remains a failure receipt, not an uninterrupted pass.

A fresh account-backed match was not available during this final check;
Highfly live-match playback, audible audio and independent backup are not claimed.
The baseline wrong-programme issue remains open. One normal iOS build/install was
used; no phone, ranking, cloud or TestFlight change. Owned output and keep-awake cleanup completed;
[cleanup receipt](cleanup.json) records 25.83 GB free after removing the gate.
