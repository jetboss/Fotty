# Carabao Cup fixture source

Status: owner approved focused activation on 28 October 2026; protected CI and production verification pending.
The six existing football-data scopes and separate cricket registries are unchanged.

The competition contract is `carabao-cup` / `Carabao Cup`; the isolated source group
is `efl-carabao-cup`. The adapter remains inactive when its dedicated `FOTTY_SPORTS_EFL_ENABLED` flag is absent or `0`; the approved production configuration sets it to `1`.
General fixture activation and `FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED` do not enable
it. This does not activate ESPN, WNBA or another website source.

## Reviewed primary source

The [official EFL competition page](https://www.efl.com/competitions/carabao-cup/)
links to its Match Hub; the current client redirects that route to Match Centre.
The shipped EFL Match Centre client advertises:

`https://multi-club-matches.webapi.gc.eflservices.co.uk/v2/matches`

Its recurring request uses `competitionID=2`, `seasonID=2026`, `page.size=100`,
and explicit UTC `from` / `to` dates. In EFL's own competition selector, `2` is
Carabao Cup and `10` is Championship. Football-data's `ELC` code is not this Cup.
The adapter uses the current July–June season and the existing bounded fixture
window. It does not hardcode a fixture or infer competition from participants.

Fresh metadata received at 2026-10-28T20:12:35Z returned JSON with eight rows and
`meta.totalCount=meta.count=8`. Actual publisher match `g2687775` was Liverpool–
Chelsea, explicit UTC kickoff 2026-10-28T20:00:00Z and `matchPeriod=FirstHalf`.
The other rows covered the same current round, including completed, in-progress
and upcoming ties. This proves reachable structured schedule/status metadata;
it does not prove stream availability, playback or a published service SLA.

## Admission and retention

- Source IDs are actual EFL match IDs under `sports-fixture:carabao-cup:`.
  The response supplies explicit whole team names, not typed team IDs; participant
  IDs are namespaced whole-name keys. Crests never establish fixture identity.
- Exact source origin/path, returned self-link query, competition, window, counts,
  row type, match ID and UTC calendar must agree. A truncated/full-capacity page,
  redirect, unknown period or changed scope fails collection.
- `kickOffDateUTC` is explicitly the publisher's UTC field. No local offset is
  inferred. Provisional/TBC teams are pending metadata, not confirmed fixtures.
- LIVE and terminal states come only from explicit `matchPeriod`, never elapsed
  kickoff. HTTP Date/Age bound the received artifact; they are not per-ball or
  per-event update timestamps. Current live evidence has the existing 30-minute
  bound. Unknown source periods fail closed rather than being guessed.
- The existing durable registry owns accepted snapshots, backoff and partial
  retention. Collection/admission failure preserves earlier facts and their old
  receipt as held. It does not erase the accepted snapshot or renew LIVE.

Before activation, review the focused source patch, run the source/registry/worker
tests, then verify the exact deployed version and warm the new dedicated source.
The production receipt must show this Cup scope covered and the actual current
fixture; local code, an HTTP response or a passing unit test is not activation.
