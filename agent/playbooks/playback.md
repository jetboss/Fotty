# Playback Playbook

Use this when touching player startup, AVPlayer, WKWebView embeds, VOD playback, stream selection, autoplay, or timeout behavior.

## Read First

- `docs/notebooklm/Project-Memory.md`
- `docs/notebooklm/Decisions-Log.md`
- `docs/notebooklm/Risks.md`
- `Fotty/Features/Player/LivePlayerView.swift`
- `Fotty/Features/Player/LivePlayerViewModel.swift`
- `Fotty/Features/Player/VideoPlayerView.swift`
- `Fotty/Core/Internal/HybridStreamProvider.swift`
- `Fotty/Core/Internal/WebViewRenderer.swift`

## Standing Decisions

- Surface observation must not delay or cancel provider taps. Use passive DOM click observation in the web frame tree, not a UIKit gesture recognizer above WKWebView. Prevent popup navigation without swallowing legitimate provider button handlers.
- Keep actual decoded-video transport state scoped to document/source/attempt. A deliberate pause cannot be undone by delayed stall/recovery/native-handoff work; a transient interruption must still recover. Execute monitor JavaScript in tests, not only parse its syntax.
- Video/player chrome remains dark when the browsing UI is Light or System. Dismissing the player restores the selected app appearance.

- Playback must show immediate feedback, but a web embed gets 20 seconds to prove decoded startup and one controlled same-source reload before failover. Explicit provider rejection skips that grace.
- Avoid cascading timeouts; the one web reload is the bounded exception and must stay keyed to the current source/attempt.
- Broadcast source switching belongs below the player in the available sources section.
- First successful stream resolution should cancel competing resolution work.
- WebView automation must quiesce after real playback starts.
- Once decoded playback starts, network-path and scene transitions must preserve the exact source attempt. Retry that item/source before considering failover.
- Delayed failures must match both source ID and attempt ID; source ID alone is insufficient after a reload.
- Catalog choices represent distinct broadcasts: collapse a channel's HD/SD pair to HD, preserve provider-family diversity, and never mix synthesized zero-variant rows into an event with real variants.
- Block provider popup windows, top-level click-throughs, `embed.st/ad.html`, and known nuisance hosts without removing generic overlays or player controls.
- In the standard web player, provider controls are canonical. Never place a parent tap gesture above the WKWebView, add a duplicate unmute button, remove its mute prompt, or continuously force mute/volume state. App-controlled web mute synchronization is limited to MultiView focus and explicitly muted diagnostics.

## Common Failure Points

- Web embed autoplay loops that keep tapping after playback begins.
- Source validation taking long enough that the player feels dead.
- AVPlayer readiness waiting too late to request playback.
- UI offering multiple places to switch streams.
- Raw provider URLs or internals leaking into user-facing failure states.
- Treating a loaded embed shell, viewer count, or catalog variant as proof of decoded playback.

## Verification

- Cold open a live match and confirm player feedback appears immediately.
- Confirm a successful source starts without extra taps.
- Confirm a slow first load retries the same source once before any source-index change.
- Confirm the source picker has distinct language/channel rows rather than adjacent HD/SD duplicates or fabricated empty-family variants.
- Inspect WebKit pages/frames after play: popup count should remain zero, ad frames should be absent, and video/player-control elements must remain present.
- On a decoding physical-device stream, independently exercise the provider's play, pause, seek/fullscreen when available, and `Tap to unmute`. Confirm Fotty does not consume the tap or immediately undo the resulting state.
- Confirm failure returns the user to broadcast sources calmly.
- Switch between regular, web embed, and P2P sources where available.
- Check that pause/play does not loop by itself after WebView handoff.
- Run the focused Catalyst policy suite without a simulator. For an intentional device or Catalyst reference-HLS check, run only `PlaybackPolicyTests/testReferenceHLSMaintainsOneAttemptDuringSoak` with `OTHER_SWIFT_FLAGS='$(inherited) -DFOTTY_PLAYBACK_SOAK'`; the diagnostic player must remain muted. Catalyst runs for 120 seconds and should show advancing playback on every sample with unchanged source/attempt/item and zero failovers.
- DEBUG Settings → Stream pipeline checks exposes the same production-path two-minute muted soak for manual use on Mac Catalyst. It exercises required-header proxying, AVPlayer readiness, watchdog continuity, and failover accounting; it does not exercise a third-party WebKit embed.
- When a live provider event is available, follow the reference soak with a muted Catalyst Watch Live hold. Record the provider/source label, starting and ending broadcast clocks, any focus/background transition, and whether loading, error, or source-replacement UI appeared. Treat that as time-scoped provider evidence, never a general uptime guarantee.

## Brain Prompts

```bash
./tools/ask-brain.sh "What playback decisions affect this change?"
./tools/ask-brain.sh "What are the current Fotty playback risks and verification checks?"
```
