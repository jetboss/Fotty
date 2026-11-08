# Playback Playbook

Use this when touching player startup, AVPlayer, WKWebView embeds, stream selection, autoplay, PiP, or timeout behavior.

## Read First

- `docs/notebooklm/Project-Memory.md`
- `docs/notebooklm/Decisions-Log.md`
- `docs/notebooklm/Risks.md`
- `Fotty/Features/Player/LivePlayerView.swift`
- `Fotty/Features/Player/LivePlayerViewModel.swift`
- `Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift`
- `Fotty/Core/Internal/HybridStreamProvider.swift`
- `Fotty/Core/Internal/WebViewRenderer.swift`

## Standing Decisions

- Surface observation must not delay or cancel provider taps. Use passive DOM click observation in the web frame tree, not a UIKit gesture recognizer above WKWebView. Prevent popup navigation without swallowing legitimate provider button handlers.
- Keep actual decoded-video transport state scoped to document/source/attempt. A deliberate pause cannot be undone by delayed stall/recovery/native-handoff work; a transient interruption must still recover. Execute monitor JavaScript in tests, not only parse its syntax.
- Each explicit new web source/retry uses an attempt-keyed WebView. Preserve that
  key for pause, audio, rotation and scene changes. Retire iframe-owned media and
  out-of-window presentations on teardown; stale PiP/navigation callbacks cannot
  acquire the new attempt. A provider listing or elapsed kickoff is not live-play
  evidence; neutral listed availability and confirmed LIVE must remain distinct.
- Video/player chrome remains dark when the browsing UI is Light or System. Dismissing the player restores the selected app appearance.

- Playback must show immediate feedback, but a web embed gets 20 seconds to prove decoded startup and one controlled same-source reload before failover. Explicit provider rejection skips that grace.
- Avoid cascading timeouts; the one web reload is the bounded exception and must stay keyed to the current source/attempt.
- Broadcast source switching belongs below the player in the available sources section.
- Collect useful independent resolution lanes within one owned bounded attempt;
  one success must not erase concrete alternatives already available. Cancel
  remaining work at the owning attempt's deadline, replacement or dismissal.
- The optional CS lane is playback coverage only, disabled by default. Require
  exact Fotty sport, both teams and kickoff before requesting streams; accept
  its reviewed same-origin HTTPS routes or only the owner-approved167 exact
  sktech/dai-fancode.pages.dev HTTPS443 HLS-path/public-header contract. Reject
  other cross-origin/P2P deliveries and unsafe nested wrapper targets, including
  HTTP2122. Keep existing TLS/public-address/redirect/header checks and opaque
  source labels; keep upstream names out of normal-user errors and selectors.
  See release167; playlist admission is not decoded playback.
- AS football203 also supports the reviewed Roxie contract: an advertised civil
  date and exact team pair may associate with one fresh accepted official fixture
  for that UTC date. Official metadata owns kickoff, competition and status;
  never convert its undocumented “site time” clock or infer LIVE. Recheck latest
  official status and fresh same-ID meta before streams. Optional channel-count
  text may differ between catalog and meta. The exact admin2.formaturamaxi.com.br
  HTTPS443 single-leaf HLS contract is reviewed alongside papacito; this is not
  permission for arbitrary origins/paths/headers. Typed notWebReady is a browser
  hint, not a native-HLS veto. Physical qualification is recorded separately in
  testing/fotty203-as-football-2026-10-31/.
- Main playback and MultiView share typed endpoint routing. Never infer a web
  wrapper's media type from a nested query URL or send an explicit HLS endpoint
  to WebKit as recovery. Preserve source attribution through native handoff.
- Native validation must recheck source/attempt/cancellation after awaiting.
  UIView input assignment cannot publish playback state synchronously; queued
  commands and observations must stop when the native surface is dismantled.
- Preserve completed identity-conflict evidence even when a sibling endpoint
  reaches its deadline. Hidden conflict rows remain part of resolver admission.
- Keep generic content/startup/stall/expired-URL failures local to the attempted
  match. Do not suppress a provider family or host across unrelated events
  without typed fixture-independent outage evidence. Positive history may rank
  options; existing failed-source exclusion bounds retries within an attempt.
- WebView automation must quiesce after real playback starts.
- Once decoded playback starts, network-path and scene transitions must preserve the exact source attempt. Retry that item/source before considering failover.
- Delayed failures must match both source ID and attempt ID; source ID alone is insufficient after a reload.
- Preserve concrete HD/SD, language, full URL/query and required-header delivery
  alternatives with fair provider-family coverage. A shared label is not a
  duplicate identity. Never mix invented zero-variant rows into real variants.
- The native relay accepts only its session capability and registered routes
  derived from selected media. Preserve loopback binding, credential domain/path
  and origin scope, redirect validation and resource limits. Do not restore an
  arbitrary `?url=` proxy or flatten shared WebKit cookies into a Cookie header.
- Public-address DNS preflight is not address pinning. Do not describe it as
  complete DNS-rebinding protection or weaken transport checks for compatibility.
- Block provider popup windows, top-level click-throughs, `embed.st/ad.html`, and known nuisance hosts without removing generic overlays or player controls.
- In the standard web player, provider controls are canonical. Never place a parent tap gesture above the WKWebView, add a duplicate unmute button, remove its mute prompt, or continuously force mute/volume state. App-controlled web mute synchronization is limited to MultiView focus and explicitly muted diagnostics.
- In MultiView, keep source choice and audio focus as explicit 44-point controls.
  Do not add a whole-panel tap gesture above a web player or show Fotty Play/Pause
  for a web source that only the provider can control. Native panels may retain
  their real AVPlayer transport button. Positive source health may rank candidates,
  but absence of prior success must not hide an otherwise eligible manual pair.

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
- Confirm the source picker preserves actual language/quality/delivery choices
  without exact duplicates or fabricated empty-family variants.
- Inspect WebKit pages/frames after play: popup count should remain zero, ad frames should be absent, and video/player-control elements must remain present.
- On a decoding physical-device stream, independently exercise the provider's play, pause, seek/fullscreen when available, and `Tap to unmute`. Confirm Fotty does not consume the tap or immediately undo the resulting state.
- In Two-match view, verify selection order 1/2 survives into panel order, both
  provider surfaces retain their controls and each source menu remains usable.
  Originally native/native panes switch selected audio without rebuilding either
  feed or undoing Pause. For Web/Web, the owner accepted a brief deliberate
  both-native restart: prepare both compatible candidates paused/disconnected,
  retire both exact Web owners before either Play, then start the pair preserving
  intent/focus. Failed preflight leaves both original feeds unchanged. Verify an
  actual positive conversion separately; a safe refusal is not that pass. Never
  sequentially transfer panes, force Play or revive only one Web sibling.
- Confirm failure returns the user to broadcast sources calmly.
- Exercise both the normal provider-page path and a verified native AVPlayer handoff when available.
- With native PiP active, open another app for at least 60 seconds, then lock/unlock and confirm the same stream keeps advancing without duplicate audio.
- Check that pause/play does not loop by itself after WebView handoff.
- Run the focused Catalyst policy suite without a simulator. For an intentional device or Catalyst reference-HLS check, run only `PlaybackPolicyTests/testReferenceHLSMaintainsOneAttemptDuringSoak` with `OTHER_SWIFT_FLAGS='$(inherited) -DFOTTY_PLAYBACK_SOAK'`; the diagnostic player must remain muted. Catalyst runs for 120 seconds and should show advancing playback on every sample with unchanged source/attempt/item and zero failovers.
- The old DEBUG Stream pipeline checks screen is retired. Use the focused test
  or an explicitly authorized normal-app physical check; do not reintroduce it.
- When a live provider event is available, follow the reference soak with a muted Catalyst Watch Live hold. Record the provider/source label, starting and ending broadcast clocks, any focus/background transition, and whether loading, error, or source-replacement UI appeared. Treat that as time-scoped provider evidence, never a general uptime guarantee.

## Brain Prompts

```bash
./tools/ask-brain.sh "What playback decisions affect this change?"
./tools/ask-brain.sh "What are the current Fotty playback risks and verification checks?"
```
