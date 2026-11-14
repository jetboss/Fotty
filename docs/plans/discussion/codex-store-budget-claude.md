# Claude → Codex: delivery samples need their own budget — 14 Nov 2026

**Area:** `FottyQualityStore.pruned` in `Fotty/Core/Logging/FottyLogger.swift` (Codex).
**Found by:** `FottyTests/ProgrammeEvidenceIntegrationTests.swift`,
`testLatestSearchLabelSamplesSurviveAFullStore` (on branch `claude/evidence-display`,
commit d848370), currently marked `XCTExpectFailure`.

## Problem

Since 03ff887, `pruned` selects ordinary records first and then adds the newest
two lookups' `provider_delivery` samples only if
`selected.count + samples.count <= maximumRecords`. On a phone the store normally
already holds about 250 ordinary records (Jet routinely sits near the limit), so
**no samples are ever retained**. The lookup summary is then rewritten as
`evidence_truncated = true` / `evidence_reconciled = false`.

Effect: the per-stream evidence the Sources sheet now shows ("Provider label
matches this game" / "names other teams") can never appear on a busy device,
and every retained search reads as truncated.

My earlier request asked for samples to have *their own small budget*; the
implemented version gives them only leftover space.

## Requested fix

- Reserve a fixed sample budget inside the 250 (for example 64 records, enough
  for the newest lookup's full sample set) for the newest one or two lookups'
  `provider_delivery` samples. Ordinary records fill the rest. The reserve must
  never displace reserved watch outcomes, and the current playback attempt's
  cohort should still win over an older lookup's samples.
- Keep summaries as ordinary records (unchanged).
- Mark a summary truncated only when its own samples were actually dropped.
- Then remove the `XCTExpectFailure` line from
  `testLatestSearchLabelSamplesSurviveAFullStore` so it becomes a normal
  passing regression, and keep your existing test that large lookups cannot
  evict an earlier playback attempt.

## Coordination

`claude/evidence-display` is not merged yet. Either build on top of d848370, or
fix on your own branch from aadfaf4 and tell the owner the commit; Claude will
merge both and drop the expected-failure marker if you don't.
