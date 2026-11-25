# Consolidated viewing incidents — 4 November 2026

Owner-approved policy replaces the per-provider notification model below.

- Keep cloud collection, fixture checks, workflow health checks, original budgets,
  confirmation/recovery windows and retained evidence running unchanged.
- The GitHub observer updates its **existing bot-owned ledger issue as one quiet
  status dashboard**. No new provider issues, assignments, comments or mentions.
  The old delivery-canary dispatch is a no-send retired operation, not a pass.
- Historical issues, delivered hashes, cloud outbox and private pending receipts
  remain intact. Dashboard persistence is never recorded as owner delivery.
- One owner case per affected discovery scope groups failure reasons, emits one
  confirmation, and emits recovery only when every recorded cause has resolved.
  Stale, absent, incompatible or expired evidence cannot clear a case.
- Raw provider errors, missing catalog rows, workflow delays, collector drift,
  capacity and optional email errors remain diagnostics. They do not establish
  that the viewer has lost playback while another route may work.
- Current positive alert authority is deliberately narrow: fresh cloud-confirmed
  HTTP 5xx failures of the app-consumed sports/cricket fixture endpoints. Wording
  must say **fixture refresh is affected; existing playback may still work**.
  These are discovery incidents, not proof that all streams are unavailable.
- Decoded-playback failure, exhausted independent backups and playback recovery
  are **not observable by this metadata-only monitor**. Do not invent those
  alerts or claim full end-to-end outage detection. That requires a separately
  reviewed native attempt/outcome signal or authorized live canary.
- The local `owner-alert.mjs` uses the same private state file, adding a bounded
  `viewing` case map. Old pending records remain retained but are no longer
  eligible to notify. Only new `viewing` receipts can reach chat. ACK still means
  verified chat append, never human reading. Never initialize/reset old state.
- Chat delivery still requires the Mac/app and the existing heartbeat to run.
  A paused heartbeat remains paused unless explicitly reactivated. No new email
  service, cloud deployment, credentials, telemetry or AI job is introduced.

Publication/activation and verification receipts:
`docs/testing/watchdog-incidents-2026-11-04/README.md`.

---

## Historical notification implementation (superseded by policy above)

# Provider alerts reaching the owner

This is observation and owner notification, not unattended code repair. The owner
approved this watchdog repair on28October2026. Keep devices, FPL, multi-stream,
source enablement and TestFlight unchanged.

29October source candidate: native AS catalog selection and additional trusted
monitor-completion triggers are staged. Publication, cloud activation and actual
delivery verification remain separate gates; the source changes below do not
claim an always-on delivery deadline.

A separate direct-email lane is prepared defaultOFF. An operator receipt verified
the private owner destination at29October23:06:34UTC; sender onboarding/eligibility
remains unresolved. See
[Watchdog-Direct-Email.md](Watchdog-Direct-Email.md) for factual setup/cutover
requirements and ambiguous-submission limits. It has not replaced either active
delivery path. Optional email-health signals are read-only and contain no target.

## Two delivery paths

1. The cloud collector commits finite metadata incidents to its existing durable
   ledger. The independent GitHub observer assigns each new incident to the
   verified owner `jetboss`, posts one event-marked bot comment mentioning that
   owner, verifies both writes, then records submission. Recovery uses the same
   issue only after its confirmation delivery finishes. Ambiguous writes retry
   by stable event marker. Historical issue-only receipts do not replay114 alerts.
2. A dedicated Codex heartbeat runs the bounded `tools/watchdog/owner-alert.mjs`
   reader and reports new events or monitoring failures in the current chat.
   It reads the cloud outbox directly, so a new cloud incident can reach this
   channel even when no fresh GitHub observer or issue write is available.
   This is a supplemental local channel: it needs the Mac/app available. GitHub's
   cloud notification path remains independent of this Mac. Assignment/mentions
   are targeted notification submissions, not proof of human reading, email
   arrival, sound or mobile push settings.

The GitHub connector has no notification-inbox endpoint; the existing CLI token
cannot read that inbox without a new scope. Do not expand tokens or change OS/
account notification preferences to make a test look passed. A real bot canary
and any accessible owner-inbox evidence are recorded separately.

## Detection contract

- Cloud cron remains every5minutes; eligible collection is15minutes. Two matching
  failed checks confirm; two fresh positive checks recover. Exact reviewed
  Streamed closure title+sentence confirms on first observation. Generic HTML,
  redirects and timeouts never acquire that terminal authority.
- Stable metadata-unavailable observations also catch alternating fatal reasons.
  Empty/source-less catalogs areUNKNOWN, not outages or recovery. No current
  fixture, held/conflicting status, expired receipt or empty stream list is a
  decoded failure. Healthy sibling providers/sports cannot clear incidents.
- Already reviewed AS manifest+football/cricket catalogs and deployed EFL Carabao
  integrity join existing metadata coverage. The CS sampler reads at mostONE
  exact current verified senior-men's football fixture descriptor; it checks
  consumer delivery shapes, including native HLS paths/headers, without fetching
  any returned delivery URL. Web-only fallback cannot clear native-HLS drift.
- AS follows the native advertised catalog selection: prefer the reviewed
  `plaviohd-football` catalog, otherwise use legacy `plaviohd-live-sports`;
  cricket uses `plaviohd-cricket` only when advertised. A duplicate or wrong-type
  reviewed sibling vetoes its scope rather than guessing. A failed/empty
  dedicated football catalog never borrows generic Live or cricket recovery.
  The existing typed metadata bounds remain strict; schema success is not an
  exact dated-fixture match or playback proof. No advertised ID can add a route.
- Providers reserve at most960metadata reads/day: CS288, AS288, four singles96
  each. Health/sports/cricket add up to288/day. At most two provider reads run in
  parallel, bounded deadlines/bodies/no retries. No paid AI/media/decode jobs.
- Independent GitHub observer intended cadence7/22/37/52minutes. Actual completion
  age matters: schedules can be delayed. The chat reader reports collector or
  normal observer completion older than35minutes, failures/pending delivery,
  overflow, unavailable reads and contract/revision drift. A successful synthetic
  canary is excluded from normal observer freshness.
- Completion of the existing Sports Fixture, Cricket Fixture or Provider
  Metadata monitor supplies an additional normal observer opportunity through
  `workflow_run`. Only the same repository's `main` runs originally triggered by
  schedule or workflow_dispatch qualify; failed audits also qualify. The job
  checks out protected `main`, never triggering-run code/artifacts/caches, and
  shares the existing serial observer concurrency group. It cannot trigger
  itself. Permissions, bounded observer requests and provider collection quotas
  remain unchanged; there is no workflow dispatch, rerun or repair side effect.
- Compatible finite source notices still flow across playback deployment-version
  drift. Drift is its own incident; wrong observer/configuration wire contracts
  still fail closed. No drift may manufacture fixture recovery.

## Delivery boundary and configuration preservation

Additional GitHub triggers reduce reliance on one cron but remain on GitHub
Actions. They are not a separate provider or a guaranteed scheduling deadline.
On29October, an all-status normal observer check found a5h14m16gap between
successful completions while the cloud collector continued to commit fresh
receipts. A successful completion later does not erase that historical delay.

Names-only inspection found no existing GitHub credential in the watchdog
Worker. Its cloud cron cannot anonymously call repository_dispatch. Do not copy
the local CLI token, create a secret, introduce an account/channel or promise
independent always-on owner delivery as part of this repair. The existing direct
cloud-to-Codex reader is independent of the GitHub observer's execution, but
depends on the Mac/app. Neither path proves email, mobile push or human reading.

The AS selection repair changes configuration identity to
`2026-10-29.native-catalog-parity-1`. Keep the original activation, durable
incidents/outbox, budgets, leases,15minute collection interval and two-check
confirmation/recovery thresholds. Old evidence remains retained; only fresh
checks of the correctly selected catalog may advance recovery under the new
configuration. Deploy the existing watchdog against the same protected playback
release identity; no initialization/reset or historical alert replay is needed.

## Reader and acknowledgement

```bash
node tools/watchdog/owner-alert.mjs poll --initialize
node tools/watchdog/owner-alert.mjs poll
node tools/watchdog/owner-alert.mjs ack WD-RECEIPT_RETURNED_BY_POLL
```

Only the first explicitly approved bootstrap uses initialize. It records known
historical observations, not prior human delivery; summarize current known
outages during activation. Monitor blindness and synthetic delivery tests are
never silently baselined. Later polls do not use initialize.

The private local state is bounded under `~/.codex/automation-state/`; it contains
finite/hashes-only incident identities and pending notifications, no credentials,
private device IDs, playback history or media URLs. Polling retains pending
receipts. **Do not acknowledge a receipt until the corresponding notification
is visible in this chat.** A later heartbeat reads the previous chat response,
acknowledges only exact visible WD receipts, then polls. This acknowledges chat
append, never human reading. If uncertain, retain/retry the notice. Do not run
concurrent writers or erase/reset state to silence a failure. A failed state read
must itself generate an owner monitoring-failure notice.

On a new alert, give the affected provider, failed stage, consequence, timestamp
in Tobago and link to the issue where available. Group same-provider diagnostic
and aggregate events. Include exact WD receipts for subsequent deduplication.
Stay quiet on healthy/unchanged checks. Do not repeatedly rebuild apps or fetch
streams. Investigate a new actionable failure with bounded read-only source
checks; stage a focused repair only within the owner's current scope. No
unattended publishing, deployment, new source trust or security exceptions.

## Real delivery qualification

Dispatch watchdog-observer with delivery_canary=true once, on protected main.
It creates a separate clearly synthetic bot issue/owner mention; no provider
incident, accepted fixture or production ledger is altered. Re-running the same
workflow ID must not duplicate the comment. Run the normal owner reader, verify
it sees exactly one labelled delivery-test receipt, report it here, then let the
next heartbeat acknowledge that visible receipt. Run normal observation
separately; a canary is not a provider health or scheduler pass.

## Deployment safeguard

Never deploy this Worker implicitly with playback. Before its separately approved
repair deploy, capture redacted status; deploy the protected exact source with
keep-vars AND explicit enabled1/original activatedAt flags. Source default0 stays
safe for accidental deployments. Verify active/original activation, new config,
retained notification IDs, no overflow and a real later cron commit. Do not erase
incidents to fit the new configuration. Local/CI/dry-run passes do not prove
activation or actual notification delivery.

Official contracts: [GitHub mentions](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#mentioning-people-and-teams),
[notifications](https://docs.github.com/en/subscriptions-and-notifications/concepts/about-notifications),
[GitHub schedule limits](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule),
[trusted workflow completion triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run),
[Cloudflare deployment vars](https://developers.cloudflare.com/workers/wrangler/configuration/#source-of-truth),
[Codex scheduled tasks](https://learn.chatgpt.com/docs/automations?surface=app).
