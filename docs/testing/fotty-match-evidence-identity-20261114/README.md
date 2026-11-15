# Stage 4 — match evidence belongs to the current fixture (14 Nov 2026)

Base: `835cf6eda21f266b93e0772f145d72f259e91352` (provider receipt retention follow-up).

## Defect

Per-match playback evidence (`LiveSourceHealthStore` match observations and the
wrong-programme renewal keys) was keyed by the raw fixture/event ID plus the executable
delivery. A provider that reuses a raw row ID and a rolling media URL for a different
fixture (changed opponents, competition, squad or cricket Test/day) made the new fixture
inherit the old fixture's verdict. The new, independently valid binding was then refused.

Baseline red (root, before any repair):
`CatalogPlaybackIdentityTests.testReusedProviderIDDoesNotTransferWrongProgrammeToChangedOpponents`
compiled and ran. Exactly 1 method and 2 assertions failed: the replacement read
`wrongProgramme` instead of `unknown`, and its admission was `nil` instead of `ready`.
The before, original-reopen and binding assertions all passed.

## Repair (evidence attribution only)

- `LiveSourceHealthStore.MatchEvidenceScope` is immutable and built from the owner's
  current `StreamPlaybackRequest`. The player builds it once from its immutable event. Discovery
  builds it once per resolution, and the selector/policy build it from the request they
  already evaluate. Every match-specific read and write requires one: `recordMatchOutcome`,
  `matchEvidence` (source and session), `sustainedMatchProviders(in:)`,
  `positiveRecoveryHistory`, `rankedSingleStreamSessions(matchScope:)`,
  `StreamDiscoveryCoordinator.collect(matchScope:)`, `hasCurrentDirectEvidence`,
  `admitsSingleSession` and `MatchOrderComparison(scope:)`. The old raw-ID overloads
  were removed, so the compiler rejects any call site that was not converted.
- Scope fields come from existing parsers and structured metadata only: the raw ID, the
  reviewed sport plus participant pair (or a reviewed cricket/TV channel), the competition
  (event and cricket fixture), the structured squad (gender and age group), and the
  cricket format, ordinal and Test day. Absent values use a fixed sentinel and never act
  as a wildcard. There are no aliases or fuzzy matching.
- Kickoff is excluded, so rescheduling the same game keeps its evidence. The
  wrong-programme renewal key also drops its kickoff discriminator and is now prefixed by
  the scope. A postponed same-fixture renewal with a new token still reads as rejected.
  Which renewals are admitted is unchanged.
- An undated request is read for identity only (never admission) with its preferred
  event's own published kickoff. That way the matcher's existing guards still decide
  whether a verified official prefix such as `ICC · India vs Australia` may be stripped:
  same ID, sport, teams and title, verified fixture, and no catalog conflict. The request
  itself stays undated, and no date is invented. With no kickoff anywhere, known teams use
  `participantIdentity` on the same title. Neither case falls back to a raw-ID-only scope.
- The writer records nothing when a supplied session is not exactly this source, or belongs
  to another fixture. A source-only write (nil session) stays valid. The player passes its
  active session only when it is the recorded source, so its existing source-only writes
  are kept.
- Wholly unparseable requests get a separately tagged, request-local scope built from the
  exact trimmed category, home, away and title. It proves no programme identity. An
  identical request keeps its own negative evidence. Any other text, and any known
  replacement, is independent.
- A session whose `matchID` differs from the supplied scope is never read or written.
- Only the device HMAC is persisted. Payload version, caps (128 deliveries × 8
  samples, 256 renewal keys) and the 6 h lifetime are unchanged.
- Bound and unbound (Web) deliveries of one request share that request's scope.

## Unchanged

- Ranking formulas, weights, tie-breaks, provider priority and enablement.
- Source guards, the `applyMatchEvidence: false` baseline and multi-stream paths.
- Global provider startup history, channel behaviour, `ProgrammeEvidenceLedger`, FPL,
  phone and TestFlight.

## Trade-offs and limits

- **Legacy records:** old raw-ID entries are not relabeled and cannot equal any scoped key.
  They stay bounded and expire within 6 h. During that window they neither veto nor qualify
  any fixture, including their own (a conservative, one-lifetime loss of history).
- **Enrichment:** when a field is missing and later known (for example the competition or
  Test ordinal), the scope starts again from `unknown` rather than merging histories.
- **Catalog context drift during recovery:** the player's `event` is immutable, and its
  scope is built once from it for every player read and write. `nextPlayableSource`
  separately calls `currentMatchForSwitch`, which returns the latest catalog event (or a
  recomputed registered request), and passes that request to `admissionForMatchAlternative`.
  That admission scopes from the request it was given. The catalog event must have the same
  kickoff, be reusable for the owner and carry no conflict. Its competition, squad, cricket
  ordinal or Test day can still differ through enrichment or live context. When they do, that
  one admission check does not see the owner-scope rejection. The player's own healthy
  ordering does see it, so the rejected delivery sorts last, and it stays excluded for the
  current attempt.
- **Residual collision:** two different fixtures with the same raw ID, teams, competition,
  squad and cricket context but a different kickoff share a scope. That is the deliberate
  consequence of the no-kickoff-split rule.
- **Out of scope:** `ProgrammeEvidenceLedger` still scopes viewer verdicts by fixture ID.
  Current production verdicts are attempt-only and metadata is lookup-scoped, so it is not
  a cause of this red. A future boundary scope there is a documented limitation.

## Validation

See `validation.json`. Baseline red: 1 failed method / 2 assertions. The first candidate compile exposed missing actor annotations in the new test helper; the corrected compile passed. Focused: **383 passed, 2 opt-in skips, zero failed**. Full Catalyst: **2,786 passed, 12 opt-in/physical skips, zero failed** (2,798 total). All source hashes remained unchanged through the green compile and tests. Actual Claude round 4 and the independent read-only review found no remaining P1/P2. The ranking comparator SHA256 is unchanged. Physical status is in `physical-watch.json`.

This is a targeted repair of demonstrated evidence attribution, not completion of a permanent fixture-identity migration. No generic provider-ID migration or cross-provider alias learning is claimed.

## Consolidated Jet check — normal signed Release 329

Installed one normal signed iPad Release, version 3.0.0 (329), containing this repair
and the provider receipt-retention follow-up. Existing source opt-ins, appearance,
interests and FPL-related stable preferences were unchanged (eight checks). All sports
was restored on Home and the test playback was closed. Phone, FPL, multi-stream,
cloud publication and TestFlight were untouched.

- **Live football did not pass:** St. Vincent and the Grenadines–Belize was corroborated
  in progress at 00:17 UTC on 15 November. Normal Watch found CS1 (2 offered / 1 admitted),
  but the guarded relay reported `upstream_response / invalid_response`; no picture
  started. The retry and refreshed-discovery attempt also failed. Home retained the match
  and Watch afterward. The records establish a delivery failure, not a stored
  wrong-programme rejection; they do not establish its upstream cause. Its failure UI
  still says “Stream Ended Unexpectedly”; the owner's separate uncommitted UI repair
  was deliberately not included.
- **Live cricket passed this bounded check:** Cricket Australia identified Sydney
  Sixers Women–Melbourne Renegades Women, WBBL match 23, women/T20, 15 November
  00:00 UTC, as in progress. Normal match-card Watch selected CNC **LS1**. The correct
  Sky Sports Cricket programme was visibly corroborated by teams, players and the
  contemporaneous score. Watch-to-decoded was **14.658 s** (attempt-to-decoded **6.236 s**).
  The app recorded **90.912 s** of advancing **1920×1080** native playback, **0 stalls**
  and **0 dropped frames**. Pause held the frame, Sources remained paused with four
  choices, and Play resumed visible motion on the same attempt without restarting.
- The other three listed cricket routes were not independently qualified. Device Hub
  does not relay audible sound; no audio, PiP, fullscreen or forced-failover pass is claimed.
  Synthetic reused-ID regressions were tested locally, not fabricated in the live catalogue.
- A brief blank Home after mirrored scrolling recovered on navigation. Its cause is
  unproven and this evidence-ownership patch makes no claim to repair it.

See `physical-watch.json` for timestamps and redacted app evidence. These results close
this targeted implementation check; they do not establish overall release readiness or
complete the remaining provider/competition acceptance work.
