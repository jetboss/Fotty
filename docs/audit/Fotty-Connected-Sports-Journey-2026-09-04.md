# Connected sports journey — implementation record

4 September 2026 · private local source after build 58

## Outcome and current status

This batch connects discovery, following, saved matches, reminders and Watch.
It also makes catalog failures and match refreshes more truthful. The accepted
compact design, badges, one-tap playback, dedicated optional FPL and separate
Home/Matchday purposes are preserved. This is batch 2 of
`docs/FOTTY-PRODUCT-EXECUTION-PLAN.md`, not completion of the entire roadmap.

**Local qualification passed.** The final combined gate passed 432 native tests,
with zero failures and two intentional live-provider/soak skips, and compiled
the generic unsigned iOS Release. All 83 web/Worker tests also passed.
Physical-device acceptance and real third-party broadcast qualification remain
open; this is not a shipped release.

## What changed

### 1. The same current Watch action from Home and Matchday

`Core/Models/CurrentEventBroadcastPolicy.swift` owns the shared decision instead
of leaving CPL fallback in Home alone. Exact current fixture sources take
precedence. For an eligible reviewed CPL schedule identity without its own
source, one tap can open the preferred active cricket channel. Other channel
rows remain in the catalog. This is an explicitly unconfirmed channel option,
not a claim that Fox or Willow is showing that particular match.

Home, Search-through-Home and personal Matchday consume the same action.
Conflicting identities, inactive sources and ambiguous channels cannot become
a preferred route. Opening a reminder still brings the user to the saved match;
it does not autoplay or insert a second channel-selection screen.

`SavedMatchContinuityPolicy`, `ArenaModels.swift` and `MatchReminderStore.swift`
preserve saved intent when a provider omits a fixture. An exact, consistent
current event can update its start time without changing the saved/reminder ID.
An explicit source withdrawal clears the saved source list instead of borrowing
old URLs. Changed times retain prior-time context. Reused or conflicting IDs
cannot replace the saved opponent identity. Restore and cancellation invalidate
pending reminder opt-in; metadata-only refreshes do not repeatedly schedule an
alert or erase its delivered notification.

### 2. Catalog checks report coverage, not false certainty

`LiveCatalogSnapshot.swift` distinguishes a valid empty feed from an error,
missing response or invalid JSON shape. `AnalyticalDataEngine` collects the
bounded mirror set under one seven-second catalog deadline, retaining responses
that arrive before cancellation. `LiveCatalogAccumulator` also retains each
completed fallback endpoint independently: a pending sibling cannot erase a
received conflict or valid result. The same collector uses the shorter
three-second budget for an already-admitted preferred-event refresh. It records attempted/responding feeds and
partial coverage instead of treating the first nonempty mirror as the whole
schedule. Raw identity-conflict tombstones survive collection and merging for
resolver rejection, while public projection hides them from browsing. An
incomplete or timed-out refresh cannot turn an observed conflict into “missing”
and then revive a cached preferred event.

`MatchListViewModel` is the single refresh owner even when existing rows are
visible. Overlapping callers coalesce; cancelled or older responses cannot
publish a replacement catalog or independently late schedule result. A failed
check retains the prior list and prior receipt, with a visible failure notice.
Partial coverage retains omitted prior entries with qualification. A successful
complete empty result is allowed to remove old provider rows; the separately
validated CPL schedule remains its own source. Saved state is reconciled only
against admitted current evidence, including explicit conflicts/withdrawals.

`CatalogRefreshNotice` exposes recovery on discovery and personal surfaces.
The timestamp means **Fotty checked these listings then**. The providers do not
supply a trustworthy upstream publication timestamp, so it must not be described
as proof that every fixture or broadcast was updated at that instant.

### 3. Slow providers no longer monopolize shared discovery

`SharedStreamDiscovery.swift` pipelines concrete mirror results into validation
as they arrive. It gives families a first opportunity before using repeated
descriptors from the same family, retains meaningful delivery alternatives, and
preserves useful sessions and actionable failures when the outer deadline ends.

Current defaults are six lookup slots and six validation slots, seven seconds
per lookup and eight seconds per validation, within the existing shared
18-second overall discovery deadline. Descriptor/candidate/session budgets also
remain bounded. The optional late refresh for an already-admitted preferred
event has a three-second limit inside that common clock; it is not an extra
unbounded wait. The whole catalog scan is not automatically restarted.

Timeout is not treated as a confirmed empty catalog. Canonical fallback remains
restricted to its known contract; failed concrete candidates do not authorize
invented routes. Incremental diagnostics survive deadline/cancellation, and
owned child URLSession work is cancelled with the parent attempt. These bounds
limit app-controlled work; they cannot guarantee provider response or decoding.

`LiveSourceHealthStore` no longer turns a match's missing content, stall or
playback error into a persisted family/host circuit. Those failures remain
attempt-local, where exhausted sources are already tracked. Legacy broad
failure/stall penalties are cleared on load; measured successful history,
startup latency and last-good preferences remain available for ordering. This
does not bypass transport security checks or declare an unhealthy source good.

### 4. Personalization has a real multisport effect

`SportsTeamIdentity.swift`, `TeamFollowKey.swift` and the typed team-search
metadata preserve sport, canonical name and badge. Reviewed football aliases,
NBA/WNBA/MLB/NHL entries and CPL identities no longer depend on the query text
or a shared logo URL. Lakers/Dodgers/CPL selections therefore stay in the correct
sport. Women, reserves, youth squads and different opponents remain distinct.
Unknown provider teams retain their declared sport and complete name; unknown
aliases are not guessed.

`SportsPersonalizationPolicy` reads legacy aliases and known incorrectly
football-tagged multisport follows compatibly. The transactional migration
helper repairs/deduplicates those records while preserving the earliest follow
and explicit mute choice, without adding a SwiftData schema. `MainTabView` now
invokes the isolated migration on startup and after private-backup restore,
with a visible error if durable repair fails. Compatibility reads keep the
saved choices usable in that case. This wiring is implemented in local source;
no installed device's store is claimed to have completed the migration yet.

Favorite Leagues now means “add recognized fixtures to My Matchday,” including
CPL and the supported major-sport league identities. Matching is competition-
and sport-scoped, excludes channels/conflicts, and rejects ambiguous evidence.
It does not turn on reminders or promise playback. Settings explains that effect.

Owned team/league settings now use isolated writer contexts and visible save
errors, so a failed preference write does not discard unrelated pending edits.
Scalable text, explicit selected states and named unfollow actions replace the
previous weaker semantics. Alert bells are offered only for supported Premier
League team updates. Device checks are still needed for visible query refresh,
large text and VoiceOver interaction after cross-context writes.

### 5. Match details refresh as one packet; missing search results recover

`MatchHubSnapshot.swift`, `FootballRepository` and `MatchHubViewModel` publish
the match and derived insights together. Pull-to-refresh no longer updates only
insights while leaving the header/lineups/statistics on an older packet.
Failed or stale refreshes retain the complete previous packet and qualify it;
request ownership rejects late replacement after stop or a newer refresh.
Catalog-only details also refresh the current source list, including an explicit
withdrawal, and expose a refresh failure instead of silently keeping a stale
Watch action as current.

A failed/conflicting recheck disables both the displayed provider choices and
actual Watch admission while retaining readable stale details. Later successful
verification can restore the action; an in-flight lookup is cancelled without
tearing down media already playing. Repository cache writes check cancellation
after asynchronous enrichment, not only before UI publication.

Canonical schedule routes survive provider enrichment/API aliases only when
the expected route and exact teams agree, kickoff is within 15 minutes and
competition/country evidence is compatible; the enriched API ID stays
associated with that checked route. Publication also validates that the match
resolves the requested route and that insights belong to the same packet. A
dictionary cache alias is not enough to rebind a different match. Header/context
and insights share freshness rather than claiming a newly fetched insight makes
an old score current.

`CatalogTimingPolicy.cplWindow` supplies one eight-hour rain-delay/expiry window
to CPL discovery and channel eligibility, avoiding a six-hour/two-policy split.
This remains a schedule estimate, not an official live/final state.

Search stays on the shared catalog. An empty result now says it is not in the
available lineup, explains late publication/partial checks and offers refresh.
It does not infer that no broadcast exists or create another independent poller.

## Verification record

| Area | New behavioral coverage present | Result |
| --- | --- | --- |
| Saved/reminded Watch | `MatchdayJourneyTests`: one-tap CPL return, direct-source priority, time/identity limits, omission/reschedule/withdrawal, restore/cancellation | 11 passed |
| Catalog refresh | `SportsCatalogRefreshTests`: valid empty vs failure, coverage, conflict tombstones, retained receipts, coalescing, stale/cancelled publication, CPL window | 12 passed |
| Provider scheduling | `SharedStreamDiscoveryTests`: incremental mirrors, slow healthy responses, bounded fairness, concrete alternatives, partial deadlines and actual URLSession cancellation | 19 passed |
| Health scope | `LiveSourceHealthScopeTests` and playback policies: match failures do not create broad circuits; legacy penalties retire without losing success history | 5 new tests passed; existing policies passed |
| Personalization | `SportsPersonalizationTests`: typed multisport identity, alias/squad negatives, legacy migration, persisted preferences and injected failed writes | 11 passed |
| Match details | `MatchHubRefreshTests`: coherent packet, failed/stale refresh, lifecycle races, known route enrichment and source withdrawal | 11 passed |
| Integration/build | Full simulator-free Catalyst suite, two build jobs, generic unsigned iOS Release in the same disposable root | 434 total: 432 passed, zero failures, two intentional skips; Release passed |
| Web/backend | Fresh complete existing web/Worker unit suite; no paid traffic or deployment | 83 passed, zero failures/skips |

Source assertions are not substituted for these state-transition tests. Tests
must pass on the combined source, not only on isolated helpers. This record
does not inherit a prior batch's passing totals as new evidence.

Qualification caught a legacy six-hour CPL assertion, now covering the exact
shared eight-hour boundary. The relay deadline harness also exposed a client
retry race: a URLSession client could reopen a closed GET before the test checked
connection count. The final harness exercises one raw loopback request and
independently verifies upstream cancellation, connection closure, exactly one
upstream request and zero retained relay connections before manual cleanup.
It passes without weakening the leak assertion or changing playback timeouts.

Final native result: 4 September 2026, 21:06 local. All gates reused one temporary
root; cleanup removed its DerivedData, test bundles and logs after reading the
results. No archive, duplicate signed app or screenshot was created. Approximately
29 GiB remained free after cleanup. `git diff --check` passed.

## Remaining acceptance and boundaries

- Qualify one exact candidate on approved iPhone/iPad: find → follow/save →
  remind → return → Watch, including corrected start times and a provider failure.
- Confirm actual cross-context preference updates, retained prior choices on
  failure, Light/System, large text and VoiceOver without coaching the tester.
- Recheck real playback controls, pause/recovery and background/PiP on the exact
  build; deterministic resolution tests cannot prove decoded media continuity.
- A closed app cannot learn a late schedule change and rewrite an already
  scheduled local reminder. Notification delivery also remains subject to system
  permissions/settings. No new background service is introduced here.
- Upstream timestamps and unknown aliases remain limitations, not facts to fill
  in optimistically. Private release/feedback and wider FPL work remain separate.

No version change, device installation, TestFlight upload, production service
deployment, Git publication or paid Coach request is part of this batch.
The preceding foundation's checked-in paid-Coach configuration remains disabled,
with the owner's 50-attempt UTC-day allowance for the whole private group;
production configuration and activation are not claimed by this source record.
