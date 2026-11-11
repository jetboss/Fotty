# Fotty developer handoff

Reviewed 10 October 2026. Fotty Sports Hub is a private iOS and iPadOS sports app
with discovery, optional third-party playback, personal Matchday planning and
an existing FPL workspace. Current work prioritizes usability, performance and
maintenance; FPL feature development is paused.

The code is suitable for incremental improvement. Preserve the working product
and its recognizable badges and sport artwork. Establish the source being
reviewed before restructuring it, and change one ownership boundary at a time.

## Source and installed versions

Jet iPad now has signed, optimized 2.0.1 build137 installed, with independent
installed-app readback. Its exact real CS2 gate proves brief native progress and
responsive controls, followed by recorded decoded-stage failure/retry; CS1 fails
and falls back. Final Home/Matchday/Search passes. CS PiP stops before start on
that actual replaced item; the passive Watch Two gate loses the runner/session
before120 seconds, not a proven app crash or full-soak pass.
See [`releases/Fotty-2.0.1-137.md`](releases/Fotty-2.0.1-137.md)
and [`releases/Fotty-2.0.1-136.md`](releases/Fotty-2.0.1-136.md). Earlier device
acceptance stays dated, not qualification of newer binaries. Owner phones remain
on125 and shared TestFlight remains121. No new distribution authority.

The local workspace contains substantial uncommitted work predating this pass.
Do not reset it or assume a checkout of GitHub contains every current repair.
Local recovery destinations identify the maintenance boundaries:

- Before: `backups/release-source/stabilization-20261010-before`.
- After: `backups/release-source/stabilization-20261010-after`.
- After coordinator/audio cleanup: `backups/release-source/ownership-20261010-after`.
- Reviewed component capture: `backups/release-source/2.0.1-129-components-reviewed`.
- Build 129 pre-build source: `backups/release-source/2.0.1-129`.
- First137 reachability pre-build source:
  `backups/release-source/2.0.1-137-ui-reachability`.
- Final installed137 passive-canary pre-build source:
  `backups/release-source/2.0.1-137-passive-canary-final`.

Each completed capture contains a `source.bundle` and `receipt.json`. The receipt
hashes every selected file and executable mode. The recovery tool verifies a
restorable single-commit bundle and scans the copied tree for secrets. It does
not change this repository's Git index, branch or history. Ignored credentials,
signing inputs, local account data and build products are not recovery inputs.
These bundles are deliberately ignored, not uploaded or automatically shared.

Verify the bundle before restoring it into a new review directory:

```bash
python3 -B tools/release_source_snapshot.py verify \
  backups/release-source/ownership-20261010-after
git clone backups/release-source/ownership-20261010-after/source.bundle \
  <new-review-directory>
```

A recovery capture establishes the captured working tree, not historical binary
provenance. Shared releases require a new pre-build capture and a source compare
before upload; see [`notebooklm/Workflow.md`](notebooklm/Workflow.md).

## Current ownership

| Responsibility | Source owner |
| --- | --- |
| Provider and accepted fixture observations | `Core/Data/Repository/FootballRepository.swift`; `Features/Dashboard/MatchListViewModel.swift` |
| Fresh football scores and retained terminal facts | `Core/Data/FootballDataPolicy.swift`; `Core/Providers/Football/FootballModels.swift` |
| Dated identity, terminal reconciliation and Home rows | `Features/Dashboard/Components/HomeSportsDiscovery.swift` |
| Home projection keys, personalization cache and ranking contracts | `Features/Dashboard/HomeCatalogProjectionPolicies.swift` |
| Home base/scope packet, cache reuse and fenced atomic publication | `Features/Dashboard/HomeProjectionCoordinator.swift` |
| Home structured task, filters, navigation and Watch commands | `Features/Dashboard/SportsDashboardView.swift` |
| Match Details presentation and view | `Features/Dashboard/CatalogEventDetailsView.swift` |
| Shared image cache, request sharing, bounded transport and decoding | `Core/Images/FottyImagePipeline.swift` |
| Ordered image selection and candidate-keyed SwiftUI state | `Design/CachedAsyncImage.swift` |
| Badge windows and remaining shared visual components | `Design/Components.swift` |
| Native and web playback lifecycle | `Features/Player/LivePlayerViewModel.swift`; `Features/Player/Components/LiveWebEmbedPlayerView.swift` |
| Serialized platform audio preparation and reset ownership | `Core/Media/MediaAudioSessionOwner.swift` |
| Injectable cancellation-aware delays and monotonic clock | `Core/Media/FottyAsyncTiming.swift` |
| Passive attempt-bound local stall/preparation intervals | `Core/Logging/FottyPlaybackIntervals.swift` |
| Admitted CS metadata and public native delivery headers | `Core/Networking/CommunitySportsAddonClient.swift` |

Paths above are relative to `Fotty/`. Read
[`notebooklm/Architecture-Map.md`](notebooklm/Architecture-Map.md) for the detailed
contracts. Current source and verified receipts outrank dated architectural
history. `web/workers/playback` is the Worker source, not evidence that a locally
staged change has been deployed.

## Invariants to preserve

Badge correctness spans source identity, artwork priority, projection inputs,
image loading and reused view state. A warm fallback must not outrank a viable
preferred crest. Loaded artwork belongs to the complete ordered URL list, and
cancellation must prevent a late result from acquiring a replacement row. Full
URLs remain cache keys; provider numeric IDs are not interchangeable badge codes.

Fixture freshness belongs to accepted source observations, not the time of a
cached read or failed refresh. Explicit, verified terminal facts outrank stale
active evidence. Empty or failed responses cannot invent a final score; generic
channels and elapsed kickoff cannot prove that a named match is live.

Home publishes one consistent base/scope packet. Exact catalog, score, clock
and selection keys plus request generations reject late work; scope-only edits
retain the accepted base revision. The view still owns the structured task and
Watch commands. Cooperative stages remain on MainActor, not detached tasks.

Audio preparation is serialized independently of transport intent. Launch and
navigation must not activate audio. Pause, replacement and dismissal revoke
late playback permission, while PiP maintenance must not revoke pending Play.
Recheck native attempt/source/player/item/user/lifecycle ownership and terminal
errors after an await. Exhaustion revokes pending transport and PiP preparation;
fresh Play cannot publish a failed attempt as playing. Explicit Retry retains its
existing new-attempt path. Media-services resets require current preparation,
not a cached active flag.
Playback, WebKit, PiP and mute handoff retain their existing native owners.

## Local verification

Use the reviewed Xcode 27 installation at `/Applications/Xcode.app`. No simulator
is permitted on the development Mac, which has 256 GB storage and 8 GB RAM.
Run heavy gates sequentially, check free disk space, and preserve unrelated
caches and owner artifacts.

```bash
python3 -B -m unittest tools/tests/test_native_source_membership.py \
  tools/tests/test_release_source_snapshot.py \
  tools/tests/test_native_version_check.py
python3 -B tools/check_native_source_membership.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
FOTTY_XCODE_JOBS=1 ./tools/ios-ci.sh
```

The membership gate resolves actual PBX group paths and checks all four target
Sources phases. The shared activity attributes file deliberately belongs to both
the app and extension; other missing, duplicate or wrong-target memberships
fail. The existing CI script runs this guard before freshly compiled Catalyst
logic tests and an unsigned generic iOS Release build, then removes its owned
DerivedData. Compilation is not signing, installation or distribution.

The initial 10 October mechanical stabilization gate passed 990 of 992 native
logic tests. The subsequent Home/audio cleanup passed 1,034 of 1,036 freshly
compiled Catalyst tests, with two existing optional skips and no failures. Its
44 new behavioural tests comprise ten Home coordinator, 23 audio ownership and
eleven Web preparation tests. They exercise controlled suspension, cancellation,
replacement, media reset, PiP/transport independence, terminal failure, fresh
remote Play and deferred-document intent. Web tests execute the emitted
JavaScript, not just source-string assertions.

The current137 source passes1093 freshly built logic tests, with two existing
optional skips and no failures. Eight added header regressions retain default
routes/deduplication and reject credentials, malformed or unsafe advertised
contracts. Public headers reach the existing proxy without broadening admission.
The temporary UI-only Release test scheme leaves production testability alone.
Consult release137 for exact source/executable receipts and physical limits.

The combined membership, recovery and version tooling suite passed 52 tests.
Provider identity vectors, generated competition data, version coherence and
`git diff --check` passed, as did the final unsigned generic iOS Release build.
Native-source checksums were unchanged across that gate. Independent review
confirmed the Home view's remaining
layout/lifecycle/Watch logic unchanged and reviewed native/Web/two-pane ordering.
The final test result contains no audio-session runtime warning and four existing
offscreen `MatchReminderTests` FocusState warnings. These results do not qualify
device sound, PiP, route recovery or frame-time performance.
Owned build products/results were removed, with approximately 30 GiB free after
the gate. No device, backend, Git publication or TestFlight gate ran.

Keep the behavioural cache, cancellation, receipt and projection tests. A large
passing test count is not a substitute for these transitions or native visual
acceptance. For a future device gate, exercise cold and warm artwork loads,
score-driven refresh, reused rows and cancelled loads; verify Home, Matchday,
Search and Details. New playback changes also need the checks in
[`../agent/playbooks/playback.md`](../agent/playbooks/playback.md).

The subsequent build 129 gate passes 1,069 freshly compiled Catalyst tests with
two existing optional skips and zero failures. Eight image ownership tests use
held transports to execute request sharing, independent cancellation, late
replacement, warm-cache cleanup and retry. Eighteen timing/interval/Web tests
exercise stale delays and attempt-bound local evidence. Nine visual tests include
the explicitly reviewed ten-image comparison; see
[`testing/Visual-Regression-Gate.md`](testing/Visual-Regression-Gate.md).
These are pinned component renders, not native UIKit/WebKit or touch proof.
Apple's read-only accessibility preferences are preserved and fingerprinted.

Native accessibility exceptions fail closed on iOS/iPadOS; only exact reviewed
Catalyst 27 static-text cases can be exempted. Physical production metrics retain
owner preferences/cache, discard one warm-up and require three finite app-target
CPU/memory/hitch/wall measurements, with verified movement and scroll signposts
for scroll tests. They include automation overhead and changing feeds; no speed
improvement or cross-build comparison is established by a single passing run.
Local audio-preparation intervals measure caller wait, not global activation
latency. Stall intervals are observational; transport playing alone is not
decoded recovery. Neither component snapshots nor muted test mode prove sound.

## Next cleanup boundaries

Home's live projection now has a tested owner. Single/two-match lookup and modal
ownership deliberately remain on the view; any further extraction needs focused
tests for transitions, cancellation and late completion before state moves.

`TeamBrandService` still combines cross-sport publisher refresh, aliases and
persistence inside `FootballService.swift`. `LivePlayerViewModel` coordinates
many lifecycle tasks. These are next review seams, not defects established
solely by file size. Separate them through measured, test-protected changes;
do not replace the architecture merely to impose another pattern.

The initial stabilization gate reported six audio-session and four focus-binding
warnings. Audio preparation is now serialized off the UI actor; physical route,
interruption, PiP and activation-latency checks remain a separate native gate.
The earlier Mac warning did not establish a device hang or an explicit app
deactivation call. Offscreen-renderer focus warnings in `MatchReminderTests` did
not establish a native focus defect. Qualify focus restoration through hosted or
device interaction rather than changing correct controls solely to silence them.

Do not delete code solely because a text search finds no direct caller. Native
target membership, SwiftUI callbacks, platform conditions and executed WebKit
bridges are part of the supported graph. Keep provider/source behavior and
privacy boundaries unchanged during cleanup. Device installation, backend
deployment, Git publication and TestFlight require their own requested gates.
