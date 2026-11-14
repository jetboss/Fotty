# Provider evidence sample reservation — 14 November 2026

Base: `claude/evidence-display` at `d848370`. Work branch:
`codex/provider-sample-budget-20261114`.

## Repair

The 03ff887 retention policy protected viewing history by giving provider
delivery samples only leftover space. A busy 250-record store therefore lost
all label samples, even from the newest search. Claude's integration regression
reproduces this through the actual Highfly adapter and Sources presentation.

The store now reserves up to **64 delivery samples** inside the existing
**250-record total**, drawn from the **newest two lookup summaries**. Whole
sample groups are considered newest-first: one full 64-entry lookup fits, or
two smaller lookups can share the budget. Unused sample capacity remains
available to ordinary records. Samples can displace older ordinary cohorts;
they are no longer limited to leftover space.

Priority remains with the newest 100 Watch outcomes, the newest playback
attempt and newest audio-job cohort. The store has no live player reference,
so newest recorded attempt/job is its bounded proxy for current viewing.
These cohorts are selected before ordinary lookup summaries and samples.
If a complete sample group cannot fit without evicting protected viewing,
the sample allocation yields and the proposed eviction is discarded. Only
the overall cap and reserved outcomes can clip an oversized current cohort.

Lookup summaries remain ordinary records. The latest summaries are protected
while reserving their samples, so no orphan samples survive. A retained
summary is newly marked truncated/not reconciled only when its own expected
samples were dropped; existing source-side truncation remains intact. Raw
counts do not change. Empty/unread lookups still occupy the latest-two window,
and replay does not restore evicted samples or invent another lookup.

## Regression coverage

- Removed `XCTExpectFailure` from
  `testLatestSearchLabelSamplesSurviveAFullStore`.
- Kept the earlier regression preserving playback/audio/outcomes after several
  large searches, with the expected sample count updated from 128 to 64.
- Busy-store retention for two small lookups, per-summary truncation and reload.
- Busy-store retention of the newest complete 64-entry sample group.
- Whole eviction of an older playback cohort while preserving the current one.
- Reserved outcomes/current playback/audio taking priority when a full sample
  group cannot fit.
- Existing equal-time append order, historical pruning, orphan removal, empty
  searches and receipt deduplication checks remain in place.

## Verification and scope

Exact Catalyst results and source hashes are recorded in `validation.json`.
**79 focused tests passed, zero skipped/failed. Full suite: 2,770 passed,
12 opt-in tests skipped, zero failures (2,782 total).** The previously expected
failure passes normally in both runs. Source hashes were verified afterward.

The test command overrides `MACOSX_DEPLOYMENT_TARGET=27.0` and uses ad-hoc
Catalyst signing without development entitlements; the project deployment
settings and production entitlements are unchanged. Initial target/signing
preflight stops ran no tests and are retained in the receipt. Focused suites cover
`WatchOutcomeRecordTests`, `ProgrammeEvidenceIntegrationTests`,
`FottyQualityStoreTests` and `StorageRuntimeSafetyTests`; the full unit suite
reuses the same compiled products sequentially.

The repository memory helper still reports the pre-existing `Current-State.md`
8 KB budget failure. Its generated export was restored; this scoped receipt
records the new policy without unrelated memory edits.

No ranking, admission, provider configuration, player/UI, FPL or multi-stream
changes. No device interaction, TestFlight, merge, push or cloud work. Only the
owned temporary test output is cleaned after the gate.
