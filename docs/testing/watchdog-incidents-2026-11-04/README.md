# Quiet incident consolidation — 4 November 2026

## Scope

Replace noisy notification fan-out, not collection. FPL, multi-stream, devices,
playback, source opt-ins, cloud activation and TestFlight are untouched.

## Implemented

- One existing GitHub ledger/status issue, with at most 64 displayed diagnostic
  groups. No provider issue creation, assignees, mention comments or canary mail.
- Historical cloud notices, legacy issue bodies, independent ledger and delivered
  hashes preserved. Failed/ambiguous dashboard writes retry without duplicate
  issue creation; successful writes do not acknowledge owner receipt.
- Owner chat groups fresh confirmed fixture-endpoint server failures into one
  discovery case per scope. Multiple causes must recover before one recovery is
  emitted. Provider metadata failures and monitoring failures remain quiet
  diagnostics. Existing legacy pending receipts are preserved without replay.
- No decoded-viewing or all-backups-failed claim from metadata alone.

## Validation

Canonical source: 227 tests passed, no failures/skips, including existing provider,
fixture, matching, runtime and safety checks. New regression coverage includes
migration without false acknowledgement; grouping; partial recovery; stale/missing
and incompatible evidence; restart deduplication; ambiguous dashboard writes;
retired canary; no comments or assignments on normal observer runs.

Publication, current-main verification and live result: pending.
