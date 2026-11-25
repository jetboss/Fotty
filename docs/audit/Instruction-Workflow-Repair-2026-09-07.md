# Global / Fotty instruction-workflow repair — 2026-09-07

Implements the recommendations in
`/Users/jelani/Documents/Development/INSTRUCTION-AUDIT-GLOBAL-FOTTY-2026-09-07.md`.
This is tooling/documentation work, not a new Fotty application build.

## Changes

- A compact `docs/notebooklm/Current-State.md` is the startup baseline. Existing
  Project-Memory, Decisions-Log and Architecture-Map history remains intact and
  searchable; old release assertions are explicitly historical.
- `tools/memory_support.py` supplies offline retrieval and export operations.
  PiP/FPL/UCL/CPL are retained, common dictated-task padding is removed, and
  relevant current sections outrank history. Matches include paths/line numbers,
  dates where known, truncation/context notices, and rejection caveats. Undated
  sibling sections no longer inherit an unrelated section's date.
- Sharing exports use allowlisted Markdown sources, not uncontrolled command
  output. URL userinfo, common query/YAML/JSON credentials, authorization values
  and private keys are redacted. Residual known patterns/signing material block
  replacement. A source digest detects stale snapshots; a failed/interrupted
  export retains the previous complete artifact and cleans temporary files.
  Pattern checks remain defense-in-depth, not a guarantee that arbitrary prose
  is safe to share. Human review and the ban on secrets in source memory remain.
- Export-path clipboard copying now requires `--copy-path`. Health distinguishes
  source presence/reference checks from `--export` digest/privacy checks. Neither
  claims to verify live app behavior.
- Global Codex guidance now includes the Mac's resource limits and task-scoped
  completion boundaries. Model recommendations are not automatic model switches;
  commentary is reserved for consequential mismatches or explicit questions.
- The personal Cursor continuity skill and bridge now require user confirmation
  and provenance for promoted decisions. Project notes do not enter Aegis's
  global profile/API; explicit cross-project preferences may. Briefs are rebuilt
  per canonical workspace, include only applicable confirmed records, preserve
  source/date/supersession, and do not reuse the old global cache.
- Ten exact auto-generated profile lines matched against legacy bridge records
  were preserved as quoted, unverified history, not confirmed preferences. No
  belief records or unrelated profile preferences were deleted. Future confirmed
  global notes are inserted into their own section before legacy history.
- OtakuVerse's active onboarding/rules now prohibit invoking the retired
  homelab/embedding setup. The original operator guide is retained under
  `agent/history/homelab-operator-retired.md`; no host or service was contacted.

## Verification

Run the bounded checks sequentially:

```sh
python3 -B -m unittest discover -s tools/tests -p 'test_memory_support.py'
python3 -B -m unittest discover -s /Users/jelani/.aegis-csm/tests -p 'test_bridge.py'
python3 -B /Users/jelani/.codex/skills/.system/skill-creator/scripts/quick_validate.py /Users/jelani/.cursor/skills/aegis-csm-continuity
for script in tools/ask-brain.sh tools/brain-doctor.sh tools/notebooklm-refresh.sh tools/agent-start.sh tools/agent-finish.sh; do bash -n "$script" || exit 1; done
./tools/notebooklm-refresh.sh
./tools/brain-doctor.sh --export
```

Tests use standard-library fixtures and self-cleaning temporary directories, not
real hooks, profile data, credentials or provider endpoints. Representative
actual-project retrieval queries are also checked for relevant first results.
No extra dependency, model-provider spending, simulator, Xcode build, app version,
device install, TestFlight distribution, commit or push is part of this repair.

Final result: 22 memory-helper tests and 14 continuity tests pass (36 total),
personal-skill validation passes, and each touched shell wrapper parses. Actual
PiP/FPL/UCL/CPL and the dictated paused-video query return Current-State first,
with outputs bounded below 6,000 characters. Targeted whitespace checks pass;
an unrelated pre-existing OtakuVerse `lib/core/constants.dart` EOF whitespace
finding was not changed. The final finish run refreshes and verifies the export.

## Recovery / boundaries

- Pre-edit global guidance, bridge code and personal skill copies are in
  `/Users/jelani/Documents/Development/instruction-repair-backup-2026-09-07/`.
- The profile pre-edit backup is owner-readable at
  `/Users/jelani/.aegis-csm/backups/AEGIS_USER-before-scope-2026-09-07.md`.
- Existing Fotty worktree changes were preserved. The current application
  baseline remains the recorded 2.0.0 (80); this task did not inspect new Apple
  state or prove a fresh match-time playback session.
- Vendor skill caches were not edited. The separate earlier Aegis/Pixel-Invoice
  Projects-audit defects are not silently claimed fixed by this global/Fotty work.
- OpenAI Docs informed instruction hierarchy/progressive loading; Skill Creator
  guided the narrower continuity trigger, explicit scope and completion boundary.

Official references: [instruction hierarchy](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
and [progressive skill loading](https://learn.chatgpt.com/docs/build-skills).
