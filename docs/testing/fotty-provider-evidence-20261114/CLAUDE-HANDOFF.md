# Claude handoff — Xcode integration, Right match and Owner Status

Prepared 14 November 2026. Repository: `/Users/jelani/Documents/Development/Fotty`.

## Owner request and scope

Finish Xcode integration, quiet optional **Right match** feedback, and fixture
evidence/count presentation in Sources and Owner Status. Keep ranking unchanged.
Leave all devices, FPL and multi-stream alone. No TestFlight, device installs,
physical tests, cloud deployment, Git push or new live-provider requests.
This is a source/integration and local Catalyst validation task.

Preserve the existing Watch flow and separate Wrong match / Picture blocked
actions. Do not redesign Home or add mandatory confirmations. Do not broaden
provider acceptance or change source order, scores, latency preferences,
fallback policy, matching or transport restrictions.

## Baseline — already merged locally

`wip/ios-3.0-baseline` is at **03ff887876b9a7bb043d55a1cba47df2b1007c14**:

| Commit | Contents |
| --- | --- |
| `63137a78fe5f0de3faffa30459417cc5a38cff01` | Evidence foundation, expiry, prepared transport and ephemeral session provenance. |
| `d1379394619f4a902cb86f410341bc481603196c` | Highfly/PenguPlay receipts, accounting, durable configuration generations and preparation bridge. |
| `03ff887876b9a7bb043d55a1cba47df2b1007c14` | Your requested retention correction: delivery samples cannot displace viewing records. |

Do not cherry-pick these again. They were fast-forwarded locally; nothing was
pushed. Your Task 1 review approved `63137a7`; your Task 2 review required the
retention fix now in `03ff887`.

Latest full Catalyst result: **2,758 passed, 12 opt-in skipped, 0 failed
(2,770 total)**. All five retention scenarios passed. This validates the clean
committed source **plus the Task 1 Xcode membership patch in an isolated test
checkout**, not the primary checkout's uncommitted work and not physical playback.

At handoff, the primary checkout contains **45 pre-existing uncommitted files**,
including player/coordinator/UI tests, fixtures, backend and monitoring work.
All were preserved byte-for-byte during the merge. Inspect `git status` and
`git diff` before editing. Reconcile your own in-progress player work with HEAD;
do not reset, broadly stash, overwrite or commit someone else's changes. Use
your own branch/worktree as agreed. Do not assume the new baseline tests cover
those 45 files.

Read these durable references first; earlier README statements about “not yet
merged” describe the original isolated task, not the current merged state:

- `docs/plans/fotty-roadmap.md` and `docs/plans/discussion/round-2-codex.md`
- `docs/testing/fotty-evidence-foundation-20261114/README.md`
- `docs/testing/fotty-provider-evidence-20261114/README.md`
- `docs/testing/fotty-provider-evidence-20261114/retention-review.json`
- Your `docs/plans/discussion/codex-2-review-claude.md` (currently untracked).

## 1. Finish the Xcode memberships

`Fotty.xcodeproj/project.pbxproj` still lacks these three memberships:

| File | Target/group |
| --- | --- |
| `Fotty/Core/Models/StreamEvidence.swift` | Fotty sources; Models group. |
| `FottyTests/StreamEvidenceTests.swift` | FottyTests sources/test group. |
| `FottyTests/StreamEvidenceSessionTests.swift` | FottyTests sources/test group. |

The reviewed patch is
`docs/testing/fotty-evidence-foundation-20261114/project-membership.patch`.
It uses zero-context hunks: inspect before applying with `git apply
--unidiff-zero`, or recreate the memberships if your project file moved. Check
the model's group path explicitly; putting it under Networking caused the first
Task 1 compile failure. Ensure no duplicate references/build-file entries.
Task 2 adds no further source files requiring membership.

## 2. Wire provenance through actual single-player preparation

Use the existing viewing-session owner. Do not create another session manager.

Relevant APIs already implemented:

- `ProviderEvidenceConfiguration.currentGeneration(for:)` — read-only current
  provider epoch. Do not call the mutating `generation(for:configuration:)`
  while displaying feedback or querying evidence.
- `LiveSourceHealthStore.fixtureProgrammeScope(fixtureID:)` and
  `channelProgrammeScope(channelID:programmeID:)` — opaque scope factories.
- `StreamSession.recordingDeliveryTransport(cookies:at:)` — actual captured
  transport; raw cookies are not retained by this evidence API.
- `LiveSourceHealthStore.preparedDeliveryProvenance(from:for:scope:
  configurationGeneration:at:)` — opaque listing handoff to prepared transport.
- `StreamSession.recordingDeliveryProvenance(_:scope:
  configurationGeneration:at:)` — attach only the valid association.
- `LiveSourceHealthStore.recordViewerVerdict`, `programmeCorrectness`, and
  `endProgrammeEvidenceAttempt` — typed evidence lifecycle.

Required preparation flow:

1. Preserve the selected discovery session carrying its listing provenance.
2. Capture the exact cookie snapshot actually supplied to that native/relay
   attempt, including an explicitly empty snapshot only when that is real.
   Never read a later mutable cookie jar when feedback arrives. WebKit cookies
   and `HTTPCookieStorage` are not interchangeable.
3. Record prepared transport on the actual session, then use the bridge with
   the original selected session and the prepared session. Recheck the current
   request, source, scope and configuration before installing the result.
4. Update the session reference actually used by feedback/presentation, not
   just a temporary local copy. Missing/expired evidence means **unknown**;
   it must not stop an otherwise admitted stream.

The current player's `preparePlaybackURL(for:requestID:)` exposes the relay
cookie snapshot; inspect both its ordinary direct path and existing handoff
path. This is an integration point, not permission to change multi-stream.
Preserve cancellation/discard handling and existing audio ownership.

The bridge requires the same source UUID, fixture, provider and current
configuration, valid original provenance and prepared transport. It preserves
the original lookup timestamp and is valid only within that lookup's 90-second
metadata lifetime. It cannot extend authority or copy correctness onto a
different contract. Do not manufacture raw listing IDs in the player.

**Renewal is a separate edge:** `renewingDelivery(from:for:at:)` preserves the
old selected source UUID, while a fresh lookup may create a new UUID. Only a
distinct fresh lookup may supply new provenance. Prepare/rebind against that
fresh descriptor before adoption as appropriate; never make an old listing
look fresh or weaken the bridge's same-selection guard. Capture the actual new
transport and keep attempt correlation explicit. The initial `source_id`
receipt join alone does not prove renewed-attempt attribution. If a shared API
change is necessary, hand a focused contract/test proposal to Codex for review.

## 3. Add quiet, explicit Right match feedback

Primary Claude-owned surfaces:

- `Fotty/Features/Player/LivePlayerViewModel.swift`
- `Fotty/Features/Player/ViewingSessionCoordinator.swift`
- `Fotty/Features/Player/LivePlayerView.swift`
- `Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift`
- Existing single-player options in `ViewingExperienceView.swift`, if needed.

Add a quiet optional **Right match** action for the current eligible single
stream, using the existing Sources/player feedback presentation. No modal
prompt or interruption. Only a deliberate tap may record `.confirmed`.
Keep Wrong match and Picture blocked distinct. Wire explicit Wrong match to
`.rejected` when current typed provenance is available, preserving the already
approved manual wrong-match recovery behaviour. Picture blocked must never
become programme rejection or confirmation.

Fence the action using the current attempt/request UUID, source UUID, active
session, scope and provider generation immediately before writing. Preserve
existing paused/PiP/retired/stale-action eligibility protections. A queued tap
from an old sheet must not affect a new attempt, even on the same source.

Right match must not restart/resume playback, change the selected source, bump
ranking, record legacy playback success, or trigger discovery. Neither decoded
frames, duration, a working URL nor metadata agreement automatically confirms
the programme. Failed evidence writes must not display success.

Supply a genuinely authoritative fixture/programme boundary if available;
otherwise use `.attemptOnly`. A generic channel name, kickoff plus guessed
duration and the 90-second metadata TTL are not programme boundaries. Do not
invent programme identity for rolling channel tiles or provenance for providers
not yet instrumented. Keep their evidence unknown.

Call `endProgrammeEvidenceAttempt` on actual attempt retirement/replacement.
It removes attempt-only observations but is not a cancellation tombstone:
late callbacks still need owner-side fencing. Refresh displayed correctness
when boundaries/cookies expire, configuration changes or the attempt changes.
Do not leave a cached “Confirmed by you” label beyond its valid scope.

## 4. Present honest fixture evidence in Sources and Owner Status

Claude owns `Fotty/Features/Settings/Views/SettingsSupportViews.swift` and the
presentation/tests. Keep owner diagnostics out of ordinary Home/Watch flows.

Use `programmeCorrectness` to distinguish unknown, metadata agreement,
viewer-confirmed and viewer-rejected. Metadata contradiction is diagnostic
evidence, not an automatic rejection or a ranking input. “Confirmed by you”
must mean explicit, currently valid viewer evidence, never observed playback.

Use `FottyQualityStore.fixtureLookupCounts(fixture:provider:window:)` for
fixture/provider/window counts. New receipts exist for Highfly/PenguPlay only;
missing evidence for other providers means unknown/not instrumented, not zero
offers or failure. Viewing these screens must not issue source/network checks.

Keep units separate:

- Advertised raw entries count repeated reads and duplicates.
- Unique contracts are deduplicated across retained lookups, not a sum of
  per-lookup unique counts. They are a lower bound when truncated.
- Read, unread and known-empty count logical selected-listing stream responses,
  not every catalog request or internal transport retry. Unread is not empty.
- Admitted choices are not played, stable or correct programmes. Keep
  selection-stage losses distinct from provider entry accounting.
- A first-picture Watch outcome is not a full programme/correctness proof.
  Do not add legacy admission records and new lookup receipts as two separate
  sets of offers. Do not invent “used” counts from admitted counts.

The `provider_delivery` source UUID joins only the exact admitted origin to
existing initial player records. Use real playback evidence where available;
show partial/unavailable if sample eviction or renewal prevents a reliable join.
Do not reconstruct historical HF1 rugby attribution: the identifying evidence
was never collected then.

Preserve the corrected retention contract: 250 records total, ordinary records
selected first, newest two lookup sample groups using spare capacity only.
Summaries survive sample eviction within ordinary retention; missing samples
mark them truncated/not reconciled. Do not infer totals by counting remaining
sample rows or add a separate unlimited history. Keep all new stored/exported
data opaque; no raw listing IDs, titles, stream URLs, tokens, headers or cookies.

## 5. Validate the final integrated tree locally

Add focused integration regressions for:

- Current Right match records confirmation without restart, discovery or reorder.
- Old source/attempt/sheet actions cannot confirm a replacement attempt.
- Paused, PiP, retired and failed-write paths preserve existing eligibility.
- Wrong match remains rejection/recovery; Picture blocked remains neutral.
- Generation A → B → A and enablement/credential changes invalidate evidence.
- Actual cookies, empty transport, probe/contract changes, lookup expiry and
  fresh renewal preserve attribution without reviving old correctness.
- Attempt-only cleanup/relaunch and authoritative programme boundaries.
- Mostly-unknown UI, unread versus known-empty, repeated lookups, truncated
  counts, other-provider unknowns and sample eviction preserving viewing logs.
- No ranking/selector change, no automatic programme confirmation, no raw data
  leakage, and no discovery side effects from feedback/status presentation.

Use the real session owner and injected fixtures; do not substitute helper-only
tests for the player wiring. Then run the full Catalyst `FottyTests` suite on
the final source **with memberships committed in the real project**. The known
12 opt-in integration/device tests remain outside this source-only gate; report
their skips honestly. Do not claim a physical Right match/UI pass.

Use one bounded temporary output directory, no simulator, sequential heavy
builds, disk checks and cleanup of owned outputs/assertions on every exit.
The prior successful gate used Mac Catalyst arm64, Debug, `-jobs 2`,
`-parallel-testing-enabled NO`, `-only-testing:FottyTests`, and ad-hoc Catalyst
signing. Do not run a build/install helper targeting Jet or a phone.

Commit only your integration changes and tests. Return commit hashes, exact
full-suite result/skips, changed files, any unresolved integration contract,
and confirmation that ranking/devices/FPL/multi-stream/TestFlight stayed
unchanged. Request Codex cross-review before merging your integration branch.
Update your roadmap progress after the work is actually complete.

## Known limits

The earlier Task 2 intermediate run hit the visual-baseline image-cache
precondition once; later full runs, including the retention gate, passed it
without changing that test or artwork. Its cause is not proven. Historical
audio reconnect timing uncertainty remains documented separately; do not hide
new failures or use these notes as permission to skip coverage.

The existing agent memory check reports `Current-State.md` over its 8 KB
budget. This is separate housekeeping; do not mix a broad memory rewrite into
the integration or overwrite the uncommitted historical summaries.
