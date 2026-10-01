# Automatic sports fixtures

Status, 1 October 2026: owner-approved primary-source activation candidate.
Protected publication and exact-deployment verification must complete before
this is called live. Cricket retains its existing registry. Website feeds stay
disabled; no TestFlight, new subscription or paid-policy change is authorized.
This backend PR does not reconcile the older remote native app with the locally
qualified consumer. The owner iPad gate uses a separate immutable source receipt.

## Coverage is explicit, not a promise of every event

The new manifest defines 30 source groups and 31 competition scopes. Of these,
28 groups have bounded adapters; boxing and PDC darts remain unsupported.
Cricket retains its separate CPL / West Indies / ICC integration and monitor.

| Lane | Staged competitions | Source boundary |
| --- | --- | --- |
| Football | PL, Champions League, La Liga, Serie A, Bundesliga, Ligue 1, MLS | Existing football-data credential for PL/CL; other leagues are gated website adapters. |
| Baseball / hockey | MLB, NHL | League-owned structured schedule routes. |
| Basketball | WNBA, NBA, men's/women's NCAA Division I | WNBA league CDN; NBA/NCAA website adapters gated. |
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
- The PL/CL authenticated bulk adapter validates echoed scope and exclusive
  `dateTo`. A bounded direct credentialed check on 1 October returned HTTP 200,
  exact requested date bounds, CL/PL scope and matching count/array length of zero.
  This used the existing local credential; equality with the deployed secret
  was not established. Require a successful deployed registry receipt as well.
  This qualifies the transport/schema, not independent fixture completeness.
  The existing proxy strips bulk competition parameters and is not proof of scope.
- Publish through a protected PR after source-access review and current gates.
  Reconcile remote native/backend state; do not assume the older remote client
  equals this working tree. The candidate `worker-version.mjs` is
  `2026-10-01.sports-fixtures-2`; do not call it deployed until the deployed
  version, binding and registered cron match the protected source receipt.
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

## Production runtime correction

Initial version `0236bf27-037f-4490-ad1b-450f57d23d6d` registered the registry
and cron but accepted no new source snapshots. This did not qualify activation.
An isolated actual-workerd reproduction found all four collectors rejected
`redirect: "error"` before outbound I/O. Node mocked-fetch tests did not expose
that runtime difference. Both collector families now use Workers-supported
`manual` and reject 3xx/already-redirected/non-success responses without following
`Location` or forwarding credentials. Website access gates remain off.
The follow-up candidate adds actual edge-runtime regressions and finite redacted
failure-stage/code/status receipts; raw exceptions/bodies/URLs are never logged.
Post-deploy accepted snapshots and monitoring still have to pass.
