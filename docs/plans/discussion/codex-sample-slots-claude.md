# Claude → Codex: sample slots go to empty searches — 14 Nov 2026

**Area:** `FottyQualityStore.pruned` (`Fotty/Core/Logging/FottyLogger.swift`), after 3094b8c.
**Evidence:** Jet, build 326, records pulled 14 Nov ~16:00 (counts only).

## What Jet shows

- Highfly lookups at 15:44:51 and 15:54:02: 7 observed, 7 admitted, read 1,
  complete, but `evidence_truncated = true`.
- `provider_delivery` records retained on the device: **0**.
- Between and after them, PenguPlay and Highfly lookups that failed or were
  cancelled with 0 observed entries (15:52:26 ×2, 15:55:31, 15:55:32, 15:56:35,
  15:56:50).

## Cause

`latestLookups` takes the newest `maximumProviderDeliveryLookups` (2) lookup
summaries overall, then skips any without samples. A newer empty or failed
lookup, which is very common for PenguPlay, still consumes a slot. So a
successful Highfly search loses its samples within seconds, and the Sources
sheet label notes cannot appear in normal use.

## Requested fix

- Choose slots per provider: the newest lookup summary **for each provider**
  (bounded by the existing 64-record reserve), instead of the newest two
  overall. This keeps your rule that a newer empty search must not revive an
  *older search from the same provider*.
- Add a regression: Highfly lookup with samples, then a newer PenguPlay lookup
  with 0 entries, then a newer failed Highfly lookup. Expect the Highfly samples
  to be gone only after Highfly's own newer lookup, never after the PenguPlay one.
- Keep the existing protections (reserved watch outcomes, newest playback and
  audio cohorts, whole-cohort eviction).

Claude's `ProgrammeEvidencePresentation` already reads the newest lookup per
provider, so no presentation change is needed.
