Current native follow-on: signed195 is installed onJet. The initial fullscreen request retains inline video until same-window AVKit presentation commits; bounded pending retries/rollback preserve transport ownership.143focused tests and real Lille–Lens native fullscreen/pause/resume/PiP over Home118.773s/systemRestore pass. No phone/FPL/multi/TestFlight change. Final cloud normal collector completed20:01:01UTC. Receipts: docs/testing/fotty194-shared-watch/.

# Fotty Architecture Map

## Current TV expansion ownership — 31 October 2026

- PR114/7d74c40 is deployed as2026-10-31.tv-football-1 (playback21d7abe1/watchdog1a3d08f2), preserving activation/bindings/state. The earlier dated ownership sections below are history.
- `reviewed-tv-espn.mjs` owns only fixed official weekly ESPN RSS, explicit Uruguay/local-IANA dates, finite linear station IDs and source-local literal aliases. It excludes Disney-only/inert/hidden/conflicting rows and never invents programme ends or live status.
- `broadcast-source-adapters.mjs` collects Willow and football independently. `BroadcastRegistry` persists capped collection and actual due-time alarms;576TVreads/day/eight-cycle/ten-minute facts unchanged. Football assignment links require a unique current accepted fixture, exact competition/squad/date/pair and0–60minute source coverage lead. Original source clock remains separate from kickoff.
- `BroadcastRegistryClient`206 negotiates a second V2 header while retaining the old V1 header. V2 receives football assignments; old V1 receives Willow only; legacy stays seven-family. Native playlist client owns TV1–TV8 exact deliveries and binding renewal; Hybrid resolves all matching TV channels with one playlist read.
- Seven Spanish ESPN feeds share one delivery origin.90-second decoder holds and observed station IDs passed privately onJet206; TV3's first stall remains recorded. Actual live PL/UCL programme/normalWatch/control gates remain open. No new generic channel-to-fixture inference, FPL, multi-stream or phone work.
- Receipts and remaining gates:docs/testing/fotty-tv-expansion-2026-10-31/.


Use `docs/notebooklm/Current-State.md` for the current baseline and topic routing.
Retrieve the ownership section relevant to the task and verify current source;
dated deployment statements below are historical evidence, not live status.

## Current shared broadcast ownership — 30 October 2026

- Protected source `76685a7` is deployed as playback `f0765380`, source
  `2026-10-30.match-source-association-2`, with watchdog `47d9ac22`. Existing
  bindings/flags, accepted state and 127 notices are preserved. A later normal
  collector receipt remains pending; deployment alone proves no playback.
- `BroadcastRegistry` Durable Object owns cloud schedules, budgets and original
  observations for eight reviewed metadata families, independently of the Mac
  or AI jobs. `broadcast-source-adapters.mjs` owns fixed metadata contracts;
  `broadcast-registry-policy.mjs` owns exact links, Test periods and conflicts.
  Sports/Cricket registries retain fixture/status authority. Public GET never
  initiates collection. Original seven read caps remain; the fixed `reviewedtv`
  guide has a separate 576-read/day cap and the shared eight-read cycle ceiling.
- `reviewedtv` admits only the fixed main-US Willow station with verified selected
  IANA timezone, explicit date/duration and current official Test context. Daily
  and programme authority is ten minutes; whole-Test event matching retains the
  original-start fence. Generic channels never identify programmes. Native 194's
  exact `reviewedtv-programme-v1` capability header receives the eighth lane;
  older schema 1 clients retain the seven-family cache-separated projection.
- Native `BroadcastRegistryClient` validates/indexes off-main and preserves
  receipts. Its private programme/channel join needs current guide proof plus
  CS `stationMarket: "US"` on the canonical main-Willow channel, preserving the
  original cricket/live/networks cohort. Unknown/UK channels remain browsable
  without fixture authority. TV1 playback opt-in does not govern guide metadata;
  fresh CS NETWORKS/same-ID US metadata still gates channel descriptors.
- `CurrentEventBroadcastPolicy`/`MatchStart` share eligible matches and newer
  negative-result vetoes. Hybrid and source adapters resolve literal current
  IDs; `StreamEventBinding` separates canonical fixture from programme/delivery
  identity, with expiry bounded by all original facts and the 90-second lease.
  Registered descriptor recovery requires fresh equivalent authority. Existing
  channel browsing and guarded transport remain separate from programme proof.
- Native 194 is signed with 399 passing tests, zero failures and three physical
  skips. Jet lock/DDI access blocks installation: Jet still has 193, whose normal
  Le Havre–PSG Watch/CS3 decoded hold is separate evidence. No 194 physical pass is
  claimed. Phone, FPL, multi-stream and TestFlight remain unchanged. See
  `docs/operations/Shared-Broadcast-Registry.md` and `testing/fotty194-shared-watch/`.

The earlier build-191 cloud-OFF/`83b1a44` and proposed-only programme-registry
statements are superseded historical baselines. Current collection and fixture
association are deployed; current source qualification still needs the specific
competition, correct-programme, fullscreen and PiP receipts.

## Shared fixture/source catalog and single Watch ownership — 29 October 2026

- `MatchListViewModel.sourceCatalogRequests` projects bounded accepted official
  fixtures for source discovery; status, terminal/conflict and receipt guards stay
  separate from provider metadata. `primarySourceCatalogEvidence` uses only the
  current accepted provider rows, never older rows retained by a partial UI merge.
- `FixtureCatalogAvailabilityIndex` in `StreamDiscoveryCoordinator.swift` owns
  process-local per-fixture/per-provider outcomes, current/prior-listed evidence,
  expiry, opt-in revisions and logical batch budgets. It owns no URLs, sessions,
  persistence, source settings or LIVE authority. `FixtureSourceCatalogCollector`
  in `LiveCatalogSnapshot.swift` gives each enabled curated family its own bounded
  lane; MainTab owns refresh/cancellation. Never-started lanes consume no budget.
- Source-local `catalogMatches` methods reuse their reviewed manifest/catalog
  scope reads without per-fixture stream/meta fetches. Score808's separate
  `Score808CatalogClient` reads only its fixed listing and advertised calendar;
  CNC's undated catalog pair remains `needsVerification`. Watch-time adapters
  retain exact joins, source-specific timing and normal transport admission.
- `ViewingSessionCoordinator.checkOptionalSources` now supports incremental
  single Watch: first admitted source mounts once, later choices append to the
  exact owned pane. Current fixture/terminal facts and enabled family are checked
  after async callbacks; tab changes cannot revive another pane or old generation.
  Home/Arena callbacks distinguish initial browsing ownership from mounted scene
  ownership. Metadata presentation alone never supplies a playable session.
- Private target is owner-approved Jelani iPhone/CS; Jet, FPL and multi-stream
  stay untouched. Initial431 passed/4 physical-only skipped;52 clock/context and
 124one-tap/admission tests passed. No physical/release acceptance is implied.

## Broadcast reliability ownership — 29 October 2026

- `web/workers/playback/src/broadcast-catalog.mjs` owns the finite schema1 metadata
  envelope, three reviewed profiles of one family, bounded concurrent complements
  and per-edge20s cache. It owns no official fixture authority or media relay.
  `AnalyticalDataEngine` validates schema/receipt/profile/row bounds before normal
  dedup and uses original-clock direct fallback only for transport/contract gaps.
- `FixtureStreamDiscoveryIndex` retains bounded prior-found timestamps separately
  from current candidate/session freshness. `FixtureSourceLookupPresentation`
  projects the same explicit Home/Search/Matchday/Details action; registry revision
  fences invalidate opt-outs and reject late restoration. No per-row networking.
- Existing watchdog provider probes mirror native reviewed AS catalog selection.
  Guarded protected-main `workflow_run` joins existing cron/serial observer;
  neither trigger diversity nor metadata shapes proves native playback.
- Staged `web/workers/watchdog/src/owner-email.mjs` owns ONLY the separate durable
  email key and finite submission queue. It reads committed operations notices,
  never mutates collector ledger/budgets or viewing data. Source defaultOFF;
  verified destination plus onboarded sender/fixed binding/fresh cutover and real
  delivery acceptance remain required. See operations/Watchdog-Direct-Email.md.

## Source-only return and discovery — 29 October 2026

- `LastLiveMatchStore` owns one optional local identity, defaultOFF and36h/8KiB;
  no stream/source/artwork snapshot. Single coordinator ownership starts a
  consume-once ticket, real decoded-stage evidence confirms it, and clear/Stop/
  replacement/non-single panes revoke it. Eligibility is pure; existing Home clock
  and Privacy task prune expiry. Current catalog plus fresh explicit LIVE are
  required before the small Home card can resolve sources afresh on tap.
- `SportsSearchSchedule` projects source-free upcoming rows up to14days from
  accepted sports/cricket/CPL snapshots. Envelope/lane/row freshness, independent
  CPL receipt, terminal/conflict tombstones and normal dedup remain mandatory.
  `MatchListViewModel.searchSchedule` owns no fetch; Search's existing cooperative
  index adds it only for nonempty queries/revision changes. Home72h is unchanged.
- `SettingsManageLeaguesView` is now the single Home interests editor: browse
  sport, additive whole-sport/competition/team choices, current-lineup preview and
  existing persistence. `TeamOnboardingView(initialLeague:)` seeds team browsing;
  settings/onboarding/Home use that same path. FPL/multi feature bodies unchanged.
  See `testing/product-return-discovery-2026-10-29/README.md`; source-only evidence
  never closes the outstanding physical UI/playback gates.

## Source-only discovery/freshness candidate — 28 October 2026

- `CuratedStreamSourceCatalog.discoveryPlan` selects independent enabled reviewed
  lanes from exact dated fixture identity. Complete MatchHub identities no longer
  await the shared catalog; ID-only routes still resolve it. Existing18second
  on-demand coordination remains. Source defaults and trust are unchanged.
- CS/AS adapters own fresh manifest/catalog/descriptor joins and ephemeral
  `StreamEventBinding`. Binding freshness is metadata authority, not media expiry;
  it is excluded from saved JSON. Cricket title context also fences ordinal/Test
  day reuse. `FixtureStreamDiscoveryIndex` owns bounded in-memory outcome state,
  generation cancellation, fresh bound-session reuse and separate preflight caps.
  Registry disable awaits invalidation; manual lookup bypasses negative results.
- Home's foreground optional-provider preflight does not start players or run
  during viewing. Fresh candidates feed existing timed single-stream actions;
  they never establish LIVE or decoded playback. Shared/Score808 stay on demand.
- Single-stream CS/AS descriptor renewal preserves selected identity and obtains
  fresh admitted transport fields within existing retry budgets. Typed causal
  failure facts avoid status-string retry heuristics. Other player contexts
  retain the legacy policy. No device/release follows from this source candidate.
  See `testing/fotty-discovery-catalog-2026-10-28/README.md` for verification/limits.

## Staged Fotty2.5 source ownership — 24 October 2026

- Core UI: `HomeOverviewLayout` composes bounded featured/upcoming content while
  flattened catalog rows stay lazy. `HomeMatchGroupShape` joins row surfaces;
  `MatchdayScopeControl`, `SettingsAccessoryLayout` and `SinglePlayerMatchIdentity`
  isolate presentation from existing models. Joined source styling is explicitly
  single-only; passive/multi consumers retain defaults. UI renders are component
  evidence, not installed175 or physical-device acceptance. See the UI receipt.
- `CuratedStreamSourceCatalog` in `StreamPlugin.swift` is the finite registration,
  manifest/provider binding, default, label, scope and typed dispatch authority.
  Registry, source matching, optional lookup, Hybrid and five add-on adapters use
  it. Each adapter still owns its schema, exact match and guarded media admission.
- `StreamDiscoveryCoordinator.collect` optionally publishes serialized append-only
  choice snapshots; its final aggregate outcome, fair opportunities and common
  deadline remain. `LiveStreamResolver` filters current enabled families before
  forwarding incremental choices; aggregate API remains compatible.
- `ViewingSessionCoordinator.watchSingle` owns Home/Matchday's task and generation.
  It rechecks the local catalog/status, including tombstones, without adding a
  network preflight. `pendingSingleEvent` drives the existing sport-aware bottom
  panel; first mount clears that feedback and later alternatives append to the
  exact single model. Navigation cancels only unpresented lookup. Opening Sources,
  appending rows, minimizing or filtering never reloads the current source/item.
- `LivePlayerViewModel.appendDiscoveredSingleSessions` requires explicit single
  ranking/context, exact matchID, active owner and delivery+header dedup; current
  order/index/attempt stay unchanged. `LiveStreamSelectorSheet` uses original
  indices and finite reviewed group names, not remote metadata as UI authority.
- `CatalogInlineContextState` fences expansion to the row's identity. Existing
  full Details and Save/Remind policies remain authoritative. Native contracts:
  `docs/audit/Fotty-2.5-Native-Experience.md`.
- Home's cooperative dedup shares its original two-pass accumulator with sync
  callers, yielding at most32 rows per batch and publishing only complete current
  packets. Search preparation and query results have separate structured task
  keys. `FottyImagePipeline` keeps shared-request cancellation plus2s/256-entry
  exact-URL failure cooldown, checking valid warm cache before retry state.
- These are staged sources, not installed175 behavior or physical qualification.
  See `docs/audit/Fotty-2.5-Implementation-2026-10-24.md` for measured limits.

## Staged StreamViX and AS cricket source contracts 24 October 2026

- `StreamVixTimingPolicy` owns strict original full-date GMT parsing and only the
  unique documented Rome reinterpretation. Canonical UTC also works if upstream
  fixes its timestamp; publisher display/ID still uses its actual Rome rendering.
  Ambiguous/nonexistent local clocks never establish a correction.
- `StreamVixSportsAddonClient` joins original schedule PL/UCL facts, exact shared
  participants/date/squad, literal catalog target and meta agreement. Canonical
  alias/conflicting siblings and truncated-ID collisions fail closed. It neither
  changes official fixtures nor infers LIVE. Fixed bounded metadata routes/cache
  generations precede fresh reviewed delivery admission and the existing relay.
  Separate bundled default-OFF `streamvix`/SV1–SV6 owns Hybrid discovery, optional
  PL/UCL official-fixture eligibility and finite hashed local attribution.
- `PlavioSportsAddonClient.CatalogProfile` separates football/cricket advertised
  catalogs, cache generations and matching. Cricket owns exact UTC, known T20I/
  Test Day1, ordinal/day/squad fences; no football publisher-ID bridge or inferred
  later Test-day start. Existing delivery admission remains unchanged.
- These are source-only additions beyond installed174:297 focused units pass,
  three physical tests skip. AS cricket and SV still need actual live Jet90s/
  programme/normal-picker/control proof. No player/ranking/FPL/multi-stream change.

## Flix source integration private174 24 October 2026

- `FlixStreamsAddonClient` owns the fixed public manifest, TV event catalog,
  soccer/cricket genre pages0/40/80 and stream DTO. All pages complete before
  `ReviewedSportsFixtureMatcher` selects exact participants/squad/sport/UTC;
  later malformed or conflicting siblings retain veto authority. Search is not
  used because the observed service ignores its query. No fixture or LIVE insertion.
- Reviewed default-video hints and the single video entry corroborate, rather
  than override, catalog target and explicit UTC date/time. New routing/header/
  DRM authority is rejected. FS1–FS6 owns a separate default-OFF bundled module,
  Hybrid lane, official-fixture eligibility and finite local `fs_` attribution.
- Headerless same-origin HTTPS443 HLS requires the existing guarded relay, with
  no native origin/playlist profile or transport exception. Player, recent-single
  ranking, FPL and multi-stream engines are unchanged by this integration.
- The current test-only shared canary requires90s advancing decoded progress.
  Jet174 FS1/FS2 currently return upstream502/zero frames; another discovery
  fails before media. FS stays OFF; normal picker and PL/UCL/cricket gates stay
  open. See release174; staged plumbing is not native playback qualification.

## Additional NHL source and complete-manifest handling private169, 23 October 2026

- `CNCSportsAddonClient` owns the fixed CNCVerse LivXow manifest/catalog/meta/
  stream contract, opaque identifiers and bounded generation-fenced caches. Catalog
  names preselect at most two metadata requests; explicit NHL/sport/UTC date and
  exact participants/qualifiers must pass `ReviewedSportsFixtureMatcher` before
  streams. Malformed/conflicting siblings remain vetoes. No fixture insertion,
  opaque-ID decoding, generic-channel matching or LIVE inference is introduced.
- CNC also has a source-local PlayZTV WBBL lane. It requires a verified official
  T20 WBBL fixture, exact dated UTC metadata and women’s team pair; terminal and
  conflicting fixtures are excluded. Its separate catalog cache/failure cannot
  erase NHL evidence. Normal optional-fixture eligibility, Watch and descriptor
  renewal reuse CNC identity and opt-in. The reviewed HTTPS Rutube signature/path
  and UA-only contract uses the guarded relay; it does not inherit NHL startup
  exceptions. Physical qualification is recorded separately in
  `testing/fotty242-new-sources/README.md`; implementation is not a live pass.
- The fifth bundled module owns default-OFF `cncsports`/LS1–LS6. Existing registry,
  optional official-fixture lookup, Hybrid parallel discovery, health/source
  grouping and finite local receipts preserve separate attribution and recheck
  opt-in after awaits. The NHL lane admits only the reviewed host7 HTTPS443 HLS
  path and exact public header contract; failed NBA/host4 is rejected. Required relay intent
  uses the existing transport checks, with no origin/port/redirect exemption.
- `LocalStreamProxyPolicy` suppresses Range/If-Range/representation preconditions
  only for known m3u8 fetches. `LocalStreamProxy` requires a full200/noContentRange
  playlist before rewriting or HEAD handling; rewritten output owns its byte
  length and strips stale origin validators. Ordinary segment ranges stay intact;
  partial/conditional MIME-only manifests fail without hidden retries.
- `NativePlaybackStartupDeadline.Budget` owns immutable20s default versus30s for
  fully revalidated LS ordinary-single sessions. Handoff/pair/default clocks and
  cancellation/Pause/ownership/fatal guards stay unchanged; no buffer/stall change.
- Shared test-only `ReviewedAddonPhysicalCanary` uses real pixel buffers and a
  visible AVPlayerLayer through normal source/relay preparation. CNC requires90s
  advancing hold; Plavio keeps its earlier20s contract. A synthetic physical
  throughput fixture does not contact third parties or prove real-source health.
- Jet169's exact NHL canary and ordinary LS1 source-picker/fullscreen/control
  check pass; AS and failed NBA remain excluded. This is sampled delivery evidence,
  not every NHL fixture, independent upstream resilience, licensing or PiP proof.

## Additional-source qualification private168, 23 October 2026

- `PlavioSportsAddonClient` is a fixed, reviewed Stremio adapter, not arbitrary
  add-on installation or a fixture authority. It admits only explicitly dated
  football rows and the narrow reviewed HTTPS443 HLS delivery contract. Metadata
  requests/caches/bytes/redirects are bounded; malformed siblings retain conflict
  evidence. Unsupported transports, placeholders and changed header contracts fail.
- `ReviewedSportsFixtureMatcher` owns pure two-team/sport/date/squad identity and
  duplicate/effective-target conflict vetoes. CS and Plavio keep separate schema,
  metadata transport/cache and delivery admission; extracting matching does not
  broaden CS delivery authority.
- The fourth bundled module exposes opaque AS1–AS6 choices independently from CS,
  default OFF. `HybridStreamProvider` collects the optional lane within the existing
  18s budget and rechecks opt-in after suspension/completion. Provider matching,
  health grouping, source labels and finite local receipts retain separate AS
  attribution, including when another family succeeds. Signed URLs are not logs.
- A headerless AS session retains `requiresGuardedRelay` through source/session
  copies and Codable; it forces the existing guarded relay, not a new origin/port/
  redirect exemption. Native playback/proxy policy and FPL/Watch Two are unchanged.
- This is staged integration, not a certified working fallback: the real Jet
  decoder canary failed with no video frames despite successful media responses.
  The exact source subsequently became unavailable. AS stays OFF; shared ancestry
  with sfly/Leaf/Highfly is not proven independent supply. See release168.

## Single-player playback foundations private163 19 October 2026

- Private164 adds single source/attempt startup evidence admission independent
  of interval decoded-stage arrival: repeated Web owners retain all recovery
  effects but cannot inflate initial health/latency. Actual native adoption owns
  its separate handoff receipt. Existing resume/watchdog samples may record first
  ready-surface progress after observer cancellation, without another timer/Play.
- The exact native item/attempt owns a local background-fatal observation. It
  persists once, recovers once on foreground under current intent, and retires on
  verified progress after its latest fatal boundary, including a paused visit.
  Replacement clears it. Fullscreen callbacks use effective model background
  state; finite per-presentation edges remain local and bounded. No new uploader.
- CS cache publication is generation-fenced; empty TTL15s/populated120s and
  rollback rejection distinguish temporary emptiness from current data. Finite
  discovery outcomes separate no exact fixture, no raw streams and no admitted
  delivery without changing exact matching or transport admission. See release164.
- `MediaModels.StreamPlaybackContract` separates declared endpoint/container from
  bounded ephemeral MIME/prefix evidence. Probe evidence is not Codable and does
  not mint codec/PiP support, delivery trust or a new source identity. Validator
  consumers use typed validity/evidence; playlist markers inside HTML are rejected.
- `NativePlaybackPreparation` owns scoped delivery/item factories and prepared
  candidate data, not Play/intent/audio authority. Explicit single handoff first
  constructs cookie-scoped delivery and validates the same URL AVPlayer receives;
  failure retains the original Web owner and retires only the failed candidate.
- `LocalStreamProxy` retains a32-entry memory-only request ring under existing
  connection limits: opaque identities, finite phases/outcomes/status and monotonic
  duration/age. Actual content processing precedes completion. Exact cancellation/
  deadline fences and atomic last-failure/request snapshots feed bounded local
  scalar diagnostics. Old failure correlation is not automatically terminal cause.
- `LiveSourceHealthStore` caches decoded state by exact Defaults bytes on its
  existing serial queue. External replacement/removal invalidates; malformed
  data is not erased. Writes/migration stay coherent. `HomeProjectionCoordinator`
  exposes CatalogDeduplication/CatalogDiscovery child signposts without moving
  publication or cancellation authority.
- `NativeFullscreenSession` is now irreversibly retired before admitted load,
  attempt/player replacement or cleanup. Its exact weak host callback synchronously
  revokes observations/delegate and detaches AVKit's borrowed player before UIKit
  dismissal, even when covered SwiftUI updates are deferred. A retired lease cannot
  re-enable transport or affect its successor. Retained-PiP closing/restoring stays
  on its same lease; retirement adds no transport command. See release163.
- Owner priority: stable single playback and source reliability first. Existing
  Watch Two architecture below is retained history/current code, not an active
  priority or completed physical acceptance claim.

## Retained viewing and core discovery private160 16 October 2026

- `Features/Player/ViewingSessionCoordinator` owns scene panes, identity-safe
  reuse, presentation, source lookup cancellation, one audio/remote/PiP owner,
  explicit Stop and Handoff intent. Prepared selections retain the common
  terminal/conflict guards. Source completion rechecks the current catalog.
  The full searchable/sport-filtered second-match picker prepares in cancellable
  batches. Change Match resolves first, then retires only its current target;
  survivor/selection generations, fixture aliases and fullscreen/PiP guards fence
  replacement. Per-pane controls use stable pane identities even after Swap.
- `ViewingSessionShell` holds each actual media view in one stable root ForEach.
  `ViewingSurfaceSlot` reports layout only; full/compact/Focus/Watch Two move and
  clip the retained AVPlayerLayer/WKWebView instead of creating another player.
  `ViewingSceneLease` stops only on its actual window scene's disconnect, not
  backgrounding, a Details cover or marker detachment.
- Existing `LivePlayerViewModel`/native/WebKit/proxy owners retain transport and
  source-safety authority. Per-model UUIDs fence lock-screen commands; secondary
  native PiP is gated. Actual system PiP claims reconcile audio after transient
  old/new overlap. Explicit pause and item/attempt identity are not presentation.
- `NativeFullscreenPlayback` presents an actual AVPlayerViewController from the
  retained marker's own window scene. Its presentation lease borrows the existing
  player/item/source/attempt; no URL, load, replacement, seek or autoplay is added.
  Inline rendering/PiP detaches while AVKit owns fullscreen, without destroying
  the retained pane. Exact-owner guards retire callbacks; Apple Close returns
  inline, preserving pause. AVKit owns its fullscreen PiP; Focus remains separate.
- `NativeFullscreenSession` separates dismissal transition from retained-PiP
  transport admission. A locked UUID epoch ticket crosses KVO's actor hop;
  stale/pre-transition observations cannot acquire the later control lease.
- `NativePlayerAudioIsolation` in `LivePlaybackPolicy.swift` serializes public
  iOS27 per-player disconnect/reconnect setters, retaining exact player/item and
  revision ACKs across uncancellable platform completions. Candidate probing
  makes no shared audio calls. Adoption stays muted through exact Web retirement;
  selected current intent activates/reconnects before unmuting. Pane revocation
  disconnects before a Web audio transfer. This does not establish mixed-engine
  coexistence;154 mixed and156 Web/Web physical tests fail audio-switch acceptance.
- 155 native candidate discovery only caches; explicit single Use Native Player
  owns suspension ACK, candidate preparation/decode and exact old-Web retirement
  before selected native audio. Viewing context fences original compatible routes
  across load/source/retry/fallback; Watch Two does not run passive native probes.
  Explicit native-retirement Retry renews a failed barrier, remaining fail-closed.
- 157 `PreparedNativeWatchTwoPlayback` captures exact model/source/request/intent,
  player/item, prepared delivery/relay and disconnected audio owner. One coordinator
  transaction preflights both paused candidates, removes both actual Web surfaces,
  awaits both exact teardown receipts, then adopts/authorizes/starts the pair.
  Intent epochs include Pause→Play; current scene/PiP/fullscreen/generation fences
  apply after waits. Missing preflight preserves both Web owners. After retirement,
  failure cannot revive only one Web pane. Native pair retry retains native route
  and scoped delivery. Owner accepted brief conversion restart; real positive
  Web/Web conversion remains physically unqualified despite passing policy tests.
- 158 builds the scoped handoff relay before HLS validation, validating the same
  URL/delivery AVPlayer will use. Typed preflight stages/outcomes persist locally.
 159 adds the exact candidate's bounded error chain/error-log HLS category and
  its own relay failure stage/status/age. No raw URL/comment/credential/userInfo
  is persisted. Last relay/log errors are not automatically the terminal cause.
- 160 accepted native AVKit Play transitions a waiting item to existing recovering
  state and rearms foreground watchdog/resume validation without extra transport
  commands. The injected timing dependency keeps the live eight-second deadline;
  Pause cancels and exact player/item/source/request/presentation guards reject
  stale commands. Background reload policy remains unchanged. Current native
  fullscreen/PiP visual passes are in release160, with separate pair HLS failures.
- 156 `LiveWebEmbedPlayerView` acknowledges managed mute only from the actual
  decoded video/audio owner with exact attempt/document/request/generation and
  original deadline. Child forwarding is not parent-evaluation success. Startup
  desired requests survive until exact decode, never a replacement document.
  `LivePlayerViewModel` retains aggregate unresolved per-attempt revocation tickets
  through replacement/removal/re-enable; exact old teardown settles old tickets.
  `ViewingSessionCoordinator` captures all waits before cleanup and grants the new
  audio owner only after successful current barriers. Disabled single panes remain
  managed until released. DOM mute ACK is not platform-session retirement.
- Native PiP Restore traverses the legitimate same-window presented chain while
  retaining the exact borrowed controller/player/item/source/request lease. No
  presentation callback loads/seeks/forces Play.156 retained-Done and Home Restore
  have bounded visual proof; later native media failure/Watch Two remain separate.
- `FottyDefaultsWriteBuffer` in `FottyLogger.swift` separates quality/performance
  in-memory mutation from Defaults persistence. Per-key revision overlays keep
  reentrant reads current; the single drainer calls Foundation only after all
  store/buffer locks are released. Causal diagnostics remain local, scalar-only
  and capped; actual platform activation is distinct from preparation duration.
- `ViewingPlanPolicy` filters the existing atomic Matchday projection into an
  optional anchored 90-minute/two-hour/Until midnight window. Full Matchday is
  the default; the legacy raw evening value remains wire-compatible. It estimates
  no match finish, invents no fixture and adds no polling owner. Home stays discovery.
- Whole-sport interests are validated local intent alongside existing team and
  league follows. Home selection/cache signatures include exact canonical sport
  IDs. Home upcoming presentation equalizes availability only for followed
  upcoming items in personalized mode; live/broad source rank remains unchanged.
- `CatalogEventDetailsView` and native catalog More actions own details/save,
  leaving watch admission and reminder consent with the existing policies.
  Search local recent queries are bounded and recorded only for explicit actions.
- `Core/Continuity` contains source-free, bounded sports Handoff and an opt-in
  KVS intent journal, durable verified application receipts, pending-plan retry
  and canonical wire equality. FPL, reminders/consent, history, source URLs,
  headers and cookies are excluded. KVS is not an encrypted vault or delivery ACK.
  Whole-sport intents use disjoint `fotty.sport.intent.v1.` keys so older sports
  sync consumers do not parse an unsupported intent kind. This does not clear
  the separately open real-account bootstrap/delivery gate.
- `SportsWidgetSnapshot` is the deliberate Foundation-only shared app/extension
  source. The app writes bounded saved-match snapshots and cached badge files
  to `group.com.jelani.Fotty.sports`; WidgetKit owns refresh budgets and expiry.
  Current football score/LIVE is omitted without a per-fixture receipt accessor.
  Existing FPL widget implementation remains unchanged. Apple profile activation
  and physical/cross-device acceptance are separate from these source boundaries.

## Source ownership after the 11 October stabilization passes

- `Core/Networking/CommunitySportsAddonClient.swift` decodes the opt-in CS
  add-on and admits public Referer/Origin/User-Agent delivery hints into native
  `PlaybackSession.requiredHeaders`. Exact unambiguous query provenance,
  existing HTTPS origin/path policy and bounded header validation remain
  authoritative; web routes cannot discard requirements. The existing local
  proxy retains header forwarding/media ownership. No auth or arbitrary hints.
  `LocalStreamProxyOriginProfile` grants the owner-approved exact CS HTTPS8443
  origin only after fresh reviewed native/DaddyLive contract admission. Runtime
  URL/header bindings reach each selected single/two-match owner; Codable and
  Web handoff exclude this authority. Default443, public/mixed-DNS, credential,
  TLS, atomic manifest and redirect fences remain. Source/runtime tests have
  distinct receipts; source labels alone do not establish this port contract.
- `PlayerDiagnosticService` and `PlaybackPreparationDiagnostic` own finite
  local stage/reason/domain/code/trigger classifications, not raw descriptions,
  provider URLs or uploaded telemetry. Fatal AVPlayerItem errors outrank older
  log entries; preparation/relay merges require the exact current attempt.
  Single and Watch Two retain their existing native/Web/PiP transport owners.
- `tools/watchdog` and `web/workers/watchdog` own the active observation-only
  service: bounded admitted metadata/fact checks, durable quiet incidents,
  collector leases, recovery fences and independently bounded GitHub delivery.
  Protected main23416ce/Worker de00d85f receipts are in the service document.
  The playback Worker, accepted fixture registries and native ring remain
  separate owners. No repair executor, paid AI or central telemetry is enabled.
- `Core/Images/FottyImagePipeline.swift` owns the shared URL cache, request
  coalescing, bounded transport, decode scheduler and decoder. The selection
  policy and candidate-keyed `CachedAsyncImage` view live in
  `Design/CachedAsyncImage.swift`; `Design/Components.swift` retains badge windows
  and unrelated shared visual components. Moved declarations are unchanged.
- `HomeCatalogProjectionPolicies.swift` owns existing selection/timing policies,
  revision keys, personalization cache, cooperative checkpoint and ranking
  contracts. `CatalogEventDetailsView.swift` owns the existing Details view and
  presentation; `MomentumPulse.swift` owns its independent decorative view.
  These live under `Features/Dashboard`. `HomeProjectionCoordinator.swift` now
  owns one immutable base/scope packet, exact input keys, facts-cache reuse and
  generation-fenced atomic publication. Its cancellable stages and sixteen-row
  batches stay on MainActor; scope changes retain the accepted base revision and
  pending base work derives the latest scope immediately before publication.
  `SportsDashboardView` retains its structured `.task`, filters, navigation,
  modal lifecycle and single/two-match Watch commands. No new fetch owner or UI.
- `Core/Media/MediaAudioSessionOwner.swift` serializes configuration/activation
  with waiter-specific cancellation and media-services reset epochs. Its real
  backend confines AVAudioSession calls to a serial queue, using SDK27 async
  activation when available and off-main blocking activation on the supported
  older runtime. Launch, route and navigation preparation are configuration-only.
  Native owners await activation before Play and recheck attempt, source, player,
  item, user intent, lifecycle permission and terminal errors. Exhaustion revokes
  pending preparation; fresh Play cannot publish a failed attempt as playing.
  Explicit Retry keeps its new-attempt path. PiP preparation is separately fenced
  and cannot cancel pending transport intent. AVPlayer, WebKit and PiP remain
  owned by their existing native players; errors remain local, bounded scalar
  diagnostics rather than new provider failures or uploaded telemetry.
- The four explicit native target inventories are checked by
  `tools/check_native_source_membership.py`, including the deliberate shared
  activity attributes source. `tools/ios-ci.sh` runs this guard before logic and
  unsigned iOS checks. File moves do not imply a new binary or visual acceptance.
- Source recovery, onboarding, checked invariants and remaining cleanup seams
  are in `docs/Fotty-Developer-Handoff.md`. Private138/shared121 receipts and
  earlier installed128 evidence remain separate and dated.

## Terminal receipts and shared artwork in private128

- `OfficialFPLScoreProvider` carries recent explicit final facts and stable-code
  PL crests. `FootballRepository` owns typed live/schedule observations separately
  from attempts/TTL, raw schedule identity and receipt-aware Details enrichment.
- `FootballScoreSnapshotPolicy` owns dated terminal retention and per-row active
  receipts. `LiveScoreService` publishes using completion time; stale/failed or
  empty active observations lose authority without fabricated final. Private
  notification baselines survive transient unknown/empty feeds independently.
- Home's terminal index retains accepted identities before playable catalog
  removal/deduplication. Existing fixture matching verifies date, squad and
  competition; Matchday, Watch and reminders use the common terminal policy.
- `FottyImageSelectionPolicy` in `Design/CachedAsyncImage.swift` owns ordered candidate loads,
  primary-only immediate cache, cancellation and candidate-keyed loaded state.
  Cache warmth cannot suppress a viable higher-priority badge. The existing
  URL-keyed pipeline, bounded response reader and decode permits retain transport
  ownership. Official-artwork merge preserves schedule IDs/names; guarded Home
  precedence cannot borrow an unrelated dated PL/squad identity.
- Final binary, current-source tests, native inspection and limits are in
  `docs/releases/Fotty-2.0.1-128.md`; no Worker/TestFlight rollout is implied.

## Native performance and request ownership in private build 127

- `FottyBoundedHTTPClient` owns bounded response reading, hard deadline
  cancellation and redirect admission for its native callers. Catalog ingestion
  distinguishes a valid empty feed from malformed data; CS redirects are checked
  before the next request, not merely after URLSession follows them.
- `MatchListViewModel` publishes provider and fixture lanes independently, skips
  unchanged/rejected snapshot merges and preserves accepted receipt ownership.
  `SportsFixtureCatalog` prepares kickoff and competition identity once per merge.
- Home publishes one revision-keyed projection packet. Its cooperative stages and
  batches stay on MainActor because event/service values are not Sendable.
  `HomeSportsSearch` shares synchronous entry semantics with a cancellable batched
  builder; `SearchView` publishes current index/results/presentations together.
- Matchday uses the same cancellable MainActor checkpoints and exact request-key
  guards before atomic publication. Its flattened heading/grid-row entries give
  the lazy stack row-level ownership without changing order, reminders or reasons.
- Shared image decoding has two permits with waiter-specific cancellation.
  Badge receipt expiry is checked while the service remains resident. Quality
  persistence caches unchanged serialized data, and backup import owns bounded
  reading, security-scoped access and cancellation independently of presentation.
- The native player owns decoded-frame proof and attempt-scoped handoff; Watch
  Two owns independent panes, viable audio selection and bounded native retry.
  The optional physical-test QoE hook is pull-only, scalar and URL-free. It does
  not expose WebKit network internals, add upload or change production quality caps.
- Verification and remaining physical limits: `docs/releases/Fotty-2.0.1-127.md`.

## Owner-only TestFlight participation (local tool after build 111)

- `owner-tools/testflight-usage-sync/scripts/app-store-connect.mjs` owns the
  read-only Apple data contract: a ten-minute ES256 JWT, the app-filtered beta
  tester roster, tester-grouped P7D/P30D usage pages, exact tester-ID joins and
  factual participation classification. Pagination is bounded and restricted to
  `api.appstoreconnect.apple.com/v1`; API errors never print credentials or
  tester response bodies.
- `owner-tools/testflight-usage-sync/scripts/fetch-usage.mjs` writes real names,
  emails and usage only to a mode-0600, Git-ignored `.local` snapshot.
  `build-live.mjs` temporarily supplies that snapshot to the verified Data App
  builder and restores the tracked fixture in `finally`; the private `dist`
  remains ignored and must be served only on loopback.
- The active least-privilege team key is stored mode 0600 outside the repository.
  An ignored mode-0700 `.local/refresh-dashboard.sh` supplies only the local key
  path/account identifiers and runs fetch plus build; no credential or tester
  identity enters tracked source.
- `owner-tools/testflight-usage-dashboard` owns the local presentation. Its
  source-backed cards and roster share the active Participation/Platform scope.
  Tracked data is an explicit synthetic `example.invalid` fixture. The dashboard
  discloses that Apple sessions do not identify Fotty features, session duration
  or successful playback.
- This tool has no runtime path into the iOS/iPadOS target, Worker or TestFlight
  build. Adding in-app telemetry, uploading local diagnostics, publishing the
  dashboard, or creating/revoking credentials remains a separate decision.

## Optional CS playback lane (local source after 93)

- `CommunitySportsAddonClient` is a bounded Stremio-protocol adapter. It caches
  the reviewed manifest and sport catalog briefly, falls back to the add-on's
  Live catalog only under the same admission policy, and requests a stream list
  only after exact sport, unordered two-team identity and kickoff matching.
  Duplicate exact IDs conflict; undated/channel, youth/senior and one-team
  matches cannot substitute for the Fotty fixture.
- The adapter accepts only HTTPS on the manifest's exact origin and only the
  reviewed `/api/manifest` native-HLS proxy or `/watch` web route. It bounds
  payload/count/query sizes, rejects credentials, cross-origin/arbitrary paths
  and P2P/Ace shapes, deduplicates by full delivery identity and returns at most
  six options labeled `CS1` through `CS6`.
- `LiveStreamResolver` runs CS independently beside shared-catalog and direct
  Score808 lanes under `StreamDiscoveryCoordinator`'s one 18-second attempt.
  `StreamPluginRegistry` ships the module disabled by default; Settings owns the
  opt-in. `LiveSourceHealthStore` groups opaque CS numbers into one family while
  preserving source-specific URLs, and the player still determines native vs
  web ownership from the admitted session contract.
- This lane is extra playback coverage only. It cannot create Home/Matchday
  rows, change competition labels, prove availability or bypass physical-device
  decoded-playback acceptance.

## Confidence and temporal correctness (local source after 93)

- `FottyQualityStore.ownerStatusSnapshot` filters retained quality evidence by
  exact app version/build before presentation. The hidden Owner Status sheet is
  revealed by seven taps on the Settings version row; it stays off Home and
  describes local/missing evidence honestly. Older-build records are counted but
  excluded from current summaries. No upload or server-health claim is added.
- Playback's existing feedback route seeds an empty report with safe context but
  never replaces an unfinished tester draft. Diagnostics remain off by default.
- FPL deadline notifications use absolute UTC components including seconds and a
  typed `fpl-deadline` route. `MatchNavigationStore` returns notification taps to
  the FPL gameweek workspace and clears competing match routes.
- `FootballMatchAlertTransitionPolicy` recognizes kickoff only from scheduled or
  timed to in-play. Halftime, suspension and provider corrections cannot announce
  another kickoff. Full simulator-free Catalyst/iOS Release verification passes;
  physical delivery, tap routing and visual acceptance remain separate gates.

## Field evidence and source recovery (local source after 93)

- `FottyPerformanceStore` in `FottyLogger.swift` retains only the latest two
  dated scalar summaries (scroll and hangs), <=2 KiB each, for up to 14 days.
  The MetricKit subscriber preserves reporting windows, reported build and
  mixed-version status; missing is unavailable, not zero. No raw payloads.
- `FottyQualityStore` incorporates those summaries into its existing explicit
  export and clears them alongside quality events. A clear cutoff rejects late
  pre-clear reports. `FottyFeedbackView` still starts with diagnostics off,
  previews the snapshot and never treats copying/sharing as confirmed receipt.
- `tools/release_source_snapshot.py` creates/verifies one-root-commit recovery
  bundles without changing the active Git index or old ancestry. Its `compare`
  gate checks working source against the saved manifest before a future upload.
  The build-93 local capture is post-release, not historical archive provenance.
- Procedures and open gates: `docs/operations/SOURCE-RECOVERY.md`,
  `docs/beta/BUILD-93-QUALIFICATION.md` and
  `docs/audit/Fotty-Field-Readiness-2026-09-09.md`. The owner-approved private
  `jetboss/fotty-recovery` now stores the verified bundle/receipt and restore
  instructions; a fresh remote restore matches all 645 files. Actions is off.
  This is manual snapshot storage, not an app remote, continuous sync or release.

## Home clock and lazy row continuity (source follow-up to build 90)

- `SportsDashboardView` flattens its changing section headers and fixture rows
  into one lazy identity sequence. `HomeSportsDiscovery.DisplayRow` identifies
  section, ordered membership and column count; routine clock ticks retain IDs.
  There is no whole-scroll-container reset or eager catalog grid.
- The Home projection clock restarts on activation/catalog change and wakes at
  kickoff, not just minute boundaries. `HomeDiscoveryRow` no longer injects its
  cached item timestamp into `MatchStartControls`; visible controls retain their
  own lightweight timeline. Fixed clocks are limited to tests/previews.
- `MatchListViewModel.refreshIfNeeded` throttles automatic attempts for 90 seconds
  and coalesces active requests. Cancellation permits immediate retry. Receipts
  still advance only on an accepted response. Age/cache-only copy is silent;
  failure, partial data and independently stale CPL authority remain visible.
- The deterministic Catalyst clock is process-local and network-free. It must
  survive Home view recreation without modifying real preferences. See
  `docs/audit/Fotty-Home-Clock-2026-09-08.md` for evidence and delivery boundaries.

## Optional Matchday clash hints (source follow-up to build 89)

- `MatchdayPreferences` in `ArenaModels.swift` owns the off-by-default
  `fotty.matchday.showKickoffClashes` preference. Settings exposes it under
  Preferences, separate from notification permissions and kickoff reminders.
- `ArenaDiscoveryView` gates both the banner and cached detection. The preference
  is part of `MatchdayProjectionKey`, so opting in/out refreshes the projection
  without changing catalog refresh, saved matches, ranking or reminders.
- Private-backup Preferences carries optional `showKickoffClashes`; older backups
  decode and restore with the hint off. Backup format version remains compatible.

## Adaptive wide-window presentation (private build 89)

- `FottyLayoutPolicy` in `Design/Theme.swift` uses actual available width, with a
  1000-point two-column threshold and a single-column accessibility-text fallback.
  `MainTabView.fottyAdaptiveWindow` publishes only breakpoint changes. Search
  measures its own sheet boundary. No orientation, refresh or data owner changes.
- Home, full lineup, Matchday and Search use stable, ordered groups of at most
  two fixture cards per wide row. Phone/narrow windows keep one card per row.
  Tablet sports tiles use a larger scaled minimum and balance complete rows;
  ten sports at 1180 points form five plus five. Phone overflow remains separate.
- Settings and FPL use `AnyLayout` to rearrange existing controls rather than
  maintaining separate tablet screens. FPL keeps the same workspace session and
  scroll container; the manager rail is 300 points at wide sizes. The full FPL
  workspace-tab label is hit-testable, including space around its icon/text.
- The Catalyst wide-window journey performs real mouse-driven resizing, checks
  FPL/Settings column positions and verifies selected-tool continuity after
  shrinking. Breakpoint, fixture-order and balanced-grid unit/render tests cover
  narrow, landscape, light/dark and accessibility-size cases. These checks do not
  replace physical iPad visual acceptance.

## FPL replacement and release qualification (internal TestFlight build 81)

- `FPLSquadPitchView.replacePlayerInSquad` rejects an unchanged element and any
  element already present in current picks before mutating the saved draft.
- `FPLAdvisorViewModel.acceptsWorkspaceMutation` bypasses live manager/season
  freshness only for the explicit deterministic automated fixture. Production
  workspaces retain the real identity guard.
- Stable accessibility identifiers cover squad rows/errors, Home interests,
  sport/event state and match-start controls. `FottyNavigationUITests` verifies
  rejection, accessible feedback, valid replacement and navigation persistence;
  release-gate failures retain focused evidence instead of permanent artifacts.

## Champions League schedule/catalog projection (protected monitor and internal TestFlight build 80)

- `AnalyticalDataEngine.officialScheduleEvents` converts verified football
  schedule matches into source-free catalog rows. `SportsDashboardView` and
  `ArenaDiscoveryView` project Champions League rows with the live provider
  catalog, so Home/Search/My Matchday can show official fixtures before stream
  publication without creating a Watch promise.
- `AnalyticalDataEngine.deduplicateMatches` first quarantines contradictory
  same-ID rows, then merges different IDs only on exact sport/kickoff and two
  reviewed team identities. It keeps a source-backed representative and unions
  concrete source descriptors.
- `shared/reference-data/football-competitions-2026-27.json` remains the one
  reviewed roster/alias source for generated Swift and TypeScript catalogs.
  `tools/audit-ucl-readiness.mjs` reconciles its identities against the official
  schedule, provider mirrors and optional Worker variant resolution. The daily
  provider workflow reports the next 72 hours; `ucl-match-window.yml` runs every
  30 minutes in UCL match windows and enforces T−30 through T+180. Its policy
  includes Admin/PPV and rejects synthetic Legacy fallback responses.

## Fixture freshness and authority (production Worker and internal build 75)

### App-wide fixture integration (cleared cloud subset active; 1 October 2026)

`sports-fixture-sources.mjs` / `sports-fixture-event-sources.mjs` locally define 26 source
groups and 31 competition scopes; 24 adapters are implemented, boxing/PDC remain
explicit gaps. `sports-fixture-policy.mjs` admits bounded UTC/identity/status facts;
`sports-fixture-registry.mjs` isolates durable due times and last-good receipts by
source group. `/api/sports/fixtures` aggregates partial coverage without turning
failures into fresh/empty data. The existing cron checks adaptive five-minute /
15-minute / four-hour due times; cricket remains separately owned.

`SportsFixtureCatalog.swift` validates/cache-merges per competition into
`MatchListViewModel`, preserves optional cache/saved metadata and keeps fixture
truth separate from current provider streams. Typed sessions/tournaments/cards
do not invent opponents. Identity/time corrections carry persistent confirmation
receipts; saved reminders retain stable fixture IDs. Current scores/playback
owners and the dedicated cricket route are unchanged.

`tools/audit-sports-fixtures*.mjs` and the published hourly workflow validate source
health and reconcile MLB/NHL/WNBA against newly fetched schedules. That is
same-publisher reconciliation, not independent-publisher proof. General activation
is one; website and WNBA flags remain zero. Six football leagues, MLB and NHL have accepted
production receipts. WNBA's league CDN returns HTML to the actual edge runtime;
its deferred descriptor prevents GET/cron/DO collection without erasing durable
state. Boxing/darts and gated website sources remain explicit gaps. Both adapter
families use manual redirect rejection; actual-workerd regressions cover transport
and source gates. Deployed football-data now covers six leagues with one bulk
request, replacing four duplicate gated adapters: eight eligible scopes / 23
remaining gaps under protected PR35 / source4. Scope/pending receipts and persisted
attempted-scope backoff protect migration from older PL/CL-only durable state.
The owner iPad112 consumer reception/retention gate passed separately from
TestFlight and predates this expansion. Later local native fixes are not installed. Local legacy
`FootballService` / `FootballRepository` cache genuine empty schedules without
unconfigured premium fanout and preserve proxy/cancellation errors.
See `docs/operations/Sports-Fixture-Service.md` for contracts and activation gates.

#### Local all-sport repair follow-up (6 October 2026; not deployed/installed)

Sports admission now stages per-record isolation with optional schema1
`source.verification` markers. Original held facts/receipts and per-competition
failure evidence remain; unaffected rows advance. Confirmation keys are per
fixture. Semantic duplicate replacements and football-data publisher IDs moving
competition are held, not silently merged or migrated. Pending dates are bounded
internal polling evidence only. Partial HTTP200 requires validated verified rows;
transport/schema/scope errors remain full-source barriers. Unavailable verified
rows expire after30minutes. Monitor transition/refresh-required findings retain
same-publisher provenance, grace and identical-evidence repetition.

Native cache acceptance stages matching marker/receipt/correction fences and
unconfirmed-start/reminder rules across sports. Fresh matched provider receipts
admit "Broadcast listed", not LIVE. Exact unique verified MLB/NHL joins support
plain provider categories and reviewed name aliases, with explicit local provider
ID aliases for playback and saved/reminder continuity; generic channels never
prove a named match. Details/player status share Matchday certainty policy.
Upcoming countdowns move below identity and channel rows shed repeated labels,
preserving badges, Watch placement and accessible touch/text sizing. Production
Worker6399f52d, shared121 and installed owner123 do not contain this follow-up.

### Broader cricket integration (record isolation deployed; 6 October 2026)

`cricket-fixture-policy.mjs` validates the official ICC international schedule
and `cricket-fixture-registry.mjs` owns shared durable snapshots, adaptive due
times and independent CPL collection. `/api/cricket/fixtures` is the new native
route; `CricketFixtureCatalog.swift` caches it and attaches fresh explicit status
without inventing provider coverage. `tools/audit-cricket-fixtures*.mjs` and the
hourly cricket workflow compare current coverage independently with CWI and
produce redacted deduplicated owner alerts. Worker deployment
`88a5bce6-c694-435c-9b8c-6ac3173121de` and protected PR27 activate cloud collection
and hourly monitoring; first run 36750055302 passes. Source4 preserves that
registry, and owner112 previously validates67 cached cricket rows.
On 1 October PR36/source `2026-10-01.cricket-corrections-1`, Worker version
`87b347ed-0b0c-4df1-b0ec-9c755f06fc5d`, admitted three verified ICC changes;
the deployed registry independently admits WI/ICC cohorts after the same complete
collection gate. Failed cohorts retain exact rows/receipts, aggregate failure
backoff remains and CPL ownership is untouched. WI9/ICC58 receipts advance to
19:45:36 UTC with67 IDs retained and zero failures; hosted cricket/sports/CPL
monitors pass. The six-hour local heartbeat supervises
both cricket and all admitted sports, read-only, without collecting routine data.
See `docs/operations/Cricket-Fixture-Service.md` for exact gates and limitations.

PR39 / `243f9bb`, source `2026-10-06.cricket-isolation-1` / Worker
`6399f52d-e0d6-45e8-ba3d-1462a94093e3`, preserves those source-wide gates but
isolates recognized individual conflicts with `admitICCIsolated`. Fresh
unaffected records carry optional `source.verification=verified`; disputed
records retain facts/observations with `held`. Incomplete collection, cohort
watermark regression, identity migration and the400-row bound still hold the
affected authority. Unavailable coverage/original receipts, failure counters
and backoff remain until full recovery; per-record recovery is not cohort health.
Revision hashing includes verification, not renewed observations. The schema1
native consumer accepts legacy absent markers, rejects null/unknown/out-of-scope
markers, fences row/cohort watermarks and demotes retained marked cache rows.
Held starts cannot generate confident countdowns or reminders. Only a fresh
provider snapshot with a matched attached descriptor grants a separate bounded
`providerObservedAt` listing receipt; neither generic channels nor replayed
provider caches prove a named match live. Such listings remain manually
discoverable as **Broadcast listed**, never verified LIVE. The monitor reports
verified/held/live counts while preserving unresolved incident alerts.

The deployed `icc-kickoff-corrections.mjs` ledger admits only three now-reviewed
exact old→new scheduled transitions, bounded by identities/series/source,
post-verification freshness and pre-kickoff expiry. It is neither a fallback
feed nor a fabricated publisher revision; collection/status/cohort safeguards
remain. Internal publisher series evidence is stripped before publication.
The replayed-provider refresh branch also merges accepted cricket with
no stale provider evidence and reconciles personal state after cricket/sports
updates. Shared111 predates the broad cricket consumer; current device and
distribution receipts are in Current-State.md, not these historical gates.

- `LiveCatalogSnapshot.checkedAt` is the receipt for stream-provider listings;
  it never proves an official fixture or a decoded broadcast.
- `CPLSchedule.Snapshot` owns a content revision, verification receipt, complete
  fixture set and typed source status. `CPLScheduleUpdater` validates all 39 rows,
  checks at most every 30 minutes, prefers current verification over fallback
  data and keeps a newer equal-trust snapshot. `MatchListViewModel` owns the
  accepted CPL status and the user-facing two-hour freshness boundary.
- The CPL Worker queries the published schedule, official correction and current
  verifier. `resolveCPLManifest` advances `checkedAt` after every successful
  multi-source check, but advances `revision` only when fixture content changes.
  Its fail-closed route returns the durable fallback with its original receipt.
- `FootballRepository` remains PL/UCL schedule authority through
  football-data.org and its 15-minute list cache. `LiveScoreService` owns the
  successful schedule receipt separately from score refresh and clears stale
  analysis authority after a schedule failure. Streaming listings continue under
  `MatchListViewModel` and retain their independent warnings.
- `.github/workflows/provider-monitor.yml` validates live PL and CL season feeds
  through `tools/audit-football-fixture-feed.mjs`, provider identities, and
  imminent UCL source readiness; the CPL workflow/audit retains its complete
  two-source and human-review boundary.
- Production deploy `e46fb1d9-06eb-4efb-8d24-ff5544e42215` and protected run
  34056219335 are the activation evidence. The app-side warning/downgrade contract
  first reaches the shared tester group in 2.0.0 (75).

## Personalized Home ownership (private build 74; introduced in build 73)

- `FollowedTeamItem` and `FollowedLeagueItem` remain the sole persisted interest
  records. `SportsPersonalizationPolicy.isFollowed` maps a catalog event to those
  records; following a competition has no notification side effect.
- `HomeInterestPreferences` owns only the UserDefaults switch that asks Home to
  apply saved interests. Its policy requires at least one selection and fails
  open otherwise. It is intentionally not SceneStorage and not another favorite
  store.
- `SportsDashboardView` applies that policy to the Home projection and its
  multiview candidates. Full lineup requests an unrestricted projection and
  Search uses the complete shared catalog. Generic broadcast channels are hidden
  from a restricted Home because they are not confirmed competition fixtures;
  they remain available in Full lineup/Search.
- `CatalogTimingPolicy` owns the 72-hour retained future boundary and the
  separate presentation horizons. `HomeSportsDiscovery.homeSections` accepts a
  bounded horizon and row limit: personalized Home uses 72 hours and three/four
  upcoming rows, while broad Home keeps six-hour featured and 48-hour later
  behavior. Personalized upcoming relevance is equalized only in the Home call
  so kickoff order wins; Full lineup keeps its established ranking.
- `SettingsManageLeaguesView` is the shared Home interests editor: browse sport,
  choose additive sport/competition/team interests and preview the current lineup.
  Team selection stays separate from saving fixtures or enabling notifications.
  `FottyPrivateBackupPayload.Preferences` carries the switch as an optional field
  to preserve version-one decode compatibility.

## Home relevance and catalog performance ownership (private build 72; builds 68–69 rejected)

- `HomeSportsDiscovery.PresentationPriority` remains a precomputed sort key.
  Its audience relevance gives PL/UCL and explicit interests the limited
  prominent Home positions; `HomeSections` partitions the ranked list into
  featured live, More live and upcoming without dropping catalog events.
- `HomeSportsDiscovery.uniqueEvents` may canonicalize a team only through
  `SportsTeamIdentity.known`, whose exact reviewed aliases must resolve to one
  sport-scoped identity. Exact kickoff remains required. Do not replace this
  with fuzzy, substring, badge-URL or one-team deduplication.

- `SportsDashboardView` owns one cached `HomeSportsDiscovery`, football-league
  projection and `HomeDiscoveryRow.Presentation` map keyed by catalog, score and
  minute revisions. Home/Full lineup expose stable rows containing one fixture
  in narrow windows or at most two in wide windows to a single vertical lazy
  stack; date headings and rows are flattened before rendering. They
  intentionally do not observe or restore absolute pixel offsets,
  because unseen lazy geometry is estimated and unstable.
  Its cached Home/Full-lineup sport activity projections now use
  `HomeSportActivityScope`: counts describe the actual destination after retained
  CPL/Channels filters, Home interests and the existing sport-switch reset rules.
  Saved preferences are not silently cleared; generic channel cards do not
  inflate live counts. Projections are prepared on revision/filter changes,
  rather than scanning the catalog in each tile's SwiftUI body.
- `TeamBrandService` publishes one atomic multi-league badge map.
  `TeamBadgeWindow` reads a snapshot without observing the service, while
  `FottyImagePipeline` coalesces URLs, bounds network/cache size and downscales
  artwork off MainActor. Waiters are reference-counted so a rapid scroll cancels
  work no visible row needs. Persisted badge catalogs have a 24-hour freshness
  window; remote JSON/league expansion is nonisolated from MainActor.
- `MatchCatalogCacheWriter` is a SwiftData model actor. Fresh catalog UI publishes
  first; generation-fenced persistence replaces cache rows off MainActor and
  reports failure without animating the whole catalog.
- `FottyPerformanceTrace` owns the two coarse signposts. The app delegate starts
  a MetricKit subscriber; dated scalar retention/export now belongs to
  `FottyPerformanceStore` as documented above. The physical
  Release workflow lives in `tools/ios-performance-gate.sh` and always deletes
  its temporary build/trace root.
- Home evaluates the catalog-wide channel fallback only for a source-less CPL
  fixture. Other lazy rows must not perform playback identity scans while they
  enter the viewport.
- Normal-size catalog rows reserve stable information geometry and use the shared
  minute snapshot instead of owning a TimelineView. `MatchRowLayout` shares
  measurements between sizing and placement. Standalone cards may retain the
  precise per-row countdown schedule where active scrolling is not the owner.

## Everyday usability and recovery ownership (fourth local batch after build 58)

- `BrowsingStateKey` centralizes scene-scoped Home filters and retained Matchday/
  FPL browsing state. Exact Home/Full-lineup/Search pixel restoration is retired;
  shared catalog/score refresh and FPL workspace ownership are unchanged.
- `MyMatchdayStore.MutationResult` is the save contract. Candidate state is
  encoded, written and read back before observation changes; Home, Search and
  Matchday surface failures locally. Reminder creation compensates by removing
  its request when the promised Matchday save fails.
- `LocalPersistenceWarning` marks SwiftData's volatile fallback on every follow
  editor and those edits fail closed. Settings components use scaled type and
  accessibility-size layouts; provider settings inherit the app appearance.
- `SettingsPrivateBackupView` self-opens an encrypted export and records a
  verified Files handoff. `FottyPrivateBackupService` commits Matchday before
  SwiftData replacement and attempts rollback on database failure. Feedback
  retains drafts and preparation receipts without a fabricated delivery receipt.
- Verification and physical limits are recorded in
  `docs/audit/Fotty-Everyday-Usability-Implementation-2026-09-05.md`.

## Complete FPL workspace ownership (third local batch after build 58)

- `FPLWorkspaceEvidencePolicy` owns manager/season confirmation and short-lived
  player-history receipt policy. `FPLAdvisorViewModel` binds async publication and
  mutations to current workspace identity; `FPLWorkspacePersistence` quarantines
  unverifiable unscoped legacy bytes instead of assigning a current owner/year.
- `FPLRivalSnapshot` pairs one primary scoring packet with selected-rival picks.
  Both use `FPLDecisionEngine`; standings remain a separate loaded snapshot.
  Primary refresh triggers selected-rival refresh, not another polling loop.
- `FPLPlanningBounds`, `FPLChipAvailabilityPolicy` and `FPLWildcardBudget` own
  calendar, season-window and qualified budget decisions. Journal store accepts
  an explicit season; its composer and route saves select a real target GW.
- Worker `coach-evidence.mjs` resolves current names and bounded histories before
  building model evidence. `coach-transfers.mjs` checks optional structured routes
  against a server-only full catalog. It does not verify arbitrary model prose or
  submit moves. Native Coach labels separate calculations, evidence and judgment.

## Connected sports journey ownership (local source after build 58)

- `LiveCatalogSnapshot`/`LiveCatalogAccumulator` carry receipt, coverage and raw
  conflict evidence. `AnalyticalDataEngine` incrementally records completed
  endpoints under its own bounded clock. `MatchListViewModel` owns refresh and
  retained display data; `playbackCatalog` adds hidden conflict tombstones back
  for admission. Search is a projection with the same refresh owner.
- `SharedStreamDiscovery` schedules fair lookup/validation opportunities and
  publishes partial results into the existing overall discovery coordinator.
  `LiveSourceHealthStore` retains positive history, not generic failure circuits.
- `CurrentEventBroadcastPolicy` supplies Home/Search/Arena's current action;
  `SavedMatchContinuityPolicy` handles same-ID reschedule continuity separately
  from strict playback identity. MyMatchdayStore retains intent and previous
  dates; MatchReminderStore reconciles pending notifications without autoplay.
- `SportsTeamIdentity`/`SportsPersonalizationPolicy` own sport-scoped follows
  and reviewed leagues. `SportsPersonalizationStore` performs isolated migration
  and settings writes. MainTab starts migration and reruns it after backup restore.
- `CatalogTimingPolicy.cplWindow` unifies the eight-hour CPL discovery window.
  Listed start is not official live status, and recognized non-CPL T20 stays six
  hours. `CatalogRefreshNotice` displays partial/error/age states without a poller.
- `MatchHubSnapshot` and the repository's `matchHubSnapshot` publish score and
  insights from the same payload. `MatchHubViewModel` owns refresh, cancellation,
  age and catalog-only fallback updates; `InsightsHubTab` is presentation-only.

## Private-product foundation additions (local source after build 58)

- `Core/Networking/LocalStreamProxyPolicy.swift` owns selected-media route
  registration, per-session capability, credential/public-destination/redirect
  policy and bounds. `LocalStreamProxy` owns loopback transport, ephemeral session
  and cancellable connections. Normal/MultiView owners fence startup. WebKit
  handoff preserves typed selected-domain cookies. DNS preflight does not pin the
  connection address; exact-provider acceptance remains separate.
- `Features/FPL/Services/FPLTransferStagingStore.swift` owns recoverable working
  state per manager/season and bounded Undo, separate from validated draft storage.
  TransferHub exposes baseline conflict resolution; the advisor requires the
  current full baseline and budget before shared-validator save. PlannerEngine
  validates complete combined routes using known selling values or explicit
  assumptions. Successful private-backup restore clears replaced staging and
  notifies/reset open editors without touching unrelated preferences.
- `web/workers/playback/src/coach-safety.mjs` owns shared deadline/body bounds,
  digest-based paid access and global persisted `CoachQuotaBudget`. Checked-in
  configuration is 50 paid attempts per UTC day with paid access disabled. The
  Worker wraps parsing/evidence/model in that deadline; deterministic scoring
  bypasses paid admission. Missing minute/access/budget configuration fails closed.
- `FPLCoachAccessStore` owns serialized, non-synchronizing ThisDeviceOnly Keychain
  storage and HTTPS bearer headers; `FPLCoachRedirectDelegate` refuses redirects.
  `SettingsCoachAccessView` is secondary to Privacy & Security and does not grant
  cloud consent or verify server acceptance merely by saving a code. Codes are
  excluded from backups/diagnostics. This is invitation authorization, not App Attest.
- New relay/transfer/access tests and `coach-safety.test.mjs` cover these boundaries.
  Rollout and evidence: `docs/operations/PRIVATE-COACH-ACCESS.md` and
  `docs/audit/Fotty-Foundation-Implementation-2026-09-04.md`. Nothing here implies
  that the inspected production Worker has changed.

## Reliability ownership additions (local source after build 58)

- `Core/Networking/CatalogPlaybackIdentity.swift`: pure MainActor admission for ordered team/date/sport and explicit provider-ID/channel/single-event routes. `StreamDeliveryIdentity` preserves the full delivery URL and required headers. `EventReference.hasCatalogIdentityConflict` carries a source-less quarantine through cache/merge; public browsing omits it, internal resolver entry points reject it.
- `AnalyticalDataEngine.curatedPlaybackCandidates` retains concrete HD/SD/language alternatives with fair family coverage, not one route per label. Aggregator/source/final-session dedup uses delivery identity rather than redacted URLs.
- `LivePlayerViewModel.webRetryTask` and its request/source token own delayed retries; injected delay enables actual lifecycle tests. Cleanup invalidates attempt identity. Network-grace callbacks are fenced too.
- `LiveWebEmbedPlayerView` selects visible, non-ad main media and routes child events through eligible parent frames to the main WebKit bridge. Removed/ended/ad owners release authority; background suspension preserves it. Native candidates come only from the selected DOM source or bound JW/Video.js APIs. Child Score808 frames retain transport containment without playback authority.
- Both playback surfaces key the WebKit representable to `loadRequestID`:
  only a source/retry replacement creates a fresh document/coordinator. Rotation,
  audio, pause and scene changes retain it. Bridge messages carry the attempt
  token; committed-document URLs and current navigation identity fence ownership.
  The coordinator owns a cancellable native startup deadline, current navigation
  failures and process termination, preserving explicit pause/background grace.
  Main-player PiP callbacks also require the current source/attempt.
- Web playback chrome is a compact UIKit-backed toolbar hosted above
  `LiveWebEmbedPlayerView`, never a descendant of a hit-testing-disabled surface.
  UIKit owns only the visible Pause/Sources bounds; the remaining provider area
  stays directly interactive. Explicit Pause clears the preceding reveal tap and
  is enforced against programmatic restarts; only a new trusted provider pointer
  interaction may authorize the provider's own Play.
  UIKit measures complete labels/symbols and reflows narrow or larger-text
  controls rather than assigning fixed widths. Provider-listed availability uses
  neutral Home labels; red LIVE/counts require confirmed live status.
- `Features/FPL/Services/FPLAdvisorDataProvider.swift` is an injectable resource boundary, not another state store. The existing advisor owns a single coherent publication path. `FPLMainView` owns the foreground/tab-scoped 60-second poller across all FPL destinations, including planning. `FPLLiveTrackerView` no longer owns a competing timer. Freshness includes bootstrap/fixtures/picks/live; full-time and gameweek transitions preserve published/local-draft isolation.
- New `CatalogPlaybackIdentityTests`, `LivePlayerRetryLifecycleTests` and `FPLMatchdayRefreshTests` exercise adversarial identities and real async owners; `PlaybackPolicyTests` executes monitor behavior for ad/frame/ownership/background transitions. Exact gate/acceptance: `docs/audit/Fotty-Reliability-Fixes-2026-09-04.md`.

## Direct Score808 boundary (build 58, 2026-09-04)

- `Score808SiteCatalog` is a pure, bounded parser for the public calendar widget, exact team/kickoff/timezone identity, unique current Watch-page ownership and configured main-player evidence. It never guesses a donor ID or persists a rolling media URL.
- `Score808SiteResolver` owns ephemeral bounded HTTPS transport and redirect validation for the Score808 page plus the public calendar endpoint. It runs only for an enabled, explicit football Watch in the late window; it does not insert Score808-only fixtures into Home.
- `StreamDiscoveryCoordinator` collects independent shared-catalog/direct-site lanes within one attempt and deadline. Partial sessions and failure values survive cancellation; detailed incomplete-lane logs remain an audit follow-up.
- `LiveWebEmbedPlayerView` retains the selected page/player context within its attempt. Direct-site mode scopes ownership and native candidates to the observed main player and fits it into the viewport. Current callers isolate source/retry attempts with a fresh WebView; script replacement also prevents stale provider mode if the representable is reused defensively. Generic-provider media ownership remains a separate audit finding.


## 1. iOS application shell and lifecycle

- `FottyBrand` in `Core/Config.swift` separates the public display name
  (`Fotty Sports Hub`) from the retained `Fotty` wordmark and technical
  identity. `CFBundleDisplayName`, the Home masthead and Settings version row
  use that public identity. Bundle IDs, target/scheme/module names, storage
  keys, `fotty://` routes, backup types and backend contracts stay unchanged.
- `MatchStartPolicy` and `MatchReminderStore` in `Core/Notifications/MatchReminderStore.swift` own scheduled-start/play eligibility and explicitly opted-in five-minute local reminders. Stable UTC requests, a serialized queue and per-ID revisions protect cancellation/rescheduling. Only fresh catalog responses update snapshots; existing score refreshes supply known status. Foreground reconciliation must not overwrite saved sources with source-less SwiftData cache rows. The store never fetches, probes streams or prompts for permission without opt-in.
- `MatchStartControls` in Dashboard Components is shared by Home rows, full-lineup/Matchday cards and catalog Match Center. Its scoped timeline ticks once a minute, then once a second inside five minutes. Build 41 adds a generic information slot and measured `MatchRowLayout`: information left, action right, stacking only for insufficient width/accessibility text, without duplicating stateful controls. Feedback stays full-width. Save/remove uses native context menus and accessibility actions rather than permanent bookmarks. Play becomes available only for a listed source inside two minutes. `MatchPlaybackFeedback` holds bounded per-event inline retry state, not provider-health blocks. `MyMatchdayStore.onRemove` revokes a selected reminder; saves alone never schedule one.
- Reminder notifications and `fotty://matchday/<id>` use `MatchNavigationStore.pendingReminderID`. MainTab selects Matchday; the existing view scrolls to a highlighted saved row and consumes the route, without starting playback or forcing Match Center. Foreground score alerts retain their existing Match Center route.

- `SettingsAppearanceView` in `SettingsScreen.swift` is the dedicated theme destination in build 38; the main Settings row shows the current value. `SettingsAppearanceOptions` holds the actual choices separately from the UIKit-backed scrolling container, allowing nonblank render validation. Engineering and the retired stream-validation UI are absent from the app target; customer support stays under Report a problem. If the persistent SwiftData store cannot open, Settings shows that the current session cannot save instead of silently presenting the in-memory fallback as durable. `TeamBrandService` merges persisted badge URLs into (not over) its bundled fallback; static NBA/WNBA/MLB/NHL and CPL fallbacks protect cold starts. Football badge catalogs use bounded ESPN league metadata plus exact generated aliases, while the rate-limited SportsDB service is reserved for CPL/IPL/Argentinian basketball and one-off unknowns. `TeamBadgeWindow` is the measured image/monogram boundary on team-name surfaces.
- `SportTileGridLayout` in `SportsDiscoveryViews.swift` measures all sport buttons at one width and gives every cell the tallest measured height, including partial rows. A scaled minimum width determines the column count. Sport titles reserve two lines; iPad (including compact Split View) and regular-width layouts show all catalog sports inline. Only compact phones retain the five-sport overflow policy and selected-sport continuity.
- `SportMotionProfile`, `FottyMotionPolicy` and `SportLoadingView` in `Design/UI/Animations.swift` form the shared motion boundary. Build 92 replaced loader symbols/glow with original shaded `SportMotionArtwork` Canvas equipment and pure bounded `SportMotionPose` math. Home/filter/heading category identity now comes from `SportIdentity`: one normalized SF Symbol vocabulary and a stable tinted emblem rather than platform-variable emoji. The visible loader timeline is capped at 30 fps and pauses offscreen, inactive, under Reduce Motion or Low Power Mode (power changes observed on the main run loop). `SportMotionContext` chooses decorative Champions League styling only from explicit UEFA/UCL metadata or matching official team/kickoff evidence, rejecting conflicting and youth/women's metadata without changing fixture classification. Home, Match Center, resolution and player preparation pass context outside the frame closure; multistream resolution uses All sports. No new media, sound, dependency, delay or transport behavior. Shimmer and momentum retain the shared motion policy. `SportCelebrationView` remains a dormant one-shot primitive requiring a verified scoring event.

- `Fotty/Design/Theme.swift`: `FottyAppearance` owns the shared `fotty.appearance` preference (Dark default, Light, System). The app root applies it without rebuilding navigation identity. Trait-resolved semantic colours separate readable amber ink (`accentText`) from gold fill (`accent`). FPL sheets inherit the app appearance; live-player presentations and pitch artwork keep scoped dark treatment.
- `SportIdentity`/`SportEmblem` in `Fotty/Design/Components.swift` supply equipment icons for Home and both catalog variants. Home discovery rows reuse `FlagSquircleBadge`, matched football crests and the existing provider/catalog cache; no new badge fetch service is added. The badge observes catalog changes and fits complete artwork. Channel/unpaired-event rows do not synthesize opponent badges.
- Web transport ownership: `LiveWebEmbedPlayerView` uses passive frame click observation rather than a UIKit tap recognizer, and sends actual primary-video transport state keyed to its document. `LivePlayerViewModel` validates source/attempt, separates explicit pause from interruptions and cancels native handoff on pause. `LivePlayerView` bounds fallback chrome to its top-right buttons, leaving provider centre/bottom controls exposed.

- `Fotty/App/FottyApp.swift`: dependency construction, SwiftData container, app-level services, and the notification delegate.
- `Fotty/App/MainTabView.swift`: Home, Matchday, FPL, and Settings navigation plus notification/Live Activity match routing, `fotty://fpl` widget routing, and followed-team alert-preference synchronization. The old `Arena` raw value is retained only to migrate persisted tab selection.
- `FottyPrivateBackupService` in `Core/Persistence/FottyPrivateBackup.swift` owns the versioned private recovery boundary. It captures only documented device-local preferences, follows, saved Matchday identity and manager-scoped FPL plans; validates size/schema/counts/identities before mutation; encrypts with PBKDF2-HMAC-SHA256 plus AES-256-GCM; and excludes credentials, provider routes, Coach conversations, consent, reminders, diagnostics and caches. Restore replaces the documented state, clears consent/reminders and posts `fotty.privateBackupRestored`. `MainTabView` then resets FPL navigation and reloads the restored public manager without recreating the app shell.
- `SettingsPrivateBackupView` is reached only from Settings → Privacy & Local Data. It owns password confirmation, `.fottybackup` Files export/import, decrypted preview and a second destructive restore confirmation. Passwords and plaintext previews are not persisted. The file type is exported in `Info.plist`; a forgotten password has no recovery path by design.
- `FPLWorkspaceSession` in `FPLMainView.swift` is root-owned by MainTabView. It retains one FPL advisor, selected workspace/tool and per-destination scroll offsets across tab changes, while off-screen views and their `.task` pollers still disappear. Manager changes reset navigation; the advisor clears unsent Coach text, pending-state UI and comparison IDs together with the existing manager-bound data. Feedback drafts retain their explicit on-device persistence.
- FPL checks its phase/data again on tab return or foreground activation using the service's existing TTL cache. Only explicit pull-to-refresh clears the cache. A cached screen remains visible during this load and displays refresh errors inline; a full-screen spinner only replaces an initial empty snapshot. Scroll restoration refuses writes from an old manager selection.
- `Fotty/Features/Onboarding/MatchdaySetupCard.swift`: optional, dismissible Home guidance for following teams and saving broadcasts. No FPL promotion or manager dependency remains on Home or Matchday. `TeamOnboardingView` uses adaptive club tiles and cancellation-safe, debounced catalog lookup with explicit loading/empty/retry states. Empty Matchday exposes following and Home discovery; the FPL tab remains independent.
- `Fotty/Features/Settings/Views/SettingsSupportViews.swift`: offline native help, shared capability explanations, and a local feedback draft with build/device context, opt-in redacted diagnostics, preview, copy for TestFlight and system sharing. It has no submission backend and never interprets copying/sharing as delivery. Player and FPL recovery screens expose this same report sheet.
- `Fotty/Features/Dashboard/SportsDashboardView.swift`: owns All-sports-first Home, compact activity selection, a three-event mixed-sport Now & next list, two later fixtures, and the full lineup on its own navigation stack. Home and My Matchday use `MatchListViewModel.shared`; whichever fixture tab is visible drives its bounded refresh loop. All sports reuses the existing football score poller; a local minute clock never fetches data. The shared current-event policy requires active direct or reviewed CPL channel sources for Watch; unavailable rows do not advertise an empty player.
- `Fotty/Features/Search/SearchView.swift`: Home's app-wide search projection, reached from the masthead. `HomeSportsSearch` filters current `HomeSportsDiscovery` items/channels plus the verified source-free upcoming `SportsSearchSchedule` projection, with case-, width- and accent-insensitive multi-token matching, explicit football-league disambiguation and a reviewed sport-scoped non-football league vocabulary inferred from event/source identity. Opaque provider IDs never enter the haystack, and category alone does not promote every hockey/baseball/basketball event into a major league. It owns no network or playback resolver. `HomeDiscoveryRow`/`LiveEventCard` render the results, and the dashboard defers Watch/details presentation until the sheet dismisses.
- `Fotty/Features/Dashboard/Components/HomeSportsDiscovery.swift`: presentation-only exact-event deduplication, timing/official-status precedence, stable sport activity summaries and bounded diverse curation. Real source descriptors are combined without URL synthesis; fuzzy identity and schema migration are excluded. Channels never enter on-now counts. `SportsDiscoveryViews.swift` owns adaptive activity buttons and compact source-gated event/bookmark actions with explicit sport and timing provenance.
- `Fotty/Features/Dashboard/MatchListViewModel.swift`: one shared in-memory Nexus catalog with a configure-once SwiftData cache, preventing Home/Matchday contradictions during tab changes. It loads the last-known-good CPL manifest, refreshes that small schedule independently from the provider catalog and merges one trusted schedule into cached/fresh rows. Debug-only cricket and cross-sport Home UI fixtures require automated-testing plus feature-specific flags and do not enter production persistence.
- `Fotty/Core/Models/CricketCatalog.swift`: seven CPL franchise identities, cricket filters, the bundled 39-fixture 2026 fallback, strict manifest decoding, the last-known-good updater and `CPLChannelOptionsPolicy`. Complete count/order/identity/stage/year/future-date validation runs before caching; an older response cannot replace a newer cache. Only matching franchises and kickoff within one hour can enrich a fixture with active catalog sources; channel sources and stale cached snapshot sources never do. During the two-minute-before/eight-hour-after fixture window, the separate channel-options policy may expose recognized Fox/Willow rows with active sources as explicitly unconfirmed alternatives; it never mutates the fixture or asserts channel programming. Started T20 rows expire after eight hours and the season remains bounded. Home separates channels from fixtures; My Matchday separates saved channels from dated plans. Neither subscribes to FPL context.
- `web/public/data/cpl-2026-fixtures.json`, `web/workers/playback/src/cpl-fixture-policy.mjs`, `tools/audit-cpl-fixtures.mjs` and `.github/workflows/cpl-fixtures.yml`: reviewed Worker fallback, one shared official/correction/current-source policy, local/live audit and a daily fail-closed PR-preparation lane. `/api/cricket/cpl-fixtures` returns an agreed dynamic update or the complete reviewed fallback. Conflicting or incomplete upstream data never writes through automatically; annual season rollover is explicit.
- `Fotty/Core/Providers/Football/FootballModels.swift`: `LiveScoreService`, shared team-normalized score indices, kickoff-bounded catalog-to-schedule matching, notification merging, and feed-aware polling (60 seconds for official FPL, 240 seconds for fallbacks). Player score/status surfaces require team and kickoff identity so an older same-team league fixture cannot label a current cup broadcast.
- `Fotty/Core/Internal/AnalyticalDataEngine.swift`: Nexus catalog normalization, near-term event filtering, badges, stream descriptors and Home league classification with explicit evidence/reason codes. Stream resolution tries generated canonical home/away identity before legacy word matching. League placement may receive a team-and-six-hour-kickoff-proven `FootballMatch`; its official competition wins, while provider markers and both-current-senior-club inference remain fallbacks. Cup/youth/friendly/lower-division identity stays outside domestic tabs; explicit Champions League remains authoritative. It accepts real catalog variants first and exposes canonical zero-variant synthesis only for the known Hotel/Delta/Golf/India contracts; Echo/Admin without variants are not fabricated.
- `Fotty/Core/Models/MediaModels.swift`: shared channel identity, display title and sport-aware timing. Channels have no inferred kickoff/end. Football uses a two-hour discovery estimate; reviewed CPL uses the shared eight-hour window, other recognized T20 six hours; unknown cricket formats receive no inferred live/final state. Other sports retain the four-hour broadcast window without an inferred final whistle. Source-free bundled CPL fixtures never claim decoded live playback. These are discovery estimates, not official results; football score lookups also require football category and kickoff identity.
- `Fotty/Design/Theme.swift`: shared semantic typography and `FottyFixtureDifficulty` provide one contrast-tested numbered difficulty scale for pitch/table. Home cards keep curated known short names but do not algorithmically erase unknown club identity. Matchday shows one relevance explanation and date-groups later fixtures.

## 2. Playback path

The build-43 reliability patch makes decoded progress video-owned and bridge failures/recovery/native candidates document-owned. `Coordinator.handlePlaybackMessage` is separately testable while `userContentController` retains the WebKit/current-document admission guard. Replacement/backward timelines establish a baseline without themselves proving recovery. Exact release status is in `docs/releases/Fotty-2.0.0-43.md`.

1. `LivePlayerView` and `MultiLivePlayerView` present single/multi-event playback.
2. `LivePlayerViewModel` owns resolution state, source selection, timeouts, cancellation, user-facing failure state, and the single `LivePlaybackState` authority.
3. `LiveStreamResolver` resolves bounded catalog candidates through one CoreMedia/web track. It curates real variants first and uses at most one canonical fallback only for a provider family with a known canonical URL contract and only when no variants exist; Echo/Admin are never synthesized.
4. `StreamPluginRegistry` loads built-in manifests; `StreamPluginProviderMatching` restricts active Watch sources to StreamEx and Score808 families. The Hybrid P2P/Ace session and warmup implementation is deleted. Provider parsing retains only an early rejection for P2P/Ace-shaped input.
5. `LiveWebEmbedPlayerView` is the physical-device WebKit adapter. It preserves the provider page for playback compatibility, performs one restrained play assist, proves readiness from decoded/advancing playback, owns attempt-scoped startup/stall recovery plus popup/nuisance/navigation containment, and reports actual HLS/MP4 candidates with the ephemeral attempt's referer, origin, user agent, and cookies. Its nuisance containment recognizes the specific VPN/install/continue-watching solicitation in accessible text and JavaScript dialogs, but never removes a matching ancestor that owns video, owns an iframe, or is effectively the player/root surface; generic overlays and the provider's real unmute prompt remain provider-owned. It also carries explicit play/pause commands through reachable HTML/JW frame media and reports non-cancelling surface taps so Fotty can reveal its bounded fallback controls without swallowing provider interaction. A non-explicit child-frame error deferred through the full startup deadline becomes a typed 20-second startup timeout; explicit provider rejections retain their reason. When the app backgrounds, its injected contract suspends reachable video/audio across the provider frame tree and resumes the same attempt on return. Native `AVPlayer` playback is different: `MediaAudioSession` activates `.playback` only at real play/PiP boundaries, and every direct or captured-candidate player opts into `.continuesIfPossible`; active PiP stays mounted and does not enter the foreground-resume path.
6. After web playback is already visible, `LivePlayerViewModel` validates and pre-rolls a candidate in a separate muted AVPlayer through `LocalStreamProxy` when headers are needed. Adoption requires advancing native playback; failure leaves WebKit untouched, and later native failure restores that same web source before provider failover.
7. `LiveSourceHealthStore` aggregates outcomes by provider family/host, ranks candidates and opens a bounded circuit after repeated failures. Recent decoded success influences automatic ordering but does not hide an otherwise eligible manual Watch or Watch-two action. `SportsDashboardView` preserves the user's ordered pair while both typed resolver requests run; `MultiLivePlayerView` leaves web transport controls provider-owned and exposes only explicit source/audio focus controls above those panels.
8. `LivePlayerView` owns the portrait match header and opaque loading/error UI; retry plus manual numbered broadcast override remain in-app. Web fallback Play/Pause and Sources controls sit at the video edge, auto-hide after four seconds of playing, and reappear through the WebKit surface callback; paused playback remains actionable. Source rows use generic quality descriptions and truthful `Selected`, `Select`, or `Try again` states. An explicit Watch navigation loads the selected catalog source with manual circuit-breaker override; later automatic failover still respects source health. Provider-site Safari fallback is intentionally absent.
9. `FottyLiveActivityController` and `FottyLiveActivityPolicy` expose a system Live Activity only after AVKit confirms PiP is active; capability or a transient inactive scene is insufficient. Web embeds are excluded, PiP stop/failure clears continuity, cold launch clears orphaned activities, and the extension presents match/score/status context rather than provider health. `MatchNavigationStore` makes the return link non-stacking while the player survives and falls back to Match Center after a cold relaunch.

Playback, discovery, match navigation and FPL compile into one production graph. There is no alternate review-safe implementation or distribution-dependent vocabulary.

## 3. Match, insights, and feature data

- `Fotty/Core/Data/Repository/FootballRepository.swift` and `Fotty/Core/Data/Providers/`: normalized football provider access. `OfficialFPLScoreProvider` in `FootballDataProvider.swift` maps fresh public FPL fixtures first; API-Football and delayed football-data are fallbacks. Live rows are merged onto football-data schedule identities before seeding Match Hub's cache. Automatic/timer hub loads use schedule/live cache only, and only an explicit full refresh allows provider enrichment.
- `shared/reference-data/football-competitions-2026-27.json` is the reviewed seasonal source for five domestic leagues plus the Champions League and Europa League, canonical provider aliases, and non-membership historical match identities. `tools/generate-football-competition-catalog.mjs` validates exact counts, unique/collision-free competition identity, source metadata, generated drift and the 30 June 2027 expiry, then emits the same canonical club resolver in `Fotty/Core/Data/FootballCompetitionCatalog.generated.swift` and `web/src/lib/football-competition-catalog.generated.ts`. Home classification, fixture/FPL matching, news topics, onboarding/badge bootstrap, local social fallbacks and web team search consume it. `shared/reference-data/provider-football-identity-vectors.json` is the URL-free cross-platform provider regression corpus; `tools/audit-provider-football-identity.mjs` validates it and optionally checks current catalog metadata without requesting video.
- `Fotty/Core/Data/FootballDataPolicy.swift`: single live-score competition allowlist, cross-provider team aliases, provenance labels, schedule-window polling gate and strict requested-window filtering. It currently enables the senior Premier League (FPL, API-Football 39, football-data `PL`/2021) and records Champions League (`2`, `CL`/2001) as the next inactive scope. Schedule/catalog discovery is intentionally separate. Dashboard and Live Activity presentation require a confirmed matched schedule competition before showing score-refresh/error copy; team-name guesses, youth/cup leagues, and unmatched catalog rows retain plain status without claiming a missing promised score.
- `Fotty/Features/Social/ArenaDiscoveryView.swift`: despite the legacy filename, this is `My Matchday`, not a second global schedule. A revision-keyed presentation projection filters the shared catalog to explicitly saved matches and followed teams and calculates official status, playback action, grouping and sort rank once per candidate. The view renders Live now / Next up / Later / Recent plus Saved channels, warns about overlapping kickoffs, and keeps Watch/Details available in place. It does not persist per-frame scroll geometry or consume fantasy squad context.
- `Fotty/Core/Models/ArenaModels.swift`: `SavedMatchRecord` and `MyMatchdayStore` persist a bounded catalog snapshot in UserDefaults without changing the SwiftData schema. Saved snapshots keep source identifiers for cold launch, then the resolver rematches against the current catalog before playback.
- `Fotty/Features/MatchHub/`: the sole status-aware match overview and refresh lifecycle. The redundant fantasy Match Lens was removed from `InsightsHubTab`; fantasy features remain in their dedicated workspace. The unreachable Dashboard Match Center and obsolete Arena/Highlights Match Hub tabs were removed from source and the Xcode target.
- `Fotty/Core/Notifications/NotificationManager.swift`: notification permission/scheduling, foreground presentation, followed-team alert scope, notification Match Center routing, and non-stacking Live Activity return handling.
- `Fotty/Features/FPL/`: FPL feature shell organized into Gameweek, Squad, Coach, and Tools workspaces, backed by the existing views, models, and advisor/planning engines.
  - `Services/FPLService.swift`: official public API transport plus version-3 disk envelopes, source provenance and bounded endpoint-specific caching. Disk use requires the current season, endpoint identity, acceptable age and—once bootstrap is known—the same official team-catalog fingerprint. Live snapshots expire after five minutes, bootstrap after 24 hours, fixtures after six hours; storage is capped at 96 files and 90 days. Legacy raw v2 snapshots are removed. `FPLSeasonIdentifier` drives rollover-safe manager storage keys.
  - `Services/FPLManagerConnection.swift`: strict official-link/positive-ID parsing, cancellation-safe identity lookup, and a confirmation boundary before the selected manager is persisted. Input remains editable after lookup failure; an old response cannot replace a newer identity. Disconnect invalidates request IDs and clears visible state while retaining manager-scoped drafts/history.
  - `Models/FPLModels.swift` and `Models/FPLOfficialModels.swift`: decoded official contracts. `Models/FPLDecisionModels.swift` keeps validated and modeled decision output separate from official facts, defines the decision journal and route checks, and retains the expiring device-local `FPLMatchdayContextStore`. Home, Matchday and Match Center no longer read that legacy snapshot.
  - `ViewModels/FPLAdvisorViewModel.swift`: single observable state and request-revision owner for manager, bootstrap, fixtures, history, event-live, leagues, phase, freshness, recommendations, reviews, alerts, Coach, Rival Race, and journal mutations. `Services/FPLWorkspacePersistence.swift` owns manager/season draft and Coach encoding, legacy migration, source-selection preference and consent lookup; it owns no UI state. `Services/FPLAdvisorDerivedStateBuilder.swift` computes validation, published-only live truth, planning routes, command-center state and optional optimizer output from immutable input; the view model applies one result and remains the only truth owner. Build 44's published `officialPicks`/`picksGameweek` versus editable `picks`/`FPLLocalSquadDraft` boundary is unchanged. `applyPublishedSquad` rejects older-week rollback and preserves drafts/source selection. Local plans have no official history/chip/autosubs; live scoring requires a matching published gameweek. Unit tests inject isolated defaults; UI fixture edits remain in memory.
  - `Services/FPLDecisionEngine.swift`: phase detection, public-history free-transfer estimation, versioned expected-minutes/projection confidence, blank/double-aware projections, deterministic live automatic-substitution and captain resolution, official-versus-provisional total separation, command-center decisions, and confirmed-gameweek reviews.
  - `Services/FPLSquadValidator.swift`: shared 15-player, position, formation, club quota, budget, captain/vice, bench-GK, uniqueness, and selectability validation used by every editing path.
  - `Services/FPLPlannerEngine.swift`: explainable roll/one/two-transfer routes with week-by-week modeled gain, hit cost/break-even, explicit downside, and verify-before-deadline checks plus legal constrained safe/balanced/aggressive squad optimization with locks and exclusions. `FPLScenarioStore` persists named manager-scoped alternatives. Output is modeled and is not described as an exact ILP solution.
  - `Services/FPLAdvisorEngine.swift`: deterministic recommendations using official expected-points hints, price projections, per-90 evidence, and set-piece/selectability context; its Rival Race analysis keeps published squad facts distinct from live points and modeled player ratings.
  - `Services/FPLAICoachService.swift`: deterministic on-device facts/rules/scoring and explanation fallback. `Services/FPLSmartCoachService.swift` is the consent-gated client for the Fotty Worker, contains no provider credentials, sends bounded evidence/history, rejects stale/incomplete responses, records redacted source/model/token evidence, and maps accepted output into structured coach cards.
  - `Services/FPLDecisionJournalStore.swift`: bounded manager-and-season-scoped UserDefaults persistence for pre-deadline decisions and post-gameweek process reflections.
  - `Services/FPLAlertScheduler.swift`: local 24-hour/two-hour deadline notifications and local coach-profile preferences.
  - `Views/FPLMainView.swift` keeps Gameweek, Squad and Coach primary and Tools secondary. Every secondary tool carries one evidence class—Official data, Official fixtures, Projection, Estimate, Published data, On-device plan or Advanced solver—and the workspace states that Fotty never submits a team or transfer to official FPL.
  - `Views/Components/FPLCommandCenterView.swift`, `FPLLiveTrackerView.swift`, `FPLTransferLabView.swift`, `FPLRivalMatrixView.swift` (Rival Race Centre), `FPLDecisionJournalView.swift`, and the optimizer/player views present the shared decision state. Plan uses decision/evidence columns at measured widths of at least 760 points, otherwise a single stack; metrics retain three flexible columns at ordinary text sizes and one at accessibility sizes. Squad preserves contained five-player pitch rows with two-line names, numbered fixture difficulty and a full-width roster from XXLarge upward. Transfer and wildcard changes are manager/season-scoped local drafts and never write to official FPL. Comparison selection is by player ID, with a bounded 60-result searchable sheet; its selections survive root-tab changes. Live Points/Rival Race waiting states navigate directly to Plan/Mini-leagues.
- `FottyLiveActivityExtension/FottyFPLDeadlineWidget.swift`: small/medium deadline widget with a minimal hourly official-bootstrap timeline, a visible official-source label in both sizes, and a `fotty://fpl` deep link. It has no manager identity and is not a live-score polling path.
- `web/workers/playback/src/index.js`: the single active public Worker owns playback/FPL plus `/api/football/matches` (football-data schedule proxy), optional `/api/football/live` (API-Football Premier League current-season/date query, filtered to in-play statuses), and `/api/cricket/cpl-fixtures`. It applies end-to-end deadlines and response-size bounds to remote sources, keeps last-known-good CPL data, reports catalog coverage without exposing source identities, and preserves a direct playback fallback when mirrors fail. Structured logs, invocation logs and sampled traces make source failures observable. The CPL route needs no secret: it applies `cpl-fixture-policy.mjs` to official/correction/current sources and returns an agreed update or the complete reviewed fallback. `FootballQuotaBudget` is one globally named Durable Object that serializes and caches the tiny Premier League feed, enforces an 80-call UTC-day app budget, reserves the provider's final 20 calls, and caches current-season plan restrictions for four hours. Health distinguishes a configured credential from usable current-season access and returns a non-secret `sourceVersion` for release-to-backend identity. `worker-version.mjs` shares that expected identity with `tools/audit-worker-health.mjs`; the daily provider workflow validates the deployed health, CPL receipt, catalog coverage/fallback and embed redirect without spending a live-score call. Provider credentials are Worker secrets, never app configuration. `/api/fpl/coach` refreshes compact official FPL evidence; `fpl-scoring.mjs` answers current-total/autosub/captain-promotion questions deterministically with zero model tokens, while other questions use DeepSeek V4 Flash in non-thinking JSON mode. The route returns token usage and rejects empty, incomplete-schema, or known rule-contradicting output. `coach-contract.test.mjs`, `cpl-fixture-policy.test.mjs` and `fpl-scoring.test.mjs` are the server contract suite. Rate-limiter bindings are abuse controls; account spending controls remain external. Production source `2026-09-20.worker-stability-1` is deployment `1ce467d8-ce0c-46b3-9ce2-9fcfbdd18b00`.
- `Fotty/Core/Storage/UserProfileStore.swift`: bounded device-local preferred-sport, followed-team compatibility and FPL-manager preferences; it is not an account or user-profile UI.
- `LocalDataStore.appSchema` retains the old `UserProfile` and social model metadata only as compatibility tombstones for existing private stores. Their UI/store graph is retired; do not interpret schema presence as a supported social product.
- Distribution does not alter Fotty's app graph, sports labels or playback availability. Any future paid product must introduce a real StoreKit purchase entitlement as a separately designed product boundary; it must not revive a hidden review-safe surface.
- `Fotty/Resources/PrivacyInfo.xcprivacy`, `SettingsPrivacyView`, and the web `/privacy` and `/terms` pages describe the active boundaries: device-local preferences/follows/FPL planning, public FPL manager lookup, opt-in Cloudflare Worker/DeepSeek Coach processing, local reminders/diagnostics and third-party player pages. The manifest declares only the transmitted User ID, installation Device ID and Other User Content used by Coach; local diagnostics are not automatically uploaded.

## 4. Verification and diagnostics

- `.github/workflows/`: `quality.yml` validates workflow syntax and reachable secrets; `web.yml` runs the Node 24 unit/type/lint/Worker/build gate; `ios.yml` runs deterministic provider checks, Catalyst units and a generic unsigned iOS Release build through `tools/ios-ci.sh`; `provider-monitor.yml` keeps the daily 72-hour live metadata report separate from pull-request correctness; `ucl-match-window.yml` runs every 30 minutes during Tuesday–Thursday/Saturday UCL windows and enforces route availability from T−30 through T+180. `cpl-fixtures.yml` runs daily and may update only the reviewed 39-match manifest on an automation branch before opening a human-review PR; it never approves or merges that PR. Its published no-change path passed manual run `33764542003`. `codeql.yml` scans Actions, TypeScript/JavaScript and Python on Linux only when their paths change. Swift remains under the simulator-free deterministic Xcode gate: both default and explicit/manual CodeQL extraction on the Xcode 27 beta graph failed to reach analysis in acceptable time and are not claimed as coverage. Dependabot handles security/minor maintenance, while GitHub secret scanning/push protection and CodeQL are repository-side controls. The iOS script has an `rg`/`grep` fallback, uses one trap-cleaned DerivedData root and may lower only the remote Catalyst host target to match GitHub's Xcode 27 image; it never changes the app's Release deployment target.

- Unreleased Coach lifecycle: `FPLAdvisorViewModel.sendCoachQuestion` owns a
  cancellable task and request/context identities; the view owns focus and
  delegates submission. Clear/disable/disconnect invalidates pending replies.
  Context changes reject results without resending. One deterministic helper
  also guards recovery. `FPLWorkspaceSession` accepts an optional injected model
  for isolated tests with real pending operations rather than mutated flags.

Build-43 scoring/request ownership (2026-08-28): `FPLLiveSquadSummary` has optional totals and explicit `hasCompleteScoringData`; incomplete data suppresses projected rules and derived totals in both Swift and Worker. `FPLAdvisorViewModel.scoringFreshness` uses the oldest picks/live fetch. `coach-request.mjs` owns request shapes, bounded stream reads and configured limiter outcomes; the Worker route retains deterministic scoring even when official evidence is unavailable. Regression evidence is in `docs/audit/Fotty-Complexity-Fixes-2026-08-28.md`; Worker rollout and separate Apple/device gates are in `docs/releases/Fotty-2.0.0-43.md`.

- `docs/NEXT-PHASE-PLAN.md` owns the approved sequence. `docs/beta/ROUND-01-ACCEPTANCE.md` keeps actual-user checks separate from automation; `docs/beta/COACH-ACCEPTANCE-CASES.md` is an evaluation specification, not model-quality certification.

- `ExportOptions-TestFlightInternal.plist`: normal Release upload to internal TestFlight with automatic signing, symbols and fixed source-controlled versions. `docs/RELEASE-PROCESS.md` and `TESTFLIGHT_READINESS.md` define the TestFlight-first path; direct-device scripts below are now opt-in debugging tools, not the default release channel.

- `FottyTests/PlaybackPolicyTests.swift`: provider policy, canonical identity/deep links, attempt/network/native-return continuity, web background suspension, injected-monitor JavaScript syntax, event timing/live-state, My Matchday persistence/pruning, official-FPL mapping/aliases, quality export, Live Activity/PiP eligibility, and normalization tests.
- Retired stream-debug and pipeline-validation screens are absent from the app target. Deterministic playback policies stay in unit tests; live decode/continuity requires the bounded external tools and physical-device checklist below.
- `FottyTests/FPLTrustTests.swift`: focused official-contract, scoring/autosub/captain/chip/hit/final boundaries, blank/double projections, phase/metrics, match-context persistence, reminders, free transfers, validation, legal optimizer, scenarios, journal isolation, deterministic Coach routing, Transfer Lab guardrails, and Rival Race tests.
- `FottyTests/BetaUsabilityTests.swift`: team-link validation, lookup failure/retry/cancellation and identity isolation, feedback contents and opt-in diagnostics, setup dismissal, truthful capability copy, preserved club identity, point gameweek/source labels, FPL session continuity and normal-text contrast for all difficulty colours. `docs/BETA-TESTER-GUIDE.md` defines the fresh-user tasks and real TestFlight report-receipt gate.
- `FottyUITests/FottyNavigationUITests.swift`: rapid tab/background lifecycle plus bounded contrast, traits, Dynamic Type, element-detection, hit-region, text-clipping, and description audits. FPL Plan, Squad, Coach, and Tools launch directly through the allowlisted Debug route and use an explicit network-free fixture; Matchday and Settings launch through their persisted tab contracts; Match Center and Player use explicit Debug-only presentation routes. The large-Type Coach audit requires both the quick-prompt control and a structured response, while the Player audit exercises its truthful no-source recovery state. Its physical-only live smoke refreshes the real catalog, selects a source-backed hero, verifies the compact source list, and holds playback muted through the initial stability window; it skips on simulators.
- `tools/stream_health_checker.py`: catalog endpoint health; it does not prove decoded video.
- `tools/test_stream_playback.mjs`: browser-level decoded-playback probe.
- `tools/audit_live_playback_matrix.mjs`: broad, concurrent WebKit matrix over current near-live provider families and variants, with an optional post-decode continuity hold that records playhead advancement and the longest freeze; streams structured JSON to stdout and leaves artifact creation to an explicit caller redirect.
- `tools/ios-deploy-device.sh`: signed physical-device build/install workflow; it can install an explicitly supplied `.app` and terminates only the existing normal Fotty process before launch.
- `tools/ios-device-qa.sh`: no-simulator release gate; checks generated seasonal identity, deterministic provider vectors and live metadata drift, then compiles/runs Catalyst policies through build-for-testing/test-without-building, builds and strictly seal-verifies one signed universal Debug artifact, installs that exact normal app on every explicitly listed physical device, compiles generic Release iOS, and prints the manual iPhone/iPad playback checklist. It intentionally never runs `FottyUITests`, reuses one DerivedData root, and removes its default temporary root through a cleanup trap.
- `tools/catalyst-ui-release-gate.sh`: lock-guarded Mac Catalyst runner for eleven release accessibility audits—six Dashboard scopes plus FPL, Matchday, Settings, Match Center, and Player Dynamic Type—and rapid-navigation check, executed individually without a simulator or physical-device UI-test runner. Its default DerivedData root is temporary and trap-cleaned; a caller-supplied shared root remains caller-owned.
- `tools/ios-physical-launch-hold.sh`: lock-aware, physical-only normal-app launch and bounded process-survival gate; it rejects simulator targets and never installs a UI-test runner.
- `FPLMainView` accepts `--fotty-fpl-workspace` only in Debug builds to initialize Plan, Squad, Coach, or Tools for repeatable normal-app physical screenshots and Catalyst audits. `FOTTY_FPL_UI_TESTING=1` additionally enables deterministic shell state only in Debug, makes no manager/network request, and never persists its Coach fixture. The parser is allowlisted and unit-tested; Release builds have no fixture or workspace override, and physical interaction remains manual.
- The FPL UI fixture now includes a synthetic 15-player squad, a five-defender row, long names, fixtures, captain cards, Plan metrics and distinct GW1 points/GW2 planning context. Shirt requests and comparison enrichment are suppressed in that explicit fixture. `testFPLContextSurvivesTabSwitch` exercises tool/scroll restoration and searchable comparison selection; the Squad Dynamic Type check requires the populated player row, not an empty state.
- `FottyApp` accepts `--fotty-ui-test-surface match-center|player` only when the Debug-only `FOTTY_SURFACE_UI_TESTING=1` flag is present. It presents deterministic network-free catalog/Player recovery state for accessibility audits; Release builds contain neither route. `MatchHubViewModel.resume()` preserves an already loaded catalog event instead of refreshing it away.

## 5. Web and retired infrastructure

- `web/`: companion Next.js/static-export surface; it is not the source of truth for the iOS lifecycle. Its supported server graph is the live catalog plus football match/standings/headline routes; browser playback uses direct third-party provider frames. There are no account, billing, admin, PocketBase, movie/TV, same-origin embed-proxy, P2P-server or stream-token routes. Preferences, saved teams and reminders are browser-local. Its baseline is Next 16.3.3/React 19.2.8 on Node 24 LTS with ES2022 output. Wrangler 4.127.1 is pinned for reproducible Worker dry-runs.
- `web/workers/playback/`: the separate Cloudflare edge boundary for stream metadata/redirects, football data and consent-gated FPL Coach requests. It does not make a third-party player same-origin or turn provider content into first-party media.
- Homelab, PocketBase and P2P/AceStream services plus the Android prototype are absent from the supported repository graph. Historical references in the decision log do not authorize restoring them.
- `agent/`, `docs/notebooklm/` and the bounded `tools/{agent-start,agent-finish,ask-brain,brain-doctor,notebooklm-refresh,private-kb-sync}.sh` scripts own durable local project memory; there is no remote embedding index.

## 6. Structural quality and refactor boundaries

- The 2026-08-31 Graphify baseline is 380 code files, 5,769 nodes, 15,005 edges and 250 communities with no detected import cycles. The report is directional because five Swift files parsed partially and repeated framework imports can collapse into one graph node.
- Knip complements Graphify for the web graph. Its intentional exceptions are the dynamically registered service worker, generated football-catalog exports, a server/test URL-builder re-export and Wrangler's configured `FootballQuotaBudget` Durable Object.
- The first FPL seam is complete: workspace persistence and pure derived computation are collaborators, while `FPLAdvisorViewModel` remains the only observable state/request owner.
- The first playback seam is complete: `LivePlaybackRecoveryPolicy` and `LivePlaybackSourcePolicy` own deterministic decisions, while `LivePlayerViewModel` remains the sole mutable AVPlayer/WebKit/proxy/task/request/PiP owner. Do not split lifecycle state merely to lower its remaining 99-edge Graphify degree. Further extraction requires a focused lifecycle test seam and physical playback acceptance.
- The next high-value production seams are `SportsDashboardView` (presentation sections/commands) and `MatchHubData` (small typed projections). Further FPL work should target manager loading or Coach transport only with request-revision tests; a lower edge count is not itself a product goal.
- Full evidence and the before/after graph are recorded in `docs/audit/Fotty-Graphify-Dead-Code-and-Optimization-2026-08-31.md`. Graphify output is disposable and must not be committed or left consuming workstation storage.

## Strategic navigation

- **Launch/watchdog or score churn**: `SportsDashboardView` → `LiveScoreService`.
- **Playback decisions**: `LivePlaybackRecoveryPolicy` + `LivePlaybackSourcePolicy` → side effects executed by `LivePlayerViewModel`.
- **Playback resolution/lifecycle**: `LivePlayerViewModel` → `LiveStreamResolver` → curated catalog descriptors → `StreamPluginProviderMatching`; it exclusively owns AVPlayer/WebKit/proxy/task/request/PiP state.
- **Web playback behavior**: `LiveWebEmbedPlayerView`; shared timing/state/value contracts live in `LivePlaybackPolicy`.
- **Catalog/metadata**: `AnalyticalDataEngine` and `FootballRepository`.
- **FPL transport/state**: `FPLService` → versioned official DTOs → `FPLAdvisorViewModel`.
- **FPL decisions**: normalized official facts → shared validation/phase/rules/projection engines → clearly labeled modeled output → local explanation or consent-gated server explanation over a refreshed evidence packet.
- **Device preferences**: `UserProfileStore`; SwiftData social/profile types are compatibility tombstones only.
- **Team identity presentation**: `TeamBadgeWindow` and `TeamIdentityLabel` in `Design/Components.swift` → explicit badge URL or `TeamBrandService` → monogram fallback. `FPLTeam.badgeURL` provides deterministic official Premier League crests for dense fantasy views.
