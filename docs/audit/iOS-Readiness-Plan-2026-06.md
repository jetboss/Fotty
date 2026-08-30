# Fotty iOS — Deep Audit Continuation Plan (June 2026)

**Baseline:** `docs/audit/World-Cup-Readiness-Audit.md` (2026-05-03)  
**Status:** M0–M4 implemented in codebase (2026-06-25). M0 playback checks remain manual on device.

---

## Milestone status

| Milestone | Status | Notes |
|-----------|--------|-------|
| **M0** Device QA gate | **Script ready** | `./tools/ios-device-qa.sh` — deploy + Release smoke + checklist |
| **M1** Trust & config | **Done** | Mocks removed/gated; homelab URL via Config |
| **M2** World Cup minimum | **Done** | API-first fixtures + standings; seed fallback banner |
| **M3** Match-day UX | **Done** | Date grouping; empty vs error; live minute on cards |
| **M4** Hardening | **Done** | ATS tightened; FottyLogger category; failover logs |

---

## M0 — Run on device

```bash
./tools/ios-device-qa.sh
# or deploy only:
./tools/ios-deploy-device.sh
```

Manual: HLS 60s+, P2P failover banner, export Console logs (`com.jelani.Fotty`).

---

## Key files (this sprint)

| Area | File |
|------|------|
| M0 QA | `tools/ios-device-qa.sh` |
| M2 WC loader | `Fotty/Features/Dashboard/WorldCupDataLoader.swift` |
| M2 API | `FootballRepository.getWorldCupFixtures/Standings`, `APIFootballProvider.fetchLeagueGroupStandings` |
| M3 dates | `Fotty/Features/Dashboard/Components/FixtureDateGrouper.swift` |
| M3 minute | `LiveScoreService` + `FottyFixture.elapsedMinutes` |
| M4 ATS | `Fotty/Info.plist` |
| M4 logs | `FottyLogger.info(category:)`; `LivePlayerViewModel.showFailoverBanner` |

---

## Definition of done (World Cup match day)

- [x] Dashboard WC section API-first with honest fallback
- [x] Match Hub honest insights/highlights
- [x] Stream failover logs to FottyLogger
- [x] No mock data in Release paths (Arena preview-only)
- [x] Physical device deploy verified (M0.1 — Jelani's iPhone 15 Pro Max)
- [ ] Physical device playback verified (M0.2–0.3 manual)
