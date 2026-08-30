# Fotty 2.0 Completion Report

Status: Complete; all accepted Fotty 2.0 release gates passed  
Candidate: `2.0.0 (33)`  
Evidence date: 2026-08-24–26 (America/Port_of_Spain / UTC)

This is the historical build-33 foundation acceptance report. It does not certify
later builds or the next product phase. Current reliability release and user
acceptance are tracked in [build 43](../releases/Fotty-2.0.0-43.md) and
[round one](../beta/ROUND-01-ACCEPTANCE.md); the approved sequence is in
[the next-phase plan](../NEXT-PHASE-PLAN.md).

## Outcome

Fotty 2.0's product journeys, data/server boundaries, automated Swift suite, generic iOS builds, static analysis, accessibility coverage, and current-provider continuity checks are implemented against the accepted contract. Build 33 is the exact signed candidate installed, independently version-reported, launched, and held as the normal app for 60 seconds on both devices. Physical playback continuity, background/foreground, native handoff, real iPad PiP, teardown, iPhone native controls, direct iPad web unmute/Pause/Play with clean audio, deliberate source switching, compact Coach keyboard behavior, the corrected small/medium widget plus FPL tap route, large-Type interaction on both form factors, and real alert/Live-Activity return all pass. The exact aggregate build-33 Catalyst gate also passes all eleven accessibility audits plus rapid navigation/foreground recovery in one invocation. The owner-authorized deletion of the retired Cloudflare Tunnel revoked the historically exposed credential without affecting Fotty's Worker. Both affected advertised branches are rewritten and independently verified clean while `origin/main` and tags remain unchanged. GitHub Support closed ticket `#4701297` after purging the retained pull-request objects. Independent authenticated API checks now return `No commit found` for both obsolete commit IDs, their public web pages return HTTP 404, the four retained PR refs are absent, and a fresh public heads/tags clone contains neither old commit nor `cert.json`. Every accepted Fotty 2.0 release gate is complete.

## Seven-pillar completion audit

| Pillar | Current implementation authority | Verification evidence | Result |
| --- | --- | --- | --- |
| Data truth and identity | `MatchModels`, `FootballRepository`, normalized providers, canonical aliases, Premier League official-FPL-first scores, and bounded Worker fallbacks | Identity tests cross catalog, schedule, score, FPL, notification, Match Center, and playback boundaries; score-mode/quota tests and production schedule/health smokes pass | Implemented and verified |
| Playback reliability | `LivePlayerViewModel`, `LiveWebEmbedPlayerView`, numbered source curation, native handoff, lifecycle recovery, typed failure UI, and `FottyQualityStore` | Complete playback policy suite; corrected provider matrix; physical same-source continuity, background/foreground, native controls, iPad PiP, teardown, deliberate switching, clean unmute/audio, and nuisance containment pass | Implemented and verified |
| FPL decision system | Official/live models, shared rules resolver, squad validator, projection/planner engines, Transfer Lab, Rival Race, saved scenarios, Decision Journal, and review loop | Complete FPL trust suite covers official scoring, legal autosubs, captaincy, Bench Boost, hits, blanks/doubles, optimizer legality, planning, rivals, and isolation; physical 64-point case agrees with published substitutions | Implemented and verified |
| Smart Coach | On-device deterministic facts/rules plus consent-gated `FPLSmartCoachService` and the production Worker over refreshed compact evidence | Zero-token rules tests/smoke, structured model smoke, malformed/stale/contradictory fail-closed coverage, and physical compact Send/Return keyboard behavior pass | Implemented and verified |
| Matchday UX | Shared Home catalog, `MyMatchdayStore`, followed/FPL relevance, bounded Recent, one Match Center, truthful Watch/In Play/Open actions, and compact editorial UI | Navigation/identity regressions, exact Catalyst Home/Matchday/Match Center audits, physical compact/regular review, and large-Type interaction pass | Implemented and verified |
| Native system experience | Capability-gated AVKit/PiP/AirPlay, `FottyLiveActivityController`, deadline widget, notification/deep-link routes, and complete teardown | Typed route/widget/activity tests, real iPad PiP and termination, confirmed small/medium widget route, real alert/Live-Activity return, and both-device large-Type acceptance pass | Implemented and verified |
| Quality and release discipline | Shared `2.0.0 (33)` version, sequential bounded-cache runners, Review Safe boundary, analyzer, accessibility gate, durable memory, secret-response runbook, and this report | Complete Swift suite, 68/68 web/Worker tests, Release and Review Safe builds, analyzer, eleven-audit aggregate, both physical installations/holds, clean-history branch/replay proofs, closed GitHub ticket `#4701297`, independent obsolete-object unreachability checks, and `git diff --check` pass | Implemented and verified |

## Implemented product journeys

### Discover and open

- Home is broad catalog discovery; Matchday is saved, followed-team, and FPL-relevant planning.
- `LIVE` is reserved for supported catalog broadcasts; source-less active fixtures use `IN PLAY` and open Match Center.
- Canonical identity and provider aliases survive score, notification, FPL, Match Center, and playback routing.
- The unreachable second Match Center and obsolete Arena/Highlights tabs were removed.

### Start and keep playback

- `LivePlaybackState` and decoded advancing video remain the only visible success authority.
- Attempt/item guards reject stale callbacks; network restoration keeps the same web attempt; native failure returns to the same web broadcast before failover.
- Web sources receive a 20-second startup window, one same-source retry, bounded stall recovery, typed failure boundaries, and manual numbered source control.
- The web companion never treats a cross-origin iframe load as decoded success, does not auto-replace an unobservable loaded feed, and hides new-tab/PiP controls that cannot fulfill their promise.
- Native player, AirPlay, PiP, and Live Activity are offered only after capability is proven.
- Quality milestones and terminal outcomes are bounded, redacted, local, and exportable.

### Prepare for the deadline

- Plan exposes squad truth, bank/free-transfer limits, validation, deadline/phase, freshness, and availability.
- Squad lenses expose fixture, modeled points, expected minutes, form, ownership, price movement, and live points with provenance/confidence.
- Transfer Lab and planner compare Roll, one-move, and two-move routes week by week with hit cost, break-even, downside, checks, and legality.
- Named manager-scoped scenarios persist locally and never imply official submission.

### Follow the live gameweek

- Official current and provisional rules totals are separate.
- Deterministic Swift/Worker coverage includes goalkeeper/outfield autosubs, legal formation/bench order, captain-only vice promotion, Bench Boost, transfer hits, published substitutions, blank/double boundaries, and checked-final truth.
- Rival Race uses published squads; Match Lens reads the same device-local squad/live snapshot.

### Review and improve

- Confirmed reviews record points/rank/cost/captain/bench/top-scorer facts from official data.
- Decision Journal entries remain manager/season scoped.
- The latest reflection appears as a process lesson in the next Plan cycle without treating outcome as proof of causation.

## Coach and server evidence

- Production Worker: `39e913bd-d1fb-48e4-bf56-20be2ba183e4`.
- Deterministic production smoke: fresh official evidence, high confidence, non-empty evidence, `Fotty FPL Rules Engine`, and `0` total tokens.
- Bounded model smoke: HTTP 200, `deepseek-v4-flash`, fresh evidence, medium confidence, 8 evidence items, 5 uncertainty items, 4 checks/actions, 15,357 prompt tokens, 831 completion tokens, and 16,188 total tokens.
- One earlier model smoke returned HTTP 502 and failed closed. The Worker was then hardened to reject empty/incomplete structured output itself, covered by direct contract tests, redeployed, and re-smoked.
- AI/provider credentials remain Worker secrets; app-source and build-product scans found zero literal AI/provider credential strings. The separate historically tracked Cloudflare tunnel credential was revoked by deleting its exact retired tunnel. GitHub closed Support ticket `#4701297` after removing the retained objects; fresh advertised-history checks contain no `cert.json`, both obsolete commit API queries return `No commit found`, both public commit pages return HTTP 404, and all four PR refs are absent.

## Automated evidence

| Gate | Result |
| --- | --- |
| Swift `FottyTests` on Mac Catalyst | Complete build-33 suite, widget source/route contract, Coach quick-prompt focus contract, and injected-script parse contract passed; the live provider soak remains intentionally opt-in |
| Web/Worker unit tests | 68 passed, 0 failed |
| Production Next.js/TypeScript build | Passed |
| ESLint | 0 errors; 91 existing warnings recorded for later cleanup |
| Generic iOS Debug | Passed, signed, and strictly seal-verified for `2.0.0 (33)`; the exact artifact is installed on both devices |
| Generic iOS Release | Passed for `2.0.0 (33)` after final app-source changes |
| Review Safe Release | Passed compile-only for `2.0.0 (33)` after final app-source changes |
| Generic iOS static analysis | Passed with no analyzer findings |
| Catalyst UI release gate | Passed in one exact build-33 invocation on 2026-08-26: all eleven accessibility audits—six Dashboard scopes plus direct FPL, Matchday, Settings, Match Center, and Player Dynamic Type—and rapid navigation/foreground recovery. No simulator was used and the owned DerivedData folder was deleted on exit. |
| Project file / whitespace | Project parses; `git diff --check` passed after the final source changes |
| Syntax / plist / secret hygiene | Shell/plist checks pass and client API-key values remain empty. The working tree deletes and ignores `cert.json`; the owner-authorized deletion of its matching retired tunnel completed revocation, all four accessible Cloudflare accounts report zero active tunnels, and the active Fotty Worker still returns HTTP 200. A disposable `git-filter-repo` 2.47.0 rewrite atomically replaced the two affected branch heads; `origin/main` and the empty tag set remain unchanged. A separate temporary clean-branch replay reproduced all 310 tracked changes and 120 Git-visible untracked files exactly without `cert.json`, then cleaned itself without touching the active checkout. GitHub closed Support ticket `#4701297` after removing the retained objects; both obsolete commits are independently unreachable, all four PR refs are absent, and a fresh heads/tags-only clone contains neither old commit nor `cert.json`. |

## Active-provider evidence

At 2026-08-25 03:55 UTC, the catalog exposed 229 events and 7 near-live events. Four current family samples were observed for up to 20 seconds each with navigation-only provider referrers. The `golf` family decoded and advanced at 960×540 after about 13.8 seconds with media HTTP 200 and zero popups. `admin` and `delta` returned media HTTP 200 without advancing decoded video in the window; `echo` returned media HTTP 500. An earlier all-403 run was invalidated after the audit was found to override the HLS referrer globally; a controlled probe and corrected rerun proved that was a harness-created failure.

The follow-up pool continuity run at 04:09 UTC tested both numbered `golf` feeds. Both decoded in about 9–13 seconds and passed a 45-second post-decode hold, advancing about 43.3 and 65.1 media seconds. Their longest observed freezes were about 1.0 and 5.0 seconds, all observed media responses were HTTP 200, no media requests failed, and neither opened a popup. The audit records the final player state but judges the complete hold window, avoiding a false failure when HLS transiently reports a lower final `readyState` between segment downloads. The independent active-provider and short continuity gates are satisfied, but physical controls, audible unmute, recovery, native/PiP, alerts, and teardown still require the normal app on hardware.

At 16:21 UTC, a new post-kickoff preflight found 235 catalog events and three near-live events. Both current football candidates were `echo` embeds and returned repeated media HTTP 500 throughout their bounded observations. This is recorded as a provider failure and cannot satisfy physical playback acceptance; it is not reclassified as an app-controlled failure.

At 16:46 UTC, the kickoff-aligned rerun observed four near-live events and the same two `admin` broadcasts. Both decoded and passed the full 45-second hold: feed 1 advanced about 45.3 seconds with zero observed freeze; feed 2 advanced about 43.0 seconds with a longest pause of about 2.0 seconds. Both returned HTTP 200 media with zero popup and zero media-request failure. This provides a current physical-test target but still does not substitute for touching the controls, audible unmute, lifecycle, PiP, alerts, and teardown on iPhone/iPad.

At 18:03 UTC, a refreshed matrix found 10 near-live events and decoded 7 of 16 sampled football broadcasts across the `admin` and `delta` families. A focused `admin` feed then decoded in about 8.4 seconds and passed a 45-second post-decode hold, advancing about 45.28 media seconds with zero observed freeze, eleven HTTP 200 media responses, zero failed media requests, and zero popups. Only redacted results were retained; the temporary URL-bearing reports were removed. A decoding hardware target therefore existed during the release gate, but physical touch and audible behavior remain unclaimed until a current source is exercised directly in the normal app.

Later physical iPhone use of build 16 opened Abha–Al-Khaleej with one current broadcast. The redacted quality trace recorded two complete same-source startup attempts about 21 seconds apart, zero decoded starts, zero automatic failovers, and one terminal failure after the second full window. That proves Fotty did not abandon or replace the source early; the provider did not produce decoded video. The same trace exposed an app-owned diagnostics defect: the deferred child-frame failure was classified as `unknown`. Build 17 now maps only deferred, non-explicit provider errors to `Startup timeout: no decoded video within 20 seconds` after the complete deadline, while preserving explicit provider-rejection reasons unchanged.

At 19:48 UTC during the build-22 physical window, a new redacted preflight sampled two current football events across `admin`, `delta`, and `echo`. Nottingham Forest–Leeds decoded on both `admin` and `delta`; Birmingham–Brentford decoded on `admin`. Each successful sample sustained the complete 20-second post-decode hold with about 19.8–20.1 media seconds of advancement, zero observed freeze, HTTP 200 media, zero failed requests, and zero popups. Both sampled `echo` feeds returned media HTTP 500, and one `delta` sample did not decode. The temporary URL-bearing JSON/log were moved to Trash after redacted extraction. Nottingham Forest–Leeds was the preferred immediate physical-control target during that time-bounded window.

During the build-27/28 physical window, the old LASK–Celtic Echo catalog entry supplied zero variants. Build 26 fabricated an `/1` URL, waited on an upstream 404, and mislabeled the stale entry live. Build 28 now refuses that fabricated fallback, returns immediately with no playable source, and labels it `AVAILABLE · Open broadcast`. The same build then opened Toronto Blue Jays–Kansas City Royals from a current three-source Admin/Delta/Golf catalog event. Broadcast 1 decoded and advanced on both devices for more than 60 seconds without a source change. Background/foreground preserved the same attempt on both; iPad entered genuine PiP after native handoff, and force termination removed the PiP/system surface. All temporary screenshots were deleted after inspection.

Build 29 then reproduced a provider-origin `VPN Recommended / Tap to Install and Continue Watching` solicitation over a healthy iPhone broadcast while the same selected source played normally on iPad. Build 30 applies a narrow semantic filter: it suppresses only the matched JavaScript solicitation or matching text/button ancestor, and never removes a candidate that owns video, owns an iframe, or is effectively the player/root. Exact build 30 decoded and visibly advanced Broadcast 1 on both devices without the solicitation or a source change; the provider-owned iPad `CLICK UNMUTE STREAM` prompt remained present. The owner directly confirmed unmute and Pause, a later capture showed Play/resume advancing to a different frame on the same selected source, and the owner reported no ticking or duplicate/overlapping audio. Deliberate Broadcast 1 → 2 → 1 switching succeeded, and the final capture showed Broadcast 1 selected with advancing video. This is evidence against blanket overlay removal, not a claim that every future provider advertisement can be removed.

## Native lifecycle corrections retained in build 33

- A standard web embed now suspends reachable media across its provider frame tree in the background and resumes the same selected attempt on return. Its injected JavaScript is parsed in the unit suite, and the view-model regression proves no source/attempt replacement.
- The system toggle-play/pause command dispatches a real toggle; teardown clears Now Playing metadata, callbacks, and command availability.
- A Live Activity is created only after AVKit confirms PiP is active—not merely because PiP is available or starting. Stop, failure, or availability loss clears continuity and pauses native playback when already backgrounded. Its return link reveals a surviving matching player but falls back to that match's Match Center after process termination. Cold launch still clears orphaned activities.
- These automated checks close code/configuration regressions. Build 28 additionally proves real iPad PiP and force-close teardown, build 30 reconfirms current playback after nuisance containment, and builds 31–33 retain those app paths. The owner subsequently confirmed the real alert/Live-Activity return opened the correct match/player.

## Physical acceptance state

- iPad Air (physical): the strictly verified universal normal artifact is installed and independently version-reported as `2.0.0 (33)`. Once unlocked on 2026-08-26, the normal build-33 app launched and its foreground process remained present through a 60-second bounded hold. Build 28 established beyond-60-second playback continuity, same-source background/foreground, genuine PiP, and teardown; build 30 reconfirmed advancing current WebKit playback with the fake VPN solicitation absent and the legitimate provider unmute prompt intact. Direct unmute and Pause were owner-confirmed, Play/resume was verified by a later advancing frame, deliberate source switching passed, and the owner reported no ticking or duplicate audio. `fotty://fpl` opened the regular-width Plan command center with the official 64-point state and no visible clipping. The owner confirmed build-31 small/medium widget presentation and the FPL tap route, then confirmed large-text interaction on both form factors and a real alert/Live-Activity return to the correct match/player.
- iPhone 15 Pro Max (physical): the same artifact is installed and independently version-reported as `2.0.0 (33)`. Once unlocked on 2026-08-26, the normal build-33 app launched and its foreground process remained present through a 60-second bounded hold. Build 28 established beyond-60-second playback continuity, same-source background/foreground, native handoff, and direct native tap-to-reveal/Pause/Play; build 30 reconfirmed advancing current playback without the provider VPN solicitation. Both Coach Send-arrow and keyboard Return paths dismissed the keyboard and preserved the reply; the captured rules answer correctly reported the official 64 points and two published automatic substitutions with zero tokens. Build 31 launched with the corrected widget.
- No simulator was started. No Fotty UI-test runner is installed on either physical device.
- On the Mac, the exact build-33 aggregate passes all eleven release-scope accessibility audits plus rapid navigation/foreground recovery in one guarded invocation. The complete exact build-33 Swift suite and generic-iOS analyzer also pass; no simulator was used.
- The physical-only normal-app runner completed exact build-33 60-second holds on both devices. Its CoreDevice handshake timeout is 20 seconds, it retries brief paired-state transport flaps, and it explicitly ends only Fotty's normal process before the broadly supported launch path because iOS 27 CoreDevice can terminate the app and then reject `--terminate-existing`. It rejects simulator and locked targets and never installs a UI-test runner. The post-run audit found only `com.jelani.Fotty` `2.0.0 (33)` on each device, no Xcode/UI-test process, no Fotty temporary path, and 53 GiB free.
- Desktop and 390×844 responsive browser passes found no empty interactive elements, horizontal overflow, or console errors. They also caught and closed the non-football clock, ambiguous glance-label, fake PiP, provider new-tab, duplicate broadcast-name, and iframe-success-contract regressions.

## Remaining release gates

- [x] Final build-33 Debug, Release, Review Safe, and static-analysis generic-iOS gates after all app-source changes.
- [x] All eleven build-33-source Dashboard/FPL/non-FPL accessibility audits pass without a simulator.
- [x] Exact build-33 aggregate eleven-audit plus rapid-navigation/foreground-recovery gate.
- [x] The same strictly verified normal build-33 artifact is installed, version-verified, launched, and held for 60 seconds on both physical devices. No Fotty UI-test runner is installed.
- [x] Hold the same selected build-28 source beyond 60 seconds on both devices without app-caused failover.
- [x] Final-build compact Coach Send/Return keyboard behavior and regular-width iPad Plan/deep-link reconfirmation.
- [x] Final-build small/medium widget presentation and FPL tap route.
- [x] Final-build Home, Matchday, Match Center, Player, FPL Plan/Squad/Coach/Tools, and Settings large-Dynamic-Type audits.
- [x] Direct physical large-Dynamic-Type interaction on both form factors, owner-confirmed on 2026-08-26.
- [x] Independently decoded current-provider sample with advancing 960×540 video and redacted evidence.
- [x] Physical playback acceptance for 60-second continuity, background/foreground, native handoff, iPad PiP, and teardown.
- [x] Physical tap-to-reveal/Pause/Play plus audible unmute with no duplicate or ticking sound.
- [x] Deliberate source switching returns to the chosen advancing broadcast.
- [x] Real alert/Live Activity return interaction opened the correct match/player, owner-confirmed on 2026-08-26.
- [x] Final full automated rerun and `git diff --check`.
- [x] Revoke the exposed tunnel credential. The owner-authorized deletion removed its exact retired tunnel; every accessible Cloudflare account reports zero active tunnels and the Fotty Worker remains healthy.
- [x] GitHub Support closed ticket `#4701297` after purging retained objects. Both obsolete commits now return `No commit found` through the authenticated API and HTTP 404 through the public web UI; all four PR refs are absent; a fresh heads/tags clone contains neither old commit nor `cert.json`; `origin/main` and tags did not move.
- [x] Reran `agent-finish` after recording the final security and release acceptance state.

Fotty 2.0 satisfies the accepted completion contract as of 2026-08-26. This is a product and release-acceptance statement, not a claim that every third-party broadcast will remain available or ad-free.
