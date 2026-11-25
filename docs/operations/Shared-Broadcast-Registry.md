Current native follow-on: signed195 is installed onJet. The initial fullscreen request retains inline video until same-window AVKit presentation commits; bounded pending retries/rollback preserve transport ownership.143focused tests and real Lille–Lens native fullscreen/pause/resume/PiP over Home118.773s/systemRestore pass. No phone/FPL/multi/TestFlight change. Final cloud normal collector completed20:01:01UTC. Receipts: docs/testing/fotty194-shared-watch/.

# Shared broadcast registry

## Current deployment — 31 October 2026

Protected main `b91812f` (PR111; PR110 preceding) is deployed as playback
`07650a86-59c0-4187-ab79-92554ec247e5`, source identity
`2026-10-31.broadcast-matching-1`, with matching watchdog
`f8ec2d9e-15d1-4266-b39c-fefc5a458665`. All21/3bindings, original activation and129
retained notices are preserved. Actual normal collector completion15:21:02UTC
is later than the paired deployment. Eight reviewed metadata families remain ON;
this does not mean eight working independently qualified suppliers.

Native202 is installed privately onJet:49final discovery/order tests pass. Actual
PL HomeWatch→CS2 and>121s correct-programme hold pass; startup remains slow.
201nativefullscreen/pause/resume/PiP/Restore passed on unchanged presentation code.
AS compatibility and intermittent refresh cause remain unresolved. Jet only. Phone, FPL, multi-stream
and TestFlight remain unchanged. Receipts: testing/fotty201-football-watch-2026-10-31/.

## Ownership and data flow

The existing playback Worker owns a new `BroadcastRegistry` Durable Object,
named `shared-broadcast-registry-v1`. It reads accepted Sports and Cricket
registry snapshots, collects bounded metadata from eight reviewed adapters,
and retains explicit source observations and canonical fixture links.
Official fixtures remain the authority for match identity and status. A source
listing cannot manufacture a fixture, change its kickoff or make it LIVE.

```text
Accepted Sports / Cricket snapshots ──┐
                                     ├─ association policy ─ shared snapshot
Reviewed source metadata ─ observations┘                         │
                                                 native local opt-in filter
                                                               │
                                                   fresh source resolution
                                                               │
                                               existing guarded native player
```

The server allowlist is `streamex`, `score808`, `communitysports`,
`plaviosports`, `cncsports`, `flixstreams`, `streamvix` and `reviewedtv`.
These are reviewed metadata identities, not eight proven independent working
suppliers. `reviewedtv` supplies fixed-station programme metadata; it does not
supply media URLs or enable TV1 playback.
In particular, the StreamEx primary/mirror/backup profiles remain one family.
Collection on the server does not enable a provider on anyone's device.
`BroadcastRegistryClient` filters lookup through current local source choices;
resolution rechecks enablement and the exact current fixture.

`GET /api/live/broadcasts` returns schema 1 metadata with a 30-second HTTP cache
directive. Query parameters are rejected. Public requests cannot trigger
collection; POST is rejected. While the flag, binding or allowlist is invalid,
the endpoint returns unavailable/pending rather than an invented empty catalog.
Native metadata refresh is bounded to one attempt per five minutes, with
accepted-cache fallback and original receipt times preserved. Native 194 sends
`X-Fotty-Broadcast-Capabilities: reviewedtv-programme-v1` to receive the eighth
lane. Default schema 1 reads retain the original seven-family projection for
older strict clients. The two profiles have separate cache identities; neither
projection renews original observations or changes local source choices.

## Automatic collection and request budget

The existing `*/5 * * * *` cloud cron is a due check. It does not fetch every
provider every five minutes. Each serialized refresh processes at most two due
providers. A Durable Object alarm, no sooner than 15 seconds later, processes
the remaining due providers in bounded batches. Persisted due times and request
counters make duplicate cron/alarm delivery idempotent with respect to reads.
No eligible work deletes the alarm; official-registry/storage failure leaves
retry to the normal cron instead of starting an alarm loop.

Every actual HTTP read must reserve its allowance durably **before** fetching.
Each provider cycle permits at most eight reads and has a 20-second cancellation
deadline. Cancellation, failure, restart, disable/re-enable and clock rollback
cannot refund or reset spent reads. The registry has its own ledger; it does
not borrow or reset the existing watchdog's budget.

| Provider | Maximum actual reads per UTC day |
| --- | ---: |
| CS / `communitysports` | 288 |
| AS / `plaviosports` | 288 |
| Each of the other five original adapters | 96 |
| Programme metadata / `reviewedtv` | 576 |

The next attempt is the slower of the demand interval and the budget floor:

- LIVE or within 30 minutes of kickoff: five minutes.
- A start in the next 24 hours: 15 minutes.
- Quiet period: four hours.
- Budget floor: `ceil(24 hours × actual cycle reads / daily allowance)`.

For example, eight CS reads require at least 40 minutes between equivalent
cycles; seven reads on a 96-read allowance require at least 105 minutes.
Activity is limited to each adapter's supported sports/competitions. One grouped
T−5-minute kickoff checkpoint may move the next background cycle earlier; its
persisted debt skips the original slot. Restart, failure, clock rollback and
disable/re-enable cannot repeat it or refund reads. This catches late listings
without promising continuous five-minute provider refresh.

Failures also receive exponential backoff, starting at five minutes and capped
at one hour, without shortening a longer budget/demand interval. Collection for
a budget-exhausted provider defers until a valid later budget day; other providers
continue. Existing facts retain only their original expiry. Rotation cursors
persist across runs. The new programme lane normally reads one fixed guide
page, or at most two when UTC and the verified selected guide timezone cross a
date boundary. Its 576-read daily cap supports that bounded active cadence;
the original seven caps and shared eight-read cycle ceiling are unchanged.

Once explicitly activated, this collection runs in Cloudflare while the Mac
is asleep and all apps are closed. It uses no local Codex schedule, AI jobs or
Codex credits. This is metadata collection, not automatic code repair or
deployment. Existing account capacity and actual runtime still require the
activation checks below; no new spending policy is implied.

## Retained facts, explicit links and unknown results

Each source observation retains a deterministic broadcast identity, provider
event/stream identifiers, resource kind, scope, title, participants, explicit
source start/end and optional competition/squad/cricket facts. It also retains
`observedAt`, `expiresAt`, verification and finite rejection reasons. The wire
contains no media URLs, request headers, credentials or tokens.

The schema separates three things:

1. Coverage per provider/scope: `available`, `partial`, `empty`, `failed` or
   `unsupported`, including original receipts and next-attempt diagnostics.
2. Observations: `event`, `channel` or `programme`, with verification `dated`,
   `undated` or `conflicting`.
3. Canonical links: `listed`, `needsVerification` or `conflicting`, with an
   exact official fingerprint and method `exact`, `test-period` or `programme`.

A partial response refreshes the IDs actually observed; it does not prove that
unseen rows disappeared. A complete accepted scope may replace that scope.
Provider failure preserves accepted sibling providers and prior observations.
An unexpired previously accepted listing may survive its own failed refresh,
using its original success/expiry receipt, solely to attempt fresh same-ID
resolution. A fresh negative, conflict, expiry or changed fixture can still
revoke it. No failure renews a fact or permits old media reuse.

Equivalent duplicate IDs in Live and sport catalogs merge. Contradictory
current identities remain conflicts. Missing dates/participants, source-time,
squad/competition/format/day conflicts and missing Test authority remain visible
diagnostics rather than false playable links. Generic channels never link to a
fixture merely because they show sports. An empty catalog is not decoded
playback failure or proof that every match lacks coverage.

Collections are capped at 1,500 records / 1 MiB; the shared state/snapshot at
4,000 records, 4,000 links and 4 MiB. Original observations may be retained for
24 hours for finite diagnostics, but their individual expiry still controls
lookup. Oversize/invalid candidates are rejected atomically; accepted records
survive and already spent requests remain charged.

## Listing lifetime and executable streams

Event/channel listing facts last at most four hours. This bridges the actual
source collection cadence; it does not grant a four-hour playable URL. Programme
facts last at most ten minutes and cannot outlive their explicit programme end.
Links also expire with the relevant official-status receipt. Network snapshots
must be fresh on first acceptance; cached snapshots preserve original receipts.

Native `StreamEventBinding` metadata has a 90-second lifetime, the discovery
positive-session cache is 60 seconds, and automatic preflight has a 90-second
cooldown. A session's own expiry, current source identity, exact binding and
transport restrictions still apply. A four-hour listing selects an advertised
identity for a **new** descriptor request; it cannot extend any of these leases.

Compatible native paths use the association as an identity constraint, then
repeat fresh provider-specific checks. CS uses its advertised ID and same-ID
metadata; AS retains its family-specific original schedule / same-ID metadata
checks; Score808 and StreamEx recheck their fresh actual source event; FS/SV
retain their existing dated catalog/meta contracts. Admitted returned sessions
must still match the original canonical request. The registry supplies no URL
and makes no decoded-video guarantee.

CNC's encoded catalog IDs can contain transport payloads. The cloud stores only
`cnc-observation:<sha256>` identities, with unresolved/undated evidence, instead
of persisting those payloads. These hashes are not executable CNC IDs. CNC's
ordinary fresh guarded native lookup remains separate; a safe cloud-to-native
executable CNC association remains pending.

## Verified early limited-overs coverage

The ordinary exact start fence remains15minutes. An optional typed schema1
`startRelation: "early-coverage"` additionally supports an ODI/T20 source event
starting more than15 and at most60minutes before its one unique accepted official
fixture. Require exact teams/squad/format, sameUTCdate, fresh current same-ID
metadata and all existing expiry/conflict/security checks. Keep both official
kickoff and source start unchanged. Late clocks, adjacent dates, Test/T10/unknown
format and ambiguous fixtures stay rejected. `matchMethod` remains `exact` for
backward schema compatibility. This does not establish actual cricket playback.

Fixture identity receipt is distinct from the publisher's last status change:
a successful current official fetch can verify identity without declaring LIVE
or renewing old status. Native LIVE/terminal authority still uses the strict
status observation. Typed temporary collector failures may retain the original
accepted verified identity for at most30minutes, never past conflicts/holds and
never by renewing its receipt or status.

## Test matches and linear programmes

The canonical Test kickoff remains the original match start. An exact whole-Test
`event` without a day qualifier may match that original UTC kickoff within the
unchanged 15-minute fence. Known ordinal, squad, date and format conflicts still
veto it. A day-qualified Test occurrence or linear programme instead requires
explicit, current official ordinal, day and whole-match end, matching source
facts and a source start inside that official interval. ICC now emits the bounded
additive `context.matchOrdinal` and `matchEndsAt` authority. Daily/programme
authority expires within ten minutes; no source moves kickoff or derives a day
from today's clock. Older receipts without the required facts remain ineligible.

The eighth adapter, `reviewedtv`, reads only TV Passport's main-US Willow station
`willow-cricket/15964`. Its explicitly selected IANA timezone, dated start and
duration establish a current Test programme on `cricket-channel:willow`, mapped
to the already reviewed TV1 channel. Only `start <= now < end` qualifies. Replays,
highlights, review shows, hidden markup, ambiguous clocks, stale facts and
overlapping programmes supply no fixture authority. The cloud never fetches a
media playlist. Historical-clock parsing proves a contract, not current playback:
the verified 30 October Test slots ended at 15:00 UTC.

Native 194 may privately join that current programme to another enabled reviewed
channel delivery while retaining both original programme and channel receipts.
Guide metadata is independent of the TV1 playback opt-in. For CS, the optional
schema 1 field `stationMarket: "US"` is emitted only from the exact main-Willow
NETWORKS/type/channel and strict three-line US-country contract. Channel identity
survives its fetched `cricket`, `live` or `networks` cohort; a cohort cannot turn
a NETWORKS channel into a fixture. Missing, UK, unknown or conflicting market
proof remains browsable but cannot grant fixture Watch. Fresh same-ID NETWORKS
catalogue, metadata and US-station proof are still required before a descriptor.
The finite lease expires with the earliest original fact, programme end or
90-second binding; neither guide nor channel alone certifies decoded playback.

Earlier official-Willow timezone probes returned identical intervals for `5.5`
and `0`; their negative programme-admission conclusion is superseded only by the
reviewed TV Passport contract above. It does not authorize other stations,
regions or Fox programmes. Foxtel's inaccessible guide was not bypassed, and a
generic Willow/Fox channel remains independently useful without identifying the
programme it carries.

## Activation and verification

The owner-approved backend gate preserves existing services:

1. Freeze/review the candidate and run the focused registry, adapter, Worker
   integration, native schema/identity and protected-input checks. Final counts
   belong in the accompanying build receipt, not this design document.
2. For a future change, advance from the deployed source identity
   `2026-10-30.match-source-association-2` and align the existing version/contract
   watchdog guard before interpreting notices. The current compatible deployment
   is recorded above. This does not activate extra email/account/alert work.
3. Preserve the deployed `broadcast-registry-v1` SQLite Durable Object migration
   and `BROADCAST_REGISTRY` binding. Apply only a separately reviewed new migration
   if a future change needs one. Preserve all existing objects, accepted snapshots,
   source settings, secrets, FPL flags and activation; do not recreate or clear state.
4. Preserve `FOTTY_BROADCAST_REGISTRY_ENABLED="1"` and the explicit reviewed
   eight-code `FOTTY_BROADCAST_REGISTRY_SOURCES` allowlist above. Confirm current
   account/runtime limits without new accounts or spending. No unknown provider is
   admitted by the general flag.
5. Verify the deployed source identity, public read-only schema, original
   receipts, bounded counters/cursors, later normal cron plus alarm continuation
   and independent provider retention. Mac-side fetch success is not edge proof.
6. Use a newly verified live fixture on free Jet iPad: normal Watch/picker,
   actual correct-programme decoded advancing video, native controls/fullscreen,
   PiP and an outage drill. PL, UCL and cricket are separate coverage gates;
   a channel-only pass does not close a fixture gate.

For a registry-specific activation failure, setting the registry flag to `0`
stops collection/reservations and removes future continuation without deleting
accepted state. Keep the new migration/binding and the old fixture services;
diagnose before re-enabling. This is a bounded containment switch, not proof
that a previous build or every provider is healthy.

Implementation owners: `broadcast-registry.mjs` (durability/scheduling),
`broadcast-registry-policy.mjs` (pure association),
`broadcast-source-adapters.mjs` (reviewed metadata), playback `index.js` /
`wrangler.toml` (wiring), and native `BroadcastRegistry.swift`,
`CatalogPlaybackIdentity.swift` / `HybridStreamProvider.swift` (fresh execution),
plus `ReviewedTVPlaylistClient.swift` and `CommunitySportsAddonClient.swift`
(programme-constrained channel delivery).
See [the current 194 receipts](../testing/fotty194-shared-watch/), the
[original registry plan](../testing/fotty191-broadcast-registry/Plan.md) and
[historical Willow probes](../testing/fotty191-broadcast-registry/willow-epg-research.json).
The initial seven-provider, cloud-OFF and staged-ICC descriptions in older
receipts are historical and superseded by this deployment; they are not current
activation instructions.


## Cricket matching repair — 1 November 2026

The optional `X-Fotty-Cricket-Matching: current-listing-v1` profile admits the
reviewed CS dynamic FanCode producer's `startBasis: current-listing` observations.
Its synthetic released clock is retained for audit, never interpreted as kickoff.
A `current-event` link needs one fresh, officially live ODI/T20 fixture with the
exact qualified pair; native resolution rechecks fresh same-ID metadata before
fetching a descriptor. Older clients receive their existing compatible profile.
No source clock, format, ordinal or official live status is invented.

Main-Willow programme parsing includes the publisher's exact ODI/T20 formats.
The station-bound current programme interval is separate from official kickoff;
its explicit match number must agree with the independently supplied ICC ordinal.
Repeat/highlight, stale, overlapping, conflicting and ambiguous records cannot
supply a match assignment. A working channel alone does not prove its programme.
Collection stays in the existing cloud registry and existing request budgets.
