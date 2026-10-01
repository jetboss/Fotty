# Sports fixture source-access ledger

Reviewed: **1 October 2026**. Source selection and bounded public research only;
this document does not authorize activation, new accounts/contact, subscriptions,
deployment or an app release. Runtime receipts remain in
[Sports-Fixture-Service.md](Sports-Fixture-Service.md).

## Production versus local stage

| State | Exact competition scopes | Evidence boundary |
| --- | --- | --- |
| Production, non-cricket | `premier-league`, `champions-league`, `mlb`, `nhl` | Four accepted cloud scopes; website and WNBA collection remain off. |
| Production, separate cricket owner | CPL / West Indies / ICC | Existing cricket registry and monitoring; not part of the 31-scope non-cricket manifest. |
| Local stage, non-cricket | The four above plus `la-liga`, `serie-a`, `bundesliga`, `ligue-1` | Eight eligible scopes, **not eight production-covered scopes**. The existing football-data account returned HTTP 200 for all six football codes with exact scope/window and matching zero count. This verifies transport/schema, not independent fixture completeness or deployed coverage. |
| Remaining local-stage gaps | The 23 IDs below | Deferred/unsupported is not healthy empty coverage. |

The six-league stage uses the existing documented football-data API/credential,
not the gated La Liga/Serie A/Bundesliga/Ligue 1 website routes. No new paid plan
is selected. MLS is not in that free coverage set. See
[football-data coverage](https://www.football-data.org/coverage).
The broad native consumer was previously received by owner iPad build 112;
that receipt does not qualify these new staged changes or a new install.

## Exact remaining 23 competition IDs

All existing ESPN website adapters remain `publicUndocumented` /
`deployment-review-required`. Public reachability is not a reuse grant; the
[Disney terms](https://disneytermsofuse.com/english/) require a separate source
access review. `FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED="0"` and
`FOTTY_SPORTS_WNBA_ENABLED="0"` remain mandatory for this source-only stage.

| Competition ID | Concrete blocker / next source decision |
| --- | --- |
| `wnba` | Existing league JSON returned valid Node data but HTTP 200 HTML at the Cloudflare edge. Current-year completeness and edge JSON must pass before explicit activation; no access spoofing or alternate-route bypass. [WNBA terms](https://www.wnba.com/terms-of-use) also limit regularly updated database reuse. |
| `nba` | League CDN routes are technical, undocumented candidates; current-season completeness, edge access and database reuse are unqualified. [NBA terms](https://www.nba.com/termsofuse). API-Sports access/rights/quota checks are also outstanding. |
| `nfl` | [nflreadr's schedule loader](https://nflreadr.nflverse.com/reference/load_schedules.html) uses `nfldata`, which has no verified data licence—not the separately licensed `nflverse-data` repository. Current CSV metadata is 2,182,354 bytes, exceeding the 2,000,000-byte collector bound; Eastern wall-clock times need DST conversion and scores do not establish explicit live status. [Underlying repository](https://github.com/nflverse/nfldata), [dictionary](https://nflreadr.nflverse.com/articles/dictionary_schedules.html). |
| `college-football` | Documented CFBD `/games/schedule` is promising; needs existing/new authorized credentials, current edge/window-envelope verification and agreeing FBS/FCS union. Shared free quota and public-endpoint reuse review remain open; see below. |
| `college-basketball-men` | Documented CBBD games support ISO date bounds, TBD time and statuses; current season, full Division I cohort and gender coverage are unverified. Same credentials/quota/reuse dependencies as CFBD. |
| `college-basketball-women` | CBBD women's coverage is not verified. NCAA website routes/wrappers do not establish licensed complete women's Division I coverage. [NCAA.com terms](https://www.ncaa.com/tos). |
| `mls` | [Openfootball](https://github.com/openfootball/world) has genuinely CC0 data, but inspected MLS history ends in 2025; no complete current 2026 schedule was found. Official website scraping requires separate review. [MLS terms](https://www.mlssoccer.com/legal/). |
| `atp` | Need a permitted current singles/doubles draw/order-of-play API, explicit UTC, withdrawals/status and completeness. ATP website terms restrict systematic retrieval/database construction without permission. [ATP terms](https://www.atptour.com/en/terms-and-conditions). |
| `wta` | Same match-level requirements; automated harvesting requires separate permission. [WTA terms](https://www.wtatennis.com/terms-and-conditions). |
| `pga` | Need a permitted tournament API with confirmed UTC start/status. PGA terms restrict automated copying; DataGolf's documented schedule API requires paid membership, excluded here. [PGA terms](https://www.pgatour.com/company/terms-of-use), [DataGolf access](https://datagolf.com/api-access). |
| `lpga` | Official API requires an executed licence schedule and issued key; published terms include fees. Public Swagger is not free access/reuse clearance. Tournament calendar dates alone do not confirm UTC start. [Official API/licence](https://lpga-api.azurewebsites.net/index.html). |
| `dp-world-tour` | Current official tournament dates are available, but not confirmed UTC starts. Personal website extracts do not clear a redistributed fixture database. [Schedule](https://www.europeantour.com/dpworld-tour/schedule/2026/), [terms](https://www.europeantour.com/terms-of-use). |
| `formula-1` | Jolpica is the strongest reviewed free schedule candidate; licence eligibility, attribution and schedule-only admission still need a decision. No adapter/activation is included here; see below. |
| `indycar` | Official 2026 season ended 6 September. Calendar downloads do not establish session-level UTC/status completeness or redistribution permission. Need a permitted feed and rollover coverage. [Official schedule](https://www.indycar.com/schedule/?year=2026). |
| `nascar-cup` | Official Swagger describes race/weekend sessions and `start_time_utc`; production authentication, free entitlement, bounds and reuse are unqualified. Website terms restrict automated collection without consent. [Swagger](https://feed.nascar.com/swagger/ui/index), [terms](https://www.nascar.com/ndmnetworktermsofuse?mobileFooter=0&mobileHeader=0). |
| `ufc` | Need a permitted UTC **card** feed, not one fixture per bout. UFC terms restrict automated acquisition/database reuse; UFCalendar is paid after its trial. [UFC terms](https://www.ufc.com/news/terms-use), [UFCalendar](https://www.ufcalendar.com/developers). |
| `rugby-prem` | No cleared documented public API found; official fixture page is not an ingestion/reuse contract. Need current UTC match feed, statuses and bounded completeness. [Official fixtures](https://www.premiershiprugby.com/fixtures-results/). |
| `rugby-urc` | No cleared documented public API found. Approved media-centre access does not clear general fixture ingestion. [Official site](https://www.unitedrugby.com/), [media terms](https://www.unitedrugby.com/media-centre-terms-of-service/). |
| `rugby-top14` | LNR calendar/results terms grant consultation/private-copy access, not a fixture-feed licence. Need separate permitted current UTC coverage. [LNR terms](https://top14.lnr.fr/page/cgu). |
| `nrl` | Official draw requires prior written approval for reproduction; parser-visible local times are not a verified UTC contract. [Official draw](https://www.nrl.com/draw). |
| `afl` | Squiggle is a documented free candidate; truthful operator identification, bounded current sample/completeness and compliant polling remain open. See below. |
| `boxing` | Unsupported: no verified complete permitted multi-promoter UTC card feed found. BoxRec restricts automated collection/republication; estimated bout times cannot replace card starts. [BoxRec terms](https://boxrec.com/en/policies/terms_conditions/public). |
| `pdc` | Unsupported: local `startDate`/`startTime` has no verified timezone contract; bounded date filtering, match/session grain and explicit live/status semantics remain unresolved. Bounded current official-calendar research did not remove these gaps. [PDC calendar](https://www.pdc.tv/calendar/). |

## Free candidates worth a separate admission gate

**Formula 1 — Jolpica.** Its code is Apache-2.0, but its API **data** has
explicit CC BY-NC-SA 4.0 terms: noncommercial eligibility and attribution/share-
alike compliance must be resolved; commercial permission is not assumed.
No key is needed; documented limits are 4 requests/second and 500/hour, with an
identifying application User-Agent. Pagination has `offset`/`total`, maximum
100 rows; optional absent UTC session times stay pending. A bounded 2026 query
returned 23 races matching its total, including five UTC sessions on 2–4 October.
The unusual Bahrain-in-Malaysia/Sepang identity is corroborated by the
[current official race page](https://www.formula1.com/en/racing/2026/bahrain).
Admit scheduled sessions only; the schedule does not explicitly establish
live/final/cancelled/postponed state. [Data terms](https://github.com/jolpica/jolpica-f1/blob/main/TERMS.md),
[race schema](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/races.md),
[rate limits](https://github.com/jolpica/jolpica-f1/blob/main/docs/rate_limits.md).

**AFL — Squiggle.** [Official API documentation](https://api.squiggle.com.au/)
permits commercial use and documents match IDs, epoch `unixtime`, `live` and
`complete`. It requires a truthful bot User-Agent/contact email, backend caching
and responsible requests; repeated identical Standard API polling is not its
persistent SSE service. No fixture request was made without operator contact
identification. Year/round/game filters exist, but no documented date-window
pagination/total envelope: verify complete bounded selection and cancellation/
replacement behavior. Men's 2026 finals ended 26 September; this does not prove
a healthy empty current API window or clear AFLW/2027 coverage.

OpenF1 publishes future UTC sessions/cancellation flags, but hosted-data licence
scope and completeness need review, and real-time access is paid. Its current
repository licence is CC BY-NC-SA 4.0, not a separate unrestricted data grant.
Do not infer live from planned session start/end. [Docs](https://openf1.org/docs/),
[licence](https://github.com/br-g/openf1/blob/main/LICENSE).

## Other access limits and actionable choices

- [CFBD](https://api.collegefootballdata.com/api/games) /
  [CBBD](https://api.collegebasketballdata.com/api/games) share a documented
  [1,000-call/month free quota](https://collegefootballdata.com/api-tiers).
  Their [terms](https://collegefootballdata.com/terms) permit app display/cache/
  scheduled polling but prohibit raw public mirrors/proxies/substitute APIs;
  review Fotty's public fixture endpoint before selecting them.
- [API-Sports](https://api-sports.io/sports/nba) documents 100 free calls/day;
  unchanged five-minute hot polling can exceed that. Its
  [terms](https://api-sports.io/terms) do not supply data-publication rights;
  free current-season access is not verified.
- [TheSportsDB terms](https://www.thesportsdb.com/docs_terms_of_use.php) require
  paid access for published App Store apps. Free
  [response caps](https://www.thesportsdb.com/docs_api_guide) also prevent complete
  window claims; no paid service or exception is selected.

## Bounded paid-provider research, 1 October

No account, key, fixture API call, subscription or publisher contact was made.
None of these providers is qualified to close all 23 gaps. Published sport or
league names are candidates, not current complete competition receipts.

| Provider | Published price / quota | Decision boundary |
| --- | --- | --- |
| [TheSportsDB](https://www.thesportsdb.com/docs_pricing.php?billing=monthly) | Single Developer $9/month, 100 requests/minute; Small Business $20/month, 120/minute. | Lowest-cost broad evaluation candidate. Its catalog names counterparts for the 23 lanes, but exact NCAA divisions, current DP World identity, tennis match/doubles grain, motorsport sessions, PDC sessions and complete current windows remain unverified. |
| [API-Sports](https://api-sports.io/sports/rugby) | Rugby, NFL/NCAA and AFL product tables show 15.00/month; MMA shows 10.00/month, with 7,500 daily / 300 minute Pro calls. These are separate products, not an all-sports bundle. | Useful partial coverage. No inspected products established tennis, golf, darts, boxing, IndyCar or NASCAR coverage. [Terms](https://api-sports.io/terms) explicitly do not grant publication rights; paid API access alone does not remove that requirement. |
| [Goalserve](https://www.goalserve.com/contact-us/sport-data-feeds/full-package-api/prices) | All-sports package $800 for one month, $3,550 for six, $5,100 for twelve. Request quota is unspecified on the inspected pricing page. | Substantially more expensive; this is not a schedule-only quote. Exact competitions/sessions, IndyCar, cache retention and normalized backend distribution still require qualification. |

Prices above preserve the sites' displayed symbols; inspected pages did not
establish an ISO billing currency. Confirm currency and the appropriate plan
before approving any budget. TheSportsDB's paid API terms contemplate app/service
use with attribution, but retain third-party rights and prohibit API resale
without permission. Its publicly accessible normalized Fotty endpoint needs a
separate use-case review; a subscription is not a blanket artwork or data-rights
grant. Premium query caps and missing pagination/count guarantees remain a
completeness issue, not solved by payment.

Recommendation: evaluate TheSportsDB's current fixture contract and exact lanes
first if the owner chooses a small paid-data budget, before any purchase. Retain
free gaps otherwise. Samples must prove scope/grain, confirmed UTC, statuses,
bounded complete selection, correction retention and edge-runtime behavior;
date-only or timezone-less rows stay pending. A budget/source choice is still
required; this research does not authorize it.

Next choices are scoped, not an all-sport promise:

1. Select F1 and/or AFL for a separate permission, operator, completeness and
   edge-runtime gate; then implement and verify source-only changes before any
   explicit activation request.
2. Review each existing ESPN website lane separately. General feature approval
   does not lift the website gate or authorize access bypass.
3. If free permitted coverage is insufficient, obtain an owner choice of a
   licensed feed, budget, credentials and operator/contact authority. Do not
   create accounts, contact publishers or buy access from this ledger alone.

Source-code licences never establish upstream fixture-data rights. Every new
feed still needs exact competition/grain, confirmed UTC, explicit status,
bounded complete selection and correction tests. Date-only rows stay pending;
do not fabricate midnight starts, opposing teams or live states.
