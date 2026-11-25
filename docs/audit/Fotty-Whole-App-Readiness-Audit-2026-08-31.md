# Fotty Whole-App Readiness Audit

**Audit date:** 2026-08-31  
**Audited version:** 2.0.0 (49) working source; TestFlight remains build 48  
**Release lane:** private owner pre-test first; TestFlight only for a coherent, significant milestone  
**Audit target:** determine whether Fotty is ready to expand beyond its current trusted testers, and identify the shortest responsible path there

## Verdict

Fotty is no longer a prototype. Its core architecture, data rules, playback recovery policy, FPL scoring safeguards, local persistence and automated regression coverage are materially stronger than an average small private app.

It is **ready for continued owner/private pre-testing**, but it is **not yet qualified for a wider tester expansion**. The blocker is not a missing headline feature. The blocker is that a small set of high-impact, hardware-dependent workflows have not been proven together on the exact candidate build:

1. Native Picture in Picture while switching apps and locking/unlocking the device.
2. Encrypted backup export, wrong-password rejection and restore through the real Files UI.
3. A fresh first-use pass by someone who did not help build the app.
4. A real live-broadcast soak covering pause/resume, interruption, network recovery and source failover.
5. Final light/dark, Dynamic Type and VoiceOver acceptance on both iPhone and iPad.

The correct next milestone is therefore **release qualification and simplification**, not another feature wave.

## Evidence scale

- **Proven:** deterministic automated test or current build gate passed.
- **Observed:** confirmed manually on hardware, but not fully repeatable in automation.
- **Open:** not yet verified on the exact candidate build or has a material unresolved decision.
- **Dormant:** compiled into the project but not reachable from the current product.

## Product map and screen-by-screen audit

### 1. App shell and navigation — AMBER/GREEN

Current user-facing tabs are:

- **Home:** cross-sport discovery and the complete live/upcoming catalog.
- **Matchday:** personal list of saved broadcasts and fixtures involving followed teams.
- **FPL:** gameweek, squad, Coach and planning tools.
- **Settings:** preferences, playback sources, notifications, privacy, recovery and support.

What is good:

- Home and Matchday now have distinct jobs.
- FPL is not required to use discovery or Matchday.
- Tab state is deliberately retained, including the active FPL workspace/tool.
- Typed deep links exist for Matchday reminders, FPL and match/player destinations.
- The tab bar and decorative icons now expose cleaner accessibility semantics.

What remains:

- Run first-use navigation with a new tester who has no project context.
- Confirm every deep link from notification, widget and Live Activity on the exact release candidate.
- Decide whether FPL is a co-primary product pillar or an optional power-user module; the current shell treats it as co-primary.

### 2. Home discovery — AMBER/GREEN

Reachable surfaces and options:

- Sport activity grid with responsive phone/iPad layouts.
- Live and upcoming event rows across football, basketball, baseball, cricket and other provider categories.
- Sport and competition filters.
- Global search across sports, leagues, fixtures and channels.
- Full-lineup browsing.
- Event detail sheet, Watch action, countdown/reminder behavior and Matchday save action.
- Multi-view entry where timing and source availability permit it.

What is proven:

- Event deduplication, doubleheader preservation, source-variant preservation and stable ordering.
- Upcoming/channel listings cannot falsely become live merely because a provider record exists.
- Finished schedules expire correctly and official status wins over estimates.
- Sports tiles use equal responsive sizing; iPad can show the broader catalog without the compact overflow treatment.
- Team rows use the shared badge contract; non-team channels do not invent opponents.
- Search cannot create a competing or inconsistent catalog.
- Current source-controlled badge audit: **272/272 valid artwork URLs**.
- Current live feed badge audit: **128/128 provider image tokens valid** across 309 events; missing provider artwork falls back to reviewed artwork or an honest monogram.

What remains:

- Fresh live-catalog acceptance during several simultaneous broadcasts.
- Confirm the final badge animation and light-mode treatment on physical iPhone and iPad with Reduce Motion both on and off.
- Provider schedules remain external data; release readiness depends on graceful truthfulness when they are incomplete, not an impossible guarantee that they are always correct.

### 3. Search and full lineup — GREEN/AMBER

What is proven:

- Search uses Home's catalog rather than maintaining a second feed.
- It searches reviewed non-football leagues and provider identities.
- Long names, channels, upcoming events and large text have render tests.

What remains:

- One fresh tester task: “Find a non-featured cricket or basketball event without being told where to tap.”
- Confirm empty, offline and provider-timeout states on hardware.

### 4. My Matchday — AMBER/GREEN

Reachable surfaces and options:

- Saved broadcasts.
- Fixtures involving followed teams.
- Follow-management entry.
- Kickoff conflicts.
- Opt-in five-minute reminders.
- Watch action only when playback is honestly eligible.
- Reminder return target and dismissal.

What is proven:

- Saving alone is silent; notification permission is requested only after explicit reminder opt-in.
- Denied permission, cancellation races, rescheduling, postponed/cancelled fixtures and reminder caps are handled truthfully.
- Reminder deep links target Matchday, not an unavailable player.
- Saved identities survive provider date faults and are pruned only after the continuity window.

What remains:

- Fresh hardware test of schedule change, notification delivery with Fotty closed and return routing on build 49 or its successor.
- Confirm reminder copy is understood by a new tester without explanation.

### 5. Event details and Match Center — AMBER

Reachable surfaces and options:

- Catalog event details from Home/Matchday.
- Match Center through typed routes, selected highlights/match presentation and Live Activity return.
- Premier League live score/minute where confirmed and in scope.
- Timeline, statistics, insight and tactical surfaces when upstream data exists.

What is proven:

- Only Premier League live scores are enabled for now.
- Current and prior-season membership rules are generated from one reviewed catalog.
- Canonical fixture identity survives catalog, score, FPL, notification and playback boundaries.
- Scores cannot leak onto an out-of-scope competition or an older meeting between the same teams.
- Production Worker health currently reports schedule credentials configured, Premier League competition `39`, an 80-call budget and no quota consumption at the time of audit.

What remains:

- Match Center has several data-dependent empty states; each must be reviewed with a real sparse and a real rich fixture.
- `InsightsHubView` and `YouTubeHighlightsView` appear dormant while the current Match Center has its own routed tabs. Remove or archive the unused alternatives after the owner decision on dormant code.

### 6. Broadcast resolution and source selection — AMBER, HIGH IMPACT

What is proven:

- Enabled source modules are enforced.
- Distinct broadcasts and provider diversity are preserved.
- Circuit-breaking, bounded retries, truthful timeout classification and stale-attempt rejection have regression tests.
- A transient network loss preserves the current attempt before failover.
- Upcoming events cannot begin resolution through a direct or hidden action.
- The internal pipeline-validation screen is not exposed to ordinary users.

What remains:

- Provider success cannot be guaranteed; the release promise must be that Fotty does not abandon or replace a healthy stream prematurely.
- Run a real simultaneous-match source-resolution soak and capture local quality evidence.
- `LiveStreamDebugSheet` has presentation code but no reachable trigger. Either wire it into a deliberate developer-only route or remove it.
- Legacy P2P implementation files remain large and partly referenced by warmup/resolution internals even though active-player policy rejects P2P-shaped streams. The boundary needs a focused cleanup after current playback behavior is frozen.

### 7. Player, controls and interruptions — AMBER, HIGHEST RISK

Reachable surfaces and options:

- Native AVPlayer playback where a direct media source can be resolved.
- Embedded web playback where native extraction is unavailable.
- Center and overlay play/pause behavior.
- Mute/unmute and volume state.
- Source selector and explicit retry.
- Full-screen/orientation handling.
- Native Picture in Picture when capability is actually ready.
- Two-event MultiLive player.
- Sport-aware loading and error states.

What is proven:

- State-machine tests prevent contradictory loading/playing states and stale callbacks replacing the active attempt.
- Web transport commands, provider-reported state, pause persistence, background suspension and handoff behavior are tested at the policy/bridge level.
- Native PiP lifecycle policy, background cleanup and Live Activity eligibility are tested.
- The user has confirmed iPad pause/unmute and iPhone audio/control fixes in earlier private builds.
- Full stream URLs are no longer printed in production diagnostics; debug logging now removes credentials, query strings and fragments.

What remains:

- **Release blocker:** physical native PiP must keep playing when another app opens, and survive lock/unlock where iOS permits it.
- **Release blocker:** a real live stream must pass a sustained pause/resume, network interruption and recovery soak without duplicate background audio or unintended source switching.
- MultiLive needs a fresh iPad acceptance pass.
- Embedded playback is inherently less controllable than native playback; the UI must continue to state capability truthfully rather than imply every source supports native controls or PiP.

### 8. Live Activity, notifications and widget — AMBER/GREEN

What is proven or observed:

- Widget and Live Activity routing are typed and regression-tested.
- Live Activity creation is limited to useful native playback state; web embeds do not create a misleading playback Live Activity.
- Backgrounded playback without active PiP is removed rather than left as a false persistent activity.
- The user has observed the revised live alert behavior and confirmed the widget works.

What remains:

- One exact-build pass covering start, update, force-close expectation, natural end and stale-activity cleanup.
- Confirm every displayed field remains useful when score data is unavailable.

### 9. FPL connection and official data — AMBER/GREEN

Reachable top-level workspaces:

- **Gameweek**
- **Squad**
- **Coach**
- **Tools**

Reachable tools:

- Transfer Lab
- Captain
- Live Points
- Price Radar
- Wildcard Solver
- Compare Players
- Plan Ahead
- Fixture Difficulty
- Mini-leagues
- Rival Race
- Decision Journal

What is proven:

- Manager input accepts numeric IDs and official team links, rejects untrusted links and protects against late/cancelled identity races.
- Published squad and local draft are deliberately separate; official refresh does not erase local planned changes.
- Drafts, scenarios, decision journal and selected view survive relaunch and remain manager-scoped.
- Season rollover, cache freshness, official fixture phase, transfer cost, chips, double-gameweeks and manager/league contracts have deterministic tests.
- Current scoring and autosub rules are computed from official evidence rather than delegated to the language model.

What remains:

- Fresh real-manager validation across published squad, a local draft, a completed gameweek and the current gameweek.
- Decide whether all 11 tools are release-grade for every tester or whether the Tools workspace should explicitly label advanced/experimental capabilities.
- The optimizer and several FPL loading/analysis paths remain complexity hotspots and deserve extraction before major new FPL features.

### 10. Smart Coach — AMBER

What is proven:

- Coach still uses the configured DeepSeek model for appropriate strategy questions.
- Current score, autosub and verified-rule questions are routed to deterministic official-data logic.
- Missing or stale official evidence cannot be turned into a fabricated current total by the model.
- Rate limiting, request-size validation, consent revocation, manager/context races and structured-response validation are tested.
- Production Worker advertises the configured Coach model and active rate-limit bindings.

What remains:

- Local Worker code and production deployment need an explicit version/hash handshake; a health response proves availability, not that production contains the newest local classifier.
- Strategy usefulness needs a small, reviewed evaluation set: captain choice, transfer choice, chip timing, injury uncertainty and adversarial “agree with my wrong total” prompts.
- Coach is useful only when it clearly distinguishes official fact, projection and opinion in every response.

### 11. Settings and every user option — AMBER/GREEN

Reachable groups after the approved cleanup:

- **Preferences:** Appearance; Favorite Teams; Favorite Leagues.
- **Playback:** Broadcast Sources, with two built-in web sources that can be enabled/disabled.
- **Match updates:** kickoff, goal, full-time and spoiler-safe in-app updates.
- **FPL deadline reminders:** FPL plan entry and system-notification state.
- **Privacy & Security:** local/network explanations, encrypted backup, quality diagnostics, legal links and local-history clearing.
- **Support & About:** native Help, problem report and exact app version/build.

What is good:

- Appearance has a dedicated, conventional destination.
- Engineering/pipeline controls are not visible to normal users.
- In-app match updates and true background reminders are explained as different things.
- Feedback includes build/context while diagnostics remain opt-in.
- The app reports its exact version and build.

What remains:

- Verify all legal URLs and support destinations before the next TestFlight milestone.
- The profile/avatar surface and its photo-library permission are removed because they had no remaining non-social job.
- Confirm Broadcast Sources is understandable to a nontechnical tester; source-provider internals should not become user burden.

### 12. Appearance, layout and accessibility — AMBER

What is proven:

- Dark is the default; Light and System are explicit saved options.
- Core palette pairs pass deterministic contrast calculations in both modes.
- Narrow-phone and iPad layout tests cover Home, appearance controls, upcoming rows and major FPL labels.
- Catalyst audits passed current hit-region, clipping and core Dynamic Type checks for Home, Matchday, FPL, Settings, Match Center and Player.
- The newly loaded badge bitmap accessibility defect was fixed by giving the actual rendered image a truthful team-badge label.
- Continuous animations honor Reduce Motion, foreground state and low-power policy.

What remains:

- Catalyst accessibility automation is flaky on this beta toolchain and can hang before test execution. The workflow needs a hard process timeout and clean relaunch.
- Catalyst reported a likely false-positive contrast failure for a team-name text node despite the verified palette ratio. Do not waive it until VoiceOver/Accessibility Inspector is checked on physical hardware.
- Complete a physical light/dark, extra-large text, Reduce Motion and VoiceOver pass on both form factors.

### 13. Privacy, security and recovery — AMBER, RELEASE BLOCKER

What is proven:

- Provider credentials are expected at the Worker boundary; the app plist contains build-setting placeholders rather than hard-coded values.
- ATS does not allow arbitrary application traffic. Arbitrary web content and local networking are enabled because embedded playback and the local media proxy require them.
- Quality diagnostics are local, bounded to 250 records/14 days and reject URLs, credentials, free-form text and manager IDs.
- Backups use a 16-byte salt, PBKDF2-HMAC-SHA256, AES-256-GCM, size limits, authenticated decryption and all-or-nothing validation.
- Backup tests cover correct-password round trip, wrong-password rejection, excluded sensitive/provider data, consent revocation and non-mutating invalid restore.
- Full intercepted stream URLs have been removed from production logging.

What remains:

- **Release blocker:** real Files export/import, wrong-password and restore must be tested on iPhone and iPad.
- The privacy manifest now uses Apple's current schema and declares only the active transmitted boundary: public FPL manager ID, installation identifier and opt-in Coach question/context. Local diagnostics are not declared as collected because they are never uploaded automatically.
- No automatic remote diagnostics is a privacy strength, but it means release triage relies on TestFlight crash reports plus user-exported local evidence. Confirm that tradeoff is intentional.

### 14. Persistence and migration — AMBER/GREEN

What is proven:

- SwiftData is used for follows, cached match records and compatibility tombstones from the retired social/profile graph; user defaults hold bounded preferences and FPL state.
- Current migrations preserve manager-scoped draft/planning state and reject stale live/season data.
- Encrypted backup deliberately excludes provider URLs, stale media routes, Coach conversation, AI consent, reminders and diagnostics.

What remains:

- Restore must be proven against a real existing install, not only an isolated test store.
- Persistent-store fallback is now visible in Settings as a non-saving warning rather than silently pretending an in-memory session is durable.

### 15. Worker, web companion and operating cost — AMBER/GREEN

What is proven:

- **75/75** web/Worker tests pass, including the Worker source-version health contract.
- Worker dry-run packaging succeeds at roughly 59 KiB uncompressed / 16 KiB gzip.
- Production `/health` currently responds successfully with football schedule/live-score configuration and quota state.
- Coach request and capacity rate limits are configured.

What remains:

- ESLint has **0 errors but 48 warnings**, including React state/effect warnings in player, polling, schedule and recovery code. These should become a bounded cleanup milestone rather than permanent baseline noise.
- Local Worker source now publishes a non-secret `sourceVersion` in `/health`; it remains unproven in production until the next separately authorized Worker deployment.
- Define one lightweight availability/quota check that does not spend live-score budget unnecessarily.

### 16. Maintainability and dormant code — AMBER/RED

Pre-cleanup scale:

- 159 production Swift files.
- Approximately 55,568 production Swift lines.
- 238 iOS unit/policy tests and 20 UI tests.
- Complexity hotspots include the web embed message handler, playback warmup, FPL optimizer/loading paths and Worker Coach/evidence/scoring functions.

Post-cleanup source check:

- 140 production Swift files and 50,144 lines.
- The explicitly retired graph removes 5,165 lines without deleting the compatibility model metadata needed by existing private stores.

Dormant or unclear production code found and retired after owner approval:

- `SocialHubView` and its local chat/explore/following/notification stack: roughly 3,000 lines in the inspected primary files, with no route from the current tab shell.
- `YouTubeHighlightsView`: defined but no reachable call site found.
- `MockMatchService`: defined but no production call site found.
- `StreamPipelineValidationView`: intentionally not linked from user settings.
- `LiveStreamDebugSheet`: sheet exists, but no trigger sets it visible.
- A separate `InsightsHubView` exists alongside the current Match Center tab structure and appears dormant.

Implemented boundary:

- The unreachable social/chat/profile, mock-match, old insights/highlights and stream-debug/validation surfaces are removed from the production graph. SwiftData compatibility model metadata remains temporarily so existing private installs are readable.
- No customer-facing or hidden developer validation UI remains in the app target.
- Refactor high-complexity paths only after the current behavior is captured by tests; do not combine cleanup with a new playback algorithm.

## Current verification ledger

Passed during this audit:

- Simulator-free iOS unit/policy gate.
- Generic iOS Release build with code signing disabled.
- 238 discovered iOS unit/policy tests in the current suite.
- 75/75 web and Worker tests.
- Worker packaging dry run.
- ESLint: 0 errors, 48 warnings.
- 272/272 source-controlled badge artwork URLs.
- 128/128 current live provider badge tokens.
- Production Worker health probe.
- `git diff --check` before the final privacy-log edit; run again at close.

Partially passed during this audit:

- Catalyst UI checks for hit regions, text clipping, major-screen Dynamic Type, FPL state retention and key FPL interaction behavior.
- Badge bitmap accessibility failure was reproduced, fixed and its focused description audit passed.

Still open:

- Full Catalyst UI suite completion because the beta automation service intermittently hangs before enabling automation.
- Physical-device qualification gates listed below.

## Recommended milestone: 2.0 private beta qualification

### Phase A — simplify and make evidence trustworthy

1. Decide and remove/archive dormant social, mock, old insights/highlights and unreachable debug code.
2. Add Worker deploy identity to `/health` and the release record.
3. Reconcile the privacy manifest with actual transmitted data.
4. Make persistent-store fallback user-visible rather than silently non-persistent.
5. Reduce lint baseline around playback/polling first; do not spend time polishing unused web demo warnings before active player warnings.

### Phase B — exact-build automated gate

1. Simulator-free iOS tests and generic Release build.
2. Web/Worker unit tests, lint and Worker dry-run.
3. Provider identity, current-season competition and live badge audits.
4. Bounded Catalyst UI tests with hard timeout, retry and guaranteed cleanup.
5. Record exact app build plus Worker deployment identity.

### Phase C — physical iPhone and iPad gate

1. Fresh install/onboarding and restore-over-existing-install.
2. Cross-sport discovery, search, save, reminder and Matchday return.
3. Native and web playback: pause/resume, mute, rotation, source change, interruption and network recovery.
4. Native PiP: switch app, lock/unlock and return.
5. MultiLive on iPad.
6. Light/dark/System, large text, Reduce Motion and VoiceOver.
7. FPL manager connect, published-vs-draft state, live points/autosubs and three Coach evaluation prompts.
8. Live Activity and widget start/update/return/end.

### Phase D — outsider beta task

Give one trusted tester the build without coaching and ask them to:

1. Find and watch a live non-football event.
2. Find an upcoming event, save it and set a reminder.
3. Return through the reminder and understand why Watch is or is not available.
4. Connect an FPL manager and explain the difference between published squad and planned draft.
5. Report a problem with enough evidence for diagnosis.

Do not expand the group until all five tasks are understandable without live help.

## Release thresholds

The next TestFlight candidate is ready to expand when:

- No critical crash, data-loss, duplicate-audio or uncontrollable-playback defect remains.
- The four physical release blockers pass on the exact candidate build.
- Worker deployment identity matches the release record.
- A new tester completes the five outsider tasks without developer guidance.
- Provider failures produce truthful, recoverable UI rather than false “live,” false “playing” or unexplained empty states.
- All created build/test output is deleted or intentionally retained as a single named release artifact.

## Owner decisions — resolved 31 August 2026

The owner approved every recommendation below for the current implementation and qualification cycle:

1. **Primary promise:** discovery/playback is the universal promise; FPL is a first-class optional module. This hierarchy is stated in Help while Home and Matchday remain free of FPL promotion.

2. **Dormant social product:** retire the unreachable community/chat/profile stack. The local profile/photo UI had no remaining job and is removed; compatibility model metadata stays until a safe measured migration can remove it.

3. **FPL tool exposure:** keep Gameweek, Squad and Coach primary. Tools remains secondary and every tool now identifies its evidence class; no local plan or model output is presented as an official transaction.

4. **Compatibility policy:** keep iOS/iPadOS 26.4+ intentionally for this private cycle; broaden only after real older-device qualification.

5. **Beta success threshold:** start with 3–5 trusted testers for one seven-day daily-use qualification and expand only after the release thresholds pass. See `docs/beta/PRIVATE-QUALIFICATION-2.0.md`.

The same pass also reconciles the privacy manifest, makes persistence failure visible and prepares a Worker source identity. The Worker identity is source-only until a separately authorized deployment; this audit does not imply a TestFlight upload, device install or service deployment.
