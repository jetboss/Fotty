# Provider-specific evidence retention — 14 November 2026

## Scope

Follow-up to Claude's Jet 326 evidence: an unrelated empty PenguPlay search displaced Highfly's delivery-label samples because the sample slots were selected from the newest two searches globally. Root and the subscription-authenticated Claude CLI coordinated directly in an isolated worktree based on `64cca6e`.

The store now considers only the latest lookup for each provider, across fixtures. A newer empty/failed search invalidates that provider's older samples; it does not consume another provider's eligibility. Samples still share one 64-record reserve inside the existing 250-record store, newest first, with whole-cohort eviction. Watch outcomes and the newest playback/audio cohorts take precedence. Lookup summaries remain ordinary history; lost samples are explicitly marked truncated and unreconciled. Older samples cannot revive when a newer summary loses capacity.

## Evidence

- Before implementation: 39 store tests ran; three methods failed with 11 assertion failures. The new regression reproduced Highfly losing its samples and the actual Sources label after unrelated empty/unread PenguPlay lookups. The other two failures pinned the new latest-per-provider policy.
- After implementation: 43 focused store/presentation tests passed, no skips or failures. Full Catalyst suite: 2,787 total, 2,775 passed, 12 opt-in/physical skips, zero failures (exit 0). Source hashes were unchanged during compilation and tests.
- The regression uses synthetic data, the real quality store and the actual `ProgrammeEvidencePresentation`; no media, account credentials or devices are involved. It also checks same-provider invalidation and persisted reload. Existing tests cover playback/audio/watch protection, full-store capacity and whole-cohort eviction.
- Codex corrected the parameterized test helper to create PP1 for PenguPlay; its actual transport/provenance fixture therefore matches the provider under test.

No ranking, provider admission, lifecycle, UI, FPL, multi-stream, source settings or app build-number changes. No device install, publication or TestFlight. Jet remains on normal 328 for this source-only step.

## Review and limitations

Claude wrote the regressions and minimal store repair; Codex reviewed the diff and ran the red/green gates. Claude round 3 found no remaining P1/P2 issues; Codex accepted the minimal diff. Review completion and full results are captured in the validation receipt. This repair preserves useful diagnostic samples; it is not new playback qualification or proof that a provider shows the right programme.

The stage 4 review identified a separate raw-ID evidence-scope risk: a new fixture using the same event ID and executable delivery may inherit an earlier fixture's rejection. That separate repair requires a failing composite identity test and review of bound/unbound callers; it is not part of this retention commit.
