# Sports TV guide — Jet 333 acceptance

## Authorized scope

15 November owner request authorizes the Sports TV guide install on Jet iPad, real Watch/Save/Remind checks and focused repairs. Phone, source ranking and TestFlight remain excluded. Existing saved data and source settings must survive. Base guide is `31f7f47`, itself based on released 332.

## Defects found before installation

Fresh registry metadata at 15:30 UTC advertised Bayern Munich–FC Köln on ESPN South on 20 November at 19:20 UTC, linked to the 19:30 UTC official Bundesliga fixture. The seven-day station sheet could display this row but its action resolver searched only Home’s 72-hour catalog. The new guide also incorrectly applied a 30-minute LIVE-status freshness limit to future planning identity; the accepted official receipt was 35 minutes old, consistent with the four-hour distant-fixture refresh cadence. Neither condition means the future match is invalid.

Repair: supplement absent future identities with the existing accepted 14-day Search schedule; use its 24-hour planning freshness for future Save/Remind. Keep all current duplicate/conflict/terminal vetoes and explicit registry fingerprint/expiry checks. A planning row never supplies current Watch authority or renews an observation. Source ranking and playback implementation are unchanged.

Official schedule corroboration: [Bundesliga](https://www.bundesliga.com/en/bundesliga/matchday/2026-2027/10/fc-bayern-muenchen-vs-1-fc-koeln/liveticker), [DFB](https://datencenter.dfb.de/matches/fc-bayern-muenchen-1-fc-koeln-2419425/liveticker). This future fixture is suitable for Save/Remind only, never live-playback proof. Refresh the registry and exact current link before physical actions; the original link has expired.

## Local verification

- Normal signed Release 333 before these repairs compiled successfully but was not installed; retained as `guide-release333.json`.
- Corrected source compiled and 152 focused Catalyst tests passed, zero skips/failures. Covered guide policy/presentation, accepted Search schedules, reminder stores, inline feedback and reminder background refresh.
- The new tests cover real validated five-day schedule projection, 45-minute/four-hour receipts, unrenewed publisher timestamps, 24-hour expiry, invalid future skew, unverified/conflicting/duplicate facts, expired links, terminal aliases and unchanged current Watch rules.
- Actual Claude independently approved the focused repair, no blockers. Its nonblocking observation about repeated planning projection cost on rendering remains a profiling hypothesis, not a demonstrated failure. Future Home rows intentionally use the same planning lifetime as wider Search rows.
- Test-host log contains macOS `com.apple.linkd.autoShortcut` 4097 service warnings; no test failed.

## Installation and physical status

The corrected normal signed **3.0.0 (333) installed on Jet** at approximately 15:46 UTC. Apple’s installed-app inventory independently confirms build 333. No launch or screen interaction was attempted while Jet remained locked; the mirrored screen also showed charging paused due to temperature. The owner was asked once to unlock and allow cooling. Physical **Watch, Save and Remind remain pending**, not passed.

Before/after installation, all 42 preference keys and values are identical, and the private database plus WAL/SHM copies are byte-identical. Baseline: one saved match, zero reminders, zero station favourites and six recent channels. No test-created data needed removal. Private captures are confined to the owned temporary gate and removed at cleanup. No media URLs, credentials or private device identifiers are retained here.

The corrected signed Release compile passed with unchanged source hashes; see `guide-corrected-release333.json`. The earlier full-suite result belongs to the preceding guide source; this focused repair passed 152 affected tests. No phone, ranking, provider, cloud or TestFlight changes occurred.

When available: verify guide layout/navigation; exercise normal channel Watch with advancing correct picture; exercise a fresh current fixture-linked Watch only if present; Save and Remind a fresh future linked fixture; confirm My Matchday and five-minute notification state; cancel/remove only test-created records; compare protected settings and saved identities to baseline. Existing source ranking, device opt-ins and owner data must be preserved.

Cleanup completed: owned DerivedData, signed app copies, logs, result bundles and private before/after captures were removed, and the bounded keep-awake assertion stopped. Free disk after cleanup: 29,892,534,272 bytes (27.84 GiB). No simulator or concurrent heavy build was used.
