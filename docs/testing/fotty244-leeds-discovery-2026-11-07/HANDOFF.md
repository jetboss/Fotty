# Fotty live catalog and playback failure — engineering handoff

Prepared 7 November 2026. The owner requested this handoff to try another agent. This is an investigation handoff, not a claim that the incident is fixed or authorization to deploy changes.

## What the owner experienced

The owner was watching **Leeds United–Tottenham Hotspur**. At half-time the stream failed. After closing and reopening Fotty, no streams appeared. They initially said Newcastle–Leeds, then explicitly corrected the fixture to Leeds–Tottenham. Do not investigate the wrong match.

The owner is frustrated by repeated catalog repairs and wants the underlying failure understood. The expected experience is: tap **Watch**, see the correct match quickly, recover automatically to a genuinely usable alternative, and retain the ability to discover sources after restarting. They should not have to use a “Check streams” button or browse channels to find a listed match.

Priorities: Premier League, Champions League, and cricket carried by Willow/Fox. Source ranking should favor actual speed/reliability and proximity to live, not blindly prefer TV over CS. Preserve all compatible options.

## Scope and safeguards

- Start by diagnosing this incident across discovery, registry, matching, caching, playback and recovery. Do not assume the player or half-time is responsible.
- Leave the owner's phone, FPL and multi-stream alone. No device was operated during this investigation. Historical device permissions do not establish current availability; do not interrupt owner playback.
- No new TestFlight release, Git publication, backend deployment, source-setting changes, account creation, spending, or transport/security exceptions are authorized by this handoff. Any later repair should follow the owner's current instruction and repository rules.
- Do not weaken exact team/squad/date/competition, terminal/conflict, original timestamp, redirect, header, public-address or transport checks just to make choices appear.
- Use the canonical repository: `/Users/jelani/Documents/Development/Fotty`. The chat may start in the old `/Users/jelani/.codex/worktrees/cricket-fixture-activation/Fotty` worktree. Verify before editing.
- Canonical checkout observed at `main`, HEAD `0219232`, with many accumulated modified/untracked files. This is not a clean representation of deployed code. Do not reset, clean, stash everything or overwrite unrelated work. Verify each relevant local/deployed/shipped version.
- Mac: 256 GB storage, 8 GB RAM. No simulators or concurrent heavy builds. Use one owned temporary output directory and clean only its artifacts. Do not start another sequence of builds before establishing the failure.

Read `AGENTS.md`, `agent/AGENT-START.md`, `docs/notebooklm/Current-State.md` and `agent/playbooks/playback.md`. Current-State contains outdated build numbers; dated release receipts and verified external state outrank it.

## Release baseline

Fotty **3.0.0 (244)** is available to the existing **Fotty Internal Smoke** TestFlight group, notes exactly **Bug fixes**. See `docs/releases/Fotty-3.0.0-244.md`.

Release checks: 2,652 Catalyst test passes, 12 skips, unsigned iOS Release compile and signed archive verification. **No physical test of 244 was performed as part of distribution.** These checks do not establish this incident's playback/restart behavior. The owner's actual incident device/build/source were not confirmed.

The archive source is preserved at `backups/release-source/3.0.0-244-final`. Compare the relevant shipped files with current source before attributing a defect to 244. Do not treat current checkout changes or old private-build tests as evidence of what shipped.

## Confirmed observations

Small redacted receipt: [investigation.json](investigation.json). Times below are 7 November 2026; Tobago is UTC−4.

1. **The official fixture remained live.** `/api/sports/fixtures` returned `sports-fixture:premier-league:560632`, Leeds United FC–Tottenham Hotspur FC, kickoff **12:30 UTC / 08:30 Tobago**, status `live`. PL collection reported zero consecutive failures at the initial check. Other competition failures do not establish a PL outage.
2. **The public registry omitted CS for this match.** At **13:41:30 UTC**, it contained listed reviewed-TV/ESPN and Score808 links, plus AS rows marked `catalog-conflict`, `missing-date` and `stale-source`. It did not contain a CS match link. Those listed alternatives are metadata evidence, not decoded-playback proof.
3. **CS itself advertised the exact match.** Fresh football and Live catalogs and same-ID metadata agreed on the pair and `2026-11-07T12:30:00.000Z`. Public event ID: `nuvio_sport_ts_tottenham-hotspur-v-leeds-united-401878758`. The slug order differs from the title; do not infer identity from the slug alone.
4. **CS returned 29 descriptor entries: one external support link and 28 direct-stream entries.** The 28 advertised same-origin HTTPS manifest wrappers. No media was decoded, and these are neither 28 proven working streams nor 28 independent providers. URLs/tokens were not saved.
5. **Current local collector and association code accepts fresh CS metadata.** At **13:45:05 UTC**, an in-memory replay using real manifest/football/Live responses through `collectBroadcastSource`, `normalizeBroadcastCollection` and `associateBroadcasts`, with the fresh official fixture, produced `listed / exact / communitysports`. Other catalog cohorts were deliberately not fetched and threw unavailable in that harness. This establishes the target's parsing/matching under those inputs, not a full cloud cycle or native resolution pass.
6. **The CS football registry receipt was old.** `lastSuccessAt`/`observedAt`: **12:25:04 UTC / 08:25 Tobago**. `nextAttemptAt`: **13:40:04 UTC / 09:40 Tobago**. That is a 75-minute scheduled gap spanning kickoff and half-time. The captured response was generated after that due time, so investigate actual execution/delay as well as planned cadence.
7. **The scheduler explicitly permits long gaps.** Daily CS budget is 288 HTTP reads. `cadence()` gives an eight-read cycle a 40-minute minimum even with a live fixture. `checkpointPlan()` can advance a pre-kickoff collection and postpone the subsequent cycle to repay that advance. Two existing scheduling tests pass while asserting this behavior. Passing these tests therefore does not validate the desired live freshness.
8. **Half-time is not generically treated as finished in the native football model.** `FootballMatch.MatchStatus.isLive` includes `.paused`; its display text is `HT`. This does not rule out another status or freshness boundary elsewhere.

## What is NOT established

- The source/variant that stopped, its media/relay error, network state, audio state, and whether recovery ran or exhausted alternatives.
- The actual device and installed build for this report; its enabled sources and exact empty-picker/error state.
- The cloud's persisted checkpoint/budget state. Public timestamps are consistent with the scheduling gap, but we did not inspect durable state or prove that exact checkpoint caused this specific missing row.
- Why an app restart showed no choices despite listed ESPN/Score808 metadata and a fresh direct CS listing. **Do not claim that the cloud CS omission fully explains the empty picker.**
- Whether AS's conflicting record affected other families. No evidence currently proves that it did.
- Whether any of the 28 fresh CS entries play correctly now.
- Whether the collector updated after the observation window. Refresh current evidence rather than treating these times as current health.

Important counter-evidence: `HybridStreamProvider` has a direct adapter fallback when `registered.isEmpty`. Therefore “CS absent from the registry” is not by itself sufficient to explain a failed explicit Watch lookup. Trace whether that branch was reached, skipped, timed out, cancelled or rejected.

## Code map for the next investigation

Line numbers are navigation hints for the inspected local source, not permanent references.

| Boundary | Files / relevant symbols |
|---|---|
| Cloud collection schedule, budget and durable merge | `web/workers/playback/src/broadcast-registry.mjs`: `cadence` (~119), `checkpointPlan` (~149), refresh/checkpoint reservation (~280), provider merge and next-attempt calculation (~318–375) |
| Source-specific catalogs | `web/workers/playback/src/broadcast-source-adapters.mjs`: `csRow`, `collectBroadcastSource`, CS manifest/live/networks/football/cricket cohort loop (~750) |
| Registry normalization and fixture links | `web/workers/playback/src/broadcast-registry-policy.mjs`: `normalizeBroadcastCollection`, `mergeBroadcastRecords`, `normalizeRegistryFixtures`, `associateBroadcasts` |
| Native registry fetch, persistence and validation | `Fotty/Core/Networking/BroadcastRegistry.swift`: `validated`, `LookupIndex.lookup`, `reconciling`, `refreshForPlayback` (~912), `performRefresh` (~937), cache priming and refresh error reporting |
| Watch visibility and negative outcomes | `Fotty/Core/Models/CurrentEventBroadcastPolicy.swift`: `actionForCurrentEvent` (~136), `BroadcastRegistryWatchPolicy` (~197), `FixtureSourceLookupPresentation` |
| Process-local discovery evidence | `Fotty/Core/Networking/StreamDiscoveryCoordinator.swift`: discovery deadline, `FixtureStreamDiscoveryIndex`, `FixtureCatalogAvailabilityIndex`; these indexes are not persistent source registries |
| Refresh and source gathering | `Fotty/Features/Dashboard/MatchListViewModel.swift`, `LiveCatalogSnapshot.swift` (locate current path), app/tab-owned refresh and cancellation |
| Registered versus direct lookup | `Fotty/Core/Internal/HybridStreamProvider.swift`: `optionalRegistryMatches`, registered/cached candidates (~720), direct fallback when registry is empty (~766), provider failure classification |
| CS parsing, metadata and admission | `Fotty/Core/Networking/CommunitySportsAddonClient.swift`: `resolve`, `selectMatch` (~1122), `makeSessions`, header/wrapper admission and stream-ID validation |
| Shared exact identity | `Fotty/Core/Networking/ReviewedSportsFixtureMatcher.swift`, `Fotty/Core/Social/SportsTeamIdentity.swift` |
| Playback/recovery ownership | `Fotty/Features/Player/LivePlayerViewModel.swift`, `ViewingSessionCoordinator` and `LivePlaybackRecoveryPolicy` (locate current files) |
| Guarded media path | `Fotty/Core/Networking/LocalStreamProxy.swift`, `LocalStreamProxyPolicy.swift` |
| Diagnostics | `Fotty/Core/Logging/FottyLogger.swift`: `FottyQualityStore` (~431), persisted key `fotty.quality.records.v1`, retention 14 days / 250 records; attempt, source, relay, HTTP, preparation and recovery fields exist |

Quality records are local. The existing App Store Connect usage dashboard does not supply the device's detailed stream failure history. Preserve records before a new test overwrites the bounded buffer. Obtain them through an authorized read-only path; do not silently take over the phone.

## Recommended next steps

1. Preserve the incident evidence and relevant shipped-source hashes. Confirm the device/build/source from available diagnostics rather than asking the owner to repeat everything. Ask only for genuinely unavailable information.
2. Reproduce the **cold-start path**, not just a warm successful lookup: official live fixture, absent/stale CS cloud link, current CS catalog, fresh process-local indexes, and the owner's enabled providers. Trace Watch eligibility → source dispatch → adapter result → picker publication. Explain why direct fallback did not rescue the reported case.
3. Inspect actual deployed scheduling code/state and collector results around 12:25–13:45 UTC. Determine whether the gap was checkpoint debt, normal budget cadence, a failed collection, delayed alarm, version mismatch, or a combination. Do not simply increase caps or refresh all sports continuously.
4. Once proven, repair bounded live-priority collection and cold-start/retry discovery together where needed. Keep official fixture identity separate from media leases. A failed URL must not imply that the match or all source families vanished. Do not renew expired media or erase genuine conflicts.
5. Correlate the initial playback failure with the source attempt and relay records. Repair that independently if necessary; catalog work alone does not establish stable media.
6. Validate focused logic first. Then use one consolidated private build on a free, authorized Jet iPad, if a build is needed. Backend activation/publication requires its own current authorization under AGENTS.md. No TestFlight upload just to deliver another unproven patch.

## Required regression and acceptance scenarios

- A provider publishes the match only after the pre-kickoff collection. Active-match collection cannot silently wait through most of the first half; prove an explicit freshness target while preserving request accounting.
- Transition scheduled → live → half-time → second half; no match disappearance or source eligibility loss solely from half-time.
- Close/reopen with an empty local index and a stale or missing cloud association. Exact fresh adapter discovery still runs where supported and publishes its outcome.
- Initial registry request fails or joins another refresh; original retained evidence stays correctly bounded and independent providers can still succeed.
- A source fails while another resolves late; failure, negative lookup, cancellation and expiry stay local to the correct provider/fixture/attempt.
- One AS conflict cannot suppress valid CS/TV/Score808 choices for the match. Do not weaken the conflicting AS row itself.
- Explicit Retry fetches current catalogs/descriptors rather than replaying the failed cached choice. Relaunch does not inherit an incorrect permanent negative.
- Real match acceptance: normal Watch → time to correct picture → observe advancing video → safe forced primary failure → measure automatic recovery to an independently verified same-match backup → close/reopen → Watch again. Preserve failed receipts. Distinguish no available independent backup from a failed failover mechanism.
- Metadata, HLS responses, player clocks and unit passes are not proof of correct decoded programme or audible commentary. Report each evidence level separately.

## Previous repairs to examine, not blindly repeat

- `docs/testing/fotty187-broadcast-reliability/README.md`: prior-found Watch evidence and catalog envelope, PR104.
- `docs/testing/fotty194-shared-watch/README.md`: PR106 fixture associations and PR107 CS channel/cohort and Flix coverage fixes.
- `docs/audit/Fotty-November-2026-Baseline.md`: snapshot isolation, cloud-to-Home availability import, delayed alternatives and discovery deadlines, builds 217–219.
- `docs/testing/fotty-watch-retry-2026-11-01/README.md`: fresh explicit Retry and fallback, build220.
- `docs/testing/fotty241-plaviolive/README.md`: AS migration/registry repair PR126 and follow-up receipt-age correction PR127.

The previous agent told the owner “at least nine catalog/discovery fixes since October29.” This was a conservative count of individual changes across these records, **not** nine independently audited release rounds or nine proven resolutions of this incident. Do not use that number as a precise defect ledger.

## Work completed in this investigation

Read-only code/metadata investigation; replayed current CS target through local cloud parsing/association; ran two existing scheduling tests. No app or backend repair, deployment, install, device control, source preference change or TestFlight action. One owned temporary raw registry capture was removed. Only the redacted JSON receipt and this handoff remain.

Return a causal account separating the initial stream interruption from source disappearance after reopening, with evidence for each. Clearly state remaining uncertainty. The owner needs a verified viewing lifecycle, not another broad “fixed” claim based on narrow tests.
