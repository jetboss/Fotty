# Fotty NotebookLM Master Source

Generated: 2026-08-30 12:24:36 AST

This file is generated from safe project-memory sources and redacted command output.
Upload this one file to NotebookLM when you want a fresh project snapshot.

Do not paste secrets into this file.



# Project Memory

# Fotty Project Memory

Last updated: 2026-08-30

## Product Positioning

Fotty is an iOS-first live sports companion with optional third-party web playback. The goal is a premium, responsive sports experience where users can:

- Discover live and upcoming matches
- Open a live match quickly (Sub-10s startup goal)
- Choose available broadcast sources
- Follow match context, timeline, highlights, and basic diagnostics
- Track and plan Fantasy Premier League squads using official public FPL data

World Cup–specific hubs, seeds, and tournament-focus modes are retired (tournament over). Home discovers fixtures and channels via StreamEx; Matchday is the personal plan built from explicitly saved broadcasts and followed teams. FPL belongs in its dedicated tab, not repeated prompts, badges or automatic squad entries elsewhere.

## Current Platform Scope

- **Native PiP background-continuity correction (local Unreleased, 2026-08-30)**: A real iPad native handoff could enter PiP but paused when Fotty moved behind another app. The app had the audio background mode and PiP controller, but only set the playback audio category; it did not explicitly activate the session when playback began, and `AVPlayer` retained the system-decided `.automatic` background policy. Native players now use `.continuesIfPossible`, activate the playback session at play/PiP boundaries, preserve the active PiP attempt through backgrounding and do not arm a false foreground resume. PiP UI restoration is acknowledged by the retained player presentation. The full simulator-free Catalyst unit suite and unsigned generic iOS Release pass. Real app-switch/lock-screen continuity still requires a native physical-device stream; this fix is not installed or uploaded.

- **Clean GitHub baseline and app-wide discovery search (Unreleased, 2026-08-30)**: The public repository now starts from a reviewed clean root rather than the obsolete two-commit history that still contained retired Android credentials. Both stale remote Cursor branches were removed. GitHub secret scanning, push protection, Dependabot security updates and CodeQL default setup are enabled; Actions now own bounded Web, iOS, workflow/secret and daily provider-metadata gates. `tools/ios-ci.sh` never uses a simulator, cleans its one DerivedData root and adapts only its Catalyst test host target on GitHub—the real generic iOS Release target is unchanged. Home now exposes a global search over the exact shared `HomeSportsDiscovery` projection, including teams, sports, football leagues, CPL fixtures and broadcast channels. Search performs no independent fetch and reuses Home badges, live-score qualification, countdowns, reminders and Watch routing. Exact Premier League queries cannot collide with Caribbean Premier League. Local Catalyst tests and unsigned generic iOS Release pass; the change is not versioned, installed or uploaded to TestFlight yet.

- **Football identity drift prevention (local Unreleased, 2026-08-30)**: Chelsea–Brighton exposed a provider `and` versus catalog `&` alias drift, not an incorrect Premier League schedule. One generated Swift/TypeScript club resolver now owns known aliases and deterministic match keys; current-league membership remains separate from historical team identity. Home reconciles canonical teams plus a six-hour kickoff window to the existing official schedule and uses its competition when proven. Rejected provider markers record redacted local evidence. Five shared payload vectors and a metadata-only live provider audit run before the no-simulator release gate. The audit found and resolved Deportivo wording and excluded a Bundesliga 2 multiview listing, then passed all three reachable feeds. Web/Worker 87/87, TypeScript, complete Catalyst policies and generic iOS Release pass. This is not uploaded or installed; see `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md`.

- **Single product graph / internal TestFlight build 46 (2026-08-30)**: Physical TestFlight use exposed build 45's restricted `Field Events` / `Reference` vocabulary. The owner chose to retire the review-safe product rather than patch its StoreKit transition. Current source removes `IntegrityService`, `LicenseManager`, StoreKit environment gating, every runtime live-sports restriction, `APP_REVIEW_SAFE`, its substitute types/plist/configurations and all alternate labels. Debug, Release and TestFlight now share the normal Home/catalog/player graph. Final-source Catalyst units and generic iOS Release pass without a simulator; the focused vocabulary test and app/project retired-symbol scan pass. The Home Catalyst UI test compiled but the beta-Mac runner timed out enabling automation twice before execution, so physical acceptance remains open. Xcode uploaded the signed build at approximately 17:56 AST on 2026-08-29; after processing and the owner's approved compliance/notes/group actions, Apple independently shows 2.0.0 (46) Internal / Testing for Fotty Internal Smoke with two testers at 09:14 AST on 2026-08-30. A direct 09:18 read confirms build 46 is installed on the iPad; the iPhone remains build 44 after TestFlight was reopened. Installation is therefore partial and launch/data/UI acceptance remains open. See `docs/audit/Fotty-Single-Product-Graph-2026-08-29.md` and `docs/releases/Fotty-2.0.0-46.md`.

- **Platform modernization / internal TestFlight build 45 (2026-08-29)**: Internal-distribution access now uses StoreKit's signed `AppTransaction` environment rather than a receipt filename. Debug, verified Xcode and verified TestFlight sandbox sessions receive the internal surface; production, unverified and failed lookups start and remain review-safe. The result is process-local and retried on activation, so a later public build cannot inherit a stored unlock. The web baseline is now Next 16.3.3, React 19.2.8, Motion 13.1.1, HLS.js 1.7.1, Tailwind 4.3.3, pinned Wrangler 4.127.1 and Node 24 LTS, with ES2022 output and zero npm audit findings. Bitcode configuration is removed. TypeScript 7, ESLint 10 and a one-shot Swift 6 switch were tested and deliberately deferred for incompatible tooling or real concurrency failures. An iOS 18 Release compile probe passes, but the checked-in 26.4 target remains because no physical iOS 18 device is available. Evidence is 86/86 web units, zero lint errors (93 warnings), a production web build, a no-deploy Worker dry-run, 219 Catalyst passes plus one opt-in skip, and both generic iOS Release configurations. The signed normal archive passed exact version/signature checks and uploaded at 15:15 AST. After the owner's declaration and explicit notes/group approval, Apple independently shows 2.0.0 (45) Internal / Testing for Fotty Internal Smoke with two invitations at 15:21 AST. No device install, external submission, Worker/web deployment, paid call, simulator, tester/role change or Git publication. See `docs/audit/Fotty-Platform-Modernization-Audit-2026-08-29.md` and `docs/releases/Fotty-2.0.0-45.md`.

- **Reference-data and release-safety remediation (TestFlight build 45, 2026-08-29)**: The owner approved all six follow-ups from the freshness audit. One reviewed `shared/reference-data/football-competitions-2026-27.json` now generates iOS and web catalogs for five domestic leagues plus the Champions League and Europa League, with exact counts, source links, collision checks and a hard 30 June 2027 expiry gate. Home classification, news, onboarding badges, social fallbacks and web team search no longer own duplicate current-season rosters. FPL snapshots are versioned, season-bound, endpoint-age-limited, catalog-fingerprinted and bounded; manager storage keys roll by season. Schedule fallbacks cannot widen an empty requested date window. The universal release unlock and embedded client key are gone; the platform modernization entry above records the signed-StoreKit boundary. Privacy/terms, in-app disclosure and the Apple manifest match local storage, public FPL IDs, opt-in Worker/DeepSeek Coach processing and third-party playback. This app work is now in build 45 Internal / Testing; the web source changes remain undeployed. See `docs/audit/Fotty-Reference-Data-Freshness-Remediation-2026-08-29.md`.

- **Premier League membership correction (TestFlight build 45, 2026-08-29)**: Official 2026/27 membership confirms Coventry, Hull and Ipswich are in; Norwich is not. Home's fallback had a stale roster and accepted either matching club. A shared season-labelled official 20 now drives fixture inference, club browsing/bootstrap and news topics. League inference requires both current senior clubs and rejects provider-label conflicts plus cup/youth/friendly/lower-division markers; explicit Champions League remains separate. Norwich is retained in All Football when legitimately listed. The correction is available in internal build 45; qualification and annual-update limits are in `docs/audit/Fotty-Premier-League-Membership-2026-08-29.md`.

- **Coach conversation integrity (TestFlight build 45, 2026-08-28)**: Public-distribution ideas are deferred; no alternate-distribution pivot was selected. Pending Coach tasks now belong to the workspace: chat clearing, disable and manager removal cancel/invalidate them; changed squad/gameweek/plan/rival context rejects stale replies without an automatic paid retry. Normal and fallback facts share published-picks/freshness checks. Direct current-score wording routes deterministically in both local source trees. The iOS change is available in internal build 45; the Worker remains at its prior deployed revision. See `docs/audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md`.

- **FPL draft correction / private build 44 (2026-08-28)**: Installed only on the owner's iPhone, not TestFlight. Published picks/gameweek and local planning drafts are now separate; refresh/reopening retain saved drafts, published/draft view selection persists without deleting either, and local plans cannot supply live scoring, official chips/autosubs or factual captain/bench answers. The picker shows rejection in place and one-tap transfers check save success. Public pre-deadline visibility remains a real limitation, now labeled. Final tests pass: 200 units (one optional skip), three scoped Catalyst UI checks (existing beta-Mac warnings), 24 Worker contract/scoring tests and both scoped iOS builds. In-place installation, independent version check, a 20-second normal launch hold and unchanged manager/15-player draft/appearance/saved-match preferences are verified. Physical replacement/refresh/reopen and source-toggle taps remain open. Exact evidence and cleanup are in `docs/releases/Fotty-2.0.0-44.md`; shared TestFlight remains 43. The owner now prefers phone-first small fixes and deliberately batched shared TestFlight releases, with unique build numbers and risk-appropriate tests for both. UI mock lineups use clearly fictional test names, not obsolete real players; they are Debug-only and explicitly opt-in.

- **CPL tester invitation / installed 43 (2026-08-28)**: After explicit owner approval of the explained Marketing-role tradeoff, Apple confirmed the invitation was sent to one selected trusted CPL participant (repository alias CPL-03). Marketing and only Fotty were selected, but the fresh pending-user row labels scope All Apps and disables Edit App Access; verify/narrow scope after acceptance before internal-group assignment. Fotty was the only app in the chooser; do not claim future-app restriction is verified. The participant is not yet eligible for Fotty Internal Smoke; do not resend or claim TestFlight access yet. At 13:23 AST both original testers independently show Installed 2.0.0 (43), but exact-device task acceptance and received feedback remain open. See `docs/beta/ROUND-01-ACCEPTANCE.md`. This is one owner-selected addition, not broad expansion authority.

- **Approved next phase / internal release 43 (2026-08-28)**: The owner accepted the gap-priority plan. Release the existing five fixes first, then gather real tester outcomes before broader feature work. `docs/NEXT-PHASE-PLAN.md` records the order and owner decisions; `docs/beta/ROUND-01-ACCEPTANCE.md` records unperformed checks explicitly. Apple preflight confirms both current testers installed 42 but no received screenshot/crash feedback; metric dashes are unknown, not zero. Source is 2.0.0 (43): full qualification, Worker rollout and Apple upload/processing are complete. After the owner's explicit approval, the declaration, English (U.K.) testing notes and existing-group assignment were saved; Apple independently shows Internal / Testing at 12:47 AST for the unchanged two testers. Exact status is tracked in `docs/releases/Fotty-2.0.0-43.md`; installation, physical acceptance and feedback receipt remain open. Worker revision `fafdf5ed-4d37-47e6-82b8-69dd55c3e116` is deployed: health, controlled invalid/oversize requests and missing-scoring zero-token answers pass. No paid-model smoke, new tester/role, simulator, direct install, external submission, new name or Git publication. This approval supersedes earlier discussion-only next-phase notes, but human acceptance is not inferred from tests.

- **Internal TestFlight release 42 (2026-08-28)**: The owner requested updating the existing internal group, followed by discussion-only planning. App Store Connect preflight showed build 35 and the unchanged two-tester Fotty Internal Smoke group (feedback on, manual Xcode distribution). Build 41 already reached the iPad, so the same qualified app source advances to 2.0.0 (42). Normal Release archive/signatures/configuration pass; Xcode reports Upload succeeded at 00:01:49 AST. The owner approved the declaration, tester notes and existing-group assignment. After resolving an expired sign-in and verifying the declaration was still missing, the approved save succeeded. At 06:18 AST, build 42 is **Internal / Testing** for Fotty Internal Smoke, its two testers unchanged, with six testing tasks/known limits saved in English (U.K.). No rebuild/re-upload was needed. This verifies availability, not installation, physical acceptance or feedback delivery. The 314 MB temporary root and 576 KB separate distribution logs are removed, with 40 GiB free. See `docs/releases/Fotty-2.0.0-42.md`. No new feature code, direct install, tester/role changes, external submission, server deployment or Git publication. Do not implement the next product phase without approval.

The release/checkpoint entries retain their historical at-the-time distribution
status; current source and shared TestFlight are 2.0.0 (46). iPad installation
is verified; iPhone installation and physical acceptance remain open.
Build 42 consolidated the app changes from 36–41.

- **Compact match actions, build 41 (installed on iPad, not uploaded)**: The owner approved restoring names/badges left and Watch right and making live saving secondary. Home/full-lineup/Matchday now share a measured row, stacking only for narrow space/accessibility text; future countdowns and reminder controls remain visible, with full-width outcome/error guidance. Save/Remove uses a native long-press menu plus accessibility actions, with updated Help/setup copy. Final 184-unit suite passes (one optional HLS skip, no unit runtime warnings); two scoped Catalyst UI checks pass save/return/removal and channel saving, retaining two beta-Mac main-thread warnings. Both Release configurations and signed Debug pass, app/extension signatures and source fingerprints verify, and iPad independently reports 41 with a passing 20-second argument-free hold. Physical visual/cleanup details are in `docs/releases/Fotty-2.0.0-41.md`. Real iPad menu/bell interaction and locked-device notification delivery/return remain separate acceptance. TestFlight remains 35.

- **iPad follow-up 38 (installed, not uploaded)**: Dedicated Settings → Appearance has clear Dark/Light/System choices; Engineering is removed from normal Settings. Sparse badge caches preserve bundled fallbacks, and static ESPN artwork covers current NBA/MLB clubs. The owner approved equal-sized sport tiles and all sports inline on iPad; measured cells share a two-line title slot and tallest height, with width/scaled-text-aware columns. Compact phones retain More sports. Final 155-unit suite passes (one optional soak skip, no runtime warnings), normal/Review Safe Release and signed Debug pass, app/extension signatures and build 38 are verified. Physical Home shows uniform eight-column-plus-second-row tiles and actual Yankees/Astros logos; an argument-free 20-second hold passes. A requested Settings capture still showed Home, so theme switching and real touch are not certified. The portrait masthead/scroll safe-area state also needs rechecking. TestFlight remains 35.
- **Countdown/reminder checkpoint 40**: The owner approved inline Starts in countdowns and opt-in five-minute local reminders. Listed broadcasts become tappable two minutes before scheduled start; failed lookup remains inline with Retry, never an empty player. Bell opt-in saves the match in My Matchday; bookmarking alone is silent, and notification taps return to that match without autoplay. Stable UTC requests, bounded capacity and serialized revision-checked reconciliation handle learned reschedules, permission changes and cancellation races. Its 181-unit suite and three build variants passed; see `docs/releases/Fotty-2.0.0-40.md`. After its iPad installation/hold, the owner paused to discuss taller rows and live bookmarks, then approved the compact build-41 follow-up above. No new API, provider probes, model cost or server was introduced.

- **Current iPad diagnostic work (36 → 37)**: The owner explicitly requested iPad-only normal-app testing. Build 36 corrects competing web taps, stale pause/play UI, pause-vs-interruption handling and an injected startup timer; its signed normal app installed, independently reported version 36 and survived a 30-second launch hold. Build 37 restores team badges/equipment icons in the compact Home and implements optional Dark-default Light/System appearance with scoped dark pitch/video. The final-source 148-test suite passes (one optional HLS skip); see the playback and appearance audit records dated 2026-08-27 for build/device outcomes. Exact provider touch and full appearance acceptance remain separate from automated evidence. TestFlight remains build 35; no iPhone, simulator, device test helper, upload or Git publication is included.

- **All-sports Home (not uploaded)**: Implements the approved compact concept: All sports by default, activity/next-start tiles with an overflow summary, at most three diverse Now & next events, two later fixtures and a full lineup on Home's own stack. Exact event duplicates do not multiply counts; channels and unknown timings do not become live matches. CPL provenance remains visible and non-team events no longer gain a synthetic opponent. No new API or stream probes. The owner subsequently authorized light appearance and required restored team badges/equipment icons; see the build-37 appearance record. Fotty's name stays unchanged. The original implementation evidence is in `docs/audit/Fotty-All-Sports-Home-2026-08-27.md`; build 35 remains on TestFlight.

- **Local cricket/tab-separation patch (not uploaded)**: Home/Matchday FPL promotion and Match Center's redundant fantasy panel are removed without deleting FPL data, bookmarks or followed teams. Cricket has All cricket / CPL / Channels filters, separate channel rows and persistent channel bookmarks. A clearly dated CPL 2026 schedule snapshot adds fixtures without inventing live scores or borrowing a Willow channel as match-specific coverage. Shared timing is sport-aware. See `docs/audit/Fotty-Cricket-and-Tab-Separation-2026-08-27.md` for exact evidence and limitations; build 35 remains the distributed version.

- **TestFlight-first distribution (2026-08-27)**: Normal updates use the existing internal group, including the owner's devices; no direct installs without a separate debugging request. `ExportOptions-TestFlightInternal.plist` uploads normal Release with symbols, internal-only eligibility and fixed source-controlled versions. After checking the prior live build 34, `tools/set-version.sh` allocated `2.0.0 (35)`. Its signed archive passed bundle/version/signature and embedded-key checks; Apple accepted the upload at 19:12 AST. The owner completed the encryption declaration; tester notes were saved and the existing Fotty Internal Smoke group assigned. At 19:21 AST App Store Connect independently showed **Internal / Testing**, with that group and its unchanged two testers. Feedback remains on and Xcode build assignment remains manual. This confirms availability, not installation or received feedback. See `docs/releases/Fotty-2.0.0-35.md`. The 305 MB owned build/archive/export tree and separate Xcode logs were removed; disk remained 41 GiB free.

- **UI refinement verification**: The refinement passes 122 unit tests (one opt-in HLS skip), 14 distinct scoped Catalyst UI checks, and final unsigned normal/Review Safe iOS builds. Wide Plan layout and text wrapping were visually checked. Native Home filter appearance is intentionally retained after cosmetic experiments failed accessibility checks. The changes are uploaded in build 35; physical iPhone/iPad qualification remains. See `docs/audit/Fotty-UI-Refinement-2026-08-27.md` and the build-35 release record.

- **Approved UI refinement (uploaded in build 35)**: After the read-only audit in `docs/audit/Fotty-UI-UX-Audit-2026-08-27.md`, the owner said to proceed. The implementation retains amber, the football pitch and distinct Home/Matchday roles, and addresses FPL readability/contrast, point provenance, root-tab FPL continuity, recognizable clubs, grouped tools, searchable comparison, clearer Settings/feedback and consistent controls. `FPLWorkspaceSession` keeps data/navigation, not hidden polling screens. Large-text squads use a roster; wide Plan uses decision/evidence columns. Catalyst evidence is not fresh iPhone/iPad certification. Duplicate catalog identity, real-device daylight/VoiceOver/Zoom, and tester task success remain separate checks.

- **Beta-usability patch (uploaded in build 35)**: Settings Help/report preparation now work natively, without the retired web host. FPL manager linking checks an official team link/ID and asks for team confirmation before selecting it; failure always allows editing/retry. Home setup is optional and Matchday has direct personalization actions. Match alerts are explicitly foreground score-fetch updates, not reliable background push; locally scheduled FPL deadline reminders are a separate capability. Copy/share feedback is a handoff, not proof of delivery. See `docs/BETA-TESTER-GUIDE.md`; confirm build availability, fresh device checks and one received TestFlight report before widening the beta.

- **Release baseline**: `1.7.0 (4)` was the one-time Daily Driver Beta rebaseline; the Matchday OS/FPL foundation progressed through `1.8.4 (11)`. The integrated candidate reached hardware qualification at `2.0.0 (33)`. Current source is `2.0.0 (46)`; latest internal TestFlight remains `2.0.0 (45)`, uploaded/processed and confirmed Internal / Testing for Fotty Internal Smoke with two invitations at 2026-08-29 15:21 AST. Physical installation exposed its restricted vocabulary, so build 45 is not an acceptance candidate. Build 46 retires that alternate graph but is not installed or uploaded. The installed iPad diagnostic build is still `2.0.0 (41)`. Builds 13 through 33 advanced monotonically whenever a predecessor reached hardware or an exact-source release gate exposed a further acceptance correction. Builds 23–26 close Zoomed-iPhone Squad density, provider-only cold Match Center routing, missing web transport controls plus stale same-team score leakage, and compact control placement/auto-hide. Builds 27–28 stop fabricating unsupported zero-variant Echo/Admin URLs and separate catalog timing from Watch labels; build 39 replaces the reported Open broadcast/availability confusion with guarded inline countdowns and explicit reminders. Build 29 closes the exact Catalyst Home recovery-state contrast defect, build 30 narrowly rejects the provider's fake VPN/install solicitation without removing video, frames, or the legitimate unmute prompt, build 31 makes the small FPL widget's official source visible rather than accessibility-only, build 32 adds deterministic network-free large-Type coverage for all four FPL workspaces, and build 33 extends that coverage to Matchday, Settings, Match Center, and the Player recovery surface. Every target and extension shares the same marketing version and build. Future releases must use `tools/set-version.sh`, update `CHANGELOG.md`, and increment beyond the latest uploaded/distributed build; CoreDevice installation sequence numbers are not app build numbers. The version tool also updates `project.yml` so Xcode project regeneration cannot revert the version.
- **iOS app**: Main priority.
- **Web/PWA**: Companion on getfotty.com (static FTP + Cloudflare playback Worker). Watch is open without accounts; provider embed (no same-origin unmute until a VPS is funded).
- **Profiles/social**: On-device only. PocketBase auth and cloud sync are retired; never describe local messages as community/cloud messages.
- **Playback**: StreamEx + Score808 web-module families only. AceStream/P2P is not an active product path.
- **Server**: Homelab P2P/PocketBase retired; do not assume pixel-invoice hosts are available.
- **Android/macOS**: Secondary and testing/support surfaces.

## Core Pillars & Strategy

1. **Data truth and identity**: One canonical fixture identity crosses catalog, score, FPL, notification, Match Center, and playback boundaries; provenance, freshness, status, coverage, and availability remain separate facts.
2. **Playback reliability**: Streams must prove decoded progress, protect recoverable attempts, expose truthful failure boundaries, keep all switching in the numbered source picker, and adopt native playback only after capability proof.
3. **FPL decision system**: Official current facts and versioned deterministic rules drive scoring, legality, planning, rival context, saved scenarios, and process review.
4. **Smart Coach**: Direct facts/rules use zero model tokens; consented model reasoning receives refreshed minimized evidence and must expose uncertainty, actions, freshness, source, and usage without contradicting verified rules.
5. **Matchday UX**: Home is broad fixture/channel discovery, Matchday is an explicitly saved/followed plan, and one Match Center provides match context. Fantasy features stay in FPL instead of being repeated across destinations.
6. **Native system experience**: AVKit/PiP/AirPlay, notifications, widgets, Live Activities, deep links, lifecycle teardown, Dynamic Type, and accessibility are capability-gated and verified on supported hardware.
7. **Quality and release discipline**: Shared professional versioning, no-simulator sequential gates, bounded build storage, redacted local evidence, secret hygiene, durable agent knowledge, and an evidence-backed completion report are release requirements rather than optional cleanup.

## Fotty 2.0 release-candidate baseline (2026-08-24)

- The accepted authority is `docs/audit/Fotty-2.0-Benchmark-and-Product-Contract.md`: one integrated loop across discover, watch, understand the match/FPL effect, plan, and review. Specialist products are behavior benchmarks, not runtime dependencies.
- Canonical fixture identity preserves one route ID plus provider aliases across catalog, score, Matchday, Match Center, notifications, FPL context, and playback. Status, score coverage, source availability, relevance, and freshness remain separate facts.
- The production resolver is explicitly StreamEx/Score808 web-only. The old Hybrid P2P implementation is behind the undefined `FOTTY_LEGACY_P2P` condition; active analytical providers and catalog rendering reject P2P/Ace-shaped sources.
- `FottyQualityStore` keeps at most 250 redacted local events for 14 days and exports aggregate playback, data, identity, FPL, and Coach evidence without match names, manager IDs, prompts, URLs, or credentials.
- FPL current scoring is deterministic in Swift and the Worker. Coverage includes legal goalkeeper/outfield autosubs, formation-driven bench order, vice-captain promotion without a bench replacement, Bench Boost, transfer hits, published autosubs, double-gameweek non-appearance boundaries, checked-final truth, and blank/double projections.
- Planning includes versioned expected minutes/confidence/assumptions, squad decision lenses, week-by-week Roll/one/two-move effects, hit break-even, downside/checks, legal validation, named alternatives, Rival Race, and a process lesson carried from the Decision Journal into the next Plan cycle.
- Coach handles rules and directly computable facts locally with zero tokens. Consent-gated model requests use refreshed official evidence, bounded context/history and output, structured evidence/uncertainty/actions, freshness checks, contradiction rejection, returned usage, and deterministic fallback. Production Worker version `39e913bd-d1fb-48e4-bf56-20be2ba183e4` passed a zero-token rules smoke and a structured DeepSeek smoke.
- Home is broad discovery; Matchday is personal; Match Center has one active implementation. Typed deep links connect notifications, the FPL widget, Match Center, and the surviving native player. Live Activities remain capability-based and useful, not persistent app-open notices.
- Build 30 passes the complete Swift policy suite, injected-script JavaScript parse contract, normal iOS Release, Review Safe Release, generic-iOS static analysis, and all six exact-source Catalyst accessibility audits plus rapid-navigation/foreground recovery. The same strictly verified signed normal artifact is installed and independently version-reported as `2.0.0 (30)` on both authorized devices. It decoded and visibly advanced the same selected Broadcast 1 on both without a source change or the build-29 provider VPN/install solicitation; the iPad preserved the provider-owned `CLICK UNMUTE STREAM` control. The owner directly confirmed iPad unmute and Pause, a later capture proved Play resumed to a different advancing broadcast frame on the same source, and the owner reported no ticking or duplicate/overlapping audio. The owner then deliberately selected Broadcast 2 and returned to Broadcast 1 successfully; the final capture showed advancing video with Broadcast 1 selected. Build 28's earlier current-source gate remains the lifecycle evidence: more than 60 seconds on both devices, same-source background/foreground recovery, genuine iPad PiP after native handoff, and complete PiP/system teardown. The stale zero-variant Echo event still returns immediately without a fabricated request and presents `AVAILABLE · Open broadcast`, not `LIVE · Watch live`. iPhone native tap-to-reveal/Pause/Play has also passed. The unchanged web/Worker boundary retains its 68/68 pass and successful production Next build.
- Exact build-30 physical FPL checks now include compact iPhone Coach and regular-width iPad Plan. Both iPhone Send-arrow and keyboard Return paths dismissed the keyboard and left the reply usable. The captured deterministic current-points answer correctly reported the official 64 points plus Kelleher-for-Benitez and Wieffer-for-Pedro Porro automatic substitutions with fresh final evidence and zero tokens. The regular-width iPad command center loaded through `fotty://fpl`, fit its three metrics and decision rows without clipping, and showed the same official 64-point state.
- Build 31 adds a visible `Official FPL` source label to the small deadline widget, matching the medium widget and retaining the typed `fotty://fpl` route. Its source contract, complete Swift suite, normal and Review Safe Release builds, generic-iOS static analysis, and all seven Catalyst UI checks pass. One strictly verified signed artifact is installed and independently version-reported as `2.0.0 (31)` on both authorized devices. The owner confirmed the physical small/medium widget presentation and FPL tap route work.
- Build 32 adds an explicit Debug-only, network-free FPL accessibility fixture and direct workspace launch coverage for Plan, Squad, Coach, and Tools. The FPL Dynamic Type audit includes the quick-prompt control and a structured Coach response; a source contract proves quick prompts clear focus through the shared send path before adding the message. The complete build-32 Swift suite, normal and Review Safe Release builds, generic-iOS static analysis, seven Catalyst accessibility audits, and rapid-navigation/foreground recovery pass. The same strictly seal-verified `2.0.0 (32)` artifact is installed and independently version-reported on both authorized devices with no UI-test runner. The devices were passcode-locked, so the install was intentionally not followed by an overnight launch; all production paths changed since the launched build 31 are accessibility metadata or Debug-only test scaffolding.
- Build 33 adds direct Debug-only, network-free Match Center and Player presentation routes plus direct Matchday and Settings launches. Matchday, Settings, catalog-only Match Center, and the truthful no-source Player recovery surface each pass the Dynamic Type audit; Home and all FPL workspaces already passed. Catalog-only Match Center resume now preserves its loaded catalog event instead of starting an unnecessary repository refresh. The complete build-33 Swift suite, normal and Review Safe Release, and generic-iOS static analysis pass. One strictly seal-verified `2.0.0 (33)` artifact is installed and independently version-reported on both authorized devices with no UI-test runner. Once unlocked on 2026-08-26, the normal app launched and its foreground process survived a bounded 60-second hold on each device. The exact aggregate Catalyst gate passed all eleven accessibility audits plus rapid navigation/foreground recovery in one guarded invocation. No simulator was used, no retry was needed, and the owned DerivedData folder was deleted on exit; the later physical holds created no build output or temporary evidence.
- Release security acceptance is complete: the owner confirmed that the homelab is retired and authorized deletion of every Cloudflare Tunnel. The authenticated API found one down tunnel, `manga-api`; its ID matched the historical `cert.json`, it was deleted, all four accessible accounts then reported zero active tunnels, and the independent Fotty playback/Coach Worker remained HTTP 200. A disposable `git-filter-repo` 2.47.0 mirror rewrite atomically cleaned the two affected advertised branches; `origin/main` plus tags did not move. GitHub then closed Support ticket `#4701297` after clearing the retained pull-request objects. Independent authenticated API checks return `No commit found` for obsolete commits `74c8b1627d24a8b8368b903fee83f8dda94d0a61` and `82f9cc431b5d5e078dd8f4cba4285ed4dfc8e237`, both public web pages return HTTP 404, all four PR refs are absent, and a fresh heads/tags-only clone contains neither commit nor `cert.json`. A temporary clean-branch worktree successfully replayed 310 tracked changes plus 120 Git-visible untracked files with exact path/content manifests, no `cert.json`, and clean whitespace, proving a safe publication route. The current dirty local branch deliberately remains on its old commit; never push or merge it back into the cleaned history. A later publication must repeat the proven Git-aware replay onto clean ancestry.

## iOS Reliability Baseline (2026-08-22)

- The physical-iPad cold-launch watchdog was fixed by keeping `LiveScoreService` lookup caches outside Swift Observation and caching misses explicitly.
- The single normal Debug/Release product graph compiles successfully; `APP_REVIEW_SAFE` is retired.
- The original reliability suite has expanded into the 2.0 coverage summarized above; one playback soak remains intentionally opt-in because it requires a live source.
- Automated tests suppress production polling through `FOTTY_AUTOMATED_TESTING`.
- Build 22's Catalyst accessibility gate passes hit regions, text clipping, sufficient descriptions, contrast, traits, Dynamic Type, and element detection, followed by rapid tab switching/foreground recovery. The runner retries only Xcode's pre-test automation-mode timeout once and never retries a real Fotty test failure. A fresh runner exhausted that retry before testing, while the already-authorized release runner then executed the exact build-22 source at 7/7. UI tests bind the cached fixture tree to 40 representative rows so XCTest's analyzer does not time out; production remains unbounded. Physical compact/regular form-factor checks remain release gates. The build-22 unit result bundle has zero runtime warnings.
- Provider families open a 15-minute automatic-attempt circuit after two consecutive failures. A decoded success closes the circuit; manual retries bypass it. This health state is an internal ordering mechanism, not consumer-facing `Risky`/`Stable`/`Cooling down` copy.
- Playback loads have unique attempt identities. Transient AVPlayer diagnostics and short WebKit stalls are recoverable; automatic failover requires a bounded lack of decoded progress from the still-current attempt. Web embeds get 20 seconds to negotiate initial decoded video and one controlled same-source startup retry before failover; decoded playback uses a 30-second stall threshold, an eight-second final recovery grace, and one same-source reconnect. Explicit provider rejection remains immediately actionable. Network-path changes preserve the same attempt/item instead of pausing, re-ranking, or rebuilding playback.
- The web companion distinguishes a loaded cross-origin provider frame from decoded playback. It keeps an unobservable loaded feed selected instead of rotating behind the user's back, exposes no provider new-tab escape, and shows PiP only for a real native video element. Non-football events do not receive invented wall-clock minute labels.
- StreamEx/Score808 now use an opportunistic native handoff: visible WebKit starts first, reports a real HLS/MP4 request only after decoded progress, and stays on screen while a separate muted AVPlayer validates and advances. Fotty adopts native playback only after that proof; failed handoff is silent, and later native failure returns to the same web source before changing provider. `LivePlaybackState` is the sole loading/playing authority.
- In the standard player, third-party WebKit still owns unmute, seek, fullscreen, and any controls it actually renders. Because a physically decoded provider exposed no play/pause control, Fotty now supplies one labeled Play/Pause fallback that commands reachable HTML/JW media across the frame tree. Its surface recognizer does not cancel provider touches, the compact toolbar sits at the video edge, fades after four seconds, and returns on a normal tap; pausing keeps Play reachable. Fotty must not add a duplicate unmute action, remove provider mute prompts, or continuously rewrite provider mute/volume state. When Fotty backgrounds, it suspends reachable web media and resumes the same selected attempt so provider/ad audio cannot continue invisibly. A real decoding physical-device stream remains the audio/control acceptance authority.

- Xcode verification on this 256 GB/8 GB workstation must reuse one bounded DerivedData directory. `ios-device-qa.sh` and `catalyst-ui-release-gate.sh` now create an owned temporary directory by default and remove it through an EXIT/INT/TERM trap; explicitly supplied cache paths remain caller-owned. Agents must check disk space, run builds sequentially without simulators, and retain no duplicate build outputs, result bundles, or temporary screenshots after evidence is extracted.
- Local proxy diagnostics are OSLog-only. Do not restore the retired per-manifest/per-segment remote logging POST because diagnostic traffic must never contend with playback.
- MultiView is hidden until two eligible events exist and provider families have a recent decoded success. Provider-site Safari recovery has been removed; source recovery stays inside the app through retry and manual Broadcast Sources selection.
- Home now treats Watch as a strict capability, not decorative chrome: hero cards, On-now choices, Pick for me, and fixture Watch actions require a supported catalog source. Score-only fixtures remain visible and route to labeled Details instead of raising a predictable no-stream alert.
- The consumer source picker is a compact numbered list with explicit Selected, Select, and Try again states. Catalog HD/SD duplicates for the same broadcaster collapse to one option, source families get a fair first slot, remaining choices favor current viewer count, and language/channel metadata is shown when the catalog provides it. Zero-variant families are not mixed into events with real variants. Canonical synthesis is a last resort only for provider families whose URL contract is actually known (`hotel`, `delta`, `golf`, `india`); Fotty never fabricates an `echo` or `admin` URL when those families supply no variants. Internal provider names, heat/circuit terminology, and discovery gauges are not shown to users.
- Catalog broadcast timing is a separate truth boundary: football uses a two-hour discovery estimate, recognized CPL/T20 six hours, and unknown cricket formats no inferred live/final state. Other sports retain their four-hour broadcast window without an inferred final whistle. Known cricket channels remain undated channels with `Open channel`; source-free bundled CPL fixtures never claim live playback. Score coverage, estimated timing and actual source availability remain separate facts.
- Home treats `LIVE` as a watchability promise: catalog-backed rows are tappable across their full surface and always expose Watch, even when recent health would make automatic selection cautious. Current supported StreamEx catalog codes are `admin`, `delta`, `echo`, `golf`, and `india`; Score808 is `hotel`. A fixture underway without one of those sources says `IN PLAY` and opens details instead of presenting a dead `LIVE` row.
- The four persistent destinations remain Home, Matchday, FPL and Settings. Home has a `Now & next` lead match, chronological fixtures and a separate cricket-channel section. As of the local 2026-08-27 patch, `My Matchday` contains explicitly saved broadcasts and followed-team fixtures, not automatic FPL squad matches. Dated fixtures use Live now / Next up / Later / Recent and sport-aware clash estimates; undated saved channels have their own section and do not expire as old matches. Home and Matchday share one `MatchListViewModel`; dated bookmarks retain their 36-hour continuity boundary. Match Center no longer repeats a fantasy panel. FPL retains Plan/Live/Review, Squad, Coach and Tools.
- The `1.8.3 (10)` compact-iPhone correction reduces FPL shell, workspace, card, and header density without scaling the whole interface or clamping Dynamic Type. Smart Coach owns explicit text-field focus: Send, Return, and quick prompts resign the keyboard before the request, while an interactive drag can dismiss it during composition. Do not restore obsolete bottom padding for a tab bar that already participates in the root layout.
- The `1.8.4 (11)` scoring boundary never asks DeepSeek to calculate a current FPL total. Official current points remain visible, while Fotty may show a separately labeled provisional total only when completed fixtures prove no appearance, the incoming bench player appeared, goalkeeper and outfield bench-order rules are satisfied, the resulting formation is legal, captain fallback is applied, and transfer cost is deducted. Live Points makes the difference explicit as `Before autosubs → After autosubs`; once official FPL data is checked, no Fotty projection may override it. The Worker refreshes and resolves these facts before model routing; scoring/autosub questions return directly from the rules engine with zero model tokens. The on-device Live Points resolver and local Coach fallback use the same policy. LiveFPL is a product-behavior benchmark, not an upstream service or data dependency.
- Home's `Match schedule` is live/upcoming only. The shared catalog still retains recent fixtures for data continuity, but completed saved or followed matches belong exclusively in `Matchday → My Matchday → Recent` for the bounded 36-hour window; they are not scheduled content on Home.
- Live Activities begin only after AVKit confirms PiP is active; foreground capability or a generic inactive scene is not sufficient. StreamEx/Score808 web embeds never create one because they cannot truthfully represent continued background playback. Eligible activities show the matchup, available score/minute or status, and a return cue. That cue reveals the matching player when it survives, but falls back to the same match's Match Center after process termination; PiP stop/failure/availability loss clears continuity and pauses playback when backgrounded, while cold launch clears orphaned activities.
- Live scores are deliberately Premier League-only for now. The first score source is the official public FPL `fixtures/` JSON already used by Fotty: fixture responses cache for 45 seconds, the normalized repository list for 55 seconds, and active polling runs every 60 seconds. Only `started == true`, `finished == false`, non-provisional fixtures become live rows. Cross-provider team aliases merge those scores into football-data schedule identities so Match Center, streams, and alert routing do not receive duplicate or incompatible fixture ids. API-Football remains the second source and football-data the visibly delayed final fallback. The broad cached schedule is loaded first; when it proves no Premier League match is within five minutes of kickoff or its three-hour live window, Fotty skips all live-provider requests. Schedules and the StreamEx/Score808 catalog remain broad; non-covered competitions never show score-unavailable messaging because score coverage was not promised there. Their Home state is `LIVE` when watchable and `IN PLAY` when not. Do not restore a global live feed.
- If official FPL is unavailable or structurally stale, the production Worker centralizes the API-Football fallback through one Durable Object. It serves one four-minute response cache to all devices, stops at 80 upstream requests per UTC day, and preserves the provider's final 20 free-tier requests. Successful live responses are reused by Match Hub; automatic/timer Match Hub loads never request provider enrichment, while a deliberate full refresh may. Delayed football-data fallback is visibly labeled instead of being presented as live.
- Goal, kickoff, and full-time notifications apply only to followed football teams with their per-team alert bell enabled. Tapping one opens the matching Match Center. A Live Activity tap foregrounds a surviving matching player without stacking another sheet; after a cold relaunch it opens the matching Match Center instead of leaving the user on an unrelated tab.
- Mac Catalyst is the repeatable shared-stack playback lab. DEBUG Settings → Stream pipeline checks includes a two-minute muted continuity soak using the production `LivePlayerViewModel`, required-header local proxy, AVPlayer readiness/watchdog path, and failover accounting. The 2026-08-23 reference run decoded 120.83 seconds across 120 advancing samples at rate 1.0, with no wait/pause samples, item/attempt/source replacement, error, or automatic failover. A separate real StreamEx #1 Mac-app hold decoded New England–NYC continuously from match clock 68:14 to 71:17, including while Fotty briefly lost focus, with no loading/error state or visible source replacement. Catalyst never requests iOS orientation geometry. This validates shared native playback plus one current provider embed, but does not replace physical-iOS checks.

## Known Risks

- **Complexity-audit fixes, 2026-08-28 (Worker deployed; app 43 Testing)**: The owner subsequently approved fixing all five reproduced boundaries. Replacement/reset playheads no longer inherit a stale progress baseline; post-start video/document ownership filters unrelated errors; incomplete FPL data cannot authorize autosubs or derived totals; missing/stale scoring stays on the zero-token rules path; Coach request shapes/body sizes/limiter failures have controlled responses. Full web tests pass 81/81 and Catalyst units 191 plus one optional soak skip. The original pre-fix audit is preserved. Current verification/release-build and cleanup evidence is in `docs/audit/Fotty-Complexity-Fixes-2026-08-28.md`. The Worker is deployed as `fafdf5ed-4d37-47e6-82b8-69dd55c3e116`; app 43 is Internal / Testing for the unchanged group, independently verified at 12:47 AST after the owner-approved declaration/notes/group submission, with physical acceptance still open. See `docs/releases/Fotty-2.0.0-43.md` for rollout evidence. Broad complexity refactors are separate, and these probes do not establish the cause of every historical device report.

- The legacy FPL match-context snapshot remains device-local and manager-scoped, but the 2026-08-27 tab-separation patch removes its Home, Matchday and Match Center consumers. Do not reintroduce those fantasy badges/panels or automatic squad-match promotion without a new product decision. The dedicated FPL workspace and its data/planning are preserved.
- The 1.8.2 FPL decision layer adds three coherent tools instead of another flat utility grid: Rival Race reads only post-deadline published picks, current official standings/fixtures, and official event-live points; Transfer Lab compares roll/one/two-move routes and still stages changes locally through the shared validator; Decision Journal is manager-and-season scoped on-device storage and never syncs or submits an official action. Smart Coach still uses DeepSeek through the consented Worker when available, but renders its answer as a bounded card with confidence, evidence, downside, required checks, model, source, and official-data status; deterministic local fallback remains available.
- The FPL deadline widget belongs to the existing WidgetKit extension and fetches only the minimal public bootstrap contract on a system-managed timeline no more often than hourly. It does not create a hidden Home/Matchday polling owner, store manager data, or imply background live scoring; tapping it deep-links to `fotty://fpl`.
- The signed 1.8.1 (8) Debug artifact and its Live Activity extension share the correct version; the exact app installed and launched on the physical iPad. The iPhone was unavailable to CoreDevice trusted connectivity during both install attempts. Debug Catalyst and generic physical iOS compile, the full unit-only Catalyst gate passed 53 active tests with the intentional soak skipped, and the final focused 13-test FPL gate passed. The beta Xcode Release frontend was deliberately stopped after more than 12 minutes of active optimized compilation with no source diagnostic so it would not monopolize the Mac; Release remains a later distribution gate, not claimed as passed.
- The signed 1.8.2 (9) Debug artifact and embedded WidgetKit extension share the correct version. The exact normal Fotty app is installed on both physical devices and launched successfully on the iPhone 15 Pro Max; the iPad was locked during both launch requests, so its installation/version are proven but an iPad UI launch is not claimed. Debug Catalyst, generic physical iOS, the focused FPL suite, and the complete unit-only Catalyst gate pass; the full result is 57 passed with only the intentional playback soak skipped. Catalyst loaded current official FPL data and visually exercised the widget deep-link destination, Tools grid, and Transfer Lab without a simulator or UI-test helper.
- The `1.8.3 (10)` compact FPL/Coach correction passes Debug Catalyst, generic physical-iOS compilation, and the focused 17-test FPL suite. A narrow Catalyst window loaded current official FPL data without clipping. Physical-iPhone installation remains outstanding because CoreDevice reports the paired phone unavailable; no simulator or UI-test helper was used.
- The `1.8.4 (11)` autosub correction was the initial deterministic scoring boundary. Fotty 2.0 supersedes its focused evidence with Swift/Worker parity for captain-only promotion, chips, hits, blank/double cases, published substitutions, and final truth; current suite/deployment evidence is recorded in the 2.0 baseline above.

- The FPL daily-use decision platform landed on 2026-08-22. It is official-data-first, phase-aware, provenance-labeled, and backed by shared squad/lineup validation, official live-event scoring, autosubs, player history, rival context, deadline reminders, confirmed-gameweek reviews, explainable transfer routes, and legal constrained squad optimization. Eleven focused FPL tests pass within the 25-test unit suite.
- Smart Coach is a hybrid: Fotty always has a deterministic on-device fallback, while an explicitly consented question can use the production Cloudflare Worker to gather a compact current FPL evidence packet and ask DeepSeek V4 Flash for an explanation. No provider credential is shipped in the app. The Worker secret is correctly configured and the production route passed a fresh-data structured-output smoke on 2026-08-23.
- Previously exposed provider credentials were removed from source but must still be revoked in provider dashboards because repository removal cannot invalidate them. Never recover or reuse an old key from repository history.
- Official public FPL data remains the primary path: bootstrap and event-live expose expected-points hints, per-90 metrics, defensive contributions, price projections, fixture-level points/BPS/bonus, and autosubs. Do not invent equivalents when an official field or endpoint exists.
- Official public FPL fixture JSON is also the pragmatic Premier League score source for this personal build. It is not a licensed commercial live-data agreement and its public contract can change. Reject stale disk snapshots for live scores, keep provenance visible, retain independent fallbacks, and observe the next active Premier League match before claiming measured real-match latency. A small server-side scraper remains a valid future tool for a specific missing field; do not copy unlicensed repository code or depend on selectors already known to return no data.
- Public FPL endpoints do not provide every authenticated account fact. Fotty estimates available free transfers from public history, cannot guarantee the manager's exact selling prices, and saves transfer/wildcard changes only as local drafts. These limits must stay visible and no UI may imply an official FPL action was submitted.
- Cloudflare Rate Limiting bindings are abuse controls scoped by location and are not a billing ceiling. Keep an account-level spending limit. The 2026-08-23 no-manager cost smoke used 8,982 cache-miss input tokens and 305 output tokens (about $0.00134); the compact public-manager smoke used 13,787 input and 564 output tokens (about $0.00209). Raw manager payload compaction reduced the representative call from $0.00297 by roughly 30%. Richer app context can cost more, so use returned token telemetry rather than assuming a fixed price.
- Third-party catalog health does not imply playable video. On 2026-08-25, a corrected WebKit matrix sampled four current families and independently decoded advancing 960×540 `golf` video after about 13.8 seconds with no popup; `admin`/`delta` delivered media but did not advance in that window, and `echo` returned media HTTP 500. A follow-up pool run decoded both numbered `golf` feeds and held each for 45 seconds; both advanced through the window with longest freezes near 1.0 and 5.0 seconds, HTTP 200 media, no request failures, and no popups. Later that day, two current `echo` football candidates returned repeated HTTP 500, while both numbered `admin` broadcasts for the next football event passed a kickoff-aligned 45-second hold: about 45.3 and 43.0 seconds of advancement, longest pauses of 0 and about 2.0 seconds, HTTP 200 media, zero popup, and zero request failure. At 18:03 UTC the refreshed matrix decoded 7 of 16 current `admin`/`delta` football samples; one focused `admin` feed decoded in about 8.4 seconds and advanced about 45.28 seconds through a 45-second hold with zero freeze, HTTP 200 media, no failed media request, and no popup. URL-bearing temporary reports were removed after redacted extraction. The prior all-403 result was invalid because the harness overwrote the HLS referrer globally. Availability can change quickly: on 2026-08-23 the actual Catalyst app also decoded and held a current StreamEx #1 football feed for just over three minutes.
- `API_FOOTBALL_KEY` is configured correctly, but a production probe proved the free provider plan cannot access the current 2026 season (it offered only 2022–2024). Worker version `e50e0d24-b700-4ca5-9b6e-f178fbca278b` therefore reports the credential separately from current-season availability, remembers the restriction for four hours, and serves `access-restricted` without spending another provider call. Basic Premier League score/minute updates now use official FPL without consuming that allowance; API-Football event/stat enrichment still requires a plan with current-season access, and `FOOTBALL_DATA_API_KEY` remains the schedule/delayed-score fallback.
- Web embeds can change without notice and can expose ad overlays. The 2026-08-24 Fulham–Chelsea trace proved an `embed.st/ad.html` frame spawning repeated external click-through windows; Fotty now removes that frame, blocks the observed ad-host chain at navigation and DOM layers, and disables `window.open` inside the embed while leaving the video element and controls intact. This still cannot safely guarantee removal of provider-origin or in-stream video ads.
- A source-backed physical iPhone 15 Pro Max UI run on iOS 27 opened StreamEx, exposed two compact source rows, and remained presented without playback error through a 20-second stability window. This is one current-provider smoke, not the broader provider matrix; upstream availability can still change.
- Native handoff and real PiP were physically proven on build 28 with a current decoded provider: the iPad continued the same broadcast in PiP and returned without selecting another source. Exact build 30 then reconfirmed current WebKit decoding on both devices after the nuisance-solicitation hardening, including direct iPad unmute, Pause, Play/resume, and no ticking or duplicate audio. The owner subsequently confirmed large-text interaction on both supported form factors and a real alert/Live-Activity return to the correct match/player. Physical interaction acceptance is complete.
- Physical build-19 Home captures on both devices caught and verified the removal of a false youth-competition `SCORE UNAVAILABLE` claim. Build-20 iPad FPL review caught narrow adaptive metrics, and build 33 retains their full-row correction. A build-20 iPhone Squad capture exposed the five-player row expanding the complete compact workspace; build 33 retains the compact shirts/nameplates and formation spacing correction. The Debug-only, allowlisted `--fotty-fpl-workspace` normal-app route remains available for repeatable physical Plan/Squad/Coach/Tools captures without synthetic touch or a device UI-test runner. The same strictly verified build-33 artifact is installed on both devices.
- Dormant defensive P2P/Ace session-shape code remains in lower-level internals, but the production Hybrid branch is compile-isolated and active analytical providers, resolver tracks, manifests, and UI are web-only.


# Architecture Map

# Fotty Architecture Map

## 1. iOS application shell and lifecycle

- `MatchStartPolicy` and `MatchReminderStore` in `Core/Notifications/MatchReminderStore.swift` own scheduled-start/play eligibility and explicitly opted-in five-minute local reminders. Stable UTC requests, a serialized queue and per-ID revisions protect cancellation/rescheduling. Only fresh catalog responses update snapshots; existing score refreshes supply known status. Foreground reconciliation must not overwrite saved sources with source-less SwiftData cache rows. The store never fetches, probes streams or prompts for permission without opt-in.
- `MatchStartControls` in Dashboard Components is shared by Home rows, full-lineup/Matchday cards and catalog Match Center. Its scoped timeline ticks once a minute, then once a second inside five minutes. Build 41 adds a generic information slot and measured `MatchRowLayout`: information left, action right, stacking only for insufficient width/accessibility text, without duplicating stateful controls. Feedback stays full-width. Save/remove uses native context menus and accessibility actions rather than permanent bookmarks. Play becomes available only for a listed source inside two minutes. `MatchPlaybackFeedback` holds bounded per-event inline retry state, not provider-health blocks. `MyMatchdayStore.onRemove` revokes a selected reminder; saves alone never schedule one.
- Reminder notifications and `fotty://matchday/<id>` use `MatchNavigationStore.pendingReminderID`. MainTab selects Matchday; the existing view scrolls to a highlighted saved row and consumes the route, without starting playback or forcing Match Center. Foreground score alerts retain their existing Match Center route.

- `SettingsAppearanceView` in `SettingsScreen.swift` is the dedicated theme destination in build 38; the main Settings row shows the current value. `SettingsAppearanceOptions` holds the actual choices separately from the UIKit-backed scrolling container, allowing nonblank render validation. Engineering no longer appears in normal Settings, including Debug; the development validation implementation remains in source and customer support stays under Report a problem. `TeamBrandService` merges persisted badge URLs into (not over) its bundled fallback and has exact static NBA/MLB image fallbacks verified against current ESPN catalogs.
- `SportTileGridLayout` in `SportsDiscoveryViews.swift` measures all sport buttons at one width and gives every cell the tallest measured height, including partial rows. A scaled minimum width determines the column count. Sport titles reserve two lines; iPad (including compact Split View) and regular-width layouts show all catalog sports inline. Only compact phones retain the five-sport overflow policy and selected-sport continuity.

- `Fotty/Design/Theme.swift`: `FottyAppearance` owns the shared `fotty.appearance` preference (Dark default, Light, System). The app root applies it without rebuilding navigation identity. Trait-resolved semantic colours separate readable amber ink (`accentText`) from gold fill (`accent`). FPL sheets inherit the app appearance; live-player presentations and pitch artwork keep scoped dark treatment.
- `SportIdentity`/`SportEmblem` in `Fotty/Design/Components.swift` supply equipment icons for Home and both catalog variants. Home discovery rows reuse `FlagSquircleBadge`, matched football crests and the existing provider/catalog cache; no new badge fetch service is added. The badge observes catalog changes and fits complete artwork. Channel/unpaired-event rows do not synthesize opponent badges.
- Web transport ownership: `LiveWebEmbedPlayerView` uses passive frame click observation rather than a UIKit tap recognizer, and sends actual primary-video transport state keyed to its document. `LivePlayerViewModel` validates source/attempt, separates explicit pause from interruptions and cancels native handoff on pause. `LivePlayerView` bounds fallback chrome to its top-right buttons, leaving provider centre/bottom controls exposed.

- `Fotty/App/FottyApp.swift`: dependency construction, SwiftData container, app-level services, and the notification delegate.
- `Fotty/App/MainTabView.swift`: Home, Matchday, FPL, and Settings navigation plus notification/Live Activity match routing, `fotty://fpl` widget routing, and followed-team alert-preference synchronization. The old `Arena` raw value is retained only to migrate persisted tab selection.
- `FPLWorkspaceSession` in `FPLMainView.swift` is root-owned by MainTabView. It retains one FPL advisor, selected workspace/tool and per-destination scroll offsets across tab changes, while off-screen views and their `.task` pollers still disappear. Manager changes reset navigation; the advisor clears unsent Coach text, pending-state UI and comparison IDs together with the existing manager-bound data. Feedback drafts retain their explicit on-device persistence.
- FPL checks its phase/data again on tab return or foreground activation using the service's existing TTL cache. Only explicit pull-to-refresh clears the cache. A cached screen remains visible during this load and displays refresh errors inline; a full-screen spinner only replaces an initial empty snapshot. Scroll restoration refuses writes from an old manager selection.
- `Fotty/Features/Onboarding/MatchdaySetupCard.swift`: optional, dismissible Home guidance for following teams and saving broadcasts. No FPL promotion or manager dependency remains on Home or Matchday. `TeamOnboardingView` uses adaptive club tiles and cancellation-safe, debounced catalog lookup with explicit loading/empty/retry states. Empty Matchday exposes following and Home discovery; the FPL tab remains independent.
- `Fotty/Features/Settings/Views/SettingsSupportViews.swift`: offline native help, shared capability explanations, and a local feedback draft with build/device context, opt-in redacted diagnostics, preview, copy for TestFlight and system sharing. It has no submission backend and never interprets copying/sharing as delivery. Player and FPL recovery screens expose this same report sheet.
- `Fotty/Features/Dashboard/SportsDashboardView.swift`: owns All-sports-first Home, compact activity selection, a three-event mixed-sport Now & next list, two later fixtures, and the full lineup on its own navigation stack. Home and My Matchday use `MatchListViewModel.shared`; whichever fixture tab is visible drives its bounded refresh loop. All sports reuses the existing football score poller; a local minute clock never fetches data. Playback still requires an active catalog source; source-less fixtures open details.
- `Fotty/Features/Search/SearchView.swift`: Home's app-wide search projection, reached from the masthead. `HomeSportsSearch` filters the already-built `HomeSportsDiscovery` items/channels with case-, width- and accent-insensitive multi-token matching plus explicit football-league disambiguation. It owns no network or playback resolver. `HomeDiscoveryRow`/`LiveEventCard` render the results, and the dashboard defers Watch/details presentation until the sheet dismisses.
- `Fotty/Features/Dashboard/Components/HomeSportsDiscovery.swift`: presentation-only exact-event deduplication, timing/official-status precedence, stable sport activity summaries and bounded diverse curation. Real source descriptors are combined without URL synthesis; fuzzy identity and schema migration are excluded. Channels never enter on-now counts. `SportsDiscoveryViews.swift` owns adaptive activity buttons and compact source-gated event/bookmark actions with explicit sport and timing provenance.
- `Fotty/Features/Dashboard/MatchListViewModel.swift`: one shared in-memory Nexus catalog with a configure-once SwiftData cache, preventing Home/Matchday contradictions during tab changes. It merges the dated CPL snapshot into cached/fresh catalogs. Debug-only cricket and cross-sport Home UI fixtures require automated-testing plus feature-specific flags and do not enter production persistence.
- `Fotty/Core/Models/CricketCatalog.swift`: seven CPL franchise identities, cricket filters, and the explicitly dated 39-fixture 2026 schedule. Only matching franchises and kickoff within one hour can enrich a fixture with active catalog sources; channel sources and stale cached snapshot sources never do. The snapshot expires after the season and requires manual league-change checks before releases. Home separates channels from fixtures; My Matchday separates saved channels from dated plans. Neither subscribes to FPL context.
- `Fotty/Core/Providers/Football/FootballModels.swift`: `LiveScoreService`, shared team-normalized score indices, kickoff-bounded catalog-to-schedule matching, notification merging, and feed-aware polling (60 seconds for official FPL, 240 seconds for fallbacks). Player score/status surfaces require team and kickoff identity so an older same-team league fixture cannot label a current cup broadcast.
- `Fotty/Core/Internal/AnalyticalDataEngine.swift`: Nexus catalog normalization, near-term event filtering, badges, stream descriptors and Home league classification with explicit evidence/reason codes. Stream resolution tries generated canonical home/away identity before legacy word matching. League placement may receive a team-and-six-hour-kickoff-proven `FootballMatch`; its official competition wins, while provider markers and both-current-senior-club inference remain fallbacks. Cup/youth/friendly/lower-division identity stays outside domestic tabs; explicit Champions League remains authoritative. It accepts real catalog variants first and exposes canonical zero-variant synthesis only for the known Hotel/Delta/Golf/India contracts; Echo/Admin without variants are not fabricated.
- `Fotty/Core/Models/MediaModels.swift`: shared channel identity, display title and sport-aware timing. Channels have no inferred kickoff/end. Football uses a two-hour discovery estimate; recognized CPL/T20 uses six hours; unknown cricket formats receive no inferred live/final state. Other sports retain the four-hour broadcast window without an inferred final whistle. Source-free bundled CPL fixtures never claim live playback. These are discovery estimates, not official results; football score lookups also require football category and kickoff identity.
- `Fotty/Design/Theme.swift`: shared semantic typography and `FottyFixtureDifficulty` provide one contrast-tested numbered difficulty scale for pitch/table. Home cards keep curated known short names but do not algorithmically erase unknown club identity. Matchday shows one relevance explanation and date-groups later fixtures.

## 2. Playback path

The build-43 reliability patch makes decoded progress video-owned and bridge failures/recovery/native candidates document-owned. `Coordinator.handlePlaybackMessage` is separately testable while `userContentController` retains the WebKit/current-document admission guard. Replacement/backward timelines establish a baseline without themselves proving recovery. Exact release status is in `docs/releases/Fotty-2.0.0-43.md`.

1. `LivePlayerView` and `MultiLivePlayerView` present single/multi-event playback.
2. `LivePlayerViewModel` owns resolution state, source selection, timeouts, cancellation, user-facing failure state, and the single `LivePlaybackState` authority.
3. `LiveStreamResolver` resolves bounded catalog candidates through one CoreMedia/web track. It curates real variants first and uses at most one canonical fallback only for a provider family with a known canonical URL contract and only when no variants exist; Echo/Admin are never synthesized.
4. `StreamPluginRegistry` loads built-in manifests; `StreamPluginProviderMatching` restricts active Watch sources to StreamEx and Score808 families. The old Hybrid P2P implementation is behind the undefined `FOTTY_LEGACY_P2P` condition and is not part of production compilation.
5. `LiveWebEmbedPlayerView` is the physical-device WebKit adapter. It preserves the provider page for playback compatibility, performs one restrained play assist, proves readiness from decoded/advancing playback, owns attempt-scoped startup/stall recovery plus popup/nuisance/navigation containment, and reports actual HLS/MP4 candidates with the ephemeral attempt's referer, origin, user agent, and cookies. Its nuisance containment recognizes the specific VPN/install/continue-watching solicitation in accessible text and JavaScript dialogs, but never removes a matching ancestor that owns video, owns an iframe, or is effectively the player/root surface; generic overlays and the provider's real unmute prompt remain provider-owned. It also carries explicit play/pause commands through reachable HTML/JW frame media and reports non-cancelling surface taps so Fotty can reveal its bounded fallback controls without swallowing provider interaction. A non-explicit child-frame error deferred through the full startup deadline becomes a typed 20-second startup timeout; explicit provider rejections retain their reason. When the app backgrounds, its injected contract suspends reachable video/audio across the provider frame tree and resumes the same attempt on return. Native `AVPlayer` playback is different: `MediaAudioSession` activates `.playback` only at real play/PiP boundaries, and every direct or captured-candidate player opts into `.continuesIfPossible`; active PiP stays mounted and does not enter the foreground-resume path.
6. After web playback is already visible, `LivePlayerViewModel` validates and pre-rolls a candidate in a separate muted AVPlayer through `LocalStreamProxy` when headers are needed. Adoption requires advancing native playback; failure leaves WebKit untouched, and later native failure restores that same web source before provider failover.
7. `LiveSourceHealthStore` aggregates outcomes by provider family/host, ranks candidates, opens a bounded circuit after repeated failures, and stores recent decoded success used by MultiView gating.
8. `LivePlayerView` owns the portrait match header and opaque loading/error UI; retry plus manual numbered broadcast override remain in-app. Web fallback Play/Pause and Sources controls sit at the video edge, auto-hide after four seconds of playing, and reappear through the WebKit surface callback; paused playback remains actionable. Source rows use generic quality descriptions and truthful `Selected`, `Select`, or `Try again` states. An explicit Watch navigation loads the selected catalog source with manual circuit-breaker override; later automatic failover still respects source health. Provider-site Safari fallback is intentionally absent.
9. `FottyLiveActivityController` and `FottyLiveActivityPolicy` expose a system Live Activity only after AVKit confirms PiP is active; capability or a transient inactive scene is insufficient. Web embeds are excluded, PiP stop/failure clears continuity, cold launch clears orphaned activities, and the extension presents match/score/status context rather than provider health. `MatchNavigationStore` makes the return link non-stacking while the player survives and falls back to Match Center after a cold relaunch.

Playback, discovery, match navigation and FPL compile into one production graph. There is no alternate review-safe implementation or distribution-dependent vocabulary.

## 3. Match, insights, and feature data

- `Fotty/Core/Data/Repository/FootballRepository.swift` and `Fotty/Core/Data/Providers/`: normalized football provider access. `OfficialFPLScoreProvider` in `FootballDataProvider.swift` maps fresh public FPL fixtures first; API-Football and delayed football-data are fallbacks. Live rows are merged onto football-data schedule identities before seeding Match Hub's cache. Automatic/timer hub loads use schedule/live cache only, and only an explicit full refresh allows provider enrichment.
- `shared/reference-data/football-competitions-2026-27.json` is the reviewed seasonal source for five domestic leagues plus the Champions League and Europa League, canonical provider aliases, and non-membership historical match identities. `tools/generate-football-competition-catalog.mjs` validates exact counts, unique/collision-free competition identity, source metadata, generated drift and the 30 June 2027 expiry, then emits the same canonical club resolver in `Fotty/Core/Data/FootballCompetitionCatalog.generated.swift` and `web/src/lib/football-competition-catalog.generated.ts`. Home classification, fixture/FPL matching, news topics, onboarding/badge bootstrap, local social fallbacks and web team search consume it. `shared/reference-data/provider-football-identity-vectors.json` is the URL-free cross-platform provider regression corpus; `tools/audit-provider-football-identity.mjs` validates it and optionally checks current catalog metadata without requesting video.
- `Fotty/Core/Data/FootballDataPolicy.swift`: single live-score competition allowlist, cross-provider team aliases, provenance labels, schedule-window polling gate and strict requested-window filtering. It currently enables the senior Premier League (FPL, API-Football 39, football-data `PL`/2021) and records Champions League (`2`, `CL`/2001) as the next inactive scope. Schedule/catalog discovery is intentionally separate. Dashboard and Live Activity presentation require a confirmed matched schedule competition before showing score-refresh/error copy; team-name guesses, youth/cup leagues, and unmatched catalog rows retain plain status without claiming a missing promised score.
- `Fotty/Features/Social/ArenaDiscoveryView.swift`: despite the legacy filename, this is `My Matchday`, not a second global schedule. It filters the shared catalog to explicitly saved matches and followed teams, groups Live now / Next up / Later / Recent plus Saved channels, warns about overlapping kickoffs, and keeps Watch/Details available in place. It does not consume fantasy squad context.
- `Fotty/Core/Models/ArenaModels.swift`: `SavedMatchRecord` and `MyMatchdayStore` persist a bounded catalog snapshot in UserDefaults without changing the SwiftData schema. Saved snapshots keep source identifiers for cold launch, then the resolver rematches against the current catalog before playback.
- `Fotty/Features/MatchHub/`: the sole status-aware match overview and refresh lifecycle. The redundant fantasy Match Lens was removed from `InsightsHubTab`; fantasy features remain in their dedicated workspace. The unreachable Dashboard Match Center and obsolete Arena/Highlights Match Hub tabs were removed from source and the Xcode target.
- `Fotty/Core/Notifications/NotificationManager.swift`: notification permission/scheduling, foreground presentation, followed-team alert scope, notification Match Center routing, and non-stacking Live Activity return handling.
- `Fotty/Features/FPL/`: FPL feature shell organized into Gameweek, Squad, Coach, and Tools workspaces, backed by the existing views, models, and advisor/planning engines.
  - `Services/FPLService.swift`: official public API transport plus version-3 disk envelopes, source provenance and bounded endpoint-specific caching. Disk use requires the current season, endpoint identity, acceptable age and—once bootstrap is known—the same official team-catalog fingerprint. Live snapshots expire after five minutes, bootstrap after 24 hours, fixtures after six hours; storage is capped at 96 files and 90 days. Legacy raw v2 snapshots are removed. `FPLSeasonIdentifier` drives rollover-safe manager storage keys.
  - `Services/FPLManagerConnection.swift`: strict official-link/positive-ID parsing, cancellation-safe identity lookup, and a confirmation boundary before the selected manager is persisted. Input remains editable after lookup failure; an old response cannot replace a newer identity. Disconnect invalidates request IDs and clears visible state while retaining manager-scoped drafts/history.
  - `Models/FPLModels.swift` and `Models/FPLOfficialModels.swift`: decoded official contracts. `Models/FPLDecisionModels.swift` keeps validated and modeled decision output separate from official facts, defines the decision journal and route checks, and retains the expiring device-local `FPLMatchdayContextStore`. Home, Matchday and Match Center no longer read that legacy snapshot.
  - `ViewModels/FPLAdvisorViewModel.swift`: single state owner for manager, bootstrap, fixtures, history, event-live, leagues, phase, freshness, validation, transfer estimates, reviews, alerts, coach context, Rival Race loading, and journal mutations. Build 44 separates published `officialPicks`/`picksGameweek` from selected editable `picks` and `FPLLocalSquadDraft`. `applyPublishedSquad` is shared by full/foreground and live refresh, rejects older-week rollback and preserves draft/source selection. Local plans have no official history/chip/autosubs; live scoring requires a matching published gameweek. Draft array plus context/source preferences remain manager/season scoped and backwards readable. `FPLSquadSourceNotice` labels both sources and provides non-destructive switching. Unit tests inject isolated defaults; UI fixture edits remain in memory.
  - `Services/FPLDecisionEngine.swift`: phase detection, public-history free-transfer estimation, versioned expected-minutes/projection confidence, blank/double-aware projections, deterministic live automatic-substitution and captain resolution, official-versus-provisional total separation, command-center decisions, and confirmed-gameweek reviews.
  - `Services/FPLSquadValidator.swift`: shared 15-player, position, formation, club quota, budget, captain/vice, bench-GK, uniqueness, and selectability validation used by every editing path.
  - `Services/FPLPlannerEngine.swift`: explainable roll/one/two-transfer routes with week-by-week modeled gain, hit cost/break-even, explicit downside, and verify-before-deadline checks plus legal constrained safe/balanced/aggressive squad optimization with locks and exclusions. `FPLScenarioStore` persists named manager-scoped alternatives. Output is modeled and is not described as an exact ILP solution.
  - `Services/FPLAdvisorEngine.swift`: deterministic recommendations using official expected-points hints, price projections, per-90 evidence, and set-piece/selectability context; its Rival Race analysis keeps published squad facts distinct from live points and modeled player ratings.
  - `Services/FPLAICoachService.swift`: deterministic on-device facts/rules/scoring and explanation fallback. `Services/FPLSmartCoachService.swift` is the consent-gated client for the Fotty Worker, contains no provider credentials, sends bounded evidence/history, rejects stale/incomplete responses, records redacted source/model/token evidence, and maps accepted output into structured coach cards.
  - `Services/FPLDecisionJournalStore.swift`: bounded manager-and-season-scoped UserDefaults persistence for pre-deadline decisions and post-gameweek process reflections.
  - `Services/FPLAlertScheduler.swift`: local 24-hour/two-hour deadline notifications and local coach-profile preferences.
  - `Views/Components/FPLCommandCenterView.swift`, `FPLLiveTrackerView.swift`, `FPLTransferLabView.swift`, `FPLRivalMatrixView.swift` (Rival Race Centre), `FPLDecisionJournalView.swift`, and the optimizer/player views present the shared decision state. Plan uses decision/evidence columns at measured widths of at least 760 points, otherwise a single stack; metrics retain three flexible columns at ordinary text sizes and one at accessibility sizes. Squad preserves contained five-player pitch rows with two-line names, numbered fixture difficulty and a full-width roster from XXLarge upward. Transfer and wildcard changes are manager/season-scoped local drafts and never write to official FPL. Comparison selection is by player ID, with a bounded 60-result searchable sheet; its selections survive root-tab changes. Live Points/Rival Race waiting states navigate directly to Plan/Mini-leagues.
- `FottyLiveActivityExtension/FottyFPLDeadlineWidget.swift`: small/medium deadline widget with a minimal hourly official-bootstrap timeline, a visible official-source label in both sizes, and a `fotty://fpl` deep link. It has no manager identity and is not a live-score polling path.
- `web/workers/playback/src/index.js`: playback/FPL edge boundary plus `/api/football/matches` (football-data schedule proxy) and optional `/api/football/live` (API-Football Premier League current-season/date query, filtered to in-play statuses). `FootballQuotaBudget` is one globally named Durable Object that serializes upstream live requests, shares a four-minute response cache, enforces an 80-call UTC-day app budget, reserves the provider's final 20 calls, and caches current-season plan restrictions for four hours. Health distinguishes a configured credential from usable current-season access. Provider credentials are Worker secrets, never app configuration. `/api/fpl/coach` refreshes compact official FPL evidence; `fpl-scoring.mjs` answers current-total/autosub/captain-promotion questions deterministically with zero model tokens, while other questions use DeepSeek V4 Flash in non-thinking JSON mode. The route returns token usage and rejects empty, incomplete-schema, or known rule-contradicting output. `coach-contract.test.mjs` and `fpl-scoring.test.mjs` are the server contract suite. Rate-limiter bindings are abuse controls; account spending controls remain external.
- `Fotty/Core/Cloud/SocialCloudStore.swift`: despite its legacy name, this is strictly on-device SwiftData messaging. There is no PocketBase account or sync layer.
- `Fotty/Core/Storage/UserProfileStore.swift`: local profile/preferences persistence.
- Distribution does not alter Fotty's app graph, sports labels or playback availability. Any future paid product must introduce a real StoreKit purchase entitlement as a separately designed product boundary; it must not revive a hidden review-safe surface.
- `Fotty/Resources/PrivacyInfo.xcprivacy`, `SettingsPrivacyView`, and the web `/privacy` and `/terms` pages describe the same active boundaries: local profile/follows/messages/FPL planning data, public FPL manager lookup, opt-in Cloudflare Worker/DeepSeek Coach processing, local reminders/diagnostics, and third-party player pages. PocketBase email/password collection is not declared because that account path is retired.

## 4. Verification and diagnostics

- `.github/workflows/`: `quality.yml` validates workflow syntax and reachable secrets; `web.yml` runs the Node 24 unit/type/lint/Worker/build gate; `ios.yml` runs deterministic provider checks, Catalyst units and a generic unsigned iOS Release build through `tools/ios-ci.sh`; `provider-monitor.yml` keeps live metadata drift separate from pull-request correctness. Dependabot handles security/minor maintenance, while GitHub secret scanning/push protection and CodeQL are repository-side controls. The iOS script has an `rg`/`grep` fallback, uses one trap-cleaned DerivedData root and may lower only the remote Catalyst host target to match GitHub's Xcode 27 image; it never changes the app's Release deployment target.

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
- `Fotty/Core/Internal/StreamPipelineValidationService.swift` + DEBUG `StreamPipelineValidationView`: URL/contract probes plus a two-minute muted production-player continuity soak. Catalyst is the preferred long-running shared-stack host; physical Apple devices remain required for iOS-specific behavior and real provider WebKit verification.
- `FottyTests/FPLTrustTests.swift`: focused official-contract, scoring/autosub/captain/chip/hit/final boundaries, blank/double projections, phase/metrics, match-context persistence, reminders, free transfers, validation, legal optimizer, scenarios, journal isolation, deterministic Coach routing, Transfer Lab guardrails, and Rival Race tests.
- `FottyTests/BetaUsabilityTests.swift`: team-link validation, lookup failure/retry/cancellation and identity isolation, feedback contents and opt-in diagnostics, setup dismissal, truthful capability copy, preserved club identity, point gameweek/source labels, FPL session continuity and normal-text contrast for all difficulty colours. `docs/BETA-TESTER-GUIDE.md` defines the fresh-user tasks and real TestFlight report-receipt gate.
- `FottyUITests/FottyNavigationUITests.swift`: rapid tab/background lifecycle plus bounded contrast, traits, Dynamic Type, element-detection, hit-region, text-clipping, and description audits. FPL Plan, Squad, Coach, and Tools launch directly through the allowlisted Debug route and use an explicit network-free fixture; Matchday and Settings launch through their persisted tab contracts; Match Center and Player use explicit Debug-only presentation routes. The large-Type Coach audit requires both the quick-prompt control and a structured response, while the Player audit exercises its truthful no-source recovery state. Its physical-only live smoke refreshes the real catalog, selects a source-backed hero, verifies the compact source list, and holds playback muted through the initial stability window; it skips on simulators.
- `tools/stream_health_checker.py`: catalog endpoint health; it does not prove decoded video.
- `tools/test_stream_playback.mjs`: browser-level decoded-playback probe.
- `tools/audit_live_playback_matrix.mjs`: broad, concurrent WebKit matrix over current near-live provider families and variants, with an optional post-decode continuity hold that records playhead advancement and the longest freeze; writes structured JSON to `/tmp/fotty-playback-matrix.json`.
- `tools/ios-deploy-device.sh`: signed physical-device build/install workflow; it can install an explicitly supplied `.app` and terminates only the existing normal Fotty process before launch.
- `tools/ios-device-qa.sh`: no-simulator release gate; checks generated seasonal identity, deterministic provider vectors and live metadata drift, then compiles/runs Catalyst policies through build-for-testing/test-without-building, builds and strictly seal-verifies one signed universal Debug artifact, installs that exact normal app on every explicitly listed physical device, compiles generic Release iOS, and prints the manual iPhone/iPad playback checklist. It intentionally never runs `FottyUITests`, reuses one DerivedData root, and removes its default temporary root through a cleanup trap.
- `tools/catalyst-ui-release-gate.sh`: lock-guarded Mac Catalyst runner for eleven release accessibility audits—six Dashboard scopes plus FPL, Matchday, Settings, Match Center, and Player Dynamic Type—and rapid-navigation check, executed individually without a simulator or physical-device UI-test runner. Its default DerivedData root is temporary and trap-cleaned; a caller-supplied shared root remains caller-owned.
- `tools/ios-physical-launch-hold.sh`: lock-aware, physical-only normal-app launch and bounded process-survival gate; it rejects simulator targets and never installs a UI-test runner.
- `FPLMainView` accepts `--fotty-fpl-workspace` only in Debug builds to initialize Plan, Squad, Coach, or Tools for repeatable normal-app physical screenshots and Catalyst audits. `FOTTY_FPL_UI_TESTING=1` additionally enables deterministic shell state only in Debug, makes no manager/network request, and never persists its Coach fixture. The parser is allowlisted and unit-tested; Release builds have no fixture or workspace override, and physical interaction remains manual.
- The FPL UI fixture now includes a synthetic 15-player squad, a five-defender row, long names, fixtures, captain cards, Plan metrics and distinct GW1 points/GW2 planning context. Shirt requests and comparison enrichment are suppressed in that explicit fixture. `testFPLContextSurvivesTabSwitch` exercises tool/scroll restoration and searchable comparison selection; the Squad Dynamic Type check requires the populated player row, not an empty state.
- `FottyApp` accepts `--fotty-ui-test-surface match-center|player` only when the Debug-only `FOTTY_SURFACE_UI_TESTING=1` flag is present. It presents deterministic network-free catalog/Player recovery state for accessibility audits; Release builds contain neither route. `MatchHubViewModel.resume()` preserves an already loaded catalog event instead of refreshing it away.

## 5. Web and retired infrastructure

- `web/`: companion Next.js/static-export surface; it is not the source of truth for the iOS lifecycle. Its current baseline is Next 16.3.3/React 19.2.8 on Node 24 LTS with ES2022 output. Playback uses HLS.js 1.7.1. Wrangler 4.127.1 is pinned for reproducible Worker dry-runs, and the Worker compatibility date is advanced explicitly while Node compatibility remains disabled because the current Worker does not use it.
- Homelab PocketBase and P2P/AceStream are retired product dependencies. Active analytical providers, resolver tracks, manifests, and UI exclude them; only lower-level defensive legacy session-shape types remain compiled.
- `agent/` and `tools/brain/`: durable project memory and local semantic-index tooling.

## Strategic navigation

- **Launch/watchdog or score churn**: `SportsDashboardView` → `LiveScoreService`.
- **Playback resolution**: `LivePlayerViewModel` → `LiveStreamResolver` → curated catalog descriptors → `StreamPluginProviderMatching`.
- **Web playback behavior**: `LiveWebEmbedPlayerView`.
- **Catalog/metadata**: `AnalyticalDataEngine` and `FootballRepository`.
- **FPL transport/state**: `FPLService` → versioned official DTOs → `FPLAdvisorViewModel`.
- **FPL decisions**: normalized official facts → shared validation/phase/rules/projection engines → clearly labeled modeled output → local explanation or consent-gated server explanation over a refreshed evidence packet.
- **Local social/profile behavior**: `SocialCloudStore` and `UserProfileStore`.


# Decisions Log

# Fotty Decisions Log

## 2026-08-30: Treat active native PiP as background playback, not foreground decoration

- **Finding**: On a real iPad, native handoff entered the system PiP window but playback paused as soon as another app opened. Fotty declared the audio background mode and retained its PiP controller, but set only the audio-session category, left `AVPlayer.audiovisualBackgroundPlaybackPolicy` on `.automatic`, and incorrectly marked an active PiP session for foreground resume.
- **Decision/implementation**: Activate the `.playback`/`.moviePlayback` audio session only when playback or PiP actually begins, set every direct and web-handoff native player to `.continuesIfPossible`, reassert both at the PiP/background boundary, and keep the active native state without arming foreground recovery. A stopped/failed PiP while backgrounded still pauses safely. The controller now acknowledges restoration to the still-mounted player UI.
- **Evidence/boundaries**: Add a unit regression proving active PiP remains `.playing(.native)`, retains its background policy and does not mark itself for resume after backgrounding. The full Catalyst suite and unsigned generic iOS Release pass without a simulator. This cannot prove iOS process scheduling, a header-proxy stream or system PiP controls; repeat on the physical iPad by opening another app and locking/unlocking. No device install, TestFlight upload, stream request or version bump.

## 2026-08-30: Replace the unsafe Git history and make Search a projection of Home

- **Finding**: GitHub's `main` was an obsolete two-commit snapshot with no active protection or viable CI, while the real 2.0 code existed as hundreds of uncommitted paths on a stale branch. The reachable old history also contained retired Android API credentials. Separately, `SearchView` was orphaned from navigation, fetched a second catalog and could disagree with Home or reject a playable listing for lack of official football detail.
- **Repository decision**: Publish the reviewed working tree as a new root, replace `main` with an exact force-with-lease and remove both stale remote Cursor branches rather than keeping a remote backup that would preserve exposed history. Retain recovery locally. Add Node 24 Web CI, simulator-free Xcode 27 compilation/tests, actionlint, gitleaks, weekly Dependabot and a daily metadata-only provider audit. Enable GitHub secret scanning, push protection, security updates and CodeQL. Test artifacts are bounded and removed.
- **Product decision**: Put Search in Home's masthead and search `HomeSportsDiscovery` directly. Results cover sports, teams, multi-word fixtures, known football leagues, CPL and channels; matching is case/accent insensitive and distinguishes Premier League from Caribbean Premier League. Result rows reuse Home's badges, score/timing truth, opt-in reminders, saving and playback route. Selection is deferred until the search sheet dismisses so presentation layers cannot collide.
- **Evidence/boundaries**: The clean root passes working-tree and one-commit gitleaks scans, 87 web/Worker units, TypeScript, lint with zero errors, Worker dry-run and production web build. The search addition passes the full Catalyst unit suite and unsigned generic iOS Release without a simulator; GitHub repeats repository/iOS gates on the pull request. No build number, device install, TestFlight upload, Worker deployment, provider video request or paid model call.

## 2026-08-30: Treat provider league placement as an identity pipeline, not a label patch

- **Finding**: StreamEx's live Chelsea–Brighton payload used `Brighton and Hove Albion`; the seasonal catalog used `Brighton & Hove Albion`. Independent normalizers and no current-provider release check silently moved the valid Premier League fixture to Other.
- **Decision/implementation**: Generate one canonical senior-club resolver for Swift and TypeScript from the reviewed manifest. Match stream events by canonical teams first, then reconcile a team-and-six-hour-kickoff match to the already-loaded official schedule and let that competition win. Provider marker conflicts emit only redacted local diagnostics. Shared payload vectors and a metadata-only live audit fail the no-simulator release gate before Xcode.
- **Evidence/boundaries**: The first live gate also exposed valid Deportivo wording and a Bundesliga 2 multiview marker; both are classified intentionally, then all three reachable feeds pass. Five shared vectors, 87 web/Worker tests, TypeScript, the complete Catalyst policy suite and generic iOS Release pass. One Xcode 27 direct-test host hang was bounded and cleaned; split build/run passes and is now the gate. No device, simulator, upload, deployment, paid call, video request or Git publication. Full record: `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md`.

## 2026-08-30: Release the single product graph as internal build 46

- **Authority/channel**: The owner requested upload and installation, then explicitly approved the final built-in-encryption declaration, testing notes and assignment to the existing Fotty Internal Smoke group. No new tester/role, direct development install, external submission, simulator, Worker/web deployment, paid call or Git publication.
- **Binary/upload**: The signed normal Release archive reports matching app/extension 2.0.0 (46), expected identifiers, minimum 26.4 and strict signatures. Xcode 27.0 reports `Upload succeeded` at approximately 17:56 AST on 2026-08-29. Source/config/test fingerprint is `01cb09a24fdcfb716f1642e54c904c971daaa0d83455dac397fc349b0daa2a84`; executable SHA-256 is `9ddd57fb9dd5436d3523567418d6d89f915f4fcd741f4d07a68284777a923054`.
- **Apple/status**: Processing completes. After a stale App Store Connect session produced a misleading unsaved localization error, the owner reauthenticated; the approved compliance answer and notes then saved without error. Only Fotty Internal Smoke was assigned. At 09:14 AST on 2026-08-30, a fresh builds-page read shows build 46 Internal / Testing, the expected group and two testers.
- **Installation boundary**: TestFlight 4.3.0 was opened on both connected devices. At 09:18 AST, a direct read confirms Jet iPad installed build 46. Jelani's iPhone remains build 44 even after TestFlight was reopened, so its update is still pending. The iPad version read certifies installation only; availability/installation do not certify launch, retained data or physical acceptance.
- **Resources**: The one bounded build/archive/export root and separate distribution logs are removed; no task-owned build 46 path remains and disk reports about 53 GiB free. Full record: `docs/releases/Fotty-2.0.0-46.md`.

## 2026-08-29: Retire the review-safe product graph after build 45 exposed it to a tester

- **Finding/cause**: Physical TestFlight installation showed `Field Events` and `Reference`. Those were hard-coded review-safe aliases, not provider labels. Build 45's new normal-Release StoreKit check started restricted while `AppTransaction` resolved and could retain or render that state; private Debug build 44 entered the normal app directly, which is why prior device work did not show the defect.
- **Owner decision**: Eliminate the review-safe codebase instead of repairing its transition. Fotty now has one truthful product graph across Debug, Release and TestFlight. A future paid tier requires a separately designed StoreKit product and cannot revive hidden vocabulary or substitute core functionality.
- **Implementation**: Delete `IntegrityService`, `LicenseManager`, ReviewSafe substitutions/plist/directory, StoreKit distribution policy, runtime capability gates and all `APP_REVIEW_SAFE` wrappers/configurations. Restore unconditional Home, real sport/league names, catalog discovery, playback, Matchday/social, reminders, live activities and MultiView. Add unit/UI vocabulary coverage and a release-gate source scan.
- **Version/evidence**: Allocate local 2.0.0 (46). Final-source Catalyst units and generic iOS Release pass without a simulator; focused vocabulary and retired-symbol scans pass. The Home Catalyst UI test compiled but UI automation timed out before execution on two attempts, so no UI pass is claimed. Every bounded temporary Xcode root was removed; about 52 GiB remains free.
- **Distribution boundary at implementation time**: No physical install, TestFlight upload, provider probe, paid model call, server deployment, tester mutation, external submission or Git publication occurred in the correction pass. The 2026-08-30 entry records the later authorized build-46 TestFlight release. Build 46 still needs physical cold-launch labels/Watch/Matchday/FPL acceptance. Full implementation record: `docs/audit/Fotty-Single-Product-Graph-2026-08-29.md`.

## 2026-08-29: Release the consolidated data/platform safety round as internal build 45

- **Authority/channel**: The owner approved TestFlight delivery, then separately approved the exact testing notes and assignment to the existing Fotty Internal Smoke group. No new tester/role, direct install, simulator, external submission, Worker/web deployment, paid call or Git publication.
- **Version/preflight**: Apple independently showed 43 as the latest upload; private 44 was never uploaded. `tools/set-version.sh 2.0.0 45` updated the app, extension and XcodeGen source together. Minimum 26.4 remains because no physical iOS 18 runtime is available.
- **Included scope**: Consolidate build 44's published/local FPL squad boundary, Coach conversation/context invalidation, reviewed 2026/27 competition generation and strict league inference, versioned season/freshness caches and reconciled privacy boundaries. Internal access now uses verified StoreKit `AppTransaction` sandbox/Xcode environments and fails closed for production/unverified/error states. Web dependency modernization remains undeployed source and is not delivered by TestFlight.
- **Evidence/upload**: Reuse recent exact-source 219 Catalyst passes plus one opt-in skip, StoreKit policy coverage, both generic iOS Release configurations, 86/86 web units, zero lint errors (93 warnings), production web build, zero npm vulnerabilities and no-deploy Worker dry-run. The version-only normal archive reports matching 2.0.0 (45), identifiers, minimum 26.4 and strict signatures. Xcode upload succeeds at 15:15:49 AST; source fingerprint is `d44b43cad20f0bb1a0cbe2d1f3e002756c1d905ac667fad43f8cfe157f350131` and executable SHA-256 is `feb43769227cb1c3673e1852a6fa50444ac51146e323d0348c4bd77683b4e652`.
- **Apple/status**: Processing completes; the owner saves the built-in-encryption-only declaration. After explicit approval, English (U.K.) notes are saved and only Fotty Internal Smoke is assigned. At 15:21 AST, Apple independently shows build 45 Internal / Testing with two invitations. Installation/session/crash/feedback dashes are not acceptance evidence. The complete record is `docs/releases/Fotty-2.0.0-45.md`.
- **Resources**: The one `/private/tmp/FottyTF45.*` DerivedData/archive/export root and separate Xcode distribution logs are removed. No Fotty build process or task-owned archive remains; disk reports about 53 GiB free.

## 2026-08-29: Modernize the compatible platform baseline and replace receipt-name trust

- **Authority/scope**: The owner requested the one-time distribution migration plus a current dependency/platform review. This authorizes implementation and qualification, not a version bump, device install, TestFlight upload, Worker deployment, paid model call or simulator.
- **Distribution decision**: `LicenseManager` now verifies `AppTransaction.shared` and grants internal access only for StoreKit-verified `.sandbox` or `.xcode` environments; production, unverified and error states fail closed. Normal Release begins review-safe, resolves asynchronously and retries on activation. Grants are process-local, old unlock defaults are removed, and Release ignores distribution overrides. Debug and the compile-time Review Safe boundary retain their intended roles.
- **Compatible upgrades**: Move the web toolchain to Next 16.3.3, React 19.2.8, Motion 13.1.1, HLS.js 1.7.1, Tailwind/PostCSS 4.3.3, Playwright 1.62.1, pinned Wrangler 4.127.1 and a Node 24 LTS production baseline; emit ES2022, declare npm 11.8.0, ignore Wrangler state and pin the Worker's current compatibility date without enabling Node compatibility it does not use. Remove obsolete Xcode bitcode settings.
- **Measured deferrals**: Do not enable TypeScript 7 while Next rejects the bridge package, ESLint 10 while Next's bundled plugins declare an incompatible peer range, or Swift 6 complete concurrency while the app still has concrete WebKit/AVKit/delegate/shared-state isolation failures. An iOS 18 Release override compiles, but checked-in 26.4 remains until the owner accepts the expanded support/physical-QA matrix.
- **Evidence**: Web units 86/86, lint zero errors/93 warnings, Next production build and zero-vulnerability full/production audits pass. Wrangler dry-run passes without deployment. Final Catalyst execution is 220 with one existing opt-in skip and zero failures; normal and Review Safe generic iOS Release pass without simulators. All owned Xcode/Wrangler temporary output is removed. See `docs/audit/Fotty-Platform-Modernization-Audit-2026-08-29.md`.

## 2026-08-29: Centralize seasonal truth and fail closed at stale-data boundaries

- **Authority**: After the broader outdated-data audit, the owner approved all six proposed remediations. This authorizes local implementation and qualification, not a version bump, device installation, TestFlight upload, Worker deployment, public submission or legal certification.
- **Reference data**: Maintain one reviewed JSON manifest for Premier League, La Liga, Serie A, Bundesliga, Ligue 1, Champions League and Europa League. Generate the Swift and TypeScript catalogs; fail checks for count mismatch, duplicate/colliding aliases, stale generated output or dates after 30 June 2027. Classifiers and fallback browsers consume generated membership and require both current clubs for a domestic league. Non-domestic markers remain Other; explicit UCL identity remains authoritative.
- **FPL and schedule safety**: FPL disk envelopes are version 3, current-season only, endpoint-age-limited, catalog-aware and pruned to 96 files/90 days. Old raw v2 cache is retired. Local planning/profile/review/chat keys derive from the current FPL season. An empty requested football schedule remains empty rather than borrowing older fixtures.
- **Distribution and disclosure**: Remove the client-side Pro key, `FOTTY_FULL_ACCESS` Release condition and remote integrity unlock. Debug and Apple's sandbox/TestFlight receipt retain internal access; public receipts are immutable-safe and cannot inherit an old stored/environment unlock. Update web Terms/Privacy, the iOS Privacy screen and `PrivacyInfo.xcprivacy` to disclose actual local records, public FPL manager IDs, opt-in Cloudflare/DeepSeek Coach processing, third-party playback and local diagnostics; remove inactive email/credential declarations. This is an engineering disclosure reconciliation, not legal advice.
- **Evidence/boundaries**: Shared-generator check, Privacy plist/project lint, 86 web units, lint with zero errors and production web build pass. Seven new Catalyst policies pass in a focused run; the final full suite passes 219 plus one existing opt-in skip. Both generic iOS normal and Review Safe Release compile. An initial Catalyst host stalled while another Xcode device test was active; it was bounded/cleaned and the uncontended reruns passed. No simulator or device was used, and every owned temporary root was removed. Exact scope is in `docs/audit/Fotty-Reference-Data-Freshness-Remediation-2026-08-29.md`.

## 2026-08-29: Use current two-club membership for Premier League catalog inference

- **Finding**: The owner's Coventry premise was outdated—official 2026/27 Premier League material confirms Coventry, Hull and Ipswich were promoted, while Norwich is not a member. The real Fotty defect was an older duplicated club list plus a team-pair helper implemented as either-side matching, allowing Norwich fixtures through when one opponent matched.
- **Decision/implementation**: Keep one season-labelled official 20-club catalog. Home requires both current senior clubs for roster inference, refuses a conflicting provider Premier League label, and excludes cup/youth/friendly/lower-division markers. Champions League identity remains explicit. Club browsing/bootstrap and news inference consume the same catalog; other league pair inference now also means both sides.
- **Status/boundaries**: Local Unreleased source on top of private build 44. Focused policy tests pass 70 plus one optional HLS skip; the full suite passes 212 plus the same skip, with no failures/runtime warnings, and both unsigned iOS Release configurations compile. Exact fingerprint and 812 MB temporary cleanup are in `docs/audit/Fotty-Premier-League-Membership-2026-08-29.md`. Norwich remains under All Football when legitimately listed. No install, upload, deployment, simulator, UI automation, paid call or stream probe.

## 2026-08-28: Continue quality work; guard Coach conversation lifetime

- **Decision**: The owner deferred public-testing discussion and asked to continue improving the existing app. No Ad Hoc/PWA distribution pivot, public review submission or feature removal was selected.
- **Scope**: Pending Coach requests now belong to the shared workspace and are invalidated by clear/disable/disconnect. A planning-context check rejects stale replies without an automatic paid retry; old completions cannot stop a newer request. Recovery uses the normal published-fact/freshness boundary. A failing offline test additionally exposed direct current-total wording missing from both scoring classifiers; both now recognize the bounded phrases while retaining model-backed strategy.
- **Evidence/status**: 209 unit passes plus one optional HLS skip, 82 web/Worker passes, two scoped Catalyst UI passes (existing main-thread warnings retained), and both unsigned iOS Release builds pass. Exact delayed-result tests, the pre-test automation retry, fingerprints and 1.1 GiB temporary cleanup are in `docs/audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md`. Changes are Unreleased, not in installed iPhone 44 or TestFlight 43. The Worker change is not deployed. Paid model quality and physical acceptance remain separate.
- **Boundaries**: No paid Coach calls, Worker deployment, device install, simulator, tester changes, upload or Git publication. Cancellation cannot recall an already-sent request or guarantee cancellation of upstream cost.

## 2026-08-28: Separate published FPL squads from saved drafts; phone-first small fixes

- **Authority**: The owner approved the discussed correction and an iPhone-only installation, with no TestFlight upload. Small fixes are privately tested first; shared fixes/features are batched into deliberate TestFlight releases. Version every acceptance build; small scope does not waive data-integrity checks.
- **Implementation**: `FPLAdvisorViewModel.officialPicks` and `picksGameweek` are immutable-to-edit scoring evidence. Full/foreground and matchday refresh restore the selected saved draft independently. Source notices identify the actual public gameweek and explain deadline publication; switching to published picks preserves the draft. Legacy array storage remains compatible with 43. Validation failures stay in the picker and never report Saved. Coach/public scoring exclude local chips, history, autosubs and multipliers, while model planning is labeled as a draft.
- **Verification/status**: Source is 2.0.0 (44), allocated after read-only Apple verification that 43 is latest. Final suite: 200 unit passes plus one optional HLS skip, no unit runtime warnings; three scoped Catalyst UI passes with existing beta-Mac warnings, 24 Worker contract/scoring passes, signed normal Debug and ReviewSafeRelease iOS build passes. Installed in place on the owner's iPhone, independently version-checked, and passed a 20-second argument-free hold. Linked manager, 15-player saved draft, appearance and saved matches are unchanged. No physical touch/visual acceptance is inferred: the screenshot transport was unavailable. Exact fingerprints, limits and cleanup are in `docs/releases/Fotty-2.0.0-44.md`; TestFlight remains 43.
- **Boundaries**: No simulator, device UI-test runner, iPad change, TestFlight upload, tester/notification mutation, paid-model request, Worker deployment or source publication. The original diagnosis remains a historical record, not current release status. Unsaved Transfer Lab staging still requires Save; private official-app changes need public deadline publication and are not fetched through passwords/cookies.
- **Test identity**: The owner questioned Alexander-Arnold appearing during tests. It was a hard-coded long-name UI fixture, enabled only by the explicit Debug testing flag, not a current official FPL record. A fresh official feed contained no matching player. Fixture/search assertions now use clearly synthetic names (including Test Double-Name); retain that clarity and never substitute stale real players in mock lineups.

## 2026-08-28: Diagnose FPL squad replacement and official-transfer visibility

- **Report**: Pedro Porro replacement appears not to save; the owner clarified it was also made in the official FPL app. Diagnosis only, not implementation or official-team mutation.
- **Findings**: Fotty imports public deadline picks, not authenticated current team state. Previous-event fallback can sit beneath a new-event heading. Separately, valid local squad edits are written to manager-scoped storage but a successful official refresh replaces displayed picks and disables draft mode; saved drafts load only if official picks are absent. Picker dismissal and one-tap recommendation success reporting do not reliably surface rejected changes.
- **Evidence/limits**: Code-path inspection and a time-scoped public API sample establish the mechanisms, not a reproduction of the owner's exact private transfer. The sampled Mac manager is also present in tests and is not confirmed as the phone identity. No app-code changes, builds, simulator, device install, server deployment or paid-model calls. See `docs/audit/Fotty-FPL-Squad-Persistence-Diagnosis-2026-08-28.md` for proposed separate official/draft state and missing regression coverage.

## 2026-08-28: Invite one owner-selected CPL internal tester

- **Authority**: The owner selected one additional trusted participant and, after explanation of the broader Marketing-role permissions, explicitly approved sending the Fotty-only App Store Connect invitation. Store the participant as CPL-03 in repository records, not by email. This does not authorize general beta expansion or changing other users' access.
- **Action/evidence**: Apple explicitly confirms the account invitation was sent. Marketing is the only selected role, Fotty the only selected app, and Create Apps is not granted. The fresh Users list shows Marketing / Resend Invitation but labels scope All Apps; Fotty was the sole chooser app, so restriction against future apps is not verified. Edit App Access remains disabled while the invite is pending. After acceptance, verify/narrow scope before internal-group assignment. The participant is not yet eligible in the group's Add Testers list; do not claim a TestFlight invitation or installation yet. No duplicate invitation or deletion was made.
- **Installed baseline**: At 13:23 AST, the group's two original testers both show Installed 2.0.0 (43). No launch, retained-data, playback or feedback-receipt pass is inferred from installation. `docs/beta/ROUND-01-ACCEPTANCE.md` records the evidence and CPL focus.
- **Boundaries**: No build, simulator, device install, new release, Worker change, external submission, source publication or raw tester-data export.

## 2026-08-28: Begin the approved reliability-first next phase

- **Authority**: The owner accepted the nine-gap recommendations and their order. Start by releasing the five existing fixes and preparing fresh-user evidence. Preserve current UX and TestFlight-first delivery; no new people/roles, paid service, name, external submission or Git publication is selected by this approval.
- **Release**: Apple preflight confirms latest upload 42 and two current testers Installed 42. Allocate 2.0.0 (43). Web/Worker tests pass 81/81, production web build passes, Swift units pass 191 plus one optional soak skip and zero runtime warnings. Two scoped UI audits pass after one permitted pre-test automation timeout retry; each retains a main-thread warning. Current archive/Apple/cleanup outcomes are maintained in `docs/releases/Fotty-2.0.0-43.md`.
- **Service**: Deploy `fafdf5ed-4d37-47e6-82b8-69dd55c3e116`, retaining previous revision `39e913bd-d1fb-48e4-bf56-20be2ba183e4` as rollback reference. Live health, invalid/oversize Coach bodies and missing-scoring zero-token response pass. No real manager or paid model request is used in this smoke; tactical routing remains covered offline.
- **Next-phase evidence**: Add a phased plan, fresh-tester/long-playback ledger and Coach acceptance-case specification. Fix stale build-35 tester-guide references and obsolete Home/Matchday fantasy assertions in the physical QA script. Unperformed tests remain unperformed. Lower-iOS support is a diagnostic assessment, not a deployment-target change; recovery/sync, spend budgets and rebranding retain explicit decision boundaries.
- **Completed release checkpoint**: Apple accepted 43 at 12:37:49 AST and independently completed processing by 12:41 AST. The owner then explicitly approved the same system-encryption declaration, notes and unchanged group at action time. All three were saved; the notes persisted after reload and only Fotty Internal Smoke (two testers) was assigned. At 12:47 AST, the independent builds page shows 43 Internal / Testing with two invites. This verifies availability, not installation, physical acceptance or report receipt. No rebuild/re-upload was needed. Unchanged-source normal Release app/extension also compile with an iOS 18 override, but 43 retains 26.4. The 1.4 GB owned build tree and separate distribution logs are removed, prior web output restored, and 62 GiB free. No paid model tokens were used by the production smoke.

## 2026-08-28: Fix the five audited reliability boundaries locally

- **Authority/scope**: The owner's “ok now we fix those” authorizes the five reproduced playback/FPL/Coach defects and regression tests, not a wholesale rewrite or rollout. Distributed TestFlight remains 2.0.0 (42); these changes are Unreleased. No simulator, direct install, deployment or Git publication.
- **Playback**: A replacement/reset playhead establishes a new baseline; only forward progress clears a stall. Post-start failures/recovery/native candidates are document-owned, DOM media errors are primary-video-owned, and callback ordering prevents a delayed failure from overtaking recovery. Pause/background behavior and provider controls remain intact.
- **FPL/Coach**: Both scoring engines require complete unambiguous picked-player evidence before projection/derived totals. Unknown totals are optional/null, not zero; supported official totals retain incomplete labels. Known gameweek mismatch cannot authorize a current total. Missing/stale scoring yields a low-confidence zero-token rules answer; local freshness uses the oldest picks/live fetch, not a fresh unrelated resource. General tactical advice still uses DeepSeek, while iOS rejects model-origin responses to recognized scoring queries.
- **Request extraction**: `web/workers/playback/src/coach-request.mjs` separates bounded stream reads, parsed/nested shape validation and limiter failures from orchestration. Configured limiter outages fail closed; optional binding behavior and no-client-secret policy are unchanged.
- **Verification**: Original probes 6/6; full web suite 81/81; Mac Catalyst units 191 pass plus one optional live-HLS soak skip, no failures/runtime warnings. Build/cleanup outcomes and remaining physical iPad acceptance are maintained in `docs/audit/Fotty-Complexity-Fixes-2026-08-28.md`. No paid model calls were needed. Preserve the original audit's pre-fix evidence rather than replacing its baseline with passing results.

## 2026-08-28: Read-only complexity audit finds untested playback and FPL boundaries

- **Scope**: The owner approved the proposed audit, not implementation. SwiftLint 0.65.1 measured 161 Swift files; ESLint 9.39.4 measured the active Worker/scoring modules and extracted playback monitor. Retained P2P/conditional code is identified separately from active Watch risk. No app/test/version/production configuration changes, builds, simulators, device operations or deployments.
- **Findings**: Offline execution of unchanged production JavaScript reproduces a false stall after a video-element/playhead reset, unrelated-video errors entering broadcast failure, a missing live-stat row becoming a projected keeper autosub, a scoring question falling through to the model on official-refresh failure, and null JSON escaping controlled request validation. No live API or paid model call was made; the model response was a stub. These are synthetic boundary reproductions, not proof of the cause of a particular physical-device incident.
- **Evidence**: All 11 existing Worker tests pass; the new audit-only probes have one passing control and five violated safety expectations. Swift tests were inspected, not rerun. The application/source fingerprint remains unchanged. Report and reproducible runners/results: `docs/audit/Fotty-Complexity-Audit-2026-08-28.md` and `docs/audit/complexity-2026-08-28/`.
- **Next step, not authorized by this audit**: Fix the false playback stall, missing-data autosub and scoring/model boundary first with regression tests; then auxiliary-media errors, request shape and targeted responsibility extraction. Preserve attempt/cancellation guards and the reminder queue. No blanket rewrite or complexity-score gate was added. Temporary analyzers are removed; disk remains about 63 GiB free.

## 2026-08-28: Consolidate the tested app in internal TestFlight; discuss next steps only

- The owner authorized updating TestFlight, not further feature implementation. Preflight confirms build 35 as the latest Apple upload and the existing two-tester Fotty Internal Smoke group, with feedback on and manual Xcode build assignment. Because build 41 already reached the iPad, allocate 42 without changing app feature code.
- Reuse the exact build-41 source fingerprint and its 184-unit/two-scoped-UI evidence. Fresh optimized normal Release archive passes bundle versions/IDs, OS minimum, strict signatures, compiled icon and empty embedded provider-key checks. Source/config fingerprints stay unchanged; no ReviewSafe substitution.
- Apple accepts the upload at 00:01:49 AST; processing is complete at the 00:03 AST read. The owner approved the built-in-encryption-only answer, tester notes and existing-group assignment. An expired session interrupted the initial declaration save at 06:15 AST; after the owner signed in, a fresh read confirmed it was still missing before the approved retry. **Ready to Test** then verified. Six What to Test tasks/known limits were saved in English (U.K.), only Fotty Internal Smoke was assigned, and its two testers verified unchanged. At 06:18 AST the builds page reports **Internal / Testing** with that group. No rebuild/re-upload was needed. The single 314 MB build/archive/export root and 576 KB distribution logs remain removed; 40 GiB is still free. See `docs/releases/Fotty-2.0.0-42.md`.
- No direct device install, simulator, account/tester/role changes, external beta/App Store submission, server deployment or Git publication. Future product ideas are discussion-only; TestFlight availability is not physical acceptance or feedback receipt.

## 2026-08-27: Approved compact rows and secondary live saving

- The owner's “proceed” approves restoring names/badges left and Watch right, retaining upcoming countdown/reminder controls and moving live saving into a secondary action. Build 41 implements a measured shared row with an accessibility/narrow-width fallback instead of an unconditional action strip. Countdown and error state are not duplicated across layout alternatives.
- Save/Remove remains in each row's native long-press menu and accessibility actions; optional setup/Help explain it. Saving remains silent, and existing saved matches/reminders are preserved. Reminder and stream-retry explanations span the full row. No provider/playback-engine or API changes.
- Verification and iPad outcomes are recorded in `docs/releases/Fotty-2.0.0-41.md`. TestFlight remains 35; only the normal iPad app is within the standing diagnostic authorization. No simulator, physical UI-test helper, iPhone install or Git publication.
- Final evidence: 184 unit passes (one optional skip, no unit warnings), two scoped Catalyst interaction passes (two beta-Mac main-thread warnings), normal/Review Safe Release and signed Debug passes. App/extension versions/signatures and unchanged source hashes verify. iPad independently reports 41, passes the 20-second normal hold, and its portrait capture confirms Watch-right rows, no permanent bookmarks, preserved badges and future countdown/bell controls. Physical menu/bell taps and real reminder delivery/return are not certified.

## 2026-08-27: Owner pauses build-40 layout for density/bookmark discussion

- Build 40 is installed on the iPad, version-checked and passed an argument-free 20-second hold; 181 unit tests and all three iOS build variants pass. The owned 1.1 GB temporary tree was cleaned after interruption. TestFlight remains 35.
- The owner dislikes Watch below names because cards are taller and questions a visible bookmark on already-watchable live rows. The action stack was applied too broadly. Discuss restoring names/badges left and Watch right for live cards; keep future countdown/bell controls and only stack when width/large text requires it. Save-to-Matchday is a secondary quick-return action, not stream readiness. Do not implement this discussion without approval. Physical notification delivery/return and final layout acceptance remain open.

## 2026-08-27: Approved inline countdowns and explicit match reminders

- **Physical follow-up 40**: Build 39 reached the iPad, so the subsequent full-contrast future-row correction advances to 40. The real screenshot caught disabled parent styling dimming future names; plain informational content now stays readable while playback alone is gated. Updated visual tests render actual Home rows. The repeated full unit suite passes 181 tests with one optional skip and no warnings. Final build/device/cleanup evidence is in `docs/releases/Fotty-2.0.0-40.md`. The physical launch helper also accepts CoreDevice's wired `connected` state without dropping its lock, physical-target or installed-app checks.
- **Decision**: The owner approved the opt-in idea. Use scheduled-start countdowns, not guaranteed-availability promises; reveal a play attempt two minutes before start. Remind me schedules a local five-minute alert and saves the match; saving alone stays silent. No new countdown/details screen or automatic playback.
- **Implementation**: Shared timing controls/guards across Home, Matchday and Match Center; MultiView uses the same two-minute window. Per-event failed lookup remains inline with Retry. Stable UTC reminder requests, bounded capacity, persisted consent, exact fresh-ID reconciliation, known status revocation and a serialized revision-checked queue prevent duplicates, overdue alerts and cancelled work resurfacing. Notification taps reveal the saved match in My Matchday. Disk-cache rows cannot erase saved source descriptors during foreground reconciliation.
- **Verification**: Final unit suite: 180 passed, one optional HLS skip, zero runtime warnings. New coverage includes silent save, denial/late permission, cancellation during every async boundary, concurrent opt-ins, reschedules/unknown times, expiry, capacity isolation, route selection, direct-action timing and nonblank themed/narrow controls. iOS/iPad outcomes and the remaining real reminder delivery/tap acceptance are in `docs/releases/Fotty-2.0.0-39.md`.
- **Boundary**: Local notifications cannot learn reschedules while the app is closed; Focus/notification settings may delay or silence them. No new API, model cost, server, provider polling, simulator, device UI-test helper, iPhone install, TestFlight upload or Git publication. Existing iPad-only diagnostic authorization applies.

## 2026-08-27: Approved uniform sport grid and full iPad sport visibility

- **Decision**: The owner approved the discussed tile layout. Every sport gets equal dimensions and a reserved two-line title; the American football label must not make only its own tile taller. Use the iPad's available width and additional rows for all listed sports, without More sports. Compact phones retain the bounded selector and selected-overflow continuity.
- **Implementation**: A small measured SwiftUI layout shares the tallest natural height across every cell and derives columns from actual width plus a Dynamic Type-scaled minimum. The iPad policy remains expanded in compact Split View. No catalog counts, playback ownership, API usage or navigation destinations change. Candidate 38 also includes the previously approved dedicated Appearance/no-Engineering and badge-cache fixes.
- **Verification**: Build 38 is installed and independently version-checked on the physical iPad. Final 155-unit suite passes with one optional soak skipped and no runtime warnings; normal/Review Safe Release and signed Debug pass. Physical Home shows uniform eight-column-plus-overflow-row geometry and real Yankees/Astros badges. A requested Settings capture instead showed Home and is not Settings interaction evidence. Argument-free 20-second launch hold passes. See the build-38 record for boundaries.
- **Next discussion, not implemented**: The owner rejected Open broadcast beginning a lookup only to report no streams. Code uses supported catalog descriptors, not verified availability, and distinguishes Watch/Open broadcast by timing. The owner prefers an inline countdown that becomes tappable about two minutes before start; a separate details screen is unnecessary unless it contains useful match information. Prefer Starts in over Available in because the schedule cannot guarantee provider readiness. Keep a not-ready retry inline. No countdown/routing edit or build 39 was produced while this interaction is being discussed.

## 2026-08-27: Dedicated Appearance, no normal Engineering, discuss equal sport tiles

- **Owner feedback**: The inline Light menu is poorly positioned. Appearance should be a normal Settings destination with clear Light/Dark choices. Engineering is not useful in the everyday interface. American football tiles are taller and iPad should expose more sports, but discuss that layout before changing it.
- **Implemented locally for 38**: Dedicated Appearance row/screen (Dark default, Light, System); Engineering removed from normal Settings even in Debug, with Report a problem retained. The real iPad revealed missing baseball crests: preserve bundled badge seeds when loading sparse persisted cache and extend existing static ESPN NBA/MLB artwork using verified current catalog names/URLs. No new runtime catalog API. Build 37 remains on the iPad, 35 on TestFlight.
- **Pending decision**: Equal tile-height/label slots and width-aware iPad capacity are proposals only. No new tile geometry/capacity edit or build-38 install was made after the owner requested discussion. Real touch, appearance-screen persistence and final baseball image acceptance remain open. See `docs/audit/Fotty-Appearance-and-Identity-2026-08-27.md`.

## 2026-08-27: Restore sports identity and add optional light appearance

- **Decision**: The owner likes the compact all-sports Home but considers real team badges and recognisable sport imagery essential to Fotty's identity. Restore badges beside each team and equipment symbols in sport tiles/menus; do not undo the approved layout or rename the app. The owner explicitly authorized app-wide light mode after the playback fix, with Dark as default.
- **Implementation**: Reuse cached provider/catalog badges and matched football crests; fit artwork rather than cropping it, observe catalog updates, and keep named initials only when artwork is missing. Channels/unpaired events have no invented teams. One shared sport-symbol mapping serves normal and Review Safe catalog adapters. `FottyAppearance` persists Dark/Light/System; adaptive surfaces, text, borders, status colours and shadows support the choice. Amber text and gold fill are separate roles. FPL sheets inherit appearance; pitch artwork and playback remain dark. No root identity reset, new image provider, paid API or FPL data migration.
- **Evidence/boundary**: Build 37 follows the physically installed build 36. Final-source unit suite: 148 passed, one optional HLS soak skipped, no failures/runtime warnings. Both-mode contrast and real symbol availability pass; light/dark iPad-width and narrow large-Type component renderings were inspected. Initial test compilation needed a locally scoped fixture helper; one old test expected the replaced athlete icon and was updated to the new equipment contract. Physical and build outcomes are in `docs/audit/Fotty-Appearance-and-Identity-2026-08-27.md`. TestFlight remains 35 until separately uploaded. No simulator, device test helper, external distribution or Git publication.

## 2026-08-27: Preserve provider transport taps and deliberate pause state

- **Decision**: The CPL centre/lower-left pause/resume report is a control-ownership and state-consistency defect, not a reason to add another central button. Provider controls remain canonical; Fotty's fallback stays bounded at the upper-right and fades while playing.
- **Implementation**: Remove the UIKit surface tap recognizer and observe DOM clicks passively in each frame. Report actual decoded-video pause/play, tied to document/source/attempt; rejected Play restores paused UI. Intentional pause cancels handoff and ignores delayed stall/recovery callbacks, while genuine interruption recovery is preserved. `_blank` prevention no longer swallows legitimate JavaScript handlers; known nuisance blocking stays. Executing injected JavaScript also caught and fixed an uninterpolated startup timer.
- **Verification**: Playback-source suite passed 144 tests with one optional HLS skip. Signed normal 2.0.0 (36) was installed on the requested iPad Air 4, independently version-checked, launched and survived 30 seconds. The exact live centre/lower-left pause-and-resume touch acceptance remains open. Computer Use decoded Willow video on Mac, but its media action timed out, so no successful tap claim follows. See `docs/audit/Fotty-Playback-Controls-2026-08-27.md`. Direct iPad testing is the owner's explicit exception to TestFlight-first delivery.

## 2026-08-27: Implement the approved compact all-sports Home

- **Decision**: The owner approved the interactive cross-sport Home concept. Make activity discoverable without visiting every category. Keep the name and four-tab structure; the additional light-mode question remains a recommendation, not an app-wide conversion or upload instruction.
- **Implementation**: All sports default; five visible sport activity tiles plus an activity-aware overflow; a maximum three-event mixed-sport Now & next list; two later events; and See all on Home's navigation stack. Native competition/cricket filtering, saved/followed Matchday and existing source-gated playback routes remain. Exact IDs or sport/start/team-pair duplicates are collapsed for presentation without a canonical-ID migration. Source-free CPL rows retain dated provenance; channels and uncertain timings do not become live events. Current official state has priority, but an unavailable/stopped score poller cannot perpetuate stale in-play state beyond the bounded freshness rule. Non-team catalog titles no longer invent an Away opponent.
- **Quality**: An interaction test caught an accessibility-container/button mismatch, corrected in the view. Computer Use inspection caught real-catalog non-team title and sport-label defects. Repeated beta-Mac contrast flags were checked against captured pixels and a separate >=7:1 actual-color unit test. A trial scoped exception merely exposed additional false-positive candidates, including white headings on black and black Watch text on amber; those new exceptions were removed. The original contrast audit remains unmodified and is not claimed clean. See the audit record for final unit/UI/build evidence and limitations; physical contrast acceptance remains open.
- **Boundary**: Local, unreleased work on build 35; no additional API/model use, source probing, playback-engine changes, simulator, device install, upload, server deployment, tester changes or Git publication. Light mode requires a coherent semantic-palette and whole-app accessibility pass. Preserve one bounded DerivedData directory, two jobs and cleanup.

## 2026-08-27: Keep fantasy in FPL and distinguish cricket channels from CPL fixtures

- **Decision**: The owner's “proceed” approves removing redundant Home/Matchday FPL promotion and the Match Center fantasy panel, plus improving discovery of existing Willow/cricket coverage. Preserve the dedicated FPL workspace, manager/data/drafts, followed teams and saved broadcasts.
- **Implementation**: Cricket gains All cricket / CPL / Channels filters and separate Willow/Fox rows with source-gated Open channel actions. Saved channels never expire from negative date sentinels. The 39-fixture CPL 2026 snapshot is explicitly dated and season-bounded, includes the July TKR correction and Barbados Tridents name, and preserves Jamaica's UTC−5 starts. Stream enrichment requires both franchises and kickoff within an hour; neither channel names nor stale saved schedule sources can invent match coverage. Shared timing uses football/T20-specific estimates and avoids a false two-hour final for unknown cricket formats.
- **Evidence**: The provider returned six Willow variants (HD/SD pairs for Willow, Willow 2 and Willow Sports). Actual decoded Willow video showed the current Jamaica Kingsmen–St Kitts & Nevis Patriots CPL match on Catalyst. The visual pass caught channel counts labelled as matches and a synthetic “vs Away” player title; both were corrected. Exact final checks, initial failures and evidence limits are recorded in `docs/audit/Fotty-Cricket-and-Tab-Separation-2026-08-27.md`.
- **Boundary**: Local implementation only; build 35 remains distributed. No new paid API, official Willow account integration, server deployment, simulator, device install, tester change or Git publication. Future CPL releases require manually checking schedule announcements; this snapshot is not a live feed or programme guide. Retain TestFlight-first delivery and the separate clean-ancestry publication requirement.

## 2026-08-27: Upload build 35 through the internal-only TestFlight channel

- **Preflight**: The owner restored browser sign-in. App Store Connect listed `2.0.0 (34)` as the only completed upload and Fotty Internal Smoke as the existing group (two testers, feedback on, manual Xcode build assignment). `tools/set-version.sh` allocated 35 across app, extension and `project.yml` without changing marketing version or app behaviour.
- **Build**: Reused the immediately preceding final-source unit/UI/compile evidence; created one optimized normal Release archive, generic iOS, automatic signing, two jobs. Both bundle identifiers, versions, iOS 26.4 minimum and strict signatures passed. Provider API-key values were explicitly empty. The source/config fingerprint stayed unchanged across archive; see `docs/releases/Fotty-2.0.0-35.md`.
- **Upload**: Xcode 27.0 reported `EXPORT SUCCEEDED` and `Upload succeeded` at 19:12 AST. App Store Connect completed processing. The owner saved the encryption declaration after the source/binary-based explanation; the accepted **Ready to Test** state was independently verified. The browser workflow then saved the five-task What to Test notes and assigned only Fotty Internal Smoke. At 19:21 AST the fresh builds page showed **Internal / Testing** with the expected group; its two testers and account roles remain unchanged. No rebuild or re-upload was needed. Availability is confirmed, not tester installation or feedback receipt.
- **Boundaries/resources**: No direct device install, simulator, device UI-test runner, server deployment, tester/role change, external review or Git publication. The 305 MB owned archive/build/export directory and 640 KB Xcode distribution logs were removed; 41 GiB remains free. Fresh physical TestFlight acceptance and a confirmed received feedback report remain wider-beta gates.

## 2026-08-27: Make internal TestFlight the normal update channel

- **Decision**: The owner requested uploading the UI refinements and using TestFlight instead of cable installs from now on. Use the normal `Fotty` Release app for the existing internal group; retain direct-device tools only for explicitly requested diagnostics. Do not expand testers, submit externally, or publish Git history as part of this request.
- **Preparation**: Added `ExportOptions-TestFlightInternal.plist` with automatic signing, symbol upload, internal-only distribution and automatic build-number management disabled. Replaced the stale ReviewSafe/simulator TestFlight checklist, and changed the release lifecycle to TestFlight-installed device acceptance before wider beta invitations. Apple's installed Xcode export help and official TestFlight documentation support the chosen options.
- **Current blocker**: App Store Connect opens at sign-in; no alternative connected browser is available. The owner must sign in before the latest uploaded build and existing group can be checked. No next number has been chosen, archive made or upload attempted; all UI changes remain local. Export/project plists and release-owned whitespace checks pass. No simulator, device install, signing-account change or Git operation occurred; disk remains 41 GiB free.

## 2026-08-27: Implement the approved UI refinement without changing football/FPL authorities

- **Decision**: The owner's subsequent “proceed” approves implementation of the audit priorities. Retain the amber identity, pitch and separate Home/Matchday purposes. Improve readable text, accurate labels, continuity and existing workflows rather than adding unrelated features.
- **Implementation**: FPL now has a root-owned workspace session, per-tool scroll restoration, cached refresh on return/foreground, manager-selection-safe restoration, and retained Coach draft/pending state and comparison IDs. Meaningful FPL text uses semantic sizing; long pitch names wrap and large text switches to a roster. Difficulty uses one numbered, contrast-tested palette. Plan emphasizes the next decision, uses measured-width evidence columns and groups existing Tools by purpose. Comparison has bounded player/club search; captain rank and point estimates are explicitly distinct. Home preserves unknown club identity and labels future broadcasts accurately. Matchday removes duplicated relevance and date-groups later fixtures. Settings demotes local identity, separates alert types, and gives report fields persistent required labels. Controls gain 44-point targets and shared Live Pulse respects Reduce Motion.
- **Preserved contracts**: No FPL points/transfer/ranking mathematics, official submission, provider resolution, PiP eligibility, source switching, auto-hide timing or unmute behavior was changed. The only advisor-engine change is explanatory captain copy. Explicit pull-to-refresh retains its cache-clearing semantics; ordinary FPL return uses existing TTL caches.
- **Verification**: The final unit run passes 122 tests with zero failures/runtime warnings and one opt-in HLS skip. Fourteen distinct scoped Catalyst checks pass, including all six Home accessibility scopes after fixing downloaded-badge descriptions, five other surface audits and three interaction checks. The Debug fixture now exercises a full squad, long names, five defenders, fixtures and captain cards instead of an empty Squad. Final normal iOS and Review Safe builds pass unsigned. Visual review confirmed wide Plan columns and wrapping; native Home filter styling is deliberately retained after tint/Menu experiments caused accessibility regressions. Some UI runs emitted main-thread warnings on the beta Mac. Full results and limits are in `docs/audit/Fotty-UI-Refinement-2026-08-27.md`; these checks do not certify physical devices or engagement.
- **Release/resource boundary**: This remains local and unreleased on the build-33 source baseline; no upload, physical installation or Git publication. Preserve the cleaned-history replay requirement. All configurations share one temporary DerivedData root with two jobs and cleanup; no simulator. Physical Display Zoom/keyboard/daylight/VoiceOver and upstream duplicate identity remain explicit follow-up checks.

## 2026-08-27: UI audit recommends refinement, not another feature expansion

- **Scope**: Read-only UI/UX review of current build-33 source plus the unreleased beta-usability patch. The owner requested judgment, not implementation. Recommendations are not approved design changes or new release gates.
- **Findings**: A credible closed-beta foundation, but not yet premium. Priorities are fixed 7–10-point meaningful FPL text, low-contrast fixture chips, ambiguous future-broadcast/current-gameweek labels, FPL workspace reset across main-tab changes, over-abbreviated club names, technical copy, and inconsistent tool/control hierarchy. Keep the amber identity, football pitch, distinct Home/Matchday jobs and in-app playback recovery.
- **Evidence**: Current-source Catalyst inspection covered Home, Matchday, four FPL workspaces, Transfer Lab, Captain, the pre-deadline Live Points state, Settings, Help and report preparation at narrow/expanded window sizes. Source review covered remaining tools, compact paths, onboarding, Match Center, player and system surfaces. Two Price Radar accessibility inspections stalled in hierarchy enumeration on the beta Mac; ordinary device freezing is not established. No new physical-device, provider-playback, VoiceOver or retention claim is made.
- **Artifact**: `docs/audit/Fotty-UI-UX-Audit-2026-08-27.md` separates observed/source-only evidence, priorities, screen recommendations and later tester tasks. One temporary Catalyst build succeeded; its 329 MB output and captures were removed, leaving about 42 GiB free. No app/source/version changes, deployment or Git publication occurred.

## 2026-08-27: Close newcomer dead ends before widening the internal beta

- **Decision**: Make Help and report preparation native/offline, require explicit confirmation of a looked-up FPL team, keep setup optional, and describe current capabilities honestly. Preparing or copying a report is not submission; foreground match updates are not background push; Fotty draft changes are not official FPL transactions.
- **Why**: New testers could otherwise follow a retired help URL, become stuck on an incorrect manager ID, expect unsupported alerts, or miss the distinction between Home discovery and personal Matchday.
- **Implementation**: Added official-link parsing and cancellable identity lookup; manager switching invalidates pending manager/review/league/rival/Coach work without deleting scoped drafts. Added shared native Help/report sheets with persisted drafts, build/device context and opt-in previewable diagnostics. Home tips and empty Matchday use direct root navigation callbacks, not persisted preferences as a navigation bus. Team selection has adaptive text, search cancellation and explicit recovery states. Added `docs/BETA-TESTER-GUIDE.md` and focused policy/navigation checks.
- **Interaction corrections**: Inactive tabs need an explicit rectangular content shape so the gap around their icon/label remains clickable; tabs also expose selection. Catalyst checks use native mouse clicks and assert the destination/selection. Setup-dismissal UI tests use an isolated, mutable Debug preference suite instead of an immutable launch-argument override. The report uses directly labeled headings/controls, avoiding the unlabeled native form-header and disclosure-image audit failures without suppressing app-owned accessibility issues.
- **UI verification**: All three new journeys passed on Mac Catalyst: native Help/report preparation with text-clipping/description audit, official FPL link entry without implicit connection, and Home → FPL → Home → setup dismissal. The strengthened rapid-tab/foreground test, Dashboard contrast/traits and Settings Dynamic Type checks also passed after the interaction corrections; the eleven existing release-scope accessibility audits had passed earlier in this work. One Xcode pre-test automation-mode timeout required the runner's bounded retry. Runtime main-thread/QoS warnings were still emitted on the beta Mac; this is not a zero-warning claim or fresh iPhone/iPad certification.
- **Policy verification**: Final-source Catalyst results contain 117 passing tests, zero failures and zero runtime warnings, with only the explicitly opt-in reference-HLS soak skipped. The twelve beta-usability tests cover strict parsing, retry/cancellation/stale-response isolation, confirmation separation, feedback context/opt-in, setup policy and manager-state reset boundaries.
- **Build verification**: The final-source normal signed generic-iOS Release and unsigned ReviewSafeRelease builds both succeeded. Project-plist validation, shell syntax and `git diff --check` passed. Builds ran sequentially in one reused, trap-cleaned temporary directory; no simulator, device deployment, archive, TestFlight upload or Git publication was performed.
- **Distribution boundary**: This is a local, unreleased patch. Do not infer that existing TestFlight testers have it or that build-33 hardware acceptance covers the new flows. A higher build number, fresh supported-device checks and one confirmed received TestFlight report remain the next beta-expansion gate. The old local Git ancestry remains frozen; no source publication is authorized by local implementation.

## 2026-08-26: GitHub purge closes the final Fotty 2.0 release gate
- **Decision**: Accept GitHub Support's closed-ticket response only after independent API, web, PR-ref, and fresh-clone verification. Close the repository-security gate while keeping the dirty old local branch frozen; any later source publication must repeat the proven Git-aware replay onto clean ancestry.
- **Why**: The support response is necessary server-side evidence, but the accepted contract requires independently proving that neither obsolete commit remains publicly retrievable and that the rewritten advertised history did not move unexpectedly.
- **Verification**: GitHub closed ticket `#4701297` and reported that unreferenced commits were cleared. Authenticated commit API calls now return `No commit found` for `74c8b1627d24a8b8368b903fee83f8dda94d0a61` and `82f9cc431b5d5e078dd8f4cba4285ed4dfc8e237`; both public commit pages return HTTP 404; `refs/pull/1/{head,merge}` and `refs/pull/2/{head,merge}` are absent. A new bare fetch of public heads/tags contains neither old commit nor `cert.json`. The cleaned branch heads remain `5912bee72390315de2799d51073f9e72c27b4602` and `8f67a85fe4de2ce3c8e0214f7d3738b7b7f208d8`; `main` remains `c0a7d5b0fcb0b03125721101ba979cedf51062fb`; the empty tag fingerprint is unchanged. Temporary verification directories were deleted.

## 2026-08-26: GitHub acknowledges active pull-request-reference cleanup
- **Decision**: Treat GitHub Support's acknowledgment as progress, not completion. Keep the repository-security gate open until Support reports completion and both obsolete commits fail independent API/web reachability checks.
- **Why**: The Support agent confirmed that the pull-request reference is being cleared, but both obsolete commit IDs remain retrievable at this checkpoint. Closing the gate on an email acknowledgment would weaken the accepted evidence standard.
- **Verification**: Ticket `#4701297` remains open and contains a GitHub Support reply stating that the pull-request reference is currently being cleared and a completion update will follow. Immediately afterward, both obsolete commit API queries still succeeded. The six-hour read-only monitor remains active.

## 2026-08-26: The completion authority maps all seven agreed pillars explicitly
- **Decision**: Keep the five connected user journeys as the product outcome model and define seven implementation pillars beneath them: data truth/identity, playback reliability, FPL decision system, Smart Coach, Matchday UX, native system experience, and quality/release discipline. Require the completion report to name current implementation authority and verification evidence for every pillar.
- **Why**: The source and evidence already covered the full program, but the durable Project Memory still listed four pre-2.0 strategy bullets and the report distributed evidence across journey and gate sections. A strict completion audit should not require readers to infer whether all seven agreed areas were actually delivered.
- **Verification**: The accepted contract and Project Memory now name the same seven pillars. The completion report maps each to source ownership and automated, production, Catalyst, or physical evidence. All product/device pillars are implemented and verified; only GitHub Support ticket `#4701297` and independent obsolete-commit unreachability remain open under the quality/security pillar.

## 2026-08-26: Prove the release tree can move to clean ancestry before publishing it
- **Decision**: Do not merge, rebase, reset, or push the dirty old local feature branch. Prove the migration using a disposable detached worktree based on the cleaned remote branch, a binary tracked-tree delta, and only Git-visible untracked files. Remove that worktree after validation and repeat the same boundary only when the Support purge is complete and the clean-ancestry release commit is ready to be created.
- **Why**: The current 373-path working copy contains the complete Fotty 2.0 program but its local HEAD predates the sensitive-history rewrite. Pushing or merging it could reintroduce the dead credential's ancestry, while copying the whole directory could include ignored build output or secrets. A Git-aware replay preserves the intended source tree without either risk.
- **Verification**: The clean branch differs from the old local HEAD only by deletion of `cert.json`. The temporary replay reproduced 310 tracked changes and 120 Git-visible untracked files; sorted path manifests matched, every changed/untracked file matched byte-for-byte, `cert.json` was absent, and `git diff --check` passed. Cleanup left zero replay directories and preserved the active branch, local HEAD `3855bd53c9dfc543832333924ee21db2175f11bc`, and 373-path dirty status.

## 2026-08-26: GitHub Support ticket 4701297 requests the retained-object purge
- **Decision**: Submit the prepared sensitive-data cleanup request through the authenticated GitHub Support repository route. Categorize it as a repository branch/history problem, not repository deletion, and include no credential value or attachment.
- **Why**: Repository owners can rewrite advertised branches but GitHub's `refs/pull/*` are read-only. The obsolete commits remain publicly retrievable through PR heads and cached objects even though the credential is revoked and fresh public branch/tag history is clean.
- **Verification**: GitHub displayed “Your message has been successfully submitted,” and the authenticated ticket list shows open ticket `#4701297`, “Purge sensitive-data commits retained by closed PR refs,” created 2026-08-26 for `jetboss`. The request includes repository name, two affected PRs, both first-changed commits, clean replacement heads, unchanged `main`/tags, and no-LFS confirmation. The 2.0 gate remains open until GitHub completes the purge and both obsolete commits are independently unreachable.

## 2026-08-26: Advertised branches are clean; GitHub retained-object purge remains
- **Decision**: With explicit owner authorization, close pull requests 1 and 2, rewrite `cert.json` from a disposable mirror, and atomically force-update only the two affected advertised branches. Preserve `main`, tags, and the 373-path dirty release checkout. Do not close the Fotty 2.0 security gate until GitHub purges the obsolete closed-PR/cache objects and both old commits are independently unreachable.
- **Why**: Fresh mirror inspection expanded the original one-branch assumption to two independent first-changed commits and six changed refs: two branch heads plus head/merge refs for PRs 1 and 2. Branch owners can clean the advertised heads but cannot force-update GitHub's retained pull-request refs. Rewriting the active dirty checkout would risk release work, while a mirror-wide push would move refs outside the inspected scope.
- **Verification**: `git-filter-repo` 2.47.0 deterministically produced branch heads `5912bee72390315de2799d51073f9e72c27b4602` and `8f67a85fe4de2ce3c8e0214f7d3738b7b7f208d8`; GitHub accepted both in one atomic forced update. A new bare fetch of public heads/tags cannot reach `cert.json`; `main` remains `c0a7d5b0fcb0b03125721101ba979cedf51062fb` and the empty tag fingerprint is unchanged. GitHub still returns obsolete commits `74c8b1627d24a8b8368b903fee83f8dda94d0a61` and `82f9cc431b5d5e078dd8f4cba4285ed4dfc8e237`, and the closed PR records still identify their old heads. The local branch, local HEAD, and dirty-path count were identical before and after refreshing only the two remote-tracking refs; all disposable directories were removed.

## 2026-08-26: Owner confirmation closes the two physical interaction gates
- **Decision**: Accept the product owner's direct hardware confirmation that large-text interaction works on both the supported iPhone and iPad and that the real alert/Live-Activity interaction returned to the correct match/player. Keep the automated Catalyst evidence and typed routing tests as supporting coverage, not substitutes for this confirmation.
- **Why**: CoreDevice can launch and observe the normal process but cannot change Dynamic Type or tap system-owned notification and Live Activity surfaces. Those two gates deliberately required a person's direct interaction, and the owner has now supplied it.
- **Verification**: In response to the explicit two-item confirmation—large text on both devices, and notification/Live-Activity tap opening the correct destination—the owner answered “yes for both.” The product contract, QA playbook, Roadmap, Risks, Project Memory, and completion report now mark physical interaction acceptance complete. The only remaining Fotty 2.0 gate is removal of the already-revoked tunnel credential from the affected public Git history.

## 2026-08-26: Delete every retired Cloudflare Tunnel and close credential revocation
- **Decision**: With explicit owner authorization, delete every Cloudflare Tunnel because the homelab no longer exists. Do not touch Cloudflare Workers, zones, domains, or DNS records. Treat credential revocation as complete only after the historical `cert.json` Tunnel ID matches the deleted object and every accessible account reports zero active tunnels; keep public Git-history removal as a separate gate.
- **Why**: The exposed JSON credential was tunnel-specific and non-expiring. Deleting the file from the working tree could not invalidate historical copies, while creating a replacement tunnel would serve no purpose for a retired homelab. The active Fotty playback and Coach edge service is a Worker and does not depend on the tunnel.
- **Verification**: The authenticated Cloudflare API enumerated four accounts and found one non-deleted tunnel, the already-down `manga-api`. Deletion succeeded at 2026-08-26T13:33:04Z; all four accounts then reported zero active tunnels. A field-limited comparison confirmed that commit `82f9cc4`'s `cert.json` names the deleted Tunnel ID without printing its secret. `https://fotty-playback-v3.adaptive-rhubarb.workers.dev/[URL_REDACTED] remained HTTP 200. The dead credential is still reachable on the local/remote feature branch and stash, so fresh-clone GitHub history cleanup remains open.

## 2026-08-26: Exact build 33 survives the normal-app physical launch gate
- **Decision**: Accept one bounded 60-second normal-app foreground hold on each authorized physical device as exact-candidate process-survival evidence. Do not interpret a CoreDevice process poll as proof of large-Dynamic-Type interaction, alert/Live-Activity return, or active-stream playback.
- **Why**: Build 33 had been strictly verified and installed while the devices were locked, so its launch state remained behind older interaction evidence. Once both devices were naturally unlocked, the existing physical-only runner could close that narrow gap without a rebuild, simulator, synthetic touch, screenshot, or UI-test runner.
- **Verification**: `com.jelani.Fotty` `2.0.0 (33)` launched and remained present through 60-second holds on the authorized iPhone 15 Pro Max and iPad Air. A post-run app inventory showed only the normal Fotty app on each device; no Xcode/UI-test process or Fotty temporary path remained, and the workstation retained 53 GiB free. The completion authority exposes exactly three open gates: direct physical large Dynamic Type, real alert/Live-Activity return, and removal of the now-revoked tunnel credential from affected public Git history.

## 2026-08-26: The completion authority exposes exactly three open gates
- **Decision**: Keep the accepted 2.0 product scope intact while making its Definition of Done match the evidence: active playback controls/lifecycle acceptance is complete; direct physical large Dynamic Type, a real alert/Live Activity return, and tunnel-credential history cleanup remain open. The contract now identifies `1.8.4 (11)` as its starting baseline and `2.0.0 (33)` as the current candidate.
- **Why**: One bundled manual checkbox obscured that every playback item except the system-return interaction had already passed, while the later-discovered repository credential exposure was absent from the accepted completion authority. A completion audit must neither hide completed evidence nor omit a blocking release requirement.
- **Verification**: The product contract, QA playbook, Roadmap, Risks, Project Memory, and completion report all identify the same build-33 candidate and the same three remaining physical/security gates. The completion report retains granular passed evidence for playback, FPL, widget, accessibility, builds, analysis, and exact-device installation.

## 2026-08-26: The generated brain bundle uses the canonical build-33 QA playbook
- **Decision**: `tools/notebooklm-refresh.sh` now embeds `docs/notebooklm/QA-Playbook.md`; the obsolete `Fotty-QA-Playbook.md` is no longer a generated-bundle source. NotebookLM guidance points first to the generated master source and names only canonical focused files.
- **Why**: The refresh completed successfully but silently embedded a May 7 P2P-era checklist instead of the current no-simulator build-33 release checklist. That made a green memory refresh an unreliable proof that agents would receive current QA constraints.
- **Verification**: Shell syntax and `git diff --check` pass. Regenerating the bundle includes the 2026-08-26 playbook, the exact build-33 aggregate result, and the remaining direct physical procedure; the obsolete May QA header and P2P source-switching script are absent from the generated QA section.

## 2026-08-26: Build 33 closes the aggregate Catalyst gate
- **Decision**: Accept the exact build-33 Mac Catalyst release gate as complete after one invocation passed all eleven accessibility audits plus rapid navigation/foreground recovery. Keep physical large-Type, notification/Live Activity return, and credential-remediation gates separate; Catalyst evidence does not waive them.
- **Why**: The first aggregate attempt correctly stopped at the lock guard. Once the Mac was naturally unlocked, the full candidate needed one uninterrupted run to prove the individually green audits also coexist under the release runner without cross-test state leakage.
- **Verification**: `tools/catalyst-ui-release-gate.sh` ran sequentially with two Xcode jobs and no simulator. Hit regions, text clipping, descriptions, Dashboard/FPL/Matchday/Settings/Match Center/Player Dynamic Type, contrast/traits, element detection, and rapid tab/foreground recovery all passed with no retry. The cleanup trap removed the owned `/private/tmp/FottyCatalystUIReleaseGate.*` DerivedData root; zero Fotty temporary targets and zero Xcode/test processes remained afterward.

## 2026-08-25: Contain the tunnel-credential cleanup to the affected branch
- **Decision**: Treat `cert.json` as a tunnel-specific, locally managed Cloudflare credential that must be replaced/revoked before release. `origin/main` and tags are clean; commit `82f9cc4` and `origin/cursor/docs-world-cup-readiness-audit` are the identified advertised-history exposure. Perform GitHub's sensitive-data rewrite from a fresh disposable clone only after owner approval and Cloudflare revocation; never run `git-filter-repo` in the 371-change release working copy.
- **Why**: Deleting and ignoring the file protects future commits but does not invalidate a non-expiring tunnel credential or remove cached Git history. A repository-wide rewrite without first proving the ref footprint would create unnecessary risk, while rewriting the dirty active checkout could lose or contaminate the release work.
- **Verification**: `git for-each-ref --contains=82f9cc4` resolves only the local/remote feature branch; `origin/main` is an ancestor of the current branch and does not contain the exposure commit; scanning every `origin/*` tree finds `cert.json` only on that branch. The redaction, Cloudflare replacement/revocation, fresh-clone `git-filter-repo`, changed-ref review, GitHub Support cleanup, and collaborator-reclone sequence is recorded in `docs/RELEASE-PROCESS.md` without exposing a credential value.

## 2026-08-25: Build 33 covers every named surface at large Type
- **Decision**: Advance to `2.0.0 (33)` and add explicit Debug-only, network-free presentation routes for catalog Match Center and the truthful no-source Player recovery state. Direct-launch Matchday and Settings audits join the existing Home and four-workspace FPL coverage. Preserve a loaded catalog-only Match Center on resume instead of starting an unnecessary repository refresh.
- **Why**: The physical devices and later the Mac were passcode-locked while the owner slept. The release contract still called for large-Type review of every named surface. Deterministic Debug presentation routes provide repeatable layout evidence without a simulator, provider request, manager account, synthetic device touch, or physical UI-test runner, while Release builds exclude the routes.
- **Verification**: Matchday, Settings, Match Center, and Player Dynamic Type audits pass against the build-33 source before the build-number-only advance; Home and FPL had already passed, so all eleven constituent accessibility audits now have green evidence. The complete exact build-33 Swift suite, normal and Review Safe Release, and generic-iOS analyzer pass. One strictly seal-verified signed artifact installed on both authorized locked devices and each independently reports `2.0.0 (33)`; no UI-test runner is installed. The guarded one-shot eleven-audit-plus-rapid-navigation runner correctly refused to bypass the locked Mac and remains the only automated rerun pending unlock.

## 2026-08-25: Build 32 makes FPL large-Type coverage deterministic
- **Decision**: Advance to `2.0.0 (32)` and add an explicit `FOTTY_FPL_UI_TESTING=1` fixture that exists only in Debug. Launch Plan, Squad, Coach, and Tools directly through the allowlisted Debug workspace route for Catalyst accessibility audits instead of relying on Xcode 27 beta's unreliable synthesized workspace taps. The fixture supplies shell state and a structured Coach response without a manager account, network request, or persisted chat.
- **Why**: The final autonomous review needed evidence across every FPL workspace while both physical devices were passcode-locked. A clean Catalyst test container correctly stopped at Manager ID onboarding, and synthesized SwiftUI workspace taps did not change the visible workspace on this beta toolchain. Neither condition was a product defect, but allowing them to skip FPL layout coverage would leave the large-Type claim unproven.
- **Verification**: Exact build 32 passes the complete Swift suite, normal and Review Safe generic-iOS Release builds, generic-iOS static analysis, seven Catalyst accessibility audits, and rapid-navigation/foreground recovery. The FPL audit covers Plan, Squad, Coach, and Tools and requires both the Coach quick-prompt control and a structured response. A separate source contract proves quick prompts clear focus through the shared send path before adding a message. One strictly seal-verified signed artifact installed successfully while both devices were locked, and each independently reports `2.0.0 (32)`; no UI-test runner is installed. The install was intentionally not followed by an overnight device launch.

## 2026-08-25: Build 31 makes the small deadline widget's source visible
- **Decision**: Advance to `2.0.0 (31)` and show the deadline entry's source label directly in the small widget, matching the medium presentation. Retain the typed `fotty://fpl` route and small/medium family boundary.
- **Why**: The final native-system audit found that `Official FPL` was visible in the medium widget and available in the small widget's accessibility summary, but not visually present in the small widget. The accepted contract requires both sizes to show deadline and source; accessibility-only text did not satisfy that promise.
- **Verification**: A regression source contract proves both supported families, the small-family source label, and the typed FPL route. The complete Swift suite, normal and Review Safe Release, generic-iOS static analysis, and all six Catalyst accessibility audits plus rapid-navigation/foreground recovery pass. One strictly verified signed artifact is installed on both authorized devices, and each independently reports `2.0.0 (31)`. The owner confirmed the physical small/medium widget presentation and FPL tap route work.

## 2026-08-25: Builds 29–30 close the final Dashboard audit and reject a provider VPN solicitation
- **Decision**: Advance to `2.0.0 (29)` after the exact Catalyst contrast audit found the Home empty-feed recovery text too muted and its Refresh action insufficiently contrasted, then to `2.0.0 (30)` after build-29 hardware playback exposed a provider-origin `VPN Recommended / Tap to Install and Continue Watching` solicitation. The empty state is now an explicit high-contrast recovery card. WebKit suppresses only the matched VPN/install/continue-watching alert or text ancestor, and refuses to remove any candidate that owns video, owns an iframe, or is effectively the player/root surface.
- **Why**: Recovery guidance must remain legible and actionable, while a fake install prompt over a healthy broadcast is both a usability and trust failure. A generic overlay/ad remover would risk destroying the player or the provider's legitimate unmute control, so the nuisance rule is deliberately semantic and narrow.
- **Verification**: Build 29 passed all six Catalyst accessibility audits plus rapid-navigation/foreground recovery. Build 30 passes the complete Swift policy suite, the injected-script JavaScript parse contract, normal and Review Safe iOS Release, and generic-iOS static analysis. The same signed normal artifact is installed on both authorized devices and each independently reports `2.0.0 (30)`. Broadcast 1 decoded and visibly advanced on both without changing source or showing the VPN solicitation; the iPad still displayed the provider-owned `CLICK UNMUTE STREAM` control, proving the filter did not blanket-remove the player prompt. The owner directly confirmed iPad unmute and Pause, a later capture proved Play/resume on the same source, and the owner reported no ticking or duplicate/overlapping audio.

## 2026-08-25: Builds 27–28 make zero-variant playback and catalog timing truthful
- **Decision**: Advance to `2.0.0 (27)` to reject fabricated canonical Echo/Admin URLs and derive `UPCOMING`, `LIVE`, or `AVAILABLE` from kickoff time, then to `2.0.0 (28)` so only the live state says `Watch live`; upcoming and stale/undated entries say `Open broadcast`. Canonical zero-variant synthesis is limited to the provider contracts Fotty actually knows: Hotel, Delta, Golf, and India.
- **Why**: A stale LASK–Celtic Echo entry supplied no variants, yet build 26 invented an `/1` URL, waited roughly 40 seconds on an upstream 404, and labeled the old event live. That was app-created failure and false product copy, not provider unreliability.
- **Verification**: Timing/action and fallback-whitelist regressions pass inside the complete build-28 Swift suite. Normal and Review Safe iOS Release, generic-iOS static analysis, strict deep signature verification, version checks, and exact-artifact installation pass. Both physical devices independently report `2.0.0 (28)`. The stale Echo event now immediately exposes no playable source and says `AVAILABLE · Open broadcast`. A current three-source event decoded and advanced on both devices for more than 60 seconds with no source change; background/foreground preserved Broadcast 1, iPad entered real PiP after native handoff, and termination removed the PiP surface. Manual tap-to-reveal/Pause/Play and audible duplicate/ticking checks remain open; the three remaining Catalyst UI checks are recorded, not waived.

## 2026-08-25: Builds 23–26 close compact density, cold provider routing, and web-player truth
- **Decision**: Advance monotonically through `2.0.0 (23)`–`(26)` as each installed predecessor exposed a distinct physical acceptance defect. Build 23 makes the complete starting XI fit the iPhone Zoomed/Larger Text canvas without scaling the whole UI. Build 24 resolves exact provider catalog route IDs and presents a truthful broadcast-only Match Center after a cold deep link. Build 25 supplies explicit web Play/Pause when a provider renders none and requires kickoff identity before showing a same-team score. Build 26 moves the compact fallback controls to the video edge, fades them after four seconds, and restores them through a non-cancelling surface tap.
- **Why**: Physical evidence showed a 1125×2436 Zoomed canvas, a dead provider-only Match Center, decoded video/audio with no usable transport control, an older Premier League `FT 0–1` leaking into a current cup feed showing `0–2`, and then oversized permanent controls centered over the match. These are product-truth and usability failures that compile-only review cannot reveal.
- **Verification**: Focused regressions cover compact lens labeling, exact catalog identity/fallback, explicit web transport commands, bounded auto-hide, and kickoff acceptance/rejection. Build 26 passes the full Swift suite, both iOS Release configurations, and static analysis. One signed universal normal artifact is installed and version-reported as `2.0.0 (26)` on the physical iPhone and iPad. The prior build physically decoded the current provider with working audio and no premature source change; build-26 control fade/tap/pause/resume awaits reconnection. Four exact-source Catalyst audits pass; the fifth failed once and its rerun was killed before test connection, leaving three UI checks open.

## 2026-08-25: Release evidence cannot consume the workstation
- **Decision**: On the 256 GB/8 GB development Mac, every broad Xcode gate must reuse one DerivedData root and remove owned temporary output on success, failure, or interruption. No simulator is allowed. Explicit caller-provided cache paths are the only retained-cache escape hatch.
- **Why**: Per-build/per-configuration directories accumulated 40 GB under `/private/tmp` (32 GB created the same day) plus Fotty DerivedData, leaving 3.7 GB free. Verification artifacts have no value after their result is recorded and the exact app is installed.
- **Verification**: The generated Fotty directories, DerivedData, and temporary screenshots were removed, restoring 43 GB free. Root agent instructions now encode the workstation limits. `ios-device-qa.sh` and `catalyst-ui-release-gate.sh` use validated cleanup traps; shell syntax, a help-path cleanup smoke, diff hygiene, and a zero-leftover-directory check pass.

## 2026-08-25: Build 22 routes the normal Debug app for physical visual QA
- **Decision**: Advance to `2.0.0 (22)` and add one bounded Debug-only `--fotty-fpl-workspace` argument that initializes Plan, Squad, Coach, or Tools. Keep Release behavior unchanged. Use CoreDevice to launch the signed normal app with the argument and `fotty://fpl`; never install a physical-device UI-test runner or claim that routing proves keyboard/audio/control interaction.
- **Why**: The device screens repeatedly auto-locked while waiting for manual taps, leaving the build-21 compact Squad correction physically uncaptured. A normal-app route makes form-factor evidence repeatable in the narrow unlocked window without synthetic touch automation and remains useful for future physical visual regression checks.
- **Verification**: The allowlisted parser accepts separate and inline arguments, maps Plan/Gameweek, Squad, Coach, and Tools, and rejects unknown values in a focused regression. Build 22 passes 94 Swift tests plus one intentional soak skip with zero failures/runtime warnings, signed/strictly verified Debug and Release builds, Review Safe compile, generic iOS static analysis, all six Catalyst accessibility audits, and rapid-navigation/foreground recovery. A fresh Catalyst runner timed out before testing; the already-authorized release runner then executed the exact build-22 source at 7/7. The same verified Debug artifact is installed and version-reported as `2.0.0 (22)` on both devices. Physical build-22 holds and routed captures await unlock.

## 2026-08-25: Builds 18–21 turn two-device visual review into release evidence
- **Decision**: Advance monotonically through builds 18–21 as each predecessor reached hardware and revealed a distinct truthful-copy or form-factor defect. Build 18 replaced substring score-coverage matching with an explicit senior Premier League/Champions League allowlist. Build 19 then removed the remaining team-name league guess when no schedule fixture confirms score coverage. Build 20 distributes the three FPL command-centre metrics across the regular-width row. Build 21 contains compact Squad player cards and formation spacing so a five-player line cannot expand the whole iPhone workspace.
- **Why**: The physical iPad first showed `LIVE · SCORE UNAVAILABLE` for Blackpool–Aston Villa U21, then proved the first policy fix was insufficient because the hero fell back to team-name inference. Later iPad Plan review showed `Current squad` clipped inside three narrow adaptive metric columns despite abundant width. The build-20 iPhone Squad capture showed fixed 76-point cards pushing the shared header and controls beyond both screen edges. None of these defects was acceptable as a daily-use interface, and replacing an already installed build number would destroy traceability.
- **Verification**: Build 21 passes 93 Swift tests plus one intentional live-soak skip with zero failures/runtime warnings, 68/68 web/Worker tests, zero-error lint, optimized Next build, signed Debug/Release, compile-only Review Safe, generic iOS static analysis, shell/plist/whitespace checks, and all six Catalyst accessibility audits plus rapid navigation. A clean universal Debug artifact passes strict deep signature verification and reports `2.0.0 (21)` in the app and extension; that same artifact is installed and version-reported on both physical devices. The exact artifact passes the 60-second iPad hold, while the final iPhone hold awaits unlock. Build-19 Home and build-20/21 Plan captures verify the score-copy and regular-width metric corrections; final build-21 physical Squad/Coach/widget/playback interaction remains authoritative. No simulator or physical-device UI-test runner was used.

## 2026-08-25: Build 17 makes the exhausted-startup boundary truthful
- **Decision**: Advance the candidate to `2.0.0 (17)` rather than replace build 16 after its physical iPhone playback trace exposed an app-owned diagnostics defect. When a non-explicit child-frame provider error is deliberately deferred through the complete startup window and no decoded progress appears, classify the terminal boundary as `Startup timeout: no decoded video within 20 seconds`. Preserve explicit provider-rejection reasons unchanged.
- **Why**: The Abha–Al-Khaleej physical session recorded two same-source attempts about 21 seconds apart, zero decoded starts, zero automatic failovers, and a terminal failure after the second full window. Fotty correctly protected the selected source and the provider failed to decode, but the exported `unknown` failure and generic terminal presentation did not tell the user or operator what had actually happened.
- **Verification**: A focused regression proves opaque deferred failures become `.startupTimeout`, include the 20-second boundary, and leave explicit provider-unavailable signals untouched. The complete no-simulator Swift result is 92 passed, one intentional soak skipped, zero failed, and zero runtime warnings. Signed Debug and optimized Release, compile-only Review Safe Release, generic iOS static analysis, all six Catalyst accessibility audits, rapid-navigation/foreground recovery, 68/68 web/Worker tests, zero-error ESLint, the optimized Next build, version/signature/plist/shell/whitespace checks, empty client API-key fields, and build-bundle credential scans all pass. The signed normal build 17 is installed and independently version-verified on the physical iPhone; it locked before the 60-second hold. The iPad install hit a CoreDevice tunnel timeout and then became unavailable. No simulator or physical-device UI-test runner was used, and final physical interaction remains authoritative.

## 2026-08-25: Build 16 closes two defects found only in the physical compact Home audit
- **Decision**: Advance the integrated candidate to `2.0.0 (16)` rather than replace distributed build 15. Offer MultiView only when at least two otherwise-eligible events are live or within 30 minutes of kickoff; catalog source presence and historical provider success cannot make a broadcast watchable hours early. Preserve recognizable dense club labels with explicit common-name mappings instead of ambiguous first-letter forms.
- **Why**: The physical iPhone Home capture showed a visible `Watch 2` action while its candidate rows were about two hours away, plus `L. City` for Leicester City. Both controls technically rendered and passed automated accessibility checks, but one could not yet deliver its promise and the other forced the user to decode an ambiguous abbreviation.
- **Verification**: Focused timing/name regressions pass, followed by the complete build-16 Swift gate at 91 passes plus one intentional live-soak skip, zero failures, and zero runtime warnings. Signed Debug, signed optimized Release, compile-only Review Safe Release, and generic iOS static analysis pass. All six individual Catalyst accessibility audits plus rapid-navigation/foreground recovery pass on the exact build-16 source. The signed normal artifact installed on both physical devices. CoreDevice independently confirms `2.0.0 (16)` on the iPad; that app survived a complete 60-second foreground hold, and physical Home/FPL captures verified the corrected 64 total, readable `Sheff Wed`, hidden premature MultiView, and no clipping or dock overlap. CoreDevice has also independently re-verified `2.0.0 (16)` on the connected but passcode-locked iPhone, where the final launch hold remains pending. Two current `echo` candidates returned media HTTP 500; the next event's two `admin` broadcasts passed a kickoff-aligned 45-second hold with about 45.3/43.0 seconds of advancement, longest pauses of 0/about 2.0 seconds, HTTP 200 media, zero popup, and zero request failure, establishing a current hardware target. Physical controls remain pending. No simulator or physical-device UI-test runner was used.

## 2026-08-25: Build 15 closes the Mac release gate; physical interaction remains authoritative
- **Decision**: Advance the integrated candidate to `2.0.0 (15)` for the final Dashboard/FPL accessibility corrections. Keep the release status at candidate until the exact normal app passes launch, compact/regular form-factor, provider-control, audio, PiP/Live Activity, notification, and teardown checks on the supported physical iPhone and iPad.
- **Accessibility boundary**: Custom sport and competition menus expose native Picker semantics and selected values; FPL loading copy is one useful announcement; match rows expose complete team labels while decorative crest initials are hidden from assistive technology. Audit handlers stay category-specific so a text-clipping run cannot be failed by a contrast finding, while every category retains its own strict gate.
- **Verification**: The complete build-15 Swift suite passes 90 tests with one intentional live-soak skip, zero failures, and zero runtime warnings. Web/Worker tests pass 68/68; ESLint has zero errors; Next/TypeScript, Debug, optimized Release, Review Safe Release, generic iOS static analysis, project parsing, plist validation, shell/Node syntax, and whitespace checks pass. On an unlocked Mac, all six individual accessibility audits plus rapid-navigation/foreground recovery pass (7/7). The macOS 27 beta accessibility warning is platform-owned and adjacent to missing Apple accessibility support bundles, with no Fotty frame. The exact normal `2.0.0 (15)` app is installed and CoreDevice-version-verified on both physical devices with no Fotty UI-test runner. The iPhone app passed the 60-second foreground process hold; physical captures verify compact Home, visible FPL deep-link routing, an unclipped Plan workspace, and the corrected on-device 64-point total. Squad/Coach keyboard/widget/large-Type, iPad launch, and physical playback remain. No simulator was used.

## 2026-08-25: Build 14 closes native lifecycle gaps without claiming physical acceptance
- **Decision**: Advance the integrated candidate from `2.0.0 (12)` through builds 13 and 14 because each predecessor had already reached the physical iPad before the next lifecycle correction. Keep the release status at candidate until the supported iPhone/iPad and unlocked-Mac gates actually pass.
- **Playback lifecycle**: Standard provider controls remain provider-owned in the foreground. When Fotty backgrounds, the injected monitor suspends reachable video/audio across the provider frame tree and resumes the same attempt on return, eliminating hidden provider/ad audio without treating the lifecycle transition as a source failure. The system toggle-play/pause command now dispatches a real toggle and remote commands are disabled during teardown.
- **Live Activity return**: A Live Activity is created only after AVKit confirms PiP is actually active, never merely because PiP is supported or a generic inactive scene transition occurred. Stop, failure, or availability loss clears the continuity state and pauses native playback if already backgrounded. A `fotty://live/<match>` link reveals the matching player when that player still exists; after process termination, it opens the matching Match Center instead of merely returning to an unrelated tab. A cold app launch still ends orphaned activities; Fotty does not claim that it can observe the instant iOS force-terminates its process.
- **Provider evidence**: The corrected decoded matrix now supports an optional post-start continuity hold. Both numbered feeds in the current playable family decoded and passed a 45-second hold with HTTP 200 media, no request failures, no popups, and no freeze of ten seconds or longer. This satisfies the independent provider/short-continuity gate but not physical controls, audible unmute, native/PiP, interruption, or teardown.
- **Verification**: The injected JavaScript parses under JavaScriptCore, focused lifecycle regressions pass, and the complete no-simulator Swift suite passes 90 tests with one intentional live-soak skip, zero failures, and zero runtime warnings. Normal Debug, optimized Release, Review Safe Release, and static analysis pass for build 14. The signed normal app is installed and CoreDevice-version-verified as `2.0.0 (14)` on the physical iPad; launch remains pending because the iPad and Mac are locked, and the iPhone is unavailable. No simulator or device UI-test runner was used.

## 2026-08-24: FPL scoring is deterministic and cannot be overruled by DeepSeek
- **Decision**: Ship the client correction as `1.8.4 (11)` and deploy the Worker guardrail immediately. Questions about current points, bench replacements, or automatic substitutions bypass DeepSeek after the Worker refreshes official manager picks, event-live stats, fixtures, and bootstrap player positions. The same deterministic resolver drives the iOS Live Points total and local Coach fallback.
- **Rules boundary**: Preserve the official current total as one fact. A different projected total is allowed only when a starter has no appearance and every gameweek fixture for that player is complete, the bench replacement appeared, goalkeeper replacement is goalkeeper-only, outfield bench order produces a legal 3–5 defender / 2–5 midfielder / 1–3 forward formation, captain-to-vice fallback is handled, and transfer cost is deducted. Name every projected replacement and label the result provisional until official `automatic_subs` or a completed data check arrives. LiveFPL is a useful behavior and presentation benchmark—especially its before/after-autosubs split—but is not a Fotty data dependency; Fotty resolves the same class of result from official FPL endpoints.
- **Why**: The previous packet exposed raw official picks and live stats to DeepSeek but did not provide an authoritative computed scoring block. The model could therefore misread a temporarily unprocessed official total as final and contradict valid pending automatic substitutions.
- **Verification**: Swift regression tests reproduce official 50 plus a seven-point bench goalkeeper and seven-point bench defender replacing two completed-fixture non-appearances, yielding a provisional 64. Another proves an earlier midfielder is skipped when a defender is required for legal formation, and final-state tests prevent Fotty from overriding a data-checked official total. Twenty focused FPL tests and five Worker scoring tests pass. Production version `c0a480d9-d966-4926-8931-bb74beebae73` returned an official scoring answer from `Fotty FPL Rules Engine` with zero prompt, completion, and reasoning tokens. The full web suite has 54 passes and one unrelated existing static-route assertion failure. The signed `1.8.4 (11)` app installed and launched on the physical iPad; the iPhone remained unavailable to CoreDevice, so its build 11 installation is pending.

## 2026-08-24: Compact iPhone FPL and Coach keyboard correction
- **Decision**: Ship `1.8.3 (10)` as a focused daily-use correction. Compact-width FPL reduces shell insets, header height, workspace-bar height, grid size, and obsolete bottom reservations; Smart Coach removes its duplicate title in the compact shell. The layout remains semantic and adaptive rather than applying a global scale transform or clamping Dynamic Type.
- **Keyboard behavior**: Smart Coach owns its composer focus explicitly. Send, Return, and quick prompts resign focus before starting a request, and the message list supports interactive keyboard dismissal, so the first response is not left hidden behind the keyboard.
- **Why**: Physical iPhone use showed that desktop/iPad spacing made the FPL workspace feel zoomed in and that clearing the first question did not resign the text field. The global tab shell deliberately ignores the keyboard safe area, so a targeted focus lifecycle fixes Coach without changing keyboard behavior across unrelated tabs.
- **Verification**: Debug Mac Catalyst and generic physical-iOS builds pass, as does the focused 17-test FPL suite. Current official FPL data rendered without clipping in a narrow Catalyst window. The paired iPhone remained unavailable to CoreDevice at deployment time, so physical installation and the final send/reply interaction remain an explicit acceptance check. No simulator or UI-test helper was used.

## 2026-08-24: FPL becomes a decision workflow, not a collection of tools
- **Decision**: Ship the next five FPL improvements together as `1.8.2 (9)`: a Rival Race Centre, structured Smart Coach cards, Transfer Lab route comparison, a manager-scoped Decision Journal, and a minimal FPL deadline widget with accessibility/presentation cleanup. Keep the product boundary honest: rival squads appear only after publication, transfer changes remain local drafts, journal content stays on-device, modeled gains remain labeled, and the widget has no manager identity or live-score claim.
- **Why**: The existing engines already had useful official facts and calculations, but the UI flattened explanations, hid tradeoffs, and scattered related actions. The useful next level is a repeatable loop—compare the race, review evidence, choose and validate a route, record the reasoning, then review the outcome—without pretending Fotty can write to the official account or see private rivals.
- **Smart Coach boundary**: DeepSeek remains the opt-in remote reasoning layer through the production Worker; it was not removed. The client now preserves the validated structured response as recommendation, confidence, evidence, downside/limits, verify-before-deadline checks, source/model, and official-data freshness. The deterministic local fallback maps into the same presentation and legacy unstructured history remains decodable.
- **System/data boundary**: Rival Race uses the already-loaded official standings, published picks, current fixtures, and event-live snapshot; it does not invent effective ownership, live overall rank, or private pre-deadline squads. The WidgetKit extension refreshes the minimal public bootstrap contract on a system-managed timeline no more often than hourly and deep-links to the FPL tab.
- **Verification**: Debug Mac Catalyst and generic physical-iOS builds compile with the widget embedded. The focused no-simulator FPL suite passes, including new journal isolation/update, legacy coach-history, Transfer Lab route-check, and Rival Race official-data regressions; the full unit-only Catalyst gate passes 57 tests with the intentional playback soak skipped. The signed app and embedded extension both report `1.8.2 (9)`. That exact normal app is installed on the physical iPad and iPhone 15 Pro Max and launched successfully on the iPhone; CoreDevice could not launch it on the iPad only because the iPad remained locked. Mac Catalyst loaded current official FPL data, displayed the new Tools grid and Transfer Lab, and accepted the `fotty://fpl` deep link. No simulator or UI-test helper was used.

## 2026-08-24: Matchday OS begins with one shared FPL match context
- **Decision**: Rename the consumer tab from `Matches` to `Matchday` while retaining its legacy persisted raw value, make the FPL primary workspace read `Plan`, `Live`, or `Review` from the verified gameweek phase, and publish one expiring device-local squad snapshot after the existing FPL workspace loads. Home cards, Matchday, and Match Center may read that snapshot but may not create another FPL network owner.
- **Why**: Football discovery and FPL planning should reinforce each other. A user should immediately see why a fixture matters to their squad, while the app avoids hidden polling, duplicate requests, and claims that a local draft is an official FPL submission.
- **Product behavior**: Relevant cards show starter/bench/captain involvement; FPL-related fixtures automatically join My Matchday; Match Center exposes an FPL Match Lens with captain/vice-captain, lineup role, and official live points/minutes when those facts were already fetched. The context clears on manager removal/change and expires after 21 days.
- **Verification**: The no-simulator Debug Catalyst build passed. The unit-only Catalyst gate passed 53 active tests with one intentional soak skipped; a final focused run passed all 13 FPL tests, including deterministic planning metrics, persisted squad-to-team matching, manager clearing, and expiry. Build 7 was installed during verification, then the Matchday header audit caught stale two-source copy; professional monotonic versioning advanced the corrected artifact to `1.8.1 (8)`. The signed app and Live Activity extension both report build 8, and that exact app installed and launched on the physical iPad. The cabled iPhone remained unavailable to CoreDevice's trusted-connectivity service. The beta Xcode optimized Release compiler remained active without a source diagnostic for more than 12 minutes and was deliberately stopped, including its child frontend, to avoid monopolizing the Mac. No simulator or UI-test helper was used.

## 2026-08-24: 1.7.2 separates Home scheduling from My Matchday history
- **Decision**: Home `Match schedule` shows only live and upcoming fixtures. Finished catalog events are filtered from Home as soon as official status reports completion or the bounded no-score kickoff heuristic proves the match is over. The shared 36-hour retention remains intact so saved or followed fixtures can appear under `Matches → My Matchday → Recent` with final context.
- **Why**: Retention and presentation had been conflated. Finished matches were ranked last but still appeared beneath a schedule heading, making completed content look upcoming and weakening the distinction between broad Home discovery and personal matchday history.
- **Verification**: Added a policy test proving a four-hour-old completed fixture still passes catalog retention but is excluded from Home while in-play and upcoming fixtures remain. The focused no-simulator Catalyst policy gate passed 33 active tests, and the full unit-only gate passed 51 active tests with the intentional soak skipped. Version advanced to `1.7.2 (6)`; the signed main app and Live Activity extension both report that version, but both physical devices were unavailable to CoreDevice for installation.

## 2026-08-24: 1.7.1 restores provider-owned web controls
- **Decision**: In the standard live player, the WKWebView and provider own play, pause, seek, fullscreen, and `Tap to unmute`. Fotty observes decoded progress and blocks popup/ad navigation but does not wrap the web surface in an app tap gesture, render a duplicate unmute button, remove the provider prompt, or continuously force media mute/volume. MultiView and explicit muted diagnostics remain the only app-controlled web-audio cases.
- **Why**: The 1.7.0 audio intervention introduced two user-visible regressions: the parent SwiftUI tap gesture captured the whole player surface, and a 500-millisecond synchronization loop immediately remuted media after the provider's own unmute gesture. A DOM property change alone had not proven interactive behavior.
- **Implementation**: Added an explicit provider-controlled audio mode to `LiveWebEmbedPlayerView`, scoped Fotty's tap-to-show-controls gesture to native AVPlayer only, removed standard-player audio state and duplicate UI, and stopped deleting provider mute prompts. Native handoff still unmutes normally outside muted automated tests.
- **Verification**: Version advanced to `1.7.1 (5)` rather than replacing distributed build 4. The no-simulator focused Catalyst playback suite passed 32 active tests, and the full unit-only gate passed 50 active tests with the intentional soak skipped. The signed main app and Live Activity extension both report build 5; the artifact installed, launched, and reports `1.7.1 (5)` on the physical iPhone 15 Pro Max. The paired iPad remained unavailable to CoreDevice. Final provider-control and audible acceptance still requires a currently decoding physical-device stream.

## 2026-08-24: Rebaseline at 1.7.0 (4); Fotty-owned web audio superseded by 1.7.1
- **Decision**: Establish `1.7.0 (4)` as the one-time Daily Driver Beta baseline across the app and Live Activity extension. From this point forward, use semantic marketing versions, monotonically increasing build numbers, `tools/set-version.sh`, `CHANGELOG.md`, and `docs/RELEASE-PROCESS.md`; never treat a CoreDevice installation sequence as the app build.
- **Superseded audio behavior**: Build 4 attempted to make Fotty authoritative for web unmute. Physical use showed that decision intercepted provider controls and re-muted media, so 1.7.1 removes it. The versioning rebaseline remains valid.
- **Why**: The provider could replace or nest its video after Fotty's one-time main-document mute update, leaving a stale provider prompt or a genuinely muted child-frame video. Version `1.6 (3)` also no longer represented the accumulated daily-driver feature set and lacked a repeatable release discipline.
- **Verification**: The focused no-simulator Catalyst playback-policy suite passed 32 active tests, and the full unit-only gate passed 51 tests with the intentional two-minute soak skipped. A WebKit provider probe changed the actual video from `muted=true, volume=0` to `muted=false, volume=1`. The signed main app and extension both report `1.7.0 (4)`, and that artifact installed and launched on the physical iPhone 15 Pro Max. The paired iPad was unavailable to CoreDevice during installation. Audible output remains a manual physical-device acceptance check on an actively decoding source; no simulator or device UI-test helper was used.

## 2026-08-24: Home `LIVE` is a watchability promise
- **Decision**: On Home, reserve the `LIVE` label for catalog events that advertise a supported web broadcast and make the entire row open playback. A score/schedule fixture that is underway without a supported catalog source is labeled `IN PLAY` and opens details instead. Recent provider-family failures may change automatic source ordering, but cannot hide Watch or block the first source attempt after an explicit user tap.
- **Why**: Match timing and broadcast capability had been conflated. Eight of the current eleven catalog-live matches were `echo`-only; Fotty displayed them as `LIVE` while excluding that family from playback, leaving rows that looked watchable but behaved like dead controls.
- **Implementation**: Restored current StreamEx catalog families (`admin`, `delta`, `echo`, `golf`, and `india`) to the supported web pipeline, kept `hotel` under Score808, added a Details fallback for genuine non-broadcast rows, and made initial single-player loading honor manual intent over the automatic circuit breaker.
- **Verification**: The current catalog was inspected directly, Debug Mac Catalyst compiled, and 28 playback-policy tests passed with one opt-in soak skipped. The Catalyst app showed Watch on the formerly dead `echo` rows and a full-row interaction opened the Fotty player with two numbered broadcast sources. That sampled provider feed then returned upstream HTTP 503/404 responses and did not decode, correctly surfacing a playback error rather than being hidden by Home. The signed build installed and launched on iPad sequence `2224` and iPhone sequence `2372`; a physical-iPad screenshot confirmed every visible `LIVE` row exposes Watch. No simulator or UI-test runner was used.

## 2026-08-24: Matchday Editorial is the single consumer UI system
- **Decision**: Replace the accumulated dashboard/control-center presentation with one restrained matchday hierarchy and shared semantic type, surface, border, and button tokens. The persistent product navigation is `Home`, `Matches`, `FPL`, and `Settings`; the legacy `Arena` raw tab value remains only as a persistence migration detail.
- **Home and matches**: Home now has one compact `Now & next` lead match and one chronological `Match schedule`, rather than several overlapping live/soon/team rails. `Matches` owns the literal `Live`, `Upcoming`, and `Results` states with competition filtering and status-aware score/time rows. Scheduled fixtures never render a misleading 0–0. Score coverage is deliberately Premier League-only, so an active non-covered league does not show a score-unavailable message. The later Home-watchability decision reserves `LIVE` for rows with a supported catalog broadcast and uses `IN PLAY` otherwise.
- **Match Center and player**: Match Center is one status-aware overview instead of Arena/Insights/Highlights tabs. It shows lineups and insights only when data exists, reserves space for its own consistent close control, and offers a real retry when details are unavailable. The player has one portrait match header, opaque loading/error states, compact numbered broadcast rows, generic quality descriptions, and truthful `Selected`, `Select`, or `Try again` actions. Internal provider names, heat, risk, cooldown, and discovery diagnostics stay out of consumer UI.
- **FPL and settings**: FPL is organized into four stable workspaces—`Gameweek`, `Squad`, `Coach`, and `Tools`—while preserving the existing official-data and Smart Coach engines. Settings is local-first and grouped by Preferences, Notifications, Playback, Privacy, and About; dead cloud/account controls and duplicated profile actions are removed.
- **Verification**: Final Debug Mac Catalyst compiles and was visually checked across Home, Matches, FPL, Settings, and player recovery. The no-simulator policy gate passed 46 tests with one opt-in soak skipped. The final signed build installed and launched on the connected iPhone 15 Pro Max as installation sequence `2364` and on the connected iPad as sequence `2216`. A physical-iPad screenshot confirmed the masthead respects the status bar and non-covered live competitions show `LIVE` without a false score-error message. No simulator, UI-test runner, or helper app was used. The generic Release smoke was interrupted after the iOS 27 beta Xcode build operation hung during package loading; it produced no source diagnostic. Live-provider/PiP behavior still requires an active compatible stream and manual physical-device interaction.

## 2026-08-23: Official FPL fixtures are the primary Premier League score source
- **Decision**: Reuse Fotty's existing official public FPL `fixtures/` and `bootstrap-static/` transport for Premier League scores. Map only actively playing fixtures, merge them into football-data schedule identities using shared team aliases, label the source `Official FPL`, and poll at 60 seconds only inside the existing match window. API-Football and football-data remain second and third sources respectively.
- **Why**: This gives the personal build useful current-season scores without paying for a feed or spending the restricted API-Football allowance. It uses a data surface the app already trusts instead of adding a second scraper maintenance path.
- **Scraper boundary**: Scraping is still a valid small-app option for a concrete missing field. The reviewed Premier-League-API repository is reference material only: Fotty does not copy its currently unlicensed code, and its present OneFootball selectors returned no rows. Add a server-side scraper only when it fills a measured gap and has freshness, schema, and fallback checks.
- **Freshness and identity**: FPL fixtures cache for 45 seconds, the repository cache for 55 seconds, and stale disk fixture snapshots are rejected. FPL ids are never treated as API-Football ids; live score/status/minute data is merged onto the existing schedule fixture so navigation, notifications, Match Center, and stream matching remain stable.
- **Verification**: The live FPL fixtures and bootstrap endpoints returned HTTP 200, 380 fixtures, 20 teams, and the expected live-state fields. The no-simulator Catalyst gate passed 46 tests with one opt-in soak skipped, and the generic Release build succeeded. No match was active during the probe, so actual match-time latency must be observed during the next Premier League fixture.

## 2026-08-23: Live-score quota is Premier League-only and globally budgeted
- **Decision**: Keep schedules and stream discovery broad, but constrain every live-score/enrichment path to the Premier League. For one active competition, API-Football uses league `39` plus current season/date and filters the response to in-play statuses because the provider rejects a lone id in `live`; football-data fallback uses only competition `PL`; iOS filters provider responses, schedule-derived score UI, minutes, and alerts; non-covered Match Hub rows do not trigger API-Football detail calls; and the emergency fixture fallback follows the same allowlist. The schedule refresh runs first and suppresses the live request outside the five-minute pre-kickoff through three-hour match window. One Worker Durable Object shares a four-minute response cache across devices, caps upstream use at 80 calls per UTC day, and holds the provider's final 20 free-tier calls in reserve.
- **Why**: Fotty should spend its small provider allowance where users are most likely to receive complete, trustworthy data. A worldwide live feed was unnecessary, and the prior multi-league emergency sweep could create several extra calls during an upstream outage.
- **Client reuse and truth labeling**: A successful live-list payload seeds the Match Hub cache. Automatic and timer-driven Match Hub loads reuse known schedule/live data and cannot enrich; only an explicit full refresh may call deeper provider data. A football-data fallback is labeled `Delayed`, and quota reservation is distinct from ordinary provider failure.
- **Future Champions League switch**: The policy records API-Football league id `2` and football-data code `CL`, but leaves them inactive. Adding `.championsLeague` to the active list enables the provider's valid multi-league `live=39-2` form and both providers' UCL ids without reopening global coverage.
- **Verification**: Forty-four active Catalyst tests pass with one opt-in soak skipped; the generic physical-iOS Release build, Worker JavaScript syntax, Wrangler dry run, Durable Object health and access-restriction paths, and production football-data fallback pass. Worker version `e50e0d24-b700-4ca5-9b6e-f178fbca278b` is deployed. A signed normal Debug app was installed on the connected iPhone as installation sequence `2316`. No simulator or UI-test runner was used.
- **Activation boundary**: The production `API_FOOTBALL_KEY` is correctly named and accepted, but the provider explicitly rejected the current 2026 season on its free plan and offered only 2022–2024. Health separates `apiFootballCredentialConfigured=true` from `premierLeagueLiveScoresConfigured=false`; the Durable Object holds that plan restriction for four hours so clients immediately fall back without repeated upstream calls. Current-season minute enrichment requires a provider plan that includes it. Until then football-data is the intentionally labeled delayed score source.

## 2026-08-23: Native-first playback and one daily-use product flow
- **Decision**: Keep provider WebKit playback as the immediate compatibility path, then capture the real HLS/MP4 request only after decoded progress, validate and pre-roll it through a separate muted `AVPlayer`, and switch invisibly only after native time advances. Native failure returns to the same web source before any provider failover. A single `LivePlaybackState` now derives loading/playing state so overlapping callbacks cannot claim contradictory UI states.
- **Why**: Headless extraction before playback was slow and unreliable, while web-only playback prevented dependable Picture in Picture. The visible stream must never be sacrificed for a speculative native upgrade.
- **Product consolidation**: Watch shows compact numbered broadcasts and visible playback notices; Search, Home, and Arena converge on one Match Center; unverifiable `4K`, provider-heat, and vague data-quality labels are gone. Home explicitly separates Live now, Starting soon, Your teams, and the dated schedule. FPL opens on its phase-aware Gameweek Plan and Smart Coach replies include evidence, limits, confidence, source, official-data status, and verification time.
- **System surfaces**: Match alerts are limited to followed teams whose per-team bell is enabled, and tapping one opens that match in Match Center. A `fotty://live/<match>` Live Activity tap only foregrounds the surviving player instead of covering it with another screen. Live Activities still require verified native/PiP eligibility and clear on close/cold launch.
- **Verification**: Debug Mac Catalyst and generic iOS compile; 36 focused tests pass with the opt-in playback soak skipped; Release and Review Safe generic iOS compile; signed Debug installed and launched as the normal `com.jelani.Fotty` app on the connected iPhone (installation sequence 2300). No simulator, UI test, or UI-test runner app was used. The iPad was not available to Xcode during this final install and still requires the printed physical checklist.

## 2026-08-23: Live Activities must represent real continuing playback
- **Decision**: Do not create a Live Activity for StreamEx/Score808 web embeds. Present one only after native playback is ready and Picture in Picture/background continuity is actually available. Eligible activities show matchup, score, minute/status, and an explicit return-to-player cue instead of provider diagnostics.
- **Why**: The previous activity started during loading, survived some force-close/background paths, and displayed technical state without useful match context. A system-hosted notification that outlives a web player falsely implies the stream is still running.
- **Lifecycle**: End the activity when playback stops, errors, loses background/PiP eligibility, or leaves the player. Clear orphaned Fotty activities on cold launch; use a short iOS background task so an end request can finish after the scene backgrounds.
- **Verification**: Three focused policy tests pass on Mac Catalyst, the Live Activity extension and signed generic iOS build succeed, and the clean app-only build was installed and cold-launched on the connected iPhone. No simulator or UI-test runner was used.

## 2026-08-23: Watch actions must be source-backed and consumer source UI stays literal
- **Decision**: Only fixtures advertising a supported StreamEx/Score808 catalog source receive Watch actions or enter the hero/On-now/"Pick for me" surfaces. Score-only fixtures remain visible with Details. The player uses compact numbered source rows labeled Playing, Select, or Try again; provider health jargon remains internal.
- **Why**: A physical-iPhone test reproduced a hero "Watch Live" button that could only end in "Stream Not Available." Consumer controls must state a real capability and make their result predictable.
- **Verification**: A subsequent source-backed physical iPhone run opened the live player, found two compact broadcast-source controls, and stayed open without the playback error overlay for 20 seconds.

## 2026-08-23: Score credentials live at the Worker boundary
- **Decision**: iOS football-data calls default to `/api/football/matches` on the production playback Worker. The Worker owns `FOOTBALL_DATA_API_KEY`; optional live/minute enrichment uses `/api/football/live` only when `API_FOOTBALL_KEY` is configured there. The later Premier League-only decision above supersedes this entry's original global-live scope.
- **Why**: The device had no local football credentials, producing `unauthorized` / `noAPIKey` and an empty score index. Provider secrets must not be embedded in the application.
- **Verification**: Worker version `ce02b53b-ead3-46d2-aacf-9d7090758f9b` deployed; health reports schedule configured and global live unconfigured, and the schedule proxy returns a successful authenticated response.

This document tracks technical and product decisions to ensure all agents (Cursor, Codex, Antigravity) maintain consistent reasoning.

## 2026-08-23: Mac Catalyst is the repeatable shared playback laboratory
- **Decision**: Keep iPhone/iPad as the release authority, but use the Mac Catalyst app for sustained testing of the shared native player, required-header local proxy, readiness observation, watchdog, attempt identity, and failover policy. DEBUG Settings → Stream pipeline checks now exposes a two-minute muted continuity soak and an exportable result.
- **Why**: The iOS 27 beta XCTest host can pause or terminate media after a short foreground window, while Catalyst can hold the same production playback objects active for long, repeatable runs without a simulator. Catalyst must not issue iOS orientation geometry requests.
- **Verification**: The signed Debug Catalyst build launched normally. The opt-in soak decoded 120.83 seconds across 120/120 advancing samples at rate 1.0, with zero waiting samples, paused samples, errors, source/attempt/item replacements, or automatic failovers. The actual app then opened current StreamEx #1 playback for New England–NYC and visibly advanced from match clock 68:14 to 71:17, including a period where Fotty lost focus, without returning to loading, showing an error, or visibly changing sources. The ordinary 30-test unit suite passed with the opt-in soak skipped, and `ReviewSafeDebug` Catalyst compiled. A broad Catalyst UI run separately found four Dashboard accessibility-audit failures unrelated to the player edits; these do not invalidate playback but remain Mac UI work.
- **Boundary**: The reference HLS run proves Fotty does not drop a healthy native stream on its own, and the real StreamEx hold proves one current provider embed can remain decoded in the Catalyst app. Neither replaces final iPhone/iPad autoplay, audio-session, background, and WebKit checks during a live match, nor guarantees future StreamEx/Score808 availability.

## 2026-08-23: Playback recovery favors the current decoded stream over eager failover
- **Decision**: Treat a temporary pause or AVPlayer error-log entry as recoverable until bounded progress checks prove the active attempt is still stalled. Every load has a unique attempt ID, and delayed WebKit, AVPlayer, watchdog, foreground, and P2P callbacks must match both the selected source and that exact attempt before they can change state or trigger failover.
- **Why**: A provider stream could briefly stall, recover and resume visibly, then be replaced by an automatic source attempt that had been scheduled from stale failure evidence. Source identity alone was insufficient when the same source had been reloaded.
- **Web behavior**: Web playback now waits 30 seconds without decoded playhead progress, accepts a recovery signal during a final eight-second grace period, cancels the pending failure when progress resumes, blocks popups/top-level ad navigation, and removes known nuisance ad overlays where WebKit can safely reach them. Same-origin or provider-inserted video ads cannot be guaranteed removable without risking the stream.
- **Continuity hardening**: A network-path loss no longer pauses or rebuilds the player, clears source history, or jumps back to a preferred source. Fotty preserves the exact attempt, lets AVPlayer/WebKit buffer, resumes that same item after connectivity returns, and only reloads the selected source if the item is terminally failed. MultiView likewise preserves web attempts across background/foreground transitions. All post-start WebKit failure signals now receive an eight-second decoded-progress recovery window, not only errors whose text says `stalled`. The local HLS proxy no longer POSTs per-request telemetry to the retired P2P host; proxy diagnostics remain on-device so logging cannot compete with media traffic.
- **Product UX**: Removed the Safari/provider-site escape and consumer-facing `Risky`, `Reliable`, `Stable`, and `Cooling down` labels. Historical source health and the 15-minute family circuit remain internal inputs to automatic ordering; failed sources are shown simply as unavailable or manually retryable.
- **Verification**: The generic physical-iOS build and signed iPhone build pass. Eighteen focused playback-policy tests pass on Mac Catalyst with no simulator, including stale same-source callbacks, offline attempt preservation, and recovery state. An opt-in muted physical-iPad HLS check decoded Apple reference media and held the same source, attempt ID, and AVPlayer item with zero errors or failovers; longer physical XCTest holds are limited by the iOS 27 beta test host's media/runner foreground window. The signed app was installed and launched successfully on the connected iPhone and iPad.

## 2026-08-23: Production Smart Coach favors verified evidence and bounded output over hidden reasoning
- **Decision**: Run the production `deepseek-v4-flash` coaching call in non-thinking JSON mode. The Worker supplies the whole-decision structure through compact official evidence and explicit truth rules, rejects empty, incomplete, or known rule-contradicting output, and returns non-sensitive token usage for cost monitoring.
- **Why**: Thinking mode consumed the entire 1,400-token and then 3,000-token completion budgets as hidden reasoning, returning no usable answer. Non-thinking mode completed a structured response in seconds and cost less. The first successful answer also exposed ambiguous raw fields, so global gameweek counters were removed, current/next events were compacted, and verified transfer/sell-on/price-projection semantics were added.
- **Truth guardrails**: Four extra free transfers means five total; sell-on fee `0.5` is the half-profit share rather than a fixed £0.5m charge; a price projection is directional rather than realized profit; zero minutes is not evidence of omission before the player's fixture starts. Known contradictions fail closed to the on-device coach.
- **Production verification**: The live Worker returned HTTP 200 with `officialDataStatus=fresh`, valid answer/evidence/assumptions/actions, `finishReason=stop`, and the correct next deadline. The no-manager smoke used 8,982 cache-miss input tokens and 305 output tokens (about $0.00134). Compacting public manager/history/picks data removed irrelevant profile/league fields and reduced a representative manager call from 19,979 input tokens/$0.00297 to 13,787 input tokens plus 564 output tokens/$0.00209, roughly 30% cheaper.

## 2026-08-22: FPL daily-use platform and consent-gated Smart Coach
- **Decision**: Make the FPL area one phase-aware decision system rather than a collection of disconnected advisory screens. Official FPL facts feed a shared command center, live tracker, player evidence, rival analysis, planner, squad validator, optimizer, reminders, and confirmed-gameweek review. AI explains that evidence but does not manufacture it or replace the local rules engine.
- **Smart Coach architecture**: Keep a deterministic on-device fallback. With explicit in-app consent, send only the question, up to eight recent messages, manager ID, and a compact decision context to Fotty's Cloudflare Worker. The Worker independently refreshes official FPL evidence and calls DeepSeek with a server-held secret; no AI credential is stored in the iOS bundle.
- **Truth boundaries**: Official, modeled, stale, and local-draft data are labeled separately. Event-live points/BPS/bonus and autosubs come from official endpoints. Available free transfers remain a public-history estimate, selling prices are not guaranteed by the public API, and transfer/wildcard actions remain local drafts rather than official submissions.
- **Implementation**: Added snapshot provenance and freshness, phase detection, shared formation/budget/club/captain/selectability validation, official live refresh, post-GW review persistence, transfer-route comparison across five or eight gameweeks, legal safe/balanced/aggressive squad generation with locks/exclusions, price-direction evidence, deadline reminders, deeper player comparison, and live rival swings. Replaced unsupported EO/rank/Monte Carlo/exact-ILP claims and removed dormant fake-data engines.
- **Verification**: Eleven focused FPL contract/rules/validation tests pass within the full 25-test suite. Debug and Review Safe Catalyst builds pass. The Worker packages successfully in Wrangler dry-run mode.
- **Activation status**: The correctly named Worker secret and route were deployed and production-smoked on 2026-08-23. The app still falls back locally for unavailable, over-limit, empty, malformed, or verified-rule-contradicting provider output.

## 2026-08-22: FPL must be official-data-first and truth-labeled
- **Decision**: Treat the present FPL feature as an ambitious prototype, not a decision-safe daily-use tool. Before adding more surface area, remove client AI secrets, restore current official API compatibility, centralize squad legality, and distinguish official facts, modeled projections, and editorial/AI explanations in both types and copy.
- **Why**: The audit found a live league schema mismatch, deadline-independent “pre-season” transfer costing, fabricated or heuristic live bonus/rank/EO/price values, misleading local-only transfer actions, a greedy optimizer presented as an exact ILP, hardcoded tactical claims that contradict the live player catalog, and no FPL-specific tests or accessibility semantics.
- **Product direction**: Use the free official FPL surface more deeply rather than adding a licensing provider. Build one phase-aware Deadline Command Center: pre-deadline planning, true event-live tracking during matches, and post-gameweek review. Add mini-league rival swings and explainable AI only after the underlying facts and rules are trustworthy.
- **Required validation**: Contract-test every consumed official endpoint; test deadline, rolling-transfer, two-chip-set, blanks/doubles, squad formation, budget, club quota, captain/vice, and autosub rules; show cache age/source; and never describe a local draft as an applied official transfer.
- **Trust-reset implementation**: Removed embedded AI credentials and all FPL coach network calls; coaching is now deterministic and on-device. Updated mini-league decoding for the current `entry`, `player_name`, `league_type`, and paging contract; prefers private mini-leagues and exposes loading, retry, empty, and load-more states. GW1 unlimited transfers now depend on the official deadline. Manager drafts and chat are manager/season scoped, purchase/selling prices survive mutations, and local transfer/wildcard/recommendation surfaces are explicitly labeled as drafts or Fotty model output.
- **Removed claims**: The product no longer reconstructs live points, bonus, autosubs, effective ownership, rank movement, Monte Carlo outcomes, press-conference certainty, exact ILP optimization, or hardcoded unlocked achievements from unsupported heuristics. The static tactical/pre-season registry no longer affects advisor scores.
- **Verification**: Added five focused FPL contract/rules tests. All 19 unit tests pass, and normal Debug plus `ReviewSafeDebug` simulator builds succeed. Source secret scanning and a live league-contract probe pass. Previously exposed provider keys still require revocation outside the repository.

## 2026-08-22: Daily-use playback means adaptive degradation, not guaranteed provider uptime
- **Decision**: Keep the existing third-party catalog model and make Fotty resilient around it. Web playback now preserves the provider page for a browser-parity startup window, proves success only from decoded/advancing video, delays child-frame errors until the startup deadline, fails over automatically, and opens a 15-minute family circuit after two consecutive failures. Manual retry always remains available.
- **Why**: A commercial licensing/feed API is not a realistic dependency for this project, while pretending an iframe load is a working stream causes black screens and retry loops. The app can control selection, validation, recovery, and honesty; it cannot control upstream rights or manifests.
- **Recovery UX**: Broadcast Sources is a real sheet again, cooling/failed sources are labeled and manually retryable, and the terminal player offers the provider website in Safari. MultiView is only offered after at least two candidates exist and their provider family has produced a decoded success in the last 24 hours.
- **Measured result**: `tools/audit_live_playback_matrix.mjs` sampled 24 current variants across admin, delta, echo, and golf with WebKit. Result was 0/24 decoded: admin/delta/echo manifests returned HTTP 403/CORS and golf reported embedding disabled; no current hotel candidates were listed. This is provider availability evidence, not an app regression.
- **UI/accessibility**: The custom dock now participates in layout instead of covering scroll rows; fixture rows use concise team/time labels; contrast, Dynamic Type, element detection, hit-region, clipping, trait, and element-description audits pass as bounded tests.
- **Verification**: 14 unit tests pass; rapid navigation/background recovery passes; normal physical-iOS, Review Safe, and static-analyzer builds pass. Signed device installation sequence `2064` rendered, refreshed 220 cached fixtures to 254 current fixtures, and survived a console-attached 65-second physical-iPad hold before an intentional interrupt.

## 2026-08-22: iOS stabilization baseline and honest feature scope
- **Decision**: Treat the current iOS product as a live-sports companion with local profiles/social data, provider-backed match discovery, and optional StreamEx/Score808 web playback. Remove unimplemented PocketBase account claims, fake seeded activity/content, VOD placeholder surfaces, and user-facing P2P/AceStream paths.
- **Why**: Daily-use reliability requires the UI to describe capabilities the shipped app can actually perform. Placeholder success states and retired infrastructure made failures look like working product behavior.
- **Implementation**:
  - Playback resolution is cancellation-safe, bounded to 20 seconds, filtered to the two enabled module families, and fails over between independently validated candidates.
  - `LiveWebEmbedPlayerView` reports decoded-frame progress, startup timeout, stalls, blocked navigation, and provider errors instead of treating page load as playback success.
  - Social messaging and profiles are explicitly on-device; Highlights exposes real match context and does not invent video clips; FPL requires a real manager ID/API response.
  - App and extension plist permissions were reduced to capabilities in use. Review Safe excludes the complete playback implementation through `APP_REVIEW_SAFE` substitutions.
- **Verification**: Normal and Review Safe generic simulator builds and the Xcode static analyzer succeed; this baseline was subsequently expanded by the daily-use playback decision above.

## 2026-08-22: Playback availability is measured at decoded video, not catalog health
- **Decision**: Keep catalog/provider health separate from playable-video health. A source is not reported healthy merely because the Nexus catalog or embed document returns HTTP 200.
- **Why**: All three current catalog feeds returned roughly 300 events, while real browser probes of sampled live matches produced no decoded frames: the StreamEx admin/delta manifests were blocked with HTTP 403/CORS and the golf candidate exposed an ad/no video.
- **Consequence**: The iOS failure and fallback UI is working, but current third-party live video availability remains an infrastructure dependency. Do not describe playback as end-to-end working until a decoded-frame probe succeeds.

## 2026-08-22: Automated tests must not start production polling
- **Decision**: `AppRuntime.isAutomatedTesting` gates dashboard/live-score polling, and the shared Fotty scheme sets `FOTTY_AUTOMATED_TESTING=1` for test actions.
- **Why**: Unit-hosted app launches were making live network requests, creating non-deterministic tests and unnecessary provider traffic.
- **Verification**: The isolated iPad unit run completed 10/10 with no production match requests in the log.

## 2026-08-22: iOS Cold-Launch Observation Loop Fix
- **Decision**: Keep `LiveScoreService`'s derived match indices and lookup caches outside Swift Observation, and represent negative lookups with a dedicated set instead of assigning `nil` to a dictionary subscript.
- **Why**: The physical iPad termination report proved a `scene-create` watchdog (`0x8BADF00D`), with the main thread stuck flushing `ObservationGraphMutation` during the first SwiftUI commit. Dashboard view evaluation called `findMatch` repeatedly; its observed cache writes invalidated the same view graph, while `matchLookupCache[key] = nil` removed misses instead of caching them.
- **Implementation**:
  - Marked the match indices, positive-result cache, and negative-result set with `@ObservationIgnored`.
  - Removed redundant locks because `LiveScoreService` and `findMatch` are main-actor isolated.
  - Clear both positive and negative lookup caches when refreshed match data rebuilds the indices.
- **Verification**:
  - Reproduced the previous installed build dying at about 30 seconds after loading 306 cached matches.
  - Built and signed Debug for iOS, installed device database sequence `1984`, and cold-launched on Jet iPad (`00008101-001954E20AC0001E`).
  - The app survived more than 80 seconds with the console attached, refreshed from 306 cached matches to 319 current matches, and rendered the complete Dashboard.
  - Relaunched without the console, captured the rendered dashboard, and confirmed both the app and Live Activity extension processes remained alive.

## 2026-08-14: Formal Homelab Decommissioning & Pure Cloud/Web Architecture
- **Decision**: Removed all residual local homelab fallbacks (`homelabAPIURL`, `homelabMatchesMirrorURL`, blocking SSH sync in agent scripts).
- **Why**: Homelab infrastructure has been retired. Fotty operates 100% cloud-native via edge CDNs, live provider APIs (StreamEx / VipLeague / Score808), and companion web infrastructure. Removing homelab timeouts eliminates 2.5s network delays across dashboard refreshes and tool scripts.

## 2026-08-13: Eliminate Fake Score808 Synthesized Stream URLs
- **Decision**: Restricted `ensureScore808EmbedSessions` in `HybridStreamProvider.swift` to only generate Score808 `hotel` streams when the match descriptor actually contains a legitimate `hotel` source code.
- **Why**: The app previously took IDs from other providers (`echo`, `delta`, `golf`) and synthesized fake `embed.st/embed/hotel/...` URLs. These non-existent IDs caused JW Player to fail loading the HLS manifest with `hls:networkError_manifestLoadError`. Real provider streams are now preserved without synthetic corruptions.

## 2026-08-13: JW Player Direct API Autoplay & Ad Overlay Bypass
- **Decision**: Added direct `window.jwplayer` API integration (`jw.skipAd()`, `jw.play()`) and automatic ad overlay removal (`#close`, `.jw-ad-container`, `iframe[src*="ad.html"]`) to `LiveWebEmbedPlayerView.swift`.
- **Why**: StreamEx and VipLeague embeds using JW Player often stall on black screens when third-party ad networks fail or place transparent clickjack overlays over the video player. Calling the JW Player playback API directly forces instant HLS streaming without user interaction bottlenecks.

## 2026-08-13: StreamEx Network Feeds & Provider Matching Fix
- **Decision**: Expanded `StreamPluginProviderMatching` to include all StreamEx network web embeds (`delta`, `echo`, `golf`, `india`, `hotel`). Removed artificial filters that wrongly discarded StreamEx's `echo` and regional feeds.
- **Why**: StreamEx serves matches across several source codes on `embed.st`. The previous strict filter was mistakenly dropping StreamEx feeds (such as Vasco da Gama and Leagues Cup fixtures), causing "Stream Not Available" alerts on legitimate live matches.

## 2026-08-13: UI Scroll Performance & Loading Animation Optimization
- **Decision**: Added memoized `O(1)` dictionary lookup cache to `LiveScoreService.findMatch(home:away:)` to eliminate 30,000+ redundant fuzzy string regex scans per scroll frame. Virtualized match lists with `LazyVStack` in `DashboardMatchList.swift`. Removed heavy per-badge `@ObservedObject` subscriptions in `FlagSquircleBadge`. Upgraded `FootballLoadingView` to display-linked `TimelineView(.animation)` for continuous 60/120 FPS rendering.
- **Why**: Drastically improves iPad/iOS scrolling responsiveness, eliminates frame drops, and delivers a silky-smooth experience across 60+ live and upcoming fixtures.

## 2026-08-13: StreamEx Play/Pause Toggle Bug Fix (WebKit Script Refactor)
- **Decision**: Fixed the recurring play/pause toggle loop in `LiveWebEmbedPlayerView.swift`. Eliminated recurring click polling on player overlay containers (`.jw-display-icon-display`), replaced loop with an early-terminating one-time kick, and removed asynchronous programmatic unmuting that caused iOS WebKit audio policy suspensions.
- **Why**: StreamEx embeds JW Player in child iframes where parent frame polling re-clicked the video canvas every 3.5s, inadvertently sending PAUSE commands to active streams.

## 2026-08-13: Codebase Cleanliness, Mega-File Modularization & PocketBase Retirement
- **Decision**: Modularized the 3,666-line `SocialHubView.swift` mega-file by extracting isolated components into `Fotty/Features/Social/Components/` (`MatchChatView.swift`, `DirectChatView.swift`, `SocialCelebrationViews.swift`). Retired dead legacy `PocketBaseClient.swift` (16KB REST client) and cleaned up `SocialCloudStore.swift` and `FootballService.swift` `TeamBrandService` to operate as local-first stores backed by SwiftData, `UserProfileStore`, and reliable remote CDNs (ESPN & TheSportsDB). Regenerated project via XcodeGen and verified clean zero-error compilation.
- **Why**: Drastically improves codebase readability, build compile times, and eliminates dead networking code while preserving 100% feature capability.

## 2026-08-13: Interactive FPL Pitch Swapper & Lock Screen Media Controls
- **Decision**: Added interactive tap-to-swap substitutions in `FPLSquadPitchView` with dynamic formation calculation and projected point delta badges. Upgraded `FPLPriceAlertsView` with velocity progress barometers. Created `NowPlayingManager` to bind iOS Lock Screen and Control Center `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` controls to stream playback.
- **Why**: Drastically improves user agency when experimenting with FPL tactical lineups and provides seamless system-level media integration.

## 2026-08-13: Fortifying Core Pillars (FPL Snapshots, Scraper Resilience, Local User Storage)
- **Decision**: Added persistent disk caching to `FPLService` to eliminate deadline/pre-season lockout failures. Created `tools/stream_health_checker.py` to continuously validate catalog mirrors. Added `UserProfileStore` for local preferences & FPL Manager ID persistence and decoupled iOS from retired PocketBase backend. Implemented interactive 5-axis Radar Chart in FPL comparisons and web embed auto-failover in `LiveWebEmbedPlayerView`.
- **Why**: Eliminates the 4 primary fragility vectors identified across streaming, review mode gating, FPL API downtime, and retired cloud backends.

## 2026-08-12: Both surfaces — Worker Watch + Score808 host-frame on iOS
- **Decision**: getfotty.com Watch must always hit the Cloudflare playback Worker for `/api/live/streams` (default `FOTTY_DEFAULTS.playbackApiBase`); do not synthesize dead “Fotty 1–4” shells when the Worker is reachable. Feed list shows StreamEx/Score808 titles like iOS. iOS keeps Score808 Safari host-frame (`score808live.tv` parent → embed.st iframe) plus CDN allowlists.
- **Why**: Site was unusable (Aug 3 static deploy; Watch called same-origin HTML as JSON). App Score808 failures were WKWebView context/filters, not dead sources.
- **Deploy**: `tools/web-deploy-ftp.sh` (needs `FOTTY_FTP_PASSWORD`) + `tools/ios-deploy-device.sh`.

## 2026-08-09: Score808/StreamEx failures were app WKWebView filters, not the sources
- **Decision**: Treat JW `hls:networkError_manifestLoadError`, StreamEx random pause, and Watch Now “Looking for a playable stream…” as **Fotty app bugs**. Score808 and StreamEx play in Safari; do not blame or retire those sources for in-app breakage.
- **Why**: `LiveWebEmbedPlayerView` treated `cloudfront.net` (and similar media CDNs) as ads in JS `isNuisanceURL` and Swift `blockedHostFragments`, cancelling HLS manifests. Allowlist omitted `embed.st` / Score808 hosts. Aggressive autoplay re-clicked JW play/pause. Resolve piled headless extract / stub retries on top. Fix: keep media CDNs out of ad blocks; direct `webView.load` with correct Referer; soft autoplay after start; Watch Now returns hotel+delta web embeds quickly (no long extract hang).
- **Follow-up**: Device-verify Score808 plays, StreamEx stays playing, Watch Now opens in a few seconds; keep P2P out of the player source list.

## 2026-08-09: Score808 works — app must match Safari host context
- **Decision**: Keep synthesizing `hotel` from donor StreamEx ids when Nexus omits it. Prefer Score808 in the source list. For hotel playback, load a **score808live.tv host-frame** that iframes `embed.st` (Safari parity). Do not `loadHTMLString` the embed document body. Keep media CDNs out of WKWebView ad blocks.
- **Why**: Users watch full matches on Score808 in Safari. In-app `manifestLoadError` was Fotty (CDN ad-block + loading embed.st as top document), not a dead Score808 feed. Treating donor-id hotel as “fake” was wrong.
- **Supersedes**: “Do not invent Score808 from StreamEx ids” / defaulting away from Score808.

## 2026-08-03: PocketBase retired on web — open Watch without VPS
- **Decision**: Homelab PocketBase is out. Web defaults `NEXT_PUBLIC_ACCOUNTS_ENABLED` off; Watch is open to guests; login/signup CTAs and `/api/pocketbase/*` return paused/410; no pixel-invoice PocketBase/P2P defaults. Stay on FTP + playback Worker until a paid VPS is justified for same-origin HLS/unmute.
- **Why**: Auth backend is gone with the homelab; splitting a VPS only for unmute is deferred. Maximize companion site on current hosting.
- **Follow-up**: Choose a new auth provider later; optional full-site VPS if unmute/HLS parity is funded.

## 2026-08-03: Static `/api/matches` stays same-origin
- **Decision**: `NEXT_PUBLIC_FOTTY_API_BASE` only rewrites **playback** paths (`/api/live/*`, `/api/embed/*`, `/api/stream*`, `/api/status`, `/api/p2p/health`). Catalog JSON like `/api/matches` stays on getfotty.com.
- **Why**: Sending matches to the playback Worker returned 404 → Home showed “fresh refresh failed” despite a healthy static matches file.

## 2026-08-02: Watch in-page via direct embed.st iframe
- **Decision**: Watch plays StreamEx in-page with a direct `embed.st` iframe (`referrerPolicy=no-referrer`). No new tab. Unmute overlay only for same-origin proxied players.
- **Why**: Users rejected new-tab playback. CF Workers get stub embed HTML; Apache can fetch player HTML but **strmd HLS returns 403** to the host IP, so PHP unmute/HLS proxy cannot complete playback. Direct iframe from the browser works.
- **Follow-up**: Contabo (or other non-blocked VPS) for true same-origin HLS + unmute bridge.

## 2026-06-18: Web Event Failover Ignores Stale Iframe Callbacks
- **Decision**: Direct-event iframe load and error callbacks must identify the embed URL that emitted them, and the watch page must ignore callbacks from a feed that has already been replaced.
- **Why**: A failed feed could trigger selection of a backup, then emit a late `load` event. Because iframe `load` only means an HTML document loaded (including provider error pages), the stale callback marked the new feed as loaded and cancelled its timeout, so automatic failover appeared intermittent.
- **Implementation**:
  - Changed `DirectEventPlayer` load/error callbacks to include their embed URL.
  - Added a commit-time current-embed guard in the watch page so callbacks from replaced iframes cannot change the active feed's load state or retry path.
- **Verification**:
  - Ran the focused stream ranking/failover tests (4 passing).
  - Ran focused ESLint; only three existing React compiler warnings remain in `WatchPageClient`.
  - Ran TypeScript with `--noEmit` successfully.

## 2026-06-13: Web Direct P2P Should Follow The Native App Route
- **Decision**: `p2pRoute=direct` on Fotty Web should use a native-style public P2P manifest route backed by a short-lived signed `stream_token`, not the Next.js `/api/stream` segment wrapper.
- **Why**: The mobile app plays P2P streams reliably by handing AVPlayer/ExoPlayer the P2P proxy HLS URL directly, while desktop Chrome continued to buffer or stop even after the old web direct route skipped broker session reuse. Server and Mac-style probes showed the P2P proxy can return FOX Sports 2 manifests and range-capable `video/mp2t` segments; the remaining difference was the browser/Next.js HLS wrapper path.
- **Implementation**:
  - Added signed public stream-token verification to `fotty-p2p-proxy` for `/proxy/acestream/stream`, `/proxy/acestream/manifest.m3u8`, and `/ace/proxy`.
  - Added `web/src/app/api/stream/native/route.ts`, which validates Fotty paid watch access, issues a short-lived P2P stream token, and redirects HLS clients to `https://p2p.pixel-invoice.com/[URL_REDACTED]
  - Changed `p2pRoute=direct` / `native` / `edge` / `app` watch URLs to use the native route.
  - Tuned the web HLS.js P2P player toward native-player behavior: larger startup buffer, longer stall/decode tolerance, lower live-edge chasing, and no custom Fotty headers on the redirecting native route.
  - Kept the real P2P API password server-side; browser-visible manifests/segments use `stream_token` and do not include `api_password`.
- **Verification**:
  - Ran `python3 -m py_compile server/p2p_proxy_service.py`.
  - Ran `PYTHONPATH=server python3 -m unittest server.tests.test_p2p_proxy_service`.
  - Ran focused ESLint and TypeScript checks for the new web route/player/watch changes; ESLint only reports existing React compiler warnings.
  - Ran the local production web build successfully.
  - Deployed `fotty-p2p-proxy` and `fotty-web` to the homelab/public site.
  - Ran a sanitized production smoke from inside `fotty-web`: `/api/stream/native` returned 307 to the public P2P proxy, the manifest returned 200 with `stream_token` and no `api_password`, and the first FOX Sports 2 segment returned HTTP 206 `video/mp2t` with `Content-Range`.
- **Follow-up**:
  - Have a signed-in user test the same FOX Sports 2 URL in desktop Chrome with `p2pRoute=direct`.
  - If this holds, make the native direct route the default for P2P web playback and keep the broker path as fallback/diagnostics.
  - Add an automated Chrome smoke that follows `/api/stream/native` and asserts first-frame decode, not only manifest/segment bytes.

## 2026-06-13: Current Ace Engine Beats Latest For FOX Direct Playback
- **Decision**: Keep production on `vstavrinov/acestream-engine:3.1.75-4` for now and test a slimmer Fotty direct P2P watch route before touching the Ace engine image again.
- **Why**: A true host-network swap to `vstavrinov/acestream-engine:latest` reported engine `3.2.11`, but it did not produce reliable media for the channels Fotty needs most. FOX Sports 2 timed out on the direct playback URL, FOX Sports 1 produced only a tiny manifest and then timed out on the first segment, and ESPN timed out while reporting peers. After rollback, the current `3.1.75rc4` engine immediately produced FOX Sports 2 and FOX Sports 1 HLS manifests plus real TS segment bytes.
- **Implementation**:
  - Briefly stopped the old host-network Ace engine, ran the latest image on the real `6878` host port, tested priority CIDs, then rolled back to the old engine.
  - Cleared stale Fotty broker session keys after rollback so failed latest-engine playback URLs would not be reused.
  - Added `p2pRoute=direct` to the web watch page. In that mode Fotty uses the existing `/api/stream?id=<cid>` direct path immediately and skips broker warm-up/session reuse.
- **Verification**:
  - Confirmed production is back on `3.1.75rc4`.
  - Confirmed the P2P proxy direct endpoint returns a FOX Sports 2 manifest and range-capable `video/mp2t` segments through the old engine.
  - Ran focused TypeScript and ESLint checks for the watch page; ESLint only reports existing React compiler warnings.
  - Ran the local production web build and deployed `fotty-web`.
  - Confirmed a signed deployed-stack smoke call to `/api/stream?id=<FOX Sports 2 CID>` returns a manifest in about 6 seconds and the first segment returns HTTP 206 with `video/mp2t`.
- **Follow-up**:
  - Manually test the signed-in public watch URL with `p2pRoute=direct` in Chrome, Firefox, and Safari before making direct mode the default.
  - Do not expose the raw Ace engine port publicly. Keep public access behind Fotty auth and the web/P2P proxy.
  - Move hardcoded P2P secrets out of compose and rotate them.

## 2026-06-13: AceStream Engine Needs A Latest-Image Canary Before Any Production Swap
- **Decision**: Treat the current AceStream setup as a stale but known production path, then canary a newer engine image before replacing it. Do not blindly switch wrappers during World Cup traffic.
- **Why**: The live homelab engine is pinned to `vstavrinov/acestream-engine:3.1.75-4` and reports engine version `3.1.75rc4`. A sidecar smoke test of `vstavrinov/acestream-engine:latest` booted successfully and reported engine version `3.2.11`; `3.2.3-1` also booted and reported `3.2.3`. That means Fotty is not running the latest available engine image, but the latest image still needs real-CID testing before it touches the public path.
- **Implementation**:
  - Confirmed the live stack routes `fotty-p2p-proxy` directly to the Ace engine with `P2P_UPSTREAM_KIND=engine`.
  - Confirmed the live stack is not currently using the `mediaflow-proxy` service from `server/p2p-stack-updated.yml`.
  - Confirmed the newer Ace engine tags start in an isolated sidecar on an alternate local port without altering the running production container.
  - Confirmed the P2P proxy itself is healthy, Redis-backed, and serving a scraper catalog, but prewarming is disabled.
- **Follow-up**:
  - Canary `vstavrinov/acestream-engine:latest` or a pinned digest that reports `3.2.11` against real high-priority CIDs such as FOX Sports 2 before production rollout.
  - Keep rollback to `vstavrinov/acestream-engine:3.1.75-4` explicit in the compose notes.
  - Reconcile homelab compose drift between the live `/home/jelani/acestream/docker-compose.yml` and repo compose files.
  - Move the P2P API password out of compose into an environment file or secret and rotate it.
  - Evaluate `mediaflow-proxy` and `martinbjeldbak/acestream-http-proxy` as separate lab comparisons rather than direct replacements for the current upstream contract.

## 2026-06-13: ViniPlay Runs As A Private IPTV Lab
- **Decision**: Run ViniPlay as a private Tailscale-bound lab sidecar, not as a Fotty production dependency yet.
- **Why**: AceStream remains fragile for browser playback, but ViniPlay is an IPTV/player/proxy harness rather than a channel source. It can quickly test whether M3U/XC sources plus FFmpeg remuxing provide steadier Chrome, Safari, and mobile playback before Fotty commits to a native IPTV gateway.
- **Implementation**:
  - Started `ardovini/viniplay:latest` on the homelab with a persistent `/home/jelani/viniplay/data` volume and `restart: always`.
  - Bound the lab only to the homelab Tailscale address on port `8998` so it stays out of the public Fotty path.
  - Created a lab admin, loaded a public sports M3U source, loaded the current Fotty XMLTV guide, and processed both sources.
  - Switched the active stream profile from raw redirect to ViniPlay's FFmpeg MPEG-TS profile so the lab tests server-side media routing instead of plain browser redirects.
- **Verification**:
  - Confirmed ViniPlay served the app over the private Tailscale URL.
  - Confirmed source processing loaded 354 sports channels and 701 matched live-guide programs.
  - Confirmed a known-good FIFA+ channel produced HTTP 200 MPEG-TS through ViniPlay's FFmpeg `/stream` endpoint and delivered about 24 MB in a 15-second smoke pull.
  - Confirmed public free-playlist FOX entries are not reliable enough to be treated as World Cup coverage by themselves: one had broken segment range behavior and another timed out from the ViniPlay container.
  - Added the public Free-TV playlist as a second lab M3U; it processed 1,888 additional channels, but the focused sports probe showed most match-relevant channels were blocked, missing, refused, geo-limited, or stale. A few regional/specialty sports channels started, but Free-TV did not materially change the World Cup coverage answer.
- **Follow-up**:
  - Test with authorized M3U/XC sources before any Fotty integration.
  - If reliability is good, build a Fotty-owned IPTV gateway instead of copying ViniPlay code, because ViniPlay's current license is not suitable for a paid production Fotty dependency without permission.

## 2026-06-13: Browser WebRTC HLS Delivery Is A Flagged Ace Experiment
- **Decision**: Fotty Web can optionally wrap broker-served AceStream HLS with P2P Media Loader/WebRTC in the browser, but the path must remain default-off until real two-client swarm behavior is proven.
- **Why**: AceStream has repeatedly been the weakest link for desktop playback during World Cup preparation. A browser-side WebRTC HLS layer may reduce repeated segment pulls from Fotty's proxy once multiple viewers watch the same CID, but it cannot fix a dead Ace source, frozen broker playlist, or manifest/auth failure by itself.
- **Implementation**:
  - Added a `plain-hls` default and `p2pDelivery=webrtc` opt-in path for watch URLs.
  - Dynamically loads P2P Media Loader only when the experiment is enabled, then injects its Hls.js mixin around the existing Fotty player.
  - Uses a stable swarm id per Ace CID, `fotty-ace:<cid>`, so viewers on the same channel can discover the same segment swarm.
  - Falls back to normal Fotty HLS if the loader script, browser support, or Media Loader API is unavailable.
  - Exposes bounded DOM/debug markers for delivery mode, swarm id, and recent P2P events so production browser tests can verify whether the experiment actually engages.
  - Wired the player-level `Retry stream` button into the watch page's broker retry path so a failed media element forces a fresh broker session instead of replaying the same stale HLS session.
- **Verification**:
  - Ran focused ESLint and TypeScript checks; only the existing React compiler warnings in `VideoPlayer` remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Browser-smoked the public FOX Sports 2 HD watch URL with `p2pDelivery=webrtc`; the page loaded the Media Loader script, rendered the `P2P WebRTC` badge, initialized `webrtc-hls`, used the stable FOX Sports 2 swarm id, and recorded `onChunkDownloaded` events.
  - Earlier in the same smoke run, the video element reached a live playing state with decoded 1280x720 video while the Media Loader path was enabled.
  - After a FOX Sports 2 screenshot showed `Playback unavailable` with broker `manifest_403`, confirmed a fresh backend broker session became ready in 5 seconds, deployed the retry handoff patch, reloaded the public watch URL, and verified active 1280x720 playback with buffered video and WebRTC-HLS chunk downloads.
- **Follow-up**:
  - Prove or reject the experiment with two real desktop/mobile clients on the same watch URL at the same time and require `onPeerConnect` / `onChunkUploaded` before treating it as useful.
  - Do not ship public-tracker defaults for production; use a private tracker/signaling setup if the two-client test is promising.

## 2026-06-13: Web P2P Playback Recovers Stale Browser Sessions
- **Decision**: Fotty Web should treat P2P browser/player failures as recoverable while the broker is still serving manifests and segments, and should preserve media range headers through the Next.js segment wrapper.
- **Why**: FOX Sports 2 HD could show `Playback unavailable` even while the Match Center reported peers, speed, segments, and buffer. Server logs showed the broker serving manifests/segments, but the browser player was turning stale session manifests, video element errors, or HLS fatal events into terminal UI.
- **Implementation**:
  - Added bounded video-element recovery in `VideoPlayer` before showing the terminal playback overlay.
  - Added bounded watch-page broker session recycling when the P2P player reports a startup failure.
  - Forwarded browser `Range` requests through `/api/stream/segment` and preserved upstream `Content-Length`, `Content-Range`, `Accept-Ranges`, and exposed range headers for Chrome/HLS.js.
  - Disabled noisy production HLS debug logging.
- **Verification**:
  - Ran focused ESLint and TypeScript checks for the watch/player/segment route changes; only existing React compiler set-state-in-effect warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Confirmed public FOX Sports 2 watch route returns 200 and the public P2P catalog includes `FOX Sports 2 HD`.
  - Confirmed a signed public `/api/stream/segment` range request returns `video/mp2t`, `Content-Length`, `Content-Range`, `Accept-Ranges`, and exposed range headers.
  - Browser-smoked the FOX Sports 2 watch page: after reload it stayed out of the `Playback unavailable` overlay with the P2P broker session active; the Codex in-app browser still did not expose decoded dimensions, so final real-browser Chrome/Safari verification remains required.

## 2026-06-13: P2P Guide Proxy Must Restart Always
- **Decision**: The homelab `fotty-p2p-proxy` container and deploy script should use Docker `restart: always`, not `unless-stopped`.
- **Why**: The public TV Guide can render `0 shown / 0 mapped` when the proxy is down even if the web app and EPG file are healthy. On June 13, the proxy had exited with code 137 and stayed down, causing `scraper.pixel-invoice.com/matches` to return 502 and the web P2P channel API to return zero rows.
- **Implementation**:
  - Restarted the live `fotty-p2p-proxy` container.
  - Updated the running container restart policy to `always`.
  - Updated `tools/p2p-proxy-deploy-homelab.sh` and `server/p2p-stack-updated.yml` so future proxy deploys keep the stronger restart policy.
- **Verification**:
  - Confirmed public `https://scraper.pixel-invoice.com/[URL_REDACTED] returned 188 channels after restart.
  - Confirmed public `https://fotty.pixel-invoice.com/[URL_REDACTED] returned 125 filtered channels.
  - Confirmed `FOX Sports 1 HD` and `FOX Sports 2 HD` are available P2P channels and map to `FoxSports1.us@HD` / `FoxSports2.us@HD`.
  - Confirmed the guide API returned 79 requested rows, 25 mapped channels, and 23 schedule-backed channels; browser hydration showed `28 shown / 28 mapped`.

## 2026-06-13: World Cup Flags And Results Provider Ownership
- **Decision**: Fotty Web's World Cup surface should render country flags from an explicit tournament team map, while automatic score/result ingestion should be owned by football data providers rather than watch-path providers.
- **Why**: National-team fixtures looked unfinished when country badges fell back to initials. Separately, the web World Cup tab was consuming StreameX/Streamed/P2P schedule and watch sources, which are useful for playback paths but not authoritative for tournament results, tables, or team metadata.
- **Implementation**:
  - Added a flag map for all 48 World Cup group teams and a `worldCupTeamFlag()` helper.
  - Preserved World Cup flags when seeded fixtures are replaced by provider rows.
  - Updated the shared team badge renderer so flag emoji display as local badges instead of being treated as remote image IDs.
  - Surfaced flags in the World Cup hero matchup, fixture calendar rows, and group table rows.
- **Verification**:
  - Ran focused ESLint for `WorldCupView`, `TeamBadge`, and `world-cup.ts`.
  - Ran TypeScript checks successfully.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Smoked public `/world-cup`, `/world-cup?tab=groups`, and `/world-cup?tab=schedule`; all returned 200 and rendered country flags with the current seeded result rows.
- **Follow-up**:
  - Wire a dedicated web World Cup results API to the existing football-data/API-Football provider stack so scores and standings update automatically instead of relying on fallback result seeds.

## 2026-06-12: Admin-Issued One-Time QR Login
- **Decision**: Fotty Web admin can issue a 15-minute, single-use QR login link for a selected PocketBase account.
- **Why**: Match-day onboarding often happens through WhatsApp or in-person setup. Users should be able to scan a code and enter Fotty without typing a temporary password, while avoiding permanent QR/session leakage.
- **Implementation**:
  - Added server-side one-time QR login records in `.data/qr-login-links.json`, storing only token hashes.
  - Added `/api/admin/login-links` for admin link generation and `/api/auth/qr/redeem` for public one-time redemption.
  - Added signed `provider: "qr"` Fotty sessions that work with entitlement refresh and protected watch APIs without exposing the user's PocketBase password.
  - Added `/login/qr` to redeem links client-side and store the normal Fotty web auth session.
  - Added a selected-account admin panel that shows a QR image, copyable link, and expiry.
- **Verification**:
  - Ran focused ESLint; only pre-existing dashboard React hook warnings remain.
  - Ran local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Generated a production QR link for `smoke@fotty.app`, redeemed it once, confirmed Plus entitlement resolves, and confirmed a second redemption fails with "already used."

## 2026-06-11: Admin User List Handles Empty PocketBase Responses
- **Decision**: Fotty Web admin should show local grants when PocketBase user listing succeeds but returns zero users while local grants exist.
- **Why**: Production had local Plus grants for test/smoke accounts, but the admin dashboard still rendered "No users found" because the PocketBase request no longer threw. It returned a successful empty list, so the earlier error-only fallback never ran. Follow-up investigation found the deeper cause: `POCKETBASE_ADMIN_TOKEN` was an expired PocketBase admin JWT, so the `users` collection rule filtered the request down to zero rows even though the PocketBase DB had 22 users.
- **Implementation**:
  - `/api/admin/users` now loads local grants after a PocketBase list and switches to local source when PocketBase reports `0` users and local grants are present.
  - The admin dashboard displays the fallback warning and clamps pagination to at least one page.
  - Rotated the PocketBase admin credential on the homelab, stored fresh admin auth env in the deploy environment, and redeployed `fotty-web`.
  - Added `getPocketBaseAdminTokenForRequest()` so server routes can refresh the PocketBase admin JWT from `PB_ADMIN_EMAIL`/`PB_ADMIN_PASSWORD` instead of relying on a pasted short-lived token.
  - Added the required PocketBase `role: "user"` field to admin-created users so account creation no longer fails with `Missing required value.`
- **Verification**:
  - Ran focused ESLint for the touched admin files; only pre-existing React hook warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Confirmed the live container returns `source: pocketbase`, `totalItems: 22`, `totalPages: 2`, and all expected PocketBase users from `/api/admin/users`.
  - Created and immediately deleted a temporary PocketBase user through the production `/api/admin/users` route to verify account creation end-to-end.

## 2026-06-11: Desktop Watch Path Errors Need Tokenized Playback Verification
- **Decision**: Treat `No verified watch path yet` reports as a playback/auth verification problem until the current browser bundle, watch-token handoff, manifest response, and actual video element state have all been checked.
- **Why**: Production stream prep was healthy, but a desktop tab could still show stale watch UI or a manifest `403` while the broker had peers and segments. Reloading onto the service-worker v17 shell restored the P2P HLS token handoff and changed BT Sport 2 from `Playback unavailable` to an active playing video.
- **Implementation**:
  - Preserved direct-event API errors through `useEventStreams` instead of replacing them with generic no-path copy.
  - Changed watch fallback headlines to distinguish session refresh, live access, broker/source failure, and true missing watch paths.
  - Bumped the service-worker shell to `fotty-shell-v17` and redeployed the public web container.
- **Verification**:
  - Confirmed public `sw.js` serves `fotty-shell-v17`.
  - Confirmed token-backed smoke access returns two UCI direct event streams and can create a BT Sport 2 P2P broker session.
  - Reloaded the public BT Sport 2 watch page in the browser and confirmed an active video element (`readyState=4`, `paused=false`, buffered, no media error).
  - Loaded the exact UCI Tour Auvergne URL and confirmed it renders a direct iframe plus `Try backup`/`Open feed`, two direct feeds, same-match P2P backups, and no console errors.

## 2026-06-11: Watch Failures Must Preserve Their Real Cause
- **Decision**: Fotty Web should not collapse broker, auth, access, network, and stale-client failures into the generic `No verified watch path yet` copy.
- **Why**: Desktop users were repeatedly reporting the same message even when production APIs were healthy. That made different failure classes indistinguishable and encouraged repeated one-off fixes instead of a reliable launch workflow.
- **Implementation**:
  - Changed the web API client to return specific broker failure messages for expired sign-in, missing live access, rate limit, broker failure, missing session, and device network failure.
  - Changed the P2P watch hook to surface the returned broker message instead of replacing it with generic no-path copy.
  - Changed direct-event unavailable state to show the actual stream lookup error.
  - Bumped the service-worker shell cache to `fotty-shell-v16` and made the PWA registration update/reload once when a new worker takes control, reducing stale desktop tabs after deploys.
- **Verification**:
  - Ran focused ESLint on `api.ts`, `useP2PBrokerSession.ts`, `WatchPlayers.tsx`, and `PWARegister.tsx`; no errors, with the existing React set-state-in-effect warning still present in the P2P hook.
  - Ran `npm run build:standalone`.
  - Deployed `fotty-web` to the homelab/public site.
  - Confirmed public `sw.js` serves `fotty-shell-v16`.
  - Confirmed the UCI direct event lookup returns two streams.
  - Confirmed public BT Sport 2 P2P broker session returns ready with playable segments.
  - Confirmed the browser-rendered BT Sport 2 watch page has an active video (`readyState=4`), peers/segments visible, and no console errors.

## 2026-06-11: Cloudflare Tunnel Outage Was Homelab Wi-Fi Loss
- **Decision**: Treat the Fotty homelab Wi-Fi link as a launch risk until the tunnel host is moved to wired networking, a second Cloudflare Tunnel connector, or a hosted deployment target.
- **Why**: Hours before World Cup traffic, all public hostnames (`fotty`, `scraper`, `p2p`, and `fotty-api`) returned Cloudflare 1033/HTTP 530. Local Fotty containers were healthy once SSH was reachable, but NetworkManager logs showed `wlp3s0` lost the AP at 12:00:15 AST, failed with `ssid-not-found` at 12:00:30, and reconnected at 12:13:31. `cloudflared` recovered at 12:13:56 after the Wi-Fi returned.
- **Implementation**:
  - Verified local services on the host: `fotty-web` on `127.0.0.1:3010`, `fotty-p2p-proxy` on `127.0.0.1:8006`, and the scraper route all returned locally.
  - Confirmed the public tunnel recovered and all key public routes returned HTTP 200.
  - Attempted to disable Wi-Fi power saving, but the SSH session lacks non-interactive sudo; the host still reports `Power save: on`.
- **Verification**:
  - Confirmed public `https://fotty.pixel-invoice.com/[URL_REDACTED] `/world-cup`, `/guide`, and `https://scraper.pixel-invoice.com/[URL_REDACTED] return HTTP 200.
  - Confirmed `cloudflared` has four registered edge connections after recovery.
  - Action for operator: on the Linux host, run `sudo iw dev wlp3s0 set power_save off` and `sudo nmcli connection modify "Digicel_5G_WiFi_Ep9r" 802-11-wireless.powersave 2`, or move the host to Ethernet.

## 2026-06-11: Direct Event Playback Needs Desktop Escape Hatches
- **Decision**: Fotty Web direct event watch pages should expose desktop-safe fallback controls on top of the event player and provide a cache-refresh recovery path when the watch route error boundary appears.
- **Why**: The UCI Tour Auvergne event returned valid direct StreameX embeds and same-match P2P alternates, but desktop users could still see a black/failed provider frame or `Stream page failed to load` while another device played the same event. The parent Fotty page cannot reliably inspect cross-origin embed playback state after the iframe loads.
- **Implementation**:
  - Added player-level `Try backup` and `Open feed` controls for direct event iframes, so desktop users can switch provider variants or open the provider as a top-level page when iframe playback stalls.
  - Added a watch error-boundary `Refresh app` action that clears Fotty shell caches, requests service-worker updates, and reloads the route.
  - Kept the existing match hub backup list and same-match P2P alternates as secondary recovery paths.
- **Verification**:
  - Confirmed the exact UCI event stream API returns two direct event variants for a paid smoke account.
  - Confirmed the signed-in watch page renders the event iframe, backup feed, and same-match P2P alternates in the in-app browser.
  - Ran focused ESLint with no errors; the pre-existing `react-hooks/set-state-in-effect` warning in `WatchPageClient` remains.
  - Ran `npm run build:standalone` successfully.
  - Deployed `fotty-web` successfully after the tunnel recovered.
  - Confirmed the public UCI event stream API returns two direct event variants after deploy.

## 2026-06-11: Desktop Web Playback Must Not Use Stale Service-Worker Chunks
- **Decision**: Fotty Web's service worker should not cache Next.js `/_next/` assets or RSC payloads, and desktop media-session integration must be optional so browser API differences cannot crash the watch route.
- **Why**: Desktop users could see `No verified watch path yet` or the `/watch` error boundary (`Stream page failed to load`) while mobile playback worked. The P2P broker and stream APIs were healthy, so the likely desktop failure modes were stale service-worker-held client chunks and browser-specific `MediaMetadata` support.
- **Implementation**:
  - Bumped `web/public/sw.js` to `fotty-shell-v15`.
  - Excluded `/_next/` assets and `_rsc` payloads from service-worker caching, leaving navigations network-first and only caching the small static shell asset set.
  - Wrapped `VideoPlayer` media-session metadata/action setup in feature checks and a `try/catch`.
  - Changed P2P watch unavailable copy to show the broker warm-up/failure message when available instead of hiding it behind generic copy.
- **Verification**:
  - Ran focused ESLint for `VideoPlayer` and `WatchPageClient`; no errors, with pre-existing React set-state-in-effect warnings still present.
  - Ran `npm run build:standalone`.
  - Deployed `fotty-web` to production.
  - Confirmed public `sw.js` serves `fotty-shell-v15` and excludes `/_next/`/`_rsc`.
  - Confirmed public watch route returns HTTP 200.
  - Confirmed paid smoke account can issue a watch token, load a P2P HLS manifest, and fetch a video segment through `/api/stream/segment`.

## 2026-06-11: Production Watch Test Account Grant
- **Decision**: The production web image should include a local Plus grant for `test@test.com` alongside the existing `smoke@fotty.app` playback smoke account until PocketBase/admin entitlement persistence is fully configured.
- **Why**: Manual watch testing was reaching the client gate with `Live access required` even after the Guide recovered, because the account session could exist while the server-side watch-access resolver had no paid entitlement to verify for that email.
- **Implementation**:
  - Added `local:test@test.com` with `entitlement: "plus"` to the ignored deploy seed `web/.data/admin-grants.json`.
  - Redeployed `fotty-web` so the running container includes the grant.
- **Verification**:
  - Confirmed the running `fotty-web` container has both `smoke@fotty.app` and `test@test.com` Plus grants.
  - Confirmed the public P2P channel feed still returns live channels after redeploy.

## 2026-06-11: TV Guide Requires Live P2P Proxy, Not Just Fresh EPG
- **Decision**: Fotty Web's `/api/p2p/channels` route should be dynamic and bypass Next fetch caching, while the homelab `fotty-p2p-proxy` must remain running in front of the scraper and EPG status endpoints.
- **Why**: The public TV Guide can show `0 shown` and `0 mapped` even when the EPG file is fresh if `fotty-p2p-proxy` is down. On June 11, the scraper was still auto-refreshing channels, but the proxy container had exited with code 137 six days earlier and Cloudflare was returning `502` for `scraper.pixel-invoice.com` and `p2p.pixel-invoice.com`.
- **Implementation**:
  - Restarted `fotty-p2p-proxy` on the homelab so `/matches` and `/epg/status` were reachable through the public tunnel again.
  - Changed `web/src/app/api/p2p/channels/route.ts` to `dynamic = "force-dynamic"`, `revalidate = 0`, and `cache: "no-store"` so an empty P2P response is not held by the web layer.
  - Updated `TVGuideView` to track channel loading separately from EPG mapping so the Guide shows an updating state while listings are being matched instead of briefly showing the empty-state copy.
  - Deployed `fotty-web` with `./tools/web-deploy-homelab.sh` after the focused route change.
- **Verification**:
  - Confirmed public `https://scraper.pixel-invoice.com/[URL_REDACTED] recovered with live channel rows.
  - Confirmed public `https://fotty.pixel-invoice.com/[URL_REDACTED] returned over 100 playable channels after deploy.
  - Confirmed public `https://fotty.pixel-invoice.com/[URL_REDACTED] maps representative channels such as Sky Sports Football, Sky Sports Main Event, ESPN, and Tennis Channel HD with exact guide rows.
  - Verified the deployed public Guide renders `25 shown`, `25 mapped`, and no empty-state message after reload.

## 2026-06-11: World Cup Hub Public Update
- **Decision**: Fotty Web's `/world-cup` hub should use URL-backed tabs, FIFA-football-only World Cup filtering, and live World Cup headline cards before public match-day traffic.
- **Why**: The first World Cup fixture traffic exposed three launch issues: unrelated "World Cup" sports such as darts could leak into the hub, client-only tabs were too fragile in Safari, and the Stories tab was showing product-planning copy instead of real football stories.
- **Implementation**:
  - Tightened `isWorldCupMatch` to require football/FIFA/soccer context and reject non-FIFA sports such as darts.
  - Changed the World Cup tabs to real route links: `/world-cup`, `/world-cup?tab=schedule`, `/world-cup?tab=groups`, `/world-cup?tab=stories`, and `/world-cup?tab=watch`.
  - Filtered the initial `/world-cup` payload to provider-confirmed World Cup rows instead of serializing the full all-sports feed.
  - Replaced static Stories cards with live `/api/football/headlines` cards for current FIFA World Cup football stories.
  - Deployed `fotty-web` to the homelab/public site with `./tools/web-deploy-homelab.sh`.
- **Verification**:
  - Ran focused ESLint for `WorldCupView`, `/world-cup/page`, and `world-cup.ts`.
  - Ran `npm run build:standalone` locally and remote Docker `next build` through the deploy script.
  - Verified `https://fotty.pixel-invoice.com/[URL_REDACTED] and all tab URLs return `200` with the expected section content.
  - Verified the public World Cup route and headline API return `NO_DARTS`.

## 2026-06-11: World Cup Hub Uses Published Fixture Seeds
- **Decision**: Fotty Web's `/world-cup` hub should load published 2026 FIFA World Cup group fixtures and groups from a deterministic seed list, then let provider feed matches replace seeded rows when real watch coverage appears.
- **Why**: The fixture draw is now public, but direct stream providers may not tag or expose every match yet. Users need trustworthy schedule, reminder, group, and guide paths immediately without Fotty pretending that unavailable broadcasts are playable.
- **Implementation**:
  - Added World Cup group/team data and opening fixture seeds to `web/src/lib/world-cup.ts`.
  - Converted fixture seeds into normal `ScrapedMatch` rows with `coverage: "unavailable"` so reminders work while watch buttons stay bounded by the existing broadcast window.
  - Merged seeded fixtures with provider World Cup matches by normalized team names and kickoff window to avoid duplicate rows once live providers catch up.
  - Replaced World Cup group placeholders with the actual group draw in `WorldCupView`.
- **Verification**:
  - Ran focused ESLint for `src/lib/world-cup.ts`, `src/components/WorldCupView.tsx`, and `src/app/world-cup/page.tsx`.
  - Ran `npm run build` successfully in `web`.

## 2026-06-03: Homelab EPG Heap Raised For Daily Refresh
- **Decision**: The homelab EPG cron remains the owner of Fotty TV guide refreshes, but the iptv-org Docker grabber now needs an 8GB Node heap.
- **Why**: The June 2 and June 3 scheduled jobs fired correctly but failed while saving the focused XMLTV output with `JavaScript heap out of memory`, leaving the public guide on the last successful June 1 file.
- **Implementation**:
  - Set `FOTTY_EPG_NODE_HEAP_MB=8192` in `/home/jelani/acestream/server/epg/epg.env` on the homelab.
  - Updated `server/epg/epg.env.example` so operators do not regress to the old 4096 MB value.
  - Added scheduled housekeeping so the refresh keeps a bounded number of logs and prunes old temp/backup files.
  - Set the homelab retention knobs to `FOTTY_EPG_LOG_KEEP=10`, `FOTTY_EPG_BACKUP_RETENTION_DAYS=7`, and `FOTTY_EPG_TEMP_RETENTION_DAYS=1`.
- **Verification**:
  - Confirmed crontab still has `0 4 * * * /home/jelani/acestream/server/epg/run_scheduled_refresh.sh # fotty-epg-refresh`.
  - Ran the scheduled refresh entrypoint manually; it completed in `00h 08m 28s`.
  - Confirmed `/data/epg/guide.xml` is dated `20260603`, `cached_body_bytes=3107706`, and `/epg/status` reports `ok=true`.
  - Confirmed the server has no EPG temp/backup leftovers, retains 10 refresh logs, and `/home/jelani/acestream` is at 13% disk usage.

## 2026-06-02: Shared Public Fallback States
- **Decision**: Fotty Web public pages should use shared fallback components for loading, empty, updating, signed-out, no verified stream, World Cup preparation, and data refresh states.
- **Why**: Paid-user and World Cup readiness requires every route to feel intentional even when live feeds, EPG, tables, or watch paths are unavailable. Blank panels, raw provider errors, and disappearing sections undermine trust.
- **Implementation**:
  - Added reusable fallback components and a bounded loading-timeout hook.
  - Applied product-quality states to Home, Live Board, Watch, TV Guide, Tables, World Cup Hub, and shared fixture lists.
  - Sanitized web auth/watch/provider failures so raw backend or broker errors are logged internally but not used as primary public copy.
  - Added `docs/audit/Fotty-Web-Fallback-State-Audit-2026-06-02.md`.
- **Verification**:
  - Ran `npm run build` successfully.
  - Smoked local production routes on port `3020`: `/`, `/swarm`, `/guide`, `/tables`, `/world-cup`, `/help`, `/welcome`, `/login`, `/settings`, and `/watch/test-source`.
  - Deployed `fotty-web` to the homelab and smoked the same public routes on `https://fotty.pixel-invoice.com`./[URL_REDACTED]

## 2026-06-02: Public Copy Must Sound Production-Ready
- **Decision**: Public Fotty Web copy should avoid prototype, MVP, concept, demo, experimental, and vague coming-soon language.
- **Why**: Fotty is being positioned for paid users and World Cup match-day traffic. Public surfaces need to sound calm, useful, and trustworthy even when data is updating or watch paths require sign-in.
- **Implementation**:
  - Updated Home hero badge, subtitle, and CTAs to `Fotty Match Hub`, `Open Live Board`, and `View World Cup Hub`.
  - Replaced guide loading, empty fixture, unavailable content, watch failure, and stream availability copy with intentional update/fallback language.
  - Removed the Settings link to internal signal tooling and renamed protected signal-console copy away from MVP wording.
  - Renamed lower-confidence stream-group internals away from `experimental`.
- **Verification**:
  - Scanned `web/src` for public prototype-style phrases; remaining hits are literal protected route paths such as `/mvp` and `/demo`.
  - Ran `npm run build` successfully.

## 2026-06-02: Web Production Trust And World Cup Readiness Pass
- **Decision**: Public Fotty Web pages should no longer present prototype language or invented fixture placeholders, and World Cup surfaces should show intentional updating states until official feed data is confirmed.
- **Why**: Paid users need trust that Home, Live Board, TV Guide, Tables, Watch, and World Cup Hub are reading the same match-day truth. Placeholder names such as `Home v Away`, MVP-style labels, and terse guide gaps make the service feel unfinished.
- **Implementation**:
  - Added a shared fixture normalization layer that treats provider placeholders as updating data and parses trustworthy fixture titles into team labels.
  - Normalized `/api/matches` output before public pages consume it.
  - Removed server-formatted kickoff text from match subtitles so pages format canonical `startsAt` timestamps in the viewer browser timezone.
  - Replaced public prototype copy and improved Home, TV Guide, Watch access, and World Cup fallback states.
  - Documented the route-by-route launch audit in `docs/audit/Fotty-Web-Production-Audit-2026-06-02.md`.
- **Verification**:
  - Ran `npm run build` successfully.
  - Started a fresh production server on port `3020` and confirmed `/`, `/swarm`, `/guide`, `/tables`, `/watch/test`, `/world-cup`, `/login`, and `/settings` all returned HTTP `200`.
  - `npm run lint` remains blocked by a pre-existing `any` in `web/e2e/prod-playback.spec.ts`.

## 2026-06-01: Direct Event Playback Must Use Real Provider Streams Only
- **Decision**: Direct event watch links should use unique event ids for the route, while P2P channel watch links continue to use AceStream CIDs. The web stream lookup should not fabricate a legacy embed when provider APIs return no playable variants unless an explicit fallback flag is enabled.
- **Why**: Multiple direct fixtures can share the same provider coverage CID, so routing event pages by CID makes playback state and fallback matching ambiguous. Fabricated embeds also made the UI report "feeds" and "stream ready" while the browser was handed a dead HLS manifest.
- **Implementation**:
  - Updated shared client and server watch-link builders to route event playback by `match.id`/`eventSource.id` before falling back to `cid`.
  - Gated the legacy `embedsports` direct-stream fallback behind `FOTTY_ENABLE_LEGACY_EMBED_FALLBACK=true`.
- **Verification**:
  - Ran focused ESLint for the changed watch-link and stream lookup files.
  - Ran `./tools/web-build-local.sh`.
  - Deployed `fotty-web` to the homelab and confirmed the public web container and P2P stack are up.

## 2026-06-01: Immediate P2P Broker Session Return
- **Decision**: Fotty Web should return a P2P broker session to the browser immediately, then let the watch page poll that session until it is ready or explicitly failed.
- **Why**: Cold AceStream startup can take longer than the first web timeout. Waiting inside `/api/stream/session` left the browser without a session id to poll, so the UI could mark a source unavailable while the homelab broker was still warming successfully.
- **Implementation**:
  - Changed `web/src/app/api/stream/session/route.ts` to call `createBrokerSession` directly instead of `createAndWarmBrokerSession`.
  - Extended the watch-page warmup window and allowed a previously failed UI state to recover when session polling later reports ready segments, a ready manifest, or active status.
- **Verification**:
  - Created a public broker session for the reported SkySP PL CID; it became ready with peers and validated segments after cold startup.
  - Ran focused ESLint for the changed API/watch files; only existing React hook warnings remain.
  - Ran `./tools/web-build-local.sh`.

## 2026-06-01: Server-Owned EPG Refresh Reliability
- **Decision**: The Fotty P2P guide refresh should run from the homelab cron job, with the EPG generator given an explicit larger Node heap.
- **Why**: The guide must refresh even when Codex usage is unavailable. The scheduled job existed, but the iptv-org generator was failing with `JavaScript heap out of memory`, leaving the public guide stuck on an old `guide.xml`.
- **Implementation**:
  - Updated `server/epg/refresh_epg.sh` so native and Docker EPG grabs use `NODE_OPTIONS=--max-old-space-size=${FOTTY_EPG_NODE_HEAP_MB:-4096}`.
  - Documented `FOTTY_EPG_NODE_HEAP_MB` in `server/epg/epg.env.example`.
  - Applied the script to the homelab and set `FOTTY_EPG_NODE_HEAP_MB=4096` in the server `epg.env`.
- **Verification**:
  - Confirmed the homelab crontab has `0 4 * * * /home/jelani/acestream/server/epg/run_scheduled_refresh.sh # fotty-epg-refresh`.
  - Ran the scheduled refresh manually on the server; it completed and published a fresh `guide.xml` dated `20260601`.
  - Confirmed public `/epg/status` reads `/data/epg/guide.xml` with `cached_body_bytes=3080550` and preview date `20260601`.

## 2026-05-31: Fotty 2.0 Live Board Visual Alignment
- **Decision**: The web `/swarm` live board should use the same premium match-day language as the redesigned home page, while keeping playback behavior unchanged.
- **Why**: A premium home page followed by an older live board makes the product feel inconsistent. The live board is a core paid-user surface, so it needs clearer hierarchy, stronger trust signals, and less intrusive install messaging.
- **Implementation**:
  - Updated the live board command strip, featured match panel, compact P2P source panel, and backup guide rows with cinematic dark styling and clearer source/status hierarchy.
  - Kept live board league selection all-first instead of quietly defaulting back to Premier League.
  - Limited the PWA install banner to help/onboarding/settings pages so it does not cover core match discovery screens.
- **Verification**:
  - Ran focused ESLint for `SwarmView` and `AppChrome`.
  - Ran `./tools/web-build-local.sh`.
  - Captured local Playwright screenshots for mobile and desktop `/swarm` match and P2P source views.

## 2026-05-24: EPG-Backed P2P Match Recovery On Web Watch Pages
- **Decision**: Event watch pages should restore same-match P2P options by matching P2P channels against verified EPG now/next listings, not only channel names.
- **Why**: Direct event embeds can fail even when the matching P2P channel is available. Channel labels like `SkySP PL` do not contain team names, so title-only matching missed the useful P2P fallback that previously made the watch page resilient.
- **Implementation**:
  - The watch page now fetches verified P2P EPG guide rows alongside the P2P catalog and scores channels using current programme/team/title matches.
  - P2P alternatives are shown above direct backup feeds so users can reach the broker player quickly when provider embeds fail.
  - Direct feed copy now says provider playback is still estimated and may require another backup or P2P route.
- **Verification**:
  - Ran focused ESLint for the watch page and stream hub files; only existing React set-state-in-effect warnings remain.
  - Ran `./tools/web-build-local.sh`.
  - Deployed to homelab and ran public smoke against `https://fotty.pixel-invoice.com`./[URL_REDACTED]

## 2026-05-23: World Cup Hub As A First-Class Web Surface
- **Decision**: Fotty Web should have a dedicated `/world-cup` hub and primary navigation entry ahead of the 2026 FIFA World Cup.
- **Why**: The tournament is large enough to become a daily habit loop: users need live matches, next kickoffs, reminders, stories, groups, guide links, and watch paths without hunting through general football filters.
- **Implementation**:
  - Added `web/src/app/world-cup/page.tsx`, `web/src/components/WorldCupView.tsx`, and `web/src/lib/world-cup.ts`.
  - Promoted World Cup into the primary nav and moved Teams under More to keep the mobile tab bar compact.
  - Seeded tournament milestones, host-region context, story cards, groups placeholder cards, and a watch-readiness checklist.
  - Reused the Fotty match feed, reminder buttons, watch-link builder, and pull-to-refresh so real World Cup fixtures auto-promote when the feed includes them.
  - Added `/world-cup` to web smoke coverage.
- **Verification**:
  - Ran focused ESLint for the new World Cup files and nav changes.
  - Ran `./tools/web-build-local.sh`.
  - Deployed to homelab and ran public smoke against `https://fotty.pixel-invoice.com`,/[URL_REDACTED] including `/world-cup`.

## 2026-05-20: Deterministic Web Timezone For Hydration
- **Decision**: Fotty Web should render match time labels with an explicit `America/Port_of_Spain` timezone instead of relying on server or browser local timezone.
- **Why**: Desktop browsers in different timezones could hydrate different match-time text from the server-rendered HTML, producing React hydration error #418 and making the public site feel broken on some PCs.
- **Implementation**:
  - Added shared Fotty locale/timezone constants in `web/src/lib/live.ts`.
  - Updated match/feed/server labels and key stream-guide timestamps to use those constants.
  - Set `sw.js` to `no-store` and bumped the service-worker shell cache so public deploys update reliably.

## 2026-05-20: Web Event Embed Switching Safety
- **Decision**: Fotty Web event playback should keep provider embeds in their original provider origin for now, while sandboxing the iframe and forcing a full iframe reload when users switch feeds.
- **Why**: A Fotty-hosted embed wrapper reduced popup risk but changed the provider environment enough to stop playback. The Mac app still has stronger native extraction; web should first preserve playback and make backup switching reliable.
- **Implementation**:
  - Removed the Fotty-hosted embed wrapper from the active event player path.
  - Kept provider embeds sandboxed without popup permission.
  - Added a selected-stream key to the event iframe so tapping Backup Stream 1/2/etc. remounts the iframe instead of appearing to do nothing.

## 2026-05-19: P2P Web Stream Visibility and 416 Probe Fallback
- **Decision**: Web P2P channel lists should preserve every distinct CID, even when multiple feeds share the same channel display name.
- **Why**: Collapsing by channel title hid alternate P2P streams that users need when one feed is cold, unstable, or region-specific.
- **Implementation**:
  - Changed `/api/p2p/channels` dedupe to only remove exact duplicate CIDs.
  - Added a broker manifest probe fallback for segment servers that reject range probes with HTTP 416, retrying once without `Range` before marking the manifest unavailable.
  - Hardened the P2P proxy scraper cache so a pinned-only internal refresh cannot overwrite a larger healthy Redis channel catalog from the standalone scraper.

## 2026-05-15: Web Monetization Foundation
- **Decision**: Fotty Web monetization should start with identity, entitlements, sponsor placements, and soft premium convenience rather than hard-blocking match discovery.
- **Why**: The MVP needs a revenue path without damaging the match-first experience or delaying playback.
- **Implementation**:
  - Added a local entitlement model for Free, Fotty Plus, Match-Day Supporter, and Fotty Collab.
  - Added `/subscribe` with checkout URL support and a local MVP activation fallback.
  - Added sponsored slots on Home, P2P sources, and Watch surfaces that disappear for paid access.
  - Added Settings and top-bar access cues, plus login account/access copy.
  - Soft-gated the P2P "Verified" convenience filter behind Plus while keeping browsing available.

## 2026-05-15: Productized P2P Guide Controls
- **Decision**: The P2P backup page should expose guide-aware filters and trust signals before users open a source.
- **Why**: The page needs to feel like a viable product surface, not a raw list of streams. Users should be able to quickly choose between all sources, channels with current guide data, mapped guide channels, and playback-verified sources.
- **Implementation**:
  - Added All sources, On now, TV guide, and Verified controls to the P2P source page.
  - Marked guide-backed rows as "Verified guide" and non-mapped rows as "Channel-only backup."
  - Scoped featured/recommended rows to the active P2P guide filter so the page does not contradict the selected view.

## 2026-05-14: Verified P2P EPG Mapping
- **Decision**: Fotty Web must only show P2P TV guide data from verified channel identity mappings, not fuzzy channel-name matching.
- **Why**: Fuzzy matching made unrelated channels share listings, including Sky Sports Cricket showing football programming. A wrong guide is worse than no guide.
- **Implementation**:
  - Added `server/epg/p2p_epg_map.json` as the explicit Fotty P2P channel to XMLTV ID map.
  - Updated `/api/epg/guide` to return guide data only for `confidence=verified` mappings.
  - Updated the EPG refresh filter to build a focused channel list from verified XMLTV IDs.
  - Refreshed `server/epg/guide.xml` with separate Sky Sports Cricket, Sky Sports Football, Sky Sports Arena, ESPN/ESPN2, Poland, Germany, and Russia channel identities.

## 2026-05-14: Web Notifications and PocketBase MVP Schema
- **Decision**: Add browser reminder notifications for saved matches and make the required PocketBase web write collections explicit.
- **Why**: Team tracking needed a concrete reminder payoff for the MVP, while PocketBase setup needed exact collection targets instead of vague follow-up work.
- **Implementation**:
  - Added an in-browser reminder notifier that fires saved match reminders while Fotty is open.
  - Added notification permission controls to the Team Alerts page.
  - Added PocketBase write-target visibility to MVP Signals.
  - Documented the `team_follows`, `match_reminders`, `partner_inquiries`, and `support_pledges` web schema in `docs/PocketBase-Web-MVP-Schema.md`.

## 2026-05-14: Web PocketBase Sync Bridge
- **Decision**: Web MVP writes should attempt real PocketBase sync when the browser has a PocketBase-backed session, while preserving local-first behavior for test sessions.
- **Why**: iOS already uses PocketBase, and web should join that backend instead of remaining a purely local prototype.
- **Implementation**:
  - Added `/api/pocketbase/auth` for PocketBase user auth via `users/auth-with-password`.
  - Extended web auth sessions with optional PocketBase token/userID/provider fields.
  - Added `/api/pocketbase/sync` to sync team follows, match reminders, Collab inquiries, and support pledges to PocketBase collections.
  - Updated local storage helpers to write locally and then attempt background PocketBase sync.
  - Added smoke coverage for PocketBase auth/sync route behavior without a session.

## 2026-05-14: Web MVP Completion Pass
- **Decision**: Treat the web MVP as complete for local validation once the core product loops are functional and externally-blocked production switches are explicit.
- **Why**: Fotty needs a usable MVP now while real auth, payment checkout, browser push, and PocketBase write-sync remain separate integration tasks.
- **Implementation**:
  - Hardened watch-page direct stream loading with bounded lookup failure states and clearer unavailable-source actions.
  - Improved search scoring so exact team/title fixture matches rank above broad channel text.
  - Moved Collab inquiries and support pledges into typed shared storage helpers, ready to map to PocketBase records.
  - Added production-switch visibility to `/mvp` for PocketBase sync, payment links, real auth, and browser push.
  - Re-ran lint, production build, standalone prep, smoke tests, and browser checks for search/watch.

## 2026-05-14: Web MVP Product Loops
- **Decision**: The web MVP should expose the core loops directly: tracked-team personalization, Collab inquiries, support intent, and local product signals.
- **Why**: Fotty’s MVP needs to feel viable as a product, not only a match list. Users should see value from tracking teams, and builders should see whether Collab/support loops are being exercised.
- **Implementation**:
  - Added a Home “For Your Teams” section that appears when teams are tracked and surfaces matching fixtures with reminder actions.
  - Added `/mvp` as a local MVP Signals console for tracked teams, Collab inquiries, support pledges, and recent local events.
  - Linked MVP Signals from Settings and added `/mvp` smoke coverage.
  - Verified the loop by tracking a team, saving a Collab inquiry, and confirming both appear in MVP Signals.

## 2026-05-14: Collab as MVP Product Pillar
- **Decision**: Fotty Collab should be a first-class web MVP surface, not only a support-page option.
- **Why**: The MVP needs a viable product path beyond individual tips: venues, fan communities, sponsors, and clubs can use Fotty as a practical match-day hub.
- **Implementation**:
  - Added `/collab` with Watch Party Kit, Community Hub, Sponsor Placement, and Local Club Pilot package cards.
  - Added a collab inquiry workflow that captures organization, contact, region, audience size, match focus, and use case, then stores the inquiry locally.
  - Added `collab_inquiry_saved` analytics and smoke coverage for `/collab`.
  - Linked Collab from Home, Support, Settings, and the desktop top bar so it behaves like an MVP pillar.

## 2026-05-14: Functional Web Support Flow
- **Decision**: The web Support page should work as an interactive support flow before payment infrastructure is fully configured.
- **Why**: Static “Register interest” cards did not feel usable enough for monetization testing, and Fotty needs to validate support intent while external checkout links are still optional.
- **Implementation**:
  - Replaced passive support links with selectable support paths and a checkout panel.
  - Added monthly/one-time amount selection, custom amount, contact, and note fields.
  - Saved local pledges/inquiries to browser storage when payment links are absent, while keeping external payment URL support through environment variables.
  - Added local `support_pledge_saved` analytics and updated smoke coverage for the functional support funnel.

## 2026-05-14: Web PocketBase Team Badges
- **Decision**: The web `/api/matches` route should enrich fixture teams with `sports_teams.badge_url` from PocketBase before falling back to schedule-provided badges or initials.
- **Why**: The web match cards should share the same metadata source of truth as iOS instead of relying only on streamed schedule badge tokens.
- **Implementation**:
  - Added server-side PocketBase `sports_teams` badge fetching in `web/src/app/api/matches/route.ts`.
  - Normalized team names and short names into a lookup map, including common diacritics, so fixtures can resolve badges before rendering.
  - Added a smoke check that `/api/matches` includes at least one PocketBase-backed team badge URL.

## 2026-05-14: Web Team Alerts & Interest Routing
- **Decision**: Web should add local team tracking before full push/account notification infrastructure, and support registration interest should route into contextual feedback rather than a generic form.
- **Why**: Users need an obvious way to tell Fotty which teams matter now, while monetization links need to capture intent cleanly before payments and entitlements are fully wired.
- **Implementation**:
  - Added local tracked-team storage, a `/teams` Team Alerts page, settings entry, Home quick link, and featured-match Track buttons.
  - Added `track_team_click` local analytics for follow/unfollow actions.
  - Routed Support fallback CTAs to `/feedback?intent=...` and added Supporter interest/Partnership feedback categories with registration-interest context.
  - Extended the web smoke script to cover `/teams` and the support interest paths.

## 2026-05-14: Web Startup Load Reduction for Testing
- **Decision**: The web home and live board pages should render lightweight shells and fetch live feeds from the browser, instead of importing API route handlers during server render.
- **Why**: Local browser testing exposed a startup stability risk when page render, provider fan-out, hydration, and client refetch happened together.
- **Implementation**:
  - Removed server-side live feed preloading from `web/src/app/page.tsx` and `web/src/app/swarm/page.tsx`.
  - Switched the web dev script to `next dev --webpack` for a calmer local testing loop while Next 16/Turbopack behavior is evaluated.
  - Pointed `npm start` at the standalone server because `next start` warns when `output: "standalone"` is enabled.

## 2026-05-14: Web Match-Day Parity Pass
- **Decision**: Web match cards and watch pages should mirror the iOS match-day model: scoreboard-first cards, status/source badges, and broadcast sources below the player.
- **Why**: The web app is becoming a usable Fotty client, not only a support/PWA shell, so the core live match experience needs to feel familiar to iOS users.
- **Implementation**:
  - Added a shared `MatchScoreboardCard` web component for Home and Live board match presentation.
  - Replaced older rail/list match cards with iOS-like league/status, team badge, score/VS, source count, and action layout.
  - Added a `Broadcast Sources` section below the web player for direct source switching and clearer P2P source status/change-source affordance.
  - Made football the default web lens by boosting football fixtures in feed ranking, preferring football for the Home featured match, and defaulting the Live board sport filter to Football when available.
  - Replaced the web-style Home hero with a compact Match Center surface and Arena/Insights/Highlights chips that more closely match the iOS MatchHub structure.

## 2026-05-14: Web Support Funnel Before Payments
- **Decision**: Monetization on web should start as a visible support funnel, not a paywall around match discovery or playback.
- **Why**: Fotty needs a monetization path, but the live sports experience should stay match-first while payment links and account entitlements are still being wired.
- **Implementation**:
  - Added a visible Support action to the desktop top bar and a Home support card.
  - Converted the Support page from a conditional "coming soon" page into three always-visible paths: Match-Day Supporter, One-Time Boost, and Venue or Partner.
  - Support actions use configured support/payment links when available and fall back to email or Feedback registration interest when links are not configured.

## 2026-05-14: Web Stability Smoke Tests & Local Event Signals
- **Decision**: Start web hardening with a zero-dependency smoke script and local product/revenue event capture before adding heavier analytics infrastructure.
- **Why**: The web app needs fast confidence checks around fragile routes and needs early signal on support/watch intent before paid account entitlements are built.
- **Implementation**:
  - Added `npm run smoke` via `web/scripts/smoke-web.mjs` to check core routes, support funnel copy, login copy, and football-first feed ordering.
  - Added `trackEvent` in `web/src/lib/analytics.ts`, storing the latest local events in browser localStorage.
  - Wired events for login attempts, watch-match clicks, support funnel clicks, and source-change clicks.

## 2026-05-10: Fast-First VOD Resolution
- **Decision**: Movie and TV playback should return the first native-capable stream instead of waiting for several mirrors.
- **Why**: The resolver was waiting for up to 5 sources while slower providers held 45-second extraction windows, causing long "Finding streams..." delays even after a usable stream had been found.
- **Implementation**:
  - `ContentResolutionService` now cancels provider races after the first VOD source.
  - VOD provider extraction timeouts are bounded to 7-15 seconds by provider.
  - `WebViewRenderer.extractSources` is cancellation-aware so cancelled provider races stop their WebView work promptly.

## 2026-05-10: VOD Playback Gate & Fallback Repair
- **Decision**: Release builds for the standard Fotty target compile with `FOTTY_FULL_ACCESS`; ReviewSafe builds compile with `APP_REVIEW_SAFE`.
- **Why**: Standard Release was falling through to runtime review mode by default, which disabled on-demand movie/TV playback unless a remote integrity check unlocked it.
- **Implementation**:
  - Added explicit compile conditions to both `project.yml` and `Fotty.xcodeproj`.
  - Corrected the movie WebView fallback route from malformed `vidsrc.net/embed/{id}` to `vidsrc.net/embed/movie/{id}`.
  - Added VOD fallback candidates for `vidsrc.to`, `vidsrc.me`, and `multiembed.mov` for both movie and TV episodes.

## 2026-05-10: VOD Stability & Platform Alignment (v1.8.1)
- **Decision**: Formally separate Android (Sports-Only) and iOS (Sports + VOD) project scope in project memory.
- **Decision**: Implement "Handoff Quiescence" in WebViewRenderer.
- **Why**: Prevent the "Infinite Pause/Play" loop caused by the auto-clicker continuing to tap the screen after the video has already started.
- **Implementation**:
    - Scraper now stops all click/tap activity as soon as `video.duration > 0` is detected.
    - Added text-based detection for "WATCH NOW" and "DOWNLOAD" buttons to bypass server gates faster.
    - Expanded sniffer to catch obfuscated `vplayer` and `playlist` URLs.

## 2026-05-09: Playback Pipeline Hardening (v1.6)
- **Decision**: Reduce pre-flight resolution timeouts from ~60s to ~20s.
- **Why**: User was experiencing "cascading timeouts" where the resolution layer took so long that the player never started.
- **Implementation**: 
  - Reduced `StreamWebExtractor` timeouts to 8s.
  - Reduced `URLSession` resource timeouts to 8s.
  - Reduced individual source validation to 5s.
  - Reduced AVPlayer readiness timeout to 7s.
- **Decision**: Implement a "Staggered Parallel Race" for stream resolution.
- **Why**: To achieve sub-10s startup times by racing Web sources against P2P backups, while preventing redundant resource usage once a stream is successfully playing.
- **Implementation**: 
  - Web track starts at `T+0`.
  - P2P track starts at `T+2s`.
  - First successful session cancels all other pending resolution tasks to preserve battery and data.
  - User requested **explicitly** to avoid background monitoring of secondary sources to keep logic "simple and fail-fast" unless reliability issues arise.

## 2026-05-09: Branding Cache-Buster Removal
- **Decision**: Remove the URL-stripping logic in `TeamBrandService`.
- **Why**: It was incorrectly removing required ESPN CDN query parameters, causing logos to "ghost" (disappear).
- **Implementation**: Replaced `URLComponents` manipulation with a safe cache-busting append logic.

## 2026-05-07: PocketBase Migration
- **Decision**: Shift to self-hosted PocketBase for all sports metadata.
- **Why**: Eliminate TheSportsDB rate limits and improve logo accuracy for leagues like NBA, WNBA, and MLB.
- **Implementation**: Added `PBSportsTeam` hardening and manual patch scripts (`fix_missing_wnba.py`).

## 2026-05-01: Broadcast Sources as Primary Switching UI
- **Decision**: Stream changes, including P2P, should happen from the “Available Broadcast Sources” section below the player.
- **Why**: The player chrome should stay focused on playback controls. Users need one obvious place to switch streams.
- **Implementation**: Removed source-switch controls from player chrome; error overlay points back to broadcast source area.

## 2026-04-28: Early Autoplay Arming
- **Decision**: Request playback immediately after handing an `AVPlayerItem` to AVPlayer, then again after readiness.
- **Why**: Some live streams do not start if the app waits until the item is fully ready.
- **Implementation**: Added `requestPlaybackStart` helper in `LivePlayerViewModel`.

## 2026-04-25: Web Embed Video-Level Nudging
- **Decision**: Web embed autoplay should directly nudge detected `<video>` elements in addition to clicking play buttons.
- **Why**: Some embed players ignore or hide normal play buttons.
- **Implementation**: Added direct `video.play()` kick with `playsinline` attributes via Javascript injection.

## 2026-05-09: Appearance Section Consolidation (v1.6)
- **Decision**: Remove the entire "Appearance" section from Settings, including the "Theme Mode," "Compact Mode," and "Reduce Motion" toggles.
- **Why**: These were non-functional placeholders. Removing them ensures the v1.6 Settings Hub is 100% reliable and only contains features that are fully implemented.
- **Implementation**: 
  - Hardcoded `.preferredColorScheme(.dark)` in `FottyApp.swift`.
## 2026-05-09: Cloud-First Strategy (Roadmap v1.7)
- **Decision**: Prioritize PocketBase synchronization for User Profiles and Playback Progress.
- **Why**: To enable a seamless multi-device experience. Users should be able to start a match or movie on an iPhone and continue on an iPad/Mac without losing progress.
- **Implementation**: Will utilize the `SocialCloudStore` and new `CinemaSyncService`.

## 2026-05-09: Notification Core Implementation (v1.6)
- **Decision**: Implement local-only notifications driven by a score-diffing engine.
- **Why**: Provides immediate value for goals and kickoffs without the complexity of a push-notification backend for the initial release.
- **Implementation**: 
  - `NotificationManager` handles `UNUserNotificationCenter` permissions.
  - `LiveScoreService` performs "snapshot diffing" on every poll to detect goals and status changes.
  - Integration with **Spoiler Protection** to mask scores in alert banners.

## 2026-05-09: Actor-Centric Search Implementation (v1.8)
- **Decision**: Re-prioritize v1.8 (Discovery) over v1.7 (Cloud Sync) based on user preference.
- **Why**: Deepening the media catalog provides immediate engagement value.
- **Implementation**:
  - Expanded `TMDBService` to fetch biographical data and combined filmography credits.
  - Added `ActorProfileView` with glassmorphic design and sorted media grids.
  - **UX Refinement**: Transitioned from horizontal scrolls to a **3-column high-density vertical grid** with segmented tabs (Movies/TV) to optimize searchability for large filmographies.
  - **Deep Discovery Loop**: Implemented navigation links from the `MediaDetailView` cast section back to the `ActorProfileView`, enabling circular discovery.
  - Updated `MediaType` enum to support `.person` and ensured exhaustive switch handling in playback and detail views.

## 2026-04-20: Native PiP & Live Activity Support
- **Decision**: Fotty should support Picture in Picture and Live Activities/Dynamic Island where system support allows.
- **Why**: Live sports users expect app minimization without losing playback; adds a premium "native" feel.
- **Implementation**: Integrated `AVPlayerLayerView` PiP bridge and `FottyLiveActivityExtension`.

## 2026-05-10: Fast VOD Native Startup With Web Fallback Kick
- **Decision**: VOD resolution should stop after a small native failover set and embedded web fallback should repeatedly trigger provider play overlays.
- **Why**: Waiting on every mirror made movies/shows slow to start, while some providers could land on a black web player with a visible play overlay and no playback.
- **Implementation**:
  - Cancel provider extraction once at least two native-playable VOD sources are found.
  - Tighten provider extraction timeouts so slow mirrors do not dominate startup.
  - Add cancellation cleanup for WebView extraction.
  - Expand embedded player auto-kick to coordinate taps, visible play/server labels, and repeated short retries before giving up.

## 2026-05-10: VOD Web Fallback Touch Handoff
- **Decision**: Web fallback hints must not cover the whole player surface, and WPlay shell fallback should not loop on a loading frame.
- **Why**: On iPhone, the bottom hint sheet could intercept the real touch it asked the user to perform, while the first WPlay shell candidate could keep retrying instead of advancing.
- **Implementation**:
  - Moved fallback candidates to direct provider routes before the WPlay shell.
  - Added a bounded WPlay shell retry so loading frames advance to the next candidate.
  - Added a Start action that sends a user-initiated playback kick without reloading.
  - Set the WKWebView user agent and direct-provider referers consistently.

## 2026-05-11: Full-Screen VOD Fallback Presentation
- **Decision**: VOD web fallback must use full-screen presentation instead of an iOS sheet.
- **Why**: The rounded sheet presentation constrained the provider player and made a blank player state look like a touch-gate issue.
- **Implementation**:
  - Replaced the web fallback sheet with a full-screen cover.
  - Replaced premature Start/Retry prompts with a non-blocking candidate status while providers are still cycling.
  - Kept Start/Retry only for final fallback failure once candidate cycling has exhausted.

## 2026-05-14: Fresh Focused P2P EPG for Fotty Web
- **Decision**: Fotty web should use a fresh, focused XMLTV guide for P2P sports channels instead of keeping a stale full guide in the repo workspace.
- **Why**: The P2P channel guide is only useful if it tells users what is on now/next. The old local `server/epg/guide.xml` was stale and unnecessarily large.
- **Implementation**:
  - Added `server/epg/filter_fotty_p2p_channels.py` to generate a focused sports/P2P channel list from the upstream guide data.
  - Updated `server/epg/refresh_epg.sh` to rebuild that focused channel list and refresh `server/epg/guide.xml`.
  - Added a daily local automation named "Refresh Fotty P2P TV Guide" to keep the guide fresh.
  - Updated the web EPG API to prefer the fresh local guide in development and to match channel ids that carry real programme rows.
- **Verification**:
  - Deleted the stale guide and generated a fresh 3.7 MB `guide.xml` dated `20260515`.
  - Confirmed the API returns now/next listings for Sky Sports Main Event and ESPN.
  - Rebuilt standalone web and ran the smoke suite successfully.

## 2026-05-20: DirecTV-Style P2P Guide for Fotty Web
- **Decision**: Fotty web should expose a real grid-style TV guide for P2P channels at `/guide`, using the existing XMLTV EPG as a schedule window instead of only showing now/next cards.
- **Why**: The previous guide was only semi-useful for discovery. Users need to scan many channels across time, filter by region, search, and jump straight into playback.
- **Implementation**:
  - Extended `POST /api/epg/guide` with `windowStart` and `windowHours` so the API can return overlapping programmes for a bounded grid window.
  - Added `TVGuideView` with sticky channel rows, half-hour time slots, search, region filters, previous/now/next controls, and direct Watch links.
  - Added `/guide` and promoted it into the web bottom navigation.
- **Verification**:
  - Confirmed the homelab EPG cron exists at `0 4 * * *` via `/home/jelani/acestream/server/epg/run_scheduled_refresh.sh`.
  - Confirmed the deployed EPG proxy reports a fresh local guide at `/data/epg/guide.xml` with cached bytes `3438328`.
  - Deployed `fotty-web:guide-test` as `fotty-web:latest`; public `/guide` returned HTTP 200.
  - Smoke-tested the deployed local API with 164 P2P channels, 78 guide rows for the first 80 channels, 27 exact EPG matches, and 187 scheduled programmes in the current four-hour window.

## 2026-05-20: US/UK-Focused P2P Guide Catalog
- **Decision**: Fotty Web should hide Poland and Russia P2P channels from the web-facing guide/catalog and prioritize US/UK sports channels in ordering and discovery.
- **Why**: The TV guide is more useful as a scan-first US/UK sports surface than as a broad mixed-region channel dump.
- **Implementation**:
  - Filtered Poland/Russia region rows, Cyrillic channel labels, and `.ru` channel labels from `/api/p2p/channels`.
  - Boosted United Kingdom and United States channels in P2P channel ranking.
  - Removed Poland/Russia from the `/guide` region controls and excluded those regions from web EPG map matching.
  - Expanded AceStream discovery queries for more US/UK targets including NFL RedZone, NBC Sports, SEC Network, ACC Network, Big Ten Network, ESPNU, ESPNews, and additional Sky Sports variants.
- **Verification**:
  - Deployed `fotty-p2p-proxy` and `fotty-web`.
  - Confirmed the deployed web catalog removed region-tagged Poland/Russia rows and returned 101 channels before final `.ru` cleanup.
  - Confirmed `/guide` returned HTTP 200 and guide smoke returned 76 guide rows, 25 exact EPG matches, and 289 scheduled programmes in the current four-hour window.

## 2026-05-20: Free-First EPG Expansion Pipeline
- **Decision**: Expand Fotty EPG coverage by auditing free XMLTV sources first, but keep the user-facing guide restricted to `confidence=verified` mappings.
- **Why**: AceStream can provide playable channel streams, but it does not reliably provide programme schedules. The guide needs separate XMLTV schedule data mapped to stream names.
- **Implementation**:
  - Added an EPG source audit script that compares current P2P channel names with existing generator channels and free XMLTV sources, writing candidates to `server/epg/p2p_epg_candidates.json`.
  - Added optional extra XMLTV merging that only imports channels already promoted to verified mappings.
  - Added support for `candidate` and `rejected` mapping states while preserving the rule that only `verified` entries are shown by `/api/epg/guide`.
  - Updated `/guide` to batch EPG requests for all visible channels, sort mapped rows before backup rows, and show a backup divider for unmapped channels.
- **Verification**:
  - Candidate audit found 57 unmapped rows with possible EPG matches, including BT Sport ESPN, Movistar sports channels, Sky Sport F1, SuperTennis, Smart Spor, and DAZN/LaLiga variants.
  - Promoted only the safe Sky Sport F1 fallback mapping; kept BT Sport ESPN candidate-only because the `tvprofil.com` grab returned HTTP 403.
  - Deployed Fotty Web and confirmed `/guide` returned HTTP 200.
  - Smoke-tested deployed guide batching: 95 P2P channels, 88 guide rows returned, 27 exact mappings, and 244 scheduled programmes.
- **Known follow-up**:
  - The homelab four-day and one-day EPG generator runs hit upstream/grabber reliability issues (`tvprofil.com` 403, Movistar certificate errors, and a Node heap/stall late in the grab). Keep the current production guide file until the refresh job is tuned to skip failing sources or split large grabs safely.

## 2026-05-20: Web P2P Live-HLS Stall Recovery
- **Decision**: Fotty Web's P2P player should treat AceStream broker manifests as sparse live HLS and aggressively resume from the live edge after stalls, rather than only restarting HLS loading before playback has begun.
- **Why**: Several P2P streams could start, play roughly ten seconds, drop to black, and repeat while the broker continued serving fresh manifests. That pointed to client-side live edge/stall recovery rather than channel discovery.
- **Implementation**:
  - Reduced the initial buffer gate for web P2P playback and tuned Hls.js live sync closer to the broker's short live window.
  - Added recovery for non-fatal buffer stalls and fatal network errors after playback has already started.
  - Added a short video `waiting` recovery timer that restarts HLS loading and jumps back toward the live sync position when playback drifts too far behind.
- **Verification**:
  - Deployed `fotty-web` successfully through the homelab Docker build.
  - Confirmed deployed `/api/p2p/channels` still returns 95 US/UK-prioritized channels and `/watch/[id]` returns HTTP 200.
  - Checked `fotty-p2p-proxy` logs showing broker manifests continue returning HTTP 200 after startup, with initial segment probes succeeding.

## 2026-05-20: Football-First Match Day Board
- **Decision**: Fotty Web's Live Board should behave more like a football fan's match-day command center, with live matches, followed teams, and imminent kickoffs separated before general upcoming fixtures.
- **Why**: A fan should not have to hunt past future or less relevant cards to find the match that is actually on, and common controls like spoiler protection and guide/tables context need to be reachable from the board itself.
- **Implementation**:
  - Added a match-day control strip with live/soon/tracked-team counts, inline spoiler toggle, and quick links to TV guide and tables.
  - Split the match list into `For you`, `Live now`, `Starting soon`, `Big fixtures`, and `Up next`, with duplicate suppression across sections.
  - Added watch confidence labels to the featured panel and match cards using feed depth and playback health signals.
  - Changed user preference hydration to start from deterministic defaults and load local storage after mount, reducing hydration mismatch risk between devices.
- **Verification**:
  - Deployed `fotty-web` successfully through the homelab Docker build.
  - Smoke-tested the public mobile `/swarm` page with Playwright: page loaded without console errors, and the new control strip, TV guide link, and confidence labels were present.

## 2026-05-21: Web Playback Stability Guardrails
- **Decision**: Fotty Web should expose stream status diagnostics, keep event stream lookup on the same watch-token path as playback, and recover from slow-loading event embeds by moving to the next ranked backup feed.
- **Why**: Playback issues were showing up differently across devices and browsers. Users need clearer device-level recovery, while the app needs to avoid silently sitting on a blank or blocked feed when alternates are available.
- **Implementation**:
  - Updated event stream lookup to request a watch token before calling `/api/live/streams`, while still sending session headers as fallback.
  - Added a watch-page Status panel showing mode, access, lookup state, feed count, selected feed, iframe state, last check time, and current error.
  - Added event iframe load/error tracking and a timed backup switch when a provider frame does not load quickly.
  - Added a Settings action to refresh the current device by clearing Fotty API caches, updating service workers, and reloading without signing the user out.
- **Verification**:
  - Ran focused ESLint on the changed web files; only the existing P2P warmup set-state warning remains.
  - Ran the local production web build successfully, with the existing Turbopack EPG NFT warning unchanged.
  - Deployed `fotty-web` successfully through the homelab Docker build and smoke check.

## 2026-05-22: Operator-Focused Admin Access Dashboard
- **Decision**: The Fotty admin access page should work as an operator dashboard, not only a raw account edit form.
- **Why**: Manual WhatsApp/bank-transfer activation needs fast answers about who is active, expiring, expired, lifetime, or on a short Match-Day pass.
- **Implementation**:
  - Added summary cards for visible accounts, active access, expiring soon, expired, and lifetime accounts.
  - Added access filters for All, Active, Expiring, Expired, Lifetime, Match-Day, Plus, and Free.
  - Added status badges and admin-note snippets to the account table.
  - Added selected-account summary cards and quick note templates for common payment/admin situations.
- **Verification**:
  - Ran focused ESLint on `AdminAccessDashboard.tsx`; only existing React set-state-in-effect warnings remain.
  - Ran the local production web build successfully, with the existing Turbopack EPG NFT warning unchanged.
  - Deployed `fotty-web` successfully through the homelab Docker build and smoke check.

## 2026-06-02: Production UX Trust Cleanup
- **Decision**: Fotty Web public routes should use one product voice, one clear next action per page, and a conservative fixture-name quality gate before live data reaches UI.
- **Why**: Paid-user and World Cup readiness depend on trust. Rough provider abbreviations, duplicated featured fixtures, dead guide grids, prototype-style legal copy, and passive empty states make the product feel stitched together instead of reliable.
- **Implementation**:
  - Added a centralized public fixture-name quality gate that converts rough all-caps provider tokens to `Fixture details updating` instead of leaking names such as `PP v San Diego Padres`, `Boston Red Sox v BO`, `WN v Miami Marlins`, or `AD v LAD`.
  - Suppressed duplicate featured fixtures in Live Board personalization.
  - Hid TV Guide quick-pick rails and grids when there are no useful rows, leaving one intentional fallback state.
  - Reorganized Settings into Account, Match Day, Device, and Support.
  - Replaced Saved and Teams one-off empty copy with shared fallback states and clear Live Board / World Cup actions.
  - Rewrote plans, Privacy, and Terms copy to sound production-ready and focus on match-day convenience, reminders, source organization, support, and account features.
- **Verification**:
  - Ran `npm run build` successfully in `web`.
  - Smoked local production routes on port `3020`: `/`, `/swarm`, `/guide`, `/tables`, `/world-cup`, `/watch/test-source`, `/welcome`, `/settings`, `/subscribe`, `/teams`, `/favorites`, `/help`, `/privacy`, and `/terms`.
  - Browser-audited core routes for public prototype/MVP/concept copy and blank-body failures.
  - Confirmed `/api/matches` no longer exposes the known bad fixture-name patterns; rough rows fall back to `Fixture details updating`.
  - Deployed `fotty-web` to the homelab and smoked the same public routes on `https://fotty.pixel-invoice.com`;/[URL_REDACTED] all returned HTTP 200 and the live match feed still reported zero known bad fixture-name patterns.

## 2026-06-11: Native iOS World Cup Mode Seed
- **Decision**: Fotty iOS should include a native World Cup mode with seeded published fixtures and groups, independent of provider feed reliability.
- **Why**: World Cup readiness cannot depend on the live provider returning clean football rows at the exact moment users open the app; the app must still show the opening schedule, groups, and a watch-path entry point.
- **Implementation**:
  - Added a World Cup football league tab and classification for known 2026 World Cup national-team pairings.
  - Seeded the opening 24 fixtures and all groups into the iOS dashboard/live feeds while filtering non-football World Cup noise.
  - Added a native dashboard World Cup section with Today, Schedule, Groups, and Watch views, plus guide/watch actions.
  - Reworked the section into a premium tournament module with a marquee next-match panel, team medallions, tournament stats, and richer group tiles.
- **Verification**:
  - Ran unsigned generic iOS Debug build successfully.
  - Ran signed Debug device build successfully for the connected iPhone 15 Pro Max.
  - Installed and launched `com.jelani.Fotty` on the connected iPhone 15 Pro Max.

## 2026-06-11: Admin Account Create Handles PocketBase Username Requirement
- **Decision**: Fotty Web admin account creation should always send a generated PocketBase username and preserve field names in validation errors.
- **Why**: PocketBase can reject auth record creation with a generic `Missing required value.` message when the `users` collection has a required field such as `username`; the admin UI only collected email/name/password, making the issue unclear.
- **Implementation**:
  - Generate a safe unique username from the email when creating PocketBase users.
  - Include the generated username in both full and minimal create-account payloads.
  - Prefix PocketBase validation messages with the failing field name.
- **Verification**:
  - Ran focused ESLint on the changed admin/PocketBase server files.
  - Ran local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.

## 2026-06-11: Admin Dashboard Falls Back To Local Grants When PocketBase List Is Forbidden
- **Decision**: Fotty Web admin users should show local admin grants when PocketBase user listing fails, instead of hiding known accounts because `POCKETBASE_ADMIN_TOKEN` exists.
- **Why**: Production had 2 local grants on disk while PocketBase user listing returned `403`. The dashboard was configured for PocketBase mode and therefore showed an empty/failed account list rather than the existing local accounts.
- **Implementation**:
  - `/api/admin/users` now falls back to `admin-grants.json` when PocketBase listing fails and local grants exist.
  - Admin create requests include the selected source so fallback-local mode creates local grants instead of attempting PocketBase.
- **Verification**:
  - Confirmed production has a PocketBase admin token, PocketBase list returns `403`, and `.data/admin-grants.json` contains 2 users.
  - Ran focused ESLint and local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
- **Follow-up**:
  - Replace or widen the production PocketBase admin API key so the dashboard can list PocketBase `users`; the fallback keeps local grants visible but does not fix PocketBase key permissions.

## 2026-06-11: Web Mobile Watch Viewport And Playback Recovery
- **Decision**: Fotty Web watch routes should scroll naturally on phones, use small viewport units for mobile player height, and expose explicit playback retry/recovery paths.
- **Why**: Mobile Safari browser chrome and fixed `dvh` layouts were making the watch page feel clipped, while desktop/mobile playback failures could leave users stuck at a generic unavailable state during match-day use.
- **Implementation**:
  - Replaced full-page mobile `h-dvh`/locked overflow on the watch route with `min-h-[100svh]`, horizontal overflow protection, and desktop-only fixed-height player layout.
  - Reduced the mobile video stage height and kept watch details visible below the player instead of clipping them inside an overflow-hidden panel.
  - Added HLS token/session resolution, longer live-buffer tolerances, live-edge recovery, fatal retry limits, and a visible `Retry stream` action in the P2P player.
  - Sent autoplay-normalized event embed URLs into the iframe, not only the external `Open feed` link.
  - Made the paid access gate respect `100svh` and safe-area padding on mobile.
- **Verification**:
  - Ran focused ESLint on watch/player files; only existing React compiler set-state-in-effect warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
  - Smoked `https://fotty.pixel-invoice.com/[URL_REDACTED] `/watch/test-source`, `/api/matches`, and `/api/p2p/channels`; pages returned 200, matches returned 101 rows, and P2P channels returned 130 rows.
- **Follow-up**:
  - Real-device/browser visual QA is still required because Codex Browser policy blocked both localhost and the production Fotty domain during this pass.

## 2026-06-12: Chrome HLS Stall Watchdog
- **Decision**: Fotty Web's HLS.js player should detect Chrome stalls where playback has started but the playhead stops without a fatal HLS error.
- **Why**: Some streams continued in Safari/Firefox but started and then stopped in Chrome, which uses the HLS.js/MSE path and can sit in a stalled non-fatal state.
- **Implementation**:
  - Added playhead progress tracking while P2P playback is active.
  - Added a Chrome/HLS watchdog that restarts HLS loading, jumps back to the live edge when needed, recovers media errors on repeated soft stalls, and performs a harder loader restart for long stalls.
  - Kept the watchdog inactive before playback starts, after user pause, or when a real playback error is already shown.
- **Verification**:
  - Ran focused ESLint on `VideoPlayer.tsx`; only existing React compiler set-state-in-effect warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
  - Smoked `https://fotty.pixel-invoice.com/[URL_REDACTED] `/watch/test-source`, `/api/matches`, and `/api/p2p/channels`; pages returned 200, matches returned 95 rows, and P2P channels returned 127 rows.
- **Follow-up**:
  - Verify on real Chrome with a stream that previously stopped; browser automation was not used because prior Codex Browser policy blocked the Fotty domain.

## 2026-06-13: World Cup Group Tables Consume Fixture Results
- **Decision**: The World Cup tab should compute group tables from World Cup fixture scorelines instead of rendering static team lists.
- **Why**: The group view showed every team as a placeholder `Fixture` row even after tournament results existed, making the World Cup hub feel unfinished and leaving tables disconnected from match results.
- **Implementation**:
  - Added World Cup group table calculation from `ScrapedMatch.score`, including P/W/D/L/GF/GA/GD/points/form and group-draw-order tie fallback.
  - Added confirmed fallback result seeds for the opening completed fixtures so tables show useful results while the current Fotty match feed is not carrying World Cup scores.
  - Replaced the Groups placeholder cards with real standings tables plus scoreline rows.
  - Added an actual fixture calendar to the Schedule tab alongside tournament milestones.
- **Verification**:
  - Ran focused ESLint and TypeScript checks on World Cup files successfully.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
  - Smoked `/world-cup`, `/world-cup?tab=groups`, and `/world-cup?tab=schedule`; all returned 200.
  - Confirmed production group HTML includes `4 results in tables`, Mexico 2-0 South Africa, South Korea 2-1 Czechia, and updated Group A rows.
- **Follow-up**:
  - Wire a live World Cup results provider into `/api/matches` or a dedicated World Cup API so result seeds can be replaced by automatic score ingestion.

## 2026-06-13: P2P Broker Recovers Frozen FOX Sports 2 Live Playlists
- **Decision**: Fotty P2P playback should treat a frozen live HLS media sequence as a broker/session health problem, but only after a recent manifest refresh proves the sequence is truly stuck.
- **Why**: FOX Sports 2 HD could show peers, speed, buffer, and downloadable old segments while Chrome sat at buffering because the playlist stopped advancing. The previous recovery path reused the same CID session and could over-restart Ace after quiet gaps, eventually driving playback manifests into `403`.
- **Implementation**:
  - Added force-new broker session support from the web watch retry path through `/api/stream/session` to the P2P proxy.
  - Added a startup decode watchdog in the web HLS player so a ready-looking source that never decodes triggers session recycling.
  - Preserved `Range`, `Content-Length`, `Content-Range`, and `Accept-Ranges` through the web segment proxy for Chrome/HLS.js.
  - Made live media-sequence manifests refresh without a stale revalidation grace window.
  - Changed frozen-sequence detection to require a recent manifest check, reset retry budget after successful prepares, and treat Ace playback `manifest_403` as retryable.
  - When a frozen sequence is proven, the broker forces a fresh Ace engine playback session and waits briefly for the refreshed manifest before returning a 503.
- **Verification**:
  - Ran focused ESLint on web watch/player/session files; only existing React compiler set-state-in-effect warnings remain.
  - Ran `npx tsc --noEmit --pretty false` and local production web build successfully.
  - Ran `python3 -m py_compile server/p2p_proxy_service.py` successfully.
  - Deployed `fotty-web` and `fotty-p2p-proxy` to the homelab/public site successfully.
  - Confirmed FOX Sports 2 HD is listed by the public web P2P API.
  - Confirmed two force-new session requests for FOX Sports 2 return different broker session IDs.
  - Confirmed the public web manifest for FOX Sports 2 stayed HTTP 200 and advanced after a quiet gap (`883 -> 885 -> 888 -> 894`), and segment range requests return HTTP 206 with `video/mp2t`, `Content-Range`, and `Accept-Ranges`.
- **Follow-up**:
  - Add an automated Chrome/HLS smoke that asserts media sequence movement and first-frame decode for pinned World Cup channels.

## 2026-07-10: Football Matches Proxy And Watch Recovery Extraction
- **Decision**: Mobile football-data.org schedule calls prefer Fotty Web `/api/football/matches` (server-held key), and event-embed failover timers live in a tested recovery helper/hook rather than inline watch-page effects.
- **Why**: Keeping the football-data token only on the web host reduces mobile binary secret exposure; extracting failover selection/timeout arming makes backup rotation testable without mounting the full watch page.
- **Implementation**:
  - Added `force-dynamic` `/api/football/matches` with query allowlisting and upstream URL builder tests.
  - Wired iOS `FootballService` and Android `FootballRepository` / `MatchRepository` to prefer the proxy (direct API remains fallback when a local key exists).
  - Extracted `watch-event-recovery` helpers + `useEventPlaybackRecovery`; `WatchPageClient` uses them for load/start failover.
- **Verification**:
  - Web unit tests: 30 passing (includes football URL builder + event recovery).
  - Android `:app:compileDebugKotlin` after DI wiring.
- **Follow-up**:
  - Deploy web with `FOOTBALL_DATA_API_KEY` before relying on mobile proxy in production.
  - Rotate previously committed credentials; run sustained P2P e2e with `FOTTY_P2P_E2E_CID`.

## 2026-07-10: Playback And Proxy Boundaries Fail Closed
- **Decision**: Caller-controlled media proxy targets must match explicit upstream allowlists, embed playback may only become “started” from real player events, and runtime credentials must not have committed defaults.
- **Why**: The broker segment endpoint and embed HLS endpoint could be abused as broad server-side fetchers, the web player treated an iframe timer as proof of playback, and committed provider/default credentials increased compromise and rotation risk.
- **Implementation**:
  - Added exact-origin validation to the Flask segment proxy and strict HTTPS host-suffix validation to the web embed HLS proxy.
  - Replaced timer-based embed success with validated `postMessage` playback events from the proxied player bridge; errors and stalls now enter the existing backup flow.
  - Split client-safe paid-plan checks from server-only HMAC billing code so Webpack development builds do not bundle `node:crypto`.
  - Removed known P2P, TMDB, football-data, RapidAPI, and API-Football credential literals from current source and moved local mobile values to gitignored build configuration.
  - Made server CI install the broker runtime dependencies and verify the broker imports before tests; serialized web unit tests for deterministic execution.
  - Made watch/auth API routes `force-dynamic` in source; removed Docker sed patching; static FTP export uses `npm run build:static` only.
- **Verification**:
  - All 46 server tests and all 23 web unit tests passed.
  - Web TypeScript, focused playback lint, production web build, Android Kotlin compilation, and iOS simulator build passed.
  - Deterministic Playwright coverage passed for a paid event embed receiving real bridge start/pulse events without remounting.
  - Repository scan found none of the removed credential literals in the current working tree.
- **Follow-up**:
  - Rotate previously committed credentials; removal from HEAD does not revoke Git-history or released-binary copies.
  - Run sustained P2P browser playback against a production-like broker (`FOTTY_P2P_E2E_CID`).

## 2026-07-10: M0 Release Safety Regressions
- **Decision**: Broker crash paths must always preserve structured JSON responses, production playback tests require explicit opt-in credentials, and canonical watch-route helpers must be exercised from their real implementation.
- **Why**: Undefined error logging could mask the original broker exception, a production smoke password was committed in test source, and an embed URL unit suite plus canonical route implementation were outside the default regression contract.
- **Implementation**:
  - Removed undefined `pulseLog` calls and added structured 500 handling for unexpected segment-fetch failures.
  - Added manifest and segment structured-500 integration regressions.
  - Gated the production playback E2E behind `FOTTY_RUN_PROD_PLAYBACK_E2E=1`; credentials, active CID, and endpoints now come from environment variables.
  - Switched the production smoke URL to `/watch/index?cid=...`, extracted the pure watch-route builder, tested P2P/event canonical URLs, and wired `embed-url.test.mjs` into `test:unit`.
- **Verification**:
  - All 43 P2P proxy tests and all 34 web unit tests passed.
  - The production Next.js build, changed-file ESLint, and whitespace checks passed.
  - Repository-wide ESLint remains blocked by 10 existing errors outside the M0 files.
- **Follow-up**:
  - Rotate the exposed production smoke-user password in PocketBase before enabling the gated production test.

## 2026-07-10: M1 Attempt-Scoped Playback Recovery
- **Decision**: Web playback success requires decoded playhead progress, and one attempt-scoped controller owns event-feed switching or P2P session recycling after player adapters report typed facts.
- **Why**: Iframe loads, `play()` resolution, and `playing` events could previously suppress recovery without proving frames advanced; nested HLS, media-element, and parent retries could amplify into remount storms; native Safari HLS lacked the Chrome watchdog path.
- **Implementation**:
  - Added a pure playback reducer with attempt IDs, fault taxonomy, strict late-event rejection, mode-specific recovery actions, and bounded budgets.
  - Event embeds now mark success only after the injected bridge observes advancing `currentTime`, decoded dimensions, and ready media data. Direct-provider fallback no longer counts as playback proof.
  - Reduced HLS fatal retries to two and media-element recovery to one startup/three live attempts; parent P2P session recycling is capped at two.
  - Replaced the Chrome-only stall loop with one media watchdog used by HLS.js and Safari native HLS; both attempt throttled, buffer-preserving soft recovery before bounded media reload.
  - Canonical P2P E2E navigation now uses `/watch/index?cid=...`.
- **Verification**:
  - All 42 web unit tests passed, including controller generation/budget, decoded-progress, embed-bridge, and native-HLS watchdog regressions.
  - Deterministic watch Playwright coverage passed: four tests passed and the real-broker test skipped without `FOTTY_P2P_E2E_CID`.
  - TypeScript and the production Next.js build passed; focused playback lint has no errors (existing warnings remain).
- **Follow-up**:
  - Run the real Chromium P2P test with an active staging CID and verify native Safari playback on a physical Apple device before production promotion.

## 2026-07-10: Pre-Deployment Dual-Browser Playback Gate
- **Decision**: Chrome and WebKit are required CI browser projects, live P2P tests require decoded dimensions plus advancing playhead, and broker credentials must never be redirected into browser-visible manifest URLs.
- **Why**: The previous Chromium-only deterministic gate missed Safari behavior; a live production-build test exposed missing watch-token propagation, cross-origin auth-header failures, stale session manifests, and an `api_password` query in the browser network path.
- **Implementation**:
  - Added WebKit to Playwright and CI browser installation, blocked service workers in deterministic tests, and refreshed stale home/login/watch assertions.
  - Added bounded event-feed exhaustion coverage and verified no feed-rotation loop after all generated backups fail.
  - Propagated short-lived watch tokens to P2P session, status, and health requests.
  - Kept P2P API credentials server-side by serving the manifest through `/api/stream`; session-manifest 503s now fall back to the CID-bound signed public manifest.
  - Prevented HLS.js from adding account headers when a signed `watchToken` already authorizes the media URL.
  - Fixed repository lint errors and reduced the gate to 48 warnings, below the enforced maximum of 50.
- **Verification**:
  - Server: 48 tests passed.
  - Web: 42 unit tests, TypeScript, lint, and production build passed.
  - Deterministic Playwright: 26 passed across Chromium and WebKit; four environment-gated real/production cases skipped as designed.
  - Deployment-like P2P playback decoded the same ESPN HD source in both engines: Chromium 1280×720 and WebKit 1280×720, `readyState=4`, advancing playhead.
  - A separate 1920×1080 source decoded in WebKit but not Chromium, confirming source/codec compatibility remains source-dependent.
- **Follow-up**:
  - Run the opt-in production PocketBase sign-in/playback test with rotated credentials.
  - Confirm WebKit behavior on a physical iPhone/iPad and run a longer multi-source soak before production promotion.

## 2026-07-10: Playback Trust And AceStream Operations Hardening
- **Decision**: Provider players run in an opaque sandbox, media URL tokens contain no PII and expire after ten minutes, the homelab Compose file is the sole production definition, and AceStream API events are part of the broker contract.
- **Why**: Same-origin provider HTML could access Fotty browser state; four-hour email-bearing URL tokens leaked identity and reusable authorization; duplicate deploy/scraper paths caused drift; generic manifest failures hid missing `proxyServer` entitlement and codec/segmenter failures.
- **Implementation**:
  - Applied iframe and CSP sandboxes without `allow-same-origin`; the bridge accepts opaque-origin messages only from the exact mounted iframe window.
  - Replaced email/user-ID token payloads with an authenticated AES-GCM envelope containing a one-way subject, nonce, and paid entitlement; shortened lifetime to ten minutes and invalidated the legacy payload shape.
  - Required broker authorization for catalog, search, metrics, and dashboard routes.
  - Made `homelab-docker-compose.yml` canonical: two Gunicorn workers × 16 threads, loopback Redis/Gunicorn bindings, no duplicate scraper, no AceStream remote-access flags, and bounded evidence-backed prewarming.
  - Updated the deploy helper to use Compose, verify `/health`, and fail when control ports 6379/6878/8006 listen beyond loopback.
  - Enabled AceStream API events and stop notifications; typed `missing_option`, `segmenter_failed`, `download_stopped`, and codec events are persisted in broker timelines and private metrics.
  - Added a five-minute free-versus-Proxy-Server baseline capture tool.
- **Verification**:
  - All 46 broker tests, 42 web unit tests, TypeScript, lint, production build, and Compose parsing passed.
  - Deterministic Playwright passed 26 tests across Chromium/WebKit; four opt-in production cases skipped.
  - Real ESPN HD playback decoded at 1280×720 with `readyState=4` and advancing playhead in Chromium and WebKit.
  - Current free-engine aggregate baseline remains below promotion gates: manifest p95 17.592s and segment 2xx rate 81.62%.
- **Follow-up**:
  - Deploy the canonical stack in a maintenance window, verify loopback listeners, and repeat the three-source five-minute soak.
  - Activate one month of an official plan containing `proxyServer`, then capture the paid comparison window; Premium cannot be activated from source code.
  - Run physical iPhone/iPad playback and controlled AceStream/Redis restart tests before shared staging.

## 2026-07-10: Live Feed Identity Includes Playback Availability
- **Decision**: Home-feed refresh identity includes event-source and playback fields; active fixtures retain their last playable mapping across transient empty/incomplete provider refreshes; finished fixtures are never hero fallbacks.
- **Why**: The previous score/status-only fingerprint treated a newly attached StreameX source as unchanged, leaving live cards rendered as inert articles and allowing a high-ranked finished World Cup fixture to remain in the hero.
- **Implementation**:
  - Added source identity, playback type, source count, and kickoff time to `matchFeedSignature`.
  - Added bounded mapping preservation for active fixtures while explicitly refusing to revive finished fixtures.
  - Prioritized any genuinely live fixture above upcoming/fallback content and removed finished matches from the final hero fallback.
- **Verification**:
  - All 45 web unit tests, TypeScript, and lint passed.
  - Focused Chromium and WebKit Playwright coverage passed.
  - The running home page selected Spain v Belgium, exposed a signed event watch link, and a live game card opened the canonical watch route.

## 2026-07-10: Watch Page Carries Every Provider Source, Not Just The Top One
- **Decision**: A fixture's watch link and player expose all provider broadcaster/language links, instead of collapsing to the single highest-priority source.
- **Why**: The matches feed picked one `eventSource` by fixed `SOURCE_PRIORITY` (echo/delta/golf/alpha/admin) and only enumerated `streamNo` variants of that one source, so multi-broadcaster events (e.g. Spain vs Belgium) surfaced only the Spanish feed even though the provider listed several.
- **Implementation**:
  - Added `eventSources` to `ScrapedMatch`; `fixtureToMatch` populates all playable provider links ordered by source priority and deduped.
  - Added `web/src/lib/watch-event-sources.ts` (encode/decode/dedupe/key) and serialized the full set into a `sources` watch-URL param from both the client (`buildWatchHref`) and server (`buildServerWatchHref`) link builders; the World Cup merge retains `eventSources` via spread.
  - Reworked `useEventStreams` to fetch every source in parallel and merge into one feed list (per-source numbered variants, deduped by embed URL); single-source matches keep their four-deep synthesized backups, and each source contributes its primary embed when detail lookups return nothing.
  - `eventEmbedURL` now derives from the selected stream's own source/id.
- **Verification**:
  - 49 web unit tests (incl. new `watch-event-sources` round-trip/dedupe coverage), TypeScript, and lint passed.
  - Live dev `/api/matches` showed 49 fixtures with multiple sources; Spain v Belgium exposed echo/golf/admin, and both SSR HTML and the hydrated home page emitted the full `sources` param for Spain and Miami.

## 2026-08-02: Web Watch needs playback Worker for iOS stream parity
- **Decision**: Every non-P2P catalog stream iOS can play (StreamEx/VipLeague/`echo`/`delta`/…) must be playable on getfotty.com via the same Referer + HLS proxy model. Static FTP alone cannot do that; ship `web/workers/playback` and set `NEXT_PUBLIC_FOTTY_API_BASE` at `build:static`. Client must use the remote API on getfotty.com when configured (do not short-circuit to bare `embed.st`). Source priority matches iOS (`echo` first).
- **Why**: Browsers cannot inject StreamEx Referer or segment headers; iOS WKWebView + `LocalStreamProxy` can. Direct iframes fail with `hls:networkError_manifestLoadError`.
- **Verification**: With Worker + `NEXT_PUBLIC_FOTTY_API_BASE`, Watch loads `/api/embed/player` from the Worker and feeds start; without it, site synthesizes Fotty 1–4 direct embeds only (degraded).

## 2026-08-02: Remove EPG / TV Guide infrastructure
- **Decision**: Delete all XMLTV/EPG product code — web `/api/epg`, guide/swarm routes and UI, iOS `EPGDataStore`, and the entire `server/epg/` tree (including the vendored iptv-org generator). No redirect stubs for `/guide` or `/swarm`. Keep `web/src/lib/stream-guide/` (match feed ranking, not TV EPG).
- **Why**: Homelab/P2P channel catalog is retired; EPG only served that Guide surface and added launch/watch dead work.
- **Verification**: No `epg` / `EPGDataStore` / `xmltv` hits under `web/src` or `Fotty/`; `server/epg/` absent.

## 2026-08-02: Retire World Cup product surfaces
- **Decision**: Remove all World Cup hubs, seeds, tournament-focus fetch targeting, nav entries, APIs, ranking boosts, and route stubs from iOS and getfotty.com. Do not keep `/world-cup` redirect pages.
- **Why**: The tournament is over; continuing to ship WC seeds, tabs, and priority ranking distorts Home/Schedule toward a finished event.
- **Implementation**:
  - iOS: deleted `WorldCupTabView` / `WorldCupDataLoader`; match lists use provider events only; restored normal multi-league football focus.
  - Web: deleted WC view/libs/hooks/APIs/routes; stripped home/schedule/discover WC rails; removed BottomNav entry and sitemap path.
- **Verification**: Zero `World Cup` / `WorldCup` / `world-cup` product hits under `Fotty/` and `web/src`.

## 2026-08-02: iOS Home badges — persist Nexus crests in SwiftData cache
- **Decision**: `MatchCacheItem` stores `homeBadge` / `awayBadge` tokens; cache reload must not force `badge: nil`. `FlagSquircleBadge` observes `TeamBrandService` so async brand resolve re-renders. Home cards (`LiveEventCard`, `HeroMatchCarousel`, `ForYouLiveCard`) also fall back to `TeamBrandService` like Social/MatchHub.
- **Why**: Home showed initials after cache round-trip even when StreamEx sent crest tokens; MatchHub/Social already had working crest paths.

## 2026-08-02: Web club badges use StreamEx crest URLs again
- **Decision**: Stop discarding long `streamed.pk` badge URLs in `teamFlagDisplay`. Show the same StreamEx crest tokens the iOS app resolves via `AnalyticalDataEngine.imageURL`.
- **Why**: Web was forcing initials because long encoded badge URLs were treated as placeholders; those URLs are valid club crests.

## 2026-08-02: Retire web Guide / Swarm / P2P channel catalog
- **Decision**: Remove TV Guide, Live Board (`/swarm`), and P2P channel rails from getfotty.com nav and Discover. Routes deleted (not redirected). Channel APIs return empty; copy points to Home/Discover/Schedule.
- **Why**: Those surfaces depended on the retired AceStream/homelab channel catalog. Site is fixtures-only (StreamEx match list → Fotty 1/2/… feeds).

## 2026-08-02: Web match feed = StreamEx catalog (same as iOS)
- **Decision**: getfotty.com loads fixtures from the **StreamEx / Nexus** schedule (`streamex.net` / mirrors), the same catalog the iOS StreamEx + VipLeague modules use. Strip retired P2P `admin` sources. Do not call the dead scraper API.
- **Why**: Homelab is gone; static export previously short-circuited to `[]`. App already watches via StreamEx/VipLeague web embeds — site should match.
- **Mapping**: `delta`→StreamEx, `echo`→VipLeague; Score808 remains an embed-domain filter in the app modules. Watch on static FTP synthesizes `embed.st` URLs when `/api/live/streams` is unavailable.

## 2026-08-02: Homelab retired — getfotty.com FTP only
- **Decision**: The Acer/homelab stack (`100.116.91.102`, `fotty.pixel-invoice.com`, scraper/P2P tunnels) is **gone**. Do not SSH, deploy via `web-deploy-homelab.sh`, or default web clients to pixel-invoice hosts. Public web deploy is **FTP to getfotty.com** only (`npm run build:static` → upload `web/out/`).
- **Why**: Operator shut down the lab; leftover defaults and deploy scripts would waste time and break builds against dead hosts.
- **Implementation**:
  - `getPublicFottyApiBase()` returns empty unless `NEXT_PUBLIC_FOTTY_API_BASE` is set at build time.
  - `web/DEPLOY.md` documents FTP-only hosting.
  - 2026-08-02 static export uploaded to Octavia FTP (416 files).

## 2026-08-02: Web companion — app-first alignment pass
- **Decision**: getfotty.com stays coverage; iOS is primary. Web Home gets **On-now glance**; `/search` ships **DiscoverViewV2** (not classic search); welcome/PWA shortcuts stop leading with Live Board/`/swarm`.
- **Why**: Site still read like a P2P/homelab product after the app retired AceStream and added glance + modules.
- **Next**: further demote `/swarm` in nav; replace build-time match feed now that scraper host is gone.

## 2026-08-02: Watch Now reliability + smarter On-now + VipLeague module
- **Decision**: Rank broadcast sources by `LiveSourceHealthStore` (success/latency/stalls + last-good provider per sport/league). On-now diversifies sports, biases followed teams, adds **Surprise**. Seed **VipLeague** (`echo`) as the third web module beside StreamEx + Score808. getfotty.com sync deferred — app remains primary.
- **Why**: Elevate value without bringing the homelab back; make Watch Now feel inevitable and discovery glanceable.

## 2026-08-02: P2P/AceStream retired for now + On-now glance
- **Decision**: Strip P2P from featured stream modules and skip homelab P2P resolution unless a P2P module is explicitly enabled. Home gains a compact cross-sport **On now / soon** glance strip under the masthead.
- **Why**: Operator is done with AceStream self-hosting for now (power/cost). Users still need a tiny “what can I watch right now?” signal that ignores the active sport filter.
- **UI**: `OnNowGlanceBar` — ~32pt chips, not a second rail or side panel.

## 2026-08-02: Stream modules restored in Settings
- **Decision**: Settings → **Stream modules** manages StreamEx / Score808 manifests. Fresh installs seed StreamEx + Score808 enabled.
- **Why**: The plugin UI existed only in a stash (`81081c5`) and never shipped on HEAD, so users couldn’t see or manage add-ons while web catalog resolution still ran invisibly.
- **Path**: `SettingsScreen.streamPluginsSection` → `StreamPluginsSettingsView`; resolvers via `StreamPluginRegistry` + `NativeBridgePluginAdapter`.

## 2026-08-02: Drop iPad Home side rail — full-width stack
- **Decision**: Home on iPad uses the same full-width vertical stack as iPhone (hero → Live rail → fixtures). No “Up next” / Live&soon side column.
- **Why**: The narrow right rail left a tall void under a short card stack and pulled weight to one edge; it read as a bolted-on panel, not cinema editorial.
- **Keep**: Regular size class still gets a 2-column fixture grid under the full-width hero.

## 2026-08-09: StreamEx in-play games pin to Live without scoreboard match
- **Decision**: `HomeMatchPriority.isLive` uses API-Football when available; otherwise treats kickoff-started + within **2h** as live (StreamEx friendlies/smaller leagues). Supersedes the earlier 3h window.
- **Why**: Liverpool vs Monaco was on the Nexus live feed but unmatched in LiveScoreService, so it never entered the Live rail and sank mid football list. 3h was wider than a real match and left finished friendlies marked live.
- **Verification**: Home → Football → in-progress StreamEx games appear under Live / hero, not buried in Today; drop off ~2h after kickoff when no scoreboard status.

## 2026-08-09: Score808 hotel-from-donor restored (web embed only)
- **Decision**: When Nexus omits `hotel`, synthesize `embed.st/embed/hotel/{donorId}` from delta/echo. Prefer Score808 web embeds over native StreamEx extracts. Never native-HLS-extract hotel. Reject ~1–2KB empty player stubs during web-embed validation.
- **Why**: Hotel shares the live feed with StreamEx donor ids (full ~600KB player config). An intermittent empty stub caused a false “dead shell” conclusion; native extract of that stub surfaces `hls:networkError_manifestLoadError` while WKWebView playback works.
- **Supersedes**: “Score808 only when Nexus has hotel”.
- **Verification**: Watch Now → Score808 #1 selected first as web embed; plays; Change Source still lists StreamEx.

## 2026-08-09: Safari-parity playback (app bug, not source bug)
- **Decision**: Watch Now returns Score808/StreamEx `embed.st` URLs immediately (no headless extract / stub probe on the critical path). `LiveWebEmbedPlayerView` loads the site origin first, then navigates to the embed so referrer matches Safari.
- **Why**: Score808 and StreamEx play fine in Safari. Stalls, black screens, and `manifestLoadError` came from Fotty’s resolve/player pipeline (Referer stripping, extract timeouts, aggressive scripts), not from the sources.
- **Verification**: Watch Now opens in ~1s; Score808 and StreamEx play in-app without hanging on “Looking for a playable stream…”.

## 2026-08-09: Player sources = StreamEx + Score808 only (no P2P UI)
- **Decision**: Remove Browse P2P Channels from the player. Watch Now resolves web-only and lists **StreamEx** + **Score808** only. VipLeague/P2P modules are stripped from seeds/featured.
- **Why**: Homelab AceStream is gone; Browse P2P was a dead end. Operator wants the source list to match the two active modules.
- **Implementation**: `LivePlayerView` P2P browse removed; `performResolution` skips P2P race; `StreamPluginProviderMatching.activePlayerProviderCodes`; registry strips echo/p2p leftovers.
- **Verification**: Rebuild → Watch Now → Available Broadcast Sources shows only StreamEx/Score808 rows; no Browse P2P control.

## 2026-08-09: StreamEx autoplay kick + Score808 visibility
- **Decision**: After first successful embed start, only call `video.play()` — never re-tap StreamEx UI (toggle leaves stream paused). Watch Now must scan **all** Nexus families for web embeds before returning; Nexus `hotel` is labeled **Score808**.
- **Why**: Post-start UI kicks toggled StreamEx into a stuck pause; early return after 2 StreamEx native extracts hid Score808/hotel from Change Source entirely.
- **Implementation**: `LiveWebEmbedPlayerView` startedPlayback soft-resume; `HybridStreamProvider` descriptor loop keeps collecting embeds; display name `hotel`→Score808; plugin timeout 12s; catalog merge filtered by enabled modules.
- **Verification**: Rebuild app → Watch Now on a live match → confirm StreamEx stays playing after buffer stalls; Change Source lists Score808 when Nexus includes `hotel` and the Score808 module is enabled.

## 2026-08-02: Home iPad hero width from container, not UIScreen
- **Decision**: Hero carousel page width must come from the proposed container (overlay `GeometryReader`), never `UIScreen.main.bounds`.
- **Why**: Screen-width fallback forced the hero wider than constrained columns / Stage Manager windows.
- **Verification**: Built + installed on iPad Air `00008101-001954E20AC0001E`.

## 2026-07-31: Home iPad Spacing — Fill Width, Dense Rows, Capped Dock
- **Decision**: Home iPad layout must fill the hero column (paging ScrollView, not TabView.page), keep vertical module gaps tight (≤10pt), use dense 76pt fixture rows, and center a max-width (~480) tab dock on regular size class.
- **Why**: TabView.page left a dead zone beside the hero; stacked header/date/competition padding created void bands; equal-width full-bleed tabs looked empty on landscape iPad.
- **Implementation**: HeroMatchCarousel + CompactHomeFilterBar + HomeMatchPriority ranking; LiveEventCard densified; MainTabView cinema dock capped/centered.

## 2026-08-24: Matches becomes My Matchday, not a duplicate catalog
- **Decision**: Keep the Matches tab, but make it a personal planning surface. Home discovers every current catalog event; My Matchday contains only explicitly saved matches and fixtures involving followed teams.
- **Why**: A second Live/Upcoming/Results browser duplicated Home and could say “No upcoming fixtures” while Home showed current provider events because the two tabs used different feeds. A persistent tab must earn its place with a distinct job.
- **Implementation**: Home and Matches share `MatchListViewModel.shared`. Home hero and fixture cards expose clearly labeled bookmarks. `MyMatchdayStore` persists bounded event snapshots in UserDefaults; My Matchday groups Live now / Next up / Later / Recent, labels why each event is present, warns when kickoffs overlap, and offers the same honest Watch-or-Details action without routing through Home.
- **Verification**: Catalyst build passed; 30 focused tests passed with one opt-in soak skipped. A Catalyst interaction check proved save → immediate My Matchday row → remove → explanatory empty state → Browse Home. The normal app was signed, installed, and launched on the physical iPhone 15 Pro Max with no UI-test runner; the connected iPad became unavailable to CoreDevice before its install and remains a manual gate.

## 2026-08-24: Slow web sources retry in place; catalog rows represent distinct broadcasts
- **Decision**: Give web embeds 20 seconds to prove decoded startup and reload the same selected broadcast once before automatic failover. Curate real catalog variants across source families, collapse each broadcaster's HD/SD pair to HD, and use viewer counts to rank remaining alternatives. A zero-variant family is omitted when any real variants exist; canonical synthesis is a one-per-family last resort only when the entire event has no variants.
- **Why**: Fulham–Chelsea exposed 18 real Admin variants, one Delta, zero Echo, and one Golf, but Fotty showed Admin #1/#2, Delta #1, two invented Echo rows, and Golf #1. The user could make a source play through repeated manual retries, proving the 10-second failover was too eager, while the picker overstated six meaningful alternatives.
- **Ad containment**: A live WebKit trace showed `embed.st/ad.html` spawning repeated external popup/click-through chains. The player removes that frame and observed nuisance hosts, disables `window.open`, keeps top-level navigation locked, and leaves the video and native web-player controls untouched. Explicit “broadcast unavailable” pages bypass the retry delay.
- **Verification**: Mac Catalyst build passed; the focused playback suite passed 32 checks and skipped only the opt-in soak. A WebKit containment probe produced zero popup pages with one video and one player-control layer preserved. Signed normal build 2396 installed and launched on the physical iPhone 15 Pro Max; final build 2404 installed after the last containment hardening, but CoreDevice could not relaunch it because the phone had locked. No simulator or UI-test helper was used.

## 2026-08-24: Fotty 2.0 is an integrated quality contract, not a feature-count release

- **Decision**: Accept `docs/audit/Fotty-2.0-Benchmark-and-Product-Contract.md` as the implementation and release authority. Fotty 2.0 must complete five connected journeys—discover, watch, deadline plan, live FPL, and review—and pass truth, accessibility, automated, physical-device, and active-provider gates.
- **Why**: Specialist comparisons showed that Fotty's advantage is the connection between matchday and FPL, while its release risk is contradictory or incomplete journeys. A compile or a larger tool list is not a useful definition of done.
- **Boundary**: LiveFPL, FPL Review, FPL.team, FotMob, Sofascore, OneFootball, Apple guidance, and open solvers are behavior/engineering benchmarks. Fotty does not copy unlicensed code, scrape manager totals from a benchmark, fabricate unsupported match data, or promise broadcaster control.

## 2026-08-24: One canonical match identity and one active Match Center

- **Decision**: Preserve a canonical fixture route ID with provider aliases through schedule, catalog, score, FPL context, alerts, Match Center, and playback. Remove the unreachable Dashboard Match Center and obsolete Arena/Highlights Match Hub tabs instead of maintaining a second presentation.
- **Why**: Provider-prefixed IDs and duplicate match surfaces caused score/playback routing ambiguity and dead controls. One identity and one overview make every visible action testable.
- **Verification**: Alias tests cover raw, canonical, and provider-prefixed identities across score/FPL/notification/playback boundaries; the Xcode target compiles with the dead files removed.

## 2026-08-24: FPL truth is deterministic; Coach explains decisions over evidence

- **Decision**: Official current points, legal autosubs, captain fallback, Bench Boost, transfer hits, blanks/doubles, published substitutions, and checked-final boundaries are calculated by versioned Swift and Worker rules. Direct facts/rules use zero model tokens. DeepSeek receives a minimized evidence packet only after consent and must return complete evidence, uncertainty, actions, freshness, source/model, and usage without contradicting verified rules.
- **Why**: A language model confidently denied a valid bench/captain outcome. Current scoring is a rules problem, while strategic choice benefits from an evidence-grounded explanation with explicit tradeoffs.
- **Verification**: Swift and Worker parity suites are green; production Worker `39e913bd-d1fb-48e4-bf56-20be2ba183e4` passed both a fresh zero-token deterministic smoke and a bounded structured model smoke.

## 2026-08-24: Playback evidence is local and retired P2P does not participate in production resolution

- **Decision**: Store only bounded redacted quality outcomes on-device; never add segment-path telemetry. Active resolution uses enabled StreamEx/Score808 catalog descriptors, and the old Hybrid P2P branch is behind undefined `FOTTY_LEGACY_P2P`. A fallback creates one source per family, not invented duplicates.
- **Why**: Playback correctness depends on decoded progress and attempt identity, while extra network diagnostics can harm playback. Retired P2P code and duplicate fallbacks made the supported path harder to reason about.
- **Verification**: Continuity tests cover stale callbacks, network restoration, same-web return after native failure, typed boundaries, and fallback source count. Current near-live browser probes recorded provider-side 403/no-media outcomes without misclassifying them as app playback success.

## 2026-08-25: A loaded web iframe is neither decoded success nor permission to replace the feed

- **Decision**: Direct cross-origin web embeds get a 20-second frame-load window. Once loaded, they stay selected unless the provider reports a concrete error or the user chooses another numbered broadcast; the parent page must not infer decoded success or failure from browser isolation. Same-origin instrumented players may report success only through advancing decoded video. Web Watch exposes no provider new-tab escape and no PiP control without a native video element.
- **Why**: The responsive release audit reproduced a provider frame where Fotty showed PiP/new-tab controls and previously promoted `iframe.onload` to playing. That both overstated capability and enabled automatic source replacement without evidence—the exact continuity failure reported by the user.
- **Verification**: The 390×844 in-app-browser pass kept Broadcast 1 selected beyond the recovery window, exposed no feed new-tab or false PiP control, reported no console error, and presented concise `Broadcast N` accessibility labels. Web/Worker tests pass 68/68 and the production Next/TypeScript build passes.

## 2026-08-25: Match clocks must respect sport semantics

- **Decision**: Fotty estimates a wall-clock-derived minute only for association football. Baseball, basketball, hockey, American football, cricket, and other period/inning sports show `Live` until a provider supplies a trustworthy sport-specific state. Compact glance chips spell out the sport and expose a complete event/timing accessibility label.
- **Why**: The visual release audit displayed `115′` for MLB and reduced `Baseball` to `Bas`, both authoritative-looking but meaningless.
- **Verification**: Four focused clock tests cover football, halftime, non-football sports, stale live flags, and explicit final states; desktop and iPhone-width browser checks show the corrected labels with zero horizontal overflow.

## 2026-08-25: Provider audits must preserve the media request's own referrer

- **Decision**: Apply the catalog/provider referer only to the top-level embed navigation in `audit_live_playback_matrix.mjs`. Never configure it as a browser-context header, because that overwrites the nested HLS request's required `embed.st` referer.
- **Why**: The first release-candidate matrix reported repeated `lb8.strmd.st` HTTP 403 responses. A controlled redacted probe returned HTTP 200 with the embed referrer, revealing that the harness—not the provider—had manufactured the failure.
- **Verification**: The corrected current-catalog rerun decoded advancing 960×540 `golf` video in about 13.8 seconds with media HTTP 200 and zero popups. Three other families remained non-decoding in the bounded window, so source-specific health remains honest rather than generalized from the one success.


# Risk Registry

# Fotty Risks

Last updated: 2026-08-30

This registry turns current sharp edges into guardrails for agents.

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


# Workflow

# Fotty Workflow

## Human-AI Loop
1. **Identify**: User identifies a stability or data issue.
2. **Research**: Agent uses `grep_search` and `view_file` to find the root cause.
3. **Reason**: Agent consults `docs/notebooklm/` to ensure the fix aligns with architecture.
4. **Deploy**: Use `tools/ios-deploy-device.sh` for physical device verification.
5. **Log**: Record the change in `Decisions-Log.md`.

## Testing Protocol (Ready for v1.6)
Before push:
- [ ] Sub-10s startup for verified web sources.
- [ ] P2P fallback resolution below the player.
- [ ] PiP stability during swipe-up.
- [ ] Branding fidelity (logos present for all Big 5 + NBA/WNBA).
- [ ] PocketBase sync reliability (no silent decoding crashes).

## Agent Hand-off
All agents must read `agent/AGENT-START.md` before initiating changes.
After significant changes, run:
```bash
./tools/notebooklm-refresh.sh
```


# QA Playbook

# Fotty QA Playbook

Last updated: 2026-08-30

This is the release checklist for Fotty 2.0. It uses Mac Catalyst and physical Apple devices only; do not start a simulator or install a UI-test runner on an iPhone or iPad.

## Default delivery and device acceptance

The owner has approved the reliability-first next phase. Current local source
and internal distribution are **2.0.0 (46)**. Apple independently shows the
build Internal / Testing for Fotty Internal Smoke with the unchanged two testers.
Physical TestFlight use exposed build 45's retired review-safe vocabulary; do
not treat 45 as an acceptance candidate. Use
`docs/releases/Fotty-2.0.0-46.md` for the current Apple/install record and
`docs/audit/Fotty-Single-Product-Graph-2026-08-29.md` for the correction.

Build 46 has one product graph and passes the final-source Catalyst unit suite,
vocabulary/retired-symbol gates and generic iOS Release compile. Its Catalyst
Home UI test could not begin because the beta-Mac automation runner timed out
twice. A direct read confirms build 46 is installed on the connected iPad; the
iPhone remains build 44 after TestFlight was reopened. After the iPhone Update,
read its version and physically confirm Home/Football/league vocabulary plus
Watch, Matchday and FPL availability after a cold launch on both devices before
the beta expands. Historical checkpoint notes below retain their at-the-time
evidence only.

The owner now prefers phone-first validation for small scoped fixes, followed by deliberately batched shared TestFlight updates. Follow `docs/RELEASE-PROCESS.md`; verify the latest build number for either route, preserve installed data, and never upload a phone-only build or change another device implicitly. Build 44 is the approved iPhone-only FPL correction; its exact status is in `docs/releases/Fotty-2.0.0-44.md`. Shared releases use the single normal Release archive/upload and independent Apple processing/group checks.

Physical acceptance uses the exact TestFlight update: verify version/build, launch, preserved preferences, narrow/Zoomed iPhone and iPad layouts, Coach keyboard, large text and current playback interactions. The historical checked items below record prior evidence, not automatic certification of every later beta. Confirm one received TestFlight report before inviting more testers.

## Automated release gate

### Football identity and live-provider drift (Unreleased)

- Generate Swift and TypeScript from the reviewed seasonal manifest and fail if
  generated output, declared club counts, aliases or validity dates drift.
- Replay `provider-football-identity-vectors.json` in both product families. The
  exact `Brighton and Hove Albion` provider spelling must resolve to the same
  club as `Brighton & Hove Albion`; former/youth/current and cup cases must stay
  distinct.
- Run `node tools/audit-provider-football-identity.mjs --live` before a shared
  release. It must reach at least one catalog feed and report zero unresolved
  top-flight marker/team pairs. It is metadata-only and must not print or probe
  stream URLs.
- Where the official schedule matches both canonical teams within six hours,
  assert its competition overrides provider/catalog inference. Without that
  proof, require explicit markers or two current senior clubs and retain
  non-domestic exclusions.
- Exported diagnostics may show the redacted reason/source class only. They must
  not contain event/team names, fixture/source IDs, URLs or credentials.
- Evidence: `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md`.

### Current Premier League membership (Unreleased)

- Assert the season-labelled official club set contains exactly 20 unique
  names. For 2026/27 it includes Coventry, Hull and Ipswich; it excludes Norwich
  plus relegated Burnley, West Ham and Wolves.
- A current/current fixture without metadata may use the Premier League roster
  fallback. Current/non-current and youth/reserve/women's fixtures must not.
- A provider's Premier League text cannot override a roster conflict. FA/EFL
  cups, Championship/lower divisions, friendlies and UEFA Europa/Conference
  remain outside the Premier League tab; explicit Champions League stays there.
- Keep legitimate non-Premier League broadcasts in All Football. Verify Home,
  club browsing/bootstrap and league-news inference use the same shared catalog.
- Evidence: `docs/audit/Fotty-Premier-League-Membership-2026-08-29.md`.

### Coach conversation ownership (Unreleased)

- Hold an injected reply, clear chat, then resolve it: nothing may reappear in
  memory or saved history. Disable consent and return a late failure: no fallback.
- Switch manager and begin another question before the old reply completes:
  only the new answer is stored and the old task cannot stop its loading state.
- Change squad, public/current gameweek, profile or rival mid-request: discard
  the outdated answer, explain why, and do not retry automatically.
- Recreate the FPL view while pending: navigation alone must preserve the task,
  input and context. Reject duplicate sends; preserve earlier follow-up messages.
- Test “What is my current total?” and equivalent explicit current-score wording
  in Swift and Worker. Undated/missing scoring stays unknown; ordinary future
  transfer/captain strategy still reaches the model stub. Never use paid calls
  to test request ownership. Evidence: `docs/audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md`.

### FPL published squad versus persistent local draft (build 44)

- Save a valid replacement, refresh full/foreground/matchday data and reopen:
  retain the draft, its manager/season, and the selected published/draft view.
- View a newly published deadline lineup without deleting the local plan. Keep
  the actual published gameweek visible; never score an older fallback against
  current live stats or treat draft multipliers/chips/history as official evidence.
- Recheck the 50-official/64-provisional goalkeeper-and-outfield autosub fixture
  before and after a hypothetical defender replacement: totals must not change.
- Reject duplicate/illegal replacements in the picker, keep the picker open
  with its reason, and never show a successful save after rejection. Exercise
  the actual UI using `testFPLSavedDraftAndPickerRejection` on Catalyst only.
- Preserve the original array for build-43 compatibility; a subsequent legacy
  edit must supersede stale companion context. Tests use isolated preferences;
  UI-fixture edits never persist in a real manager's defaults.
- Verify retained phone manager/draft/preferences before and after install,
  normal cold launch, narrow Squad source labels, and actual owner interaction.
  Public API absence before deadline publication is not a failed official save.

### Scheduled starts, compact rows and opt-in reminders (builds 39–41)

The countdown/reminder direction is now approved and implemented. The final
unit suite passes 184 tests with one optional HLS soak skipped and no runtime
warnings. Build and physical outcomes are recorded in `docs/releases/Fotty-2.0.0-41.md`.
Build 39's iPad inspection caught dimmed future names; build 40 presents the
names as readable information rather than the label of a disabled button.
Build 41 restores teams/badges left and Watch right. Saving uses the native
long-press menu/accessibility actions, not a permanent bookmark. Two scoped
Catalyst interaction tests pass, including silent save, Matchday return/removal,
channel saving and clipping/description audits. The UI runs retain two beta-Mac
main-thread warnings; they are not physical interaction certification.

- Check ordinary Home/lineup/channel rows at phone and iPad widths: Watch stays
  beside the information, not in an extra strip. Narrow/accessibility fallback
  may stack; full-width error/reminder explanations must stay readable. Long
  names and badges remain visible. Long-press Save/Remove must work on the iPad;
  saved data survives the update and no alert permission is requested by saving.
- Confirm passive Starts in before T−2 minutes, second precision inside five
  minutes, a source-backed play affordance at T−2 and Watch at T. No stream
  readiness guarantee, extra details screen, autoplay or extra provider polling.
- Save a match without receiving a prompt or scheduled reminder. Then tap
  Remind me: allow/deny permission and check truthful selected/error state.
  Opt-in saves the match; bell cancellation keeps it saved; unsave cancels both.
- Verify one scheduled alert survives a normal relaunch/locked device, tap it
  to return to the exact saved My Matchday row, and confirm no player starts.
  Dismissing a notification must not navigate. Check a removed target calmly.
- Check changed/unknown/cancelled starts, cancellation during a pending system
  response, no duplicate IDs, no overdue replay, and preservation of FPL alerts.
  Do not claim awareness of schedule changes while Fotty is closed.
- Exercise empty/failed resolution and inline Retry on the real iPad. Confirm
  channels stay usable and unknown/source-free fixtures do not claim playback.
- Light/dark/narrow previews are nonblank and inspected, but real large text,
  VoiceOver, bell taps, locked-device delivery and notification return require
  their own physical evidence. Never install a device UI-test helper.

### Appearance, sports identity and web transport (builds 36–38)

Build 38 was the prior installed iPad checkpoint. It has dedicated Appearance/no Engineering,
static NBA/MLB fallback/cache preservation, equal measured sport cells and all
sports inline on iPad, including Split View. Compact phones retain overflow.
155 unit tests pass with one optional skip and no runtime warnings; normal and
Review Safe Release plus signed Debug pass. Real Home confirms equal rows and
Yankees/Astros badges. Argument-free 20-second launch hold passes. A requested
Settings capture still showed Home and does not certify preference interaction;
the portrait masthead's scroll/safe-area state also needs a recheck.

Build 38 did not include countdown routing. The subsequently approved build-39
implementation and its separate physical acceptance are described above.

Keep Dark as the absent/invalid preference default. Verify Light and System in
Settings, return through every tab and presented form, and confirm the selection
survives relaunch without resetting the loaded FPL team/drafts. Check readable
text, selected sport/filter states, buttons and error/empty screens in both modes.
Pitch artwork and video stay dark; dismissing them must restore the chosen app
appearance. Home must show cached/provider team crests beside names and equipment
icons on sport tiles; channels/unpaired events must not invent opposing teams.

Unit regressions now resolve both light/dark palettes, verify real equipment
symbols, render bounded Home layouts and execute the injected playback script.
They are not substitutes for daylight, VoiceOver, scrolling or real touch tests.
On a decoded iPad provider feed, use the SAME centre or lower-left control for
pause and resume; compare Fotty's top-right state, wait beyond 20 seconds while
paused, and confirm no source switch/handoff resumes it. Verify unmute and popup
containment remain intact. A process hold alone never proves these interactions.

The owner explicitly requested normal-app iPad testing for this task; do not
expand it to the iPhone, simulator, device UI-test helper or TestFlight upload.
Exact outcomes and remaining acceptance are in the playback and appearance audit
records dated 2026-08-27. TestFlight remains build 35.

### Local all-sports Home patch

The approved Home concept is implemented locally, not distributed. See
`docs/audit/Fotty-All-Sports-Home-2026-08-27.md`. Validate All sports as the default,
visible next-start/activity summaries, More sports and selected-overflow
continuity, bounded mixed-sport Now & next, later-day fallback, See all on Home,
source-free Details, bookmarking and the separate personal Matchday. No source
variant or channel may inflate an event count. Retain CPL's checked-date label.
`HomeDiscoveryTests` in `BetaUsabilityTests.swift` covers policy, freshness,
identity, non-team titles and actual tile-color contrast. The explicit Debug
Home UI fixture is network-free and non-persistent.

Run all six Dashboard accessibility scopes and
`testHomeDiscoveryShowsActivityFiltersAndFullLineup` on Catalyst, alongside the
cricket channel journey. The beta-Mac contrast analyzer still reports fixed
high-contrast text despite captured-pixel and >=7:1 palette evidence. New trial
exceptions were removed; do not report that audit as clean. The final-source
gate passes 140 unit tests (one opt-in soak skipped), eight selected UI checks
(five non-contrast Home audits plus Home, cricket and setup journeys), and
unsigned normal/ReviewSafe iOS compilation. Sampled UI runs retain a main-thread
responsiveness runtime warning. Fresh TestFlight iPhone/iPad large-text, Zoom,
contrast and interaction acceptance remain separate gates. No light-mode
capability is enabled by this patch.

### Local cricket/tab-separation patch

The 27 August post-build-35 patch is not yet distributed. See
`docs/audit/Fotty-Cricket-and-Tab-Separation-2026-08-27.md` for its final-source
checks. Before its next TestFlight upload, recheck CPL league announcements.
On the TestFlight update, verify Home → Cricket filters, a saved Willow channel
in My Matchday, channel playback/control placement on iPhone/iPad, and preserved
FPL state in its own tab. Never interpret a channel listing as a confirmed CPL
programme or Catalyst playback as physical-device acceptance.

From the repository root:

```bash
tools/ios-device-qa.sh --skip-deploy

cd web
npm run test:unit
```

Run the eleven `FottyNavigationUITests` accessibility audits—six Dashboard scopes plus direct FPL, Matchday, Settings, Match Center, and Player Dynamic Type—and the rapid-navigation check individually on Mac Catalyst. Catalyst UI automation may request local macOS authentication; canceling that prompt is a harness failure, not an audit result. Never substitute a simulator run.

The runner also includes three beta-usability journeys: native Help/reporting,
FPL link entry without implicit connection, and setup navigation/dismissal.
See `docs/BETA-TESTER-GUIDE.md` for the fresh-user/recovery matrix and actual
TestFlight feedback receipt gate. A local passing test does not prove that a
report reached the owner's inbox or App Store Connect.

Catalyst interaction checks must use mouse clicks for native controls and assert
the resulting screen or selected tab. A synthesized touch tap can move the Mac
pointer without activating a control; the continued existence of a tab button
does not prove navigation. Keep Fotty foregrounded while these checks run.

The guarded runner exits before invoking XCTest when the Mac is locked:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  tools/catalyst-ui-release-gate.sh
```

Build 33 passed this complete runner in one invocation on 2026-08-26: all
eleven accessibility audits plus rapid navigation/foreground recovery. The
runner used no simulator or retry and deleted its owned DerivedData on exit.

The unreleased 2026-08-27 usability patch passed 117 policy tests (one opt-in HLS
soak skipped), both generic-iOS Release configurations, and all three new beta
journeys. Its corrected tab-selection test, Dashboard contrast/traits and Settings
Dynamic Type checks also passed. See the Decisions Log for the exact scope and
remaining beta-Mac runtime warnings. This does not extend build 33's physical
acceptance to a new distribution: check the new flows on supported hardware and
confirm a received TestFlight report before widening the tester group.

Only for explicitly requested direct-device debugging, generic iOS compile, signed installation and launch:

```bash
tools/ios-device-qa.sh \
  --device <iphone-coredevice-id> \
  --device <ipad-coredevice-id>
```

The script builds one signed universal Debug artifact, strictly verifies its seal, and installs that exact normal Fotty app on every requested device. It does not install `FottyUITests-Runner`.

After an install, the lock-aware physical process gate rejects simulators and
holds only the normal Fotty app in the foreground:

```bash
tools/ios-physical-launch-hold.sh \
  --device <physical-coredevice-id> \
  --hold-seconds 60
```

Process survival is only the cold-launch/watchdog gate; complete the visual,
audio, PiP, notification, and interaction checklist manually on the device.

For repeatable visual routing in a signed Debug normal app, terminate the
existing Fotty process and launch with `fotty://fpl` plus one bounded workspace
argument: `--fotty-fpl-workspace Plan`, `Squad`, `Coach`, or `Tools`. Release
builds ignore this QA-only argument. This is normal-app navigation only; it does
not synthesize touches or install `FottyUITests-Runner`, so keyboard, audio,
provider controls, and other interaction claims still require a person.

## Journey 1 — discover and open a match

- [x] Home has one clear `Now & next` lead and one broad live/upcoming schedule; completed fixtures do not remain scheduled content.
- [x] A `LIVE` row has a supported catalog broadcast, the whole row is actionable, and Watch opens source resolution.
- [x] A source-less active fixture says `IN PLAY` and opens Match Center rather than a dead player.
- [x] Dense fixture rows keep recognizable club names; avoid ambiguous first-letter forms such as `L. City` when a common short name exists.
- [x] `Watch 2` is hidden unless at least two otherwise-eligible events are live or within 30 minutes of kickoff and their provider families have recent decoded success.
- [x] Matchday contains only saved, followed-team, and current FPL-squad fixtures, including its bounded Recent section.
- [x] Notification taps, Matchday rows, Home rows, Match Center, and playback resolve the same fixture and teams.
- [x] Non-Premier-League rows do not say that a score is unavailable; Fotty did not promise score coverage there.

## Journey 2 — start and keep playback

- [x] A selected numbered broadcast remains selected while it negotiates the full startup window.
- [x] Provider play, pause, seek/fullscreen when offered, and `Tap to unmute` controls respond directly; Fotty does not cover the web player with a full-screen tap target.
- [x] Popups and known ad-navigation chains are contained without removing legitimate provider controls. Provider-owned in-video advertising is not presented as app-controlled.
- [x] A short pause, network transition, or recovered decoded stream does not trigger an unsolicited source replacement.
- [x] One same-source startup retry occurs before automatic failover; manual source selection always remains available.
- [x] When a verified HLS/MP4 candidate appears, native handoff has no visible jump. A later native failure returns to the same web broadcast before trying another provider.
- [x] PiP, AirPlay, and Live Activity are offered only after native capability is proven. Closing playback ends the activity and leaves no duplicate audio or ticking sound.
- [ ] With a real native handoff already playing in PiP, open a different app for at least 60 seconds and lock/unlock once. Video/audio must continue in the system window without a Fotty resume, source change or duplicate audio. This is a physical acceptance gate for the 2026-08-30 correction.
- [x] Backgrounding a web embed pauses provider/ad audio; foregrounding resumes the same selected broadcast without an unsolicited source change.
- [x] Terminal copy distinguishes device network loss, explicit provider unavailability, slow startup, unsupported media, and exhausted Fotty recovery.
- [x] A deferred opaque provider-frame failure becomes `Startup timeout` only after the complete 20-second window; an explicit provider rejection keeps its original reason.
- [x] Settings → Quality & Diagnostics records the attempt, proven start/recovery/failure, and exports only redacted local evidence.

## Journey 3 — prepare for the FPL deadline

- [x] Plan shows the official squad, local deadline, bank, estimated free transfers, validation, flags, and freshness/source.
- [x] Squad lenses switch between next fixture, modeled points, expected minutes, official form, ownership, price movement, and live points without clipping on iPhone.
- [x] Transfer Lab compares Roll, one-move, and two-move routes week by week with hit cost, break-even, downside, assumptions, confidence, and validation.
- [x] Named scenarios persist only for the current manager and season and never imply an official FPL submission.
- [x] Smart Coach Send and Return dismiss the keyboard and preserve the response at standard Dynamic Type.
- [x] Smart Coach quick prompts share the focus-clearing send path, and a structured response remains visible through the Plan/Squad/Coach/Tools large-Dynamic-Type audit.
- [x] Direct rules, deadline, captain, bench, selling-price, free-transfer, and current-points questions use the local/rules route with zero DeepSeek tokens.
- [x] A model answer includes evidence, downside, checks, freshness, source/model, and token usage; malformed, stale, contradictory, or incomplete output falls back safely.

## Journey 4 — follow the live gameweek

- [x] Live Points shows official current points first and labels a different deterministic total `PROVISIONAL`.
- [x] Goalkeeper and legal outfield autosubs are named in/out; double-gameweek players are not declared absent while a fixture remains.
- [x] Captain failure promotes a played vice-captain even when no bench replacement is possible. Bench Boost creates no autosubs. Transfer cost is deducted.
- [x] Published `automatic_subs` or a finished/data-checked event replaces every Fotty projection with official truth.
- [x] Rival Race uses only published post-deadline squads and separates official standings from live/modelled implications.
- [x] Match Center's FPL Match Lens agrees with the device-local squad and already-loaded live snapshot.

## Journey 5 — review and improve

- [x] Review records confirmed points, rank, transfer cost, bench points, captain return, and top scorer from official data.
- [x] Decision Journal entries and reflections remain manager/season scoped.
- [x] The latest reflection appears as a process lesson in the next Plan cycle without claiming the result proves causation.
- [x] Saved scenarios remain available for comparison but are clearly dated/model-versioned assumptions.

## Native system and form-factor checks

- [x] Spoiler-safe goal/full-time alerts never expose a score or the word `goal`; ordinary alerts contain the expected result.
- [x] The small and medium FPL deadline widgets show the official deadline/source and `fotty://fpl` opens the FPL tab.
- [x] An eligible Live Activity begins only after PiP is actually active and shows matchup, score, match phase, and a return cue; web embeds and ordinary foreground playback never create one.
- [x] PiP stop/failure while backgrounded pauses native playback and removes the Live Activity; temporary inactive scenes do not force PiP.
- [x] Typed Live Activity return-route tests reveal an existing matching player, or open that match's Match Center after a cold relaunch; the owner also confirmed the real system-surface return opened the correct match/player.
- [x] Cold-launch iPad for at least 60 seconds: Home remains responsive, one bounded refresh path runs, and no `0x8BADF00D` occurs.
- [x] On iPhone and iPad, inspect Home, Matchday, Match Center, Player, FPL Plan/Live/Review, Squad, Coach, Tools, and Settings at standard and large Dynamic Type; owner-confirmed on 2026-08-26.
- [x] On Mac Catalyst without a simulator, every named surface above passes the release-scope large-Dynamic-Type audit using direct deterministic presentation where live/account data is not appropriate.
- [x] VoiceOver descriptions, hit regions, contrast, element detection, and text clipping have no unresolved release-scope finding.

### Completed direct physical procedure

These checks use the installed normal app, not `FottyUITests-Runner` or a
simulator. CoreDevice launch/capture is not accepted as interaction evidence
because it cannot change Dynamic Type or tap a system surface.

1. On each form factor, note the existing text-size setting. In Settings →
   Accessibility → Display & Text Size → Larger Text, enable the accessibility
   sizes and select a clearly large size. Open Home, Matchday, Match Center,
   Player, FPL Plan/Live/Review, Squad, Coach, Tools, and Settings. Scroll and
   activate the primary action on each screen; verify content is not clipped,
   overlapped, unreachable, or replaced by unlabeled icon-only controls. On
   Coach, send one deterministic rules prompt and verify the keyboard can be
   dismissed and the answer read. Restore the owner's original text-size
   setting afterward.
2. Use a real source that completes native handoff; an ordinary WebKit embed is
   intentionally ineligible. Enter PiP and confirm the useful Live Activity.
   With the matching player still alive, tap the activity and verify it reveals
   that player without stacking a second sheet. Repeat after terminating Fotty:
   tapping the remaining system surface must cold-open the same match's Match
   Center, and stopping playback must remove the activity.
3. During an eligible followed Premier League fixture, tap one real Fotty alert
   and verify the same canonical match opens. Preserve spoiler-safe content for
   spoiler-safe alerts. Do not substitute CoreDevice's Darwin-notification
   command; it is not a user-notification interaction.
4. Record only build, device form factor, timestamp, route/result, and whether
   the action passed. Do not retain lock-screen screenshots, private stream
   URLs, notification content, or temporary device captures.

## Release evidence

- [x] Debug and the single Release generic physical-iOS graph compile; the retired `APP_REVIEW_SAFE` graph is absent.
- [x] Normal Fotty installs and launches on the supported physical iPhone and iPad; CoreDevice reports `2.0.0 (33)` and observes the exact normal app for a bounded 60-second hold on each target.
- [x] Active-match evidence records provider family, timestamp, decoded result, source changes, audible-unmute result, interruption recovery, native/PiP availability, and teardown without a private stream URL.
- [x] During an eligible followed Premier League fixture, the owner confirmed the real alert/Live Activity tap returned to the correct match/player without retaining notification content or a private stream URL.
- [x] Revoke the historically exposed Cloudflare tunnel credential; the owner-authorized deletion removed its exact retired tunnel and left the Fotty Worker healthy.
- [x] GitHub Support closed ticket `#4701297` after purging the retained objects. Both obsolete commits return `No commit found` through the authenticated API and HTTP 404 through the public web UI; all four PR refs are absent; a fresh heads/tags clone contains neither commit nor `cert.json`; `main` and tags did not move.
- [x] `git diff --check`, Worker/web unit tests, Swift unit/policy tests, and release-scope accessibility audits pass.
- [x] `CHANGELOG.md`, Roadmap, Risks, Architecture Map, Project Memory, Decisions Log, and the 2.0 completion report agree on build 33 and its single remaining Git-history security gate.


# iOS Manual Deploy Notes

# iPhone Manual Deploy

This repo now includes a repeatable device deploy script:

[`tools/ios-deploy-device.sh`](/Users/jelani/Documents/Development/Fotty/tools/ios-deploy-device.sh)

## Quick start

From the repo root:

```bash
tools/ios-deploy-device.sh
```

That will:

1. build the `Fotty` scheme for a physical iOS device
2. find the first paired iPhone destination
3. install the app with `devicectl`
4. launch `com.jelani.Fotty`

## Useful commands

List paired devices:

```bash
tools/ios-deploy-device.sh --list-devices
```

Deploy to a specific phone:

```bash
tools/ios-deploy-device.sh --device 00008130-000544A0212A001C
```

Reuse the last build and just reinstall:

```bash
tools/ios-deploy-device.sh --skip-build
```

Install without auto-launching:

```bash
tools/ios-deploy-device.sh --no-launch
```

## Notes

- The phone must be connected, paired, and unlocked.
- If iOS refuses the install because the developer image cannot mount, unlock the phone and retry.
- Default bundle ID: `com.jelani.Fotty`
- Default scheme/configuration: `Fotty` / `Debug`

## Current device

The last successful physical-device deploy in this thread used:

- device UDID: `00008130-000544A0212A001C`
- bundle ID: `com.jelani.Fotty`

So your fastest repeat command is:

```bash
tools/ios-deploy-device.sh --device 00008130-000544A0212A001C
```


# Mac Catalyst Testing Notes

# Mac Catalyst Testing

Fotty now has a repeatable Mac test path through a proper Mac Catalyst build.

## Build and launch

From the repo root:

```bash
tools/mac-catalyst-run.sh
```

This will:

1. build `Fotty`
2. target `platform=macOS,variant=Mac Catalyst`
3. open the built `.app`

## Useful variants

Build without launching:

```bash
tools/mac-catalyst-run.sh --no-open
```

Use a different configuration:

```bash
tools/mac-catalyst-run.sh --configuration Release
```

## Manual Xcode route

1. Open `/Users/jelani/Documents/Development/Fotty/Fotty.xcodeproj`
2. Select scheme: `Fotty`
3. Select destination: `My Mac (Mac Catalyst)`
4. Press Run

## Current recommendation

Use the Mac Catalyst destination for Mac testing.

Do not use the `Designed for iPad` destination as the primary Mac test path. That route was unstable on this machine and could make the Mac feel frozen under the Xcode wrapper runtime.


# TestFlight Readiness Notes

# Fotty TestFlight Readiness Checklist

## Channel and build

- Default: the existing **internal TestFlight** group, including the owner's devices.
- Use scheme `Fotty`, configuration `Release`, generic physical iOS destination, and `ExportOptions-TestFlightInternal.plist`.
- Fotty has one Release product graph. TestFlight and local Release builds use the same user-facing sports names and functionality.
- No external review submission, tester/role changes, direct device install, or Git publication is implied.

## Before archiving

- Sign in to App Store Connect and check the latest uploaded build; do not assume the local build number is current.
- Use `tools/set-version.sh` for one higher, unused Apple build number across app and extension. Keep the marketing version for iterations within the same beta release scope.
- Record passing unit/policy and relevant Catalyst UI evidence for the source being released. Compile generic iOS; no simulators on this Mac.
- Check disk space. Reuse one owned temporary DerivedData/archive/export root, build sequentially with two jobs, and install an exit/interrupt cleanup trap.

## Archive and upload

- Verify matching app/extension bundle versions, identifiers, signatures, deployment targets, production configuration and current icon.
- Automatic signing may use the existing Xcode developer account. Never put credentials in source or logs.
- Upload with symbols and `testFlightInternalTestingOnly = true`; keep Xcode's automatic build-number management disabled so source and upload agree.
- Record Apple's upload result. Then check processing completion and availability to the existing internal group; these are separate states.
- Add concise What to Test notes for the exact build, including changed screens and known limitations.
- Delete owned temporary build/export/archive artifacts after completion or failure and recheck free disk space. Keep only small release records.

## Through TestFlight, before wider invitations

- Verify version/build, launch and preserved local preferences on a supported iPhone and iPad (iOS/iPadOS 26.4+).
- Check Home, Matchday, FPL and Settings; narrow/Zoomed iPhone, large text, keyboard dismissal and iPad rotation.
- Exercise real provider playback controls and lifecycle when an active feed can be independently decoded. Report provider failures separately from app faults.
- Follow `docs/BETA-TESTER-GUIDE.md`, including one confirmed received TestFlight feedback report before widening the group.
- Keep internal users' access limited to their role. Internal testing is not App Store approval, and builds expire after 90 days.

The full release sequence and source-publication boundary are in `docs/RELEASE-PROCESS.md`.


# P2P Server README

# P2P Proxy Reliability Service

This service hardens `/proxy/acestream/stream` by:

- returning deterministic `503` JSON errors for manifest failures (timeouts, upstream status issues, empty/invalid manifests),
- validating segment URLs before exposing them to clients,
- rewriting validated segment URLs through a local proxy route,
- exposing health metrics for `manifest_ttfb`, `segment_2xx_rate`, and per-CID failure reasons.

## Run Locally

```bash
cd server
python3 p2p_proxy_service.py
```

## Docker

```bash
cd server
docker build -f Dockerfile.p2p-proxy -t fotty-p2p-proxy .
docker run --rm -p 8006:8006 fotty-p2p-proxy
```

## Environment Variables

- `P2P_UPSTREAM_BASE_URL` (default: `http://127.0.0.1:6878`,/[URL_REDACTED] the local AceStream engine)
- `P2P_API_PASSWORD` (**required** — no default in source; set in `.env` on homelab)
- `P2P_MANIFEST_TIMEOUT_SECONDS` (default: `20`)
- `P2P_ENGINE_SESSION_CREATE_TIMEOUT_SECONDS` (default: `20`)
- `P2P_ENGINE_WARMUP_TIMEOUT_SECONDS` (default: `150`)
- `P2P_SEGMENT_TIMEOUT_SECONDS` (default: `5`)
- `P2P_BROKER_RETRY_COOLDOWN_SECONDS` (default: `12`)
- `P2P_BROKER_MAX_RETRYABLE_PREPARE_ATTEMPTS` (default: `3`; repeated retryable warmup failures become a clean failed state)
- `P2P_BROKER_MANIFEST_FRESH_SECONDS` (default: `12`; cached live manifests older than this are revalidated before being served)
- `P2P_BROKER_MANIFEST_STALE_GRACE_SECONDS` (default: `15`)
- `P2P_REDIS_URL` or `REDIS_URL` (optional; enables shared broker sessions across workers)
- `P2P_REDIS_KEY_PREFIX` (default: `fotty:p2p:broker`)
- `P2P_BROKER_REDIS_RECORD_TTL_SECONDS` (default: warmup budget plus 300s)
- `P2P_BROKER_REDIS_CONNECT_TIMEOUT_SECONDS` / `P2P_BROKER_REDIS_SOCKET_TIMEOUT_SECONDS` (default: `2`; keeps Redis outages from hanging broker startup or health checks)
- `P2P_PREWARM_ENABLED` (default: off; set to `true` to keep likely channels warming before taps)
- `P2P_PREWARM_CHANNEL_SOURCE_URL` (production uses the embedded catalog at `http://127.0.0.1:8006/[URL_REDACTED]
- `P2P_PREWARM_BASE_URL` (public broker base URL used in returned session links)
- `P2P_PREWARM_INTERVAL_SECONDS` (default: `45`)
- `P2P_PREWARM_LIMIT` (default: `6`)
- `P2P_PREWARM_CONCURRENT_LIMIT` (default: `1`; keep this low because the AceStream engine does not warm many channels reliably in parallel)
- `P2P_PREWARM_MIN_AVAILABILITY` (default: `0.75`; availability is weak metadata, health still decides ranking)
- `P2P_PREWARM_EVIDENCE_MAX_AGE_SECONDS` (default: `21600`; unpinned channels need recent successful manifest/segment evidence)
- `P2P_PREWARM_PINNED_CIDS` (optional comma-separated CIDs to keep warm even after recent failures)
- `P2P_MIN_SEGMENT_BYTES` (default: `512`)
- `P2P_MAX_SEGMENTS_TO_VALIDATE` (default: `8`)
- `PORT` (default: `8006`)
- `P2P_SCRAPER_US_UK_QUERIES` (optional comma-separated AceStream text searches; default list in `p2p_scraper_queries.py` covers NFL/MLB/NHL/CBS SN, Sky F1/Golf, Racing TV, etc.)
- `P2P_SCRAPER_EXTRA_QUERIES` (optional; overrides core PL/UCL/NBA search terms)
- `P2P_SCRAPER_MAX_TEXT_QUERIES` (default: `120`; US/UK network queries are prioritized first)
- `P2P_SCRAPER_SPORT_PAGE_SIZE` / `P2P_SCRAPER_EXTRA_PAGE_SIZE` (sport category vs per-query page sizes)

Homelab redeploy after changing scraper queries:

```bash
./tools/p2p-proxy-deploy-homelab.sh
```

### Pinned channels (when Ace search has no results)

US league linear nets (NFL/MLB/NHL/CBS SN) and some UK feeds may not appear in the AceStream
engine index even with text search. Add confirmed infohashes to `server/p2p_pinned_channels.json`
(only non-empty 40-char `cid` values are merged). The homelab container mounts this file read-only
so you can update CIDs without rebuilding the image.

Probe a query on the running proxy:

```bash
curl -sS -H "Authorization: Bearer $P2P_API_PASSWORD" \
  "https://scraper.pixel-invoice.com/[URL_REDACTED] | python3 -m json.tool
```

The Docker image runs Flask through Gunicorn using `gthread`. Production explicitly uses two
workers × 16 threads with Redis. Keep `GUNICORN_WORKERS=1` when `P2P_REDIS_URL` is not set.
Once Redis is enabled, multiple workers share broker sessions, per-CID dedupe, event timelines,
and CID health history safely.

Retryable validation failures surface as `retrying` instead of an endless `warming` state. The
broker still retries them on the normal cooldown, but clients can show a clearer message while
preferring sessions that are already `ready`.

## TV guide / EPG (retired)

Homelab XMLTV/EPG infrastructure has been removed. There is no `server/epg/` bundle, no `/epg/*` broker endpoints, and no `EPG_*` env vars on this service.

## Endpoints

- `GET /proxy/acestream/stream?id=<cid>&api_password=[REDACTED]
- `POST /proxy/acestream/session`
- `GET /proxy/acestream/session/<session_id>/status`
- `GET|POST /proxy/acestream/prewarm`
- `GET /ace/proxy?cid=<cid>&url=<encoded_segment_url>`
- `GET /metrics` (broker authorization required)
- `GET /health`
- `GET /matches`, `GET /status`, and `GET /search/<query>` (broker authorization required)
- `GET /dashboard` — private Glances-style page that polls `/health` + `/metrics` every 1.5s (disabled in production; enable with `P2P_DASHBOARD_ENABLED=1` and require either broker authorization or `P2P_DASHBOARD_KEY`)

AceStream sessions request API events and stop notifications. Broker events distinguish codec
discovery, segmenter failure, engine stop, and missing `proxyServer` entitlement. Capture a
five-minute free/paid comparison with `server/scripts/acestream_premium_baseline.py`; the script
reads `P2P_API_PASSWORD` from the environment and never writes it to the result.


# Agent Start

# Fotty Agent Start Here

Before architecture work, broad refactors, release planning, or unfamiliar debugging, read:

- `agent/AGENT-START.md`
- `docs/notebooklm/Project-Memory.md`
- `docs/notebooklm/Decisions-Log.md`
- `docs/notebooklm/Architecture-Map.md`

Use the private brain when the question depends on project history:

```bash
./tools/agent-start.sh "Describe the task"
```

After significant work, update durable memory and run:

```bash
./tools/agent-finish.sh "Describe what changed"
```

## Workstation resource limits

This project is developed on a 256 GB Mac with 8 GB RAM. Treat build products
as short-lived resources:

- Never create a new DerivedData directory for every test, configuration, build
  number, or device. Reuse one bounded directory for the active gate.
- Use a cleanup trap for temporary Xcode output and delete it after the artifact
  is installed and verified, including on failure or interruption.
- Check free disk space before and after broad Xcode work. Do not leave result
  bundles, screenshots, archives, or duplicate signed apps in `/tmp`.
- Run builds sequentially and do not use simulators on this Mac.


# Agent Brain Ops Playbook

# Brain Ops Playbook

Use this when touching project memory, agent instructions, Cursor/Antigravity/Codex flow, Ollama, embeddings, or the homelab brain.

## Read First

- `AGENTS.md`
- `agent/AGENT-START.md`
- `agent/AGENTS.md`
- `agent/OPERATOR.md`
- `.cursor/rules/private-knowledge-base.mdc`
- `tools/brain/README.md`
- `tools/ask-brain.sh`
- `tools/private-kb-sync.sh`
- `tools/brain-doctor.sh`
- `tools/brain/query_brain.py`
- `tools/brain/embed_index.py`
- `server/brain_monitor.py`

## Standing Decisions

- Durable memory is markdown in this repo.
- Generated memory source is `docs/notebooklm/Fotty-NotebookLM-Source.md`.
- The remote semantic index lives at `tools/brain/.cache/knowledge.jsonl` on the homelab.
- Agents should consult the brain before architecture work, broad refactors, release checks, and unfamiliar debugging.
- Brain scripts must stay safe around secrets and private stream URLs.

## Common Failure Points

- Docs referring to commands that do not exist.
- The indexer looking for a different generated source filename than the generator writes.
- Local scripts updated but not pushed to the homelab.
- Agent rules becoming advisory prose without executable checks.
- Empty or stale indexes silently producing weak guidance.

## Verification

- Run `bash -n tools/*.sh` for touched shell scripts.
- Run `python3 -m py_compile tools/brain/*.py server/brain_monitor.py` for touched Python.
- Run `./tools/private-kb-sync.sh`.
- Run `./tools/brain-doctor.sh`.
- Ask a smoke question with `./tools/ask-brain.sh`.

## Brain Prompts

```bash
./tools/ask-brain.sh "What should agents read before working on Fotty?"
./tools/ask-brain.sh "What can make the Fotty Brain stale or misleading?"
```


# Agent Playback Playbook

# Playback Playbook

Use this when touching player startup, AVPlayer, WKWebView embeds, VOD playback, stream selection, autoplay, or timeout behavior.

## Read First

- `docs/notebooklm/Project-Memory.md`
- `docs/notebooklm/Decisions-Log.md`
- `docs/notebooklm/Risks.md`
- `Fotty/Features/Player/LivePlayerView.swift`
- `Fotty/Features/Player/LivePlayerViewModel.swift`
- `Fotty/Features/Player/VideoPlayerView.swift`
- `Fotty/Core/Internal/HybridStreamProvider.swift`
- `Fotty/Core/Internal/WebViewRenderer.swift`

## Standing Decisions

- Surface observation must not delay or cancel provider taps. Use passive DOM click observation in the web frame tree, not a UIKit gesture recognizer above WKWebView. Prevent popup navigation without swallowing legitimate provider button handlers.
- Keep actual decoded-video transport state scoped to document/source/attempt. A deliberate pause cannot be undone by delayed stall/recovery/native-handoff work; a transient interruption must still recover. Execute monitor JavaScript in tests, not only parse its syntax.
- Video/player chrome remains dark when the browsing UI is Light or System. Dismissing the player restores the selected app appearance.

- Playback must show immediate feedback, but a web embed gets 20 seconds to prove decoded startup and one controlled same-source reload before failover. Explicit provider rejection skips that grace.
- Avoid cascading timeouts; the one web reload is the bounded exception and must stay keyed to the current source/attempt.
- Broadcast source switching belongs below the player in the available sources section.
- First successful stream resolution should cancel competing resolution work.
- WebView automation must quiesce after real playback starts.
- Once decoded playback starts, network-path and scene transitions must preserve the exact source attempt. Retry that item/source before considering failover.
- Delayed failures must match both source ID and attempt ID; source ID alone is insufficient after a reload.
- Catalog choices represent distinct broadcasts: collapse a channel's HD/SD pair to HD, preserve provider-family diversity, and never mix synthesized zero-variant rows into an event with real variants.
- Block provider popup windows, top-level click-throughs, `embed.st/ad.html`, and known nuisance hosts without removing generic overlays or player controls.
- In the standard web player, provider controls are canonical. Never place a parent tap gesture above the WKWebView, add a duplicate unmute button, remove its mute prompt, or continuously force mute/volume state. App-controlled web mute synchronization is limited to MultiView focus and explicitly muted diagnostics.

## Common Failure Points

- Web embed autoplay loops that keep tapping after playback begins.
- Source validation taking long enough that the player feels dead.
- AVPlayer readiness waiting too late to request playback.
- UI offering multiple places to switch streams.
- Raw provider URLs or internals leaking into user-facing failure states.
- Treating a loaded embed shell, viewer count, or catalog variant as proof of decoded playback.

## Verification

- Cold open a live match and confirm player feedback appears immediately.
- Confirm a successful source starts without extra taps.
- Confirm a slow first load retries the same source once before any source-index change.
- Confirm the source picker has distinct language/channel rows rather than adjacent HD/SD duplicates or fabricated empty-family variants.
- Inspect WebKit pages/frames after play: popup count should remain zero, ad frames should be absent, and video/player-control elements must remain present.
- On a decoding physical-device stream, independently exercise the provider's play, pause, seek/fullscreen when available, and `Tap to unmute`. Confirm Fotty does not consume the tap or immediately undo the resulting state.
- Confirm failure returns the user to broadcast sources calmly.
- Switch between regular, web embed, and P2P sources where available.
- Check that pause/play does not loop by itself after WebView handoff.
- Run the focused Catalyst policy suite without a simulator. For an intentional device or Catalyst reference-HLS check, run only `PlaybackPolicyTests/testReferenceHLSMaintainsOneAttemptDuringSoak` with `OTHER_SWIFT_FLAGS='$(inherited) -DFOTTY_PLAYBACK_SOAK'`; the diagnostic player must remain muted. Catalyst runs for 120 seconds and should show advancing playback on every sample with unchanged source/attempt/item and zero failovers.
- DEBUG Settings → Stream pipeline checks exposes the same production-path two-minute muted soak for manual use on Mac Catalyst. It exercises required-header proxying, AVPlayer readiness, watchdog continuity, and failover accounting; it does not exercise a third-party WebKit embed.
- When a live provider event is available, follow the reference soak with a muted Catalyst Watch Live hold. Record the provider/source label, starting and ending broadcast clocks, any focus/background transition, and whether loading, error, or source-replacement UI appeared. Treat that as time-scoped provider evidence, never a general uptime guarantee.

## Brain Prompts

```bash
./tools/ask-brain.sh "What playback decisions affect this change?"
./tools/ask-brain.sh "What are the current Fotty playback risks and verification checks?"
```


# Agent P2P Server Playbook

# P2P Server Playbook

Use this when touching the homelab broker, proxy, manifest generation, warmup behavior, Docker compose, or server-side stream health. (Server-side EPG/XMLTV was removed with the retired homelab guide pipeline.)

## Read First

- `docs/notebooklm/Project-Memory.md`
- `docs/notebooklm/Decisions-Log.md`
- `docs/notebooklm/Risks.md`
- `server/README_P2P_PROXY.md`
- `server/homelab-docker-compose.yml`
- `server/p2p_proxy_service.py`
- `server/p2p_proxy_core.py`
- `server/tests/test_p2p_proxy_service.py`

## Standing Decisions

- P2P is a resilient fallback, not a reason to block the whole player.
- Reuse warm sessions when available.
- Keep server behavior observable through explicit health/progress states.
- Keep `GUNICORN_WORKERS=1` unless the concurrency model is deliberately redesigned.
- Do not expose secrets, raw stream URLs, or private provider internals in docs or user-visible errors.

## Common Failure Points

- Cold P2P startup exceeding the user’s patience window.
- Stale manifests or segment authorization mismatches after session reuse.
- Background work continuing after the client has moved to another source.
- Compose changes that desync the homelab from local scripts.
- Logs or generated memory docs accidentally containing private URLs.

## Verification

- Run focused Python tests for changed proxy behavior.
- Confirm warm source reuse still works.
- Confirm failed P2P source returns useful state instead of hanging.
- Re-run `./tools/brain-doctor.sh` after homelab script or compose changes.

## Brain Prompts

```bash
./tools/ask-brain.sh "What P2P broker decisions affect this change?"
./tools/ask-brain.sh "What are the known P2P startup and warm-session risks?"
```


# Git Working Tree Snapshot

```text
 M Fotty/App/FottyApp.swift
 M Fotty/Features/Player/LivePlayerView.swift
 M Fotty/Features/Player/LivePlayerViewModel.swift
 M FottyTests/PlaybackPolicyTests.swift
 M docs/beta/ROUND-01-ACCEPTANCE.md
 M docs/notebooklm/Architecture-Map.md
 M docs/notebooklm/Decisions-Log.md
 M docs/notebooklm/Fotty-NotebookLM-Source.md
 M docs/notebooklm/Project-Memory.md
 M docs/notebooklm/QA-Playbook.md
 M docs/notebooklm/Risks.md

```


# Recent iOS Player Files

```text
Fotty/Features/Player/LivePlayerView.swift
Fotty/Features/Player/LivePlayerViewModel.swift
Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift
Fotty/Features/Player/Components/LiveStreamDebugSheet.swift
Fotty/Features/Player/Components/PlaybackErrorOverlay.swift
Fotty/Features/Player/Components/PlaybackControlsOverlay.swift
Fotty/Features/Player/Components/LoadingStateOverlay.swift
Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift
Fotty/Features/Player/MultiLivePlayerView.swift

```


# Recent P2P Server Files

```text
server/Dockerfile.brain-monitor
server/p2p_scraper_queries.py
server/p2p_config.py
server/tests/test_p2p_scraper_queries.py
server/tests/test_p2p_proxy_service.py
server/tests/test_p2p_pinned_channels.py
server/Dockerfile.p2p-proxy
server/p2p-stack-updated.yml
server/p2p_pinned_channels.json
server/brain_monitor.py
server/p2p_proxy_core.py
server/monitor_manifest_v2.py
server/monitor_manifest.py
server/p2p_pinned_channels.py
server/p2p_proxy_service.py

```
