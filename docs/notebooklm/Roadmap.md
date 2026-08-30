# Fotty Strategic Roadmap

Last updated: 2026-08-28

## Approved next phase — reliability first

The owner approved the product-gap recommendations on 28 August. Execute
[the next-phase plan](../NEXT-PHASE-PLAN.md) in order: release the existing five
fixes, observe a small tester round, improve data/Coach confidence, then assess
compatibility/recovery, personalization, operating budgets and identity.
This supersedes the prior discussion-only boundary; it does not select a new
name, authorize new tester roles or approve paid infrastructure.

Release **2.0.0 (43)** is **Internal / Testing** for the unchanged two-tester group,
verified **2026-08-28 12:47 AST** after the owner's declaration/notes/group approval.
The matching Worker revision
`fafdf5ed-4d37-47e6-82b8-69dd55c3e116` is deployed and its zero-token scoring/
request smokes pass. Apple preflight shows both current testers installed 42,
but metric dashes and no feedback reports do not establish task acceptance.
Use [the 43 release record](../releases/Fotty-2.0.0-43.md) and
[round-one ledger](../beta/ROUND-01-ACCEPTANCE.md) for separate release/user gates.

## Previous delivery: 2.0.0 (42)

The owner requested consolidating the approved changes in the existing internal
TestFlight group, followed by discussion only. Apple accepted build 42 at
00:01:49 AST on 2026-08-28. At 06:18 AST, the approved declaration and saved
tester notes are complete, and build 42 is **Testing** for the unchanged
two-tester Fotty Internal Smoke group. Fresh physical acceptance and received
feedback remain distinct from this verified availability. See
`docs/releases/Fotty-2.0.0-42.md` for that release's distribution and acceptance evidence.

This packages all-sports Home, restored badges, optional Light/System appearance,
cricket/CPL discovery, dedicated FPL, provider transport fixes, countdowns,
opt-in reminders and compact Watch-right rows. It adds no new feature code.
The discussion-only boundary at that checkpoint is superseded by the later
owner approval above. Fresh device outcomes and received feedback still gate
wider invitations and the evidence-driven product changes.

## Historical 2.0 foundation acceptance: 2.0.0 (33)

Goal: make Fotty one dependable matchday loop for enjoying football and making better FPL decisions.

Implemented in the 2.0 candidate:

- One benchmark-backed product contract and five release journeys.
- Canonical match identity across Home, Matchday, scores, Match Center, alerts, FPL context, and playback.
- Truthful Watch capability, attempt-scoped recovery, typed failures, native handoff return, PiP/Live Activity eligibility, and local quality evidence.
- Premier League-only live-score scope with official-FPL-first truth and bounded Worker fallbacks.
- Official-current versus provisional deterministic live FPL, including captain fallback, legal autosubs, hits, Bench Boost, blanks, doubles, and checked-final boundaries.
- Squad decision lenses, expected minutes, projection confidence/provenance, week-by-week routes, break-even, named scenarios, Rival Race, and a decision-review loop.
- A consent-gated DeepSeek Coach over refreshed evidence, plus zero-token deterministic facts/rules and fail-closed response validation.
- A distinct personal Matchday workspace, one active Match Center, typed system routes, a deadline widget, and useful Live Activities.
- Privacy-safe local diagnostics, no-simulator release tooling, shared professional versioning, and updated durable QA guidance.

Fotty 2.0 acceptance completed on 2026-08-26:

- The exact strictly seal-verified build-33 normal artifact is installed and independently version-reported on both supported devices. Once the devices were unlocked on 2026-08-26, that normal app launched and its foreground process survived a bounded 60-second hold on each device. Its complete Swift suite, widget/Coach/injected-script contracts, normal and Review Safe Release builds, generic-iOS static analysis, version/signature checks, and bounded-cache cleanup pass. This process-survival evidence does not replace the build-31/30/28 visual, playback, control, and lifecycle evidence stated below.
- Physical build-28 playback established the complete lifecycle baseline on both devices: a source held beyond 60 seconds, survived background/foreground without changing, entered real iPad PiP, and cleared that system surface on termination. Exact build 30 decoded and advanced the same selected current source on both after the narrow fake-VPN filter, with the provider's real iPad unmute prompt preserved. iPhone native controls pass; the owner directly confirmed iPad unmute and Pause, a later frame proved Play/resume on the same broadcast, and the owner reported no ticking or duplicate/overlapping audio.
- The exact build-33 aggregate Catalyst gate passes all eleven accessibility audits—six Dashboard scopes plus FPL, Matchday, Settings, Match Center, and Player Dynamic Type—and rapid navigation/foreground recovery in one invocation. This covers every named app surface at large Type without a simulator; the owned DerivedData folder was deleted on exit.
- Exact build-30 compact Coach Send and Return both dismiss the keyboard and preserve the reply; its zero-token rules answer showed the correct official 64 points and two published automatic substitutions. Regular-width iPad Plan also fits and shows the same official state. Deliberate iPad Broadcast 1 → 2 → 1 switching succeeds and returns to advancing video. Build 31 corrects the small widget's missing source label; the owner confirmed small/medium presentation and the FPL tap route on hardware. On 2026-08-26 the owner also confirmed large-text interaction on both supported form factors and a real alert/Live-Activity return to the correct match/player. For the repository gate, the owner-authorized deletion of the exact retired Cloudflare Tunnel completed credential revocation without affecting the active Fotty Worker. Both affected advertised branches were atomically rewritten and independently verified clean while `origin/main` and tags remained unchanged. GitHub closed Support ticket `#4701297` after purging the retained pull-request objects; both obsolete commits are independently unreachable through the authenticated API and public web UI, the PR refs are absent, and a fresh heads/tags clone is clean. All accepted Fotty 2.0 gates are complete.

## 2.0.x — Daily-use evidence patches

- Fix only reproduced app-controlled playback, score, notification, FPL, Coach, accessibility, or layout defects.
- Add a regression test and quality-event definition for every confirmed app failure.
- Track startup, continuity, provider boundary, and Coach token evidence locally; do not add per-segment telemetry.
- Keep Premier League as the only live-score promise until another competition has a freshness, quota, identity, and fallback plan.
- Increment the Apple build number for every distributed acceptance build.

## 2.1 — Measured decision advantage

- Add retrospective projection calibration and decision-process review only after enough versioned, leakage-checked history exists.
- Consider live effective ownership/rank effects only with a reproducible sampling model and transparent uncertainty.
- Improve editable expected-minutes and scenario assumptions without mislabeling Fotty estimates as official expected points.
- Consider richer match visuals only when a reliable feed supplies the underlying events; never fabricate xG, momentum, ratings, or lineups.

## Later, only with an operating plan

- Cross-device sync, accounts, shared leagues, or community features require an approved backend, privacy model, abuse controls, support ownership, and sustainable cost.
- Additional playback providers require a measurable reliability gain and a supportable trust boundary.
- Additional platforms remain secondary to the physical iPhone/iPad daily-use standard.

## Explicitly retired directions

- PocketBase account/cloud sync is not active.
- Homelab AceStream/P2P, TV Guide/EPG, and World Cup-specific product paths remain retired.
- Cinema/movie discovery, betting, rumors, and a generic news feed are outside Fotty's matchday-and-FPL product promise.
