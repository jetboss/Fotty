# Fotty watchdog service

The observation-only watchdog checks admitted playback-source contracts,
deployed fixture integrity and the health of the monitors themselves. It does
not repair code, migrate domains, publish native builds or upload tester data.
The owner approved publication and activation on 11 October 2026. Deployment
receipts and final physical results are recorded below when their gates finish.

## Ownership and coverage

`fotty-watchdog` is a separate Cloudflare Worker with its own transactional
SQLite Durable Object. It reads CS manifest/catalog, both admitted StreamEx
catalog paths, the Streamed backup catalog, the Score808 listing contract, and
the existing playback Worker's health and accepted sports/cricket snapshots.
Accepted fixture registries, source admission and playback delivery remain
owned by the existing service. No generic channel establishes a named match.

The fixture scope is the actual deployed eight non-cricket cohorts (Premier
League, Champions League, La Liga, Serie A, Bundesliga, Ligue 1, MLB and NHL),
plus CPL, West Indies and ICC cricket. Deferred feeds and genuine off-season
coverage remain inactive, not outages. Held ICC facts retain their existing
conflict/freshness evidence. A successful request does not renew accepted facts.

Source metadata is not stream-list, media-segment, decoded-video, audible-audio
or PiP proof. Those need a named physical canary. Native evidence remains the
private device ring and local test results; central tester telemetry is not
enabled. Exact-match stream sampling and unattended native testing remain
separate future gates, not hidden coverage in this service.

## Schedule and request limits

Cloudflare cron checks whether collection is due every five minutes. Actual
metadata collection is at most once per 30 minutes, at most two reads in
parallel, with no compounded retries. Each read has a 10-second deadline and
a bounded body; CS catalog uses the native 700 KiB ceiling. CS allows 96 metadata
requests per UTC day; each other provider allows 48. Reservations use the actual
UTC day and an exact live collector lease. Exhaustion means unknown, not an
outage or recovery. Existing fixture collection cadence is unchanged.

The collector claims a four-minute lease with an increasing fence and commits
only while still owning it. An overlapping cron or late worker cannot overwrite
a newer receipt. Notifications and completion times follow a successful durable
commit; failed storage never announces recovery.

The independent GitHub observer runs at minute 13 and 43. It reads redacted Worker
status and published sports, cricket and provider/CPL workflow results. It uses
a 75-minute collector heartbeat allowance, three-hour hourly-workflow allowance
and 30-hour daily-workflow allowance. GitHub scheduling may be delayed; this is
secondary verification, not precise uptime measurement.
[GitHub schedule limits](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule),
[Cloudflare cron configuration](https://developers.cloudflare.com/workers/configuration/cron-triggers/).

## Incidents and delivery

Stable incident identity combines environment, source, stage, failure class and
normalized facts, excluding timestamps, attempts and builds. Three matching
failed windows confirm; two fresh matching successful windows recover. Unknown,
inactive, wrong-version or partial checks interrupt recovery. Healthy siblings
and unrelated sports/cricket scope cannot clear an incident. Fact-specific
omissions require their own recheck; metadata success cannot erase them.

The ledger preserves 128 active and 256 resolved summaries, with 30-day resolved
retention, 2 KiB records and a 1 MiB total storage envelope. Up to 512 retained alert
events survive failed delivery and restart. A separate reserved capacity notice
makes exhaustion explicit; no active conflict or undelivered notice is silently
discarded. Capacity degradation blocks future repair claims until reviewed.

GitHub delivers changed-state alerts through bot-owned, stable-identity issues,
deduplicated by exact event IDs. Failed delivery stays retryable in durable
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

## Current activation receipt

Candidate only while protected publication and activation gates are unfinished.
Source revision: `2026-10-11.watchdog-1`; configuration:
`2026-10-11.admitted-metadata-1`; expected playback source:
`2026-10-06.cricket-isolation-1`. No source/fixture activation is implied by a
successful observer bundle.

11 October bounded source checks found CS manifest/catalog and the backup/
Score808 listing contract available. Both old admitted StreamEx paths redirected
to a new origin; the watchdog correctly rejected them. This is a trust-review
decision, not permission for automatic allowlist or endpoint migration.
