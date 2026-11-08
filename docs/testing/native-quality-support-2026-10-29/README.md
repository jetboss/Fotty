# Native single-player quality — 29 October 2026

Source-only implementation within the approved remaining Fotty2.5 batch.
Phone, devices, FPL, multi-stream operations, backend and TestFlight are excluded.

## Screen contract

The existing single-player Viewing options menu exposes **Quality** only when
the current native HLS asset declares distinct video bandwidth tiers. The native
picker offers Auto and Data Saver with a selected checkmark. Fixed/unknown/Web
deliveries and metadata failures do not expose a fabricated control. No new
screen, persistent setting, sync payload, audio/subtitle choice or Best label is
added. Native menu semantics handle Dynamic Type and selected-state accessibility.

Auto preserves the current item's original bitrate/resolution preferences. Data
Saver prefers a declared lower tier: the highest below the source's/current
ceiling and at or below1.5Mbps, or the lowest declared tier. That target is Fotty's
product policy, not an Apple requirement. It never promises a hard data cap,
specific decoded resolution or decoder support for every advertised variant.

## Ownership and behavior

- Inspect the selected AVURLAsset through AVFoundation after its existing decoded
  callback; do not probe a different media URL or delay playback startup.
- Require the current single owner, player, item, source UUID and attempt UUID
  when accepting metadata and applying either preference. A5s observation deadline
  drops the optional control; it never cancels loading on the shared media asset.
- Change only `preferredPeakBitRate` and `preferredMaximumResolution` on that
  same item. Do not reload, replace, seek, issue Play/Pause, resolve sources,
  change native fullscreen/PiP, or adjust buffers/startup behavior.
- Item/source/attempt retirement cancels inspection and restores original item
  preferences. Context departure restores them synchronously before retained
  media can enter paired use. A new item starts in Auto; no user-data migration
  or global data-policy change occurs.

## Evidence used

Apple's current primary documentation was read on29October2026:
[bandwidth preference](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredpeakbitrate),
[HLS resolution preference](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredmaximumresolution),
[asset variants](https://developer.apple.com/documentation/avfoundation/avurlasset/variants),
and [native menus](https://developer.apple.com/design/human-interface-guidelines/menus).
The public site's Markdown endpoints and the installed iOS SDK headers agree:
the two item limits are preferences; resolution applies to HLS; modern variant
inspection uses asynchronous `load(.variants)`. No playback API established a
distinct forced-highest mode, so Best is omitted rather than duplicate Auto.

The pinned [Shaka REA receipt](../rea/established-players-2026-10-28/shaka-delivery-presentation.json)
informs same-media presentation ownership. Its static Web evidence is not proof
of native AVPlayer behavior or the current Fotty stream's quality.

## Verification boundary

Fourteen focused tests are supplied in `SinglePlaybackQualityTests.swift` for
variant policy, unsupported metadata, defaults/restoration, exact current-owner
guards, stale async results, paused/fullscreen/PiP state and paired-mode isolation.
Their AVURLAssets reference `/dev/null`; variant metadata is injected. They make
no media/network or physical-playback claim.

Swift syntax parsing and whitespace checks pass. Root owns target membership,
compilation/XCTest execution and the authorised Jet iPad interaction gate. No
passing device, data-consumption or visual result is claimed by this receipt.

## Single-player support access

The same existing Viewing options menu now exposes **Report a problem** while
the single stream is Playing, paused, recovering or showing a portrait error.
It opens the existing feedback sheet; no shared/multi error overlay is changed.
The ephemeral seed includes a bounded match title, reviewed public provider
label/option number, typed Native/Web state and a validated observed stage.
Raw errors, media URLs, headers, credentials and transport UUIDs are excluded.
An old unfinished draft remains authoritative through the existing seed policy.
Copy/Share remains explicit, and opening a sheet never sends a report.

Seven additional context tests cover neutral Playing state, error redaction,
untrusted names/labels, existing-draft preservation, paused native/fullscreen
ownership, Web command identity and exclusion of paired/retired owners. This is
source/lifecycle coverage, not physical sheet/focus/keyboard acceptance.

## Matchday navigation

A native Jump to menu reuses only Full Matchday's visible heading identities and
complete titles: current Live/Broadcast listed/Next up sections and nonempty date
groups. It is absent from the Time window mode and from a single-section plan.
Selection scrolls the existing ScrollViewReader; it does not filter, reload,
change a date, widen a horizon or mutate a bookmark/reminder. Existing heading
adaptation remains in use. Five source tests cover nonempty scope, pinned reminder
exclusion, stable compact/wide IDs, DST boundaries and invalid/duplicate targets.

## Cricket interval presentation

The owner's [current ICC receipt](../fotty25-remaining-2026-10-29/icc-context-live-contract.json)
has three fixtures with an enclosing live status, but two explicitly say Stumps
and one In play. Home previously labelled/counts all three LIVE and ordered the
older Test first. A presentation-only helper now uses the fresh, team-bound
CricketMatchContext phase: Stumps and other explicit intervals keep their own
labels, do not contribute to the actively-live count, and rank below current
in-play content. No resumption date/time is inferred.

Stale/invalid present context cannot supply a fresh LIVE badge. Missing legacy
context retains its existing accepted fixture behavior. Fixture status, identity,
Item.phase/isOnNow, source availability, playback timing and pairing logic stay
unchanged. The legacy multi-select candidate order uses its explicit old rank;
normal Home's cache never stores that fallback ordering. Ten focused source tests
cover interval labels/counts, current-vs-Stumps ordering, legacy order, context
freshness/validation and unchanged fixture/source/timing facts. Native rendering
and the Jump to interaction remain root's physical acceptance gate.
