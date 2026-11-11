# Fotty Graphify, Dead-Code and Optimization Audit

Date: 2026-08-31  
Status: implemented and validated locally; not deployed, installed or uploaded

## Outcome

Fotty now has one deliberately supported source graph: the iOS app and Live
Activity extension, the companion Next.js sports surface, and the Cloudflare
playback/football/Coach Worker. Retired Android/TWA, homelab/P2P and duplicate
web-player implementations have been physically removed rather than hidden
behind flags or described as inactive.

This was a structural cleanup, not a claim that a dependency graph can prove
behavior by itself. Graphify supplied the relationship map and hotspot signal;
reachability, product decisions, repository references, static analysis,
compilation and tests decided what could safely be removed.

## Method

1. Read the current product scope, architecture, decisions and risk register.
2. Generate a full code-only Graphify graph of the working tree.
3. Classify weak/disconnected areas against real app entry points, Xcode target
   membership, Next routes, Worker bindings, tests, scripts and documentation.
4. Delete only code proven retired or unreachable; retain compatibility data
   and defensive rejection boundaries when installed data or unsafe inputs can
   still encounter them.
5. Use Knip as an independent TypeScript/JavaScript reachability and export
   cross-check.
6. Rebuild and test the supported products, then regenerate Graphify from the
   final source tree.

Graphify was run from a disposable Python virtual environment with `--code-only`
and `--force`; no LLM labeling or paid token use was needed. The temporary graph
and virtual environment are not repository artifacts.

## Graph comparison

| Metric | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Code files scanned | 464 | 380 | 84 (18.1%) |
| Nodes | 6,437 | 5,769 | 668 (10.4%) |
| Edges | 16,886 | 15,005 | 1,881 (11.1%) |
| Communities | 291 | 250 | 41 (14.1%) |
| Import cycles | 0 | 0 | none introduced |

Both graphs were 94% extracted and 6% inferred. The final graph had five
partially parsed Swift files. Graphify also collapses some repeated import names
such as `SwiftUI`, so its counts are directional architecture evidence rather
than a compiler-grade proof of liveness.

## Removed product graphs

### Native application

- Removed the compile-isolated Hybrid P2P/Ace resolver, P2P session service,
  playback warmup service/models/UI, P2P telemetry and P2P-specific proxy retry
  policy.
- Simplified active playback to the supported event/web-provider resolution,
  native handoff and failover path.
- Removed unreachable social/chat/profile UI, old insights/highlights, mock
  match data, stream-debug and pipeline-validation screens/services.
- Removed obsolete avatar/photo UI and its photo-library permission.
- Retained only two intentional compatibility boundaries: unsafe P2P/Ace-shaped
  catalog inputs are rejected, and the existing Live Activity payload keeps its
  old `isP2P` field fixed to `false` so installed schema readers do not break.

### Web and Worker

- Removed the old home/search/card layer that was disconnected from the current
  v2 routes.
- Collapsed Watch to the active event-embed path and removed duplicate playback
  controllers, P2P broker/session/token code, same-origin player helpers, old
  stream-guide UI and its unused HLS dependency.
- Removed unused account/support/history shims, dead storage APIs, obsolete
  fixture/search/personalization helpers and thirteen ad-hoc Chrome/provider
  research scripts that duplicated maintained release audits.
- Narrowed module exports so internal implementation details are no longer an
  accidental public API.
- Preserved the collaboration inquiry save path after the production compiler
  correctly disproved a static false positive.

### Retired roots

- Removed the tracked `FottyTWA` Android wrapper and ignored Android build tree.
- Removed the retired homelab/P2P server tree.
- Removed the one-line scraper stub.

Historical documentation remains historical evidence; it does not make these
deleted systems supported again.

## Static-analysis exceptions

The final Knip pass reports only intentional contracts:

- `web/public/sw.js` is registered dynamically by the PWA runtime.
- Four exported football catalog constants are generated-file contracts shared
  with the catalog generator and validation workflow.
- `buildFootballMatchesUpstreamUrl` is re-exported as a server/test boundary.
- `FootballQuotaBudget` is the Durable Object class named by Wrangler, so it is
  discovered through configuration rather than a JavaScript import.

These are documented exceptions, not candidates for blind deletion.

## Remaining hotspots

Graphify's final most-connected production areas are:

- `FPLAdvisorViewModel` — 154 edges. Split only along validated state ownership:
  manager/session loading, published scoring, planning/drafts, Coach orchestration
  and rival/journal features. Avoid multiple competing truth owners.
- `LivePlayerViewModel` — 100 edges. The legacy branch is gone; the remaining
  work is to separate resolution/failover policy from AVPlayer/WebKit lifecycle
  without changing pause, PiP or provider-control behavior.
- `SportsDashboardView` — 76 edges. Extract presentation sections and commands
  while preserving one shared catalog projection.
- `MatchHubData` — 72 edges. Prefer small typed projections at view boundaries;
  do not duplicate match truth into parallel models.

`CodingKeys`, test harnesses, theme tokens and the shared `cn` class helper also
rank highly but are expected hubs rather than immediate production refactors.
No large hotspot was split merely to improve a graph score.

## First hotspot pass

After the dead-code milestone, the owner authorized the next optimization pass.
`FPLAdvisorViewModel` was selected first because it was the most connected
production node and its persistence plus derived-state seams already had direct
trust tests.

- `FPLWorkspacePersistence` now owns manager/season-scoped draft encoding,
  published/draft selection, Coach-message storage, consent lookup and legacy-key
  migration. The view model keeps all published UI state and request identity.
- `FPLAdvisorDerivedStateBuilder` now computes validation, live-squad truth,
  planning routes, command-center state and optional optimized squads from one
  immutable input. The view model applies that result and remains the only
  mutable source of truth.
- Full loads previously invoked the derived-state pipeline twice—once through
  recommendation recalculation and immediately again for the optimizer. Live
  refresh also rebuilt the same state twice. Both paths now perform one rebuild.
- The view-model file fell from 1,405 to 1,318 lines. Existing published API and
  state names were preserved, so views did not acquire a second observable owner.

The follow-up Graphify map has 382 files, 5,794 nodes, 15,090 edges and 235
communities with no import cycle. The two new focused modules legitimately add
nodes/edges, while `FPLAdvisorViewModel` falls from 154 to 152 direct edges.
This is the expected result: clearer ownership and less repeated runtime work,
not artificial minimization of the global node count. Graphify still partially
parses the same five Swift files, so the compiler/test gate remains authoritative.

## Second hotspot pass

`LivePlayerViewModel` was the next production hotspot. Playback is a higher-risk
boundary than ordinary view state, so this pass did not move `AVPlayer`, WebKit,
proxy, task, request-identity, audio-session or Picture in Picture ownership.
The view model remains the single mutable playback authority.

- `LivePlaybackPolicy` now holds the shared playback state/value contracts,
  failure classification and WebKit timing policy outside the WebKit view.
- `LivePlaybackRecoveryPolicy` turns network, native-handoff, native-fallback,
  same-source web retry and source-exhaustion precedence into one pure decision
  table. The view model executes the returned action and still owns every side
  effect.
- `LivePlaybackSourcePolicy` owns deterministic source-shape classification and
  health-ranked initial/next selection. Existing view-model query methods stay
  as thin compatibility boundaries for callers and tests.
- Removed the unused duplicate `preferredInitialSourceIndex`, unused logger and
  unused imports. The actual initializer now uses the shared selection policy.

The view-model file falls from 1,256 to 1,154 lines. On the final Graphify run,
its direct degree falls from 100 to 99. The complete graph has 383 code files,
5,819 nodes and 15,129 clustered edges; the import-cycle section is empty.
Community clustering is nondeterministic on this graph (235 and 251 communities
on successive identical-source runs), so community count is not used as a
quality claim. Graphify still partially parses the same five Swift files.

Focused playback contracts cover the pure recovery table alongside existing
attempt identity, provider rejection, pause/background, native return, PiP and
WebKit bridge behavior. The complete simulator-free Catalyst unit and generic
physical-iOS Release gate also passes. Live provider decode and system PiP
continuity remain physical acceptance work; this structural pass does not claim
either from compilation.

## Validation

- Graphify final graph: 380 code files, 5,769 nodes, 15,005 edges, 250
  communities, no import cycles.
- Knip: only the documented dynamic/generated/configuration exceptions above.
- Web ESLint: pass with no errors or warnings.
- Web/Worker unit contracts: 66/66 pass.
- Next.js 16.3.3 production build and TypeScript: pass; all 31 static pages
  generated.
- Wrangler 4.127.1 Worker dry-run: pass; Durable Object and rate-limit bindings
  resolved.
- iOS: the complete simulator-free Catalyst unit gate and generic physical-iOS
  Release build pass with two Xcode jobs and a bounded temporary DerivedData
  root.
- The two follow-up hotspot passes also pass their focused FPL/playback suites
  and the complete simulator-free iOS gate. Their disposable Graphify roots and
  bounded Xcode output are removed after use.
- No simulator, device install, version change, TestFlight upload, Worker/web
  deployment, Git commit or publication occurred.

## Release implication

This cleanup is substantial enough to join the next coherent private beta
candidate, but compilation is not physical acceptance. The next candidate must
still pass the existing exact-build iPhone/iPad playback, PiP, backup/restore,
accessibility and tester qualification gates before wider invitations.
