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
| 4b | Convert the remaining fences: startup (`loadCurrentSource`), Watch Two resume, web-to-native transfer and handoff audio leases, startup deadlines. | Medium–high | |
| 5 | `PlaybackLifecycleController`: background, foreground, PiP and fullscreen transitions. | Medium; Jet PiP check | |
| 6 | `NativeWatchTwoController`: the multiview and web-to-native transfer (~850 lines). Multiview work is paused by the owner, so this slice moves code without changing behaviour. | Medium | |
| 7 | `RecoveryCoordinator`: `recoverSourceStartupFailure` and its helpers, built on slices 3–4. | High; Jet live failover check | |
| 8 | Route audio interruptions and route changes to the active player (audit §2.1-E). | Medium; device audio check | |
| 9 | Decide `Fotty/Engine`: delete it, or reduce it to thin wrappers over the production matcher, relay and preparation. Do not keep a second copy of any rule. | Low | |

**Target.** `LivePlayerViewModel` under about 1,500 lines, owning playback state, transitions and composition of the components above.

## Fence scopes that differ today (found in slice 4a)

Slice 4 keeps each fence's existing scope, because the active source can change without a new load request (handoff, source selection). These differences are therefore real, and tightening any of them is a behaviour change to decide separately:

- **Startup.** The load task checks the request alone on most guards, but request and source after descriptor negotiation and at startup completion.
- **Watch Two resume.** The sampling loop checks request, source and intent; the seek-completion callback drops the source.
- **Network loss.** The grace task checks the request alone; its owner check (single player only) also covers source and playback intent.
- **Stall validation.** Deduplication keys on request and item; the samples check request and source.

## Receipts

- Slices 1–3: [testing/fotty246-phase-a-2026-11-08/README.md](testing/fotty246-phase-a-2026-11-08/README.md)
