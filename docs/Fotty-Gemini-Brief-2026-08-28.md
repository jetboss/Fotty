# Fotty: where the app is now and where it is heading

Prepared for Gemini · 28 August 2026

This is a self-contained product briefing, based on the project’s recorded release state and latest completed engineering work. It is discussion context, not authorization to change code, deploy services, rename the app or start a redesign. Release status below is the last verified project checkpoint, not a fresh check of Apple or Cloudflare during preparation of this document.

## 1. What Fotty is

Fotty is an iPhone/iPad-first sports companion: discover what is on, watch through available supported third-party sources, organize your own matchday, and make better Fantasy Premier League decisions.

It began as a football app but now includes multi-sport discovery—for example football, cricket/CPL, basketball, baseball and American football, depending on the provider catalog. FPL remains a major specialist feature, but it should not dominate the experience for someone who simply wants to watch sport.

The ambition is a dependable daily-use app with a strong identity, not a collection of loosely connected tools. For FPL users, the goal is informed, explainable decisions that improve their chances in their league—not a promise that an algorithm will guarantee a win.

## 2. Actual delivery status

| State | What it means |
|---|---|
| Available in internal TestFlight | **2.0.0 (42)**, last verified as Testing for the existing small internal group. Includes the multi-sport Home, dedicated FPL, restored badges, appearance options, countdowns, opt-in reminders and compact match rows. |
| Finished locally, not yet released | Five recent playback/FPL/Coach reliability fixes, with automated tests and iOS build checks complete. Neither their Worker deployment nor a new TestFlight upload has happened. |
| Still discussion/planning | A possible new name, wider beta priorities, deeper decision-model improvements and larger architectural refactors. No new name or wholesale redesign has been approved. |

Version 2.0 is already a real internal beta; it is not a future concept waiting to be built. Normal updates should go through TestFlight. Cable installs are reserved for specifically requested debugging. The current configured minimum is iOS/iPadOS 26.4, so support for an older tester’s device cannot be assumed.

## 3. The four main destinations

**Home — discover sport.** An All sports view makes activity across sports visible without forcing users to open every category. Compact sport tiles show activity/next starts, followed by a curated Now & next selection and access to the full lineup. Team badges and recognizable sport imagery are intentional. iPad uses its width to show more sports inline, with consistently sized tiles.

**My Matchday — my personal plan.** Saved broadcasts and followed teams, grouped into useful time sections, with saved channels kept separate. It is not a second copy of Home. Saving something is silent; choosing a reminder is a separate opt-in. FPL does not automatically fill this space with squad-related fixtures.

**FPL — the specialist workspace.** Team/gameweek information, squad decisions, the Coach and deeper tools live here. FPL promotion and duplicated fantasy panels have deliberately been removed from Home and Matchday.

**Settings — preferences and support.** Appearance, help and report preparation belong here. Dark is the default, with Light and System as explicit options under Appearance. Internal engineering controls should not be prominent user-facing features.

## 4. The FPL system already exists

Users connect a public FPL team by ID or official team link and confirm its identity. The feature includes:

- Official current points and separately labeled provisional totals, including rule-based autosubs and captain/vice-captain effects.
- Formation, bench order, goalkeeper substitution, chip and transfer-hit handling; blank/double-gameweek context.
- Squad decision views, player comparisons, captain options, availability and fixture context.
- Multi-gameweek transfer routes, including holding a transfer, projected gains, hit break-even, expected minutes, downside and uncertainty.
- Legal squad validation and constrained optimization, saved alternative scenarios, rival comparisons and mini-league context.
- A decision journal and gameweek review, plus deadline reminders and an FPL deadline widget.

LiveFPL helped establish the desired standard for explaining live points and pending substitutions. Other products studied during the 2.0 work included FPL Review, FPL.team, Fantasy Football Fix, FotMob and Sofascore. These are benchmarks, not claims that Fotty has their data, prediction quality or full feature sets.

Important limits: public FPL data does not prove every authenticated account fact. Free-transfer counts may be estimates; exact selling prices can require checking official FPL. Saved transfers, lineups and wildcard plans are **local drafts**. Fotty does not submit changes to the user’s official team. Preferences and drafts are not automatically synced across devices.

## 5. The Coach is hybrid, not rules-only

There are two deliberately separate jobs:

1. **Facts and arithmetic:** official data and deterministic rules establish points, eligible substitutions and other directly computable facts. A language model should not invent or recalculate the current total.
2. **Reasoning and advice:** DeepSeek remains the model-backed Coach, accessed through a Cloudflare Worker after user consent. It receives a bounded official-data/context packet and returns an explanation with evidence, uncertainty, actions and usage information.

The useful Coach should consider the whole decision: squad legality, availability, expected minutes, budget uncertainty, free transfers, hits, captaincy, chips, fixture horizon and rivals. Advice must explain tradeoffs, not merely produce a player name.

The latest **unreleased** fixes strengthen the failure path: recognized scoring questions stay deterministic even when official data is missing or stale, rather than falling through to a paid model answer. Unknown statistics are no longer treated as zero points or proof of a non-appearance. Tactical advice still uses DeepSeek. The scoring classifier is an explicit language pattern, not perfect understanding of every possible question.

## 6. Playback and data: practical expectations

This is a small independent project. The current strategy is to improve the sources and data we can realistically use—not assume access to an expensive broadcaster partnership or a universal licensed streaming API.

- Active playback uses StreamEx/Score808 web-provider families. Provider availability and page behavior can change. A listing or a count of source links is not proof of playable video.
- Fotty should preserve a recovering stream, respect intentional pause, and avoid racing retries that replace a stream which has resumed.
- Provider controls must remain usable. No whole-screen gesture should swallow play/pause or unmute, and no extra unmute button should compete with a working provider control.
- Native playback handoff exists where an actual compatible stream can be validated. Picture in Picture is capability-dependent, not guaranteed for every web embed. Live Activities are tied to real supported playback state, not an “app is open” notice.
- Popup/nuisance containment must not destroy the player. There is no blanket guarantee that provider-origin or in-stream ads can be removed.
- Live-score coverage is intentionally **Premier League-only** for now. Other sports and competitions can still have broadcasts without scores; the UI must not call that deliberate lack of coverage “unavailable.” Champions League is a possible later expansion, not currently enabled coverage.
- Public FPL fixtures supply the primary Premier League score path, with bounded fallbacks. A configured third-party API key is not proof that its plan covers the current season.
- CPL discovery includes a dated schedule snapshot and separate cricket/channel views. A Willow-related channel listing is not proof that a specific CPL match is airing, and the snapshot is not a live program guide.

Scrapers and open-source projects are not dismissed because the app is small. Evaluate them pragmatically for a specific need: accuracy, freshness, provenance, maintenance, permitted reuse and cost. Do not build a prominent feature on data we cannot actually verify.

## 7. UX principles the owner cares about

- Compact rows: names/badges on the left, Watch on the right when space allows. Stack only when width or accessibility text requires it.
- Every button must have a useful, clearly explained action. Avoid redundant screens, ambiguous labels and visible engineering terminology.
- Upcoming events use an inline countdown. A listed source can be attempted near kickoff; a countdown is not a promise that a provider will be ready.
- Five-minute match reminders are explicitly opt-in. Tapping one returns to the saved match without autoplay. Saving alone must not unexpectedly request notification permission.
- Keep the app’s character: team badges, sport equipment icons, a coherent dark/amber identity and carefully scoped pitch/player styling. “Cleaner” must not mean generic or stripped of recognizable sport imagery.
- Light mode must work across the app, not merely invert one screen. iPhone Display Zoom, large text, keyboard behavior, iPad rotation and touch targets are real acceptance criteria.
- Home, Matchday and FPL must have distinct purposes. Do not reintroduce FPL everywhere under the banner of integration.

## 8. Latest engineering checkpoint

The complexity audit identified five concrete defects; all five have been fixed locally:

1. False stalls when a provider replaces the video or resets its playhead.
2. Unrelated video/frame errors entering the active broadcast’s failure path.
3. Missing FPL live statistics becoming false autosubs or unsupported derived totals.
4. Scoring questions reaching the model when verified scoring is unavailable.
5. Malformed Coach requests escaping controlled validation/error handling.

Verification: **191 Swift tests passed**, with one optional live-stream soak skipped; **81 web/Worker tests passed**; normal and Review Safe iOS release builds passed. This proves the tested code paths and compilation—not that the patch is deployed or that every provider stream is reliable. Broader complexity hotspots still exist; the fix was not a wholesale rewrite.

## 9. Where we are heading

### Immediate: dependable beta journeys

The next proposed release steps are to deploy the qualified Worker changes, publish a newly numbered TestFlight build, then verify actual device behavior. They require the normal release approval/checks.

Before widening the beta, test complete journeys: discover → watch → pause/resume → return after interruption; save → find in Matchday; reminder → correct return; connect FPL → understand official versus provisional points; report a problem → verify feedback was actually received.

A small, varied trusted cohort is more useful than a large tester count without actionable feedback. Previous physical-device success does not automatically certify a newer build. Match-score alerts are not a reliable background push service; local reminders cannot learn a reschedule while the app is closed.

### Near term: evidence-led 2.0.x improvements

Prioritize reproduced app-controlled reliability and usability problems. Add regressions, measure startup/continuity and Coach cost, and improve the complex code in small behavior-preserving steps. Avoid feature accumulation, a broad rewrite or new APIs without a demonstrated benefit.

### Later: measured FPL advantage and selective expansion

The indicative 2.1 direction is better decision quality: projection calibration against real outcomes, editable assumptions/expected minutes, stronger scenario comparison and learning from prior decisions. Live rank/effective-ownership effects are candidates only with a defensible data/sampling approach and honest uncertainty. Richer match visuals require reliable underlying events—not invented xG, ratings or momentum.

More live-score competitions, new playback providers, cross-device sync or community features need an operating plan, evidence of value and sustainable cost. They are not promised features. iPhone/iPad quality comes before broader platform expansion.

### Naming: open discussion

“Fotty” now understates the multi-sport experience. A new name is being considered and **does not need to start with F**. No winner has been selected. The brand should accommodate multiple sports while retaining personality; a rename alone does not justify redesigning the whole app.

## 10. Technical and operating boundaries

The main app uses Swift/SwiftUI with native media and WebKit integration; local persistence/caching supports preferences, saved matches and FPL state. Cloudflare Workers handle selected server-side data/proxy and Coach responsibilities. Provider/model secrets stay server-side. A companion web codebase exists, but it is secondary to the native app.

The homelab, PocketBase cloud accounts/sync, AceStream/P2P, old TV guide/EPG and World Cup-specific paths are retired. Legacy filenames do not make those active features. Do not propose restoring them as though infrastructure already exists.

Development runs on an 8 GB RAM, 256 GB Mac: no simulators, sequential bounded builds, one reusable temporary build area and prompt cleanup. Do not leave gigabytes of archives, result bundles or duplicate builds behind. Respect existing work and use the documented release/version process.

## Suggested discussion request for Gemini

Given this context, help evaluate Fotty’s next direction. Identify the most important remaining user-facing gaps, challenge weak assumptions, and prioritize a small number of high-value improvements. Separate beta essentials from later differentiation. Explain what each idea requires in data, engineering, ongoing cost and validation. Consider whether the multi-sport positioning and a name change make sense, without assuming we must redesign everything. Do not suggest features that already exist as though they are missing. Discuss first; do not start implementation or deployment.

## Source checkpoints

Prepared from the current project memory, decisions and architecture; the 2.0 roadmap and benchmark contract; the build-42 release record; and the 28 August complexity-fix verification record. Later dated decisions override earlier football-only positioning and historical build/distribution statements. No credentials, private provider URLs, tester email addresses or account identifiers are included.
