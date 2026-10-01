# Automatic cricket fixtures

Status, 1 October 2026: source4's cohort-isolation/boundary repair is deployed
through protected PR35. The Worker-only correction candidate now has owner
publication/deployment approval; production recovery still requires a deployed
receipt. Native edits, installs and TestFlight are outside this release.

ICC's rendered schedule and all three canonical match-centre pages were checked
on 1 October. They confirm the unflagged UTC corrections below for Women's T20I
Tri-Series in Malaysia, 2026 (publisher series15827). This is authoritative
publisher confirmation, not independent national-board corroboration.

| ICC ID | Fixture | Previous UTC kickoff | Confirmed UTC kickoff |
| --- | --- | --- | --- |
| 275298 | Indonesia Women–Samoa Women | 4 Oct 02:30 | 4 Oct 02:00 |
| 275299 | Malaysia Women–Indonesia Women | 6 Oct 02:00 | 6 Oct 02:30 |
| 275300 | Malaysia Women–Samoa Women | 7 Oct 02:30 | 7 Oct 02:00 |

`icc-kickoff-corrections.mjs` admits only those exact existing-row transitions,
with unchanged team/squad identity, competition, T20 format, scheduled status,
ICC provenance and publisher series. A complete fresh collection received after
the verified18:38:42.869 UTC publication evidence must still pass every ordinary
admission gate. Each authorization expires before either kickoff. It does not
invent fixtures, synthesize revised flags, refresh retained receipts, clear other
conflicts or permanently pin a schedule. Internal evidence fields are stripped
from the unchanged public schema1 response. Genuine later publisher-flagged
revisions retain the existing contract.

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
- Source4 keeps per-cohort finite failure diagnostics, rejects cross-cohort ID
  movement and older empty/pending-only observations, and preserves aggregate
  failures/five-minute retry until both cohorts recover. A fresh/retained/CPL
  union over400 holds the entire previous valid envelope and original CPL
  receipt; it never truncates rows or throws before persisted backoff.
  Success/failure, concurrent calls, restart and retry-boundary regressions pass.
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

The published hourly GitHub workflow runs `tools/audit-cricket-fixtures.mjs`.
It validates the accepted snapshot and independently compares current West
Indies matches with Cricket West Indies. Missing fixtures, stale match-window
receipts and repeated sync failures alert the owner in one dedicated, redacted
bot issue. Transient endpoint failures and brief source-status disagreements
require a repeated matching finding before notification. The monitor never
writes fixtures, merges source changes or deploys a repair.

CWI calendar-heading timezone is not documented for AST/UTC dates crossing
midnight. Such rows fail the independent check rather than manufacturing a
24-hour discrepancy; the ICC registry still supplies their explicit UTC facts.

The existing local heartbeat `fotty-cricket-fixture-supervision`, now named
Fotty all-sport fixture supervision, checks both bounded fixture audits
every six hours, stays quiet on healthy/unchanged states and investigates new
actionable failures with scoped sub-agents. It is supplemental investigation,
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

One native update is needed to adopt this new route. After that, routine
fixture/status updates do not need an app rebuild. Do not install a binary or
send a TestFlight update without explicit distribution authority and the normal
source-receipt/device qualification gates.

## Operator checks

```sh
node tools/audit-cricket-fixtures.mjs
node tools/audit-cpl-fixtures.mjs --live
node tools/audit-worker-health.mjs
cd web && npm run test:unit && npm run worker:check
```

The retained ICC failure is a now-confirmed source correction, not expected
pending activation. After correction deployment, retain the deployment identity,
confirm registry binding and cron registration, verify a fresh public snapshot,
and run the independent monitor. GitHub scheduling is active only after the
workflow is published on the default branch and successfully exercised.

Pre-deployment evidence at19:02 UTC: production and the fresh complete ICC
collection each contain67 named fixtures (WI9/ICC58). A read-only in-memory
rehearsal accepts exactly the three corrections and clears43 aggregate failures
without altering the other64 starts. That rehearsal is not persisted recovery.
Fresh CWI comparison found no supported current/next24h omission. The reviewed
CPL audit passes all39 fixtures with the unchanged exact verifier exceptions
for matches21,22 and28. This is time-scoped source evidence, not device decoding
or universal coverage.

Isolated Worker-candidate qualification: all326 clean-checkout web/Worker tests
pass, with TypeScript, zero-warning lint on changed modules, Worker dry-run and
targeted gitleaks. Full baseline lint has48 pre-existing warnings and no errors.
The clean baseline package/lockfile are retained. GitHub Web CI additionally
qualifies the optimized web build before merge. Owned dependency/dry-run
temporary output is removed after use. No native binary is built, installed or
distributed for this Worker-only gate.
