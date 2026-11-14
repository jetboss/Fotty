# Codex 1 — evidence foundation and expiry

Date: 14 November 2026. Branch: `codex/evidence-foundation-20261114`.
Base: `eb6dc3e` on the reviewed `wip/ios-3.0-baseline` history.

This is the source-only first task in the approved roadmap. It supplies the
types and storage required by the later provider receipts and optional Right
match feedback. It does not add those producers or buttons, identify the
historical HF1 rugby delivery, change ranking, or establish a physical playback
pass. The paused broad refactor and primary checkout are untouched.

## Implemented

- `StreamEvidence.swift` defines the agreed provenance, metadata, explicit
  viewer verdict, correctness, scope, expiry and lookup-count types.
- `ProgrammeEvidenceLedger` derives correctness independently of playback
  health. Explicit viewer feedback takes precedence; a tied rejection beats
  confirmation. Metadata contradiction is not a viewer rejection. Decoding,
  duration, blocked pictures and audible-sound assumptions have no input here.
- Fixture or channel/programme, provider, full delivery contract and current
  configuration generation scope evidence. Query callers must provide the
  current authoritative boundary, or `attemptOnly` when none exists. The
  stored boundary and current boundary both apply, exclusively at their end.
- The ledger retains at most 256 observations, including expired deduplication
  markers, with a seven-day logical retention limit checked on access. Old
  opaque bytes can remain in defaults until a later write; there is no timed
  disk deletion. Markers prevent an observation's expiry
  from being extended by repeated writes while retained; they grant no
  correctness. Bounded snapshots preserve those markers. Attempt-only viewer
  evidence is removed on attempt end and never persisted/restored.
- The health-store facade reuses its existing device-only Keychain HMAC key,
  with new versioned, length-framed domains. Payloads contain opaque digests,
  enums, times and local correlation UUIDs. Raw fixtures, provider listing IDs,
  URLs, query tokens, headers, cookies and titles are not written to the new
  evidence payload. Without persistent key access it stays process-local.
- `StreamSession` carries provenance and prepared transport context only in
  memory. Decoding cannot restore either. Probe contract changes invalidate
  them; renewal accepts valid context supplied on the fresh descriptor and a
  distinct fresh lookup receipt. The caller must recapture transport for the
  replacement attempt; the context itself does not identify an attempt.
- Prepared transport captures the cookie snapshot actually supplied to native
  playback or WebKit handoff, including an explicitly empty snapshot. Cookie
  values and scope contribute to the opaque contract. The current cookie jar
  is never substituted for the snapshot used by the playing attempt. Cookie
  expiry also ends viewer-proof eligibility.
- Declaration-level metadata may exist before preparation. Viewer verdicts
  require valid prepared transport; an unprepared session cannot read back
  retained viewer correctness. No stream is rejected by these evidence APIs.

Existing `MatchOutcome`, legacy wrong-programme rotation behaviour and source
ranking remain unchanged. The new store does not migrate legacy playback or
wrong-programme observations into typed correctness.

## Integration handoff

Claude owns project-file integration. The branch does not modify
`Fotty.xcodeproj/project.pbxproj`. The full test gate uses the accompanying
`project-membership.patch` only in its isolated checkout. Apply/review the
three file memberships before integrating this branch:

1. `Fotty/Core/Models/StreamEvidence.swift` → Fotty target, Models group.
2. `FottyTests/StreamEvidenceTests.swift` → FottyTests target.
3. `FottyTests/StreamEvidenceSessionTests.swift` → FottyTests target.

The patch has zero context to avoid whitespace warnings from embedded Xcode
indentation. On this exact base, `git apply --unidiff-zero` reproduces the tested
project hash; review/recreate the memberships if Claude's project file has moved.

Producer/feedback wiring must supply these facts rather than infer them:

- **Configuration generation:** use the current provider's durable UUID,
  rotate it on credential, manifest, enablement or configuration changes,
  including changing away and back. The existing process-local enablement
  counter is not this generation. Task 1 deliberately introduces no fallback
  default and does not modify configuration lifecycle owners.
- **Provenance:** build with `deliveryProvenance`, attach with
  `recordingDeliveryProvenance`, and keep raw lookup/listing data transient.
  Preserve all observed deliveries and reasons in Task 2; counts here are
  types, not a running collector. A contract fingerprint is not safety or
  game-matching authority.
- **Preparation:** call `recordingDeliveryTransport(cookies:at:)` with the
  actual captured cookies used by that attempt. A changed contract clears the
  old provenance and needs fresh matching provenance. Do not invent an empty
  snapshot or read the mutable cookie jar later when feedback arrives.
- **Boundary:** supply an authoritative fixture/programme end or `attemptOnly`.
  Do not turn the 90-second event-binding TTL, kickoff plus an assumed match
  duration, or a generic channel name into a programme boundary.
- **Attempt ownership:** the existing viewing-session owner must fence current
  attempt, selection, configuration and scope immediately before recording.
  `endProgrammeEvidenceAttempt` clears attempt-only observations; it is not
  a second session owner or a cancellation tombstone for future stale calls.
- **Feedback:** only a deliberate viewer action may call `recordViewerVerdict`.
  Use `programmeCorrectness` for presentation; collection counts include
  expired deduplication markers and must not be interpreted as active proof.
- **Privacy:** the new evidence codec is local-only. Task 2 owns any redacted
  diagnostic receipts and must not export raw request data or credentials.

These integration hooks remain pending. Task 1 by itself does not change what
the installed app records or displays, and does not solve the untraceable
historical rugby incident retroactively.

## Verification

Full Catalyst `FottyTests` validation: **2,717 passed, 12 opt-in skipped,
0 failed (2,729 total)**. All **39 added tests** passed. No suite was excluded;
`VisualRegressionTests` and `NativePlayerAudioIsolationTests` also passed.
The exact source hashes, project-membership patch hash and skipped test names
are recorded in `validation.json`. All six implementation/test files remained
byte-for-byte identical to the isolated full-suite checkout.
No simulator, Jet build/install, phone work, Git publication, cloud deployment
or TestFlight action is part of this task.

The first isolated gate attempt stopped before tests because its temporary
project membership put the model in Networking instead of Models. Membership
was corrected in the test checkout; implementation source was unchanged.

The existing local brain startup/finish checks report that `Current-State.md` exceeds
its 8 KB limit. General memory cleanup and the roadmap are outside this task;
this scoped handoff is the durable implementation receipt.
