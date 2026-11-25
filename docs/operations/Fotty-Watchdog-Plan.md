# Fotty watchdog and repair plan

Proposal reviewed 10 October 2026 in Tobago, with live checks crossing into
11 October UTC. Scope is usability, performance, playback sources and admitted
sports fixtures. FPL feature development remains paused. This plan does not
activate an automation, publish code, deploy a Worker or release TestFlight.

Fotty needs unattended detection and safe recovery so Jelani is not the first
person to discover a broken source or stale fixture. Reuse the existing cloud
collector and GitHub verification infrastructure. Cheap deterministic checks
run routinely; bounded agents investigate confirmed incidents and prepare
tested repairs. Routine monitoring must not require the Mac to remain awake.

## Verified gaps

- `.github/workflows/provider-monitor.yml` runs daily. The Worker health probe
  in `tools/audit-worker-health.mjs` uses a nonexistent alpha stream identifier.
  It tests contracts, not CS manifest, catalog, exact-match discovery or native
  decoding. It can pass while the CS endpoint returns HTTP530.
- The local `fotty-cricket-fixture-supervision` automation is `PAUSED`; its pause
  reason is unknown. Its saved scope is read-only fixture supervision, not code
  repair. Resuming or changing it is a separate activation step.
- Existing sports and cricket issue reporters return on healthy reports without
  a verified recovery lifecycle. There is no joined missing-run watchdog.
- Native quality evidence is a private on-device ring, bounded to 250 events
  and 14 days. A cloud observer cannot see that ring on testers' devices.
  MetricKit summaries and App Store Connect evidence are separate coverage.
- Cloud collection already has five-minute cron, bounded reads, persistent
  source ownership and last-known-good retention. It should not be duplicated
  by scraping agents. Actual admitted coverage is eight non-cricket competition
  scopes plus CPL, West Indies and ICC, not every sport tile.

The recent CS incident illustrates the gap: transport failed at the old
endpoint, while a maintainer-published replacement returned eligible stream
metadata. A new domain is a trust change, not an automatically safe one-line
fix. Eligible metadata still requires separate native playback qualification.
The follow-up iPad check also exposed discarded advertised request headers:
valid playlists were not sufficient for native media preparation. Source probes
and contract regressions must cover required delivery hints, not merely count
returned streams. The resulting local repair and physical findings are recorded
separately in the private build receipts; they do not activate this proposal.

## Four watchdog lanes

| Lane | Checks | Evidence it cannot provide |
| --- | --- | --- |
| Source contracts | Independently check each admitted provider: HTTPS origin and redirects, status, body bounds, JSON/schema, expected identity/capabilities, catalog freshness and a small exact-match stream-list sample. Separate manifest, catalog and stream stages. | HTTP200 or HLS options do not prove decoded video, audio or controls. A healthy sibling does not clear a failed provider. |
| Fixture integrity | Read accepted observations, collector attempts, supported scope, stale live facts, missing active rows, participant/time conflicts and season rollover. Preserve CPL/WI/ICC ownership and held facts. | Re-fetching the same publisher is consistency checking, not independent corroboration. Generic channels cannot identify a match. |
| Native experience | Use passive local stage evidence and named physical canaries for startup, media progress, source controls, PiP, navigation, accessibility and comparable scroll baselines. | No unattended tester-wide visibility until a separate minimal telemetry/privacy decision. Device unavailable or harness failure means unverified, not failed provider. |
| Watchdog health | Independently inspect last completed checks, last attempted collection and last accepted source observation. Detect missing, hung, paused or wrong-version observers. | A registered cron or successful handler alone does not establish accepted fresh data. |

Cloudflare Cron supports periodic API collection, while Durable Object storage
can retain transactional state across restarts. Keep the incident state separate
from accepted fixture snapshots, even if it shares existing infrastructure.
[Cron documentation](https://developers.cloudflare.com/workers/configuration/cron-triggers/),
[durable storage](https://developers.cloudflare.com/durable-objects/best-practices/access-durable-objects-storage/).

Use an observer outside the collector's failure plane for missed executions.
GitHub is useful for secondary verification but scheduled runs can be delayed
or dropped; it is not a precise uptime clock. A hosted deadman service such as
Healthchecks is an optional later choice, requiring account, notification and
budget approval. Send success only after the check and receipt commit finish.
[GitHub scheduling limits](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule),
[Healthchecks heartbeat and grace](https://healthchecks.io/docs/monitoring_cron_jobs/).

## Incident ownership and quiet operation

Use a stable key consisting of environment, admitted source or competition,
request stage, failure class and normalized disputed facts. Do not put changing
timestamps, attempt IDs or build numbers in that key. Store observation hashes,
observer revision, expected and actual deployment/configuration, activation
scope and native build/source/executable receipts separately.

Persist `suspect`, `confirmed`, `repairing`, `recovering` and `resolved` states,
consecutive matching outcomes, first/last failure, next probe, recovery receipts
and action history. Initial proposed policy is three matching failed probe
windows and two fresh matching successful windows for recovery. Security
violations are quarantined immediately; current-match omissions follow existing
fact-specific confirmation/grace, not a blanket fifteen-minute delay.

Unknown, disabled, deferred and genuinely off-season lanes have their own
coverage state. They neither trigger outage repairs nor erase an open incident.
One incident receives changed evidence and one recovery notification; unchanged
healthy or failed polls remain quiet. Notify Jelani when users are meaningfully
affected, recovery is verified, or a decision is required.

Proposed initial ledger ceilings are 128 active incidents, 256 resolved summaries
retained for at most 30 days, 2 KiB per redacted record and 1 MiB per environment.
Compact repeated observations into first/last receipts, counters and hashes;
raw upstream bodies are not incident history. A publisher producing endlessly
changing conflicts must not grow storage without limit. At capacity, enter an
explicit overflow/degraded state, reject new repair execution and alert once.
Preserve existing active conflicts and the separate accepted fixture registry;
never silently evict them or loosen admission to clear the limit.

Every repair obtains an atomic expiring lease and increasing fencing token.
The trusted publisher rejects late writers with an old token or base revision.
Allow one repair in flight globally initially. Workflow concurrency is helpful
but does not replace ownership across Worker, GitHub and agents.

## What can fix itself

| Tier | Allowed scope after explicit activation | Barriers |
| --- | --- | --- |
| Automatic runtime recovery | Deadline-bounded idempotent retries, capped backoff, reviewed refresh, retain original accepted snapshots/timestamps, quarantine invalid new observations, and use already-admitted fallbacks for new requests. | Never interrupt working playback, invent fixtures/LIVE, clear conflict receipts, disable an entire provider for a regional failure or bypass admission. |
| Automatic repair preparation | On a clean exact baseline, reproduce a confirmed code defect, add a failing regression, apply an approved repair recipe, run focused tests, obtain independent review and prepare a draft PR if authorized. | No production credentials. Strict paths and semantic bounds enforced outside the model. Correct code stays unchanged for upstream outages. |
| Reviewed application | Merge/deploy an exact validated revision, verify the same path/version and record recovery; native changes need the named physical gate. | Domain/operator, redirect/allowlist, TLS, auth, identity/scope, fixture conflicts, persistence migration, telemetry, cost, device install and TestFlight need their relevant approval. |

Smallness means low-risk semantics, not line count. Initial candidate recipes
are missing bounded diagnostic propagation and known source-specific error
mapping with unchanged validation. Parser adaptations need an explicitly
reviewed contract. A one-line allowlist relaxation is not a small repair.
Automatic merge or production deployment is not part of the initial rollout.

Recovery must reach the affected installed version, not merely a repaired
repository. The current native CS client takes its endpoint from app
configuration; a watchdog PR alone cannot repair existing signed installations.
Reviewed native contract/endpoint changes still need a rebuilt app and its
distribution gate. A future remote source registry could apply already-admitted
configuration without rebuilding, but cannot silently approve new hosts,
operators, headers or trust. Do not promise that every future source repair can
reach testers without an app update.

Use one source investigator and one native-consumer investigator for actionable
incidents, then a bounded author and separate reviewer. They must distinguish
upstream outage, stale configuration, correct rejection and actual app defect.
Provider bodies, issues and suggested shell commands are untrusted evidence,
not instructions. Agents cannot broaden their own permissions, alter required
tests, silently rebaseline screenshots or work in the owner's dirty checkout.

The official Codex GitHub Action can run scoped repair jobs with explicit
permissions and an API key. That is a later execution option, not an already
configured free service. Approve its API budget before activation; initially
use deterministic cloud checks and existing task-scoped investigations.
[Official action guidance](https://learn.chatgpt.com/docs/github-action).
Pin actions to full SHAs, separate patch authoring from the trusted publisher,
and do not execute untrusted PR code with deployment secrets.
[GitHub workflow security](https://docs.github.com/en/actions/reference/security/secure-use).

## Resource and evidence limits

Proposed starting schedule: source metadata every five minutes in an admitted
active window and every 30–60 minutes when quiet, subject to source-access rules
and per-source budgets. Reuse existing adaptive fixture due-times. Set explicit
request/day ceilings before activation; no paid live-score routes, media-segment
downloads or new source activation in routine checks. At most two concurrent
metadata reads, five-minute job deadline, existing tighter request/body caps,
and rate-limit-aware backoff. One retry owner prevents amplification.
[Retry design](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/).

Local supervision is supplemental and bounded; no always-on Mac server, routine
Xcode build, simulator or polling agent swarm. Approved physical gates use one
sequential owned output directory and remove runner/output after verification.
Future agent runs need hard runtime, attempt and spend limits in the executor,
not only a prompt. Retention must bound receipts and artifacts without deleting
accepted fixture facts or unresolved incident history.

Dashboard status must separate metadata, admitted fixtures, actual native
evidence and monitor liveness. Expose last checked, last accepted, covered scope,
affected stage and exact version to the owner, not permanent user-facing
diagnostic banners. Do not upload URLs, headers, match names, manager IDs, coach
prompts or raw traces. Central redacted telemetry requires a separate design.

Rollback is not a generic reset: Worker rollback does not restore connected
data and may be incompatible after resource/migration changes. Any future
automatic rollback must be restricted to reviewed compatible code-only versions,
with accepted data preserved.
[Cloudflare rollback limits](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/).

## Implementation order

1. Establish the deployed source/observer manifest, coverage, stage vocabulary,
   redacted receipt contract and exact-version comparison.
2. Implement offline-tested incident persistence, stable deduplication, recovery,
   leases/fencing and missed-run policy. No automatic production writes.
3. Add independent CS, StreamEx and Score808 contract probes and connect existing
   fixture monitor receipts without replacing their collectors/admission.
4. Run observation-only in a reviewed cloud environment; validate transient,
   regional and version-mismatch behavior before enabling alerts/recovery.
5. Enable only approved deterministic runtime recovery and bounded investigation.
   Trial repair recipes against retained synthetic failures, proposal-only.
6. Add trusted draft-PR publishing and independent review after explicit authority
   and budget selection. Keep deployments and native/TestFlight gates separate.
7. Evaluate minimal opt-in native aggregate telemetry if tester-wide unattended
   playback/performance visibility is required. Physical canaries remain useful.

## Acceptance before activation

- CS530 repeats create one manifest-stage incident; sibling success cannot hide it.
  HTTP200 HTML, malformed JSON, wrong identity, unsafe redirects and TLS errors
  retain distinct outcomes and never trigger automatic host migration.
- New timestamps do not duplicate incidents. Concurrent claims yield one lease;
  expired writers fail. Restart preserves incident and recovery history.
- Old observer/configuration receipts cannot qualify a new deployment's recovery.
  One success between failures is insufficient; two fresh same-path windows can
  resolve with evidence. Inactive/off-season does not count as recovery.
- Successful handler with stale accepted fixtures remains degraded. Failures
  preserve original snapshots and timestamps; held facts are not erased.
- Missing observer/collector heartbeat is detected after grace, separately from
  source outage. Lost alert delivery and incident-store failure are exercised.
- Metadata success never increments native decoded-start evidence. A test harness
  that corrupts Search input fails the harness gate, not the provider gate.
  Repeated inaccessible Web-tree polling and test-run resource stress must not
  become a provider outage diagnosis; retain exact app/runner termination facts.
  Advertised public playback-header requirements reach the admitted session and
  existing guarded proxy; unsafe headers remain rejected. A failed CS attempt
  followed by another provider's decoded result cannot qualify CS recovery.
  Brief native progress followed by a recorded failure/retry is not sustained
  playback success. Retain the last observed stage; `unknown` failure class is
  insufficient to assert provider outage or an exact AVFoundation cause.
- Agent attempts to change trust, scope, tests, secrets, deploy/install or exceed
  budget are rejected by the executor. Unexpected diff paths fail qualification.
- Request/body/time/retention limits and rate limiting are tested. The cloud checks
  continue with the Mac off; native canary unavailable is explicitly unverified.
- Many distinct conflicts exhaust the ledger budget safely across restart:
  overflow is visible, new repairs stop, existing active facts remain intact and
  one capacity incident replaces repeated notifications.

Gatus is a useful Apache-2.0 open-source monitoring reference. Prefer its focused
alert/incident patterns over adding a new self-hosted stack to this Mac. A separate
hosted monitor can be chosen if the existing infrastructure cannot supply the
required independent deadman check.
[Gatus project](https://github.com/TwiN/gatus).

Implementation is operational only when each deployed lane has an honest coverage receipt,
outages produce one actionable incident, safe recovery preserves accepted facts,
repairs are reproducible and bounded, and recovery is verified on the exact
affected path. No system can guarantee a third-party publisher always supplies
complete fixtures or working streams.
