# Fotty 3.0.0 (246–247): Phase A playback and Watch-gate repair on Jet

Dated 8–9 November 2026 (UTC). Private Jet iPad install only. No TestFlight, Git publication, backend deployment, source-setting change or phone involvement. Source is uncommitted on `wip/ios-3.0-baseline`; see `AUDIT.md` §3 Phase A for the plan this implements.

## What changed (source)

| Item | File | Change |
|---|---|---|
| A1 | `Fotty/Features/Player/LivePlayerViewModel.swift` | A web-embed stall, timeout or generic failure after its one same-source reload now runs the single exhausted-delivery fresh lookup. Explicit provider rejections, denied and unsupported sources stay terminal. Fresh web embeds need no event binding. |
| A1b | same | After a session has decoded, any non-hard failure (including `unknown`) earns that fresh lookup. Hard preparation reasons, typed no-retry failures, access-denied, unsupported and proxy failures do not. The lookup is injectable, and it is a no-op under hosted tests. |
| A2 | `Fotty/Core/Models/CurrentEventBroadcastPolicy.swift` | `canOfferFreshWatch`: a started, verified non-cricket fixture with an enabled discovery-capable source gets Watch with no prior evidence. It is withheld for 60 s after every relevant provider's definitive empty result, and when a catalog row is conflicting or unsupported. The details title reads "Look for a broadcast". |
| A3 | `Fotty/Core/Models/SportsFixtureCatalog.swift`, `MatchListViewModel.swift` | `isUnconfirmedLive`: a verified LIVE receipt observed after kickoff (5 min skew) but older than 30 min stays eligible for lookup and catalog collection until 4 h after kickoff. It is never shown as confirmed LIVE. Adapter identity-receipt freshness is unchanged. |
| A5 | `Fotty/Features/Dashboard/MatchListViewModel.swift` | Concurrent `refresh()` callers join the in-flight refresh. The first caller's cancellation still cancels it. |
| A6 | `Fotty/Features/Player/NativePlaybackPreparation.swift` | Live HLS uses AVFoundation's automatic forward buffer. Progressive mp4 keeps 12 s. |
| A8 | `CurrentEventBroadcastPolicy.swift`, `Fotty/Core/Logging/FottyLogger.swift` | A `watch_gate_suppressed` receipt is recorded at most once per fixture per 10 min. The quality buffer keeps only the 40 newest successful `live_refresh`/`schedule_refresh` records; failures and playback evidence keep their normal retention. |

Not implemented: A4, the per-open-fixture 60 s provider polling. It would raise third-party catalog reads about fivefold while a match is open and awaits an owner decision.

## Device evidence that motivated A1b and the buffer cap

A read-only copy of Jet's app preferences was taken before 245's first launch and deleted after summarising. Only the redacted counts and sequence below were kept.

- All eight source families were enabled on Jet.
- The 250-record quality buffer only reached back to 8 Nov 15:10 UTC. 184 `live_refresh` and 27 `schedule_refresh` successes had evicted the 7 Nov Leeds–Tottenham window, so **that incident cannot be diagnosed from this device**.
- 8 Nov 15:10–16:07 UTC, single native CS session: CS3 failed twice (network), and CS5 decoded at 15 s. CS5 played about 55 min with three short stalls, then hit a stall timeout at 16:06:52. Automatic failover reached CS2, CS4 and CS6, all from the original discovery and all failed within 35 s. The last was classified `unknown`, and the session ended in `terminal_failure` **without a fresh lookup**. This is the A1b gap.
- `broadcast_registry_refresh` failed with `network` four times between 16:45 and 18:45 UTC. Not investigated further here.

## Verification

| Check | Result |
|---|---|
| Full Catalyst `FottyTests` (Xcode 27.2, deployment override 26.1, 60 s per-test timeouts) | 2,709 run, 0 failures, 12 physical-only skips |
| Isolated `VisualRegressionTests` | pass (run against the A1–A8 source; not rerun after A1b, which touches no UI) |
| Native source membership | coherent (Fotty=214, FottyTests=92) |
| Signed Release 3.0.0 (246), app and widget | both `CFBundleVersion` 246; `codesign --verify --deep --strict` ok |
| Install on Jet iPad (iPad13,1) | `devicectl` reports 3.0.0 (246) |
| `tools/ios-physical-launch-hold.sh`, 60 s | foreground process present at every 10 s sample |
| Post-launch quality buffer | 249 → 78 records; the 15:10–16:07 playback incident retained; routine successes capped at 40 |

Fifteen existing tests that encoded the old rules were updated, not deleted. They covered "no Watch without evidence", the 30-minute live fence, "an overlapping refresh returns immediately" and "a failed renewal is terminal without a fresh lookup". Build 245 was installed briefly before A1b and replaced by 246; it was never used for playback.

## Build 247 additions (9 Nov): backup freshness during playback

Motivated by the same Jet session. The backups tried at 16:07 UTC were about 56 minutes old, and each needed its own descriptor renewal when chosen.

| Item | Change |
|---|---|
| Backup refresh | Every 10 min while a single, non-channel match is playing, one exact lookup runs through the same injected resolver path. Its results replace older backups of the same provider family. The playing delivery keeps its index and transport, other families are untouched, an empty result changes nothing, and paused, failing or recovering sessions make no request. A completed refresh renews the single exhausted-delivery lookup budget. |
| Parallel renewal | When failover chooses a backup, up to two more backups whose 90 s event binding has lapsed are renewed concurrently, capped at two in flight. This is the same `refreshSourceDescriptor` call and `binding.matches` check as the serial path. No media, relay or validator request is made. A renewal that fails spends that source's one renewal, so it is skipped quickly. |

Not done, deliberately: parallel manifest probing. Every backup with headers or a playlist profile, which is nearly all CS, is validated through a loopback relay scoped to the one selected stream. Probing several would mean pre-starting relays outside that scope.

Verification for 247: full Catalyst FottyTests 2,712 run, 0 failures, 12 skips, with three new tests. They cover same-family replacement with a fixed playing index, no request while paused, and two concurrent renewals with no third and no duplicates. The signed Release app and widget are both at 247, and the Jet launch hold of 60 s passed. Request cost: about 6 lookups per hour per playing match. Each runs the enabled providers' exact lookup with the existing discovery deadline; the match's catalogs are not polled continuously.

## Not established

- **No live-match Watch → picture → forced failure → recovery cycle has been observed.** No PL/UCL/cricket match was live at install (01:05 UTC 9 Nov). Three NHL games were live, but the screen was not observed and no Watch was tapped.
- **Whether the fresh lookup finds a working backup in practice.** That depends on provider supply at the time; the unit tests prove only that the lookup runs.
- **The unsigned generic iOS Release CI build was not run separately.** The signed Release device build of the same source compiled.
- Decisions-Log and Current-State are not yet updated, because a sibling session has uncommitted edits there. The draft entry is in the session notes folder.

## Suggested owner acceptance (when a PL/UCL/cricket match is live)

1. Cold-open Fotty on Jet and confirm the live match shows **Watch** without "Check streams".
2. Tap Watch and note the time to a correct, advancing picture.
3. When a source stalls or fails, note whether the player says "Checking more sources…" and whether it recovers.
4. Close and reopen Fotty, then tap Watch again.
5. Afterwards, ask for the quality records to be read, which needs a cable and an agent session. The buffer will now retain the attempt.

## Live cricket check on Jet, 9 Nov 10:30 UTC (build 247)

`WatchRetry220PhysicalUITests/testCurrentNamedMatchThroughWatch` ran on Jet against `cricket-fixture:icc:274140`, the Pakistan v Sri Lanka Test, through the `FottyFoundationUI` Release runner with `FOTTY_WATCH220_PHYSICAL=1`. Provider audio was muted. The owner enabled UI Automation on Jet for this run; the first attempt had timed out enabling automation mode.

| Observation | Result |
|---|---|
| Watch on Home | present and tapped by the runner |
| Time to first picture | 9.06 s after the tap (UI test); `decoded_progress` 6.06 s after the attempt started |
| Route | TV1, Willow Cricket (reviewed TV, registry programme binding) |
| 90 s continuity | `native_continuity_90s` success: 92.1 s of media advance, 0 stalls, 0 dropped frames, 1280×720 |
| Correct programme | screenshots show Willow Live with PAK 240-4 (58.5 ov) before the hold and 241-4 (59.1 ov) after |
| Alternatives | picker showed 1 source at the start and after the hold |

Why there was no backup:

- **CS**: the direct fallback ran (the device registry had no CS association). It returned 4 entries and admitted 0: one support link, two `/api` wrappers around plain HTTP to raw IP addresses (correctly rejected by policy), and one `/api/….m3u8` wrapper around an HTTPS target. That last one fails only because `/api` is not a reviewed CS route. Admitting it needs an explicit security review.
- **AS**: the manifest returns HTTP 402 (Payment Required), confirmed with a direct GET at 10:3x UTC. The add-on appears paywalled on the provider's side.
- **Flix**: the catalog returned HTTP 503.

Not exercised: failover and recovery, because there was nothing to fail over to, and the forced-outage drill needs a private build flag. The two U19 ODIs had only `needsVerification` registry rows. Record copies and test attachments were deleted after summarising.

## Build 248: CS `http` provenance admission and live alternate check (9 Nov, 10:51–10:56 UTC)

**Change.** `CommunitySportsAddonClient.admittedRequestHeaders` now accepts plain-`http` Referer/Origin page labels under the contract in `CS-http-provenance-review.md`:

- only for the reviewed `nuviosports.xyz` manifest and its literal `/api/manifest(.m3u8)` route;
- only when the single nested target passes the HTTPS/public destination rule;
- the labels must be public DNS names on the default port, with no credentials, query or fragment, and must match their URL parameters exactly;
- Fotty then **drops** those two headers and sends User-Agent only.

There are two new tests covering one admission case and fifteen rejection cases, plus a check that the relay still never forwards `http` provenance. Full Catalyst suite: 2,714 run, 0 failures, 12 skips.

**Live check.** `testCurrentNamedMatchThroughWatch` with `FOTTY_VERIFY_ALTERNATE=1` ran on Jet against the Pakistan v Sri Lanka Test (Release 248 runner, provider audio muted). It passed in 300.7 s.

| Step | Evidence |
|---|---|
| Sources offered | TV1 (Willow) and **CS1** (T Sports HD 720p): 2 sources, up from 1 under build 247 |
| Initial choice | CS1 started first; the preflight had already found it, while TV1 joined later |
| CS1 cold start | `readiness_timeout` after the 20 s startup deadline: item status unknown, waiting to minimise stalls, 0 access stalls |
| **Automatic failover** | `automatic_failover` CS1 → TV1 with no user action; TV1 decoded 6.9 s later; the test measured 33.52 s from Watch to first picture |
| TV1 hold | `native_continuity_90s`: 92.1 s, 0 stalls, 720p |
| Manual switch to CS1 | decoded in 10.2 s; `native_continuity_90s` 92.1 s, 0 stalls, 720p |
| Programme | the CS1 screenshots show T Sports HD Live carrying PAK 253-5 at 63.4 overs, then 63.5 overs: the correct live match |

**New finding (not fixed).** The first choice is "whichever source arrives first". TV1 had decoded this exact fixture 20 minutes earlier, but CS1 was chosen ahead of it, and its cold start cost 20 s before failover. A short wait for a sibling with recent positive history on the same fixture, or starting that sibling first, would have produced a picture in about 7 s.

Not exercised: mid-match failure recovery under real conditions (A1/A1b) and the 10-minute backup refresh (build 247). Jet now runs Release 3.0.0 (248).

## Build 249: per-match evidence survives relaunch (owner option A, 9 Nov 11:12–11:17 UTC)

**Decision.** The owner chose option A: per-match delivery evidence persists across relaunch so that a reopened match prefers the delivery that just sustained it. Option B, a coarse sport/league last-good hint, was declined.

**Change** (`LiveSourceHealthStore`):

- The HMAC key for match evidence is now device-local, stored in the Keychain as `com.jelani.Fotty.match-evidence.v1`: `AfterFirstUnlockThisDeviceOnly`, not synchronizable, data-protection keychain. It was previously random per launch. If the Keychain is unavailable, behaviour stays per-launch and nothing is persisted. Hosted tests never touch the Keychain.
- Match observations and wrong-programme reports persist as `fotty.live.matchEvidence.v1`. They hold HMAC digests only, with the same 6 h lifetime and caps: 128 deliveries × 8 observations, and 256 reports. They load lazily, are saved after each observation, and are never written during drills. They are not part of private backup.
- Two tests cover the round trip (sustained and wrong-programme evidence survive and stay scoped to their fixture) and expiry beyond 6 h. A test-only hook simulates the relaunch. Full Catalyst suite: 2,716 run, 0 failures, 12 skips.

**Live check.** Two consecutive `testCurrentNamedMatchThroughWatch` runs on Jet against the Pakistan v Sri Lanka Test, each a fresh app launch:

| Run | Selection reason | Source | Decoded (app) / picture (test) | 90 s hold |
|---|---|---|---|---|
| A | `same_pick` (no evidence) | CS1 | 7.7 s / 9.63 s | 92.9 s, 0 stalls |
| B, relaunch | **`played_this_fixture`** | CS1 | 6.7 s / 8.75 s | 92.6 s, 0 stalls |

After run A the device stored one evidence entry (CS1, sustained). Run B chose the source from that persisted evidence, which the store used to discard on every launch. Note that CS1 also started cleanly here, so the 20 s cold-stall case of build 248 did not recur. That run is what proves the fix is needed; these runs prove the mechanism works. AS (402) and Flix (503) were still unavailable. Provider audio is muted only for runner-launched sessions (`FOTTY_PHYSICAL_LIVE_TEST`); a normal launch plays audio. Jet now runs Release 3.0.0 (249).

## Build 250: player shrink slice 1, `NetworkPathObserver` (9 Nov, 11:50 UTC)

**Change.** The owner chose to shrink `LivePlayerViewModel` in place ([PLAYER-SHRINK-PLAN.md](../../PLAYER-SHRINK-PLAN.md)); `REDO-PLAN.md` is marked superseded. Slice 1 moves the system path monitor into one `NetworkPathObserver` (`Fotty/Core/Media`), now used by both the view model and `MultiLivePlayerView`. It holds its owner weakly, which fixes the AUDIT §2.1-D retain cycle, and exposes `isRunning`/`startCount` for tests. The reachability policy is unchanged and stays in the view model. `xcodegen generate` reproduced the project with only the new file's four lines; membership is Fotty=215.

**Tests.** A new leak test shows that a player which started network monitoring but was never cleaned up is released. Nine existing assertions now go through the observer API; the "repeated start reuses the monitor" check now uses `startCount`. Full Catalyst suite: 2,717 run, 0 failures, 12 skips.

**Jet live check (Release 3.0.0 (250)).** Pakistan v Sri Lanka Test, Watch on CS1 (chosen from persisted evidence): first picture 9.41 s after Watch, then the 90 s hold passed in a 143.7 s test. Provider audio was muted (runner launch).
