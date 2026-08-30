# Fotty World Cup Readiness Audit - Product Readiness Report

## Executive Summary
Fotty has successfully pivoted to a sports-only application, but it is currently in a "functional prototype" state for major matchday usage. While core streaming and live score services are implemented, there are significant gaps in tournament-specific features (World Cup), data integrity (placeholder/mock data), and UX polish (date grouping, error states).

**Status: Almost Ready (Needs Hardening & WC Mode)**

---

## 1. Product Feature Audit

### Home / Live Now
- `[x]` Shows live and upcoming matches via `SportsDashboardView`.
- `[ ]` **FAIL**: No prioritization for major tournaments like the World Cup.
- `[ ]` **FAIL**: Section header only shows "Football" or "Following", no date-based grouping.
- `[x]` Loads quickly using SwiftData cache + background refresh.

### Fixtures
- `[ ]` **FAIL**: Fixtures are not grouped by date.
- `[x]` Match times are localized via `kickoffDate` extension.
- `[ ]` **RISK**: "Upcoming" feed window is limited to 48 hours in `AnalyticalDataEngine`.

### Match Details (Arena)
- `[x]` Scoreboard, Timeline, Chat, and Polls implemented in `ArenaView`.
- `[ ]` **FAIL**: Uses `MockMatchService` as a fallback, which can lead to "fake" data being shown in production if API fails.
- `[x]` Community chat synced via `SocialCloudStore`.

### Live Scores & Timeline
- `[x]` `LiveScoreService` polls every 60s with multi-provider fallback.
- `[x]` Timeline events (Goals, Cards, Subs) handled in `ArenaTimelineModule`.

### World Cup Mode
- `[ ]` **MISSING**: No dedicated World Cup section.
- `[ ]` **MISSING**: No World Cup group standings or knockout brackets.

### Insights & Highlights
- `[x]` Insights based on real `API-Football` data.
- `[ ]` **BLOCKER**: `YouTubeHighlightsView` is hardcoded with a Rickroll video (`dQw4w9WgXcQ`).

---

## 2. Data Accuracy & API Audit

| Source | Provider | Refresh Rate | Notes |
| :--- | :--- | :--- | :--- |
| **Fixtures/Scores** | API-Football / Sportmonks | 60s | Stable fallback chain implemented. |
| **Streams** | Nexus Alpha / P2P | On-demand | Hybrid resolution with 12s timeout. |
| **Insights** | API-Football | On-demand | Real data, but lacks deep analysis. |
| **Highlights** | YouTube (Mock) | N/A | **CRITICAL FIX NEEDED**: Currently a Rickroll. |

---

## 3. Stream Playback Stability

- **Current State**: Uses `LiveStreamResolver` with a "Staggered Parallel Race" between Web and P2P.
- **Diagnostics**: Detailed `StreamEventRecord` and `StreamProviderAttemptLog` implemented.
- **Risk**: WebView extraction can be slow (up to 12s timeout).

---

## 4. Priority Order (Launch Blockers)

### P0 — Launch Blockers
1. **Remove Rickroll Highlights**: Replace `YouTubeHighlightsView` placeholder with real search/discovery or hide it.
2. **Remove Mock Fallbacks**: Ensure `ArenaView` and `MatchListViewModel` show honest empty states instead of `MockMatchService` data.
3. **World Cup Identification**: Add "World Cup" (WC) to `League` enum and `AnalyticalDataEngine` detection logic.

### P1 — World Cup Critical
1. **World Cup Filter**: Add a "World Cup" tab to `SportsDashboardView`.
2. **Date Grouping**: Group fixtures by date in `DashboardMatchList`.
3. **Standings Support**: Implement World Cup group standings module.

### P2 — UX Polish
1. **Empty States**: Improve empty states for "No matches today" vs "Connection Error".
2. **Player Diagnostics Overlay**: Ensure debug-only overlay is not in release builds.

---

## 5. Recommended Next Steps
1. **Phase 2 Implementation**: Update `FootballService` and `AnalyticalDataEngine` to support World Cup data.
2. **Phase 3 Hardening**: Implement a real Highlights discovery service or hide the module.
3. **Phase 4 UX**: Add date grouping to the main fixture list.
