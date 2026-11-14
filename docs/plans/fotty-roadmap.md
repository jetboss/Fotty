# Fotty roadmap — joint Claude/Codex plan

Status: **Approved by the owner on 14 Nov 2026** (plan, ownership split, first four tasks, retirement-review threshold).
Next gate: Codex commits its build 324 working tree as the baseline; Claude reviews it; then tasks start.
Discussion record: `docs/plans/discussion/` (round 1 prompt and Codex review, round 2 Claude
reply and Codex reply).

## Product goal

Open Fotty, find your match, tap Watch, and see **the right game**, quickly, staying stable, with
automatic recovery. Football first (Premier League, Champions League), cricket second (Willow/Fox).

## Principles (agreed)

1. **Safety and the right game are strict; data shape is not.** Refuse unsafe deliveries and the
   wrong fixture; never refuse because of an unfamiliar field, server, layout or listing count.
2. **Playback proves playability, never correctness.** Decoded frames, silence or a long stable
   hold never establish the right programme (Jet 324: HF1 decoded rugby under a hockey match).
   Metadata agreement and viewer verdicts are separate facts.
3. **One match, one permanent identity.** A provider outage changes only that provider's options.
4. **Consolidate the existing session owner** (`ViewingSessionCoordinator`, attempt IDs, intent
   fences) — no second owner. UI renders session state; late callbacks cannot override newer intent.
5. **Every refusal is named and counted**; counts distinguish repeated lookups, unique deliveries
   and unread responses.
6. **Single-stream reliability before breadth** (FPL, multi-stream, coaching wait).
7. **Team naming:** sport + kickoff only shortlists candidates; no automatic alias learning;
   ambiguous aliases are reviewed; squad/competition/date checks stay.

## Order (agreed)

1. **Interfaces and ownership first** — freeze the evidence types below; agree file ownership and a
   committed baseline.
2. **Provenance + evidence** — record listing→delivery→attempt association; per-delivery metadata
   comparison receipts; improve the existing wrong-match action; expose evidence on device.
3. **Lifecycle consolidation** with deterministic failure tests (pause during renewal, cancelled
   discovery, replaced attempts, late recovery callbacks, token expiry, half-time, app reopen).
4. **Targeted identity fixes** for demonstrated gaps (postponements, provider-ID changes).
5. **Remaining provider gaps, measured** (e.g. CNC read failures/timeouts, Score808 web-only counts);
   share protocol plumbing only where contracts genuinely overlap. Reviewed TV is already on the
   shared policy in the 324 working tree (station identity and playlist provenance stay pinned).
6. **Physical qualification on Jet/iPhone:** explicit PL, UCL and cricket acceptance gates; pause/
   resume, audible audio, renewal, recovery, PiP, and the new player on iPhone.
7. **Then** broader modularization (Swift packages optional, driven by real defects), polish and
   breadth.

## Correctness model (agreed)

- States: `unknown`, `metadataAgrees`, `viewerConfirmed`, `viewerRejected`.
- Only an explicit viewer action sets confirmed/rejected. "Right match" is optional and quiet;
  "Wrong match" and "Picture blocked" are separate one-tap actions (blocked picture is neutral on
  correctness). Ranking must work with mostly unknown/metadata evidence.
- Scope: device-keyed delivery-contract fingerprint per fixture (or channel programme).
- Expiry: fixture live-window end or programme boundary; immediately on contract, configuration or
  scope change; attempt-only when no authoritative boundary exists.
- Metadata-based ranking waits until receipts show delivery labels actually carry team names.

## Frozen evidence interface (proposed by Codex, owned by Codex)

All `DeviceHMAC` fields are device-keyed, domain-separated HMACs using the existing device-local
key. Raw identifiers, labels, URLs and headers stay transient. See
`docs/plans/discussion/round-2-codex.md` for the Swift sketch: `DeviceHMAC`, `ProgrammeScope`,
`DeliveryProvenance`, `MetadataComparison`, `DeliveryMetadataReceipt`, `ViewerVerdict`,
`ProgrammeCorrectness`, `CorrectnessExpiry`, `ProgrammeEvidence`, `FixtureLookupCounts`.

## Progress

- **14 Nov — baseline:** Codex committed build 324 (f9b88eb, bd6764f); Claude reviewed it and
  added the relay-deadlock fix proven on Jet 317 (d1347dd). Full suite 2,685 / 0 failures.
- **14 Nov — Claude task 1:** the planned lifecycle scenarios were already covered; recorded in
  `docs/plans/lifecycle-coverage-map.md` instead of duplicate tests.
- **14 Nov — Claude task 2 (first half), merged at 48e7978:** separate Wrong match and Picture
  blocked actions in the Sources sheet and player options. Codex cross-reviewed five rounds and
  found seven defects, all fixed with tests (stale-attempt taps, typed failover outside transport
  recovery, paused/PiP refusal, shared failover accounting, blocked-hold that unmounts the Web page,
  late native stall fence). Full suite 2,690 / 0 failures. Right match waits for Codex 1.
- **14 Nov — Codex 1 and 2, on baseline at 03ff887:** evidence foundation and expiry (63137a7);
  Highfly/PenguPlay delivery receipts, lookup counts, provider configuration generation and the
  prepared-provenance bridge (d137939). Claude reviewed both; one P2 (delivery samples could evict
  playback history from the 250-record store) fixed by Codex in 03ff887. Claude added the three
  Xcode memberships. Full suite on the clean commit 2,770 / 0 failures. Next: Claude's Right match.
- **14 Nov — Claude task 2 (second half), merged at 66c146c:** optional Right match in the Sources
  sheet and player options. Native relay preparation captures its exact cookie snapshot and
  rebinds lookup provenance; the verdict is attempt-only (no authoritative programme end) and
  never changes playback or ranking. Wrong match now also records the typed rejection. Codex
  cross-reviewed two rounds (two P2s fixed). Full suite 2,775 / 0 failures. Not yet on a device.
- **14 Nov — Claude task 2 complete (evidence presentation), merged at 58915d3:** Sources sheet
  shows each provider's newest search ("found N · M can be tried") and a quiet provider-label note
  per source; Owner Status has "Programme evidence on this build". Integration tests drive a
  Highfly lookup through presentation and Right match. The tests found that delivery samples got
  no space in a full store; Codex reserved 64 records for them (3094b8c). Codex review fixes: one
  store read per sheet opening, exact test assertions. Full suite 2,783 / 0 failures (one
  `VisualRegressionTests` "missingWindowScene" failure did not recur on rerun).
- **Open follow-up (Codex area):** `NativePlayerAudioIsolationTests` reconnect test crashed once
  under full-suite load; likely a pre-existing timing flake. *Update (stage 3):* the available
  crash report (EXC_BAD_ACCESS in CoreFoundation/MediaToolbox during XCTest teardown, no test
  named) does not support a timing explanation; cause unknown, no change made. The 7 unchanged
  tests passed in the stage 3 focused run; the earlier crash remains unexplained.
- **14 Nov — stage 3 (lifecycle), paused Wrong match repair verified locally:** the stage 3
  primitives were already covered (see `docs/plans/lifecycle-coverage-map.md`). One composite gap
  repaired in `LivePlayerViewModel`: Play after a paused Wrong match resumed the rejected delivery.
  Explicit Play after Pause now goes through the existing wrong-programme gate in
  `loadCurrentSource` (new attempt, failover or "No matching broadcast"); with no backup it holds
  the delivery like a blocked picture, so the rejected Web page and late callbacks cannot restart
  it. Baseline: the regression failed (one method, 20 assertions, native/Web × 1/2 sources).
  Catalyst: focused 261 passed / 0 skipped / 0 failed; full suite 2,785 total, 2,773 passed,
  12 opt-in/physical skips, 0 failed. Independent review: no remaining P1/P2. Ranking, provider
  matching/admission, FPL and multi-stream unchanged. **Jet 328:** normal Watch, correct Haiti–United States picture, paused Sources and same-attempt
  resume checked; exact wrong-picture feedback remains physical-unexercised (correct stream observed); the rest of the roadmap (stages 4–7) is not done. The per-provider store-slot follow-up
  is separate and not implemented.

## Ownership (agreed)

- **Codex:** provider adapters and tests, fixture matching/bindings, delivery/provenance models,
  `LiveSourceHealthStore`, logging producers/validation.
- **Claude:** `ViewingSessionCoordinator`, `LivePlayerViewModel`, player/source-sheet UI, Owner
  Status presentation, lifecycle/UI tests, roadmap docs, Xcode project-file integration.
- One branch per agent; the other reviews before merge; shared-file changes transfer ownership
  explicitly; no shared uncommitted edits.

## First tasks (agreed)

- **Codex 1 — evidence foundation and expiry** (lands first, shared base): new
  `Core/Models/StreamEvidence.swift`; `MediaModels.swift`, `LiveSourceHealthStore.swift`; tests.
- **Codex 2 — Highfly/PenguPlay receipts and accounting**: both adapters, `FottyLogger.swift`,
  adapter tests; label-based ranking unchanged initially.
- **Claude 1 — lifecycle regression coverage**: `ViewingSessionCoordinatorTests`,
  `LivePlayerRetryLifecycleTests`; repairs only in the coordinator and player view model.
- **Claude 2 — feedback and evidence presentation**: separate Wrong match / Picture blocked, quiet
  optional Right match, fixture evidence and counts in Sources/Owner Status.

## Provider retirement (agreed)

Categories: disabled, untested, unavailable, repeatedly unsuccessful. At least 10 eligible target
fixtures across at least 2 weeks with no viewer-confirmed or stable correct play **triggers owner
review**, together with startup/timeout cost. Unconfirmed viewing is not counted as failure.

## Owner decisions (14 Nov 2026)

1. **Baseline:** the build 324 work (71 modified files plus new files, including
   `StreamDeliveryPolicy.swift`) is uncommitted in the main checkout. It must become a committed,
   reviewed baseline before either agent starts tasks. Proposed: Codex commits its 324 work; Claude
   reviews it.
2. Plan, ownership split and first four tasks: **approved**.
3. Retirement-review threshold: **approved**.
