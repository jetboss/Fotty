# Listings-first Watch — agreed design (22 Nov 2026)

Owner-approved direction, reviewed with Codex. Replaces the fixture-first
model in which an official, verified fixture was the only path to Watch.

## Why

Until 27 Oct 2026 Fotty used the Streamed/StreamEx shared catalog as its one
list of matches, times and streams; a listing made a match watchable. Problems
in that period were almost all playback. Schedule problems began when
official-fixture admission arrived (cricket 30 Sep, sports 1 Oct) and, after
StreamEx closed (removed 9 Nov: 2b9173f, 6766c06, 74a3a2c), official
verification became the only route to Watch. Every schedule wobble then hid
Watch: "No stream listed", "Start unconfirmed", blank leagues (21–22 Nov), and
international cricket's lane failing 10,494 times since 3 Oct.

StreamEx's website is back (streamex.hn) but its catalog API is not (checked
22 Nov). If it returns it is one more listing source, never the only one.

## Scope

Football, cricket and basketball (NBA). Other sports are not built for.

## The model

- **Listings decide which matches appear and get Watch.** Sources: Highfly,
  PenguPlay, Plavio, Flix, CNC, Community Sports (all addon catalogs), plus
  StreamEx if its catalog returns. One fresh, identifiable listing from an
  enabled source is enough to offer Watch, even during a schedule outage.
- **Official data only enriches:** confirmed kickoff, LIVE, score, badges,
  reminders, terminal state (football-data, ESPN, FPL, ICC, CPL, ESPN NBA).
  A failed schedule read never closes Watch; only an exact finished or
  cancelled fact does.
- **Player safety stays:** ranking, participant/squad corroboration, same-ID
  metadata checks, query-preserving renewal, PlaybackAttempt fences (owner
  rules). Reason: build 335 played basketball for Belarus–Albania.

## Merging listings (the hard part)

StreamEx supplied one shared ID, start and source set. Fotty now does that:

- Each match gets a stable Fotty ID and keeps every contributing
  `(provider, event ID)`.
- Merge only on a unique match across sport, normalized participants,
  compatible competition and squad, and dated start. Cricket also needs format
  and sometimes match ordinal or Test day. Distinguish coverage start from
  kickoff. Generic basketball rows need NBA evidence.
- Ambiguous rows stay separate. Channel-style rows stay in TV.
- Existing pieces to reuse, none sufficient alone:
  `AnalyticalDataEngine.deduplicateMatches` (exact starts, keeps first ID),
  `CatalogPlaybackIdentity` (dated ±15 min playback match),
  `SportsFixtureCatalog.merging` (official projections), Score808's dated
  calendar parser.
- Source gaps to close first: Highfly rows are often undated and borrow the
  official kickoff; Highfly and PenguPlay bulk checks return
  `needsVerification`; CNC football requires a verified fixture. Each needs
  its own dated evidence to carry a match through an outage.

## Where it runs

- One scheduled job (the same job planned to replace the Worker's Durable
  Objects) reads **public** catalogs, merges them and publishes one timestamped
  static snapshot, polling listings even when the official schedule is empty.
  Each source is cached separately with its own expiry.
- The phone filters by the sources the user enabled and merges **private
  account sources on the device**. Account links, headers and stream
  descriptors never leave the device.

## What the user sees

- Listing-only match: **"Listed · coverage from {source}"** with Watch.
- **LIVE** only when confirmed in play *and* watchable (avoids the 24 Aug
  "LIVE but unplayable" problem).
- Watch resolves the exact listing afresh on tap.
- Reminders need a positive kickoff confirmation; existing reminders survive
  outages and move on confirmed corrections.
- Default (owner to confirm): official fixtures with no listing stay visible in
  Schedule and Search for planning and reminders, without Watch.

## TV channels and the broadcast registry

Keep the official fixture ID as an alias on the merged match so an exact,
current programme assignment can still add a TV route. Standalone stations
stay browsable. A channel name alone never identifies a match.

## Phases

1. **Shadow merge.** Build the listing merge; run it beside today's path and
   log what it would show, changing nothing for users.
2. **Pilot on Jet.** Listing-only Watch on device behind a switch.
3. **Retire the old gate.** Remove accepted-fixture enumeration,
   `OptionalSourceLookupPolicy`'s official-fixture prerequisite and schedule
   holds that suppress listed Watch. Keep validation for confirmed times,
   scores, terminal facts and TV assignments.
4. **Server consolidation.** The scheduled job publishes the listing snapshot
   and the fixture files; retire the Worker's request-time assembly, duplicated
   hold logic and Durable Objects once the static feeds serve every consumer.
   Keep public FPL scores and ESPN NBA enrichment.

## Acceptance test

Ten fixtures per sport (football, cricket, NBA) with the official feeds
disconnected: every fresh, eligible listing stays visible and actionable;
90 seconds of the correct programme observed on each successful play; every
failed attempt recorded. Required: zero false merges, zero wrong programmes,
zero unconfirmed reminders, and a correct-play rate at least equal to today's
Watch path on the same fixtures.

## Owner decisions

- Approved 22 Nov 2026: listing-only Watch.
- Open: whether unlisted official fixtures stay in Schedule/Search (default
  above: yes, without Watch).
- Unchanged and still the owner's: player ranking/corroboration/fences,
  spending, feed rights, device privacy, acceptable live-score lag.
