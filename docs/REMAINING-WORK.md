# Fotty — remaining work report

Date: 2026-11-09. Originally drafted by DeepSeek. **Corrected the same day** against the repository, the live Worker and same-day device evidence. The corrections are listed in §5. Receipts:

- the audit: [AUDIT.md](../AUDIT.md)
- builds 246–249 and the live checks: [testing/fotty246-phase-a-2026-11-08/README.md](testing/fotty246-phase-a-2026-11-08/README.md)
- the CS security review: [CS-http-provenance-review.md](testing/fotty246-phase-a-2026-11-08/CS-http-provenance-review.md)

## 1. Current state

**Deployed (live):**

- **Worker freshness fix** `2026-11-07.live-freshness-1`. `/health` reports this version, and it is committed on `wip/ios-3.0-baseline`. A follow-up live-window cadence rewrite (`2026-11-08.live-window-registry-1`) is **local and undeployed**: a sibling session's uncommitted edits under `web/workers/playback` and `tools/audit-*`.

**Installed on Jet only (private Release builds, not TestFlight), from uncommitted source:**

| Build | What changed | Verified |
|---|---|---|
| 246 | Cold-start **Watch** for a started, verified non-cricket fixture with an enabled source: the resolver decides, with no "Check streams" step. A stale LIVE receipt stays eligible for lookup up to 4 h after kickoff. A fresh lookup runs after a web-embed or decoded-session failure. Concurrent refreshes share one fetch. Live HLS uses the automatic buffer. A `watch_gate_suppressed` receipt is recorded. Routine refresh successes are capped at 40 in the quality buffer. | Full Catalyst suite and 60 s launch hold |
| 247 | Backups refresh every 10 min while a match plays, replacing the same family's older choices. Failover renews the next two backups in parallel, capped at two in flight. | Full suite and launch hold |
| 248 | CS deliveries with `http://` Referer/Origin are admitted on the reviewed `/api/manifest(.m3u8)` route only. The nested target must be HTTPS on a public host, and Fotty drops those two headers. | Live: Pakistan v Sri Lanka had 2 sources (Willow TV1 + CS1 T Sports HD); both showed the correct match and held 90 s with 0 stalls. **Automatic failover** CS1 → TV1 happened after a 20 s cold stall. |
| 249 | Per-match playback evidence survives relaunch for 6 h. It is HMAC'd with a device-only Keychain key and capped (owner option A). | Live: after relaunch the selection reason was `played_this_fixture`, with a picture in about 9 s versus 33.5 s before |

The full Catalyst unit suite at 249: **2,716 run, 0 failures, 12 device-only skips**.

**Built, not wired into the app:** `Fotty/Engine/` (`PlaybackState`, `MatchIdentity`, `SourceResolver`, `StreamTransport`, `PlaybackEngine`, `NativeStreamTransport`), with 32 engine tests. Playback still runs through `LivePlayerViewModel`, `LiveWebEmbedPlayerView` and `LocalStreamProxy`.

**Provider status observed 9 Nov:**

- **AS** (`addon.plavio.site`) manifest returns **HTTP 402**. It appears paywalled by the provider.
- **Flix** catalog returned **HTTP 503**.
- **Willow TV and CS** were the only working sources for live cricket.

**Plan:** `docs/REDO-PLAN.md` (Steps 4–7 and the §3.2 extraction map).

## 2. What needs to be done (prioritized)

### P0 — Commit today's work (do this before anything else)

The branch is pushed and in sync with `origin/wip/ios-3.0-baseline`. What is **not** committed is everything the Jet now runs:

- the Swift changes for builds 246–249, across 5 `Fotty/Core` files, 3 `Fotty/Features` files and 9 test files;
- `AUDIT.md`;
- the receipts under `docs/testing/fotty246-phase-a-2026-11-08/`;
- this report.

The sibling session's undeployed Worker and monitor edits are also uncommitted. That is 35 working-tree entries in total.

1. Commit the native work in reviewable commits:
   - Phase A (246)
   - backup freshness (247)
   - CS `http` provenance (248)
   - persisted match evidence (249)
2. Leave the Worker and monitor edits to the session that owns them.
3. Prepend the drafted Decisions-Log entry. It is in the session notes as `phase-a-decisions-entry.md`, waiting because `Decisions-Log.md` has the sibling's uncommitted edits.
4. Run `./tools/agent-finish.sh`.
5. Local `main` is 32 commits behind `origin/main` by the last-fetched refs. Merging `wip/ios-3.0-baseline` back is a separate, publication-gated step.
6. Confirm `xcodegen generate` reproduces `Fotty.xcodeproj` with no drift. Source membership is currently coherent (Fotty=214, FottyTests=92).

### P0 — Live acceptance still open

- **Mid-match recovery under real conditions:** a source that dies after playing (A1/A1b) and the 10-minute backup refresh. Today's checks covered cold start, startup failover and manual source switching only.
- **The normal app with audio.** Runner-launched sessions mute provider audio by design (`FOTTY_PHYSICAL_LIVE_TEST`).
- **A PL/UCL match**, the owner's top priority. Today's live checks were cricket only.
- **Reading the quality records after a real failure.** The buffer now retains them.

### P1 — Finish Step 4 (native transport port)

The seam exists; the real transport is still in `LivePlayerViewModel` (about 4,900 lines). Extract it into `NativeStreamTransport`, preserving the source, request and intent fences (`loadRequestID`, `sourceID`, `requestID`, `nativeWatchTwoIntentID`). Line numbers are as of build 249:

| Concern | Location in `LivePlayerViewModel` |
|---|---|
| Item failure observers (`failedToPlayToEndTime`, `playbackStalled`, `newErrorLogEntry`) | `configureItemFailureObservers` (about L2872) |
| Status KVO (`item.observe(\.status)`) | inside `configureItemFailureObservers` |
| Observer teardown | `removeItemFailureObservers` (about L2939) |
| Decoded-frame sampling | `decodedFrameSample` (about L2856) |
| Native resume progress | `observeSingleNativeResumeProgress` (about L2761) |
| Playback start | `startPlaybackIfNeeded` (about L987) |
| Recovery and backup freshness | `recoverSourceStartupFailure`, `refreshBackupsOnce`, `prefetchDescriptorRenewals` |
| Teardown (proxy, observers, player) | `cleanup` and throughout |

Then the WebKit transport, the relay transport, and audio/PiP/recovery. This is the **multi-week core** of the redo. Do it slice by slice with the full Catalyst gate, and run a physical Jet check after the player migration. Either wire in `Fotty/Engine` or delete it, so it does not drift as dead code.

### P1 — Step 5 (freshness and observability)

Parts are already done:

- per-match backup refresh during playback (247);
- the Worker live-window cadence (written, **not deployed**);
- typed, redacted per-attempt quality records (existing), which now survive the buffer cap.

Remaining:

- deploy or replace the Worker cadence under its own gate;
- decide on **A4**, polling the open match's catalogs every 60 s. That is about 5× the third-party catalog reads while a match is open, and was held for an owner decision.

### P1 — Step 6 (UI migration)

Migrate Home/Matchday/Player onto the engine and direct resolver, one screen at a time. Delete `LivePlayerViewModel` only after the physical gate passes: live → correct picture → forced failure → recovery → close/reopen → Watch.

### P2 — Step 7 (deletion)

In dependency order:

1. Remove registry-as-gate from the remaining paths. The native Watch gate already treats the registry as a hint for non-cricket fixtures (246).
2. Remove the unused scheduler debt.
3. Prune optional source families. **Guard:** keep the reviewed **TV (Willow/Fox)** source and **CS**, which were the only working live-cricket sources on 9 Nov. AS currently returns 402.

### P2 — Consolidate the Stremio-protocol add-on clients

CS, AS, CNC, Flix and StreamVix are five separate clients (about 5,100 lines) for the same manifest → catalog → meta → stream protocol. Each has its own caching, timeouts and admission. Merge them into one protocol client with a policy per provider.

### P2 — Lint ratchet

**Correction:** production Swift has about **60** force-unwrap-style `!` uses, with **0** in `LivePlayerViewModel`. The earlier "2,267 / 288" figures counted negation and `!=`. There is one `as!` and no `try!`. Other counts:

- 23 `URL(string:)!` literals;
- 28 `print` calls;
- 27 empty `catch {}` blocks;
- about 40 unique compiler warnings in `logs/verify-latest.log`.

SwiftLint and SwiftFormat are installed but not configured. Add a non-blocking `swiftlint lint` step with a ratchet, then fix the warnings.

### P2 — Retired infrastructure still in code

- `Config.swift` defines `pocketBaseBaseURLString`/`pocketBaseBaseURL`, though nothing else uses them.
- The web app still has `src/app/collab` and `src/app/favorites`. The earlier mention of `subscribe`/`login` routes was wrong: they do not exist.
- The Worker enumerates some retired sources (not re-verified here).
- `StringObfuscator` hides provider hosts. It is not a security control.

### P2 — Process overhead

There are about 850 docs, 115 release notes and 105 files under `docs/audit`. Consolidate them into the living `Current-State.md`, the decision log and the risk register.

## 3. Risks and guardrails

- **Watch at cold start is approved behaviour; do not revert it.** Since 246, a started, verified non-cricket fixture with an enabled discovery source offers Watch and lets the resolver decide (owner decision, 9 Nov). Exceptions:
  - it is withheld for 60 s after every provider returns a definitive empty result;
  - it is withheld when a catalog row is conflicting or unsupported;
  - cricket keeps its evidence-first rule.

  The earlier "never invent a Watch action" rule is superseded. What still holds: never show a provider listing or LIVE status that was not observed.
- **Never weaken exact matching.** Sport, team pair, kickoff and conflict veto remain the wrong-match guard. Adapter identity-receipt freshness is unchanged.
- **Transport and relay exceptions change only through a recorded review.** The reviewed 8443 and playlist-profile contracts and the 9 Nov CS `http`-provenance rule are the whole set. They are narrow, documented and tested; HTTP and IP-literal media destinations stay rejected.
- **Per-match evidence is device-local.** It uses a Keychain HMAC key (this device only), lasts 6 h, is capped, and is not exported by private backup. Do not sync or export it.
- **Gates.** No backend deploy, TestFlight, Git publication or device install happens without its own gate, per `AGENTS.md`.
- **Physical acceptance.** A unit or compile pass is not decoded playback. A runner-driven check is muted and does not prove audio.

## 4. Recommended sequence

1. Commit today's native work and the receipts; apply the Decisions-Log entry and run `agent-finish` (P0).
2. Live acceptance on Jet during a PL/UCL match: normal launch with audio, a mid-match failure and its recovery, then reopen.
3. Finish Step 4 native transport (KVO/decoded-frame) → WebKit → relay → audio/PiP/recovery.
4. Step 6 player migration and the device gate.
5. Step 5 remainder: the Worker cadence deploy (its own gate) and the A4 decision.
6. Step 7 deletion (keep TV and CS) and the add-on client consolidation.
7. In parallel, as time allows: the lint ratchet, retired-infrastructure cleanup and docs consolidation.

## 5. Corrections to the original draft

| Original claim | Correction |
|---|---|
| "~812 uncommitted files"; shipped fixes not committed | 35 working-tree entries. The branch is pushed and in sync, and the deployed Worker fix is committed. Today's native work (Jet 246–249) is what is uncommitted. |
| "Check streams" cold-start fix that "never fabricates Watch"; guardrail "never invent a Watch action" | Superseded by the owner-approved cold-start **Watch** (246), verified live. |
| "Never broaden transport/relay exceptions" | One narrow, reviewed exception was added on 9 Nov (the CS `http` provenance) and is now part of the documented set. |
| "2,267 force-unwraps; 288 in `LivePlayerViewModel`" | About 60; 0 in `LivePlayerViewModel`. |
| Retired web routes `subscribe`, `login` | Not present; `collab` and `favorites` are. |
| "31 engine tests" | 32. |
| "40+ audits" | 105 files under `docs/audit`; the order of magnitude stands. |
| "Keep CS + one reliable second" source family | Must keep the reviewed TV source. AS is currently paywalled (402). |
| "521/521 worker tests green" | Not re-run here. About 494 test cases are in `web/workers/playback/src`; the sibling session reports 647 for its newer change. |
| `LivePlayerViewModel` line numbers | They shifted with builds 246–249; updated above. |
| Builds 246–249, the CS review, the AS/Flix status and the open live gates | Missing from the original; added. |
