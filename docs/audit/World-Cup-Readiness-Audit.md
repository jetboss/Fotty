# Fotty — World Cup Readiness Audit (Phase 0)

**Date:** 2026-05-03  
**Scope:** Fotty iOS (sports-only), codebase inspection + static analysis.  
**Not performed in this pass:** Physical device QA, simulator runs, known-good HLS/MP4 URL playback tests, live API capture, Apple Developer Documentation fetch.

---

## 1. Executive summary

**Status: Almost ready — with material P1 gaps before claiming “World Cup-ready.”**

**Why:** Core navigation is sports-only (Dashboard / Arena / Settings). Match Hub, live player, hybrid/P2P resolution, live score polling, and API-Football-backed repository paths exist in code. However, **several user-visible or data paths still blend placeholders, mock fallbacks, or hardcoded “insights” that are not provider-derived**, and **World Cup–specific discovery (tournament ID, standings, bracket) is not evidenced in code**. Stream UX has **failure classification** in `LivePlayerViewModel`, but **end-to-end playback validation** was not run in this audit.

**Evidence:** CODEBASE (files cited below).  
**Gaps labeled:** TEST_RESULT = *not run*, RUNTIME_LOGS = *not collected this pass*.

---

## 2. Architecture summary (CODEBASE)

| Layer | Role | Key locations |
|--------|------|----------------|
| **App shell** | Tabs, onboarding, live score injection | `Fotty/App/FottyApp.swift`, `Fotty/App/MainTabView.swift` |
| **Dashboard** | Live/for-you/match lists, sports categories | `Fotty/Features/Dashboard/*` |
| **Match Hub** | Arena / Insights / Highlights tabs, stream resolution → player | `Fotty/Features/MatchHub/*`, `MatchHubViewModel.swift` |
| **Data** | API-Football provider → `FootballRepository` actor | `Fotty/Core/Data/Providers/APIFootballProvider.swift`, `FootballRepository.swift`, `FootballModels.swift` |
| **Match list (Nexus)** | Homelab mirror + SwiftData cache | `MatchListViewModel.swift`, `MatchListActor.swift` |
| **Streams** | Hybrid discovery, P2P broker, warmup, local proxy | `HybridStreamProvider.swift`, `P2PDataService.swift`, `PlaybackWarmupService.swift`, `LiveStreamResolver` (via `MatchHubViewModel`) |
| **Playback** | `AVPlayer`, diagnostics, failover | `LivePlayerView.swift`, `LivePlayerViewModel.swift`, `PlaybackErrorOverlay`, `LoadingStateOverlay`, `LiveStreamDebugSheet` (#if DEBUG) |
| **Integrity / review** | Remote `integrity.json` toggles review mode (Release) | `IntegrityService.swift` |
| **Notifications** | Permission + immediate local alerts | `NotificationManager.swift`, `LiveScoreService` (goal diff) |
| **EPG (listings)** | Optional XMLTV hints | `EPGDataStore.swift`, `LiveStreamSelectorSheet.swift` |

---

## 3. Product / feature status

Legend: **Working** = coherent implementation present | **Partial** | **Broken** | **Hidden** | **N/A** | **Unknown** (needs TEST_RESULT / RUNTIME_LOGS)

| Area | Status | Notes | Evidence |
|------|--------|--------|----------|
| **Home / Dashboard** | Partial | `SportsDashboardView` + lists; depends on Nexus homelab + SwiftData. Hardcoded `homelabAPIURL` (`192.168.1.100:8080`). | CODEBASE: `MatchListViewModel.swift` |
| **Live now / For you** | Partial | Cards/timelines exist; real data path tied to upstream + cache. | CODEBASE: `Dashboard*` |
| **Fixtures / dates** | Partial | `FootballRepository.getFixtures` / `getPremiumFixtures` (PL `39`, UCL `2` season heuristic). **No World Cup league id surfaced.** | CODEBASE: `FootballRepository.swift` |
| **Match details** | Partial | `MatchHubViewModel.loadMatchData` → `getMatchHubData`. Errors surfaced via `errorMessage`. | CODEBASE |
| **Live scores** | Partial | `LiveScoreService`: 60s loop, fetches live + premium range; keeps stale on failure; `hasQuotaError` on rate limit. **Minute field mapped `nil` in legacy map.** | CODEBASE: `FootballModels.swift` |
| **Timeline** | Partial | Insights views (`MatchTimelineView`, etc.) + `MatchHubData.events` — **needs API shape verification**. | CODEBASE (paths only); **UNKNOWN:** live payload |
| **Teams / leagues** | Partial | Onboarding + follows; `LeagueTeamPicker` comment admits **mock team suggestions**. | CODEBASE: `LeagueTeamPicker.swift` |
| **World Cup mode** | N/A / Unknown | **No dedicated “World Cup” feature** found by name. Premium fixtures limited to PL+UCL. **WC would require API-Football tournament/league configuration.** | CODEBASE |
| **Arena / Hub** | Partial | `MatchHub` tabs; **ArenaView** still wires `MockMatchService` for fixture/events/poll when loading path uses mocks** | CODEBASE: `ArenaView.swift`, `MockMatchService.swift` |
| **Insights** | Partial | **Hardcoded placeholder form strings and static win probability** in `getMatchInsights`. | CODEBASE: `FootballRepository.swift` L58–66 |
| **Highlights** | Partial | `HighlightsHubTab` uses **`getMockHighlights()` when empty** and mock story module. | CODEBASE: `HighlightsHubTab.swift` |
| **Streams / player** | Partial | Rich resolver progress strings; `LivePlaybackFailureKind` classification; watchdog/stall paths in `LivePlayerViewModel`. **Black-screen elimination** needs RUNTIME_LOGS + TEST_RESULT. | CODEBASE |
| **Notifications** | Partial | Permission-gated immediate alerts from score diff; **no scheduled kickoff reminders** evidenced in `NotificationManager`. | CODEBASE |
| **Settings** | Working | Settings stack present. | CODEBASE |
| **Sports-only / no movies** | Working | Tabs are Dashboard / Arena / Settings — no movie/browse routes in `MainTabView`. | CODEBASE: `MainTabView.swift` |

---

## 4. Data sources (Phase 2 matrix)

| Provider / layer | Purpose | Real vs mock | WC / live support (evidence) | Refresh / cache | Failure behavior | Evidence | Risk |
|------------------|---------|--------------|------------------------------|-----------------|------------------|----------|------|
| **API-Football** (via `APIFootballProvider`) | Fixtures, hub data, live scores | **Real** (key from `Config`) | **Partial:** PL+UCL premium range; **WC not configured in repo** | Repo actor cache; live poll 60s; match hub timer 60s | Stale cache return; prints | CODEBASE | Wrong/missing tournament coverage |
| **FootballRepository.getMatchInsights** | Insights tab feed | **Mixed / fake metrics** | N/A | Derived from hub + **placeholders** | Always returns “something” | CODEBASE | **P1 — misrepresents analytics** |
| **Nexus homelab** | Match list JSON | Real URL (LAN) | Unknown coverage | `URLCache` + SwiftData | Fallback text in `MatchListViewModel` | CODEBASE | Hardcoded IP; wrong env breaks home |
| **MockMatchService** | Arena / previews | **Mock** | N/A | N/A | Used in `ArenaView` paths | CODEBASE | **P1 — user trust** |
| **HighlightsHubTab mocks** | UI fill | **Mock when empty** | N/A | N/A | Shown to user | CODEBASE | **P1** |
| **P2P broker + scraper** | Ace streams | Project-approved per your ops | N/A for FIFA data | Health store | Resolver errors | CODEBASE | Matchday load |

---

## 5. Stream pipeline (Phase 3) — CODEBASE

**Flow (evidenced):** `MatchHubViewModel.watchLive` → `LiveStreamResolver.resolvePlayback` with `streamStatusMessage` / `streamStatusDetail` → sessions → `LivePlayerView` / `LivePlayerViewModel` (`AVPlayer`).

**Strengths**

- Progress user messages + technical detail on resolve (`MatchHubViewModel` L180–185).
- `LivePlaybackFailureKind` + `terminalMessage` + `invalidatesP2PSession` (`LivePlayerViewModel.swift` L7–50).
- `PlayerDiagnosticService`, `StreamContractValidator` referenced on view model (L113–114).

**Gaps / risks**

- **Per-candidate structured failure log** to UI (beyond `streamStatusDetail`) — **partially** present; needs RUNTIME_LOGS to confirm UX.
- **Known-good HLS/MP4** — **TEST_RESULT: not run** this audit.
- **DASH / non-HLS** — not validated here (**UNKNOWN**).

---

## 6. Player / AVFoundation (Phase 4)

**Decision:** Do not change player architecture in this Phase 0 document.

**Apple docs:** Not re-fetched in this session for ATS/HLS edge cases.

**Evidence:** CODEBASE (`LivePlayerViewModel`, `LivePlayerView`).  
**Risk if wrong:** Misclassified stalls vs network (**ENGINEERING_INFERENCE** until log-backed).

---

## 7. Matchday UX, performance, App Store (Phases 5–9) — highlights

| Topic | Finding | Evidence | Risk |
|--------|---------|----------|------|
| **ATS** | `NSAllowsArbitraryLoads` = **true** | `Info.plist` | App Store scrutiny |
| **Integrity polling** | 60s remote toggle in Release | `IntegrityService.swift` | Network / UX if endpoint slow |
| **Background audio** | `audio` mode set | `Info.plist` | OK for live |
| **Debug** | `LiveStreamDebugSheet` gated by `#if DEBUG` in selector sheet region — verify no DEBUG overlay in Release build config | CODEBASE grep pattern | Ship risk if mis-flagged |
| **Secrets in logs** | `print` widely used (e.g. `LiveScoreService`, `MatchListViewModel`) | CODEBASE grep | **P2 — log hygiene** |

---

## 8. P0 / P1 / P2 / P3 issue list (fix order)

### P0 — Launch blockers (none proven without TEST_RESULT)

- **UNKNOWN (needs TEST_RESULT):** Crash-on-launch, Release player black screen on primary provider — *not observed in static read*.

### P1 — World Cup / trust critical

1. **Insights show placeholder / invented form & probability** — `FootballRepository.getMatchInsights`.  
   **Evidence:** CODEBASE. **Fix:** Derive from API or show “Data unavailable.”

2. **Highlights tab shows mock highlights/story when empty** — `HighlightsHubTab`.  
   **Evidence:** CODEBASE. **Fix:** Honest empty state; link to real provider only.

3. **Arena stack still imports `MockMatchService` for fixture/poll paths** — `ArenaView.swift`.  
   **Evidence:** CODEBASE. **Fix:** Gate mocks behind DEBUG or remove from production navigation.

4. **World Cup discovery not implemented** — only PL+UCL in `getPremiumFixtures`.  
   **Evidence:** CODEBASE. **Fix:** Add WC league/tournament IDs from API-Football docs + UI entry (minimal).

5. **Live score legacy map sets `minute: nil`** — may hide live minute in UI.  
   **Evidence:** CODEBASE `FootballModels.swift` ~397+. **Fix:** Map API minute / status elapsed.

### P2 — Important polish

- Hardcoded homelab IP for match list (`MatchListViewModel`). **Evidence:** CODEBASE. **Fix:** `Config` / env.
- `LeagueTeamPicker` mock teams comment. **Evidence:** CODEBASE.
- `MatchHubViewModel` `arenaActivityCount = Int.random` for half-time — **feels fake**. **Evidence:** CODEBASE L121.
- `NSAllowsArbitraryLoads` — tighten ATS exceptions. **Evidence:** CODEBASE.

### P3 — Later

- Animations / extra polish in `Design/UI/Animations.swift` — not audited in depth.

---

## 9. Dead / duplicate / mock code hygiene

| Item | Detail | Evidence |
|------|--------|----------|
| `loadMockData()` in `MatchHubViewModel` | **Defined but not referenced** elsewhere in repo grep | CODEBASE |
| `Features/Live/` | Legacy paths may still exist in tree (git status historically showed `Live/`); confirm routing not duplicated | UNKNOWN without full route grep |

---

## 10. Testing matrix (Phase 10) — status

| # | Test | Status this audit |
|---|------|-------------------|
| 1–5 | Fresh / poor / offline launch | **NOT RUN** |
| 6–11 | Home, fixtures, match detail lifecycle | **NOT RUN** |
| 12–13 | Known-good HLS / MP4 | **NOT RUN** |
| 14–18 | Provider streams, fallback, reopen | **NOT RUN** |
| 19–22 | BG/FG, lock, poor network playback | **NOT RUN** |
| 23–28 | Timeline, scores, highlights, arena, settings, notifications | **PARTIAL** code review only |
| 29–31 | Simulator, physical iPhone, Release | **NOT RUN** |

---

## 11. Recommended next sprint (ordered)

1. **Remove or gate all production mock UI** (Highlights, Arena, Insights placeholders). — *P1*  
2. **Implement honest Insights** from API-Football (or hide tab sections). — *P1*  
3. **World Cup minimum:** configurable league/tournament id(s) + dashboard section fed by real `getFixtures` / standings endpoints per **PROVIDER_DOCS**. — *P1*  
4. **Run known-good HLS/MP4** + one P2P path; archive logs (**RUNTIME_LOGS**). — *P0/P1 validation*  
5. **Homelab URL + ATS** hardening. — *P2*  
6. **Replace `print` with `Logger` + redaction** for production. — *P2*

---

## 12. Evidence discipline (self-check)

Every **major** negative claim in sections 3–8 is tied to **CODEBASE** file paths. Items requiring device/API proof are marked **UNKNOWN** or **TEST_RESULT: not run**. No **ENGINEERING_INFERENCE** is presented as **TEST_RESULT**.

---

## 13. Files worth first code touch (implementation Phase 12 — *not done in this deliverable*)

1. `Fotty/Core/Data/Repository/FootballRepository.swift` — `getMatchInsights`  
2. `Fotty/Features/MatchHub/Tabs/HighlightsHubTab.swift`  
3. `Fotty/Features/Arena/ArenaView.swift` — `MockMatchService` usage  
4. `Fotty/Core/Providers/Football/FootballModels.swift` — `LiveScoreService` mapping / intervals  
5. `Fotty/Features/Dashboard/MatchListViewModel.swift` — homelab URL configuration  

---

*End of Phase 0 audit. No production behavior was changed by this document.*
