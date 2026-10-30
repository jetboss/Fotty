## 30 October association repair

The registry joins all reviewed source families to accepted official fixtures.
Exact whole-Test listings use the unchanged original-start fence; day-qualified
Test and linear programme joins require current official ordinal/day/end and a
10-minute authority expiry. ICC now emits that bounded additive context.

AS uses the original explicitly dated soccer section despite decorative emoji,
and compares the same advertised metadata clock rather than a display channel
count. CS decorative status prefixes do not change team identity. FS retains
literal cricket format/ordinal/day facts. Genuine dates, squads and Test-day
conflicts remain rejected.

The eighth metadata lane, `reviewedtv`, is fixed to TV Passport's main Willow
station `willow-cricket/15964`. A selected IANA timezone and explicit dated
start/duration identify a current Test programme; main Willow is mapped to the
already reviewed TV1 channel. Review, highlights, replay, hidden markup,
ambiguous clocks and stale/overlapping intervals provide no fixture authority.
The cloud never fetches a media playlist or retains delivery URLs. Its new
metadata-only cap is 576 actual reads/day, with one guide read normally and at
most two across the verified timezone/date boundary. Existing seven budgets,
shared eight-read cycle ceiling, durable records and activation flags remain.

Native clients opt into the eighth lane with the exact capability header
`X-Fotty-Broadcast-Capabilities: reviewedtv-programme-v1`. Default schema1 reads
retain the seven-family compatibility projection and original timestamps.
Both profiles are cache-separated. This prevents a new lane from invalidating
older strict native snapshots.

A reachable Willow channel is independent of a current programme association.
The 30 October guide's verified Test slots ended at 15:00 UTC; parsing those
slots with an injected historical clock proves the contract, not current live
playback. A current day-qualified source still needs matching official facts.

# Shared broadcast registry

Owner approved activation on30October2026. This source sets activation ON for
the reviewed seven-provider registry. Deployment and live acceptance require
separate receipts; an enabled configuration is not proof that a stream plays.

## Ownership and data flow

The existing playback Worker owns a new `BroadcastRegistry` Durable Object,
named `shared-broadcast-registry-v1`. It reads accepted Sports and Cricket
registry snapshots, collects bounded metadata from the seven reviewed source
adapters, and retains explicit source observations and canonical fixture links.
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
`plaviosports`, `cncsports`, `flixstreams` and `streamvix`. These are seven
reviewed adapter identities, not seven proven independent working suppliers.
In particular, the StreamEx primary/mirror/backup profiles remain one family.
Collection on the server does not enable a provider on anyone's device.
`BroadcastRegistryClient` filters lookup through current local source choices;
resolution rechecks enablement and the exact current fixture.

`GET /api/live/broadcasts` returns schema 1 metadata with a 30-second HTTP cache
directive. Query parameters are rejected. Public requests cannot trigger
collection; POST is rejected. While the flag, binding or allowlist is invalid,
the endpoint returns unavailable/pending rather than an invented empty catalog.
Native metadata refresh is bounded to one attempt per five minutes, with
accepted-cache fallback and original receipt times preserved.

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
| Each of the other five adapters | 96 |

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
persist across runs.

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

## Test matches and linear programmes

The canonical Test kickoff remains the original match start. A daily source
occurrence may associate only with explicit, fresh official Test ordinal, day
and whole-match end, matching source format/ordinal/day and an explicit source
UTC start inside that official interval. The implementation does not derive a
daily date from today's clock, shift the original kickoff or reinterpret stale
Day 3 as Day 4. The additive ICC `context.matchOrdinal` and `matchEndsAt` contract
is staged; deployed receipts lacking those fields cannot qualify this gate.

Canonical Willow and Fox channel inventory is useful independently. It is not
programme association. The bounded official Willow investigation found dated
programme/session structure but no verified timezone/absolute UTC contract:
requests with timezone `5.5` and `0` returned identical intervals. Distributor
channel metadata supplied no station/timezone authority. No Willow programme
adapter or fixture links are activated. Foxtel's inaccessible guide was not
bypassed. A publisher-supported UTC interval, exact linear channel and current
programme/day/ordinal remain prerequisites.

## Activation and verification

The owner-approved backend gate preserves existing services:

1. Freeze/review the candidate and run the focused registry, adapter, Worker
   integration, native schema/identity and protected-input checks. Final counts
   belong in the accompanying build receipt, not this design document.
2. Bump the playback source version from the current source identity
   `2026-10-29.broadcast-catalog-1`; align the existing version/contract watchdog
   compatibility guard before interpreting new notices. This does not activate
   extra email/account/alert work.
3. Apply the additive `broadcast-registry-v1` SQLite Durable Object migration
   and `BROADCAST_REGISTRY` binding. Preserve all existing Durable Objects,
   accepted snapshots, source settings, secrets, FPL flags and other activation
   flags. Do not recreate or clear existing state.
4. Set `FOTTY_BROADCAST_REGISTRY_ENABLED="1"` with the explicit reviewed seven-code
   `FOTTY_BROADCAST_REGISTRY_SOURCES` allowlist. Confirm existing account/runtime
   limits without enabling new accounts or spending. No unknown provider is
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
`CatalogPlaybackIdentity.swift` / `HybridStreamProvider.swift` (fresh execution).
See [the candidate plan](../testing/fotty191-broadcast-registry/Plan.md) and
[Willow evidence](../testing/fotty191-broadcast-registry/willow-epg-research.json).
