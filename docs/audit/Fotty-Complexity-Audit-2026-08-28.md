# Fotty complexity and reliability-boundary audit

Date: 2026-08-28. Status at audit completion: **audit complete; fixes not implemented**.

Follow-up: the owner subsequently authorized fixes. See [the implementation and verification record](Fotty-Complexity-Fixes-2026-08-28.md) for current local status. The measurements and failing results below remain the historical pre-fix baseline, not current release status.

## Verdict

The audit was worthwhile. The main opportunity is targeted reliability work, not a wholesale rewrite. Offline probes reproduced **five boundary failures** in unchanged production code: two playback-monitor cases, two FPL/Coach cases, and malformed Coach request handling. All **11 existing Worker tests pass**, so these expose gaps in the tested cases rather than failures of those existing tests.

Fix the false playback stall, unsupported FPL autosub, and scoring-to-model fallback first. Then address unrelated-media errors and request validation. Refactoring should preserve those fixes with regression tests, not merely reduce complexity numbers.

These are synthetic, deterministic reproductions of source behaviour. They do not establish that any particular previous incident on the owner's device had the same cause.

## Scope and evidence

- Current working tree advertising **2.0.0 (42)**, including existing uncommitted/untracked app work. This is not a binary inspection of the TestFlight upload.
- Measured all **161 Swift files** under Fotty and FottyLiveActivityExtension; inspected the active playback, FPL, catalog and reminder paths in more depth.
- Measured the active Worker entry point, its FPL scoring module, and the actual JavaScript monitor embedded in LiveWebEmbedPlayerView.
- Reviewed existing Swift tests and ran the two Worker test files. No new Swift/XCTest, device, UI, performance, coverage-instrumentation or provider-playback run.
- The companion Next.js UI, retired servers, dependencies and generated/build products are outside this focused audit. Conditional compilation and retained legacy Swift were not eliminated from the raw scan; they are distinguished below.
- No app code, production test, version, release setting, dependency manifest or deployed service was changed. Added audit evidence/runners and updated durable documentation only.
- No simulator, Xcode build, device install, live FPL request or paid model request. Worker fetches in the probes are replaced by local stubs. The official 11.4 MiB SwiftLint download is temporary, checksum-verified and removed by its context manager; no global installation or lint cache.
- Snapshot: **192 source/resource/config/test files**, SHA-256 **78ba4084d7e9f830f746942d88a402633e5c7b28cb54a2a049406e3a4845c503**. This covers the app, extension, Swift tests, Worker sources, project.yml and Xcode project; it intentionally excludes audit/memory documents.

## Measurements and their limits

| Scope | Tool | Scores >10 | Scores >20 | Highest |
|---|---|---:|---:|---:|
| Swift app/extension, including retained and conditional code | SwiftLint 0.65.1 | 45 | 3 | 27 |
| Worker entry point + FPL scoring, 135 functions/callbacks | ESLint 9.39.4, classic | 12 | 3 | 79 |
| Embedded playback monitor, 57 functions/callbacks | ESLint 9.39.4, classic | 6 | 0 | 19 |

The Swift scan has 869 bodies with a nonzero reported complexity score; that is **not** the total number of functions in the codebase. Zero-score bodies are omitted by the audit's warning threshold. No runtime coverage percentage is inferred.

The tools count differently. SwiftLint's syntax score calibrated at 3 for one if, one guard and one while; a raw string containing JavaScript branches did not inflate its score. ESLint classic includes its initial path and conditional operators/optional chains. **Do not interpret 79 versus 27 as a cross-language risk ratio.** The thresholds above are sorting aids, not acceptance gates. The audit configuration deliberately reports small values to collect a baseline; it is not installed in CI.

A preliminary Lizard calibration failed to recognize a function containing a Swift raw multiline string, so its output was discarded. The final Swift metrics use SwiftLint's Swift-native parser. The embedded script was separately extracted, its six known interpolations resolved from source, Swift backslash escaping decoded, and JavaScript parsed. The rest of the Swift file's short injected command strings are not included in the JavaScript count.

Tool references: [SwiftLint complexity rule](https://realm.github.io/SwiftLint/cyclomatic_complexity.html), [pinned SwiftLint release](https://github.com/realm/SwiftLint/releases/tag/0.65.1), [ESLint complexity semantics](https://eslint.org/docs/latest/rules/complexity).

## Ranked reproduced findings

### 1. P1 — A replacement video can falsely fail while making progress

Source: [inspectProgress](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift:623).

The monitor retains lastProgressTime from the old video. It accepts a replacement when the old element disconnects, but does not reset that time baseline when it changes playbackVideo. A new element whose playhead restarts below the old timestamp cannot update lastProgressAt until it catches up.

**Reproduction:** Confirm a video at 300 seconds, disconnect it, supply a replacement at one second, and advance the replacement every second for 40 seconds. The unchanged monitor emits “Playback stalled: decoded playhead stopped advancing.” The deliberate-pause control still passes.

**Impact:** A provider replacing its video element can trigger app-origin recovery/reconnection despite advancing media. The Swift coordinator delays the failure, but repeated real progress below the stale timestamp cannot emit the expected recovery signal.

**Recommended fix/test:** Reset the progress baseline on confirmed media identity/time-origin changes while preserving source/attempt ownership. Add replacement-element, same-element playhead-reset/seek, genuine frozen-video and deliberate-pause tests. Verify the same-source recovery on an iPad after implementation; the current evidence is the exact script in a mocked DOM, not physical WebKit.

### 2. P1 — Missing FPL live data becomes a confirmed non-appearance

Source: [Worker row construction](/Users/jelani/Documents/Development/Fotty/web/workers/playback/src/fpl-scoring.mjs:77).

A missing liveById entry becomes an empty stats object. That becomes played=false and zero minutes; a completed fixture then produces confirmedNoAppearance=true. Absence of evidence is being treated as evidence that the player did not play.

**Reproduction:** Start with a complete fixture where every starter appeared and no autosubs are projected. Remove only the starting keeper's live-stat row. The Worker now projects Kelleher replacing that keeper, despite having no non-appearance evidence.

**Impact:** A partial data response can produce the wrong substitution and total in the Coach evidence. This also reveals Swift/Worker drift: the [Swift candidate builder](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Services/FPLDecisionEngine.swift:282) requires a live-stat row and skips a missing candidate. That is source-level comparison, not a freshly executed Swift parity test.

**Recommended fix/test:** Represent unknown, appeared and confirmed-absent separately; require complete relevant evidence before projecting. Keep the official total and expose incomplete data rather than replacing it. Use shared fixture cases for both engines: missing/duplicate stats, missing player metadata, captain/vice, Bench Boost, Triple Captain, hits, published autosubs and double-gameweek boundaries. Do not assume the rest of either engine is safe for partial data merely because this keeper case is identified.

### 3. P1 — A points question falls through to the model when official scoring is unavailable

Source: [Coach routing](/Users/jelani/Documents/Development/Fotty/web/workers/playback/src/index.js:1252); [client response acceptance](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Services/FPLSmartCoachService.swift:402).

The deterministic return requires both a scoring question and a populated scoring result. If refreshing official evidence fails, the same points question proceeds to DeepSeek with client-context-only status. The client checks that status is nonempty, not that it proves usable scoring evidence.

**Reproduction:** Locally fail all four official evidence requests and send “How many gameweek points do I have?”. The Worker makes one **simulated** model call and accepts a synthetically invented 99-point answer with HTTP 200 and client-context-only status. No real model was called and no actual account total was evaluated.

**Impact:** The zero-model, verified-scoring guarantee fails on the error path; it can spend tokens and accept an unsupported numerical answer. The normal iOS path handles scoring locally when a live summary is available, but [its deterministic branch](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Services/FPLAICoachService.swift:65) requires that summary. This is a missing-data fallback defect, not a claim that every points question currently uses DeepSeek.

**Recommended fix/test:** Classify factual scoring questions before considering model fallback. Return a deterministic incomplete-data/retry response when scoring is unavailable; retain a clearly dated known official total if supported. Add route-level tests asserting zero model calls for failed, missing and stale scoring evidence. Keep general tactical advice distinct from requests to calculate points.

### 4. P2 — Errors from unrelated video elements can fail the broadcast

Sources: [DOM error listener](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift:662), [Swift failure routing](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift:882).

The error listener accepts every VIDEO target, whereas progress/transport logic tracks the selected playbackVideo. After confirmed playback, an unrelated video reporting media error 4 produces stream_failed for the broadcast.

**Evidence limit:** The probe proves the erroneous bridge message. Continuous primary-video progress may cancel the coordinator's eight-second recovery grace, so it does not prove every such error causes a visible source switch. If primary playback is briefly buffering, the unrelated error can nevertheless enter the shorter failure path before the normal 30-second stall boundary.

**Recommended fix/test:** Correlate post-start errors with the primary media and document; separately handle genuine pre-start provider rejection. Test an auxiliary/ad video error, a primary error, stale child-frame messages and recovery during the grace period. Do not remove provider controls or indiscriminately suppress errors.

### 5. P2 — Valid JSON of the wrong shape escapes controlled request handling

Source: [request parsing](/Users/jelani/Documents/Development/Fotty/web/workers/playback/src/index.js:1240).

JSON parsing accepts null, then body.query throws outside the provider-request error handler. Calling the exported Worker route with a null JSON body produces TypeError rather than a controlled 400 response.

**Priority context:** This is request-boundary hardening, not an observed ordinary iOS user action. No remote request was made to demonstrate it.

**Recommended fix/test:** Validate an object request and the types of nested history/context collections before property access or iteration. Cover null, arrays, scalars, malformed collections, oversized requests and unavailable rate-limit bindings with local route tests.

## Maintainability priorities, distinct from reproduced defects

| Area / function | Measured score | Assessment and next useful action |
|---|---:|---|
| Worker handleFplCoach, line 1221 | ESLint 79 | Highest active hotspot: mixes request validation, evidence acquisition, deterministic routing, capacity controls, model transport, output validation and usage. Add failure-path tests, then separate those responsibilities. |
| Worker buildOfficialFplEvidence, line 1067 | ESLint 47 | Separate gameweek selection, endpoint retrieval/completeness and evidence compaction. Test planning/live/final phases and partial endpoint failure. A recent timestamp alone is not completeness. |
| Worker resolveFplScoring, line 65 | ESLint 47 | Keep deterministic authority. Establish cross-language fixtures and missing-data policy before splitting normalization, substitutions, captaincy and totals. |
| Swift WebKit bridge, line 850 | SwiftLint 27; 130 body lines | Typed event decoding plus a pure, attempt/document-scoped transition policy would make delayed effects easier to test. Existing immediate guards are valuable; preserve them. |
| Embedded inspectProgress / set-playing / startup-assist callback | ESLint 19 each | Individually below 20, yet their shared state contains the reproduced playback defects. Scores alone would miss the priority. |
| FPLSquadOptimizer.optimize, line 216 | SwiftLint 23; 130 body lines | Constraint-heavy algorithm with final shared validation. Keep bounded iterations, locks, exclusions, budget and club limits. Add infeasible-lock/budget and property-based legality tests; do not change optimization strategy just to lower a score. |
| FPLAdvisorViewModel.loadData, line 356 | SwiftLint 17; 194 body lines | Many responsibilities, but request/manager/cancellation checks exist after key awaits. Separate immutable fetched snapshots, pure decision-building and one guarded state commit; test refresh/manager-switch overlap. No new race was reproduced here. |
| MultiView loadCurrentSource, line 793 / single-player loadCurrentSource, line 538 | SwiftLint 19 / 13 | Duplicated startup/recovery responsibilities can drift. Establish common policy tests before sharing machinery; do not force different audio/focus semantics into one controller. |
| MatchReminderStore.performReconcile / performEnable | SwiftLint 14 / 13 | Higher scores largely reflect useful permission, capacity and cancellation safeguards. The serialized queue and per-event revisions should remain. **29 reminder test methods** exist, including cancellation during permission/add/reschedule and concurrent opt-ins; reviewed, not rerun here. Lower-priority refactoring. |
| Category/status/icon/tool-destination switches | SwiftLint 11–18 | Mostly straightforward mappings. Low priority despite their counts; no feature rewrite is justified by the numbers. |
| AceSessionEngine.prepareSessionInternal | SwiftLint 27; 241 body lines | Retained P2P/warmup code, not the active StreamEx/Score808 Watch path. Do not put it ahead of active playback defects. Inventory/deletion is a separate approved cleanup. |

The raw scan also flags legacy resolver/P2P helpers and diagnostic/social paths. The [active resolution track](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Internal/HybridStreamProvider.swift:901) runs the web provider only. Some legacy code remains compiled; only the old Hybrid branch is explicitly behind FOTTY_LEGACY_P2P. “Retired” must not be confused with “all deleted or compile-excluded.”

## Verification and proposed sequence

1. **First patch:** regression tests plus findings 1–3. Keep changes narrow; no redesign or new product features.
2. **Second patch:** findings 4–5 and the Worker route-failure matrix. Share scoring fixtures across Swift/JS and make evidence completeness explicit.
3. **Then refactor:** extract Coach responsibilities and playback transition policy in behaviour-preserving steps. Retain before/after baselines and run the existing suites; avoid lowering a metric merely by moving conditions into anonymous helpers.
4. **Later guardrail:** add an approved changed-code complexity baseline to CI, with reviewed exceptions for straightforward switches. No explicit production cyclomatic-complexity rule was found in the project/CI configuration. Do not fail every existing hotspot at once.
5. **Release qualification after fixes:** sequential bounded Swift tests/builds, followed by real iPad playback/recovery acceptance and the normal TestFlight process. None of those actions is part of this audit.

Fresh results:

- SwiftLint and ESLint scans completed, JavaScript parse successful; no autocorrection.
- Existing Worker tests: **11 passed, 0 failed**. Node emitted the pre-existing module-type warning; no package setting was changed to silence it.
- Offline audit probes: **1 control passed, 5 safety expectations violated**. Their exit code 1 is deliberate while the defects remain; these are not added to the production test suite.
- Swift test sources inspected: 79 PlaybackPolicy, 31 FPLTrust, 46 BetaUsability and 29 MatchReminder test methods. Counts include conditional/optional tests and are not fresh execution or coverage claims.
- Application/source fingerprint is checked again at handoff. No production edits, upload, deployment or device operation.
- Disk: approximately **63 GiB free before and after**. Audit files are small durable evidence, not leftover build products.

## Reproduce / inspect evidence

Run from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 docs/audit/complexity-2026-08-28/measure-swift.py
node docs/audit/complexity-2026-08-28/measure-js.mjs
node --test --test-concurrency=1 web/workers/playback/src/coach-contract.test.mjs web/workers/playback/src/fpl-scoring.test.mjs
node docs/audit/complexity-2026-08-28/probe-boundaries.mjs
```

The last command intentionally exits 1 while a safety expectation fails. The probes reuse the existing test fixtures and execute unchanged production JavaScript; every possible Worker fetch is intercepted. JavaScript metrics use the already installed ESLint version, which is recorded in the results. SwiftLint is pinned by version and SHA-256. The runners print results rather than overwrite the captured baseline files.

Evidence: [Swift metrics](/Users/jelani/Documents/Development/Fotty/docs/audit/complexity-2026-08-28/swift-metrics.json), [JavaScript metrics](/Users/jelani/Documents/Development/Fotty/docs/audit/complexity-2026-08-28/javascript-metrics.json), [probe outcomes](/Users/jelani/Documents/Development/Fotty/docs/audit/complexity-2026-08-28/boundary-probes.json), [source baseline](/Users/jelani/Documents/Development/Fotty/docs/audit/complexity-2026-08-28/source-baseline.json).
