# Complexity audit — reliability fixes

Date: 2026-08-28. Status: **local implementation and automated qualification complete**. Not deployed or distributed.

Subsequent rollout: the owner approved the reliability-first next phase. The
Worker is now deployed; build 43 qualification, Apple status and physical
acceptance are tracked in [its release record](../releases/Fotty-2.0.0-43.md).
The at-the-time local-only evidence below is preserved.

## Outcome

The owner approved fixing the five reproduced defects in [the original audit](Fotty-Complexity-Audit-2026-08-28.md). All five original safety probes now pass, along with their deliberate-pause control. This is a targeted reliability patch, not a wholesale refactor or a claim that every complexity hotspot is resolved.

## Changes

1. **Playback progress identity:** a replacement video or backward playhead discontinuity establishes a new baseline. Only subsequent forward progress proves recovery; a frozen replacement still triggers the watchdog. Intentional pause, background suspension and provider controls remain intact.
2. **Playback error ownership:** after playback starts, media errors must belong to the confirmed video. Swift also requires the owning document ID for failures, recovery, transport and native candidates. Recovery/failure callbacks preserve main-thread event ordering; unrelated iframe errors cannot enter the broadcast's grace timer. Genuine pre-start rejection and primary-video failures remain supported.
3. **Scoring evidence:** both engines require a complete, unambiguous 15-player scoring set before projecting autosubs/captaincy or deriving a total. Missing/invalid/duplicate rows are unknown, not non-appearances. Independently published official points can remain visible with an incomplete-data label. Without a supported total, Swift uses optional points and the UI displays a dash; the Worker returns null. Known previous-gameweek picks cannot authorize a current total.
4. **Coach authority:** recognized scoring questions always use the rules path, including unavailable/incomplete data, with zero model tokens. Local scoring also refuses undated or older-than-five-minute picks/live evidence; the Worker rejects explicitly stale HTTP Age/Date evidence. The iOS response guard rejects a model-sourced answer to a recognized scoring query. Tactical advice remains eligible for DeepSeek; it is not replaced by a simple rules-only coach.
5. **Request boundary:** `coach-request.mjs` owns non-null object/nested collection validation, question/history limits, bounded streaming reads (48 KiB), and configured limiter failures. Bad shapes and interrupted/invalid bodies return 400, oversized bodies 413, denials 429, and failed configured limiters 503. Validation happens before official/model requests. Existing optional-binding semantics remain unchanged.

No provider-control redesign, audio-policy change, simulator, direct device installation, TestFlight upload, Worker deployment, version allocation or Git publication is included.

## Verification

- Original offline probes: **6/6 pass**, including all five formerly violated expectations; zero simulated model calls on unavailable scoring, and no real network calls from those probes.
- Worker regression files: **24/24 pass**. Includes the normal tactical-model route, stale/missing official scoring, malformed shapes, oversized/chunked/interrupted bodies, limiter failures, missing/duplicate stats/metadata, real zero versus unknown, previous-gameweek rejection, DGW protection and Triple Captain inheritance.
- Mac Catalyst unit suite: **191 passed, 1 optional live-HLS soak skipped, 0 failed, 0 runtime warnings**. XCTest result summary independently read before cleanup. The first compile caught an older test fixture missing the new completeness field; corrected before this passing full run.
- Final full web suite: **81/81 pass**. The pre-existing Node module-type warning remains; no package/dependency configuration was changed to hide it.
- Unsigned generic-device **Release** and **ReviewSafeRelease** builds both pass. These are compile/link checks, not signed archives or TestFlight uploads.
- Targeted Worker ESLint: **0 errors**; four existing warnings remain in the entry point (unused legacy helpers/parameter and anonymous default export). No lint suppression or package-setting changes were added.
- Builds run sequentially with two jobs in one temporary DerivedData directory. The cleanup context also removed the failed first compile's output; no per-device/per-configuration build directories or simulator data were created.
- Temporary build products/result bundles were removed after reading the test summary and completing both builds. Free disk returned to **62.8 GiB** (about 63 GiB). `git diff --check` passes.

## Limits and next gate

- These tests execute the production monitor in JavaScriptCore/mocked DOM and exercise Swift bridge handling; they do not certify live provider behavior in physical iPad WebKit. Same-source buffering/recovery and pause/resume remain the meaningful hardware acceptance check.
- Scoring questions are classified by an explicit shared-language pattern, not a universal semantic intent detector. Complete-looking but incorrect upstream data cannot be disproved by these structural checks. Worker freshness checks can reject explicit stale headers but cannot prove upstream generation time when no trustworthy timestamp is supplied.
- The audit's larger optimizer, ViewModel, reminder and Coach orchestration refactors remain separate maintainability work. Request/limiter extraction is included because it enforces a tested boundary, not to game a complexity score.
- The current distributed internal TestFlight release remains **2.0.0 (42)**. This source has unreleased changes. A future approved rollout needs the Worker deployment and a newly numbered, qualified TestFlight build; use App Store Connect preflight before allocating its number.
