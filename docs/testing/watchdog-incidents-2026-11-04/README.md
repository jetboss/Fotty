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

Current-main isolated candidate: 165 checks pass after reusing the installed
Wrangler dependency (the first run lacked that dependency; not a code failure).
PR125 is open and protected CI is running. Live activation is not yet claimed.

Read-only evaluation of current cloud/GitHub evidence returned quiet, retained
10 legacy pending receipts and 129 known receipts without writing private state.
The existing chat automation was found PAUSED; its prompt now uses viewing-only
alerts and remains PAUSED pending the owner’s explicit preference. Cloud
collection is active. The old GitHub observer’s latest failed run reported four
deliveries and one pending, demonstrating the notification fan-out being removed.


## Published verification

PR125 merged through protected checks at 5c074725c56b1dde815856c41cb01816846e28ad.
Workflow/security/secrets/CodeQL/observation-policy checks passed. Normal observer
run41945708992 succeeded: ledgerIssue45, confirmedChanges1, delivered0, pending0,
apiRequests12. Issue45 is titled Fotty incident status, with zero comments and no
assignees. No Worker rebuild/deployment was required. The cloud collector remains
active; the existing chat automation remains PAUSED pending the owner's choice.
Do not present quiet metadata as end-to-end playback health.
