# Fotty provider resilience: research and recommended next work

28 October 2026. Read-only investigation requested by the owner after the Streamed closure, CS route drift and owner-alert repair. This report proposes work; it does not implement or activate it.

## Conclusion

Keep the existing single-stream architecture and the repaired watchdogs. The next milestone should prevent silent loss of monitoring, make monitoring agree with the shipped app, and demonstrate an actual viewing journey before a playback release. Adding more source labels or an autonomous repair agent does not establish those properties.

External publishers can still close or refuse requests. The achievable goal is to detect this, notify the owner through a working independent route, and use a separately qualified alternative when one exists. A monitor must never describe compatible metadata as verified video playback.

## Evidence and limits

- REA analyzed the actual deployed `fotty-watchdog` JavaScript fetched through Cloudflare's read-only script-content API at **22:43:31 UTC / 18:43:31 Tobago**. Deployment inventory was unchanged before and after retrieval: active version `4316bd15-eada-44f4-9b10-071d78f61440`, 100% allocation. `index.js`: 126,714 bytes, SHA-256 `532b2550b7aa95d48a31ce98c2f5211e3eae47f13e677cb30d5412daf3683b74`.
- REA parent evidence: `ev_6449666f93580d51d8322a863cfba6dbe67af5fe126b2a58be8bf7de6b72676e`. One included JavaScript file parsed without errors; exports include `WatchdogState` and `default`. Static semantic coverage is partial/unknown, with 3,870 unresolved semantic observations. This does **not** prove runtime execution, current bindings, alert delivery or video playback. Selected identity/summary evidence is retained in `docs/testing/rea/fotty-watchdog-2026-10-28/receipt.json`.
- Ordinary source inspection covered the native CS/AS clients, matching rules, watchdog contracts, persistence and GitHub/chat delivery. The GitHub observer is a separate program and is not claimed to be part of the analyzed Worker bundle.
- Pure offline probes confirmed the unexpected-deactivation outcome and the CS ID mismatch. A separate offline probe reproduced cross-competition incident recovery. No provider/media requests, app builds, device interactions, production mutations or deployments were performed for this audit. Documentation and the deployed script were retrieved read-only. Owned temporary analysis input was removed after retaining the small receipt.
- Today's actual Cup playback recovery and monitoring activation remain covered by their existing receipts, not by this static analysis: `docs/testing/fotty181-playback-recovery-2026-10-28/` and `docs/testing/watchdog-owner-alerts-2026-10-28/`. The 22:33 UTC unattended owner-alert run also completed quietly. Neither that run nor the synthetic delivery test proves email/mobile-push arrival or human reading.

## Confirmed problems and concrete failure paths

### 1. Unexpected deactivation can silence the independent observer

`tools/watchdog/github-observer.mjs:53–78` treats a compatible status response with `activation: pending` as inactive, and returns no cloud notices. `web/workers/watchdog/wrangler.toml` deliberately defaults activation to zero. This is correct for a never-activated candidate, but cannot distinguish it from an accidentally deactivated production installation.

**Scenario → consequence:** a later deployment misses the explicit activation override; the existing active collector becomes pending. With the Mac unavailable, the GitHub path does not raise the expected stopped-collector incident. The current deployed collector is active; this finding describes a reproducible next-deployment risk, not a new current outage.

**Recommended solution:** persist the production activation expectation outside the collector. Require a deliberate, time-bounded maintenance declaration to suspend it. Verify enabled state, original activation timestamp, storage identity and first real scheduled collection after every monitoring deployment. A previously active installation becoming pending must be actionable; initial unapproved candidates must remain quiet.

**Acceptance:** offline and isolated runtime cases for never activated, activated→pending, deliberate maintenance, expired maintenance and active-but-stale. The outside observer must detect unexpected pending even when the local reader is absent.

### 2. Alert history has finite lifetime capacity without safe retirement

`tools/watchdog/incident-policy.mjs:173–184,241` preserves all outbox events, including those already submitted downstream. Cloud policy allows 512 events; the independent observer allows 64. `tools/watchdog/owner-alert.mjs:15,95,114` keeps up to 1,024 known receipts; acknowledgement removes pending entries but retains known receipts. GitHub issue/comment discovery has additional finite inventory bounds.

**Scenario → consequence:** recurring failure/recovery transitions eventually fill one ledger even when delivery works. Overflow becomes sticky or the local reader refuses another event. This is a long-run lifecycle defect; the audit does not claim any current limit is exhausted. Finite memory bounds themselves are desirable.

**Recommended solution:** a verified delivery watermark, bounded archival/issue rotation and deduplication sequence floor, with explicit schema migration. Preserve active incidents, exact event identity, unresolved deliveries and ambiguous submissions. Alert before exhaustion. Raising ceilings or deleting history without an acknowledgement model is insufficient.

**Acceptance:** feed more than two full capacities through a bounded offline/isolated lifecycle, including restart, ambiguous POST response, retry, compaction and rollback. Undelivered events survive; delivered events do not replay; memory stays bounded.

### 3. Monitoring and native consumer contracts disagree

- `tools/watchdog/source-probes.mjs:9,84` restricts catalog IDs more narrowly than `Fotty/Core/Networking/CommunitySportsAddonClient.swift:806–815`. Offline example: `nuvio_sport_example~variant` is rejected by the watchdog despite matching the native ID policy.
- `source-probes.mjs:115–119` rejects the entire AS catalog for one malformed independent row. The native path can preserve that row as local conflict evidence while admitting an unrelated valid match (`PlavioSportsAddonClient.swift:175–183`; `ReviewedSportsFixtureMatcher.swift:85–107`).
- Monitoring contracts do not currently identify the consumer contract revision supported by each installed release. A newly compatible descriptor does not establish compatibility with an older app.

**Scenario → consequence:** a usable catalog produces a false source-outage alert, or a green metadata check is mistaken for evidence about a different installed consumer. This undermines the owner's confidence in monitoring.

**Recommended solution:** one reviewed, versioned corpus of redacted contract examples run by both Swift and Node tests. Include routes/aliases, IDs, headers, exact squads/dates, conflicting duplicates, missing optional fields and malformed independent rows. Associate qualified contract revisions with release artifacts. This does not require replacing Swift with JavaScript or deploying a contract broker. Preserve all security and ambiguity rejections.

**Acceptance:** identical documented outcomes from both consumers for the corpus. Explicitly distinguish partial-row drift, source-wide unavailability, incompatible contracts and unknown evidence.

### 4. A different competition can falsely establish recovery

`tools/watchdog/delivery-contract.mjs:69–71,231–258` deterministically prioritizes eligible PL fixtures and records all CS descriptor outcomes with `scope: football` and `dimension: candidate-shape`.

**Scenario → consequence:** a Cup route fails twice and confirms drift. Subsequent healthy PL samples resolve the same incident although the Cup route has not recovered. When PL and Cup matches are simultaneously eligible, repeated selection favors PL. An offline synthetic sequence reproduced both behaviors.

**Recommended solution:** stable incident scope by reviewed competition and delivery family, plus fair bounded sampling designed together with confirmation/freshness policy. Merely rotating every poll can reset the existing missing-check streaks and introduce a different blind spot. Missing live fixtures or empty descriptors remain unknown, never invented failures or recovery.

**Acceptance:** interleaved PL/UCL/Cup samples cannot clear each other's incidents, every eligible admitted scope receives a bounded turn, and delayed samples retain correct confirmation semantics within the request budget.

### 5. AS/cricket and actual playback remain outside important gates

`tools/watchdog/manifest.mjs:31–33` admits AS manifest/catalog monitoring but no AS descriptor stage. CS's descriptor selector covers senior men's football only. `source-probes.mjs:285–286` deliberately never fetches returned media URLs. These are explicit coverage boundaries, not evidence that those providers are currently broken.

**Scenario → consequence:** a valid AS cricket catalog or compatible CS master descriptor survives while a video playlist returns 403 or the programme is wrong. The metadata monitor cannot detect the user's failed viewing journey. Today's descriptor-versus-child-playlist experience makes this a concrete failure mode.

**Recommended solution:** add bounded, exact-fixture AS/cricket descriptor coverage using the native format/ordinal/Test-day rules. Separately qualify real user journeys on an approved device in actual PL, UCL and cricket windows: fixture→discovery→normal picker→correct decoded video held for 90 seconds→basic native controls. Controlled reference video between live windows verifies the player, not a third-party provider. Measure the whole tap-to-first-frame and recovery wait, including failed attempts.

**Acceptance:** distinguish `discovered`, `consumer-compatible`, `media-available` and `native-playback-verified` evidence with timestamps and tested release. A valid URL, advancing clock, empty overnight catalog or skipped device test never counts as decoded playback.

### 6. Cached manifests can conceal an upstream repair

CS and AS cache manifests for 30 minutes without a forced refresh when a required resource/catalog is missing (`CommunitySportsAddonClient.swift:211,398–402`; `PlavioSportsAddonClient.swift:253,270–272,312–320`).

**Scenario → consequence:** AS adds a required cricket or same-ID metadata resource after a prior manifest fetch. Fresh monitoring sees it; the owner's explicit retry retains the older manifest and still cannot discover the match.

**Recommended solution:** one bounded forced refresh for a relevant resource/configuration mismatch inside the existing owned discovery deadline. No unrestricted polling, nested retries or refresh on every empty stream response.

**Acceptance:** cached missing resource→fresh valid resource succeeds on retry; unchanged missing resource stops within budget; cancellation and conflicts still reject safely.

## Additional resilience requirements

### Actual independence, not endpoint count

The closed Streamed publisher served several configured catalog profiles. Those are useful routes but were not independent providers. Today's AS identity repair removed a dependency on that publisher; preserve that improvement.

Record reviewed catalog publisher, fixture authority, resolver and known delivery dependency separately. Do not infer independence from names such as CS1/CS2 or different hostnames; unknown relationships stay unknown. Target two independently qualified delivery paths for PL/UCL and priority cricket where available. A shared upstream closure must not eliminate every discoverable path or cause duplicate alerts pretending to be unrelated failures.

Fixture freshness is another dimension: accepted snapshots and a fresh fetch of the same publisher can agree while both omit a match. The current MLB/NHL/WNBA reconciliation explicitly uses the same publisher. For a concrete suspected critical-fixture omission, use bounded corroboration from a reviewed independent authority, preserving conflicts and explicit activation scope. Never infer a match from a generic channel.

### Owner alerts when the Mac is off

The new GitHub assignment/mention path is cloud-side; the supplemental chat reader depends on the Mac and Codex. GitHub documents that scheduled jobs can be delayed or dropped. Assignment/comment submission is not verified email or push delivery.

For stronger coverage, add one verified direct cloud owner-notification destination and a separately hosted missed-heartbeat checker, retaining durable retries/deduplication and a synthetic delivery drill. Select the destination and validate its actual receipt before claiming this property; no new service, credentials or spending was activated for this report. A second observer on the same platform does not by itself eliminate that platform's outage risk.

### Persistence-aware release and rollback gates

The repaired legacy failure-count and cadence carry-over cases demonstrate why empty-storage tests are insufficient. `incident-policy.mjs:112,139` also rejects retained records whose source is removed from the next manifest. That is a plausible future configuration/migration risk, not a current failure.

Require old confirmed/suspect/resolved/pending-delivery state in regression qualification; test new-reader/old-state and rollback-reader/new-state compatibility. Bind a release receipt to the actual deployed script, activation, schema and native contract revision. Cloudflare code rollback does not rewind Durable Object data. Rehearse a supported rollback and preserve the last qualified playback path.

Keep current strengths: the owned 18-second discovery budget, per-attempt failed-source exclusion, decoded-start ranking, explicit safety/identity guards, durable notifications, duplicate protection, confirmed-window policy and unknown semantics. Do not introduce retries at every layer or globally ban a provider because one match returns 404.

## Recommended implementation order

1. **Protect monitoring itself:** expected activation, maintenance semantics, safe delivery-history retirement and capacity warnings. Establish the cloud owner destination if approved.
2. **Align contracts and sampling:** shared Swift/Node regression corpus; correct CS competition scope and fair sampling; bounded manifest refresh; explicit AS/cricket descriptor coverage.
3. **Qualify independent coverage:** reviewed publisher/dependency map and actual backup PL/UCL/cricket delivery evidence; targeted independent fixture corroboration.
4. **Make release readiness measurable:** end-to-end native live-window canaries, total viewing/recovery latency, retained-state migration/rollback gate and isolated monitor/delivery fault drills.

Completion means the concrete acceptance cases above pass with saved receipts. It does not mean every third-party stream is always available. No broad UI rewrite, multi-stream work, continuous device farm, broker deployment or autonomous source-domain/security change is needed for this milestone.

## Primary research

- [Google SRE: monitoring distributed systems](https://sre.google/sre-book/monitoring-distributed-systems/) — symptom monitoring, internal diagnostics and low-noise actionable alerting.
- [Google SRE: canarying releases](https://sre.google/workbook/canarying-releases/) — bounded evaluation before wider rollout; a canary is limited evidence, not universal coverage.
- [Stremio Stream Object contract](https://stremio.github.io/stremio-addon-sdk/api/responses/stream.html) — advertised URL/protocol and header requirements do not guarantee support in every client.
- [Stremio protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md) — catalog, metadata and stream resources are separate contracts.
- [GitHub scheduled workflow limitations](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule) — scheduled execution can be delayed/dropped.
- [Cloudflare Wrangler configuration](https://developers.cloudflare.com/workers/wrangler/configuration/#source-of-truth) — deployment configuration and variable preservation must be explicit.
- [Cloudflare Worker rollbacks](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/) — code rollback and retained external/Durable Object state have different lifecycles.
- [Cloudflare Durable Object storage](https://developers.cloudflare.com/durable-objects/best-practices/access-durable-objects-storage/) — transactional storage and SQLite recovery support, subject to a deliberate recovery procedure.
- [Apple HLS playback logging](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/HTTPLiveStreaming/HTTPLiveStreaming.html) — access/error logs provide diagnostic evidence beyond catalog availability.
- [AWS: control and limit retries](https://docs.aws.amazon.com/wellarchitected/latest/framework/rel_mitigate_interaction_failure_limit_retries.html) — bounded retries and avoiding amplification across layers.
