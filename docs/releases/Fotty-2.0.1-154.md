# Fotty 2.0.1 build 154 private playback qualification

16 October 2026. Signed Release 2.0.1 (154) is installed on Jet iPad Air 4,
iPadOS 27.0.1. It retains the four core experience batches described in
`Fotty-2.0.1-148.md`. Native fullscreen and the ordinary Home/PiP/Restore journey
have current visual evidence, but mixed Web/native Watch Two still fails.
This is not a completed playback gate or TestFlight-ready claim. Phones,
shared TestFlight 121, FPL and backend deployments are unchanged.

## Repairs retained in 154

- Local causal receipts distinguish candidate validation, preparation, actual
  platform audio activation, Web transport, adoption and exact Web retirement.
  They use allowlisted scalar fields, omit stream URLs and derived source keys,
  and stop at 32 causal records per attempt and 64 activation jobs per process.
  These limits never stop normal playback. The existing quality retention and
  explicit export consent remain unchanged.
- Native fullscreen dismissal has a distinct transition and retained-PiP control
  lease. Locked epoch tickets reject time-control callbacks captured before
  dismissal or from a retired lease; deliberate retained-PiP controls remain
  eligible after the transition. No automatic Play or seek was added.
- The build 150 watchdog kill exposed a diagnostic-store deadlock, not a proven
  Device Hub fault. A background writer held the quality-store lock while
  UserDefaults delivered a main-queue observer; the main thread was waiting for
  that same lock to record Web transport. Build 152 moves UserDefaults mutations
  outside store and buffer locks. A revisioned pending overlay preserves newest
  values through reentrant notifications. Quality and performance stores share
  this repair; six bounded regressions test the lock and reentrancy contracts.
- Native candidate audio is disconnected through the public iOS 27 AVPlayer API
  before candidate Play. Uncancellable setters are serialized per exact
  player/item, with late completion reconciled to the newest requested state.
  Current source, request, item, intent, scene and audio-focus checks still apply.
  Adopted native audio reconnects only after exact old-Web retirement and a
  current selected-owner activation. Losing focus immediately mutes and requests
  serialized asynchronous disconnection.
- Candidate preflight calls neither shared audio configuration nor activation.
  On runtimes without the isolation API, automatic overlapping native probing
  retains the playing Web route; ordinary direct native playback is unchanged.
  These safeguards do not establish Web/native coexistence.

## Frozen source and local verification

Build 154 passed 1,392 Catalyst tests, with two existing optional skips and zero
failures, 1,394 total. Thirty-two tooling tests, five provider identity vectors,
source membership, native version checks and the simulator-free generic iOS
Release gate pass. Existing FocusState and unavailable-Sendable test-fixture
warnings remain. Signed native app compilation, strict signature verification,
installation and actual 2.0.1 (154) readback pass. All 42 FPL source hashes match
the starting state.

The pre-build receipt contains 1,107 files and one history-free local recovery
commit, without changing main repository refs or remote Git state:

- Receipt: `backups/release-source/2.0.1-154-isolated-candidate-no-configuration`
- Commit: `bf7f91a9675bcd0516d2652e0de7b8becf52f7a6`
- Source SHA256: `071dd5344dd58dd2489b8457920d02b0b423e84283cf62996a3b2a5565444b83`
- Bundle SHA256: `ee80ed024e1f08da7b1dd8501a2a109ac57e7db08f5c764e46b699155010bad7`

All inputs compare before build/install and after installation. Later acceptance
and memory edits are separate from the frozen production inputs. No simulator
or new physical XCTest runner was used in this continuation. The earlier build
148 Touch ID gate ran no physical XCTest methods; ordinary Device Hub interaction
does not establish exact player/item identity, audible output or continuous frames.

## Current iPad observations

On 154, both Tennis broadcasts decoded Web video. Their native candidates failed
before Play: one readiness timeout and one readiness failure. The Web stream
continued. These are correct fallback observations, not proof of native overlap.

Sky Sports Golf decoded Web video, then adopted native playback as the silent
right-hand Watch Two pane. Local attempt `B7B8BB70` records isolation completion
at 16:44:33.622 UTC and native adoption at 16:44:35.272. The sibling Tennis Web
attempt `50BEA83A` paused at 16:44:35.183, then reported playing again at
16:44:41.904 without an operator resume. This does not prove Fotty ordered that
pause or provider recovery, but it fails uninterrupted sibling playback.

Selecting Golf audio at 16:47:28 reproduced the failure. Actual platform activation
ran from 16:47:28.106 to 16:47:29.301; Tennis paused at 16:47:29.185. Selecting
Tennis audio and explicitly pressing its Play restored two advancing panes while
Golf remained silent. The app and source/pane controls stayed responsive. Neither
silent native disconnection nor zero candidate configuration resolves this pair.

Keeping the right-hand Golf pane returned the existing attempt to single viewing.
Actual AVKit fullscreen, Apple Pause/Play and advancing video were observed.
PiP advanced visibly on the iPad Home screen for over two minutes. After moving
the PiP window and using its actual system Restore button, Fotty returned to
native fullscreen and the floating window disappeared. Paused intent was
preserved; explicit Apple Play resumed video. Closing fullscreen subsequently
returned to advancing inline video without another Play or source attempt.

A separate repeat dismissed native fullscreen using Escape while PiP continued.
That retained-PiP presentation stayed alive, but subsequent Pause and Restore
attempts were not qualified: no accepted control/delegate receipt establishes
which callbacks arrived, and restoration did not visibly complete. Do not merge
that branch with the successful ordinary Home-to-Restore result. The app Stop
action retired playback and PiP normally. All-native Watch Two and audible or
external-audio exclusivity remain open.

The bounded current crash listing contains the build 150 watchdog report at
11:26:25 AST and the older 10 October report; no newer Fotty report was present.
This is not a crash-free soak claim. Build 152's earlier five-minute Tennis PiP
observation remains historical, not a substitute for 154 acceptance.

## Remaining decisions and focused repairs

Mixed Watch Two needs an explicit playback-engine policy, not more global audio
flags. The recommended next product decision is to preserve proven Web owners,
make native transfer deliberate and acknowledgement-bound, and admit engine
combinations only after actual compatibility checks. A larger alternative is a
coordinated transition of both panes to native, with rollback and per-pane Pause
fencing. Either changes user-visible behavior and needs owner agreement. Do not
ignore unknown Web pauses, repeatedly force Play, silently remove Watch Two or
enable global audio mixing.

One source-confirmed recovery defect is also recorded: after a failed retired
native-disconnect acknowledgement, `waitForNativeAudioRetirementBeforeWeb` awaits
the same failed barrier on Retry. A focused repair should renew that barrier on
explicit retry, remain fail-closed and test failure followed by a fresh successful
acknowledgement. This was not reproduced on the iPad and does not explain the
mixed-playback failure. Retained-PiP Restore needs bounded delegate/presenter
evidence before changing its hierarchy guards; Companion itself is inline.

Primary references: [Apple per-player audio disconnection](https://developer.apple.com/documentation/avfoundation/avplayer/disconnectedfromsystemaudio),
[Apple asynchronous disconnection](https://developer.apple.com/documentation/avfoundation/avplayer/setdisconnectedfromsystemaudio(_:completionhandler:)),
[Apple PiP restoration contract](https://developer.apple.com/documentation/avkit/avplayerviewcontrollerdelegate/playerviewcontroller(_:restoreuserinterfaceforpictureinpicturestopwithcompletionhandler:)),
[WebKit media-session arbitration](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/MediaSessionManagerIOS.mm).
The public audio API does not promise concurrent Web/native video ownership.

## Workstation and device handoff

The single reused 1.1 GB build gate, raw temporary crash copy, result bundles and
logs were removed after recording these results. Valid source recovery receipts
and installed Fotty 154 remain. Free disk rose from 17 to 18 GiB. No unrelated
user artifacts or caches were removed.

All sports, empty query/history, original Light/landscape and unchanged interests
were restored; sports sync remains off. Playback and PiP stopped normally. A
background transition persisted scene state before a normal no-environment
relaunch; Home retained All sports. Keyboard capture is off and Device Hub is
closed. The owned temporary caffeinate process and its assertions are absent.
Permanent sleep, lock and security settings were not changed.
