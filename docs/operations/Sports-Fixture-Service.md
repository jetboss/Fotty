# Automatic sports fixtures

Status, 1 October 2026: the cleared cloud subset is deployed and its hosted
monitor is healthy. Six football leagues, MLB and NHL have accepted production receipts.
WNBA is explicitly deferred after a verified Cloudflare access failure.
Cricket retains its existing registry. Website feeds stay disabled; no
TestFlight, new subscription or paid-policy change is authorized.
The six-league football expansion and cricket conflict isolation are now deployed
through protected PR35; source `2026-10-01.cricket-corrections-1` / PR36 now
preserves that coverage/configuration and recovers the verified ICC corrections.
Current hosted sports monitor36916809058 passes. See the historical receipt below
and `Cricket-Fixture-Service.md` for the superseding Worker identity/recovery.
This backend PR does not reconcile the older remote native app with the locally
qualified consumer. The owner iPad gate uses a separate immutable source receipt.

## Coverage is explicit, not a promise of every event

The deployed manifest defines 26 source groups and 31 competition scopes. Of these,
24 groups have bounded adapters; boxing and PDC darts remain unsupported.
Production covers six European leagues through the existing football-data group,
MLB and NHL: eight accepted competition scopes, with 23 deferred/unsupported
source gaps. Successful empty receipts qualify transport/schema in this window,
not independent proof of every league's fixture completeness.
Cricket retains its separate CPL / West Indies / ICC integration and monitor.

| Lane | Staged competitions | Source boundary |
| --- | --- | --- |
| Football | PL, Champions League, La Liga, Serie A, Bundesliga, Ligue 1, MLS | Deployed six-league football-data bulk adapter uses the existing credential; MLS remains a gated website adapter. |
| Baseball / hockey | MLB, NHL | League-owned structured schedule routes. |
| Basketball | WNBA, NBA, men's/women's NCAA Division I | WNBA cloud access deferred; NBA/NCAA website adapters gated. |
| American football | NFL, NCAA FBS/FCS | Gated website adapters; agreeing interdivision duplicates are unioned, conflicts rejected. |
| Tennis | ATP, WTA | Gated per-day feeds, with explicit tour/gender checks; doubles retain two sides, not fabricated home/away teams. |
| Golf | PGA, LPGA, DP World Tour | Gated tournament feeds; unconfirmed start times are pending, not reminders. |
| Motorsport | Formula 1, IndyCar, NASCAR Cup | Gated typed sessions/races, not fake opposing teams. |
| Fight / rugby / AFL | UFC cards, Premiership, URC, Top 14, NRL, AFL | Gated structured feeds; boxing is not claimed covered. |
| Darts | PDC | Not admitted: published date/time lacks verified timezone and the bulk feed is not bounded to the required window. |

Public accessibility is not an API licence. ESPN adapters are marked
`publicUndocumented` / `deployment-review-required`. The linked
[Disney terms](https://disneytermsofuse.com/english/) restrict automated
extraction; these adapters must not be activated merely because the owner
approved the general feature. Resolve source access or substitute an appropriate
feed first. League-owned routes are technical candidates, not a claim of
unrestricted commercial reuse. No new paid data service has been selected.

## Durable ownership and scheduling

`sports-fixture-sources.mjs` and `sports-fixture-event-sources.mjs` collect source
facts. `sports-fixture-policy.mjs` admits complete, explicitly timed fixtures.
`sports-fixture-registry.mjs` owns one Durable Object per source group, named
`shared-sports-fixtures-v1:<source-id>`; one sport's failure cannot erase another.

The existing five-minute Worker cron checks persisted due times: collect every
five minutes when live/imminent, 15 minutes within 24 hours, four hours when
quiet, and retry a failed source after five minutes. A cold API GET returns
accepted state and schedules bounded collection instead of making the user
wait for every upstream scrape. `/api/sports/fixtures` has a 12-second aggregate
deadline and 1.5-second per-registry read deadline. Source collectors have
12-second deadlines, page/body/request limits and complete-envelope checks.

Snapshots are at most 2 MiB / 3,000 rows and preserve per-competition receipts.
Ordinary fixtures cover the previous UTC day and seven forward UTC days.
Explicitly live non-match events can retain a start up to seven days earlier.
An old live receipt cannot become healthy simply because the kickoff ages out
of the hot polling interval. Content revisions exclude receipt-only changes.
WNBA full-season data must identify the current UTC year. At rollover, an old
year remains unavailable until the new feed is published/reviewed; a freshly
downloaded previous season cannot prove healthy empty current coverage.

Missing previously accepted active rows, conflicting participant/time changes,
terminal status rollback and future live/final claims fail admission. Identity,
time and live-to-scheduled corrections require the same observation again after
at least four minutes. Confirmed correction receipts persist so an offline
native client can accept them later. Failed refreshes retain the original
accepted facts and original timestamps; partial is not a healthy empty league.

## Native consumer

`SportsFixtureCatalog.swift` validates/caches responses and merges into the
shared `MatchListViewModel`. Home, Search, Matchday and saved reminders therefore
use the same accepted schedule facts. Optional metadata keeps old caches
decodable. Unavailable/older/conflicting lanes retain accepted data independently.
Explicit live status expires after 30 minutes; timestamps never imply live.

Cricket's dedicated authority is unchanged. Football's existing score owner is
unchanged. Current provider descriptors attach only with explicit competition,
exact participants/squad and kickoff within 15 minutes. Tournament/session/card
rows keep typed titles and never invent a second team or infer a stream from a
generic channel. Unconfirmed teams/times cannot create a countdown or reminder.
Terminal/corrected saved fixtures keep their stable identity for rescheduling.

One native update is required to introduce this consumer. After cloud activation
and that installation, routine admitted fixture/status corrections do not need
an app rebuild. Publisher schema/access changes can still require adapter work;
no automation guarantees a publisher will never omit or correct a fixture.

## Local repair follow-up (6 October 2026; source-only)

This follow-up is staged, not the deployed service described above. No source
activation, publication, deployment, device installation or TestFlight release
has occurred in this repair pass.

- Schema1 accepts optional `source.verification: "verified" | "held"`; legacy
  absent markers remain valid, null/unknown values do not. Held rows retain
  their original facts and source receipt; affected competition coverage stays
  unavailable. Unaffected rows/competitions can advance independently. Whole
  source schema/scope/transport failure still holds all its retained records.
- Corrections require repeated per-record facts, not a whole-collection hash.
  Ambiguous replacement IDs with identical match facts and football-data IDs
  moving competition are held/withheld, never guessed into aliases or migrations.
- Provisional pending dates/counts are internal, scoped polling evidence: near
  starts keep five-minute polling; unknown timing keeps15-minute polling. They
  are not public fixtures, countdowns or reminder eligibility.
- A wholly partial HTTP200 needs validated fresh verified rows. Unavailable
  row overrides expire after30minutes; receipt/provenance failures cannot bypass
  admission. Native failures/caches preserve watermarks and remove held reminders
  without deleting bookmarks. Installed clients do not gain these changes until
  the separately approved native installation gate.
- Native MLB/NHL stream joins may admit one exact dated two-participant match
  from a plain category, only for verified senior men's fixtures with no contrary
  league/squad evidence. Ambiguity/doubleheaders are rejected. Explicit local
  provider-ID aliases preserve saved and playback continuity; generic channels
  remain programme-unconfirmed.
- Fresh same-publisher finished/cancelled/postponed evidence is compared with
  accepted active records. Fresh current evidence against an old quiet snapshot
  requires refresh, not a definitive omission claim. Only identical consecutive
  fact evidence escalates after grace; collection remains bounded and limited
  to admitted publisher lanes. This is not independent-publisher corroboration.

## Monitor and its limits

The staged hourly `sports-fixtures.yml` validates accepted identities, counts,
per-lane freshness, conflicts and repeated failures. Healthy/pending activation
does not create an issue. Alerts use one dedicated bot issue and fixed redacted
codes; a transient failure must recur in the same competition, not merely in a
different sport. The monitor never changes fixtures or deploys a repair.

The monitor also reconciles currently live and next-24-hour MLB/NHL/WNBA
fixtures against newly fetched league schedules. This is an independent fetch
of the same publisher, not independent-publisher corroboration. Pending times,
stale/failed comparison sources and the normal refresh grace cannot establish
an immediate omission. Cricket separately compares West Indies with CWI.
The unactivated website lanes do not receive an automated crosscheck. Full
cross-publisher coverage remains a source-selection gap, not a completed gate.

## Activation and release gates

- `FOTTY_SPORTS_FIXTURES_ENABLED="1"` is the owner-approved primary-source
  activation setting; `FOTTY_SPORTS_PUBLIC_WEB_FEEDS_ENABLED="0"` remains mandatory.
  General activation cannot turn on the public website adapters.
- `FOTTY_SPORTS_WNBA_ENABLED="0"` is separately default-off. On 1 October the
  canonical league schedule returned valid JSON to Node, but a bounded Cloudflare
  remote preview returned HTTP 200 `text/html`, not an admissible schedule.
  This is an access gap, not healthy empty WNBA coverage. The adapter is retained
  and any previous durable state is not deleted; no cron/GET collects this lane
  until verified edge access and explicit activation. Do not widen JSON admission,
  spoof access headers or add an unreviewed alternate publisher to evade this gate.
- The PL/CL authenticated bulk adapter validates echoed scope and exclusive
  `dateTo`. A bounded direct credentialed check on 1 October returned HTTP 200,
  exact requested date bounds, CL/PL scope and matching count/array length of zero.
  This used the existing local credential; equality with the deployed secret
  was not established. Production version `5befcc6e-540d-41db-be0c-6171d9ccd250`
  accepted both lanes at 09:44 UTC with matching zero rows and no failures.
  This qualifies the transport/schema, not independent fixture completeness.
  The existing proxy strips bulk competition parameters and is not proof of scope.
- Publish through a protected PR after source-access review and current gates.
  Reconcile remote native/backend state; do not assume the older remote client
  equals this working tree. Production `worker-version.mjs` is
  `2026-10-01.sports-fixtures-4`, deployed from exact merged main `3742b96`.
  Recheck current version before health assertions; older dated receipts below
  describe prior deployments, not the present baseline.
- Confirm the registered cron, deployed flags/binding, warmed per-source
  receipts and a published monitor run. Observe a scheduled run separately.
- Install only on the explicitly approved device, then verify retained interests,
  source-free countdown/reminder, provider playback and saved corrected fixtures.
  TestFlight is a separate significant-update gate.

Local qualification, 30 September: all 294 JavaScript units pass, including 35
monitor/crosscheck tests; TypeScript, repository lint, zero-warning focused
Worker lint, Worker dry-run, actionlint and redacted secret scans pass. The
simulator-free Catalyst unit / unsigned iOS Release gate passes after the NCAA
cohort correction, including 21 new native fixture tests. SwiftLint's new-file
error is resolved; style warnings remain, not a claimed zero-warning Swift gate.
These checks are not physical playback or production activation evidence.
Owned Xcode/dry-run/actionlint output is removed; about 48 GiB remains free.

## Local expansion and qualification, 1 October

The existing football-data credential returned an exact six-code scope/window
with matching zero count in one bounded request. PL/CL, La Liga, Serie A,
Bundesliga and Ligue 1 now share that adapter, replacing four gated duplicate
website descriptors. This uses the existing account, not a new subscription;
it proves transport/schema, not independent completeness or production coverage.
The required Football-Data.org attribution is included in native privacy and
web terms source. The [source-access ledger](Sports-Fixture-Source-Gaps.md)
records every remaining competition and distinguishes data rights from code
licences. No provider account, purchase, access bypass or new paid call occurred.

Older PL/CL-only durable receipts cannot mark the four added leagues covered.
New scope triggers one immediate refresh and persists its attempted scope;
failed migration respects five-minute backoff after GET/POST/restart. Per-scope
pending counts must exactly reconcile with the requested lanes and total.
Malformed scope/count receipts preserve accepted rows and timestamps.

The existing local heartbeat was updated in place, retaining its six-hour
cadence and ID `fotty-cricket-fixture-supervision`, under the name **Fotty
all-sport fixture supervision**. It runs both bounded audits, checks published
monitors and investigates new actionable source/native failures independently.
It treats deferred/offseason lanes as expected gaps, not incidents, and cannot
edit, publish, deploy or replace the cloud collector. Local supervision still
requires the Mac/app available; the Worker cron does not.

Fresh simulator-free qualification passes 652 Catalyst tests with two skipped
and the generic unsigned iOS Release compile, including eight legacy-football
regressions. This is freshly compiled source, not an old installed Mac app.
The source-only native correction is not installed and no TestFlight build was
uploaded. Owned Xcode output was removed; pre-existing caches are preserved.
The full backend suite passes 317 tests, including actual-workerd primary-source
contracts and cricket cohort/boundary regressions. TypeScript, zero-warning
focused ESLint, Worker dry-run and redacted targeted source scans pass. Existing
SwiftLint file-length/style errors remain; this is not a clean app-wide SwiftLint
claim. About 46 GiB remains free. No cloud/GitHub publication occurred.

Independent bounded research supports an expected empty PL/CL window for UTC
1 October through 8 October exclusive: the Premier League's
[published season list](https://www.premierleague.com/en/news/4675097) and
[25 September return notice](https://www.premierleague.com/en/news/4726845/when-does-the-premier-league-return)
resume on 10 October, while UEFA's
[published league-phase calendar](https://www.uefa.com/uefachampionsleague/news/02a8-2174c9e9019d-f909a77bd77a-1000--2026-27-champions-league-all-the-league-phase-fixtures/)
places the next matchday on 13–14 October. Dynamic calendar rows and subsequent
rearrangements were not independently readable. This corroborates published
expected emptiness for PL/CL only, not current completeness of all six leagues.

## Expanded cleared-source rollout, 1 October 2026

- Owner chose backend publication/deployment only, not TestFlight or new feeds.
  Protected [PR35](https://github.com/jetboss/Fotty/pull/35) merged as
  `3742b96f08d02e4dce722073f818c3b3f7a4a43d`. Only nine fixture Worker
  source/test files and three operations documents changed; playback, Coach,
  credentials, config and native code were excluded. The reused clean checkout
  was detached at that exact merged commit before deployment.
- Node24 qualification: all 321 units, typecheck, focused zero-warning ESLint,
  dry-run, redacted scans and diff checks pass. Full-repository lint has 48
  existing warnings, zero errors. Hosted Web CI36883227752 (including build),
  quality36883227772 and CodeQL36883227802 pass; no local app/simulator build.
- Worker `d1cdb4e4-abb5-48a5-b024-2b276ddc23c8` carries source
  `2026-10-01.sports-fixtures-4` at 100% traffic. Existing four Durable Object
  bindings, website0/WNBA0, Coach disabled/50 and four secret-name/type receipts
  are retained. The quota-consuming football-live route was not called.
- The registered `*/5 * * * *` handler was independently observed on that exact
  version at 15:30:45 UTC, outcome ok, zero exceptions. Only finite timing,
  version/outcome/count metadata was retained; the bounded tail stopped.
- Fresh production receipts at 15:25:46 UTC accept all six football scopes
  with zero rows/pending in this window, plus MLB13 (eight separately pending)
  and NHL57. Eight covered /23 explicit unsupported scopes; no enabled-lane
  failures or conflicts. [Hosted sports monitor36884399877](https://github.com/jetboss/Fotty/actions/runs/36884399877)
  passes live contracts and same-publisher reconciliation on merged main.
  Manual dispatch does not establish hourly GitHub scheduler timing.
- Cricket remains partial: healthy WI9 advances, while conflicted ICC58 retains
  exact 13:00:46 facts and source receipts. Its full monitor still flags the
  unresolved kickoff changes; see cricket operations. CPL39, health/embed and
  all three catalog providers pass. No shared release or new device install.

## Production runtime correction

Initial version `0236bf27-037f-4490-ad1b-450f57d23d6d` registered the registry
and cron but accepted no new source snapshots. This did not qualify activation.
An isolated actual-workerd reproduction found all four collectors rejected
`redirect: "error"` before outbound I/O. Node mocked-fetch tests did not expose
that runtime difference. Both collector families now use Workers-supported
`manual` and reject 3xx/already-redirected/non-success responses without following
`Location` or forwarding credentials. Website access gates remain off.
Protected PR32 deployed `5befcc6e-540d-41db-be0c-6171d9ccd250`, source version
`2026-10-01.sports-fixtures-2`. The 09:44 UTC receipts admitted PL/CL (zero),
13 MLB and 57 NHL fixtures. WNBA remained unavailable with fixed
`collection/upstream-not-json` evidence; the final candidate defers that lane.
The correction adds actual edge-runtime regressions and finite redacted
failure-stage/code/status receipts; raw exceptions/bodies/URLs are never logged.
The initial manual monitor run 36842326870 failed during cold/failed activation;
the final cleared-source monitor has passed. Owner-device acceptance remains open.

## Cleared activation receipts, 1 October 2026

- Protected [PR33](https://github.com/jetboss/Fotty/pull/33) merged as
  `7eb401cf00dd06331f4ec5991c989f3c3377b0f2`. Its source tree matches the deployed
  clean checkout. Web CI 36846612572, quality 36846612567 and CodeQL 36846612478
  pass; all302 clean JavaScript units and focused local gates pass.
- Worker version `dc563c36-0137-41d5-b2bf-d292634902e7`, source
  `2026-10-01.sports-fixtures-3`, has the registry binding, general activation1,
  website0/WNBA0 and registered `*/5 * * * *` trigger. Health header/body agree.
- A bounded read-only tail observed that exact version's scheduled handler at
  10:10:45 UTC with outcome `ok`, independent of a manual GET or monitor dispatch.
  Only cron/time/version/outcome fields were retained; the tail process ended.
- `/api/sports/fixtures` returns HTTP200, verified, 70 fixtures: MLB13/NHL57;
  PL/CL have successful empty receipts in this window. Four scopes are covered,
  27 deferred/unsupported. Zero collection failures/conflicts in cleared lanes.
  Eight MLB provisional events are separately pending, not fabricated reminders.
- [Hosted monitor 36847037463](https://github.com/jetboss/Fotty/actions/runs/36847037463)
  passes its contracts, live audit and same-publisher MLB/NHL comparison. This
  manually dispatched recovery is not proof of hourly GitHub scheduler timing.
- Cricket independently validates67 fixtures/three scopes; CPL verifies39;
  health/embed and all3 catalog providers pass. Paid Coach remains disabled at50,
  secrets/budget identities unchanged and football-live quota route not called.

## Owner iPad consumer receipt

Private2.0.1(112) app/extension installed and launched on exact Jet iPad
`00008101-001954E20AC0001E` after strict signatures, profile/device/team,
empty embedded provider-key checks and an immutable pre-build source compare.
Native last-known-good cache validates70 fixtures/31 lanes and revision
`38d7b01dedac3eded81080ef407c6a7b19afb9cba33648d23c963266c1ed00df`;
its successful receipt is10:15:46 UTC. Original manager/Home-curation values
are retained (fingerprints compared privately, values never exported).
Actual landscape Home renders and installed process remains alive beyond60s.
This is reception/retention/launch evidence, not reminder or decoded-playback proof.

Owner112 also shows a separate legacy football-verification warning. Bounded PL/CL
legacy probes return200 and empty current-season windows. The legacy repository
escalates empty results into an unconfigured full-season premium fallback;
proxy cooldown can also cause local no-key failures. Both are concrete paths,
but the exact observed device error was not captured. Local source now treats
valid empty schedules as successful cached results, avoids unconfigured premium
and per-league fanout, preserves real proxy errors across cooldown and propagates
cancellation without poisoning the cache. Malformed 200 bodies are decoded
before success caching. Eight injected-session/repository regressions qualify
these concrete paths, not the exact old device error. Install/accept the new
source separately before calling that warning resolved; real errors stay visible.
