# Live TV and adaptive playback — researched direction

30October2026. Owner asked to research the unknown GitHub TV scraper mentioned by
his friend and bandwidth-aware playback. None of the repositories below is known
to be the friend's project. No new feed was enabled, no scraper executed, and no
new stream/EPG supplier was qualified by this research. FPL/multi/phone remain out.

## Useful primary projects

- iptv-org/iptv: https://github.com/iptv-org/iptv . Unlicense; channel-link
  aggregation and identifiers, not a video host or proof of sports availability.
- iptv-org/epg: https://github.com/iptv-org/epg . Unlicense; actual maintained
  guide grabbers, XMLTV/channel mappings and source-specific time parsing.
- Guovin/iptv-api: https://github.com/Guovin/iptv-api . AGPLv3; server candidate
  discovery, validation, measured ranking and M3U/API/EPG output. Study its
  qualification architecture; it is not a drop-in native player or licensed supply.
- 4gray/iptvnator: https://github.com/4gray/iptvnator . MIT; explicit persisted EPG
  mapping, real rendition selection, buffer/engine statistics and channel UX.
- tvheadend/tvheadend: https://github.com/tvheadend/tvheadend . GPLv3; useful
  programme→channel→multiple delivery-service separation.
- jellyfin/Swiftfin: https://github.com/jellyfin/Swiftfin . MPL2; explicit device/
  codec compatibility. Its server-transcoding capabilities are not Fotty features.
- kineticman/FastChannels: https://github.com/kineticman/FastChannels . Reuse
  license not established. Stable channel identity and fresh-on-tune resolution
  are useful references. Its described highest-bandwidth-variant redirection is
  unsuitable to copy into native Auto: it can remove the adaptive master ladder.

The selected IPTVnator quality implementation changes the next rendition instead
of flushing the current buffer:
https://github.com/4gray/iptvnator/blob/cecdbb177aad8bec66a9e8f90f9fbfb11bc67e2e/libs/ui/playback/src/lib/web-video-support/web-video-hls-controls.ts
Its measured statistics implementation is separate:
https://github.com/4gray/iptvnator/blob/cecdbb177aad8bec66a9e8f90f9fbfb11bc67e2e/libs/ui/playback/src/lib/player-controls/web-video-stream-stats.ts

## Concrete Fox guide lead

iptv-org/epg maps Fox Cricket Australia/English site_id14 to FoxCricket.au@SD:
https://github.com/iptv-org/epg/blob/master/sites/foxsports.com.au/foxsports.com.au.channels.xml
The paired config reads the publisher's date-bounded programme API, matches exact
channelId and retains titles, descriptions, startTime/endTime. It invokes dayjs.utc:
https://github.com/iptv-org/epg/blob/master/sites/foxsports.com.au/foxsports.com.au.config.js
The site index marks this Fox Sports adapter green and the separate Foxtel adapter
broken. This is a reviewed research candidate; actual publisher timestamp/offset,
DST, regional stream identity, freshness and programme correctness still need
bounded verification. It establishes no playable Fox feed. No dedicated Willow
site adapter was found in the inspected site index; other mappings remain unknown.

## What Fotty already does

Native AVPlayer performs HLS adaptation when the supplied asset has real multiple
renditions. SinglePlaybackQualityPolicy inspects actual asset variants, shows Data
Saver only with at least two declared video bitrate tiers and sets a genuine lower
bitrate/resolution cap. Auto restores initial preferences. It changes the same
item, without a seek or player replacement, and resets ownership on source change.
The direct native path requests12seconds of forward buffering and enables
AVPlayer's stall-minimization waiting. The guarded relay preserves master playlist
lines and rewrites URI references; no global highest-variant selection was found.
A fixed-quality feed cannot become adaptive by adding an Auto label.

Apple references:
https://developer.apple.com/streaming/
https://developer.apple.com/documentation/http-live-streaming/creating-a-multivariant-playlist
https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredpeakbitrate
https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent

## Recommended next acceptance milestone — discussion, not implementation

1. Finish activation/current-source acceptance of the shared registry; keep each
   channel distinct from its programme and from its concrete delivery alternatives.
2. Add finite per-attempt evidence from existing relay/player observations: real
   rendition/indicated vs observed bitrate, first decoded frame, stall count/time,
   playlist sequence/unchanged duration and meaningful request failure stages.
   No URLs, tokens or extra background media polling. Unknown remains unknown.
3. Qualify a small direct-TV shortlist against exact channel/region and current
   programme, then90second decoded hold and normal controls. Prefer actually
   validated multivariant HLS and independent healthy alternatives. A successful
   HTTP request, repository popularity or a broadcaster logo is insufficient.
4. Review the Fox EPG adapter's actual publisher contract before adding its bounded
   metadata collection to the existing cloud registry. A generic Fox/Willow name
   never grants a fixture broadcast. Keep Willow programme mapping unresolved
   until its original interval timezone/station identity is established.
5. Prove Auto/Saver under controlled strong→weak→recovered bandwidth on Jet, with
   actual renditions and rebuffer timing. Then tune source-specific startup/buffer
   tradeoffs from measurements. Avoid global buffer changes or replacement-player
   source switches sold as seamless ABR. No zero-gap promise for upstream outage.

The191 Willow live hold failed twice after decoded progress. Its first-12888
record is consistent with a nonadvancing playlist, not proof of insufficient
bandwidth. Apple engineering reference:
https://developer.apple.com/forums/thread/783255 . The next measurement must
separate an unchanged upstream window from actual bandwidth starvation; simply
raising a buffer target would not repair a permanently frozen live playlist.
