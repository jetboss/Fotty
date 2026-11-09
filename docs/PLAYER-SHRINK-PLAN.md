# Player shrink plan: decompose `LivePlayerViewModel` in place

Owner decision, 9 Nov 2026: shrink the existing player in place rather than build the parallel `Fotty/Engine` path in `REDO-PLAN.md`, which this supersedes.

**Why.** In every live test on Jet (builds 248–249), the player itself was not what failed: decoding, 90 s holds and automatic failover all worked. The observed failures were in discovery, ranking and source admission, and builds 246–249 fixed those. A parallel engine had already begun to diverge from production rules: `MatchIdentity` is a second, flatter wrong-match guard, and `NativeStreamTransport` chooses the relay differently and drops cookies. One implementation of each safety rule is safer than two.

## Rules for every slice

- **Behaviour-preserving moves.** A slice extracts one responsibility into its own type or file and keeps the view model's public API unless a test is updated in the same slice. A slice may fix a defect only if that fix is the reason for extracting.
- **One implementation per safety rule.** Matching, relay admission and attempt fencing are reused, never re-derived.
- **Gate.** Source membership must be coherent after `xcodegen generate`, the project diff must show only the intended files, and the full Catalyst `FottyTests` must pass with per-test timeouts. Slices touching playback timing also need a Jet live check: Watch → advancing picture → 90 s hold.
- **One slice per commit**, with its receipt in `docs/testing/`.

## Where the weight is (build 249, about 4,850 lines)

| Concern | Lines | Main functions |
|---|---|---|
| Recovery, failover, stalls, backups | ~920 | `recoverSourceStartupFailure`, `validateRecoverableStall`, `nextPlayableSource`, `startPlaybackWatchdog`, backup refresh |
| Native Watch Two and web-to-native handoff | ~850 | `beginNativePlaybackTransfer`, `prepareNativeWatchTwoCandidate`, handoff audio claims |
| Native startup and loading | ~590 | `loadCurrentSource`, `handleSuccessfulStartup`, `requestPlaybackStart` |
| PiP, fullscreen and app lifecycle | ~470 | background/foreground handling, PiP activity, fullscreen rate |
| Continuity and resume | ~260 | `beginSingleNativeResume`, `observeSingleContinuity` |
| UI controls and state | ~250 | `togglePlayPause`, `transition`, auto-hide |
| Diagnostics | ~200 | quality and causal records |
| Audio | ~160 | preparation and isolation |
| Network | ~120 | reachability and network recovery |

## Slices (in order)

| # | Slice | Risk | Status |
|---|---|---|---|
| 1 | `NetworkPathObserver`: one path-monitor owner shared by the view model and `MultiLivePlayerView`, holding its owner weakly. It fixes the audit §2.1-D retain cycle. | Low | **Done** (`7349e44`, build 250) |
| 2 | `BackupFreshness.swift`: a pure `BackupFreshnessPolicy` (which backups to replace and which to renew), a `BackupRefreshScheduler` and the choice collector, moved out of the view model. The view model keeps only guards and wiring. | Low | **Done** (build 251) |
| 3 | `PlaybackProgressPolicy.swift`: every progress threshold and interval as a named, pinned constant, plus a `PlaybackStagnationCounter` value type for the watchdog. The view model's samplers keep their structure and call the policy. | Medium | **Done** (build 252); the live 90 s hold is pending a live match |
| 4a | `PlaybackAttempt.swift`: one value carrying the load request plus an explicit scope (source, playback intent, audio intent), with a single `isCurrent(in:)`. Converted: the network-recovery owner, the native failure observation, the stall-validation owner and its guards, the network-loss task, and the four audio paths (start, handoff claim, resume, PiP). Item identity stays inline (`===`), since a value type must not retain the item. | Medium–high | **Done** (build 254) |
| 4b | Startup (`loadCurrentSource`: request fence, source fence, and a start fence with audio intent), Watch Two resume (sampling and seek callback), the startup waiter, resume-progress evidence, and the web-to-native transfer with its handoff audio leases and candidate audio isolation. | Medium–high | **Done** (build 255) |
| 4c | The remaining 34 continuation fences: web-embed callbacks, web PiP and background suspension, auto-hide, resume validation, URL preparation, item observers, the watchdog and continuity loop, backup refresh, wrong-match reports, Watch Two candidate preparation, audio retirement and diagnostics. Adds `isCurrent(requestID:sourceID:)` and `isCurrent(requestID:)` shorthands. Stored-record state checks (a saved request ID compared with the current one) and the startup observation-end classifier stay as they are. | Medium | **Done** (build 256) |
| 5 | `PlaybackLifecyclePolicy.swift`: the PiP keep-alive rule, the web background action and the native resume-after-foreground rule, as pure tested functions. The orchestration stays in the view model (see the finding below). | Medium; Jet PiP check | **Done** (build 257); Jet PiP check pending a live match |
| 6 | `NativeHandoff.swift`: the Watch Two preflight enums and the handoff diagnostic moved out of the view-model file, a `NativeHandoffCandidateLedger` (one key format and the cap of 12, previously written in two places), one shared item-status label (previously three copies) and the preflight receipt mapping. No controller: the transfer and Watch Two paths use 68 to 76 view-model members each, about half private. | Medium | **Done** (build 258) |
| 7 | `RecoveryCoordinator`: `recoverSourceStartupFailure` and its helpers, built on slices 3–4. | High; Jet live failover check | |
| 8 | Route audio interruptions and route changes to the active player (audit §2.1-E). | Medium; device audio check | |
| 9 | Decide `Fotty/Engine`: delete it, or reduce it to thin wrappers over the production matcher, relay and preparation. Do not keep a second copy of any rule. | Low | |

**Target.** `LivePlayerViewModel` under about 1,500 lines, owning playback state, transitions and composition of the components above.

## Slice 5 finding: lifecycle is not a clean controller seam

Measured on 9 Nov, the background, foreground, PiP and fullscreen block (about 600 lines) uses 107 other view-model members, 55 of them private. They span recovery, audio, discovery, transport and diagnostics. A separate `PlaybackLifecycleController` would need a host interface about as wide as the view model, which moves code without reducing what it depends on. Slice 5 therefore extracted only the pure decisions.

There are two ways to cut the file size further, and both are the owner's call:

- **Extension files.** Move the lifecycle orchestration into `LivePlayerViewModel+Lifecycle.swift`. This shrinks the main file by about 600 lines but widens those 55 private members to internal, because Swift's `private` does not cross files.
- **Leave it.** The owner chose this on 9 Nov. Slice 6 then measured the same pattern for Watch Two and the transfer: the candidate preparation uses 68 members (34 private) and the web-to-native transfer uses 76 (44 private). So slice 6 also extracted only the standalone types and shared rules.

## Fence scopes that differ today (found in slice 4a)

Slice 4 keeps each fence's existing scope, because the active source can change without a new load request (handoff, source selection). These differences are therefore real, and tightening any of them is a behaviour change to decide separately:

- **Startup.** The load task checks the request alone on most guards, but request and source after descriptor negotiation and at startup completion.
- **Watch Two resume.** The sampling loop checks request, source and intent; the seek-completion callback drops the source.
- **Network loss.** The grace task checks the request alone; its owner check (single player only) also covers source and playback intent.
- **Stall validation.** Deduplication keys on request and item; the samples check request and source.

## Receipts

- Slices 1–3: [testing/fotty246-phase-a-2026-11-08/README.md](testing/fotty246-phase-a-2026-11-08/README.md)
