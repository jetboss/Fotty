# Code Guardian Report: Latest
Generated: 2026-04-27 22:32:24

## Executive Summary
The Guardian has scanned the project. Found 22 issues and 5 risks.

## Top 10 Critical Issues
### 1. [UI Consistency] Hardcoded UI String
- **Description**: Found hardcoded text in UI. Use string resources for localization.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/ui/components/MediaComponents.kt
- **Confidence**: Medium

### 2. [UI Consistency] Hardcoded UI String
- **Description**: Found hardcoded text in UI. Use string resources for localization.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/core/ui/MatchComponents.kt
- **Confidence**: Medium

### 3. [UI Consistency] Hardcoded UI String
- **Description**: Found hardcoded text in UI. Use string resources for localization.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/core/ui/components/MaterialLiveCard.kt
- **Confidence**: Medium

### 4. [Data Fidelity] Placeholder Data Detected
- **Description**: Found placeholder data: 'placeholder'. Ensure real match data is used.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/core/ui/components/FottyPlayer.kt
- **Confidence**: High

### 5. [Fragility] Weak Error Handling
- **Description**: Empty or silent catch block detected.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/core/networking/HeadlessWebExtraction.kt
- **Confidence**: Medium

### 6. [Fragility] Weak Error Handling
- **Description**: Empty or silent catch block detected.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/core/storage/TeamBrandService.kt
- **Confidence**: Medium

### 7. [UI Consistency] Hardcoded UI String
- **Description**: Found hardcoded text in UI. Use string resources for localization.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/features/settings/ui/SettingsScreen.kt
- **Confidence**: Medium

### 8. [UI Consistency] Hardcoded UI String
- **Description**: Found hardcoded text in UI. Use string resources for localization.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/features/settings/ui/ProfileScreen.kt
- **Confidence**: Medium

### 9. [Fragility] Weak Error Handling
- **Description**: Empty or silent catch block detected.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/features/home/viewmodel/HomeViewModel.kt
- **Confidence**: Medium

### 10. [UI Consistency] Hardcoded UI String
- **Description**: Found hardcoded text in UI. Use string resources for localization.
- **File**: ../app/src/main/java/com/pixelperfect/fotty/features/splash/SplashScreen.kt
- **Confidence**: Medium

## Performance Risks

## Architecture Risks
- **Oversized File** in `../app/build/generated/hilt/component_sources/debug/com/pixelperfect/fotty/DaggerFottyApp_HiltComponents_SingletonC.java`: File is too large (859 lines). Consider splitting into smaller components.
- **Oversized File** in `../app/src/main/java/com/pixelperfect/fotty/core/networking/HeadlessWebExtraction.kt`: File is too large (545 lines). Consider splitting into smaller components.
- **Oversized File** in `../app/src/main/java/com/pixelperfect/fotty/core/extractors/LiveSportsExtractor.kt`: File is too large (603 lines). Consider splitting into smaller components.
- **Oversized File** in `../app/src/main/java/com/pixelperfect/fotty/features/player/viewmodel/PlayerViewModel.kt`: File is too large (589 lines). Consider splitting into smaller components.
- **Oversized File** in `../app/src/main/java/com/pixelperfect/fotty/features/player/ui/VideoPlayerScreen.kt`: File is too large (1355 lines). Consider splitting into smaller components.

## Sports Integrity Risks (CRITICAL)
- **Non-Sports Content Violation** in `../app/src/main/java/com/pixelperfect/fotty/core/network/repository/football/FootballRepository.kt`: Found prohibited non-sports keyword: 'season'. Fotty is a sports-only platform.
- **Non-Sports Content Violation** in `../app/src/main/java/com/pixelperfect/fotty/core/network/api/football/APIFootballInterface.kt`: Found prohibited non-sports keyword: 'season'. Fotty is a sports-only platform.
- **Non-Sports Content Violation** in `../app/src/main/java/com/pixelperfect/fotty/data/providers/APIFootballProvider.kt`: Found prohibited non-sports keyword: 'season'. Fotty is a sports-only platform.

## Do Not Change Yet (Risky Areas)
- **Player Logic**: Media3 implementation is sensitive to state timing.
- **P2P Resolver**: Complex threading and timeout logic.

## Next Steps
1. Review high-confidence UI issues.
2. Refactor oversized ViewModels.
3. Address lint warnings to improve code health.
