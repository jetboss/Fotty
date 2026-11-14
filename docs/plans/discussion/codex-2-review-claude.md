# Claude review of Codex task 2 (d137939) — 14 Nov 2026

**Verdict: merge after one change.** Read-only review; tests not rerun by Claude
(Codex reported 2,754 passed, 12 skipped, 0 failed).

## Required change (P2): evidence cohorts flood the shared quality store

`FottyQualityStore.recordProviderLookup` appends up to 65 records per lookup
(64 `provider_delivery` samples + 1 `provider_lookup` summary) to the shared
250-record store. `pruned` keeps the newest cohorts first, so a few Highfly or
PenguPlay lookups (Highfly often returns 60+ streams; retries repeat lookups)
evict earlier watches' playback-attempt and audio cohorts. This is the same
failure mode as the 8 Nov routine-refresh flood (184 of 249 records).

Requested fix:
- Always keep `provider_lookup` summaries.
- Give `provider_delivery` samples their own small budget (for example, only
  the newest two lookups' samples) so they can never evict playback, audio or
  watch-outcome records. If samples for a lookup are dropped, its summary
  should read as truncated, not reconciled.
- Add a regression test: several large lookups after a playback attempt leave
  that attempt's cohort intact.

## Minor (no action required)

`StreamLookupEvidence.attaching` records the metadata receipt at admission,
before the final configuration/fixture check. A lookup withdrawn at that check
can leave a `metadataAgrees` receipt in the ledger. It expires after the
90-second metadata lifetime and never counts as viewer confirmation.

## Confirmed good

- `preparedDeliveryProvenance` closes the task 1 integration gap: the player
  re-links a prepared session to its opaque listing without raw listing IDs.
- `ProviderEvidenceConfiguration` rotates on save/remove and on real
  enablement changes; A → B → A gets a new generation; lookups fence on it.
- No new refusal reasons; ranking and order unchanged.
- New records carry only HMAC hex, enums, counts and local UUIDs, all
  validated by the logger allowlist.
