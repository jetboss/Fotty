# Reliability fixes — first five deep-audit findings

Date: 4 September 2026. Local source after private build 58; not distributed.

## Outcome and scope

The owner approved the five highest-priority findings in the
[deep application audit](Fotty-Deep-App-Audit-2026-09-04.md). This work changes
correctness and lifecycle boundaries, not the app's navigation, subscription,
streaming entitlement, Coach model or feature count. TestFlight remains 55 and
the installed Jet iPad build remains 58. A future physical candidate needs its
own build number before installation.

## 1. Match identity is admission, not a similarity score

`CatalogPlaybackIdentity` requires both ordered canonical teams, sport and a
kickoff within 15 minutes for name-based recovery. It preserves reserve/youth/
women's qualifiers, rejects ambiguity and contradictory metadata, and retains
explicit opaque-ID, channel and single-event race/tournament contracts.

The active shared resolver validates preferred cached events too. Legacy
name-only entry points no longer guess another fixture. Unknown aliases can
therefore return unavailable until a verified mapping is added; they cannot
silently pick a similarly named opponent.

Contradictory duplicate provider IDs are kept as one quarantined, source-less
representative internally and omitted from browsing. The conflict flag survives
local cache encoding and merge; resolver entry points reject it before opening
any shared or direct-site lane. This avoids both wrong playback and duplicate
SwiftUI row identities.

## 2. Delayed retries have a lifecycle owner

`LivePlayerViewModel` owns one cancellable retry task/token. Before reloading it
checks the source, attempt, foreground/network state, explicit pause and recovery
state. Cleanup, loading cancellation, source/manual reload, pause, resumed decode,
backgrounding and network wait cancel it. Duplicate pending failures coalesce.

Cleanup invalidates the attempt so old bridge callbacks cannot revive playback.
The nearby delayed network-grace callback is also fenced against the old attempt,
cleanup and pause. Tests use the actual view model and an injected controlled
delay, checking that an uninterrupted retry happens exactly once and an
interrupted retry does not reload.

## 3. Media must belong to the visible player

The web monitor rejects hidden, tiny, offscreen and explicitly advertising-marked
videos; it keeps a paused/buffering selected player rather than electing whichever
video advances first. Known preroll state, an ended/removed element and removed
iframes release ownership so a replacement can claim it within a bounded window.

Child playback events travel through their actual parent iframe, with visible
frame checks at each level; only the main frame submits the resulting WebKit
bridge message. Source/attempt/document checks remain in place. Direct Score808
children retain pause/background/popup containment but cannot own playback.

Native handoff no longer accepts fetch/XHR/performance traffic as media evidence.
It uses the selected video's current source or a JW/Video.js API whose container
actually contains that video. An unrelated manifest or player cannot donate a
URL. Player errors are scoped to the owned container once a player is known.
Background time is excluded from stall timing; visibility loss during deliberate
suspension does not release the owner or lose its resume intent.

This is not universal advertisement detection. An unmarked full-size ad using
the same player can be indistinguishable from content. A generic opaque MSE
stream without a supported ownership API stays in WebKit, so native/PiP cannot
be promised for every source. Real-provider controls, frame nesting, background
continuity and PiP still require physical acceptance.

The API binding follows the official [JW setup/container reference](https://docs.jwplayer.com/players/reference/player-initiation),
[JW playlist reference](https://docs.jwplayer.com/players/reference/playlist) and
[Video.js player API](https://docs.videojs.com/player).

## 4. Presentation labels no longer erase delivery alternatives

Different English-language, HD/SD, URL-query, path-case and required-header
deliveries remain distinct through curation, discovery aggregation and final
source selection. Proven identical routes collapse, while round-robin family
coverage preserves alternatives under the existing caps. Existing lookup,
validation, session and timeout limits remain; retaining an alternative does not
claim it was decoded or that every provider variant is tried without a budget.

## 5. FPL refresh publishes a coherent snapshot

The visible FPL workspace owns one 60-second foreground poller across planning,
Gameweek, Squad and Coach. Automatic refresh reuses the existing observable
owner and request-revision publication path, refreshing bootstrap/gameweek,
fixtures, manager/history, published picks and live statistics. Bootstrap can
remain cached for five minutes in distant planning, but only one minute near
the deadline or during live play. Existing endpoint caches bound other traffic;
this does not call the paid Coach model.

All four scoring inputs need current, non-disk provenance. An incomplete
automatic refresh retains the whole previous snapshot and original timestamps;
an offline initial load cannot present newly calculated live points over stale
fixtures. Freshness uses the oldest of bootstrap, fixtures, picks and live stats.
Manager changes, cancellation and newer full loads invalidate late results.

A visible current-gameweek result stays visible through full time and checked
finality, then follows an official gameweek rollover. Published picks and editable
local drafts remain separate. Automatic polling avoids extra league/history-review
work and unnecessary optimizer rebuilds. The public endpoints have no shared
revision token: this is same-gameweek, bounded-age consistency, not a claim of a
server-atomic transaction.

## Verification

- Final simulator-free Catalyst run: **326 passed, zero failures, two intentional
  skips (328 total)**. Compared with the build-58 suite this adds 53 test cases.
  The skipped cases require opt-in real streaming; no historical fixture is
  presented as current live acceptance.
- New dedicated suites cover 18 catalog/delivery/quarantine cases, 14 real-owner
  delayed-retry cases and 10 FPL refresh cases. Existing monitor/aggregation tests
  now cover both direct and generic ad exclusion, player-bound MSE sources,
  frame removal, hidden-before-background ordering, bounded replacement and
  header-distinct deliveries.
- The complete `tools/ios-ci.sh` gate passed on final frozen source, including
  generic unsigned iOS Release compilation (exit 0). It also passed before the
  final stale-label/double-gameweek follow-up. Both used the same bounded build root.
- Independent review caught and corrected background ownership loss, retained
  ended-video ownership, unscoped player-error prose, missing direct-site child
  suspension, duplicate UI IDs during conflict handling, and stale-looking FPL
  labels. One new-test argument-order compile error was corrected before passing.
- Xcode still reports the pre-existing Catalyst audio-session main-thread warning
  (also exercised by the new retry tests). This is an open optimization concern,
  not a failed test and not evidence of physical playback quality.
- `git diff --check` passes. No simulator, UI-test runner, real Coach request,
  device installation, TestFlight upload, Worker/web deployment or Git publication
  was performed for this batch.

The final source is ready for a uniquely numbered private candidate, not marked
physically accepted. No live-stream success, PiP continuity or tester rollout is
inferred from the Catalyst/generic-device gate.

The owning shell's cleanup trap removed the one temporary DerivedData/result
root after qualification; its absence was verified. Peak retained build output
was approximately 1.1 GiB during the final gate and was not left on disk. No
archive, duplicate signed app or screenshot collection was created.

## Remaining acceptance and next work

- Physical player: main broadcast versus ads; play/pause/resume; old element/frame
  replacement; source changes; recovery during retry; background/foreground; native PiP.
- Physical FPL: leave the workspace open through full time/deadline, verify autosubs,
  finality, local draft retention and offline/reconnect behavior.
- The audit's remaining catalog freshness/error/order, mirror completeness,
  health-scope, CPL timing, reminder routing and notification-transition findings
  remain separate work. The duplicate player-summary cache now clears on explicit
  refresh, but its general TTL/reset lifecycle finding is not certified closed.
