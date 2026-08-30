# Fotty 2.0 Benchmark and Product Contract

Status: Accepted and complete; all release gates passed  
Research snapshot: August 24, 2026  
Audience: Product owner and engineering  
Accepted starting baseline: Fotty 1.8.4 (11); current candidate: Fotty 2.0.0 (33)

## Executive Summary

- **Fotty 2.0 will be a quality and integration release, not a feature pile or a ground-up rewrite.** The existing shared catalog, deterministic playback state, official-data-first FPL stack, Matchday workspace, and native handoff remain the foundation.
- **The differentiated product is one connected matchday loop:** discover the match, watch when a supported source is available, understand what is happening, see the effect on the user's FPL team and rivals, then make the next decision.
- **Specialist products set the standard for individual jobs.** LiveFPL sets the live-FPL truth standard; FPL Review, FPL.team, Fantasy Football Fix, and open optimizers set the planning standard; FotMob and Sofascore set the match-centre standard; OneFootball sets the personalization standard; Apple sets the native playback and system-experience standard.
- **2.0 is complete only when the release gates in this document pass.** A compile, a larger feature count, or a version-number change is not sufficient.

## Product Promise

> Fotty is the complete matchday companion for a football supporter who wants to enjoy the match and win their FPL league.

The promise has three parts:

1. **Find and follow the match.** Home discovers the broad catalog; Matchday organizes the user's saved, followed-team, and FPL-relevant fixtures; Match Center explains one fixture.
2. **Watch honestly.** `LIVE` means Fotty has a supported catalog broadcast to attempt. Fotty proves playback only through decoded progress, protects a recovering stream from eager switching, distinguishes app failure from provider failure, and adopts the native player only after it proves continuity.
3. **Understand the FPL consequence.** Official facts and deterministic rules establish the current squad, points, captaincy, autosubs, rivals, fixtures, and constraints before any model explains options.

## Seven Implementation Pillars

The five user journeys below are delivered through seven engineering/product pillars. Every release gate must trace back to at least one pillar; a pillar is not complete merely because its source files exist.

1. **Data truth and identity:** canonical fixture identity, explicit provenance/freshness, Premier League official-FPL-first scoring, bounded fallbacks, and no fabricated unsupported facts.
2. **Playback reliability:** decoded-progress authority, attempt-scoped recovery, full startup windows, honest source switching, typed failures, provider-boundary containment, and local redacted evidence.
3. **FPL decision system:** official current scoring, deterministic rules, legal planning/optimization, explainable scenarios, rival context, and review/journal continuity.
4. **Smart Coach:** zero-token deterministic answers where possible and consent-gated model reasoning over refreshed, minimized evidence with contradiction rejection and visible uncertainty.
5. **Matchday UX:** broad Home discovery, personal Matchday planning, one Match Center, truthful actions/status, shared identity, and clear compact/regular layouts.
6. **Native system experience:** capability-gated AVKit/PiP/AirPlay, useful bounded Live Activities, typed notification/widget routes, lifecycle teardown, and accessible Dynamic Type behavior.
7. **Quality and release discipline:** shared professional versioning, no-simulator automated/physical gates, active-provider evidence, bounded build storage, secret hygiene, durable memory, and an evidence-backed completion report.

## Decision Principles

Every proposed 2.0 feature is classified using these rules:

- **Adopt:** universal behavior that improves truth, clarity, accessibility, reliability, or decision quality.
- **Adapt:** a proven specialist pattern that strengthens Fotty's combined matchday-and-FPL loop without copying the specialist's entire product.
- **Reject or defer:** behavior that depends on unavailable licensing, unreliable data, provider control Fotty does not possess, unsupported prediction claims, a new social/backend operation, or unrelated content volume.

The product must prefer fewer complete journeys over more disconnected tools.

## Benchmark Findings

### Live FPL truth

| Benchmark | Standard demonstrated | Fotty decision |
| --- | --- | --- |
| [LiveFPL live rank](https://www.livefpl.com/blog/fpl-live-rank) and [autosubs](https://www.livefpl.net/autosubs) | Live points are most useful when projected bonus, autosubs, effective ownership, and rank effects are separated and explained. | **Adapt.** Keep official current points distinct from provisional autosubs. Add explainable swing/rival context only when the public data supports it. Never ask the language model to calculate the total. |
| [Official FPL squad views](https://www.premierleague.com/en/news/4680259/whats-new-in-202627-fantasy-more-ways-to-view-your-squad) | Fixture difficulty, ownership, opponent, form, and price movement are useful inside the squad context instead of isolated dashboards. | **Adopt.** Make the squad pitch switchable between decision lenses without making users leave the squad. |
| [Official FPL Companion](https://www.premierleague.com/en/news/4685134/how-the-fantasy-premier-league-companion-can-help-you-in-202627) | A useful coach knows the team, availability, and budget, offers a range of options, and does not pretend there is one certain answer. | **Adopt.** Coach responses must be grounded in a verified packet, return options and tradeoffs, expose evidence/freshness, and fail closed when facts are missing. |

### Planning and optimization

| Benchmark | Standard demonstrated | Fotty decision |
| --- | --- | --- |
| [FPL Review](https://docs.fplreview.com/getting-started/about-fplreview/) | Expected minutes, editable assumptions, multi-gameweek projections, multiple drafts, solver scenarios, and retrospective process review belong to one planning loop. | **Adapt.** Add transparent expected-minutes and projection confidence, saved scenarios, week-by-week effects, and a decision review. Fotty will not claim an equivalent model without equivalent inputs and validation. |
| [FPL.team](https://fpl.team/plan/2024/) | Future transfers, chips, lineups, and substitutions are easier to reason about on a gameweek timeline. | **Adapt.** Replace isolated five-gameweek totals with a week-by-week route view and saved alternatives. |
| [Fantasy Football Fix](https://www.fantasyfootballfix.com/why_fix/) and [Fantasy Football Scout](https://www.fantasyfootballscout.co.uk/benefits) | Rotation, price movement, lineup likelihood, fixture runs, comparisons, live rank, and custom alerts reduce deadline uncertainty. | **Adapt selectively.** Use current official fields and clearly labeled Fotty estimates. Do not add alerts or statistics that cannot be refreshed reliably. |
| [Open FPL Solver](https://github.com/solioanalytics/open-fpl-solver) | Squad and transfer recommendations should respect constraints and expose configurable assumptions. | **Adopt the engineering principle.** Optimization output is independently validated, reproducible, and never described as official action. Fotty may improve its local solver without copying external implementation code. |
| [VibeGaffer](https://github.com/Jadax/VibeGaffer) | Break-even analysis, xMins, multiple strategy profiles, a transfer roadmap, and deadline-aware refresh can work with low operating cost. | **Adapt selectively.** Use break-even and uncertainty concepts. Treat unlicensed/no-license source code as behavior research only. |
| [Vaastav historical FPL data](https://github.com/vaastav/Fantasy-Premier-League) | Historical datasets can support validation, but fields may contain look-ahead bias or slower update schedules. | **Research input only.** Never silently mix historical training data with current official truth. Any later model must have a versioned dataset, leakage checks, and backtesting. |

### Match centre and personalization

| Benchmark | Standard demonstrated | Fotty decision |
| --- | --- | --- |
| [FotMob matchday features](https://www.fotmob.com/en-GB/topnews/3949-Setting-you-up-for-the-Premier-League-season) | Lineups, shot maps, live xG, detailed stats, alerts, and live FPL points can reinforce one another inside a match. | **Adapt within available data.** The Match Lens connects the user's players and points to the fixture. Fotty does not fabricate xG, momentum, or ratings when no reliable feed exists. |
| [Sofascore](https://corporate.sofascore.com/about) | Dense information becomes understandable when momentum, heatmaps, shot maps, and ratings are purpose-built visual explanations. | **Adopt the information-design principle.** Show only the most decision-relevant facts first, with progressive disclosure for detail. |
| [OneFootball](https://onefootballsupport.zendesk.com/hc/en-us/articles/4412970161937-What-does-the-OneFootball-app-offer) | Followed clubs, competitions, players, and personalized content establish a personal starting point. | **Adapt.** Matchday is the personal hub; Home remains broad discovery. Avoid a generic news feed. |

### Playback and Apple system behavior

| Benchmark | Standard demonstrated | Fotty decision |
| --- | --- | --- |
| [Apple HLS](https://developer.apple.com/streaming/) | HLS is designed to adapt to network conditions, while validation still requires varied network and visual testing. | **Adopt.** Preserve recoverable attempts across network changes, validate native candidates before adoption, and retain physical-device network testing. |
| [AVPlayerViewController](https://developer.apple.com/documentation/avkit/avplayerviewcontroller) | The system player supplies familiar controls, AirPlay, and Picture in Picture when the media is compatible. | **Adopt conditionally.** Use native playback after proof, never imply PiP for an embed that cannot continue in the background. |
| [Apple Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) | A Live Activity has a defined beginning/end, shows important glanceable updates, links to the relevant content, and is easy to stop. | **Adopt.** Eligible Fotty activities show matchup, score/minute/status, and return to the surviving player. They end when the session ends or continuity is no longer real. |

## What Fotty Will Not Become in 2.0

- A licensed broadcaster or a product that promises control over third-party stream availability.
- A broad live-score service for competitions without a sustainable score source.
- A social network, newsroom, betting product, or transfer-rumor feed.
- An AI wrapper that lets a model overwrite official facts or deterministic FPL rules.
- A clone of LiveFPL, FotMob, Sofascore, or FPL Review.
- A cloud-sync product until an approved backend, privacy model, and operating plan exist.
- A repository that revives retired PocketBase, AceStream/P2P, EPG, or World Cup-specific product paths.

## The Five Required Journeys

### 1. Discover and open a match

1. Home shows one broad chronological catalog and a clear lead match.
2. `LIVE` rows are fully tappable and have a supported source; `IN PLAY` rows open details.
3. Matchday contains only saved, followed-team, and FPL-relevant fixtures.
4. Match Center and playback retain the same canonical fixture identity.
5. Every visible action has an immediate, labeled outcome.

### 2. Start and keep playback

1. The user selects Watch or a numbered broadcast.
2. Fotty records one attempt identity and shows truthful progress.
3. A web source has a bounded startup window and one same-source retry.
4. Decoded progress cancels eager failover. Short stalls and network transitions attempt in-place recovery.
5. A verified native candidate may take over without a visible jump; native failure returns to the same web source before provider failover.
6. The failure screen names the boundary: provider unavailable, network unavailable, unsupported response, or Fotty recovery exhausted.

### 3. Prepare for the FPL deadline

1. Plan opens with the current squad, deadline, bank, estimated free transfers, availability, and validation status.
2. Squad lenses expose next opponent, fixture difficulty, form, ownership, price movement, expected minutes, and modeled points with provenance.
3. Transfer Lab compares Roll, one-move, and two-move routes week by week, including hit break-even, downside, and required checks.
4. The user can save named scenarios and compare them without modifying the official FPL account.
5. Coach reads the same facts and scenarios, presents multiple defensible options, and names uncertainty.

### 4. Follow the live gameweek

1. Live Points shows official current points first.
2. Provisional autosubs appear separately with named in/out players and legal-formation reasoning.
3. Captain, vice-captain, bench, players played/remaining, bonus, and fixture state are visible.
4. Rival Race compares published squads only and clearly separates official standings from live/modelled implications.
5. Match Center's FPL Match Lens uses the same current squad snapshot and points.

### 5. Review and improve

1. Confirmed gameweek points, rank, transfer cost, captain return, bench points, and top scorer are recorded from official data.
2. Decisions saved before the deadline are linked to the result.
3. The review distinguishes outcome luck from process quality; it never claims causal certainty.
4. The next planning cycle starts from the review's actionable lesson.

## 2.0 Architecture Contract

### Canonical match truth

- One canonical fixture identity survives schedule, catalog, score, Matchday, notification, Match Center, and playback boundaries.
- Provider-specific IDs are aliases, never substitute primary identities after matching.
- Status, score, source availability, FPL relevance, and data freshness remain separate facts.
- A conflict is visible and diagnosable; no layer silently invents a value to make the UI look complete.

### Playback confidence

- `LivePlaybackState` remains the sole visible loading/playing authority.
- Every delayed callback proves it belongs to the current attempt and item.
- Decoded progress is the only playback success fact.
- Provider health affects automatic ordering, not the user's ability to make an explicit attempt.
- Playback quality evidence is stored locally in aggregate and can be exported; it never adds per-segment network traffic.
- Web providers own their visible play, pause, seek, fullscreen, and unmute controls.

### FPL truth and modeling

- Official data, deterministic derivations, Fotty estimates, and AI explanations are distinct types and labels.
- Current scoring and autosubs never use the model.
- Projections expose horizon, expected-minutes/availability assumptions, fixture inputs, model version, and confidence.
- Every proposed squad or route passes the shared validator independently of the algorithm that generated it.
- Local drafts and scenarios never imply submission to official FPL.

### Coach

- Deterministic routing answers facts/rules/scoring without model tokens.
- Model requests contain a compact, current, minimized evidence packet and bounded conversation history.
- The response schema contains options or recommendation, confidence, evidence, downside, checks, freshness, source, model, and token usage.
- Known contradictions, malformed output, missing evidence, or stale manager identity fail closed into the deterministic local path.

### System experiences

- Notifications are scoped to explicitly followed teams and selected event types.
- Spoiler protection applies consistently to notification copy.
- Live Activities exist only for sessions or events that can provide useful ongoing state, have an explicit end, and route to the correct surviving context.
- PiP and AirPlay claims exist only when the native player reports the capability.

## Measurement Framework

Fotty is currently a personal/local-first product without a trustworthy aggregate analytics baseline. The first 2.0 foundation therefore adds privacy-safe on-device quality records and an exportable diagnostic summary. Targets below are release gates, not claims about current performance.

### Primary release KPIs

| KPI | Definition | 2.0 release target | Source |
| --- | --- | --- | --- |
| App-controlled playback continuity | Count of automatic source/item replacements after decoded progress when the provider had resumed within the recovery window, per physical-device acceptance session. | **0** | Attempt identity, decoded samples, recovery/failover reason. |
| FPL decision integrity | Deterministic current-score, autosub, legality, captain, transfer-cost, and phase cases that match the encoded official rules and fixtures. | **100% of release fixtures pass; 0 model overrides** | Versioned Swift and Worker contract tests. |
| Promise-to-action integrity | Visible Watch/LIVE/actions that lead to the promised destination or a truthful actionable state; dead or misleading controls. | **100%; 0 dead controls** | Automated policy tests plus physical-device journey audit. |

### Driver metrics

| Driver | Definition | Gate |
| --- | --- | --- |
| Proven startup time | Watch selection to first decoded advancing frame, measured only for a source independently proven playable during the same window. | Median under 10 seconds; no app timeout before the 20-second provider window. |
| Attempt stability | Number of attempt/item/source identity replacements after first decoded progress. | Zero unless a typed terminal failure or exhausted recovery is recorded. |
| Match identity consistency | Duplicate or conflicting fixture identities across Home, Matchday, Match Center, scores, notification routes, and playback in test fixtures. | Zero. |
| Coach evidence coverage | Structured Coach responses carrying freshness, evidence, downside, checks, source/model, and deterministic rule block when applicable. | 100% of accepted responses. |
| Scenario legality | Saved/planned squad states that pass budget, position, formation, uniqueness, and club-quota validation. | 100%. |
| Accessibility findings | Release-scope failures for Dynamic Type, VoiceOver description, contrast, clipping, hit regions, and element detection. | Zero unresolved high-value failures. |

### Guardrails

- No provider credential or private stream URL in source, diagnostics, documentation, or exported logs.
- No remote telemetry in the manifest/segment playback path.
- No new live-score league without a freshness, quota, fallback, and identity plan.
- No release claim based solely on a simulator; Fotty uses Catalyst plus physical iPhone/iPad acceptance.
- No hidden background poller created by Home, Matchday, widgets, or Coach.
- No increase in Coach spend caused by deterministic questions or unbounded raw payloads.

## Required 2.0 Workstreams

### A. Product and data foundation

- Add a canonical product contract and maintain it with release decisions.
- Add privacy-safe local quality records and a user-exportable quality summary.
- Reconcile obsolete QA/documentation with the active product.
- Remove compiled dead UI paths and isolate dormant playback code that can affect maintenance.

### B. Matchday truth

- Formalize canonical fixture aliases and conflict diagnostics.
- Add a single user-facing freshness/provenance treatment shared by Match Center and FPL.
- Complete Home/Matchday/Match Center navigation and action invariants.

### C. Playback confidence

- Record attempt milestones and typed terminal reasons locally.
- Add continuity regression tests for decoded recovery, network change, web/native return, and stale callbacks.
- Make provider-versus-app failure wording consistent.
- Verify provider controls, native handoff, PiP, backgrounding, and recovery on physical devices during active sources.

### D. FPL command centre and planning

- Complete deterministic scoring edge cases: captain fallback, hits, Bench Boost, doubles, official autosubs, and checked-final boundaries.
- Add expected-minutes/projection confidence and versioned assumptions.
- Add multi-gameweek scenario models, saved alternatives, week-by-week net effects, and hit break-even.
- Put decision lenses on the squad surface and remove redundant/dead FPL navigation code.
- Link review/journal outcomes to the next planning cycle.

### E. Evidence-grounded Coach

- Expand deterministic intent routing beyond scoring to rules and directly computable squad facts.
- Include scenario comparison and projection provenance in the server evidence packet.
- Enforce response schema, evidence references, freshness limits, contradiction checks, token limits, and local fallback.
- Expose returned token usage and request source in the debug/diagnostic export without exposing prompts or manager-private payloads.

### F. Native and notification experience

- Ensure Live Activities show useful match state, route correctly, and end correctly.
- Keep eligibility tied to real native continuity.
- Make notification controls and spoiler behavior complete and testable.
- Verify the deadline widget and FPL deep link on both physical form factors.

### G. Release hardening

- Pass no-simulator Catalyst unit/policy tests, web/Worker tests, generic physical-iOS Debug/Release builds, and physical iPhone/iPad acceptance.
- Close the known Dashboard accessibility findings.
- Keep every target on the same version/build, update the changelog, release process, roadmap, risks, architecture, and durable memory.

## Implementation Order

1. **Contract and instrumentation:** this document, local quality metrics, current baseline, and truthful QA playbook.
2. **Truth layer:** canonical identity/provenance/freshness and FPL deterministic edge coverage.
3. **Decision layer:** projections, expected minutes, scenarios, break-even, Coach evidence, and review loop.
4. **Experience layer:** squad lenses, Live FPL, Home/Matchday/Match Center cohesion, system experiences, and dead-control cleanup.
5. **Playback hardening:** additional continuity tests plus active-provider physical validation; implementation changes only when evidence identifies an app-controlled failure.
6. **Release gate:** accessibility, builds, Worker/web tests, physical iPhone/iPad checklist, documentation, version 2.0.0, and final report.

## Definition of Done

Fotty 2.0 is complete when all of the following are true:

- [x] The five required journeys are implemented without contradictory navigation or dead controls.
- [x] Canonical match identity tests cover schedule/catalog/score/FPL/notification/playback aliases.
- [x] Local quality diagnostics record and export playback, FPL, Coach, and data-freshness outcomes without secrets or remote segment logging.
- [x] Playback continuity gates pass in automated policy tests and on active physical-device sources.
- [x] Deterministic FPL tests cover scoring, autosubs, captaincy, hits, chips, blank/double fixtures, legality, phase, and final-data boundaries.
- [x] Planning exposes week-by-week scenarios, assumptions, confidence, legality, cost, downside, and hit break-even.
- [x] Coach deterministic routing and structured model responses pass Worker and client contract tests with bounded cost telemetry.
- [x] Home, Matchday, Match Center, FPL, notification, Live Activity, widget, and PiP behaviors pass their truthful eligibility/routing tests.
- [x] All release-scope accessibility audits pass.
- [x] Mac Catalyst unit/policy tests and web/Worker unit tests pass with no unexplained failure.
- [x] Generic physical-iOS Debug and Release builds succeed without a simulator.
- [x] The normal Fotty app installs and launches on the supported physical iPhone and iPad; no UI-test helper is installed.
- [x] Active-match manual checks are recorded for provider controls, audible unmute, recovery, source switching, background/foreground, native handoff, PiP, and teardown.
- [x] Direct physical large-Dynamic-Type interaction passes on the supported iPhone and iPad; owner-confirmed on 2026-08-26.
- [x] A real eligible alert/Live Activity return interaction opens the correct matching player or Match Center; owner-confirmed on 2026-08-26.
- [x] The historically exposed Cloudflare tunnel credential is revoked; its exact retired tunnel was deleted with owner authorization and all accessible accounts report zero active tunnels.
- [x] GitHub Support closed ticket `#4701297` after purging retained pull-request/cache objects. Both obsolete commits are independently unreachable through the authenticated commit API and public web UI, all four PR refs are absent, and a fresh public heads/tags clone is clean without moving `main` or tags.
- [x] All targets report `2.0.0` with one monotonically increased build number and the changelog/release memory agree.

## Caveats and Assumptions

- Third-party stream availability, ads embedded in provider-controlled video, compatible HLS exposure, and licensing are outside Fotty's control. The release gate judges Fotty's behavior around those boundaries.
- Official public FPL endpoints are not a licensed commercial contract and can change. Snapshot versioning, schema tests, provenance, and fallback behavior remain mandatory.
- Exact effective ownership and live overall-rank calculations require a sampling/rank model that Fotty does not currently operate. They remain deferred until data quality and cost are acceptable.
- Current API-Football access cannot serve the 2026 Premier League season on the configured plan. Premier League scoring remains official-FPL-first; broader live-score expansion is not part of the 2.0 definition of done.
- Physical acceptance depends on the relevant device being unlocked, paired, and available and on an active compatible stream. Automated work continues while a time-dependent acceptance window is unavailable, but 2.0 cannot be declared complete without the recorded checks.
