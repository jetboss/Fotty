# Score808 direct-site investigation

Date: 2026-09-04. Scope: diagnosis, not an implemented or deployed fix.

## Result

The owner's supplied public Score808 page contains a working Video.js player.
The in-app browser decoded 852 × 480 video with readyState 4 and advancing
playhead samples. Football footage was visually observed. This disproves the
earlier blanket claim that Score808 playback necessarily uses the failing
`embed.st` transport. It does not prove physical iPad playback or independently
verify a live broadcast's provenance from its scoreboard.

The source is hosted on CacheFly, not `embed.st`. A normal-TLS bare HEAD request
returned HTTP 403 while the actual webpage played. Preserve ordinary page
context; do not assume that extracting a media URL makes native playback work.
No certificate bypass, ad-gate bypass, media download or native-player test was
performed in this investigation. The page also displayed advertising overlays.

Public page inspected:
https://www.score808live.tv/score808-live-football-scores-real-time-match-updates-results/

## Actual discovery contract observed

The page embeds a public Elfsight calendar. Its loader publishes the unauthenticated
`https://core.service.elfsight.com/p/boot/` endpoint with widget ID `w` and public
page URL `page` query parameters. The widget ID can be read from the page's
`elfsight-app-<UUID>` markup; it is not a credential.

The response path is `data.widgets[widgetID].data.settings.events`. Check both
top-level and widget status before consuming it. The inspected response has
288 manually maintained events, including historical rows hidden by the UI.

The visible Ipswich Town vs Liverpool event publishes September 5, 00:00–02:00
in `Asia/Karachi`, equivalent to September 4, 19:00–21:00 UTC / 15:00–17:00
Trinidad. Its visible, nonrecurring event's primary Watch Now action points to
the owner's exact page. Following that UI action independently returned the
same page. Other simultaneous matches have other targets; one uses another
website. Historical Liverpool events reuse this same article URL.

This is provider programming metadata, not an official fixture authority or a
documented permanent API. Never use URL reuse alone to establish match identity.

## Build 57 audit corrections

- `Score808LateDiscoveryPolicy.inferredHotelDescriptor` copies an `admin` ID
  into a `hotel` descriptor. It contains no independently verified provider
  mapping. A large HTML response is not proof of Score808 or match identity.
- `readPrefix(limit:8192, minimumBytes:256)` stops at 256 bytes. The validator
  admits ordinary HTML of at least 32 bytes; the claimed 1–2 KB stub rejection
  is not implemented. Unavailable text after that prefix can be missed.
- Descriptor scans and validations are sequential, with Hotel last, inside a
  20-second global budget. A timeout can prevent reaching it and discard earlier
  diagnostic failures. The generic no-playable-stream message is not proof that
  every provider was actually checked.
- Existing tests cover the inferred-ID/window policy, not real-site discovery,
  stub rejection, slow-provider fairness or physical successful playback.

## Required implementation and acceptance

1. Remove the unverified cross-provider donor inference. Retain bounded explicit
   Watch refresh near kickoff, without persisting negative discovery indefinitely.
2. Add separate direct-site discovery using the actual published calendar:
   bounded size/time, explicit timezone conversion, visible/nonrecurring entries,
   exact normalized team pair plus kickoff, one unambiguous fresh match, and
   allowlisted HTTPS Watch destinations. Do not execute remote code or follow
   arbitrary cross-host targets. Fail closed on changed schema.
3. Discover the selected page's current player, not a hardcoded rolling media
   URL. Preserve provider context and existing navigation/security protections.
   Do not claim native/PiP compatibility until exercised.
4. Give provider work a fair bounded budget and preserve actionable evidence;
   a resolver timeout must be reported as a timeout. Distinguish page reachability
   from actual decoded playback.
5. Add deterministic fixtures for stale/reused pages, simultaneous events,
   timezone rollover, wrong teams, hidden/recurring/ambiguous events, unsupported
   destinations, malformed/oversized config, unavailable HTML beyond 256 bytes
   and cancellation/timeout. Then run simulator-free gates and private Jet iPad
   startup, pause/resume, ad-overlay and background/PiP checks.

No application source, version, installed app, TestFlight, service or Git
publication changed in this investigation. Jet iPad remains build 57 and
TestFlight remains build 55. No Xcode artifacts or downloaded media were created.
