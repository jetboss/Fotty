# Fotty baseline for the five-product comparison — 29 October 2026

Read-only active-source and retained-receipt inventory. This pass did not open
Fotty, operate a device, build, run tests, fetch providers/media or modify app
source/settings. FPL and multi-stream feature work are excluded. Shared player/
root files were inspected only for the single-player and app-navigation questions.

**Evidence level:** implemented below means source checked, not newly visually or
physically verified. Jet's installed normal build is 184; the iPhone remains 177.
Neither was visually re-inspected for this comparison. The [184 receipt](/Users/jelani/Documents/Development/Fotty/docs/testing/fotty184-source-native-2026-10-28/README.md)
records installation without launch, 75 focused native tests and 117 separate CS
tests; live184 fullscreen/PiP remains deferred. [178's dated receipt](/Users/jelani/Documents/Development/Fotty/docs/testing/fotty178-nine-fixes-2026-10-25/README.md)
contains earlier normal-app navigation, channel decoding, fullscreen and PiP
observations. It is not current184 or current-iPhone proof. Historical test counts
must not be merged into a fresh whole-app acceptance claim.

## Implemented core journeys and states

| Surface | Implemented in current source | Verification limits and real opportunity |
| --- | --- | --- |
| Home | Loading/error/content switch; Now & next; scoped sport/interests menu; live/upcoming projections; broader sports; exact lineup search; actionable listing/refresh notices. Existing interests affect ranking. | [SportsDashboardView.swift:416](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/SportsDashboardView.swift:416), [:434](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/SportsDashboardView.swift:434), [:471](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/SportsDashboardView.swift:471), [:1047](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/SportsDashboardView.swift:1047). No fresh visual clutter, scrolling or latency conclusion follows from this source read. Opportunity: demonstrate the value of existing personalization and last-live return, rather than add another Home system. |
| Matchday | Saved/followed matches, viewing-window or full-matchday scope, Live/Broadcast listed/Next up/day groups, recent/awaiting-confirmation rows, changed-time explanation and useful empty state with Browse Home/Follow. | [ArenaDiscoveryView.swift:583](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Social/ArenaDiscoveryView.swift:583), [:651](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Social/ArenaDiscoveryView.swift:651), [:716](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Social/ArenaDiscoveryView.swift:716), [:768](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Social/ArenaDiscoveryView.swift:768). This already provides a personal plan; a new Saved/Watchlist tab would duplicate it. |
| Search | Native search field, current catalog index, deliberate recent queries stored locally, followed-interest shortcuts, sports shortcuts and verified-team follow action in an empty result. Loading, results and unavailable states are distinct. | [SearchView.swift:85](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Search/SearchView.swift:85), [:470](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Search/SearchView.swift:470), [:640](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Search/SearchView.swift:640), [:734](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Search/SearchView.swift:734). Scope is already-loaded lineup, not a full persistent team/competition schedule directory. Test the case of a followed team's next match falling outside that lineup. Recent searches are explicitly not viewing history (:4). |
| Setup/follows/save | Optional dismissible setup, league-selectable team search, skip/Done, saved follows and errors. Settings separates Favorite Teams and Home interests. Visible ellipsis actions already expose Details and Save/Remove alongside context menus. | [TeamOnboardingView.swift:18](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Onboarding/TeamOnboardingView.swift:18), [:25](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Onboarding/TeamOnboardingView.swift:25); [MatchdaySetupCard.swift:35](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Onboarding/MatchdaySetupCard.swift:35); [SportsDiscoveryViews.swift:3](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift:3), [:475](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift:475). Setup's tip still teaches long press (:66), but saving is **not long-press-only**. Improve teaching/continuity and test discoverability; do not add a second Save system. |
| Match details | Loading, enriched match hub where available, generic catalog fallback with honest unavailable scores/lineups/stats, refresh and retry. Watch triggers feedback before async discovery; cancellation remains available. | [MatchHubView.swift:25](/Users/jelani/Documents/Development/Fotty/Fotty/Features/MatchHub/MatchHubView.swift:25), [:169](/Users/jelani/Documents/Development/Fotty/Fotty/Features/MatchHub/MatchHubView.swift:169); [MatchHubViewModel.swift:210](/Users/jelani/Documents/Development/Fotty/Fotty/Features/MatchHub/MatchHubViewModel.swift:210). Rich context depends on the admitted data source, not merely another detail-screen layout. |
| Single watching | Retained media surface, minimize/return dock, native fullscreen action, iPad video-first composition, accessible Sources/Details dock and companion. Exact same-session reopen avoids rediscovery when eligible. | [ViewingExperienceView.swift:25](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/ViewingExperienceView.swift:25), [:41](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/ViewingExperienceView.swift:41), [:250](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/ViewingExperienceView.swift:250), [:357](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/ViewingExperienceView.swift:357); [ViewingSessionCoordinator.swift:135](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/ViewingSessionCoordinator.swift:135). These features exist. Long native184 viewing, fullscreen/PiP round trip, audio and actual route behavior need their named physical gates; no new player rewrite follows from a competitor screenshot. |
| Source choices/recovery | Validated source list, All/group filter, incremental checking state, selected/failed/cooldown actions and contextual empty result. Sanitized advertised quality/language is already shown as **Listed**, separate from observed active Native/Web mode. Error UI offers Retry, alternate Sources, Report and Close. | [LiveStreamSelectorSheet.swift:40](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift:40), [:131](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift:131), [:314](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift:314), [:428](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift:428); [PlaybackErrorOverlay.swift:15](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/PlaybackErrorOverlay.swift:15). Adding descriptive metadata is not wholly new; improve supplied evidence/coverage only when known. A validated descriptor or Listed HD is not decoded quality or a playback guarantee. |
| Settings | Appearance, Home/Matchday preferences, source plugins, privacy and support grouped into adaptive columns; notification permission handling; separate sports-continuity screen. Owner diagnostics are gated, rather than a normal Home destination. | [SettingsScreen.swift:18](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/SettingsScreen.swift:18), [:83](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/SettingsScreen.swift:83), [:101](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/SettingsScreen.swift:101); [SettingsSupportViews.swift:349](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/Views/SettingsSupportViews.swift:349). Appearance and task grouping are implemented, not new competitor-inspired features to count again. Actual text density and discoverability need equivalent-build visuals. |
| Feedback | Existing contextual report opens from playback error, seeds expected/actual descriptions, keeps a local draft, offers optional minimized diagnostics/review and explicit Copy/Share/manual TestFlight handoff. It does not silently transmit. | [PlaybackErrorOverlay.swift:60](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/PlaybackErrorOverlay.swift:60); [SettingsSupportViews.swift:118](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/Views/SettingsSupportViews.swift:118), [:154](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/Views/SettingsSupportViews.swift:154), [:207](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/Views/SettingsSupportViews.swift:207). Both required fields are prefilled from that error entry point; do not claim every tester must start by typing both. A classified issue/session-specific draft and simpler approved delivery are opportunities, not absence of reporting. |
| Continuity | Explicit Handoff, opt-in sports preference/saved-identity iCloud code, saved-match widget snapshot and fresh schedule/source checks on arrival. Sync does not include viewing history, stream links or local reminders. | [SettingsSportsContinuityView.swift:5](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/Views/SettingsSportsContinuityView.swift:5). Current-State still holds real sync/widget acceptance open and sync off. Existing capability and unverified acceptance must remain distinct. AirPlay/A2DP-capable playback audio category is configured in [MediaAudioSessionOwner.swift:70](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Media/MediaAudioSessionOwner.swift:70); no current casting interaction was tested. |

## Confirmed capability gaps and narrow product opportunities

### 1. A local last-live return after cold launch

No persistent ordinary watch-history/last-live model or Home affordance was found
in the inspected active source. [MainTabView.swift:15](/Users/jelani/Documents/Development/Fotty/Fotty/App/MainTabView.swift:15)
creates a fresh coordinator; [ViewingSessionCoordinator.swift:36](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/ViewingSessionCoordinator.swift:36)
starts with empty panes. Existing retention/reopen is same-session and explicit
Handoff is a different mechanism. Matchday's Recent group is saved/followed schedule
history, not a viewing record. A bounded repo search of active Swift files for
`Recently watched`, `recentlyWatched`, `viewingHistory`, `watchHistory`, `lastLive`
and `lastWatched` found no implementation.

Proposal: one optional, clearable local event-identity return card; recheck identity,
terminal status and fresh source on tap. Do not retain/replay media URLs, silently
create cloud viewing history, promise exact VOD resume or offer finished events as live.
This is additional product behavior and needs a privacy/design decision before implementation.

### 2. Current cricket score context and UCL score activation

[CricketFixtureCatalog.swift:49](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Models/CricketFixtureCatalog.swift:49)
contains start, format, status, competition, teams and source—no runs/wickets/overs/
innings fields. The player's [score helper:678](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/ViewingExperienceView.swift:678)
explicitly accepts football only. [FootballDataPolicy.swift:154](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Data/FootballDataPolicy.swift:154)
activates PL live scores; UCL is planned separately. Cricket currently omits a
football score rather than inventing a 0–0; absence is a capability gap, not an
incorrect scoreboard bug.

Proposal: review an appropriate fresh data contract/cost, then supply verified
cricket-specific state and resolve UCL's activation gate. A new stats panel without
a data source cannot deliver this value. Do not enable paid/unreviewed feeds as part of this audit.

### 3. Deliberate quality/data preference

No user-facing Data Saver/Auto/Best selection or native bitrate/resolution preference
was found in inspected Settings/player surfaces or active Swift searches for
`Data Saver`, `dataSaver`, `preferredPeakBitRate`, `preferredMaximumResolution`,
`videoQuality`, `preferredQuality`, `qualityPreference` and `qualitySelection`.
Native preparation currently sets a buffer preference in
[NativePlaybackPreparation.swift:62](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/NativePlaybackPreparation.swift:62);
normal native stalling behavior is configured at
[LivePlayerViewModel.swift:1719](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/LivePlayerViewModel.swift:1719).
Neither is a consumer quality selector.

Proposal: truthful Auto/Data Saver/Best policy only where variants or admitted
alternative deliveries support it. Advertised `Listed: HD · English` already
exists; do not confuse richer source metadata with actual rendition selection.
A fixed-quality feed cannot honestly offer arbitrary lower resolution.

### 4. Schedule-change delivery while closed

Existing reminders fire five minutes before a saved scheduled start and can arrive
while Fotty is closed. [MatchReminderStore.swift:338](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Notifications/MatchReminderStore.swift:338)
reconciles confirmed changed/terminal events, cancels inappropriate alerts and
replaces changed notification times. This is not missing rescheduling logic.

The limitation is obtaining a new schedule while closed: current Home/Matchday
refresh tasks are active-scene gated; the Help copy explicitly discloses the
boundary in [SettingsSupportViews.swift:14](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/Views/SettingsSupportViews.swift:14).
A bounded active Swift/plist/entitlement search found no `BGTaskScheduler`,
`registerForRemoteNotifications`, `didReceiveRemoteNotification`, `content-available`
or `aps-environment` implementation to establish a closed-app update path.

Proposal: design an opt-in schedule-change/cancellation service with reviewed
source freshness and explicit notification authority. Do not promise background
timers or guaranteed push timing, and do not claim current local reminders cannot fire while closed.

## Accessibility and visual acceptance

Current source contains semantic button labels/selected state and 44pt controls,
Dynamic Type reflow, contrast-aware theme colors, Reduced Transparency treatment
and Reduce Motion-aware scroll behavior. Representative evidence:
[selector row:323](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift:323),
[selector accessibility:383](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift:383),
[Search:705](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Search/SearchView.swift:705),
[Home:592](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/SportsDashboardView.swift:592),
[card material:790](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift:790),
[Theme.swift:99](/Users/jelani/Documents/Development/Fotty/Fotty/Design/Theme.swift:99).

These are meaningful foundations. They do not prove real VoiceOver order,
physical Dynamic Type, keyboard/rotor behavior, every screen's light-mode contrast,
current phone geometry, 60fps or absence of hangs. Do not turn a competitor's
accessibility declaration into a certification comparison. Finish concrete
same-size/same-state visual and interaction gates before declaring parity.

## Duplication traps for the combined recommendation

- Do not propose adding Search, follows, saved matches, reminders, visible Save,
  source groups, source metadata labels, native fullscreen, PiP, video-first iPad,
  feedback, appearance settings, Handoff, iCloud code or a widget as absent basics.
- Do not equate source listings with current decoded delivery, generic cricket
  channels with a named match, kickoff with LIVE, source refresh with a broadcast
  guarantee, or completed unit tests with physical acceptance.
- Prefer one clearer existing journey to another destination. Add actual new
  capability only when its data, privacy, notification and delivery contract exists.
- Retain badges/sport artwork and current native media behavior; no FPL or
  multi-stream redesign is recommended by this baseline.
