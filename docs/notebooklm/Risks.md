# Fotty Risks

Last updated: 2026-08-30

This registry turns current sharp edges into guardrails for agents.

## Repository attack surface and third-party playback (merged 2026-08-30)

- CodeQL found 71 alerts after the clean root made several retired graphs visible to current scanning. Critical/high findings in obsolete Android, homelab/P2P, PocketBase/account, embed-proxy and movie/TV code were removed, not dismissed as false positives or hidden from the workflow.
- The supported product graph is iOS, a bounded sports companion web surface and the Cloudflare playback/football/Coach Worker. Do not restore a tunnel, Python server, PocketBase route, browser credential store, same-origin player proxy or Android build by copying historical code.
- Third-party player pages remain a real provider-origin risk. Keep them on distinct origins, retain exact-origin message admission and navigation guards, and do not describe their UI, ads, availability or content as Fotty-controlled. A redirect or successful frame load is not decoded-playback evidence.
- GitHub Actions are commit-SHA pinned. Dependency update PRs must preserve the reviewed action origin and full hash. Advanced CodeQL covers Actions, JavaScript/TypeScript and any surviving Python; Swift stays under the simulator-free Xcode gate until bounded extraction works.
- Status: protected PRs #10 and #11 are merged. The post-merge `main` Actions/JavaScript/Python CodeQL scan reports zero open alerts; repository-quality and web gates pass. This does not add Swift CodeQL coverage and did not deploy the app, Worker or public web.

## Native PiP background continuity (Unreleased)

- A visible system PiP window does not by itself prove that playback will
  survive Fotty entering the background. Native players must retain
  `.continuesIfPossible`, the `.playback` audio session must be active at the
  real play/PiP boundary, and active PiP must not enter the ordinary
  foreground-resume path.
- Unit policy and a generic-device Release build cover Fotty's state and build
  contract, but cannot certify iPadOS scheduling, a header-proxy stream, system
  controls, or lock-screen continuity. Before distributing this correction,
  use a real native handoff on the physical iPad, open another app for at least
  60 seconds, lock/unlock once, and confirm the same source keeps advancing
  without duplicate audio.
- Do not activate the audio session at app launch or ordinary foreground entry;
  that would interrupt another app's audio before the user starts playback.
- Status: corrected locally on 2026-08-30; not installed or uploaded. The
  physical acceptance step remains open in `docs/notebooklm/QA-Playbook.md`.

## Platform modernization boundaries (TestFlight build 45)

- Build 45 proved that distribution-sensitive launch gates can expose the wrong
  labels and data path to legitimate testers. The StoreKit unlock and alternate
  review-safe graph are retired in current source. Do not restore receipt-name,
  AppTransaction-environment, persisted-default, environment-variable or remote
  unlocks. A future paid tier requires a separately designed StoreKit product;
  it must not alter ordinary sports vocabulary or silently substitute the app.
- A full Swift 6/complete-concurrency diagnostic currently fails. Migrate
  incrementally, beginning with non-playback shared state, then delegate and
  WebKit/proxy boundaries under focused tests. Do not suppress isolation errors
  or switch language mode in one release merely to claim modernity.
- The source compiles with an iOS 18 deployment override, but checked-in minimum
  26.4 is unchanged. Lowering it expands the supported runtime matrix and needs
  an iOS 18 physical smoke plus current-OS gates; compile success is not runtime
  certification.
- TypeScript 7 is blocked by the current Next compiler-package check, and ESLint
  10 by Next's bundled plugin peer ranges. Keep TypeScript 5.9 and ESLint 9.39.5
  until upstream compatibility advances. The current web lint has zero errors
  and 93 warnings; reduce those deliberately rather than weakening rules.
- Node 24 LTS is the declared production baseline. The workstation's unrelated
  Node 25 installation is end-of-life and must not define release behavior.
  Keep Wrangler pinned, dry-run before deploy, and do not enable Worker Node
  compatibility without a code-level requirement and contract rerun.
- Swift CodeQL does not currently complete an instrumented Xcode 27 app build
  within an acceptable hosted-macOS budget; default and explicit manual setups
  were both tried. Do not report Swift CodeQL coverage. Retain the complete
  simulator-free iOS gate, and revisit after the Xcode/CodeQL toolchain changes.
- Status: `docs/audit/Fotty-Platform-Modernization-Audit-2026-08-29.md` and
  `docs/releases/Fotty-2.0.0-45.md` retain the historical migration record.
  Physical installation exposed the restricted vocabulary in build 45, so it is
  not an acceptance candidate. The web source and Worker compatibility-date
  change remain undeployed.

## Seasonal club membership and league inference (Unreleased)

- Historical participation and one matching opponent are not current
  competition evidence. Domestic inference requires both current senior teams
  and rejects cup/youth/friendly/lower-division markers. A provider text label
  cannot override a known membership conflict.
- The reviewed 2026/27 manifest is shared across iOS/web classification, club
  browsing/bootstrap, social fallback, news topics and web Team Alerts for five
  domestic leagues plus UCL/UEL. Generation rejects wrong counts, duplicates,
  cross-club alias collisions and stale output.
- Provider spelling remains unstable even within one day. Known senior clubs
  must resolve through the generated Swift/TypeScript identity, not a new local
  alias dictionary. Current competition membership and historical identity are
  separate: adding a former club for fixture matching must not add it back to a
  league. Where both canonical teams and kickoff reconcile to the official
  schedule within six hours, use that competition; otherwise keep fail-closed
  provider-marker/two-current-club logic.
- Shared URL-free provider vectors and
  `tools/audit-provider-football-identity.mjs --live` are release gates. The
  live check intentionally blocks when every metadata feed is unavailable; do
  not weaken it to preserve an upload schedule. It requests metadata only and
  must not log event IDs, stream URLs or credentials. On-device conflicts keep
  only a redacted reason/source class.
- Release checks fail after 30 June 2027. Verify every official source and all
  seven memberships before changing the season label/date; never carry the
  current manifest silently into 2027/28. All Football can still show valid
  broadcasts outside these competitions.
- Status: build 45 contains the original seasonal-membership correction. The
  identity resolver, official reconciliation and live drift gate are later
  local Unreleased work; see
  `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md`. Physical and
  TestFlight acceptance of that later work are still outstanding.

## Coach conversation lifetime (Unreleased)

- Clear/disable/disconnect must prevent pending successes and failures from
  reappearing. Old-manager completions cannot alter a newer conversation or stop
  its loading state. Navigation alone preserves valid work.
- Check request identity, consent and planning context before committing model
  or fallback output. Discard stale replies with an explanation, not a paid retry.
  Fallback retains published-fact/freshness rules. Keep explicit current-score
  phrasing aligned between Swift and Worker; strategy must remain model-backed.
- Cancellation cannot recall shared data or guarantee zero upstream cost. Offline
  delayed responses verify client behavior, not live reasoning or server billing.
- Status: `docs/audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md`.
  Internal TestFlight build 45 contains the iOS changes. The deployed Worker does
  not contain the companion classifier change from this audit.

## FPL draft and publication boundary (build 44)

- A public gameweek snapshot is not the authenticated current team. Keep its
  actual gameweek and source visible, especially when the next deadline's picks
  are not published yet. Never request passwords/session cookies to hide that limit.
- Saved local drafts survive refresh/reopening and remain separate when new
  official picks arrive. Viewing published picks must not delete user intent.
  Scoring, autosubs, published captain/bench facts and rival results must never
  inherit hypothetical draft players, chips, history or multipliers.
- Drafts are on-device, manager/season scoped, not cloud-synced. Unsaved Transfer
  Lab staging still needs Save. Legacy and companion-context preferences must
  stay compatible when the owner moves between direct builds and TestFlight.
- Phone-only validation does not authorize TestFlight upload, another device,
  tester/notification changes or a paid Coach call. Exact build-44 device and
  cleanup evidence is in `docs/releases/Fotty-2.0.0-44.md`.

## Guardrails from the 2026-08-28 complexity audit

- **Status**: The original audit is historical pre-fix evidence. All five boundaries are fixed with regressions; see `docs/audit/Fotty-Complexity-Fixes-2026-08-28.md`. The Worker fixes are deployed as `fafdf5ed-4d37-47e6-82b8-69dd55c3e116`; iOS 43 is qualified and Internal / Testing for the unchanged two-tester group, verified at 2026-08-28 12:47 AST after the owner-approved declaration/notes/group submission. Physical acceptance and received feedback remain open. The app fixes are not in 42. Current distribution/acceptance is recorded in `docs/releases/Fotty-2.0.0-43.md`, not inferred from the earlier local report.

## Next-phase compatibility and acceptance

- The unchanged normal Release app/extension pass an unsigned iOS 18 compile probe, but build 43 still ships with minimum 26.4. No older-device runtime or lower-target Review Safe result is implied; see `docs/audit/Fotty-Device-Compatibility-2026-08-28.md`.
- Existing-group installation and TestFlight metric dashes are not task-success evidence. `docs/beta/ROUND-01-ACCEPTANCE.md` requires exact-build iPhone/iPad playback, retained data, reminders and one received report before more invitations.
- The next-phase Coach cases are a specification, not a completed strategic-quality evaluation. Backup/sync, hard Coach budgets and a new name retain explicit implementation/owner-decision gates in `docs/NEXT-PHASE-PLAN.md`.
- **Playback progress identity**: Replacement/backward timelines reset the progress baseline, but only real forward progress resets the watchdog. Retain frozen-replacement, pause/background and auxiliary-video regressions; never treat a baseline reset alone as recovery.
- **Media/document ownership**: After start, only the confirmed video/document may fail or recover the broadcast. Preserve genuine pre-start rejection, primary errors and grace cancellation. Synthetic tests are not physical WebKit/provider acceptance.
- **FPL completeness**: Missing/invalid/duplicate picked-player evidence is unknown. Suppress all projections/derived totals until complete; preserve only supported official totals with an incomplete label. Nil/null is distinct from a genuine zero. Reject known gameweek mismatch. Do not reintroduce default-empty stats or dictionary duplicate traps in the live engine.
- **Deterministic scoring**: Recognized scoring questions must not fall through to the model on missing/stale data. Local scoring freshness uses picks/live timestamps; explicit stale Worker HTTP evidence is rejected. General tactical advice remains model-backed. The classifier is an explicit language pattern, not universal semantic understanding, and header freshness cannot prove upstream data generation when headers are absent.
- **Coach request boundary**: Keep null/scalar/array/nested-shape, chunked/oversize/interrupted-body and configured limiter-failure tests. A configured limiter outage returns 503, not an unbounded paid fallback; absent optional bindings are unchanged, so account-level spending controls still matter.

## Scheduled starts and opt-in reminders

- **Do not promise availability**: Starts in is a schedule countdown. The two-minute play affordance permits an explicit lookup, not a guarantee that a provider is ready. Unknown times and channels have no invented countdown. Empty resolution stays inline with Retry; no background stream probes or automatic playback.
- **Consent and races**: Only Remind me schedules a five-minute alert. A save/follow is not consent. Serialize system requests and check per-event intent after every suspension; cancellation must prevent delayed permission prompts and remove late add/reschedule completions. Unsave cancels the reminder, whereas bell cancellation preserves the bookmark.
- **Closed-app limit**: OS local notifications can arrive with the app closed, subject to permission/Focus/system settings. Schedule changes can only be learned during a refresh; a static CPL snapshot cannot promise real-time rescheduling. Missing catalog rows or changing IDs are not cancellation evidence. Update only exact fresh IDs and known matched status; never replace source snapshots from the source-less disk cache.
- **Capacity and honesty**: Bound match reminders to 32 and check total pending capacity. Keep FPL/score-alert namespaces intact. Never enqueue an overdue alert after relaunch or late permission acceptance. Denied permission and failed scheduling must not show as a working reminder.
- **Device acceptance**: Deterministic scheduling/routing tests and a normal iPad process hold are not a locked-device delivery or real notification-tap test. Those remain explicit physical acceptance items for build 40; see its release record. A passive future fixture must not be a disabled parent button that dims all its text/badges; this was caught physically in 39 and corrected in 40.

## Cross-sport discovery and appearance

- **Counts and curation**: Home counts unique events, not source variants. Its deduplication is deliberately exact (ID or sport/start/both names); inconsistent provider aliases and kickoff times still need separate reconciliation. Never merge doubleheaders, borrow channel sources or treat a source descriptor as decoded playback.
- **Timing**: “On now · listed start” is a catalog estimate, not an official score. Unknown formats/times and channels do not enter on-now counts. Final/cancelled facts override estimates; stale or unavailable live-score evidence falls back to labeled timing. All sports uses the existing football polling owner, not a second live/API loop.
- **Overflow and quiet periods**: Keep the compact phone selector bounded while exposing hidden activity in More sports. On iPad, including Split View, show all sports in equal-sized width-aware rows; larger text reduces columns instead of increasing only one tile. The full lineup stays on Home, and later-day fixtures remain reachable when Now & next is empty. A selected overflow sport and a followed-only filter must remain visible.
- **Appearance**: Dark-default Light/System choice is implemented in build 37 with adaptive semantic tokens and inheriting forms/FPL sheets. Use `accentText` for amber ink on light surfaces, `accent` for gold filled actions with `textOnAccent`; do not interchange them. Media/pitch exceptions must stay scoped, not force all browsing dark. Automated contrast/render evidence is not complete daylight/VoiceOver or physical preference-switch acceptance.
- **Sports identity**: Preserve actual team badges and equipment icons when refining density. Fit whole crests instead of cropping them; use existing provider/catalog imagery and named initials when unavailable. Do not invent an opponent or crest for a channel/non-team event. Home's new text-only row omission is corrected in build 37.
- **Provider transport**: Deliberate pause is not a stalled stream. No delayed recovery/handoff may unpause it or switch the selected source. The app's passive surface observation must never delay provider button taps. Build 36's process hold does not certify the reported centre/lower-left gesture; the real pause-and-resume acceptance remains open.

## CPL schedule and cricket channel truth

- **Manual snapshot**: The bundled CPL 2026 schedule was checked on 27 August, including the July TKR opponent swap. Recheck league announcements before each release during the season. Its dated disclaimer and season expiry are mandatory; this is not a live schedule feed or score API.
- **Channel versus fixture**: Willow/Fox listings are channels, not evidence that a particular match is airing. Keep them outside dated rails and retain channel bookmarks despite negative provider date sentinels. Never attach a channel source to a CPL fixture by league name alone.
- **Identity/timing**: CPL stream enrichment requires both franchises and a kickoff within one hour. Unknown cricket formats must not inherit football's two-hour end. Score lookups must retain football-category and kickoff guards.
- **Evidence limit**: One decoded Willow broadcast proves that variant worked at that time, not every variant, future programme availability or physical iPhone/iPad playback. Existing provider availability and regional restrictions still apply; no paid Willow integration is being added.

## UI refinement and navigation continuity

- **Guardrail**: Preserve the root-owned FPL session, not invisible full-screen views whose pollers continue running. Keep manager selection invalidation intact. Comparison uses player IDs rather than sorting-dependent indices, and Coach draft/pending state must survive ordinary tab changes without permitting a duplicate in-flight question.
- **Readability**: Difficulty colours have one shared numbered scale and a 4.5:1 text-contrast regression check. Do not restore 7–8-point pitch labels or shrink the whole iPhone interface to make a five-player row fit. Large text uses a roster; measured-width Plan columns collapse when space is insufficient.
- **Filters**: Competition/cricket pickers retain native appearance. The newly approved sport-activity selector uses real buttons with selected/value semantics. Keep all six Home accessibility scopes and the actual filter/overflow/lineup interaction check. The beta-Mac contrast analyzer currently reports fixed high-contrast elements despite captured-pixel and >=7:1 actual-color unit evidence. New trial exceptions were removed; this audit remains open, not green. Do not substitute a passing color calculation for physical Display Zoom/daylight/VoiceOver acceptance.
- **Verification limits**: Populated Catalyst tests and normal/Review Safe compilation do not prove physical iPhone Display Zoom, keyboard geometry, daylight readability, VoiceOver, provider playback, or engagement improvements. Do not mark the new UI released until it has a higher build number and explicit physical qualification. Catalog duplicates remain a separately scoped identity diagnosis, not something typography fixes.

## Beta usability and feedback delivery

- **Risk**: A working build can still leave new testers stuck on an incorrect FPL ID, expecting background match alerts, or sending reports through retired web infrastructure.
- **Guardrail**: Native Help/report preparation must not require the former website. Keep reports local until a tester copies/shares them, default diagnostic inclusion off, and never equate a clipboard/share action with delivery. Match alerts are foreground score-fetch updates; separately scheduled FPL deadline reminders are not evidence of a background push service.
- **FPL identity**: Lookup and confirmation are separate. Keep team links editable on failure; disconnect/switch invalidates pending manager, review, league, rival and Coach responses and clears visible state without deleting scoped drafts/history.
- **Verify**: Run the beta-usability unit/navigation checks and `docs/BETA-TESTER-GUIDE.md` fresh-user matrix. Before expanding the TestFlight group, upload a higher-numbered build and confirm receipt of one actual tester report. These distribution/human checks are not replaced by local compilation or source review.

## FPL decision integrity and current-season schema

- **Risk**: The FPL surface depends on undocumented public endpoint contracts and could regress into official/live labeling if facts, cached snapshots, estimates, and AI explanations are not kept distinct.
- **Guardrail**: Use official public fields and endpoints where available; keep measured data, modeled projections, and editorial notes visibly distinct. Derive gameweek phase from deadlines rather than a gameweek number, support the current chip/free-transfer rules, paginate league results, and never fabricate a fallback value.
- **Verify**: Keep captured JSON contract fixtures for bootstrap, manager, picks, history, league standings, element summary, and event-live. Test deadline boundaries, blank/double fixtures, chips, rolling transfers, captain/vice/autosub behavior, and unavailable/error states.
- **Current status**: Bootstrap, league paging, event-live, phase, reminders, rolling transfers, shared legality/optimizer behavior, structured coach-history compatibility, journal isolation, route checks, Rival Race, and explicit blank/double projection and autosub boundaries have focused coverage. Official live points/BPS/bonus and autosubs are integrated with freshness/provenance labels; fabricated EO/rank/Monte Carlo surfaces remain removed. Rival Race refuses planning-phase squad comparison because rival picks are not yet public. Endpoint drift and real unusual fixture schedules still require ongoing observation.

## FPL live total and automatic-substitution integrity

- **Risk**: The official current total can temporarily exclude unprocessed automatic substitutions, while raw zero minutes are ambiguous until all of a player's gameweek fixtures finish. Allowing an LLM to recalculate either state can produce a confident but invalid total.
- **Guardrail**: DeepSeek never calculates or overrides current points. Use the shared deterministic policy: preserve the official current total, require completed fixtures before declaring a non-appearance, require the incoming player to have appeared, enforce goalkeeper-only replacement and legal outfield formation in bench order, apply captain fallback and transfer cost, and label any unresolved difference provisional. Stop projection when official data is checked. LiveFPL may be used as a behavior benchmark, but Fotty must not depend on or scrape it for manager totals.
- **Verify**: Test goalkeeper plus outfield replacement, formation-driven bench skipping, captain/vice fallback, transfer hits, bench boost, doubles with a fixture remaining, official published substitutions, and final data-checked totals. During a real pending-autosub state, compare the named replacements and both totals with official FPL before and after processing.

## FPL secrets and third-party AI disclosure

- **Risk**: Provider credentials previously embedded in the app may remain valid in provider dashboards, Git history, or released builds even after source removal. The server coaching route adds privacy, abuse, and spend exposure if consent, rate limiting, or account controls drift.
- **Guardrail**: Rotate exposed credentials immediately. Never ship provider secrets in the client. Keep deterministic local fallback; route only explicitly consented, minimized requests through the Worker; scope stored coach history and drafts by manager and season. Treat Worker Rate Limiting bindings as abuse controls, not a billing ceiling, and set a Cloudflare account spending limit before deployment.
- **Verify**: Secret scanning finds no provider credentials in source or build products, network inspection matches the privacy disclosure, the unavailable/over-limit path falls back locally, manager switching cannot reveal previous drafts/chat, and the Worker is not described as live until its newly issued secret and spend ceiling are configured.
- **Current status**: The app and inspected build products contain no AI credential and local fallback is always available. Worker version `39e913bd-d1fb-48e4-bf56-20be2ba183e4` is production-active. Deterministic scoring returned fresh official evidence with zero tokens; a bounded model smoke returned evidence, uncertainty, actions, source/model, freshness, and usage. Empty, truncated, malformed, incomplete-schema, and known rule-contradicting model results fail closed. The historically exposed tunnel credential is revoked: its exact retired tunnel was deleted with owner authorization, every accessible account reports zero active tunnels, and the Worker remains healthy. Both affected advertised branches were rewritten and verified clean without moving `main` or tags. GitHub closed Support ticket `#4701297` after purging the retained objects; both obsolete commits are independently unreachable and all PR refs are absent. Maintaining an account spending ceiling remains an operator responsibility.

## FPL squad legality and optimizer claims

- **Risk**: Local swaps, transfer recommendations, and the wildcard generator can create duplicate players, illegal formations, invalid club quotas, or unaffordable squads. Labels such as “Official Transfer Hub”, “Apply”, “ILP”, and “100% optimal” overstate local-only or greedy behavior.
- **Guardrail**: Enforce one reusable squad/rules validator at every mutation and validate optimizer output before display. Call local changes drafts, state that official FPL is not modified, and only claim optimization methods or guarantees that the implementation proves.
- **Verify**: Add property-based rules tests for every mutation path and adversarial optimizer fixtures covering budget, position quotas, maximum three players per club, captain/vice eligibility, goalkeeper substitutions, and minimum legal formations.
- **Current status**: All current editing paths use the shared validator, and constrained optimizer output is validated before display. Unit coverage proves representative legal and illegal squads; broader property-based and UI mutation coverage remains desirable.

## FPL accessibility and test coverage

- **Risk**: The FPL feature has improved semantic typography and interaction labels but still lacks a complete physical-device accessibility certification and end-to-end feature UI coverage. Focused unit tests do not validate the entire advisor workflow, widget timeline behavior, or every compact iPhone layout.
- **Guardrail**: Keep new controls at least 44 points, prefer semantic/scaled typography and adaptive grids, label interactive elements, expose visual meaning textually, and add focused unit/UI coverage before expanding the surface. On compact iPhone widths, reduce spacing and redundant chrome rather than scaling the whole view or clamping Dynamic Type. Composer actions must resign focus deliberately so replies are not obscured by a persistent keyboard.
- **Verify**: Run FPL schema/rules/engine unit suites plus large Dynamic Type, VoiceOver labels/actions, hit targets, contrast, loading/error/retry, and manager-switch UI tests. On a physical iPhone, verify that Send, Return, quick prompts, and interactive scroll all dismiss the Coach keyboard as intended.
- **Current status**: Compact Squad actions split into semantic summary/action rows and Coach focus handling is implemented. The complete build-33 Swift suite is green. Build 29 corrected the actionable Home empty state found by the exact contrast audit. The exact build-33 aggregate passes all eleven accessibility audits—six Dashboard scopes plus FPL, Matchday, Settings, Match Center, and Player Dynamic Type—and rapid navigation/foreground recovery in one invocation. Explicit network-free fixtures audit every FPL workspace with a visible structured Coach response, catalog-only Match Center, and the truthful Player recovery state; a source contract proves every quick prompt clears focus through the shared send path before adding the message. Physical build-19 Home captures on both sizes closed false non-covered score copy; build-20/21 iPad Plan review closed clipped narrow metrics; build-30 compact Coach Send/Return both passed. Build 33 retains contained compact shirts/nameplates and the Debug-only normal-app routing used for physical Squad/Coach captures without a test runner, while build 31's corrected small/medium widget plus FPL tap route pass on hardware. The owner confirmed direct large-Type interaction on both form factors on 2026-08-26; physical accessibility interaction acceptance is complete.

## FPL Matchday context freshness

- **Risk**: A squad badge or Match Lens can look current even when it came from an older published squad, a local draft, or the last official live snapshot.
- **Guardrail**: Home, Matchday, and Match Center read only the device-local `FPLMatchdayContextStore`; they never start another FPL request path. Preserve the snapshot's gameweek, phase, and updated time, expire it after 21 days, clear it on manager removal/change, and never describe local draft changes as submitted to official FPL.
- **Verify**: Unit-test persistence, expiry, team aliases, manager clearing, starter/bench/captain roles, and optional live points. On device, open FPL first, verify freshness, then compare Home, Matchday, and Match Lens against the same squad.

## Playback truth and provider volatility

- **Risk**: A healthy catalog or loaded iframe can be mistaken for playable video. Provider manifests, CORS policy, ad layers, and domains change independently of the app.
- **Guardrail**: Only decoded playhead progress marks a source successful. On Home, `LIVE` means the catalog advertises a supported broadcast and the row must remain manually watchable; recent health can influence automatic ordering but cannot turn it into a dead row. Use `IN PLAY` for active score/schedule rows without a supported source. Never synthesize Echo/Admin when their catalog supplies zero variants; canonical zero-variant fallback is limited to the known Hotel/Delta/Golf/India URL contracts and only applies when the event has no real variants. Do not show HD/SD duplicates as separate broadcasters. Preserve the 20-second web-start window, one same-source startup retry, stall watchdogs, typed failures, bounded failover, and exact active-attempt guards. Do not treat an AVPlayer error-log entry, a short pause, a network-path transition, or web background/foreground as permission to rebuild or switch while the current item can still resume; preserve the attempt and final-check progress before switching.
- **Verify**: Run `tools/stream_health_checker.py` for catalog health and `node tools/audit_live_playback_matrix.mjs` for decoded browser playback. Never infer the second result from the first.
- **Current status**: The corrected 2026-08-25 matrix decoded advancing 960×540 video from one of four current families in about 13.8 seconds with media HTTP 200 and zero popups. Later Admin/Golf samples passed 20–45 second browser holds without media-request failures or popups. On physical build 28, a current three-source event decoded on both devices and held Broadcast 1 beyond 60 seconds with advancing frames and no source change. Background/foreground preserved the same source; iPad entered real PiP after native handoff; termination removed the PiP surface. A stale zero-variant Echo event now fails immediately without a fabricated URL and says `AVAILABLE · Open broadcast`. Exact build 30 then decoded and visibly advanced the same selected Broadcast 1 on both devices after the narrow provider-solicitation filter; the fake VPN/install prompt was absent and the legitimate iPad unmute prompt remained present. The owner directly confirmed iPad unmute and Pause, a later frame proved Play/resume on the same source, and the owner reported no ticking or duplicate/overlapping audio. Deliberate Broadcast 1 → 2 → 1 switching also succeeded and ended with Broadcast 1 visibly selected and advancing. URL-bearing reports and temporary screenshots were removed after redacted extraction.
- **Latest target**: Toronto Blue Jays–Kansas City Royals supplied three current Admin/Delta/Golf choices and decoded Broadcast 1 on both devices during the build-28 and build-30 physical gates. Availability remains time-dependent; refresh the catalog rather than preserving this route as a permanent test fixture.
- **Network isolation**: Local proxy diagnostics must stay on-device. Never add per-manifest or per-segment remote telemetry in the playback data path.
- **Web isolation**: A direct cross-origin iframe cannot prove decoded progress. Its `load` event is only frame readiness: do not mark it successful, but also do not auto-replace a loaded feed solely because the parent page cannot observe its playhead. Hide native-only PiP and browser-escape controls on that path.

## Provider navigation trust boundary

- **Risk**: Third-party embeds can navigate into ads or unrelated origins, and some provider-controlled or same-origin ads cannot be distinguished safely from required player content.
- **Guardrail**: Block popups, user-triggered top-level navigation, `embed.st/ad.html`, observed nuisance-host chains, and accessible ad overlays while allowing rotating HTTPS media/player child-frame origins needed for playback. Disable `window.open` inside the isolated embed; never blanket-remove generic overlays because those can be required player controls. The only solicitation-text rule currently allowed is the exact VPN/install/continue-watching combination, and a matching ancestor is protected whenever it owns video, owns an iframe, or covers essentially the player/root viewport. Do not restore a user-facing browser escape. Do not claim all in-stream advertising can be removed without provider control.
- **Verify**: Exercise source selection and failover with the WebKit console attached. On hardware, prove a healthy stream advances with the matched solicitation absent while the provider's real unmute control remains available.

## Web playback control ownership

- **Risk**: SwiftUI gestures or recurring injected JavaScript can make the entire WKWebView behave like one app button, intercept provider play/pause controls, or immediately undo the provider's direct unmute gesture.
- **Guardrail**: The standard player delegates visible media controls and audio gestures to the provider. A non-cancelling surface observer may reveal Fotty's bounded Play/Pause fallback, but it must recognize simultaneously and never turn the complete WKWebView into one consuming button. Do not render a second unmute control, remove the provider prompt, or continuously set `muted`, `defaultMuted`, volume, or JW Player mute state. Fotty-controlled mute synchronization is allowed only for MultiView focus and explicit muted diagnostics.
- **Verify**: On a currently decoding physical iPhone/iPad stream, independently tap play, pause, seek/fullscreen when offered, and the provider's `Tap to unmute`. Confirm each control responds directly and remains in its selected state. DOM property probes and builds are not substitutes for this interaction check.
- **Background boundary**: A standard provider embed keeps its own foreground controls and audio ownership, but Fotty suspends every reachable media frame when the app enters the background and resumes the same selected attempt on return. This prevents hidden provider/ad audio without treating backgrounding as a source failure.

## Launch-time observation and polling

- **Risk**: Mutating observed caches during SwiftUI evaluation or assigning multiple owners to live polling can cause render loops, request storms, and scene-create watchdog termination.
- **Guardrail**: Keep derived lookup caches `@ObservationIgnored`; cache misses explicitly; use `MatchListViewModel.shared` for Home and Matchday; only the visible fixture tab runs the bounded catalog loop. `LiveScoreService` remains a singleton and `startPolling()` performs its own immediate refresh, so do not add another immediate score refresh beside it.
- **Verify**: Cold-launch on a physical iPad for at least 60 seconds and confirm one initial score refresh, a responsive UI, and no `0x8BADF00D` termination.
- **Current status**: The exact normal `2.0.0 (33)` app launched on the authorized iPhone and iPad on 2026-08-26, and CoreDevice observed its foreground process for the complete 60-second bounded hold on each. This closes process survival for the release candidate; the earlier direct iPad review remains the evidence for responsiveness and visible refresh behavior.

## My Matchday snapshot freshness

- **Risk**: A saved match must survive relaunch, but persisting a provider URL indefinitely would make stale or removed broadcasts appear trustworthy.
- **Guardrail**: Persist catalog identifiers and team metadata only as a bounded snapshot, prune 36 hours after kickoff, prefer the current shared catalog when it has sources, and ask `LiveStreamResolver.catalogEvent` to rematch before playback. Saved status is a user preference, not proof that video is currently healthy.
- **Verify**: Save/remove/relaunch tests cover persistence and pruning. On a live fixture, confirm the bookmark does not trigger Watch, the Matchday row retains an honest Watch/Details action, and provider failure still reports the normal bounded playback error.

## External score and match-detail dependencies

- **Risk**: The match catalog can work while rich scores, statistics, lineups, or timelines fail because public schemas, API credentials, or proxies are unavailable. The public FPL JSON is practical for this personal build but is not a licensed commercial score agreement; its schema, cadence, or availability can change. Multiple devices or automatic Match Hub refreshes can also exhaust API-Football's small fallback allowance.
- **Guardrail**: Keep catalog rendering independent from enrichment and show useful unavailable/retry states instead of fabricated data. Live scores remain Premier League-only. Accept only fresh non-disk FPL fixture data, normalize FPL teams onto schedule identities, retain explicit provenance, and preserve API-Football/football-data fallbacks. Route all API-Football calls through `FootballQuotaBudget`, preserve its four-minute shared cache, 80-call UTC-day ceiling, and 20-call provider reserve, and never let automatic/timer Match Hub loads request enrichment. Label football-data fallback as delayed.
- **Verify**: Test active/scheduled/provisional FPL fixture mapping, team aliases, stale snapshots, unauthorized/offline paths, current-season-access-restricted API fallback, quota reservation, delayed fallback, cache hits, and daily-budget responses. During the next live Premier League match, measure official FPL score/minute latency and confirm stable schedule identity, notification routing, and Match Center updates. Production `/health` must still show API-Football competition id `39`; credential configuration is not proof of current-season enrichment access.
- **Current status**: The app now recognizes its single-league `league/season/date` API-Football request as Worker-proxied when no client credential exists; focused coverage prevents the former local unauthorized failure. The deployed Worker health route reports the schedule credential and Premier League quota boundary, and a live schedule smoke returned fixtures. Current-season enrichment access remains provider-plan dependent.

## FPL offline snapshot contamination

- **Risk**: An old gameweek, prior-season roster or unrelated cached endpoint can make Coach/scoring/planning output appear current while offline.
- **Guardrail**: Disk snapshots include schema version, endpoint, saved time, season and optional bootstrap team fingerprint. Reject future timestamps, endpoint mismatch, wrong season, fingerprint mismatch and endpoint-specific expiry. Never treat a rejected snapshot as zero or current data.
- **Verify**: Unit-test the July rollover plus live/bootstrap/fixture age boundaries, wrong seasons and fingerprint mismatches. Keep UI provenance/freshness visible and re-run against the official API around season rollover.
- **Current status**: Version-3 envelopes and bounded pruning are implemented. The next physical/offline acceptance should prove an expired live snapshot produces an honest unavailable state.

## Local-only social scope

- **Risk**: The legacy name `SocialCloudStore` can lead agents or UI copy to imply accounts, community delivery, or cloud sync.
- **Guardrail**: Treat it as on-device SwiftData persistence. Do not add sign-in or remote-success UI without a real authenticated backend and product approval.
- **Verify**: Privacy and Settings copy accurately state local storage; messages persist locally across relaunch.

## Single product graph

- **Risk**: A future distribution, licensing or review workaround could silently rename sports, substitute data sources, or disable playback for legitimate testers.
- **Guardrail**: Keep one production graph and truthful vocabulary across Debug, Release and TestFlight. Product restrictions must be explicit, user-facing product decisions rather than hidden launch-time mode switches.
- **Verify**: Build the normal generic physical-iOS Release configuration without a simulator, scan production source/build settings for retired review-safe symbols, and physically confirm Home, Matchday, FPL and Watch retain their normal names and actions.

## Accessibility regression risk

- **Risk**: Fixed typography, dense fixture labels, low-contrast treatments, or overlay navigation can regress accessibility even when basic taps still work.
- **Guardrail**: Preserve semantic/scaled typography, the layout-owned dock, concise dense-card formatting, and all bounded accessibility audit categories. Do not recombine them into one audit; XCTest times out on large fixture trees.
- **Verify**: Run the individual UI audit tests. `FOTTY_AUTOMATED_TESTING` limits the cached audit tree to 40 representative fixtures only; production data remains unbounded.

## Dormant P2P/Ace internals

- **Risk**: Legacy defensive playback code can be mistaken for an active supported provider or reintroduced into Watch Now accidentally.
- **Guardrail**: `StreamPluginProviderMatching.activePlayerProviderCodes` remains the single active allowlist and must exclude P2P/Ace sources. Do not ship a P2P manifest or user-facing browser.
- **Verify**: Unit-test active provider filtering and inspect Broadcast Sources on device.
- **Current status**: The analytical provider list is CoreMedia-only, P2P-shaped catalog candidates are rejected before rendering, and the retired Hybrid P2P resolver is behind the undefined `FOTTY_LEGACY_P2P` compile condition. The production resolver consults only enabled StreamEx/Score808 families. Lower-level defensive Ace types still compile for legacy session-shape compatibility but have no active Watch resolution or UI entry point.

## Test isolation

- **Risk**: Hosted unit/UI tests can poll production services, making runs flaky and consuming provider quota.
- **Guardrail**: Preserve `AppRuntime.isAutomatedTesting` checks and `FOTTY_AUTOMATED_TESTING=1` in the shared test scheme.
- **Verify**: Unit logs contain no production match refresh.

## Agent memory and secrets

- **Risk**: Agents can rely on stale decisions or accidentally copy provider secrets into generated memory.
- **Guardrail**: Run `./tools/agent-start.sh` before broad work and `./tools/agent-finish.sh` after it. The generated bundle must source the canonical `docs/notebooklm/QA-Playbook.md`, not the obsolete `Fotty-QA-Playbook.md`. Never store tokens, private stream URLs, or credentials in durable markdown.
- **Verify**: Brain doctor succeeds; the generated bundle contains the current build-33 QA heading/date and completed physical procedure; a smoke query returns the current iOS playback/provider scope. The owner-authorized deletion of the historical credential's exact tunnel completed revocation. Fresh advertised heads and tags no longer reach `cert.json`; after GitHub closed Support ticket `#4701297`, both obsolete commit API requests return `No commit found`, both public web pages return HTTP 404, and all four retained PR refs are absent. Never push or merge the dirty old local branch back into cleaned history; any publication must replay the release tree onto the cleaned remote ancestry.
