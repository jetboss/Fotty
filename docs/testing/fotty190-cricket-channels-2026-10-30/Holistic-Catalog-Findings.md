# Holistic catalog correction —30October2026

Read-only review after the owner observed SA–Australia playing on Willow while
the canonical match card remained Broadcast unconfirmed. Existing189/190 work
does not fulfill a durable shared broadcast-catalog requirement.

## Confirmed gaps

1. MatchListViewModel.sourceCatalogRequests explicitly excludes channels.
   CS.catalogMatches reads sport/Live catalogs; its new channel route reads
   NETWORKS separately. No current programme-to-fixture relationship exists.
2. FixtureSourceCatalogMatch retains matchID/outcome/providerEventID, discarding
   the original broadcast observation and why a recognizable event was rejected.
   Watch independently searches again. The indexes are process-local; the
   Worker live catalog still covers three primary profiles from one family.
3. CS can treat absence in a potentially truncated initial catalog as notListed,
   although Watch has a later advertised search fallback. AS timing/schema
   rejection can also become notListed. Incomplete collection, contract drift,
   ambiguity and proven absence require distinct retained outcomes.
4. Shared matching applies a15minute kickoff fence to a multi-day Test's
   original start. CS descriptions' Test ordinal/day are not represented in
   the shared candidate identity. Widening that fence alone would be unsafe.
5. One global preflight provider cursor can starve individual fixtures: with
   four providers and two rotating fixtures, each fixture repeatedly receives
   only the same two providers. Rotation must be per exact fixture/provider,
   while preserving the global request/concurrency budgets.
6. Catalog hint, refresh, descriptor, binding and readiness clocks differ.
   Fresh exact listings can offer an honest Watch attempt, but cannot substitute
   for fresh endpoint validation or programme evidence. A newer negative result
   must veto that provider's older listing without hiding healthy siblings.

## Proposed coherent model —not implemented

Retain bounded typed provider broadcast observations before association, then
link them to canonical official events through one pure policy reused by batch
catalogs, same-ID metadata, Watch and binding renewal. Keep source/effective IDs,
event/channel/programme kind, literal dated identity facts, receipt/revision,
coverage completeness and specific conflict/uncertainty reasons. Persist only
non-secret lookup/link metadata; never persist expiring media URLs or credentials.

For Tests, separate whole-match identity from the current broadcast occurrence.
Verified format/ordinal, exact teams/squads, compatible competition, unique
official Test and source UTC inside its published start/end can identify the
whole match. A stale day label remains a programme-currentness conflict and
could indicate replay. It cannot silently become today's day or prove LIVE.
Wrong ordinal/competition/squad, outside-period date, conflicting reused ID and
ambiguous fixture remain hard vetoes. AS clock-only rows still lack a full date.

A channel-to-match link requires corroborated current programme/EPG or a
maintained explicit provider programme identity. The reviewed contracts have no
such implemented link. Observing Willow's actual programme proves this incident
but is not a repeatable automated mapping contract. Generic channel names are
not programme evidence.

## Acceptance for the full repair

Use the same accepted record for the normal match card and Watch resolver.
Exercise three fixtures/six providers to prove fair qualification, then primary
outage, independent valid broadcast, channel-programme link, Test occurrence,
wrong/replayed programme, source revocation, terminal change, restart and expiry.
Finish with real advancing native video through the normal match Watch on Jet.
Channel190's isolated delivery is not completion of these gates.
