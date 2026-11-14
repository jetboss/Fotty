# Build 324 committed baseline review

The owner requested a scoped commit on `wip/ios-3.0-baseline`, a full Catalyst unit run on exactly that commit, and preservation of unrelated work.

Code commit: `f9b88eb6657fb4a4744d7c8e5600b686e67ea19b`. Parent: `f3d6ed6`. Existing 323 commits: `1deda63c22d70771457c5c4e3daea6a834d36141` (implementation) and `c3c0706ec4030ac98caededb098b6a06c531cc4f` (physical receipt).

## Scope and provenance

Included the shared delivery policy, active-adapter admission accounting, selection receipts, Owner Status accounting, declared HLS/manifest role propagation, corresponding regression tests, and the explicitly requested 317–324 receipt folders. The 320 `protected-worker.patch` is archived evidence only; no backend patch was applied.

The 43-path commit excludes earlier working changes. Ownership was checked against `saved/uncommitted-2026-11-13` (`ed6dbbe`). Mixed relay/player/test and notebook files were staged by content without replacing working files. Every original working-file hash and every `docs/plans/` file hash was unchanged. The pre-existing generated notebook export remains uncommitted.

Historical 323/324 test counts describe their original broader working snapshots and do not qualify this narrower commit. The new run uses a clean detached checkout of the code commit. No suite is excluded from the `FottyTests` target; physical/UI automation is not part of this unit run.

## Fresh exact-commit validation

**Passed: 2,672 tests; 12 opt-in tests skipped; zero failures (2,684 total).** The full `FottyTests` target ran without excluded suites; `VisualRegressionTests` passed. The 12 skips are the existing opt-in production/provider/physical-media/soak gates, listed in [the redacted result](committed-baseline-validation.json). No physical tests or UI-test target ran.

The first attempt stopped before tests because a Mac Catalyst development profile was unavailable. The successful run used local ad-hoc signing and deployment-target overrides of 27.0 on macOS 27.0.1, Xcode 27.2. No provisioning or Apple account changes were made. Runtime warnings concern existing SceneStorage/FocusState use in rendering tests, not failing assertions.

The exact command, commit/tree hashes, native-tree fingerprint and skip list are recorded in the JSON receipt. The test checkout remained clean before and after execution.

## Files left uncommitted

These 47 paths are untouched after the scoped commit. Some contain only the older remainder of a mixed file. Their current contents are preserved in the main working tree. In particular, the earlier relay-deadlock fix remains in the uncommitted remainder and is not part of this narrowly scoped baseline.

```text
 M .github/workflows/provider-monitor.yml
 M .github/workflows/ucl-match-window.yml
 M Fotty/Core/Models/SportsFixtureCatalog.swift
 M Fotty/Core/Networking/LocalStreamProxy.swift
 M Fotty/Core/Networking/LocalStreamProxyPolicy.swift
 M Fotty/Features/Dashboard/Components/HomeSportsDiscovery.swift
 M Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift
 M Fotty/Features/Dashboard/MatchListViewModel.swift
 M Fotty/Features/Dashboard/SportsDashboardView.swift
 M Fotty/Features/MatchHub/MatchHubView.swift
 M Fotty/Features/MatchHub/MatchHubViewModel.swift
 M Fotty/Features/Player/Components/PlaybackErrorOverlay.swift
 M Fotty/Features/Player/LivePlayerView.swift
 M Fotty/Features/Player/LivePlayerViewModel.swift
 M Fotty/Features/Player/ViewingSessionCoordinator.swift
 M FottyTests/FootballScoreReceiptTests.swift
 M FottyTests/LivePlayerRetryLifecycleTests.swift
 M FottyTests/LocalStreamProxyTests.swift
 M FottyTests/PlayerChromeUsabilityTests.swift
 M FottyTests/SportsFixtureCatalogTests.swift
 M FottyTests/ViewingSessionCoordinatorTests.swift
 M FottyUITests/FottyNavigationUITests.swift
 M docs/notebooklm/Current-State.md
 M docs/notebooklm/Decisions-Log.md
 M docs/notebooklm/Fotty-NotebookLM-Source.md
 M tools/audit-ucl-readiness-policy.mjs
 M tools/audit-ucl-readiness-policy.test.mjs
 M tools/audit-ucl-readiness.mjs
 M tools/audit-worker-health-policy.mjs
 M tools/audit-worker-health.mjs
 M tools/audit-worker-health.test.mjs
 M web/workers/playback/README.md
 M web/workers/playback/src/broadcast-registry-policy.mjs
 M web/workers/playback/src/broadcast-registry.mjs
 M web/workers/playback/src/broadcast-registry.test.mjs
 M web/workers/playback/src/broadcast-source-adapters.mjs
 M web/workers/playback/src/broadcast-source-adapters.test.mjs
 M web/workers/playback/src/index.js
 M web/workers/playback/src/playback-catalog.test.mjs
 M web/workers/playback/src/sports-fixture-registry.mjs
 M web/workers/playback/src/sports-fixture-sources.mjs
 M web/workers/playback/src/sports-fixture-sources.test.mjs
 M web/workers/playback/src/sports-fixture-worker.test.mjs
 M web/workers/playback/src/ucl-reported-score-policy.mjs
 M web/workers/playback/src/ucl-reported-score-policy.test.mjs
 M web/workers/playback/src/worker-version.mjs
?? docs/LICENSED-SOURCES-RESEARCH.md
```

The paused coherent-Watch roadmap work remains isolated at `/Users/jelani/.codex/worktrees/fotty-coherent-watch-20261114/Fotty`; nothing from it was merged here. No push, device build, install, cloud deployment or TestFlight operation was performed. `docs/plans/` was not edited.

The temporary checkout, DerivedData and raw result bundle were removed after the redacted receipt was saved. The owned keep-awake process stopped. Original working-file and roadmap hashes remained unchanged.
