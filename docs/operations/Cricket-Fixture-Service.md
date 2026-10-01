# Automatic cricket fixtures

Status, 1 October 2026: cloud collection and the hourly monitor are published
through protected PR27; production source3 preserves them. Candidate source4's
cohort-isolation/boundary repair now has owner publication/deployment approval,
not deployed recovery. New native installs and TestFlight are not authorized.

At14:10 UTC production retained67 fixtures (WI9/ICC58) with eight failures and
the original13:00 UTC observation. Three future ICC women's tri-series kickoffs
changed30 minutes without is_revised; no independent correction clearance was
found. Fresh CWI agreed with five in-window WI fixtures and had no live/next24h
omission. Scheduled run36877207360 at14:33 UTC confirmed repeated sync failure.
Source4 independently admits WI/ICC after the unchanged complete collection
gate, retaining failed cohort facts/receipts exactly. It does not accept those
three unflagged corrections merely to clear the monitor.

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

The current failure is an unconfirmed source correction, not expected pending
activation. After source4 deployment, retain the deployment identity,
confirm registry binding and cron registration, verify a fresh public snapshot,
and run the independent monitor. GitHub scheduling is active only after the
workflow is published on the default branch and successfully exercised.

Current evidence: live local collection contains 63 named fixtures, including
India–West Indies and South Africa–Australia marked live by ICC. CWI independently
matches India–West Indies. Two pending Asian Games pairings are deliberately
excluded. The reviewed CPL audit passes all 39 fixtures, with exact known
verifier exceptions for matches 21, 22 and 28; actual fixture times did not move.
This is time-scoped source evidence, not device decoding or universal coverage.

Local qualification: 196 web/Worker tests (including 34 monitor tests), 18 new
native cricket XCTest methods within the complete simulator-free Catalyst suite,
generic unsigned iOS Release, TypeScript, zero-warning lint, Worker dry-run,
optimized web build, workflow actionlint and targeted gitleaks scans all pass.
Owned Xcode/web/lint temporary output was removed; the pre-existing web output
was restored. About 52 GiB remains free. No binary was installed or distributed.
