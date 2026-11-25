# Fotty 2.0.1 build 156 private playback qualification

16 October 2026. Signed Release 2.0.1 (156) is installed on Jet iPad Air 4,
iPadOS 27.0.1. It retains the four core experience batches in release 148.
Native single-player controls and both PiP Restore branches have current visual
evidence. Watch Two audio switching still fails physical acceptance. A later
native media failure also prevents a blanket uninterrupted-playback claim.
This is not a completed playback gate or TestFlight-ready build. Phones, FPL,
shared TestFlight 121 and backend deployments are unchanged.

## Focused repairs in 155–156

- Passive discovery caches native candidates without starting native playback.
  Single Web playback has an explicit **Use Native Player** action in the
  existing More menu when a verified current candidate is available. The
  candidate prepares paused and disconnected, without shared audio calls.
  Actual old-Web suspension acknowledgement precedes candidate Play; source,
  request, intent, scene, generation and audio-lease fences are rechecked.
  Native audio remains muted until exact old-Web teardown acknowledgement and
  selected-owner activation/reconnection. Cancel and Pause retire candidates;
  unknown pre-acknowledgement Web Pause remains a veto, not ignored evidence.
- Watch Two retains original Web/Web routes rather than silently introducing a
  native sibling; originally native/native routes remain admissible. A mixed
  route is rejected without replacing the current viewing. Context checks also
  apply during source selection, retry, fallback and candidate discovery. This
  policy does not establish Web/Web audio-session independence.
- Web audio focus now requires an acknowledgement from the actual decoded
  media-owner document. Managed mute/defaultMuted/zero-volume readback covers
  video and audio elements. Parent JavaScript evaluation is not a child-frame
  acknowledgement. Exact attempt, document, request, generation and deadline
  guards reject stale, missing, replaced or navigation-invalidated replies.
  A request made during startup survives until that exact decoded start without
  extending its original deadline or rebinding to a replacement document.
- The model retains all unresolved old-attempt revocation tickets, including
  after source replacement or model removal. Coordinator waiters capture those
  tickets before cleanup. A new-attempt acknowledgement cannot settle an older
  attempt; only its exact mute reply or actual Web teardown can. Explicit retry
  renews the same-attempt acknowledgement lease. A disabled pane returning to
  single viewing stays managed/muted until the coordinator releases ownership.
  Stop, reversal, replacement and stale completion cannot grant the new owner.
- Explicit Retry after a failed native-retirement acknowledgement renews the
  barrier rather than awaiting the same settled failure forever. Failure still
  blocks Web activation until a fresh successful acknowledgement.
- Native PiP restoration follows the legitimate presented-controller chain in
  the retained marker's own window, retaining exact controller/player/item and
  source/request ownership. It does not load, seek or automatically Play.
  Dismissal epochs and retained-PiP transport admission remain separate.

## Frozen source and local verification

The final 156 gate passed 1,458 Catalyst tests, with two existing optional skips
and zero failures, 1,460 total. Thirty-two tooling tests, five provider identity
vectors, source membership, version checks and simulator-free generic native
Release compilation pass. Signed native compilation, strict signature check,
installation and actual 2.0.1 (156) readback pass. All 42 FPL source hashes match
the starting state. Existing FocusState and unavailable-Sendable fixture
warnings remain.

The first 156 run caught one obsolete test assertion: re-enabling audio must
retain unresolved old-attempt retirement waiters, not erase them. Correcting
that assertion preceded the final receipt and green full gate. No failed run is
being counted as a pass.

The final pre-build receipt contains 1,108 files and one history-free local
recovery commit. Main repository refs and remote Git state were not changed:

- Receipt: `backups/release-source/2.0.1-156-web-audio-ack-r2`
- Commit: `75a0b08ed5bff7620630fe67435bc8f2884c21b9`
- Source SHA256: `51cf3fe7c45256dbd829b5f97daf9c9cc21531cac18902a48f69742aba0ce74f`
- Bundle SHA256: `af5d0cea193bc32018656fd479d1981e9bea753bed83f4c6fe2ebe019e2298b9`
- Signed executable SHA256: `6332bfbee0b30cf8cb9e2b1fd5b9d9bde00983d658ca8815a27e15f0d8d614f1`

All 1,108 inputs compare before build/sign/install and again during physical
testing, before these acceptance/memory notes. Later documentation changes are
separate from the frozen production inputs. No simulator or physical XCTest
runner was used in this continuation. Device Hub visual inspection and bounded
local attempt records are not exact runtime-object, audible-output or continuous
frame proof.

## Current physical results

### Watch Two: confirmed failure

Golf Web attempt `50283DCC` and Darts Web attempt `C899F2C0` both decoded and
visibly advanced. Replacing the earlier Tennis pane affected only that pane;
Golf retained its current attempt. Per-pane Sources and replacement controls
worked in the bounded checks.

Selecting Darts audio paused Golf at **18:30:49.006 UTC**, despite Golf's preceding
Play intent. No native candidate ran (`candidate_count=0`). The old decoded
document's mute acknowledgement was obtained, but this did not prevent the
pause. Thus removing automatic native probes and awaiting actual DOM mute still
does not qualify Web/Web audio switching. Do not report this as merely untested.

Tennis separately experienced startup timeouts, buffering, retry and fallback
before audio selection. These receipts do not establish an all-provider outage
or its external cause. A later period of delayed Device Hub navigation was not
qualified as a responsive Return-to-one journey or a proven Fotty deadlock.

### Single native, fullscreen and PiP: bounded passes with a later failure

On the same current Golf attempt `50283DCC`, explicit Use Native Player adopted
at **18:45:18.542 UTC**. Exact old-Web retirement followed at 18:45:18.765;
platform activation completed at 18:45:18.857, then reconnection at 18:45:19.095.
Actual native fullscreen displayed advancing video. Apple Pause at 18:46:08.341
and subsequent Play worked.

PiP continued after Escape dismissed fullscreen to the retained companion.
The actual PiP controls paused at **18:47:05.688** and resumed at 18:47:22.331;
the picture visibly advanced. The actual system Restore button then removed the
floating window and returned to advancing native fullscreen. This qualifies the
previously open retained-Done branch for this bounded visual journey.

A separate native PiP repeat advanced on the visible iPad Home screen from at
least **18:48:30 to 18:49:43 UTC**. Background Pause worked; actual system Restore
removed PiP and returned to native fullscreen with Pause preserved. Neither
Restore was simulated by an app-layer replacement button.

After explicit Play and Escape around 18:50:15, the current native item reported
`failed_to_play_to_end`, CoreMedia **-12312**, at **18:50:16.188**. Existing recovery
returned to the original Web route. Its first attempt `FAE199AB` failed startup;
retry `D4EF7568` decoded at 18:50:49.458. This is a real failure, not an
uninterrupted inline-return pass. The error alone does not establish a provider,
network or fullscreen-transfer cause. Focused source review found no direct
Close-triggered load/Play/seek; the accepted media-failure handler explains the
new Web attempt. A later explicit native retry reached readiness timeout while
Web video continued. Do not erase either failure because fallback recovered.

Build 155 separately passed native fullscreen, retained-Done PiP Pause/Play and
Restore, >60-second Home PiP, paused Restore and subsequent inline advancement.
Those are historical 155 observations, not substitutes for a missing 156 result.

The current bounded crash listing contains only the build 150 watchdog report
and the older 10 October Fotty report. No newer Fotty report was present; this is
not a crash-free soak or cause attribution for delayed mirror input.

## Remaining material decision

No additional narrow evidence-backed focus-transfer defect was found on final
independent review. DOM mute is not a platform audio-session retirement receipt.
WebKit's cross-process audio interruption is a source-backed possible mechanism,
not a confirmed internal cause on Jet. Do not force repeated Play, ignore unknown
Pause, add global audio mixing or weaken source validation to conceal the symptom.

The stronger next design is one atomic **both-native** Watch Two transition:
validate and prepare both captured native candidates paused/disconnected; suspend
and retire both exact Web owners; await both teardown acknowledgements; only then
start the native pair, preserving each paused intent and selected audio owner.
Do not call the single-pane transfer twice. A failed preflight leaves current
viewing unchanged; after transition, never automatically revive only one Web pane.

That is a material behavior/architecture decision: both pictures briefly restart,
and some Web sources never supply a playable validated native candidate. It is
not implemented or physically qualified. Decide the compatibility/fallback
experience before proceeding. The later native media failure also needs exact
item/error-order evidence if it repeats; it is not proof of a Close policy bug.

Primary references: [Apple Web media suspension](https://developer.apple.com/documentation/webkit/wkwebview/setallmediaplaybacksuspended(_:completionhandler:)),
[Apple per-player audio disconnection](https://developer.apple.com/documentation/avfoundation/avplayer/disconnectedfromsystemaudio),
[Apple PiP restoration](https://developer.apple.com/documentation/avkit/avplayerviewcontrollerdelegate/playerviewcontroller(_:restoreuserinterfaceforpictureinpicturestopwithcompletionhandler:)),
[WebKit process audio-session arbitration](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/GPUProcess/media/RemoteAudioSessionProxyManager.cpp#L208-L258).
None promises independent audio-session ownership for arbitrary Web players.

## Workstation and device handoff

Stopped test playback/PiP normally; final Web session closed at 18:52:16.260 UTC.
All sports, empty test query/history, original Light/landscape and unchanged
interests are restored. Sports-sync preference readback is false. FPL and phones
were not opened or changed. Keyboard capture is off and Device Hub is closed.

Removed only the owned reused 1.1 GB build gate, including DerivedData, signed
temporary app, result bundles, logs and temporary preference copies. Free disk
returned from 17 to 18 GiB. Valid source recovery receipts and installed Fotty 156
remain. The owned temporary awake process is stopped; no permanent sleep, lock,
security setting, unrelated cache or user artifact was changed.
