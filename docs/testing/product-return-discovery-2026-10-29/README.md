# Return and discovery batch — 29 October 2026

Source-only implementation of the first product batch accepted after the
[five-product study](../../audit/competitor-study-2026-10-29/README.md). This is not
a new visual redesign or a playback/provider repair. Device184/177 and shared121
remain separate, unchanged installations. FPL and multi-stream are excluded.

## Screen and interaction contract

| Area | Priority/composition | Compact and accessible adaptation | States and acceptance |
| --- | --- | --- | --- |
| Home return | One compact “Back to your match” card before the lineup, with actual badges, match identity, one Watch/Check streams action and a visible Forget action. No duplicate while a viewing owner exists. | Use the existing surface and spacing; full names can wrap; narrow layouts and accessibility sizes put the action below identity. Preserve the sport grid and existing Home groups. | Off by default under Privacy. A real decoded single-player confirmation can retain one identity for36h. Cold launch requires a matching current catalog row and fresh explicit live evidence; missing/stale/conflicting/finished/cancelled evidence hides the card. Opening rechecks status and uses normal source resolution; no autoplay, saved URL or rewind promise. Forget/disable revokes pending callbacks. |
| Search | Existing search destination, current broadcasts first-class, with verified upcoming accepted schedule rows up to14days where available. The result's normal Save/details state applies; schedule presence never supplies a broadcast. | Keep existing compact/wide search composition, keyboard handling and Dynamic Type. No extra tab or live source fetch for typing. | Existing recent/follow shortcuts persist. Envelope, competition-lane and row receipts must be fresh; terminal/held/quarantined data cannot re-enter through the wider projection. Empty results say no matching fixtures or channels. The Home72h horizon, merge and cache admission are unchanged. |
| Interests | One Home interests editor: immediate Home preview with a bounded selection summary, Browse sport, whole-sport choice, competitions, teams, Done. It uses existing stores and optional sync semantics. | Native grouped List and pickers; semantic text and44pt controls. Rows wrap and team badges remain. No separate onboarding requirement or new account. | Changing Browse sport changes editor scope only. Whole-sport and narrow choices are additive; removing one does not erase others. Only-selected remains unavailable for zero interests and preview uses current vetted content. Selection-only preview is explicit when Settings has no supplied lineup. Save errors and volatile persistence remain surfaced. |

## Evidence boundaries

Compile and deterministic tests can establish type compatibility, lifecycle and
freshness/identity rules. They cannot establish actual iPhone/iPad layout,
VoiceOver focus, contrast, keyboard overlap or native media playback. Those
physical/visual gates remain open until a separately authorised device session.
No screenshot or old Mac app is treated as current native proof.

Verification results and changed-input hashes are in `verification.json` after the
local gate. No app version bump, install, app launch, feed activation, provider
probe, Git publication, cloud deployment or TestFlight release belongs to this pass.

## Local verification

-194 current-source Catalyst XCTest cases passed;0failures and0skips. Includes
 17 local-return policy tests,17 wider-Search tests, six coordinator return
  boundaries and the existing selected discovery/personalization/identity cases.
-32 source-membership tool tests passed. Native membership and unchanged
 2.0.1(184) version coherence passed;45 protected FPL/multi file hashes match.
- Two initial new-test failures described contradictory synthetic fixture IDs/
  statuses. Their test data was corrected without weakening conflict/terminal
  checks or changing shared production dedup. The corrected gate includes real
  observation-time and current-score cancellation regressions.
- The first test-runner attempt selected zero tests due to one incorrectly
  combined filter argument. It was discarded; a successful exit alone did not
  count. Final XCTest totals above come from the actual result bundle.

- Unsigned generic iOS Release compile passed. The executable's Mach-O platform
  is iOS, version2.0.1(184); no version bump, signing, install or launch occurred.
- Owned DerivedData, source copy, test result bundles, raw logs and keep-awake
  process were removed. Only these small redacted summaries/hashes remain.
