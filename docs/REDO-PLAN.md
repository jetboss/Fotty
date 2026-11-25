# Fotty playback redo — Steps 4–7 plan

> **Superseded 2026-11-09.** The owner chose to shrink `LivePlayerViewModel` in place instead of migrating to the parallel `Fotty/Engine` path. See [PLAYER-SHRINK-PLAN.md](PLAYER-SHRINK-PLAN.md) for the plan and the reasons. This document is kept as history.


Status: bug fixes (worker freshness + native cold-start "Check streams") are already
deployed. This document plans the remaining *structural* work: replace the
registry-gated, `LivePlayerViewModel`-centric playback path with the clean
engine, migrate the UI onto it, and delete the superseded modules.

This is a deliberate, multi-week, test-protected migration — each slice ships
green and is verified against the full Catalyst gate plus a physical-device
check before the next slice.

---

## 1. The transport surface (what Step 4 must abstract)

`StreamTransport` is the single seam behind which every real player lives. Its
input is the **rich** `StreamSession` (`Core/Models/MediaModels.swift`), not the
engine's minimal `SourceCandidate`:

- `playableURL`, `requiredHeaders`, `streamType`, `providerName`, `qualityLabel`
- `expiryTime`, `leaseID`, `canRefresh` — media lease facts
- `requiresGuardedRelay` — forces the `LocalStreamProxy` header relay
- `nativeOriginProfile` / `nativePlaylistProfile` — reviewed 8443/playlist profiles
- `mediaProbeEvidence`, `declaredPlaybackEndpoint`, `eventBinding`

The transport responsibilities currently spread across
`LivePlayerViewModel.swift` (4,685 lines) are:

1. **Native AVPlayer** path — item construction, decoded-frame observation, KVO.
2. **WebKit embed** path — `LiveWebEmbedPlayerView.swift`, attempt-keyed documents.
3. **Header relay** — `LocalStreamProxy.swift` + `LocalStreamProxyPolicy.swift`.
4. **Audio session** — `MediaAudioSessionOwner.swift` (serialized activation).
5. **PiP / fullscreen** — `NativeFullscreenPlayback.swift`, system PiP control.
6. **Recovery** — `LivePlaybackPolicy.swift` (network/startup/stall retry order).

**Step 4 does NOT move these bodies immediately.** It first freezes their exact
behavior behind the protocol, then ports them one at a time.

## 2. Engine ↔ app type bridge

The engine works in minimal types; the app works in rich types. The bridge:

| Engine | App | Bridge note |
|---|---|---|
| `MatchRequest` | `StreamPlaybackRequest` | thin, lossless in the adapter layer |
| `SourceCandidate` | `StreamSession` | adapter builds `StreamSession` from `SourceCandidate` + transport facts |
| `MatchReceipt` | `StreamEventBinding` | matcher verdict → binding |
| `StreamTransport` | AVPlayer/WebKit/proxy | `StreamSession` in, decoded playback out |

`StreamTransport` is therefore **revised** to consume `StreamSession`
(`prepare(_: StreamSession)`, `play(_:)`, `pause()`, `stop()`), not
`SourceCandidate`. The engine stays transport-agnostic.

## 3. Step 4 — transport port (sub-steps, each green)

1. **Revise `StreamTransport`** to `StreamSession`-based, add a `TransportKind`
   (`.native`, `.web`) and a typed `TransportFailure`. *(small, now)*
2. **Native transport** — extract AVPlayer item construction, decoded-frame
   observation and KVO into a `NativeStreamTransport: StreamTransport`. Port the
   existing `NativePlaybackPreparation` / `NativePlaybackEvidence` logic.
   *(highest risk — do with the full playback test suite)*
3. **Web transport** — extract the attempt-keyed WKWebView embed into
   `WebEmbedTransport: StreamTransport`. *(medium)*
4. **Relay transport** — wrap `LocalStreamProxy` behind the same seam for
   `requiresGuardedRelay`/profile sessions. *(medium)*
5. **Audio/PiP/recovery** — move `MediaAudioSessionOwner`, PiP control and
   `LivePlaybackPolicy`'s recovery order into the engine's state transitions.
   *(high — do last, with physical audio/PiP checks)*

## 4. Step 6 — UI migration (one screen at a time)

1. **Player** — swap `LivePlayerView`/`ViewingSessionCoordinator` to drive
   `PlaybackEngine` instead of `LivePlayerViewModel`. Keep the existing views as
   fallback until device-verified.
2. **Home/Matchday** — route the "Check streams" / Watch actions through the
   engine's `SourceResolver` (direct, no gate) once it can produce the same
   ranked `StreamSession`s.
3. **Delete `LivePlayerViewModel`** only after the device passes: live match →
   correct picture → forced failure → recovery → close/reopen → Watch.

## 5. Step 7 — deletion (bounded, in dependency order)

Only after Step 6 is device-verified, delete in this order:
1. `BroadcastRegistry`-as-gate usage in the Watch path (keep the Worker + native
   `BroadcastRegistryClient` for metadata only).
2. Scheduler debt / checkpoint repayment helpers that are now unused.
3. 4 of 6 optional source families (keep CS + the single most reliable second),
   after confirming no resolver references them.

## 6. Sequencing, risks, gates

- **Order:** revise seam → native transport → web → relay → audio/PiP/recovery →
  player UI → discovery UI → deletions.
- **Risks:** wrong-match playback (guarded by `MatchIdentity.select`),
  audio-session races (guarded by `MediaAudioSessionOwner`), WebKit ownership
  (attempt-keyed documents), relay/transport exceptions (never broadened).
- **Every slice gate:** `check_native_source_membership.py` + focused tests +
  full `ios-ci.sh` (simulator-free) + `tools/check_native_source_membership.py`.
- **Physical gate (player migration only):** Jet iPad — live → picture → forced
  fail → recovery → close/reopen → Watch.

---

## First slice (starting now)

Revise `StreamTransport` to be `StreamSession`-based and add `TransportKind` +
`TransportFailure`, with focused tests. This unblocks every later transport
extraction without touching the live player.

## Progress log (as of the last working session)

Completed and green:
- Seam: `StreamTransport` → `StreamSession`-based + `TransportKind` + `TransportFailure`.
- Seam: `@MainActor`-bound (`PlaybackEngine` is `@MainActor final class`).
- `NativeStreamTransport` (first slice) wraps `prepareDelivery` + `makeItem` +
  minimal play/pause/stop; compiles cleanly.

Next slice — §3.2 native AVPlayer KVO/decoded-frame migration. Extract from
`LivePlayerViewModel.swift` into `NativeStreamTransport`, preserving the
source/request/intent epoch fences (`loadRequestID`, `sourceID`, `requestID`,
`nativeWatchTwoIntentID`):

| Concern | Source location |
|---|---|
| Item failure observers (`failedToPlayToEndTime`, `playbackStalled`, `newErrorLogEntry`) | `configureItemFailureObservers` L2849 |
| Status KVO (`item.observe(\.status)`) | L2907 |
| Observer teardown | `removeItemFailureObservers` L2916 |
| Decoded-frame output + `decodedFrameSample` | `AVPlayerItemVideoOutput` L3838, L2833 |
| Native resume progress | `observeSingleNativeResumeProgress` L2738 |
| `lastObservedPlaybackStage = .decoded` bookkeeping | L2603, L2764, L3401 |
| Playback start/control (`play`/`pause`, `timeControlStatus`) | `startPlaybackIfNeeded` L965 |
| Teardown (proxy discard, observer removal, player nil) | throughout |
