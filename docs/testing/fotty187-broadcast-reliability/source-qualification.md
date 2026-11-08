> Historical 29 October qualification receipt. For current November1 source code and acceptance, read `docs/testing/fotty-liverpool-watch-2026-11-01/README.md` and `docs/notebooklm/Current-State.md`. AS now contains the dated publisher join; November AS403 and fresh FS discovery/delivery failures are separate evidence. Preserve the original rows below; do not use them as current source-contract declarations.

# Step 3 — independent source qualification preparation

29 October 2026. Read-only preparation for the approved broadcast-reliability
batch. This is a source/metadata receipt and pending-gate plan, not a playback
qualification. No app edits, settings changes, device inspection/input, media
fetch, builds, publication or deployment occurred. Phone, FPL, multi-stream and
TestFlight remain untouched.

## Current exact fixture and honest live eligibility

- **Everton–Newcastle United, men's senior Carabao Cup, 29 October 19:45 UTC.**
  The already-admitted EFL Match Centre endpoint returned HTTP 200, one of one
  scoped rows, competition ID 2, explicit `FirstHalf`, `TBC: null`, and exact
  `kickOffDateUTC: 2026-10-29 19:45:00`. Response Date was **20:23:11 UTC**;
  Age was absent. This corroborates the fixture and publisher-reported current
  phase. It does not establish a stream or decoded programme.
- CS's freshly fetched football catalog at **20:21:27 UTC** contains that pair,
  England–League Cup, with explicit `released: 2026-10-29T19:45:00.000Z` and a
  default-video identity equal to its catalog identity. Its LIVE text alone was
  not used as authority. This is the strongest current qualification fixture;
  it is **Cup, not Premier League or UEFA Champions League**.
- The admitted ESPN PL day scoreboard returned HTTP 200 with zero events for
  29 October. No live PL fixture was corroborated in this bounded check. The
  next UCL window retained in the earlier audit is 3–4 November; reverify the
  authoritative fixture/status at execution rather than treating that old
  schedule receipt as current live evidence.
- Fresh admitted ICC schedule metadata at **20:21:27 UTC** was complete, 59/59.
  South Africa–Australia, third Test (27 October 08:30 UTC), explicitly reports
  **Stumps, Day 3**; Bangladesh–West Indies, first Test (28 October 03:30 UTC),
  explicitly reports **Stumps, Day 2**. Both have `is_match_on_break: true` and
  `is_match_ended: false`. They are ongoing fixtures, not current active-play
  candidates. AS's Test Day 1-only contract cannot be repinned to later days.

## Redacted source matrix

| Reviewed lane | Current contract / retained proof | Independence evidence | Exact remaining gate |
| --- | --- | --- | --- |
| Primary, mirror, backup browse family | The separate outage receipt records primary/mirror converging on the same canonical catalog, with an incompatible scalar response, and backup redirecting to its root. | Primary/mirror are one demonstrated failure domain. Three labels do not establish three supplies. | A maintained, dated, exact publisher catalog/source contract; never trust a redirected host or HTTP 200 alone. Independent fixture lookup must remain usable meanwhile. |
| **CS 3.1.3** | Manifest and current football catalog HTTP 200. Exact current Cup row has explicit UTC release and matching catalog/default-video identity. Prior 28 October CS2 Cup playback is historical and shorter than this campaign's 90-second qualification gate. | Existing reviewed source hints distinguish some upstream families; no current descriptors were requested here. Overall ancestry and independence from AS/Flix remain unproven. | Normal real-adapter exact-match discovery, current compatible descriptor, guarded delivery, correct programme, 90-second decoded progression, then ordinary picker/native controls/fullscreen/PiP. PL/UCL/cricket need their own real fixtures. |
| **AS 1.9.98** | Manifest HTTP 200; dedicated football catalog 142 rows. Current Cup appears in two distinct advertised families, DLHD and Roxie. Historical Villa–City native canary passed 90 seconds on 24 October; that does not qualify today's contract or all coverage. | Current family names suggest different catalog ancestors, not proven independent media origins. Earlier AS Streamed-derived linkage is historical; current row prefixes changed. | **Date authority is currently missing** in the inspected DLHD catalog and exact meta. Obtain a reviewed full-date publisher linkage/contract before requesting streams. Do not derive the date from fetch time, official kickoff alone, opaque ID or UK clock. |
| AS cricket | Current catalog HTTP 200, 15 rows; inspected South Africa–Australia row says third Test Day 2 and only an 08:00 UK clock. Current ICC says Stumps Day 3. Other rows include Sixes, outside the reviewed T20I/Test Day 1 contract. | Not proven independent of football/CS delivery infrastructure. | Supported exact format/ordinal/day plus full UTC corroboration, then new descriptor and complete native gate. No generic cricket channel or later Test day substitution. |
| **Flix Free 1.0.0 / FS** | Manifest HTTP 200. All three reviewed soccer catalog pages returned **503** at 20:21 UTC. Historical Lazio device manifests returned 502/zero decoded frames on 24 October. | Upstream independence versus CS/Daddy was never established. | Current catalog recovery and exact dated fixture first; current descriptor/guarded native programme gate afterwards. Today's failure is catalog-stage, not a newly observed playback failure or permanent rejection. |
| **CNC / LS** | Existing native admission is NHL-only and exact reviewed delivery/header contract. The accepted NHL sample is historical; football/cricket metadata and incompatible or unreviewed deliveries in the earlier audit remain separate. No CNC request was repeated. | A different wrapper/host does not prove independent origin; target-sport independence unproven. | A reviewed compatible football/cricket delivery contract and target-sport adapter gate, followed by complete native qualification. Do not silently enable a sport/host or retry known HTTP/DRM/account limitations. |
| **StreamViX / SV** | Staged, default OFF. Requires explicit original GMT, date/DST-aware Rome corroboration, advertised ID, catalog/meta agreement and unexpired delivery. No new SV request was made. | Its original schedule is Daddy-derived and therefore overlaps an existing CS family; it is not proven additional independent supply. | A current exact PL/UCL fixture with all existing timing/identity gates and compatible fresh descriptor, then full native qualification. Empty-token/expired/unsupported contracts remain rejected. |
| Score808 | Existing dated-calendar lookup is independent of the master listing gate. Prior 28 October source visibility versus 403 HLS is historical; no new Score808 request or playback was performed here. | A separate discovery website is known; underlying media independence from other lanes is unproven. | Current exact dated listing, compatible delivery and full normal-app native/programme test; site reachability does not qualify a stream. |

No currently inspected lane establishes two independently qualified supplies for
all PL, UCL and supported cricket. This is a qualification gap, not evidence that
every lane or every stream fails.

## Concrete AS drift and safe repair boundary

The current full-team DLHD catalog row has `type: tv`, `genres: [Football]`, and
description `Starts 19:45 (UK time) · 28 channels`. Its exact advertised meta
returned HTTP 200 / 235 bytes at **20:23:45 UTC**. The literal meta ID matches
the catalog ID; its only fields are `id`, `type`, `name`, `genres`, `description`.
The description is `Starts 19:45 (UK time)`. There is no calendar date, UTC
timestamp, `released`, `videos`, `behaviorHints` or embedded stream authority.

The second same-pair Roxie catalog entry says
`Starts October 29, 2026 12:45 PM (site time) · 2 channels`; its site timezone is
not corroborated and its metadata was not requested. Neither entry uses the
old reviewed Streamed-derived ID family. Different IDs/families are not
automatically conflicting fixtures, but neither may borrow the other's date or
an assumed timezone.

Current native AS admission expects the earlier `Sports` genre plus explicit
dated UTC envelope or the reviewed Streamed/LIVE envelope with exact advertised
metadata corroboration. Therefore the new rows are rejected before playback.
Merely accepting `Football`, stripping the competition prefix, or treating
today's EFL date plus a clock-only row as source date authority would leave the
actual missing-date issue unresolved.

The source-local next step is to establish a maintained **explicit dated**
publisher linkage for the newly advertised family, if the provider exposes one,
with catalog/meta/advertised-ID and pair/squad/competition agreement. Otherwise
retain this family as incompatible/pending publisher repair, keep CS/manual
lookup reachable, and report the source contract stage accurately. No broader
matching, date, timezone or transport exception is proposed.

## Execution gate once steps 1–2 are ready

1. Refresh the exact official Cup status and CS binding immediately before any
   physical test. Retain explicit source failure/empty/conflict distinctions;
   do not silently replace an expired fixture pin with another programme.
2. Through the real adapter, request only the exact advertised current source
   descriptor. Check its existing supported TLS/origin/header/redirect/expiry
   contract before media. A rejected descriptor is not a decoder failure.
3. Root inspects Jet availability. Once free and within the approved Jet gate,
   select the existing match's ordinary source picker. Observe the correct
   programme contemporaneously and require 90 seconds of advancing decoded
   frames, then pause/resume, source selection, native fullscreen and PiP.
   Preserve the playing owner/session and do not touch the phone/FPL/multi.
4. Exercise a broken primary with a verified working independent alternative;
   maintain correct source attribution and meaningful availability during
   catalog refresh. Names/URLs/HTTP status alone cannot close independence or
   programme gates.
5. Record Cup evidence as Cup evidence. Required PL, men's UCL and supported
   cricket remain pending their independently current source/programme windows.
   Do not enable an unqualified lane or call a skipped/unavailable gate passed.

## Request and privacy receipt

Sixteen bounded JSON metadata requests total: two existing Worker snapshots;
three admitted manifests; one ESPN PL day schedule; one admitted ICC schedule;
AS football twice and cricket once; one CS football catalog; three reviewed
Flix soccer pages; one admitted EFL schedule; and one exact advertised AS meta.
Manual redirects, 12-second per-request deadlines and existing response-size
bounds were used. Responses remained in memory; no raw payload, opaque provider
identifier, media URL/token, header credential or private device data is saved.
No media playlist/segment/key, account, challenge or payment route was requested.

See the [outage diagnosis](../fotty25-remaining-2026-10-29/Broadcast-Failure-2026-10-29.md)
and [earlier source audit](../../audit/Fotty-New-Sports-Sources-2026-10-23.md).
