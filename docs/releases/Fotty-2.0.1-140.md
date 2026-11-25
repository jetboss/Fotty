# Fotty 2.0.1 (140) private score and CS verification

Jet iPad received build140 on 11 October2026. This remains a private score/CS
gate, not a TestFlight release. Phones125 and shared121 are unchanged.

## Change and provenance

Build140 retains139's full-name official score/freshness repair and finite
native HLS diagnostics. It adds the verified exact
`p16-common-sign.tiktokcdn.com` `.image` segment predicate to the runtime CS
playlist profile. Signed query bytes, captured headers and the original first
admitted delivery remain immutable. No destination permission, TLS/DNS/redirect
relaxation, media-byte rewriting or timeout change occurs.

- Pre-build capture: `backups/release-source/2.0.1-140-score-cs-image-segments`.
- Commit: `1477a54d5b3deb1f97308916eab0704a6d542b91`.
- Source SHA256: `b853f124b2fc33258b33b381961fcccd9260ad2a250580052312425807507816`.
- Bundle SHA256: `0294366d942b924f5d8456a6730493d8d88edcff13e88127daf265895181498c`.
- Signed executable SHA256: `3a8d186f1d6ac04ecbef323a35cedc2deac30cc3be0eafc068c8698bc497a08e`.

The frozen1075-file comparison, strict deep signature, app/extension140 and
independent installed-app readback pass. Full simulator-free CI passes1170
units:1168 passes, two existing optional skips, zero failures. This includes
the exact-host negative controls and headerless adapter/native-profile route.

## Actual physical result, not label-based attribution

The required CS6 native PiP test passes with one test and zero skips/failures.
It checks Sources, native inline video/progress, a visible SpringBoard Home
surface for60 seconds, unchanged player-item/attempt identity, ordinary PiP
Stop, inline video/progress and Close. Media time advances69.76594288 seconds
across the Home interval. The selected attempt records no source failure.

However, the actual local `source_key` is
`cs_fada09d27ba43d60a99ce614` (DaddyLive), not the repaired streamedpk format.
CS numbering is response-local and the iPad response differs from the earlier
Mac metadata response. This pass qualifies only that actual DaddyLive attempt;
it is not continuity proof for streamedpk/timstreams. Muted XCTest also does
not qualify audible playback or continuously decoded background frames.

Fresh Liverpool–Manchester City metadata at15:35:47UTC contains38 options:
ten initial DaddyLive variants, then streamedpk and timstreams. The old adapter
caps the admitted list at six before representing upstream groups, so those
alternatives can disappear. This confirmed cap defect is repaired separately
in141, followed by tests explicitly attributed to their actual source keys.

The actual140 native Home screenshot/AX tree at15:32UTC renders Liverpool FC
versus Manchester City FC with0–0 and LIVE0'. A fresh official receipt reports
the same live pair0–0; Palace–Forest3–1 is provisionally finished and must not
be presented as a current live match. See139 for the original display-key
mismatch and source facts. No fixture, preferences or backend data is altered.
