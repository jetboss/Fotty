# Automatic cricket fixtures

Status, 6 October 2026: per-record ICC recovery is deployed. The16:16:30 UTC
receipt has77 fixtures,72 verified and five held, with two fresh verified live
matches. This is **partial recovery**, not healthy ICC coverage. Five original
October3 receipts remain quarantined; monitor/issue37 stay open. Shared121 stays.

## Per-record isolation rollout, 6 October

Protected [PR39](https://github.com/jetboss/Fotty/pull/39) merged normally as
`243f9bb662b2b1a42f187bd324071c654aa26884`, changing exactly six backend/monitor
files. All PR and merged-main Web CI, quality and CodeQL checks pass. Focused
tests pass79; the primary working-source web suite passes333. Source
`2026-10-06.cricket-isolation-1` is deployed100% as Worker
`6399f52d-e0d6-45e8-ba3d-1462a94093e3`. Pinned Wrangler4.127.1 dry-run and
strict deployment pass. Metadata comparison preserves all17 binding names/types,
plain vars, rate limits and four Durable Object namespace identities. Existing
secret names/types, paid flags, source activation and the sole`*/5` cron remain.
Exact-version scheduled invocation16:15:59 UTC completes ok; its bounded tail
contains no collection receipt. A separate normal due-check collection at
16:16:30 proves admission. No forced collection or state rewrite is used.

The earlier69-row snapshot froze ICC60 at3 October04:51:20.153 UTC on
`accepted-fixture-missing`, blocking valid unrelated updates. Recognized record
conflicts are now isolated: unaffected rows are verified; held rows preserve
their exact facts/observations. Collection completeness, pagination, identities,
watermarks,400-row bounds and the reviewed correction ledger remain barriers.
Failure receipts/backoff and unavailable cohort coverage are not cleared by
partial success. Explicit markers enter revision hashing and public validation;
whole-source retention cannot leave an old marked row looking fresh.

Root and independent read-only verification agree:77 rows, WI9 covered/fresh,
ICC68 unavailable,72 verified, five held and two fresh verified LIVE. IndiaU19
vs AustraliaU19(`270987`) advances to live; Pakistan vs India(`274310`) advances
from stale live to finished. India vs West Indies(`270273`) remains fresh live.
Held IDs275298/275299/275300 retain their last reviewed starts and original
October3 receipt; future274655/273760 retain05:30/06:00 UTC onOctober9 rather
than accept unconfirmed changes. All five still require source-fact resolution.
At16:17:39 the monitor removes stale-current-match findings but deliberately
retains repeated failure, unavailable coverage and stale competition-window
alerts.650 failures are not reset. The bounded CWI comparison matches its one
current/next24h supported fixture; this does not certify every ICC row.

Native build123 consumes the optional verified/held contract, protects row and
cohort cache watermarks, suppresses unconfirmed countdown/reminder starts and
keeps fresh matched provider listings separately discoverable without inventing
LIVE. Its Home sport counts use the destination's retained filters and interests.
See `docs/releases/Fotty-2.0.1-123.md` for the separate private device gate.
The owner's original Willow programme was not identified: a generic channel or
successful source lookup does not prove that exact broadcast's fixture identity.
Rollback is code-only to the prior Worker, never accepted fixture state.

## Historical verified Worker-only recovery, 1 October

Protected [PR36](https://github.com/jetboss/Fotty/pull/36) merged normally after
all checks as `0416690f66019657dea4c299d51546b5b3b3c7a6`. Exact clean release
qualification passes326 units, typecheck, changed-module zero-warning lint,
dry-run and redacted scans; hosted Web CI includes the optimized build.
Source `2026-10-01.cricket-corrections-1` is Worker version
`87b347ed-0b0c-4df1-b0ec-9c755f06fc5d`,100% traffic, preserving all runtime
settings, DO namespace identities and secret names/types. Five-minute cron is
registered; its exact-version scheduled handler at19:46:01.790 UTC completes
ok/zero exceptions. A successful handler and an accepted collection are separate
receipts; do not infer which caller caused collection.

At19:46:20 UTC production is complete/schema1/verified: all67 IDs retained,
exactly the three starts below changed and other64 starts equal. WI9/ICC58
observations advanced to19:45:36.647 UTC; all aggregate/cohort failures clear.
Internal revision/series evidence is absent. Hosted
[cricket36916807008](https://github.com/jetboss/Fotty/actions/runs/36916807008),
[sports36916809058](https://github.com/jetboss/Fotty/actions/runs/36916809058) and
[CPL36916811364](https://github.com/jetboss/Fotty/actions/runs/36916811364)
pass on merged main. CPL reports current without a fixture commit or PR.
The CWI current/next24h comparison is healthy; this does not independently certify
every ICC fixture. Reviewed incident34 is closed with fresh recovery evidence.
Health/embed, CPL39 and complete3/3 provider catalog pass; no paid/live-score call.
Owned dependency/bundle/tail resources are removed/stopped;44 GiB free.
Rollback is code-only to source4/versiond1cdb4e4, never old fixture state.

Owner112 already accepts newer same-ID cached starts/reminder reconciliation.
Its provider-replay branch can still delay visible changes until the local native
repair is separately installed. Shared111 predates this broad cricket consumer.
Backend recovery does not retrofit either binary or prove physical delivery.
See the [deployment receipt](https://github.com/jetboss/Fotty/pull/36#issuecomment-5939284827).

Earlier on 1 October the cleared sports expansion superseded the original deployment
with source `2026-10-01.sports-fixtures-4` / Worker
`d1cdb4e4-abb5-48a5-b024-2b276ddc23c8`, preserving this registry and monitor.
The earlier activation audit passed 67 fixtures/three scopes and CPL 39.
The earlier Jet iPad112 validated cache contains67 fixtures: nine West Indies and
58 other internationals, with CPL explicitly offseason. Its original lane receipts
are `2026-10-01T10:10:46.067Z`. Existing FPL/Home preferences are retained;
this does not qualify reminders or decoded playback.
See `Sports-Fixture-Service.md` for the superseding receipts and owner-device gate.

## Verified correction contract and local native repair, 1 October

Rendered ICC women fixtures and each canonical match-centre page confirm these
starts. The complete 18:38:42 UTC feed also agrees across its UTC, Malaysia
UTC+08:00 and India UTC+05:30 fields. This is authoritative publisher
confirmation, not independent cricket-board corroboration; the board checks
did not produce explicit kickoff evidence. Secondary copies are not counted as
independent sources.

| ICC fixture | Previous UTC | Verified UTC | Official publication |
|---|---|---|---|
| 275298, Indonesia Women–Samoa Women | Oct4 02:30 | Oct4 02:00 | [Match2](https://www.icc-cricket.com/matches/275298/indonesia-vs-samoa) |
| 275299, Malaysia Women–Indonesia Women | Oct6 02:00 | Oct6 02:30 | [Match3](https://www.icc-cricket.com/matches/275299/malaysia-vs-indonesia) |
| 275300, Malaysia Women–Samoa Women | Oct7 02:30 | Oct7 02:00 | [Match4](https://www.icc-cricket.com/matches/275300/malaysia-vs-samoa) |

`icc-kickoff-corrections.mjs` is a reviewed transition ledger, not another feed
or fallback schedule. It admits only these exact retained-old to collected-new
transitions: fixture/team IDs and names, series15827/name, ICC scope, T20 format,
scheduled→scheduled status, canonical source identity and equal row/collection
receipt must match. Receipts must be at least 18:38:42.869 UTC on Oct1, no older
than six hours and not future-dated; the transition expires before either old
or new kickoff. Existing complete-collection, identity, status, watermark,
cohort-isolation and durable-write guards remain. Internal series evidence is
stripped with `revised` before public/persisted fixture publication. An
unexpected unflagged move or reversal is still held; a subsequent explicitly
publisher-revised correction retains the existing admission contract. Cold
collection never synthesizes or rewrites source rows from this ledger.

At 19:02:16 UTC a bounded **in-memory** rehearsal against production's retained
67 rows and a fresh complete ICC67 response changes exactly those three starts,
keeps WI9/ICC58, and would clear the43-failure streak to verified/zero. Nothing
was written to cloud state during that rehearsal; recovery was still pending.
The later deployment receipt above supersedes this state. Local backend/monitor
regressions pass68; the complete
local web/Worker suite passes322 and focused ESLint has zero warnings.

The native replayed-provider branch now merges independently accepted cricket
updates into visible rows, with no retained provider evidence for enrichment,
then reconciles bookmarks/reminders once after cricket/sports merges. Three
regressions cover both30-minute directions, stale matching-source exclusion,
exact saved-ID continuity, participant rejection and complete-empty replacement.
The source-only native compile/test gate is separate from physical acceptance;
shared111 and owner112 have not been updated by this repair. The Worker-only
recovery above does not qualify the native repair or a shared app release.

Final local qualification:655 Catalyst tests passed, two skipped, generic
unsigned iOS Release compiled; nonincremental TypeScript and Worker dry-run
pass. Existing Catalyst playback tests emit four audio-session runtime warnings;
no new playback/audio change or physical notification-delivery claim is made.
The owned DerivedData/result bundle and Worker dry-run output were removed;
44 GiB remains free. Pre-existing dependencies, caches and user artifacts stay.

## Earlier conflict and deployed isolation, 1 October

At 14:10 UTC the deployed registry retains 67 fixtures (WI9 / ICC58), with
eight consecutive failures and its original 13:00:46 UTC observation. A bounded
fresh ICC response is complete (67 advertised/returned rows, 223,858 bytes).
Parsing succeeds; admission rejects three unflagged kickoff changes in the
Women's T20I Tri-Series in Malaysia. `icc:275298`, `icc:275299` and
`icc:275300` move by 30 minutes but have `is_revised=false`. No IDs, participants,
statuses or live rows differ. The initial detail-page reads did not provide
correction clearance. Later rendered canonical ICC pages resolve the publication
facts above; production retained the old rows until the later PR36 deployment.

Fresh CWI has no live/next-24-hour West Indies match, and all five fixtures in
the rolling window agree on teams, format and UTC kickoff. The previous shared
admission path froze WI refresh along with the conflicting ICC cohort.
Protected PR35 deploys cohort isolation: at 15:25:46 UTC WI9 advances with zero
cohort failures; ICC58 retains its exact 13:00:46 rows and receipts. All 58 ICC
records compare equal to the pre-rollout snapshot, including the disputed times.
The full source still has 18 failures and finite `admission/kickoff-unconfirmed`
evidence. This is partial WI recovery, not permission to accept changed ICC times;
no current-match omission was found. Deployed guards remain unchanged.
Safeguards also reject older empty/pending-only cohort receipts, block
cross-cohort ID movement and preserve full failure counts/backoff until both
cohorts recover. If a retained/fresh union exceeds 400 rows, including recovered
CPL, the whole last valid envelope and its original CPL receipt are held rather
than truncating rows, emitting an invalid response or throwing before backoff is
persisted. Success/failure paths, concurrent callers, restart and five-minute
retry boundaries have regressions. No admission-policy override was introduced.
Focused cricket/monitor qualification passes 63 tests; the clean release suite
passes 321, TypeScript/focused ESLint and Worker dry-run pass. Full GitHub gates
pass and exact merged main3742b96 is deployed, with its scheduled handler
observed at 15:30:45 UTC, outcome ok. Handler success is not full feed recovery.
The [scheduled monitor at 14:33 UTC](https://github.com/jetboss/Fotty/actions/runs/36877207360)
independently records `repeated-sync-failure,coverage-unavailable` against
current production main; its failure is the live incident, not an old checkout
or an expected pending activation. Earlier successful scheduled checks do not
clear it. The post-rollout [cricket monitor36884670580](https://github.com/jetboss/Fotty/actions/runs/36884670580)
still correctly flags this ICC incident. The sports monitor36884399877 passes
on merged main; hourly sports GitHub scheduler timing is still unobserved.

## Activation receipts

- Worker source `2026-09-30.cricket-fixtures-1`, deployment
  `88a5bce6-c694-435c-9b8c-6ac3173121de`, uploaded at 17:09 UTC.
  Cloudflare confirms the five-minute cron and registry binding; the deployed
  handlers are `scheduled` and `fetch`. Cron registration is verified, not an
  inference from a manual fixture GET.
- Protected [PR 27](https://github.com/jetboss/Fotty/pull/27) merged as
  `1f4ce95e1e813c8cefd309dcec423c2a451f3320`. Web CI run 36749066090 passes
  204 clean-worktree units, type/lint/dry-run/build; required repository and
  CodeQL gates pass. Two parser findings were fixed with one-pass entity decoding
  and lexical comment masking, with four regressions.
- The published hourly monitor's first
  [production run](https://github.com/jetboss/Fotty/actions/runs/36750055302)
  passes at 17:15 UTC, including 38 monitor tests and the independent CWI check.
  Healthy operation created no issue. Future scheduled runs are configured;
  this first receipt is a manual dispatch, not an hourly-timing observation.
- Production returns 63 verified fixtures: 10 West Indies and 53 other
  internationals, plus two provisional pairings counted separately. At 17:11
  UTC South Africa–Australia is live and today's West Indies matches are finished.
  All five upcoming CWI fixtures inside the feed window independently match
  named teams and UTC kickoff. CPL independently verifies all 39 fixtures.
  Existing health/embed/catalog contracts pass; all three catalogs responded
  during this check. No quota-consuming football-live or paid Coach call occurred.

Remote main was older than the deployed September 20 Worker. Publication
reconciled only its backend foundation and cricket dependencies, preserving
production behavior: existing modules hash-match the retained build-111 source
receipt and the entrypoint differs only by cricket integration. Paid Coach stays
disabled at the existing 50-attempt group limit; secrets/budget identities were
not changed. Remote native source remains older than the locally retained
client; publish/reconcile its access and draft contracts before any future
paid-Coach enablement. An absent adjusted draft bank remains explicitly unknown.

## Coverage and ownership

- `/api/cricket/fixtures` supplies CPL plus international fixtures from the
  ICC website's public structured schedule. Coverage groups are `cpl`,
  `west-indies` and `icc`; `icc` means the broader international feed, not that
  every bilateral series is an ICC tournament. This does not cover every
  domestic cricket league.
- `cricket-fixture-policy.mjs` validates UTC source timestamps, complete bounded
  pagination, international gender/youth identity and official status. The
  rolling window includes six prior days and seven future days, retaining
  multi-day Tests. Explicit provisional dates or participants are omitted from
  customer pairings and counted separately as pending; they are not fabricated.
- `CricketFixtureRegistry` is one globally named Durable Object. It persists
  accepted snapshots and serializes concurrent cold callers and cron work.
  Content revisions exclude receipt times. Failed refreshes retain original
  per-source observations; a fetch must never make stale live evidence fresh.
- The existing CPL adapter remains its full-season authority. During its active
  season the registry collects the verified CPL response separately. The
  reviewed 2026 offseason ends at the year boundary; another season requires
  explicit source/manifest review. Unknown future coverage becomes unavailable,
  not a silently renewed 2026 schedule.

## Refresh and monitoring

The configured Cloudflare trigger checks every five minutes. Persisted due
times limit actual source collection to five minutes when live/imminent,
15 minutes when a fixture starts within 24 hours, and four hours when quiet.
Failures retry after five minutes. Once activated, this collection does not
depend on a tester leaving Fotty open or on this Mac being awake.

The active hourly GitHub workflow runs `tools/audit-cricket-fixtures.mjs`.
It validates the accepted snapshot and independently compares current West
Indies matches with Cricket West Indies. Missing fixtures, stale match-window
receipts and repeated sync failures alert the owner in one dedicated, redacted
bot issue. Transient endpoint failures and brief source-status disagreements
require a repeated matching finding before notification. The monitor never
writes fixtures, merges source changes or deploys a repair.

CWI calendar-heading timezone is not documented for AST/UTC dates crossing
midnight. Such rows fail the independent check rather than manufacturing a
24-hour discrepancy; the ICC registry still supplies their explicit UTC facts.

The active local Codex heartbeat retains ID `fotty-cricket-fixture-supervision`
but is now named **Fotty all-sport fixture supervision**. It checks both cricket
and the app-wide sports audits every six hours, stays quiet on healthy/unchanged
states and investigates new actionable failures with scoped sub-agents. Deferred
or unactivated lanes are expected source gaps, not new incidents. It is supplemental investigation,
not the cloud updater. It respects pending activation and needs this local host
available. It cannot publish, deploy, install, release or change paid limits.

## Native consumer and release boundary

`CricketFixtureCatalog.swift` validates and caches bounded complete responses.
Partial responses preserve unavailable competitions. Explicit live evidence
expires after 30 minutes; ODI/Test live status is not guessed from T20 duration.
Non-200, malformed, fallback and rejected responses have a five-minute retry
cooldown even after a quiet-day cache. Cancellation clears that cooldown.

Stream enrichment requires cricket, both exact canonical teams/squad qualifiers
and kickoff within 15 minutes, accepting either team order and mapping badges
to the right side. Only current provider descriptors are attached. Willow/Fox
remain separate channels: a live fixture is not proof of a playable broadcast.
Existing CPL channel behavior and authority are preserved.

Owner build 112 adopts this new route. After that installation, routine
fixture/status updates do not need an app rebuild. Shared testers still require
their separately qualified native update. Do not install a binary or
send a TestFlight update without explicit distribution authority and the normal
source-receipt/device qualification gates.

## Operator checks

```sh
node tools/audit-cricket-fixtures.mjs
node tools/audit-cpl-fixtures.mjs --live
node tools/audit-worker-health.mjs
cd web && npm run test:unit && npm run worker:check
```

The earlier activation endpoint/identity audits passed against the
deployment above; the current unconfirmed-kickoff incident is recorded at the
top, not a healthy recovery. Future changes must retain a deployment identity, confirm
registry binding and cron registration, verify a fresh public snapshot and run
the independent monitor. Do not count a public GET as proof of cron execution.

Implementation-time evidence (16:35 UTC): local collection contained 63 named fixtures, including
India–West Indies and South Africa–Australia marked live by ICC. CWI independently
matches India–West Indies. Two pending Asian Games pairings are deliberately
excluded. The reviewed CPL audit passes all 39 fixtures, with exact known
verifier exceptions for matches 21, 22 and 28; actual fixture times did not move.
This is time-scoped source evidence, not device decoding or universal coverage.

Historical 30 September local qualification: 200 web/Worker tests (including 38 monitor tests), 18 new
native cricket XCTest methods within the complete simulator-free Catalyst suite,
generic unsigned iOS Release, TypeScript, zero-warning lint, Worker dry-run,
optimized web build, workflow actionlint and targeted gitleaks scans all pass.
Owned Xcode/web/lint temporary output was removed; the pre-existing web output
was restored. About 52 GiB remained free. That source-only gate installed no binary;
the separate 1 October owner gate above supersedes its device status.
The managed activation source checkout is clean and 23 MiB; Codex refused
archival because this chat/workspace is pinned. Its borrowed dependency symlink
and generated type-check output were removed. Preserve the protection; retry
normal archival after it is unpinned, without deleting the checkout manually.
