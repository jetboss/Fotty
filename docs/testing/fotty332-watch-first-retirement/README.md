# Watch-first retirement — private build 332

Owner scope: remove the active FPL product and park Watch Two, preserve football scores, club follows and saved data, keep source ranking unchanged, and verify one consolidated private build on Jet. Phone and TestFlight are excluded.

## Implementation

- Home, TV and Matchday remain the three destinations. Persisted FPL tabs and legacy FPL widget/notification links return to Home, dismissing competing presentations. Matchday, followed clubs and score services remain.
- The app target excludes 37 fantasy UI/engine files and Coach settings. Four existing FPL-named public-data/persistence files remain because scores and backups depend on them. Exact legacy Codable data models move to `FPLBackupCompatibility`; this does not delete or migrate saved data. Archived feature sources remain in Git for recoverability.
- Existing deadline notifications are removed by their exact prefix only. The existing FPL widget kind now serves a passive retirement message, makes no network requests, and uses a `.never` timeline. App launch requests only that widget's timeline reload to replace cached deadlines. Sports Plan and ordinary match alerts are retained.
- Watch Two has an immutable, default-off coordinator capability. Its controls and pair entry points are gated before discovery cancellation, model creation or ownership mutations. No settings, environment or launch-argument override is added. Pair tests explicitly enable their old behavior; paused and pending single-stream tests use the production default.
- Ranking, provider adapters, relay, player model and native player transport are unchanged. The two shared presentation/coordinator files change only Watch Two entry guards.

## Preservation and verification

The primary checkout had 46 existing owner changes. They were copied byte-for-byte into an isolated local qualification snapshot (`cdbe8284`), and all task changes are layered on that snapshot. The primary checkout is left untouched. See `scope.json` for intentionally retired compile memberships and suites; retained public score, fixture, persistence and backup cases continue running. Full unit and physical results are recorded separately in `validation.json` and `physical-watch.json` after execution.

New regression coverage includes a nonempty legacy-store capture → encrypted export → restore → capture round-trip, unchanged unrelated stored data, retired-tab restoration, deadline-ID isolation, and parked pair actions preserving paused/pending single-player ownership and existing Handoff behavior.

Actual Claude approved the frozen committed implementation without blockers after independently reviewing it through the established read-only bridge. The first compile failure was a test fixture assigning a private-set Web PiP property; the fixture now invokes the real callback. The original failed receipt is retained. No production setter or player behavior was changed to satisfy the test.

Current status: Catalyst compilation and the full suite passed (2,687 passed, 12 opt-in/physical skips, zero failures); Claude confirmed approval. The same source built signed Release 332, now installed and verified on Jet. No phone or TestFlight change.

## Actual Jet checks

Normal Watch opened the correct live WBBL Match 23 (Sydney Sixers Women–Melbourne Renegades Women) via CNC/LS1. Watch outcome was 6.599 seconds; the native hold advanced 91.225 seconds over 91.224 elapsed, with zero recorded stalls or dropped frames. Picture was 640×360. Pause retained the picture while Sources opened; resume advanced on the same attempt, after a brief Reconnecting label. Home, TV and Matchday navigation retained the mini-player; FPL and Watch Two entry points were absent. The legacy FPL link dismissed Settings and returned Home without stopping playback.

Ten of eleven protected preference values were byte-identical. The remaining value was the saved match: identity, saved time and all other fields were unchanged; only its normal cricket fixture observation timestamp advanced. One followed club and three followed leagues were byte-identical, and the copied SQLite store passed its integrity check. Source settings, interests, appearance and saved legacy fantasy data were preserved. Jet was left on Home/All sports with the test playback closed. See `physical-watch.json`.

This is ready to prepare for a controlled internal TestFlight beta, with no blocker found in the retirement change. Audio was not audible through Device Hub, and this was one live cricket route, not universal provider or PL/UCL qualification. Unchanged fullscreen/PiP and failover were not repeated. Shared distribution still needs its pre-archive immutable source receipt, archive validation, pre-upload comparison and explicit release authority. Nothing has been uploaded.
