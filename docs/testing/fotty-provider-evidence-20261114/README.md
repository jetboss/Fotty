# Codex 2 — Highfly/PenguPlay receipts and accounting

Date: 14 November 2026. Branch: `codex/provider-evidence-20261114`.
Base: `63137a78fe5f0de3faffa30459417cc5a38cff01` (Codex 1).

Claude's Fotty chat approved Codex 1 at 16:28:57 UTC on 14 November:
“I reviewed Codex's task 1 (commit 63137a7) and found no defects, so it's fine
to merge as is.” Claude explicitly did not rerun that suite. This review was
found in the local chat record; the roadmap had not yet recorded it. The
owner authorized Task 2 after that review. No roadmap files were changed.

## Scope and behaviour

Both adapters now produce one bounded receipt per eligible resolve call.
Each receipt links the opaque fixture, provider configuration generation,
lookup, listing and delivery contract. Each retained admitted row also carries
the returned local source UUID, joining existing player `source_id` records to
the exact listing/entry that produced the initial choice. Duplicate or refused
rows with the same contract do not inherit that UUID.

This is evidence production, not a new player owner or selection policy.
Source order, labels, existing matching/admission rules and ranking are
unchanged. An actual configuration change during a pending lookup now
invalidates its result even if the account link changed away and back.
Player preparation, optional Right match feedback and Owner Status presentation
remain Claude's integration work. No device has received this branch.

### Labels and programme evidence

- `name` and `title` decode independently and tolerantly. Missing, non-string
  and oversized labels do not become new stream refusal reasons.
- Existing participant parsing yields `agrees`, `contradicts` or
  `noParseableTeams`. Contradiction in either parseable field wins. The metadata
  receipt aggregates retained rows sharing the exact contract, so a duplicate
  contradictory label cannot be hidden by the first admitted label.
- This is a comparison of provider claims. It never establishes what was on
  screen, confirms the programme, or changes ranking. Stable playback is not
  used as correctness evidence.
- A rolling channel tile receives counts and source correlation, but no
  fixture-programme provenance. A generic channel name cannot identify a game.

### Counts and retention

- Raw entries are counted before the existing scan/session caps. Existing
  admission reasons account for each observed row, including capped tails.
- Read, unread and known-empty counts describe logical **stream-response**
  reads for selected listings. They are not totals of catalog requests,
  transport retries or all unseen provider inventory. A metadata conflict
  preventing a stream read is unread; a successfully decoded empty response
  is known empty. Failed metadata fallback followed by a successful stream
  response is a read response.
- Repeated lookups have separate UUIDs; replaying the same receipt while it is
  retained is idempotent. The unique-contract count is a set across retained
  lookups, not a sum of their per-lookup counts. Window queries use lookup
  completion time, not delayed log-write time. Impossible nonempty/empty
  response totals are rejected rather than marked reconciled.
- At most 64 delivery samples are retained per lookup, while raw-entry and
  disposition totals cover the full decoded response. `isTruncated` marks a
  limited listing scope, sample cap or missing retained samples. Unique
  contracts are therefore a lower bound when truncated. Admitted sources past
  the sample cap still receive in-memory listing provenance but do not have an
  individual diagnostic row.
- Receipts use the existing 250-record quality store, not another telemetry
  service. Lookup summaries participate in ordinary bounded retention
  independently of their samples. Playback, audio, Watch outcomes and all other
  ordinary records are selected first. Whole sample groups from only the newest
  two retained lookups may use remaining capacity; they reserve no slots and
  cannot evict ordinary records. Equal-time lookups use append order.
- Dropping a lookup's samples preserves its summary and raw/read totals, marks
  it truncated and not reconciled, and makes aggregate unique-contract counts
  explicitly incomplete. The newest empty/unread searches do not revive older
  samples. Retained summaries still deduplicate replay after sample eviction;
  persisted older records receive this policy on read. Existing Watch-outcome
  reservation, total record bound and time retention remain. “Keep summaries”
  does not mean unlimited history: ordinary time/count limits still apply.
  Old admission records remain separate from these records.
- `provider_lookup` and `provider_delivery` contain only finite enums/counts,
  device-keyed HMACs and local UUIDs. Raw fixture/listing identifiers, labels,
  URLs, query tokens, headers and cookies are absent from the new records.

## Integration handoff to Claude

### Durable configuration generation

`ProviderEvidenceConfiguration.generation(for:configuration:)` returns a
device-local generation for a provider and full configured manifest URL.
Persistence contains a UUID and device-keyed configuration digest, never the
URL. Successful account save/removal and actual enablement changes rotate the
generation; invalid setup, failed writes and no-op toggles do not. A changed
configuration, including A → B → A, cannot reuse the previous generation.
The store is finite, validates its payload and is isolated in automated tests.

For player feedback use the read-only
`ProviderEvidenceConfiguration.currentGeneration(for:)`. Do not create a new
generation while rendering evidence. Recheck it, the current attempt and the
selection immediately before recording feedback.

### Preparation without raw listing IDs in the player

1. Preserve the **selected discovery session** carrying `deliveryProvenance`.
2. Prepare native playback with the actual supplied cookie snapshot using
   `recordingDeliveryTransport(cookies:at:)` from Task 1. Do not infer an empty
   snapshot or fetch a different mutable cookie jar later.
3. Call `LiveSourceHealthStore.preparedDeliveryProvenance(from:for:scope:
   configurationGeneration:at:)`, passing the selected session and prepared
   session. It requires the same local source UUID, fixture, provider and
   configuration, valid original provenance and current prepared transport.
   It rebinds only the contract to the actual prepared cookie context while
   preserving the opaque listing, lookup and original observation time.
4. Attach the returned provenance via `recordingDeliveryProvenance`. A nil
   result means unknown evidence, not a playback refusal. The bridge expires
   after the original 90-second metadata authority; it never refreshes it.
5. Keep Task 1's authoritative-boundary/attempt-only and explicit-viewer rules.
   The bridge does not copy metadata agreement or viewer correctness onto a
   changed contract. Unknown is the safe presentation until new evidence.

The existing session owner must fence late callbacks. This task does not wire
the helper into Claude-owned player files. Renewal can preserve an earlier
selected source UUID while the fresh lookup creates another UUID; the initial
`source_id` join is not proof of renewal attribution. Integrating renewal needs
the fresh provenance plus current attempt correlation, not a fabricated
association with an old listing. The historical build 324 rugby stream remains
unidentified: these receipts cannot reconstruct data that was never recorded.

### Project integration and review

No new source files or Xcode memberships are added by Task 2. It depends on
Task 1's three memberships. The full local test checkout applies Task 1's
`project-membership.patch`; `Fotty.xcodeproj/project.pbxproj` is unchanged on
this branch. Review Task 2 before merging it into the shared baseline.

## Verification

The original `d137939` results follow. The required retention review correction
and its later validation are documented below and in `retention-review.json`.

The full Catalyst suite passed: **2,754 passed, 12 opt-in skipped, 0 failed
(2,766 total)**. All **37 added regression tests** passed. Exact tested source
hashes, skipped tests and the isolated project hash are in `validation.json`.
All twelve changed source/test files remained byte-for-byte identical to the
final test checkout. No suite was excluded. Added regression coverage
includes multiple listings, malformed labels, contradiction without ranking
changes, duplicate same-contract origin attribution, partial/empty/unread
responses, all-entry caps, final configuration fencing, serialized generations,
privacy, repeated lookups, whole-cohort eviction and prepared-contract rebinding.

The first compile stopped before tests because a new PenguPlay privacy test
attempted to encode a deliberately non-Codable receipt. The test was corrected
to inspect the actual sanitized persistent records. Failed-run evidence is
retained as a small redacted result rather than raw build output.

The intermediate full run passed its 34 new tests but failed the unchanged
visual-baseline test's immediate image-cache precondition (`XCTAssertNotNil`
at `VisualRegressionTests.swift:306`). The final full run, with three additional
review-driven accounting regressions, passed that visual test as well as the
native audio-isolation suite. Neither the image cache nor the visual test or
artwork was changed. The earlier failure is retained; its cause is not proven.

No live provider requests, device interactions, simulator, iOS packaging,
install, Git publication, cloud deployment or TestFlight action is included.
The primary checkout and paused broad worktree remain untouched. The existing
local brain check reports `Current-State.md` above its 8 KB limit; this scoped
handoff preserves the Task 2 facts without editing Claude's roadmap or the
shared historical summaries.

## Claude retention review correction

Claude's 14 November review accepted the evidence design, privacy and
prepared-provenance bridge, but found that up to 65 records per lookup could
evict earlier viewing evidence. The original atomic summary/sample retention
policy was wrong. Limiting samples to two lookups alone would still consume
space ahead of viewing records, so the correction uses **only spare capacity
after ordinary retention**. No new storage or increased total capacity is used.

Only `FottyLogger.swift` and `WatchOutcomeRecordTests.swift` change in this
follow-up. The old summary-plus-sample eviction test is replaced with coverage
for preserved summaries, global sample limits, equal-time order, replay and
truthful counts. Four additional regressions cover a six-search flood after
playback/audio/Watch records, near-full viewing history, legacy persisted
records/orphan samples, and empty/unread searches. The sanitizer test uses an
ordinary summary record because orphan delivery samples are now discarded.

The full Catalyst suite passed on the frozen two-file change: **2,758 passed,
12 opt-in skipped, 0 failed (2,770 total)**, including all five retention
regression scenarios. One isolated gate used the existing Task 1 membership
patch; the exact source hashes and skipped tests are in `retention-review.json`.
Ranking, admission, configuration
generation, player/UI, devices, project integration and TestFlight are unchanged.
