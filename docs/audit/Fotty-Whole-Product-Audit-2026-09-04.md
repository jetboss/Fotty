# Fotty Sports Hub — comprehensive product audit

Date: 4 September 2026  
Purpose: explain what works, what still undermines everyday use, and what would make Fotty genuinely better for its owner and private testers.  
Status: audit and recommendations only; no application, backend, device, distribution or tester changes.

## The conclusion in plain English

Fotty is a feature-rich private beta with a worthwhile identity. Its main weakness is **consistency between features**, not a shortage of features or the need for another redesign.

Home can find something that Matchday cannot open. A team can have the right badge but be followed under the wrong sport. The main FPL score can refresh correctly while a rival comparison remains old. A transfer suggestion can look sensible in isolation but fail when combined with another suggestion.

There are also two less visible priorities: tighten the native playback relay's security boundary, and protect the paid Coach service with real access and spending controls. These are source-level risks, not evidence of an attack or unauthorized spending.

My recommendation is a **Trust and Daily Use milestone**, followed by one deliberately qualified private TestFlight batch. Do not expand the tester group or add another collection of tools before the high-priority journeys are dependable.

## What this audit actually covered

Four parallel reviewers inspected current source, tests and durable release records. The review followed actions across screens rather than treating each screen as an isolated component.

| Area | Coverage and assessment |
| --- | --- |
| First use and onboarding | Optional setup is good; multisport team identity is not preserved correctly. |
| Home and all-sports discovery | Strong direction; catalog completeness, refresh order and truthful failure states need work. |
| Sport/competition filters and Search | Shared catalog is a strength; browsing-state retention and empty-search recovery need attention. |
| Matchday, saved items and follows | Distinct purpose is right; saved CPL playback, aliases and league preferences are not consistently connected. |
| Match details, insights, scores and lineups | One refresh does not currently update every visible section coherently. |
| Stream discovery and provider selection | Recent identity/alternative repairs are valuable; sequential shared-provider discovery remains a bottleneck. |
| Native and web playback, controls, PiP and recovery | Reviewed current ownership/retry architecture and prior evidence; new relay security/resource findings. No new decoded-device acceptance in this audit. |
| MultiView, interruptions and media lifecycle | Included in playback boundary review; simultaneous-stream heat, sound focus and long-session device behavior remain physical checks. |
| FPL connection, squad and live points | Strong public-data/draft boundary and recently repaired coherent scoring refresh. |
| FPL rivals, transfers, chips and wildcard tools | Several distinct stale-state and plan-validity gaps remain. |
| FPL comparisons, scenarios and journal | Already substantial; evidence refresh, replayable plans and intended-gameweek attribution need improvement. |
| Coach reasoning, evidence, consent and cost | Useful constrained foundation; named-player coverage, factual assurance and paid-service protection need strengthening. |
| Reminders, notifications, widgets and Live Activities | Existing functionality, not proposed new features; FPL reminder controls/routing and cross-screen status consistency need finishing. Exact-build system behavior remains a device gate. |
| Settings, light/dark/system and accessibility | Good overall structure; some older settings screens retain fixed text, missing accessibility state and a forced-dark override. |
| Persistence, encrypted backup and privacy | Encryption/exclusion/validation safeguards exist; save-failure visibility and physical restore qualification remain gaps. |
| Feedback and tester support | Honest opt-in report preparation exists; delivery is still a separate manual step. |
| Worker, quotas, monitoring and dependencies | Good foundations in live-score budgeting and metadata checks; weaker boundaries elsewhere. |
| Release process, source recovery and workstation use | Sensible written gates and cleanup discipline; exact-candidate evidence and source reproducibility need consolidation. |

This is not a penetration test, a measurement of production uptime, or a visual certification of every screen. The existing 30 August iPad Home screenshot was inspected as a design reference, not passed off as the current build. No simulator, fresh Xcode build, device interaction, paid Coach request, production setting change or full-broadcast recording was used.

### Verification available

- **Fresh in this audit:** 71 web/Worker unit tests passed, zero failures or skips.
- **Fresh:** generated football catalog check, five provider identity vectors and structural validation of the 39-fixture CPL manifest passed. These offline checks do not establish today's provider availability or independently confirm today's schedule.
- **Fresh:** npm's advisory audit reported zero known dependency vulnerabilities. This does not certify Fotty's own code or absence of unknown vulnerabilities.
- **Prior exact local-source gate, not rerun here:** the recent reliability batch passed 326 Catalyst tests, zero failures and two intentional live-test skips; generic iOS Release compilation passed. See the reliability report linked below.
- **Not established here:** current production access controls/billing limits, received tester feedback, battery/thermal performance, current device controls, native PiP continuity, physical Files restore, or all-screen VoiceOver/large-text/light-mode behavior.

Recorded distribution is still TestFlight 55 and Jet iPad 58. The newer five reliability fixes are local source changes after build 58, not installed fixes. Those five are **not reopened** by this report: exact shared match identity, owned delayed retries, selected-media ownership, concrete alternative preservation and coherent main FPL scoring refresh.

## Findings, ordered by user impact

Priority A means address before widening the private beta. Priority B means finish in the coherent daily-use batch. Priority C means validate or improve after the blocking journeys. Findings describe inspected code paths; conditional consequences are not claims of observed incidents on a tester's device.

### 1. A — Close the native playback relay boundary

The small local server used to help AVPlayer fetch some streams is not explicitly bound to the device's loopback interface. It accepts a supplied destination URL and forwards captured headers/cookies without checking that they belong to that destination. Absolute URLs inside manifests are also accepted without a destination policy.

**Why it matters:** unrelated destinations could receive provider-session information. Whether another device can reach the listener depends on platform permissions and networking; no attack was attempted or reproduced.

**Recommendation:** loopback-only binding, an unguessable per-playback token, approved destination registration, cookie domain/path/secure checks, scoped headers and redirect policy. Preserve legitimate multi-host delivery without sharing credentials indiscriminately. Add response-size, connection-count and idle limits.

**Done when:** unauthorized requests and unrelated hosts are rejected; valid playlist/segment/key requests still play; cancellation closes all owned work; credentials never cross their permitted boundary.

Evidence: `Fotty/Core/Networking/LocalStreamProxy.swift:49`, `:152`, `:166`, `:336`, `:385`, `:480`, `:510`. No dedicated proxy test suite was found.

### 2. A — Make the paid Coach genuinely private and budget-bounded

Internal TestFlight access does not itself protect the Worker endpoint. The inspected backend accepts an installation identifier, not proof of approved tester membership. Minute limits exist, but no persistent daily Coach allowance was found; an absent rate-limit binding bypasses that check.

The separate football schedule proxy also lacks the durable shared quota guard already implemented for Premier League live scores. Coach's several evidence-fetch stages plus model timeout can exceed the app's 55-second wait, and request cancellation is not propagated end to end.

**Recommendation:** revocable private-device authorization without a burdensome public account system, required production limit bindings, a hard daily allowance, and an owner-only emergency switch. Give the complete Coach request one deadline; stop abandoned work where supported and account for usage on failed responses. Bound schedule queries and coalesce identical requests. Verify provider/account-level spending controls separately.

**Done when:** an unapproved caller cannot spend the allowance; reaching the allowance fails calmly; a missing binding fails closed; a timed-out question cannot silently start another paid attempt.

Evidence: Worker `web/workers/playback/src/index.js:128`, `:759`, `:910`, `:945`; `coach-request.mjs:63`; `Fotty/Features/FPL/Services/FPLSmartCoachService.swift:381`.

### 3. A — Try good shared sources before a slow source consumes the clock

The direct Score808 lane is now independent, but the shared-provider lane still gathers source descriptors sequentially and waits for all of them before validating the candidates. Each descriptor can also wait for several mirrors. An early usable result can therefore sit unused until the discovery deadline expires.

**Recommendation:** bounded parallel family lookups with incremental validation and retained partial results. Separate a match-specific failure from a host-wide outage: currently two failures can suppress that family/host for 15 minutes and affect unrelated events.

**Done when:** a fast valid source becomes usable despite a stalled later lookup; a missing stream for one match does not automatically block another; intentional pause and the recently repaired retry ownership remain unchanged.

Evidence: `Fotty/Core/Internal/HybridStreamProvider.swift:655`; `AnalyticalDataEngine.swift:858`; `Fotty/Core/Networking/StreamDiscoveryCoordinator.swift:28`; `LiveSourceHealthStore.swift:23`, `:261`, `:289`.

### 4. A — Make a saved CPL match as watchable as the same match on Home

Home can route an eligible source-free CPL fixture straight to Fox/Willow. Matchday checks direct sources only and does not supply that alternate Watch action. Match reminders open Matchday, so a delivered reminder can lead to a row with no Watch button even though Home can open the channel.

**Recommendation:** one shared event-action policy for Home, Search, saved Matchday and reminder return. Keep their content and purpose different; only the answer to “what happens when I watch this event?” should be shared. A channel is a fallback option, not proof of its current programme.

**Done when:** save CPL fixture → receive opted-in reminder → open Matchday → one tap reaches the same preferred channel as Home, with other channels still in the list.

Evidence: `Fotty/Features/Dashboard/SportsDashboardView.swift:721`, `:732`, `:1078`; `Fotty/Features/Social/ArenaDiscoveryView.swift:277`, `:511`; `MainTabView.swift:117`; `LiveEventCard.swift:35`, `:69`.

### 5. B — Make personalization honor the team and sport the user chose

The badge search contains teams from several sports, but onboarding discards sport identity and saves every result as football. A followed basketball/baseball team may consequently never populate Matchday. Even football follows can miss provider aliases such as Manchester United versus Man Utd because follow keys use name slugs rather than the canonical identity system.

Separately, Favorite Leagues persists checkmarks but has no Home or Matchday consumer. That setting currently promises an effect it does not deliver, and its choices omit CPL.

**Recommendation:** carry canonical team identity, sport, name and badge together through search, following and fixture matching. Migrate existing follows carefully. Make favorite competitions meaningfully populate/prioritize personal Matchday, or remove the ineffective setting until that behavior exists.

**Done when:** a Lakers, Dodgers, CPL and aliased football follow each produces the correct personal fixtures without mixing senior, reserve or women's teams. Every preference has a visible, explained effect.

Evidence: `Fotty/Features/Onboarding/TeamOnboardingView.swift:122`, `:134`; `Fotty/Core/Providers/Football/FootballService.swift:1512`; `TeamFollowKey.swift:4`; `ArenaDiscoveryView.swift:414`; `SettingsManageLeaguesView.swift:8`, `:50`. Repository-wide league-model inspection found persistence/backup consumers but no discovery consumer.

### 6. B — Agree on what is live, fresh, missing or finished

Several related weaknesses remain from the earlier audit:

- Provider failures can become an empty array and then look like a successful catalog refresh. A CPL schedule fallback can hide the failed stream feed.
- Refreshes with existing rows can overlap; an older response can overwrite a newer response.
- The first nonempty mirror is accepted without proving it is complete or current.
- Home qualifies stale score status; Matchday can use it unqualified.
- CPL has a six-hour expiry in general event logic but an eight-hour channel-fallback window, producing contradictions during long delays.
- Search's empty state gives little help distinguishing an unlisted match from a stale or failed catalog.

**Recommendation:** a shared data result containing rows, fetched time, source, completeness and failure state; one refresh owner/revision; consistent sport-aware expiry. Preserve a useful last-known list with an honest age. Offer relevant retry or channels without claiming a known fixture is absent everywhere.

**Done when:** offline, valid-empty, partial-feed and fresh-feed cases look different; reverse-order responses cannot rewind the UI; rain-delayed cricket has the same state in Home, Search and Matchday.

Evidence: `AnalyticalDataEngine.swift:768`, `:783`; `Fotty/Features/Dashboard/MatchListViewModel.swift:117`; `HomeSportsDiscovery.swift:89`, `:136`; `FixtureDateGrouper.swift:87`; `Fotty/Core/Models/MediaModels.swift:49`; `CricketCatalog.swift:289`; `SearchView.swift:175`, `:215`. See findings 6–11 in the earlier audit for the detailed traces.

### 7. B — Preserve browsing position and make refresh mean the whole match

Switching tabs reconstructs Home while its selected sport, competition and navigation state are local state. The expected consequence is losing a cricket/CPL browsing position after visiting another tab; this needs device reproduction.

Pull-to-refresh in match insights only replaces the insights state, not the parent match header, score, statistics and lineups. The parent waits for its separate timer; failures can remain invisible when old data exists.

**Recommendation:** preserve lightweight browsing state without keeping hidden video or extra background tasks alive. Publish one coherent MatchHub snapshot from pull-to-refresh, return-to-foreground and periodic refresh.

**Done when:** a tab round-trip preserves the intended browsing position; refreshing a changed score updates every visible representation and marks a failed refresh honestly.

Evidence: `MainTabView.swift:66`; `SportsDashboardView.swift:16`; `InsightsHubTab.swift:69`, `:119`; `FootballRepository.swift:152`; `MatchHubView.swift:50`; `MatchHubViewModel.swift:89`, `:102`.

### 8. A — Protect FPL work and validate the complete recommendation

Transfer Lab staging is view-local. Whenever published/displayed picks change, the view replaces the staged squad and clears marked removals. An unfinished plan can disappear when underlying data updates.

Two individually acceptable transfer recommendations can also be combined without checking their combined bank and club quota. The normal saving validator is a useful final guard, and Fotty does not submit official transfers, but the recommendation itself can still be impossible. Selling-price knowledge is also incomplete and must remain explicit.

**Recommendation:** autosaved staging, Undo and an explicit conflict/rebase choice when official data changes. Validate the whole proposed squad before recommending or staging a route. Unknown free transfers or selling prices should be clearly identified assumptions or owner-confirmed inputs.

**Done when:** refreshing or changing tabs cannot silently erase work; two individually legal moves that together overspend or exceed the club quota are never presented as a verified plan.

Evidence: `Fotty/Features/FPL/Views/Components/FPLTransferHubView.swift:134`, `:139`; `Fotty/Features/FPL/Services/FPLPlannerEngine.swift:72`, `:168`; `FPLAdvisorEngine.swift:302`.

### 9. B — Extend main-score correctness to rivals and every planning tool

The newly repaired own-team scoring snapshot does not automatically refresh Rival Race. A rival analysis is stored when selected while the screen still says LIVE; its calculation also does not use all the stronger own-team autosub/finality rules.

Other concrete tool-state gaps:

- Chip cards call unused chips AVAILABLE without checking their allowed gameweek window.
- Wildcard results only observe the result count, so three new squads replacing three old squads can leave the display unchanged. Manual and automatic generation also use differing budget starting points.
- A future transfer decision can be journaled under the current live gameweek rather than its intended planning week.
- Player-history evidence has no local TTL. Explicit refresh now clears it, but unchanged comparison selections still need a refresh/error path. This is narrower than the original pre-fix cache finding.
- The chosen manager ID is reused across seasons without reconfirming the intended team, even though drafts/caches are season-scoped.
- FIXTURES LEFT counts players with a fixture remaining, not fixtures; double gameweeks expose the misleading label.

**Recommendation:** shared rules and evidence revisions, not more duplicate local calculations. Make labels describe the actual value and date. Reconfirm identity at season rollover without deleting history silently.

**Done when:** goal/full time/autosub/deadline changes update both sides of a selected rivalry; same-count optimizer refresh works; chip windows and journal target weeks are correct; stale comparisons are unmistakable.

Evidence: `FPLAdvisorViewModel.swift:805`, `:1052`, `:1130`; `FPLAdvisorEngine.swift:443`; `FPLRivalMatrixView.swift:74`; `FPLMultiGWPlannerView.swift:270`; `FPLWildcardGeneratorView.swift:26`, `:240`; `FPLAdvisorDerivedStateBuilder.swift:93`; `FPLDecisionEngine.swift:232`. Paths are under `Fotty/Features/FPL/` in their Views/Components, ViewModels or Services directories.

### 10. A/B — Make Coach check the player actually asked about

The official player packet contains squad/recommendation/captain selections plus a top-projection shortlist. It does not resolve player names from the question. A less-popular budget player can therefore be missing from the evidence even when that player is the entire point of the question.

The strategic “Evidence checked” label is also stronger than the implemented validation. The Worker checks response structure and several known rule contradictions, not every player claim, budget assertion or suggested route. Confidence is model-provided, not a measured accuracy score.

**Recommendation:** resolve named players before reasoning, retrieve the specific missing official evidence, and say what could not be checked. Connect claims to dated player/fixture/rule facts. Validate any proposed route through the normal planner. Keep deterministic score answers separate from uncertain strategy, and let local factual answers work without cloud consent.

**Done when:** questions about players outside the shortlist fetch their evidence or explicitly decline the unsupported claim. “Recheck this advice” produces a new dated answer; historical advice never silently becomes current. No promise that AI can guarantee winning a league.

Evidence: Worker `index.js:667`, `:787`, `:855`, `:880`, `:998`; `FPLSmartCoachService.swift:371`; `FPLAICoachView.swift:40`, `:360`; `FPLAdvisorViewModel.swift:1206`.

### 11. B — Finish reminder control and notification semantics

FPL deadline reminders expose Enable without a complete enabled/cancel/next-fire state. Their notification lacks the FPL destination used for routing and omits explicit timezone information. Separately, the football event transition logic can classify returning from halftime as another kickoff.

**Recommendation:** one clear reminders destination with next alert, cancel, permission repair and correct return route; preserve existing opt-in behavior and per-match bells. Reconcile schedule changes when fresh data arrives. Do not promise local notifications will learn a last-minute schedule change while the app is closed. Distinguish kickoff from second-half restart.

**Done when:** enable, cancel, re-enable, timezone change, postponed fixture and tap-from-lock-screen all behave predictably, without autoplay or duplicate kickoff alerts.

Evidence: `FPLAlertScheduler.swift:33`; `FPLCommandCenterView.swift:249`; `Fotty/Core/Notifications/NotificationManager.swift:196`; `Fotty/Core/Providers/Football/FootballModels.swift:520`, `:573`.

### 12. B — Make saving failures and recovery visible where they happen

The database preserves the original store and falls back to temporary memory if it cannot open. That is better than deleting data, but its warning is only shown in Settings. A user following a team elsewhere can miss it. Some settings saves also ignore errors, allowing success-looking UI after a failed save.

Encrypted backup already includes meaningful protections: validated payloads, password encryption, exclusions for streams/consent/Coach conversations, preview and explicit replacement confirmation. Do not redesign it into an account system. Its complete Files export/import/restore interaction still needs exact-device qualification.

**Recommendation:** a visible non-destructive persistence warning at affected actions, explicit save failures, and a safe retry/backup recovery path. Offer a discreet last-backup reminder only if the owner wants it. Do not add automatic cloud sync without a separate privacy/conflict design.

**Done when:** simulated store/save failure never looks like a durable successful follow; invalid/wrong-password imports leave data untouched; a real encrypted backup can restore the documented data on physical hardware.

Evidence: `Fotty/Core/Persistence/LocalDataStore.swift:58`; `Fotty/Features/Settings/SettingsScreen.swift:26`; `SettingsManageFollowsView.swift:51`, `:111`; `SettingsManageLeaguesView.swift:62`; `Fotty/Core/Persistence/FottyPrivateBackup.swift:343`; `FottyTests/PrivateBackupTests.swift`.

### 13. B/C — Finish the existing visual system instead of redesigning again

The inspected iPad design has a clear hierarchy, compact match actions, recognizable team badges, sport imagery and a restrained dark palette. That identity is worth keeping. It is not evidence that every current screen is visually finished.

Specific code-level polish gaps remain: the stream-settings destination forces a dark navigation-bar scheme; follow/league settings retain fixed-size text; the unfollow icon lacks a team-specific accessibility label; league selection lacks an explicit selected value/trait.

**Recommendation:** one destination-by-destination finish pass for light/dark/system, larger text, VoiceOver, narrow/Zoomed iPhone and iPad rotation. Keep player chrome dark intentionally. Use precise sport symbols, resilient badge fallbacks and Reduce Motion rather than adding motion or larger cards to suggest “premium.”

**Done when:** every control has a clear purpose/state, names stay readable, actual tap targets remain usable, and appearance changes never reduce navigation/control contrast.

Evidence: `StreamPluginsSettingsView.swift:48`; `SettingsManageFollowsView.swift:40`, `:63`, `:92`; `SettingsManageLeaguesView.swift:79`, `:88`; current shared `LiveEventCard` accessibility support is a strength. Historical visual reference: `web/public/marketing/screenshots/fotty-home-ipad.png` (30 August).

### 14. B — Close the feedback loop and prove one coherent release

Fotty's report composer is honest: copying is not sending, diagnostics are optional and can be previewed. But a tester must still move the report into TestFlight or another share destination. We should confirm receipt rather than assuming a report arrived.

The written seven-day qualification plan is strong, but old evidence records are not acceptance of the current candidate. Different devices/TestFlight hold different builds, and the latest reliability work is not installed. The checkout currently has hundreds of changes; historical release fingerprints help, but are not a replacement for a recoverable exact source snapshot. The documented clean-ancestry restriction must be respected, not “fixed” with a blind push or reset.

Some old agent guidance also contradicts today's code: the playback playbook still says to cancel competing resolution on the first success and collapse HD/SD alternatives. Those instructions can reintroduce recently repaired behavior.

**Recommendation:** one exact app/backend candidate ledger; one received test report; reviewed source snapshot/provenance; remove contradictory active guidance when implementation is approved. Keep the existing small private group for seven ordinary-use days after entry gates pass. No invitations, uploads or Git publication are authorized by this audit.

**Done when:** a fresh engineer can identify and reproduce the tested source; the build and Worker identity agree with the ledger; feedback is confirmed received under that build; the five uncoached tasks pass.

Evidence: `Fotty/Features/Settings/Views/SettingsSupportViews.swift:176`; `docs/RELEASE-PROCESS.md`; `docs/beta/PRIVATE-QUALIFICATION-2.0.md`; `docs/beta/ROUND-01-ACCEPTANCE.md`; `agent/playbooks/playback.md:25`, `:29`, `:55`.

## Why existing tests did not catch all this

Passing tests are useful; they are not proof of the whole product. There is strong deterministic scoring/identity/retry coverage. However, some UX tests inspect source strings instead of exercising the action and checking the resulting state.

One concrete example is `BetaUsabilityTests.swift:286`: the test named “persistence failure cannot silently pretend to save” verifies that the fallback flag and warning text exist in source. It does not simulate a failed save from Home and establish that the user sees the warning. Likewise, the CPL fallback source check does not exercise save → reminder → Matchday → playback.

The next testing investment should emphasize **transitions**: time passes, data changes, a user switches screens, a provider hangs, a save fails, a budget is exhausted. Keep useful structural guards, but pair them with behavior tests and exact-device acceptance.

## Ten improvements worth considering after the fixes

These are recommendations, not approved scope. Most strengthen existing capabilities and do not require another tab.

1. **Your next watch:** one compact suggestion for the next saved/followed event, with overlap awareness. Put the full personal schedule in Matchday; keep Home broadly useful.
2. **Last watched:** an optional device-local shortcut to the last event/channel, resolving a fresh source when reopened. This is not a recording, catch-up service or promise to resume a live stream at an old timestamp.
3. **What changed since I last checked?** Briefly identify a changed kickoff, postponement, newly listed source or FPL availability change. Notify only for opted-in, actionable changes supported by evidence.
4. **Ready for deadline:** connect the existing FPL draft, transfer validation, captain/bench checks and official-FPL link into one finishable checklist. Reconcile the intended plan with the next published team. Never imply Fotty submitted changes.
5. **Coach answers with receipts:** expandable player/fixture/rule evidence, timestamps, missing information and a Recheck action. Stage suggested changes only through the normal validator.
6. **A meaningful Rival Race:** refresh one chosen rival correctly, show what caused the swing and whose players remain. Broader live rank/effective ownership needs reliable population data; do not invent it from one team.
7. **A replayable multiweek plan and honest advice review:** extend existing scenarios/journal to store intended player IDs, actions and weeks, recalculate legality, and compare forecast assumptions with actual results. Avoid treating hindsight or short-term luck as measured coaching skill.
8. **A proper reminder center:** see what will notify you, when, and why; cancel or repair permissions. Contextual Share fixture / Add to Calendar could complement this without putting more buttons on every row.
9. **Optional screen-wide spoiler protection:** extend the existing alert-only concept to conceal scores until tapped. Useful for delayed streams, but opt-in and consistent across supported surfaces; it cannot control a provider's own video graphics.
10. **Quiet service awareness:** a discreet time-stamped incident notice plus a private operator view of app/backend versions, dependency status and remaining allowances. A constrained emergency configuration could disable an approved failing integration without a rebuild; never allow arbitrary remote hosts or hidden alternate product modes.

### External reference points, not a copying exercise

FotMob separates live, television and time-based discovery. The useful lesson for Fotty is clear state and navigation, not adding all its news/tools. See [FotMob's own interface](https://www.fotmob.com/).

LiveFPL exposes rank-tier averages and effective ownership. The useful lesson is explaining personal context with the right underlying population data; Fotty should not display equivalent metrics without that evidence. See [LiveFPL's rank-tier page](https://plan.livefpl.net/rank_tiers).

Apple provides received screenshot/crash/general feedback in App Store Connect, with build/device context and webhook support. Start by proving the existing delivery path; a new ticket backend is optional, not necessary for this small beta. See [Apple's tester-feedback guidance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback).

No new scraping integration, third-party subscription or paid service is recommended merely because these reference products have a feature.

## Recommended implementation order

| Milestone | Work | Exit condition |
| --- | --- | --- |
| 1. Protect the user and owner | Relay isolation/resource limits; Coach authorization/budget/deadline; protect unfinished FPL plans and validate combined routes | Negative-path tests prove boundaries and no silent plan loss; production safeguards independently verified before claiming them active |
| 2. One dependable sports journey | Incremental provider lookup; catalog freshness/order; saved CPL Watch; canonical multisport follows; useful league preferences; coherent MatchHub and reminders | Find → save → remind → watch works without explanation; all screens agree on the event and its data state |
| 3. Trust every FPL tool and finish the UI | Rival refresh; named-player evidence; chip/wildcard/journal/season fixes; browsing-state retention; settings/accessibility/save failures | No falsely live or unsupported “checked” claims; no vanished work; changed surfaces pass physical interaction checks |
| 4. Qualify a meaningful private beta batch | Unique build, exact source/backend record, one received feedback report and the existing seven-day plan | Entry gates plus five uncoached tasks and ordinary-use evidence pass; then consider widening |
| 5. Add selected differentiators | Pick two or three of the ten ideas based on observed tester value | Users complete a useful new task; feature does not clutter core discovery or increase hidden costs |

This is a recommended dependency order, not a delivery-date estimate or permission to deploy.

## What I would deliberately not do next

- Another wholesale redesign, larger match cards, redundant Watch/unmute controls or FPL promotion on every screen.
- A social network, accounts or automatic sync merely because large apps have them.
- Every-sport live scores without a sustainable data source and budget.
- Universal PiP/ad-free/reliability promises for third-party players that the app cannot guarantee.
- A latest-version rewrite as a substitute for fixing lifecycle and data ownership. The native language-mode setting is not proof of an old compiler; prioritize measured concurrency/resource problems over a blanket migration.
- More frequent TestFlight emails for small fixes, more simulators, retained build products or full-broadcast recordings.

## Acceptance still needed on the exact next candidate

Use the already agreed private qualification plan rather than inventing another testing program. Cover an iPhone and iPad, light/dark/system, large text/VoiceOver/Reduce Motion, one non-football newcomer journey, notifications, encrypted Files restore, FPL planning and one received report.

During actual decoded web/native playback, check the same-control pause/resume, unmute, recovery, intentional pause, app switching, native PiP/lock, source switching and clean dismissal. Include an ordinary sustained session, note heat/battery/charging context, and exercise MultiView separately. A successful browser page, process launch, widget extension or compile is not that evidence.

## Related records

- [Earlier technical audit](Fotty-Deep-App-Audit-2026-09-04.md): original 14 findings; first five subsequently implemented locally.
- [Implemented reliability batch and exact qualification](Fotty-Reliability-Fixes-2026-09-04.md).
- [Build 58 distribution and limits](../releases/Fotty-2.0.0-58.md).
- [Existing private qualification plan](../beta/PRIVATE-QUALIFICATION-2.0.md).

Source line numbers refer to the inspected working tree and will move after implementation. Short filenames in evidence sections name their unique current repository files; this report is a navigation aid, not a frozen source archive. Recommendations remain unimplemented unless a later work record explicitly closes them.
