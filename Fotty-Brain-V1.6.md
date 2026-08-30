# Fotty Brain v1.6 — Stability & Onboarding Core

## 🚀 Version Overview
- **Marketing Version**: 1.6
- **Build**: 1
- **Focus**: Hardening HLS stream stability and implementing a premium, personalized onboarding experience.

---

## 🛡️ Stability Architecture (HLS & P2P)

### 1. LocalStreamProxy (iOS & Android)
The network proxy has been upgraded from a "zero-tolerance" policy to a resilient, retry-based architecture.
- **Global Retry Baseline**: All standard HLS streams now feature **5 retries** with exponential backoff.
- **P2P Throttling**: P2P (AceStream) retries have been capped at **15** (previously 45) to prevent infinite UI hangs and device heating.
- **Jitter Handling**: Implemented thread-safe socket recovery for non-P2P segments to handle transient network drops.

### 2. Player Buffering (AVPlayer)
- **Forward Buffer**: Increased `preferredForwardBufferDuration` to **20.0 seconds**.
- **Impact**: Provides a safety cushion for live streams on jittery 5G/LTE networks without introducing unacceptable latency for live sports (latency remains within the ~1-2 segment range).

---

## 👤 Arena Onboarding (v1.0)

### 1. Team Following Logic
To ensure the "For You" feed and "Social Arena" are vibrant, the app now checks for followed teams on launch.
- **Trigger**: Appears if `followedTeams.count < 3`.
- **Mandatory (Dev Mode)**: Non-mandatory for rapid iteration (Skip button included).
- **Sticky Dismissal**: Uses `AppStorage("fotty.onboarding.hasDismissed")` to prevent re-prompting after the first skip/entry.

### 2. TeamBrandService Catalog
The service was extended to support "Catalog" mode for onboarding.
- **Source**: Fetches from TheSportsDB (`search_all_teams.php`) for top European leagues.
- **Leagues**: Premier League, La Liga, Serie A, Bundesliga, Ligue 1, MLS.
- **Assets**: Authentic high-resolution club badges are automatically mapped to followed entities.

---

## 🛠️ Internal Maintenance
- **Project Configuration**: Synchronized `MARKETING_VERSION` (1.6) and `CURRENT_PROJECT_VERSION` (1) across main app and Live Activity extensions via `project.yml`.
- **Logging**: Confirmed all stream proxy logs use `os.Logger` for secure, performant debugging.

---

## 📍 Roadmap
1. **v1.7**: User Account (PocketBase) deep-sync completion and real-time chat testing.
2. **v1.8**: Live Activity "Goal Alerts" tuning and Apple Watch companion app bootstrap.
