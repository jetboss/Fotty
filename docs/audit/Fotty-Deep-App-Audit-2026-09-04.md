# Fotty Sports Hub — deep application audit

Date: 4 September 2026  
Scope: native discovery, playback, FPL, notifications, persistence/freshness and UI integration  
Method: read-only source and test inspection by parallel reviewers; no simulator, device interaction, paid call or deployment

## Executive assessment

The next milestone should be correctness across the whole user journey, not more visible features. Fotty has substantial policy coverage, but several independently reasonable policies do not compose correctly when time passes, requests finish out of order, a player changes documents, or an upstream feed fails.

The highest risks are opening the wrong match, restarting playback after the user leaves or pauses, treating advertisement media as the broadcast, discarding working alternatives, and calculating FPL live state from a mixture of fresh and old inputs. These are concrete code findings, not a claim that all were reproduced on the owner's devices.

The direct Score808 integration is implemented separately in **private build 58**; its exact qualification/distribution status is in [the release record](../releases/Fotty-2.0.0-58.md). The owner subsequently approved findings 1–5, now implemented in local source after build 58; see [the reliability implementation and qualification record](Fotty-Reliability-Fixes-2026-09-04.md). The findings below preserve the original audit evidence. Findings 6–14 remain separate work; neither this audit nor automated qualification certifies physical playback acceptance.

References identify the inspected source and owning function. Line numbers are a review-time locator and may move as the separate Score808 work changes the resolver. All paths are relative to the repository root.

## What the Score808 incident exposed

Build 57's inferred `admin` → `hotel` descriptor did not prove a relationship to the owner's Score808 website. Its generic HTML validation could accept small unavailable-player pages: `readPrefix` stopped at 256 bytes despite an 8,192-byte requested limit, while the stub check rejected only bodies shorter than 32 bytes. Sequential lookup and validation could also spend the global timeout before reaching the late-listed source.

The owner's actual page has a different player route, and the site's published calendar supplies the match/date relationship needed to select it safely. A long HTML response or a page that decodes some video does not independently prove the right fixture. A reused Watch page must be selected from current, exact event evidence.

See [Score808 route investigation](Fotty-Score808-Route-Investigation-2026-09-04.md) for that incident's evidence. Its regression gate should distinguish matched listing, missing listing, unavailable player, failed transport and exhausted lookup budget; no TLS bypass or invented URL is an acceptable recovery mechanism.

## Prioritized findings

### 1. P1 — Match resolution can accept the wrong opponent or date

**Evidence:** `Fotty/Core/Internal/HybridStreamProvider.swift`, `resolveCatalogEvent` (approximately lines 1079 onward during this audit). The legacy score-based fallback accepts a score of 40; one matching home name can exceed that by itself. Away identity and kickoff proximity are bonuses rather than mandatory constraints.

**Consequence:** A source-less official fixture or an unmatched ID can resolve another match involving only one of the teams, including a different day.

**Change:** Require both canonical team identities and a bounded kickoff for match-specific fallback, with a unique result. Keep channel and ID-only navigation distinct. Fail closed on ambiguous fixtures.

**Behavioral tests:** Same home/different opponent; same teams tomorrow; senior/reserve/women's teams; reversed venues; two plausible candidates; missing kickoff. Existing alias tests do not prove this end-to-end admission rule.

### 2. P1 — Delayed retry can restart after dismissal, pause or recovery

**Evidence:** `Fotty/Features/Player/LivePlayerViewModel.swift:790`, `retryCurrentWebSource`, starts an unowned 500 ms task guarded only by source ID. `cleanup` at line 1146 does not cancel it or clear that selected source. `loadCurrentSource` resets explicit-pause state.

**Consequence:** Dismissal, a recovered stream or a manual pause during the delay can be followed by an unexpected reload. This matches the class of interruption the owner previously described, but this audit did not reproduce a current-device incident.

**Change:** Own and cancel the retry task; capture request/attempt identity and verify playback lifecycle before reloading. Cancel on cleanup, pause, recovery and source change.

**Behavioral tests:** Advance a controlled scheduler across the retry boundary after each interruption and expect zero reloads; uninterrupted retry should reload exactly once.

### 3. P1 — Advertisement media can acquire broadcast ownership

**Evidence:** `Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift:562–606,824–841` admits advancing video as small as 16×16 and assigns ownership to the first reporting document. Lines 375–428 and 737–748 observe manifest/media resources without proving that each belongs to the selected video.

**Consequence:** A preroll or hidden ad can become the primary document; later broadcast messages can be rejected. An unrelated playable manifest can also become a native handoff candidate. Decoding success proves media playback, not match identity. Occurrence depends on the provider page.

**Change:** Establish primary-player ownership with visibility, size and player context; support an intentional preroll-to-broadcast transition. Prefer the selected video's current source or a manifest demonstrably owned by that player. Resource observation alone should not authorize automatic handoff.

**Build-58 scope:** The direct Score808 route now restricts ownership and native candidates to its observed main player. The generic shared-provider path still has the risk described here. Final review also caught provider-specific rules persisting when SwiftUI reused the web view; build 58 replaces those rules before each source/attempt load and tests both switch directions. Same-element ad-source replacement and real WebKit playback still require acceptance.

**Behavioral tests:** Ad first; ad element retained after completion; hidden video; unrelated manifest after broadcast starts; iframe replacement. The existing test at `PlaybackPolicyTests.swift:1495` begins with the broadcast already owning the coordinator and misses the adverse ordering.

### 4. P1 — Curation discards delivery alternatives before they can be tried

**Evidence:** `Fotty/Core/Internal/AnalyticalDataEngine.swift:917`, `curatedPlaybackCandidates`, uses language/label grouping to collapse distinct stream numbers and URLs. Selecting a preferred HD candidate can discard the SD fallback entirely.

**Consequence:** Several different routes labeled “English” can become one route; if that route fails, a working returned alternative is never attempted.

**Change:** Preserve concrete delivery identities for resolution/failover. Presentation can group equivalent labels without deleting their alternative routes. Collapse only proven duplicates.

**Behavioral tests:** Multiple generic-English streams; HD unavailable/SD working; same label on different channels; actual mirror duplicates; fair family coverage under the session limit.

### 5. P1 — FPL live refresh leaves fixture completion and gameweek state behind

**Evidence:** `Fotty/Features/FPL/ViewModels/FPLAdvisorViewModel.swift:1008–1028` refreshes live statistics and picks but not `fixtures` or `currentGameweek`. `FPLDecisionEngine.swift:294–307` requires fixture completion for projected autosubs, lines 232–237 use it for players remaining, and line 263 uses gameweek finality. `FPLLiveTrackerView.swift:26–31` repeats this partial refresh. Planning-phase polling is disabled.

**Consequence:** Keeping the screen open through full time can update points while autosubs, players remaining or finality remain stale. Keeping it open across the deadline can leave it in planning until a full reload/tab or scene transition.

**Change:** Refresh a coherent gameweek/fixtures/picks/live snapshot under the existing request revisions. Re-evaluate phase at the deadline without requiring navigation.

**Behavioral tests:** Non-playing starter plus scoring substitute across full time; double-gameweek completion; final data-checked transition; planning across deadline. Existing scoring tests provide already-correct fixtures and do not exercise this refresh lifecycle.

### 6. P2 — Catalog failure, empty success and fresh data are conflated

**Evidence:** `AnalyticalDataEngine.swift:768–780` catches provider errors and returns an empty array. `Fotty/Features/Dashboard/MatchListViewModel.swift:124–135` consequently reports success; lines 149–154 hide refresh errors when rows exist, and line 168 ignores empty near-term results. CPL schedule merging can make the result nonempty even when provider discovery failed.

**Consequence:** An outage can silently retain stale Watch descriptors or replace provider rows with schedule-only data. The UI has no provider fetched-at/trust state to explain which happened.

**Change:** Return typed catalog outcome, timestamp and provenance. Retain last-known-good provider rows on failure with an unobtrusive stale notice; deliberately apply validated empty success.

**Behavioral tests:** All feeds fail with populated cache; valid empty response; CPL fallback while provider discovery is offline; stale source expiry. Do not use an empty array as an error sentinel.

### 7. P2 — Warm refreshes can overlap and publish out of order

**Evidence:** `MatchListViewModel.swift:117–120` uses `isLoading` as its guard but sets it to `matches.isEmpty`. It is therefore false during refresh when rows already exist. There is no response revision at `applyFreshMatches`.

**Consequence:** An older slow request can overwrite a newer corrected catalog and feed that old snapshot into reminder reconciliation. Polling, pull-to-refresh and tab changes can multiply requests.

**Change:** Separate initial-loading presentation from an owned in-flight refresh. Coalesce requests or enforce latest-request-wins publication.

**Behavioral tests:** Controlled requests A/B completed in reverse order; cancellation on navigation; simultaneous Home/Matchday entry. No behavioral `MatchListViewModel` test was found in the inspected suite.

### 8. P2 — The fastest nonempty mirror is assumed to be complete

**Evidence:** `AnalyticalDataEngine.swift:783–820`, `fetchLiveEvents_NexusAImplementation`, accepts the first nonempty mirror and cancels the others without comparing freshness or completeness.

**Consequence:** A fast partial/stale mirror can repeatedly hide an event or its newly published source even though another mirror contains it.

**Change:** Preserve fast initial display if useful, but perform bounded exact-event/source enrichment on Watch or merge completed results by proven identity. Do not merge fuzzy matches or silently choose between conflicting kickoffs.

**Behavioral tests:** Fast stale versus slower fresh mirror; subset feed; disjoint sources; conflicting times; timeout with useful partial evidence.

### 9. P2 — Match-specific failures can block unrelated broadcasts

**Evidence:** `Fotty/Core/Networking/LiveSourceHealthStore.swift:23–24,109–125,261–292` scopes health keys to family and host. Two failures can open a 15-minute circuit for that entire scope; `LivePlayerViewModel.swift:460–472` skips blocked sources.

**Consequence:** Two unavailable matches or early-start attempts can suppress a healthy, unrelated match. The behavior is deliberate but the blocking scope is too broad for match-specific failures.

**Change:** Separate route/event failure memory from common-host transport failure. Retain family ranking, but require host-wide evidence before broad blocking; permit a bounded fresh-event trial.

**Behavioral tests:** Failed A does not suppress B; genuine TLS failure can affect the host; explicit retry; expiry; native-handoff failure does not poison healthy web delivery.

### 10. P2 — CPL's eight-hour delay window is cut off after six hours elsewhere

**Evidence:** `Fotty/Core/Models/MediaModels.swift:49–65` assigns CPL a six-hour estimated duration. `HomeSportsDiscovery.swift:89` removes elapsed events before its CPL branch. `CricketCatalog.swift:289–301` permits channel fallback for eight hours, and schedule merging preserves a seven-hour rain-delay case. Matchday also uses the six-hour estimate to classify finished events.

**Consequence:** At kickoff +7h, a rain-delayed fixture remains valid in schedule/channel logic but disappears from Home or moves to recent in Matchday.

**Change:** Centralize discovery expiry separately from estimated playing duration.

**Behavioral tests:** Compose schedule merge → Home → Matchday → Watch at +7h and +9h. `BetaUsabilityTests.swift:610–613` and `:672–679` currently test the contradictory boundaries independently.

### 11. P2 — Matchday trusts stale live score status that Home rejects

**Evidence:** `Fotty/Features/Dashboard/Components/FixtureDateGrouper.swift:87–99` reads raw cached score status; Matchday consumes it at `ArenaDiscoveryView.swift:375–379`. `FootballModels.swift:739–754` does not qualify freshness. Home's `HomeSportsDiscovery.recentStatus` at lines 136–146 does.

**Consequence:** After a score outage or a stopped poller, Matchday can still say Live while Home correctly falls back to listed timing.

**Change:** Expose one freshness-qualified status boundary to all screens and playback affordances.

**Behavioral tests:** Same cached in-play fixture on both tabs after ten minutes and after a failed feed. Test consumers together, not just Home's helper.

### 12. P2 — FPL reminders lack complete routing and control

**Evidence:** `Fotty/Features/FPL/Services/FPLAlertScheduler.swift:46–59` creates notifications without a destination payload, while the notification delegate requires `matchID` before routing. Its date components omit timezone/calendar/seconds. `FPLCommandCenterView.swift:249–271` always shows Enable, without pending state or cancellation.

**Consequence:** Tapping a deadline alert opens the previous app surface rather than FPL; the user cannot inspect or cancel that opt-in in the app. Changing timezone can alter an unanchored trigger.

**Change:** Add typed FPL routing, observable pending/cancel state, UTC triggers and deadline-change reconciliation. Reuse the stronger match-reminder lifecycle pattern.

**Behavioral tests:** Delivered tap from Home and cold launch; cancel/re-enable; timezone change; revised deadline. `FPLTrustTests.swift:986–995` only verifies planned offsets.

### 13. P2 — Kickoff can be announced again at the second half

**Evidence:** `Fotty/Core/Providers/Football/FootballModels.swift:573` treats every non-inPlay → inPlay transition as kickoff. Halftime maps to `.paused` at line 520.

**Consequence:** A provider reporting halftime correctly can cause another “Match started” notification when play resumes.

**Change:** Require a genuine pre-match → live transition and deduplicate event delivery by fixture identity.

**Behavioral tests:** Scheduled → live → halftime → live → finished; provider corrections; repeated same-team fixtures. Existing notification tests inspect content/spoiler wording, not transitions.

### 14. P2 — Player evidence has an indefinitely retained second cache

**Evidence:** `FPLAdvisorViewModel.swift:995–1001` returns `elementSummaries[playerID]` without TTL validation. Only manager removal clears that dictionary. Explicit refresh clears the service cache at line 435, not this cache; `FPLPlayerComparisonView.swift:206–228` renders the retained history.

**Consequence:** Pull-to-refresh can update headline FPL data while the already-viewed player's “recent official” history remains old.

**Change:** Remove the duplicate cache or enforce resource-metadata age; invalidate it on explicit refresh. Fence outstanding summary requests against manager/season reset.

**Behavioral tests:** New official history after initial comparison, explicit refresh, manager switch during fetch and season transition. No summary-cache refresh test was found.

## Smaller UI and discovery follow-ups

- **Disabled-source affordances:** supported-family checks can leave Watch visible after its providers are disabled. Presentation should use enabled availability and explain the disabled state, rather than resolving to generic unavailable.
- **Equal-sized catalog replacements:** `SportsDashboardView.swift:197–215` validates sport/league selection only when total row count changes. Observe the option-set signature or catalog revision so equal-count replacement cannot strand a removed filter.
- **Independent Score808 discovery:** resolver-only integration does not make Score808-only fixtures discoverable. Treat that as a separate bounded catalog milestone with exact identity and expiry, not an implied property of the immediate fix.
- **Settings and reminder accessibility:** fixed-size explanatory text in `SettingsPrivacyView.swift:89–93,118–123` and the horizontal reminder card at `FPLCommandCenterView.swift:249–271` need largest-text/light-mode/VoiceOver checks. This is a code-level inconsistency and an acceptance risk, not observed physical clipping.
- **Support delivery:** the local report/preview/share flow correctly distinguishes copying from sending. Preserve that honesty; test a received report from a real tester before calling the feedback loop complete.
- **Partial discovery diagnostics:** build 58 preserves discovered sessions and actionable errors when a lane is cancelled, but detailed timeline/attempt records currently arrive only with completed lanes. Stream those records incrementally and log deadline/grace exits even when another source succeeded; do not describe the current trace as complete.

## Safeguards to preserve

- Published FPL picks remain separate from local planning drafts.
- Coach responses are manager/context scoped, cancellation aware, and consent gated.
- FPL resources carry source/age metadata and season-bound disk validation.
- Match reminders use opt-in, serialized revision guards and absolute UTC triggers.
- Private backup has validated encrypted export/restore and does not transfer consent or reminders.
- Native PiP and web playback have different background policies; Live Activities require useful native playback/PiP state.
- TestFlight release, installation, normal launch and actual interaction acceptance are documented as distinct evidence levels.

## Recommended implementation order

1. **Complete the separate Score808 repair and qualify its exact build.** Verify current fixture mapping, playable media, timeout/failure classification and iPad behavior. A build success alone is not streaming acceptance.
2. **Prevent wrong actions and lost playback.** Findings 1–4: strict match identity, owned retry lifecycle, retained alternatives and explicit media ownership. Use adversarial provider/frame fixtures before physical testing.
3. **Make displayed data coherent.** Finding 5, then 6–8 and 10–11: complete FPL snapshots, truthful catalog state, single-flight publication, mirror enrichment and unified timing/freshness.
4. **Finish recovery and everyday controls.** Findings 9 and 12–14 plus the scoped UI follow-ups. Preserve the owner's compact, one-tap design; do not add generic screens or permanent controls to compensate for data problems.
5. **Run a meaningful private acceptance round, then batch TestFlight.** Use existing bounded build tooling, sequential execution and no simulators. Do not create a fresh retained DerivedData tree per case.

## Acceptance gate

The next evidence should cover transitions, not merely static screenshots or source-text assertions:

- Discovery through Watch with late publication, partial mirror, missing fixture and provider outage.
- Play → manual pause → resume; recover during retry; close during retry; change source; ad before/after broadcast.
- Native PiP across app switching and lock/unlock, with actual audio/video continuity and restoration.
- FPL deadline, halftime/full-time, autosubs, double-gameweek completion and final data-checked state without leaving the screen.
- Reminder scheduling, cancellation, updated kickoff, notification tap and timezone change.
- Cached launch → offline → reconnect; overlapping refreshes; successful empty catalog.
- Owner-sized iPad plus phone acceptance when available: light/dark, largest text, VoiceOver, compact layouts and feedback receipt.

No finding in this report should be marked fixed solely because an isolated policy test passes. Link the implementation and transition test, then record physical acceptance where AVKit, WebKit or system notifications own the behavior.
