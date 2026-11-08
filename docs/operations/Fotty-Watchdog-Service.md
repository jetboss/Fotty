# Fotty watchdog service

The observation-only watchdog checks admitted playback-source contracts,
deployed fixture integrity and the health of the monitors themselves. It does
not repair code, migrate domains, publish native builds or upload tester data.
The owner approved publication and activation on 11 October 2026. The cloud
collector and independent GitHub observer are active; physical build acceptance
remains a separately recorded native gate.

## Ownership and coverage

`fotty-watchdog` is a separate Cloudflare Worker with its own transactional
SQLite Durable Object. It reads CS manifest/catalog, both admitted StreamEx
catalog paths, the Streamed backup catalog, the Score808 listing contract, AS
manifest/football/cricket catalogs, one eligible CS delivery-descriptor shape and
the existing playback Worker's health and accepted sports/cricket snapshots.
Accepted fixture registries, source admission and playback delivery remain
owned by the existing service. No generic channel establishes a named match.

The fixture scope includes deployed Carabao plus the earlier eight non-cricket cohorts (Premier
League, Champions League, La Liga, Serie A, Bundesliga, Ligue 1, MLB and NHL),
plus CPL, West Indies and ICC cricket. Deferred feeds and genuine off-season
coverage remain inactive, not outages. Held ICC facts retain their existing
conflict/freshness evidence. A successful request does not renew accepted facts.

Catalog/descriptor-shape metadata is not media-segment, decoded-video, audible-audio
or PiP proof. Those need a named physical canary. Native evidence remains the
private device ring and local test results; central tester telemetry is not
enabled. The exact current-fixture sampler reads one descriptor only; it never fetches
delivery URLs. Unattended native/media testing remains a separate gate.

## Schedule and request limits

Cloudflare cron checks whether collection is due every five minutes. Actual
metadata collection is at most once per15minutes, at most two reads in
parallel, with no compounded retries. Each read has a 10-second deadline and
a bounded body; CS catalog uses the native 700 KiB ceiling. CS and AS each allow288metadata
reads per UTC day; each single-read provider allows96. Provider reads total960
maximum; existing health/sports/cricket reads add up to288. Reservations use the actual
UTC day and an exact live collector lease. Exhaustion means unknown, not an
outage or recovery. Existing fixture collection cadence is unchanged.

The collector claims a four-minute lease with an increasing fence and commits
only while still owning it. An overlapping cron or late worker cannot overwrite
a newer receipt. Notifications and completion times follow a successful durable
commit; failed storage never announces recovery.

The independent GitHub observer runs at minutes7,22,37and52. It reads redacted Worker
status and published sports, cricket and provider/CPL workflow results. It uses
a35-minute collector heartbeat allowance, three-hour hourly-workflow allowance
and 30-hour daily-workflow allowance. GitHub scheduling may be delayed; this is
secondary verification, not precise uptime measurement.
[GitHub schedule limits](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule),
[Cloudflare cron configuration](https://developers.cloudflare.com/workers/configuration/cron-triggers/).

## Incidents and delivery

Stable incident identity combines environment, source, stage, failure class and
normalized facts, excluding timestamps, attempts and builds. Two matching
failed windows confirm; a reviewed explicit publisher closure confirms on its
first observation. Two fresh matching successful windows recover. Empty catalogs
areUNKNOWN. Stable metadata-unavailable observations retain repeated mixed-cause
failure detection alongside specific diagnostics. Unknown,
inactive, wrong-version or partial checks interrupt recovery. Healthy siblings
and unrelated sports/cricket scope cannot clear an incident. Fact-specific
omissions require their own recheck; metadata success cannot erase them.

The ledger preserves 128 active and 256 resolved summaries, with 30-day resolved
retention, 2 KiB records and a 1 MiB total storage envelope. Up to 512 retained alert
events survive failed delivery and restart. A separate reserved capacity notice
makes exhaustion explicit; no active conflict or undelivered notice is silently
discarded. Capacity degradation blocks future repair claims until reviewed.

GitHub delivers changed-state alerts through bot-owned, stable-identity issues
assigned to jetboss and event-marked owner-mention comments. Only verified issue
assignment and comment submission advance the delivery receipt. Exact event IDs
deduplicate retries; this is not proof of human email/push receipt. A supplemental
Codex heartbeat bridges changed alerts and monitor failures to this chat. See
[owner delivery operations](Watchdog-Owner-Alerts.md). Failed delivery stays retryable in durable
history. A failed write fences later transitions for that same incident, so a
recovery cannot overtake an undelivered failure and leave a stale reopened alert.
Unknown or unchanged polls do not create repeated alerts. Independent
observer state is stored separately in a bounded bot-owned issue. Token access
is restricted to GitHub; source metadata never receives it.

The local incident adapter supports atomic offline persistence and one expiring,
fenced repair claim. No production repair executor, paid agent job, automatic
PR creation, merge, deployment or source migration is activated.

## Operator controls

Worker activation requires `FOTTY_WATCHDOG_ENABLED=1` and a valid
`FOTTY_WATCHDOG_ACTIVATED_AT` timestamp. GitHub requires its separately approved
repository variable `FOTTY_WATCHDOG_ENABLED=1`. The public Worker exposes only
GET `/status`; public requests cannot start checks or acknowledge/erase events.

To pause observation, deploy the reviewed Worker with its flag 0 and disable the
GitHub variable. Do not delete the Durable Object or fixture state. After any
observer/configuration revision change, qualify exact new-version receipts;
old success cannot establish recovery. New origins, operators, credentials,
headers, TLS exceptions, feeds, telemetry or spending need their own review.

Offline qualification:

```bash
node --test tools/watchdog/*.test.mjs
node --test web/workers/watchdog/src/runtime.test.mjs
```

Tests inject synthetic requests and use the installed deployment runtime.
They do not fetch provider media or require production credentials. Physical
builds run sequentially on the approved owner iPad, without simulators, with
owned output removed after evidence is summarized. TestFlight remains separate.

## Original activation receipt — retained history

Protected [PR41](https://github.com/jetboss/Fotty/pull/41) merged with all required
checks and review conversations resolved, without an administrator bypass.
Deployed main commit: `23416ceb21b35b79cd09b334b291bc7b0f13d402`.
Cloudflare version: `de00d85f-2794-456f-8f7b-f2710e980750`.
Activation: `2026-10-11T11:14:52.000Z`; five-minute cron registered.
Source revision: `2026-10-11.watchdog-1`; configuration:
`2026-10-11.admitted-metadata-1`; expected playback source:
`2026-10-06.cricket-isolation-1`. No source/fixture activation is implied by a
successful observer bundle.

The first real scheduled collection started `2026-10-11T11:20:30.189Z`, committed
completion at `11:20:31.207Z`, and recorded next due `11:50:30.189Z`. The public
[bounded status](https://fotty-watchdog.adaptive-rhubarb.workers.dev/status)
reports exact matching revisions and no overflow. This is a scheduled collection
receipt, not a claim that every observed source or fixture is healthy.
Read-only recheck at12:04UTC confirms a later real cron receipt:
attempt11:55:30.064UTC, durable completion11:55:30.787UTC, next due12:25:30.064UTC.
The exact deployed version still serves100%; six initial suspects are unchanged,
with no confirmed incident, notification or overflow.

GitHub's separate repository flag is enabled. The initial
[observer run38134921448](https://github.com/jetboss/Fotty/actions/runs/38134921448)
passed and created its bot-owned ledger issue45. The post-collection
[run38135260124](https://github.com/jetboss/Fotty/actions/runs/38135260124) also
passed; its ledger retains the real `11:20:30.189Z` collector heartbeat and
matching observer/configuration/deployment revisions. A prior cricket workflow
failure remains one unconfirmed suspect, not a new confirmed outage.
Both initial GitHub runs are manual dispatches on exact protected main.
The active13/43-minute schedule and repository flag are verified, but no
scheduled run has appeared as of12:04UTC. GitHub scheduling is delayed; this
receipt does not claim a completed scheduled observer run.

The real12:25:30.089UTC collection committed at12:25:30.913UTC and scheduled
next due12:55:30.089UTC. Six existing suspects reached their third matching
window and became confirmed: two StreamEx redirect rejections and four existing
cricket integrity/freshness observations. Notices1–6 remained durable; a new NHL
unavailability observation is only suspect. These are metadata/integrity facts,
not decoded playback failures or authority to rewrite sources/fixtures.
The activation verification then dispatched exact-main
[run38139497827](https://github.com/jetboss/Fotty/actions/runs/38139497827).
It passed at12:30UTC and delivered all six real notices to bot-owned issues46–51
with pending0/APIrequests14, within the reviewed budget. Thus changed-state
delivery is qualified, separately from scheduled GitHub execution. No scheduled
event is present as of12:31UTC; defaultmain/workflow/Actions/repository flag are
enabled and verified. No concrete setup defect or platform cause is established.

108 combined offline and actual deployment-runtime tests pass with no skips or
failures. These include durable commit/lease fencing, calendar activation,
UTC-day reservations, notification ordering/restart, partial-batch recovery
interruption and bounded fail-closed listing parsing. Public collection requests
remain disabled. No production repair executor or tester telemetry is active.

11 October bounded source checks found CS manifest/catalog and the backup/
Score808 listing contract available. Both old admitted StreamEx paths redirected
to a new origin; the watchdog correctly rejected them. This is a trust-review
decision, not permission for automatic allowlist or endpoint migration.

## 28October owner-alert repair qualification

The owner approved focused watchdog detection/delivery repairs. New configuration
2026-10-28.admitted-metadata-2 keeps the observer wire namespace and existing
durable ledger; it does not replay old issue-only114 notices. Compatible playback
version drift alerts independently without suppressing provider notices. Wrong
wire/configuration remains fail-closed. Normal pending delivery makes Actions fail.

Protected publication, exact deployment, retained-state/cron and real bot-canary
receipts belong in the dated watchdog-owner testing record. Do not infer them
from the original activation history above. Native181 and all owner devices stay
untouched; no TestFlight release or decoded-source qualification.
