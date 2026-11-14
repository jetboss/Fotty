# Claude review receipt — provider sample reservation at `3094b8c`

Reviewed commit: `3094b8c` ("Reserve provider delivery sample capacity without
losing current viewing evidence"), parent `d848370`. Implementation receipt:
[`../fotty-provider-sample-budget-20261114/`](../fotty-provider-sample-budget-20261114/README.md).

## Verdict

**Approve, no blockers.** A dedicated read-only Claude Code session reviewed
the commit in two rounds and finished successfully with no permission denials.

Confirmed against the frozen source:

- 64 delivery-sample slots are reserved inside the 250-record total, not
  limited to leftover space; unused reservation stays available to ordinary
  records.
- Up to the newest two lookups share that budget; each lookup's samples are
  kept or dropped as a whole group.
- The newest 100 Watch outcomes, the newest playback attempt and the newest
  audio-job group take priority. Older groups are evicted whole, and a
  proposed eviction is discarded entirely if the samples still cannot fit.
- No orphan samples survive and replay does not restore dropped samples.
- A retained summary is newly marked truncated only when its own samples
  were dropped.
- Pruned output is stable across repeated reads and reloads.
- `XCTExpectFailure` is removed from
  `testLatestSearchLabelSamplesSurviveAFullStore`; the earlier
  playback-preservation regression is kept with its expected sample count
  updated from 128 to 64.
- No ranking, admission, provider-adapter, FPL or multi-stream changes.

## `audio_job_id` follow-up (closed)

The first round asked whether the "current audio" protection could select a
different group than audio-job grouping. Direct follow-up closed it:

- The only production writer is `ActivationDiagnostic.record(in:)` in
  `Fotty/Core/Media/MediaAudioSessionOwner.swift` (key at line 115), which
  emits a `.playback` `audio_activation_evidence` record with `audio_job_id`
  plus `diagnostic_phase`/`purpose`/`result`, and no `attempt_id`.
- `jobID` is always a `Job.id` created by `UUID()`, so it passes the UUID
  checks at `FottyLogger.swift:1118` (grouping) and `:1269` (validation).
- `MediaAudioSession.owner` wires `diagnostic: { $0.record() }` (line 253).
  The other path, `audio_session_preparation` (line 273), carries no
  `audio_job_id`.
- Therefore protection (`FottyLogger.swift:1140`) and grouping
  (`:1117–1119`) always identify the same group and cannot land on a
  playback attempt. Test files write `audio_job_id` only on
  `audio_activation_evidence` records.

## Retained limits (documented, non-blocking)

The policy is bounded, not lossless:

- A very large current attempt can clip the newest audio group to a partial
  group (the overall cap and reserved outcomes can clip an oversized current
  cohort).
- Protecting the current attempt changes which ordinary records survive
  even when no lookup is present.
- Whole-group eviction can leave slots unused until new records arrive.
- Lookup summaries older than the newest two may be evicted to make room for
  samples, weakening duplicate detection if an old receipt were replayed;
  the adapter contract states replays do not occur.

## Verification basis

No tests were run for this review or for this receipt. The reviewer used
only Read/Grep/Glob, did not build or edit, and could not hash files; the
repository-wide `audio_job_id` scope beyond the review packet was supplied
by Codex and spot-checked here by search of `Fotty/`. `validation.json` in the
implementation receipt hashes only the logger, the two test files and
`project.pbxproj`, not `MediaAudioSessionOwner.swift`.

Test results come from the prior exact-source Mac Catalyst verification in
[`../fotty-provider-sample-budget-20261114/validation.json`](../fotty-provider-sample-budget-20261114/validation.json):
**79 focused tests passed; full suite 2,770 passed, 12 opt-in skips,
0 failures (2,782 total).** This documentation-only change does not require
another full build.

## Coordination

The review used a genuine subscription-authenticated Claude Code session;
direct follow-up between Codex and that session resolved the audio-job
question. A separate scoped Claude Code coding session authored this receipt
(documentation only). Codex retains final diff review and local commit
responsibility. The local coordinator lives at
`/Users/jelani/.codex/bridges/fotty-claude-review`. No credentials, device
identifiers or private session identifiers are recorded here.

No device interaction, simulators, TestFlight, merge, push or cloud work.
