# Focused TV startup/retry repair

Owner requests Sky Sports Football repair, an explanation/fix for channels needing retries and Jet iPad acceptance. Phone/FPL/multi/TestFlight excluded. Preserve existing channel choices, no source security exceptions or cloud/Git deployment.

## Confirmed evidence

209 ordinary Sky Football Watch reproduced two startup timeouts after media readiness. The live Apple HLS asset exposes audio but no video track, despite a running clock/full buffer. A control TNT2 route decodes through the actual relay. Sky fails both direct and through relay. Current six-segment source window contains HEVC in MPEG-TS; Apple HLS requires HEVC in fragmented MP4. Earlier H.264 TS sample decodes as a local file, which does not qualify the later live HEVC contract. The compatible alternate was independently found through the already enabled CS NETWORKS station catalog, then verified through fresh same-ID metadata. No unsupported format-conversion or inferred alternative channel is enabled.

Actual fetched manifests preserve tags and overlapping URI mapping in the bounded sample. Prior URI-change diagnostics remain historical error evidence, not a confirmed current proxy-rewrite cause. Alternate advertised HTTPS Sky Football candidates returned403; HTTP candidates were not fetched/upgraded. No expired token was decoded, modified or renewed artificially.

## Focused app changes

1. Extend the existing once-only, exact selected-source/fresh-descriptor recovery to reviewed TV when a current repeated relay observation proves a nonadvancing live playlist. Keep pause/background/owner/decoded/budget/expiry restrictions.
2. Ignore late native fatal callbacks for an already terminal single-player attempt; manual Retry/reselection remains the explicit new-attempt path. Multi behavior unchanged.
3. Add the existing CS NETWORKS exact UK Sky Sports Football catalog/meta/stream route to this station's ordinary discovery. Preserve CS opt-in, attribution, same-ID metadata, ambiguity and all destination/header restrictions. It is a television station, not a fabricated fixture or programme assignment.
4. Give the verified compatible Sky CS alternate the cold tie preference while keeping TV11 selectable and preserving actual positive startup/continuity evidence. Prevent another TV station's shared-CDN success from making this station proven: single-player positive TV history is station/host scoped, while legacy ranking for other contexts is unchanged.
5. Run focused regressions, signed compilation and ordinary affected-channel checks on free Jet. Preserve first failures and retries independently. The first 210 candidate exposed the cold-selection gap; its failed TV11 Watch and successful manually selected CS1 hold are recorded separately. A focused correction requires a final consolidated install and one-tap recheck.

Sources: [Apple HLS authoring](https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html), HEVC/fMP4 requirement1.5; [RFC8216](https://www.rfc-editor.org/rfc/rfc8216.html), playlist reload continuity. Native diagnostic and media receipts are separate from physical acceptance.
