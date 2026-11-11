# Fotty2.5 UI candidate —25October2026

These nine PNGs are fresh **production-root static captures**, not rebuilt
illustrations and not physical phone screenshots. The actual Home, Matchday,
Search, Settings, details and source-sheet views are hosted in a newly compiled
Catalyst test app at fixed viewport sizes. The source sheet has no mounted media
owner. Synthetic teams exercise long names and honest missing-art fallbacks;
they are never inserted into an owner's catalog.

Each JSON sidecar records viewport, appearance, declared text-size traits, safe
areas, fixture receipt and actual host idiom. Phone-width Catalyst still reports
the iPad idiom, and its glyph/material behavior is not iOS typography proof.
SceneStorage outside the SwiftUI App lifecycle returns default values; these
captures therefore do not establish restored filters, typed queries or keyboard
behavior. Accessibility reflow branches are exercised, not physical VoiceOver
or full-size Dynamic Type certification.

The initial fixture receipt predated the test cache check and was correctly
rejected. The harness now obtains a fresh receipt after cache configuration and
rejects captures if its exact accepted catalog changes. Failed initial captures
are not retained as loaded-state evidence. The true-empty captures use an
explicit accepted empty snapshot, not a failed lookup.

The loaded narrow Home capture exposed an unreadable, compressed Watch capsule.
The repaired footer reserves natural action width and reflows Saved/time as one
group. The explicit empty Home capture verifies recovery before Browse sports,
without an empty Up Next/See all destination. No production freshness, ranking,
source admission or playback rule was changed to make these fixtures pass.

The checked [six-screen ledger](../../design/fotty25-ui-reference-contract.json)
binds retained captures to57 focused inputs and the fresh host identity. The
private build/device receipt records the application and test-bundle hashes
separately. This is a focused provenance declaration, not compiler attestation,
owner approval or permission to distribute.

These are review evidence, not newly approved golden baselines. The original
10October pixel baselines remain untouched. Source/capture checks, physical
interaction and owner acceptance remain separate stages.

`jet177-home-portrait-dark.png` is different: an actual physical Jet iPad
screenshot of the signed normal Release177 app with real current catalog data.
The ledger records its separate iPadOS/app-executable identity. It shows Home,
native tabs and real/fallback badges; an image alone is not a successful touch,
source-selection, decoded-media or phone-idiom test. See the
[private UI receipt](../../audit/Fotty-2.5-UI-Completion-2026-10-25.md) for the
device journey and restoration outcome.

The `jet177-search`, `jet177-settings`, `jet177-matchday` and
`jet177-player-sources`/`jet177-player-details` PNGs are actual focused XCTest
screens on Jet, not Catalyst renderings. Their ledger identity is the signed
Debug177 application, real feeds, and the pre-existing muted physical test mode.
The normal signed Release177 application is restored after testing. Search shows
the native input accessory, not a full software keyboard; the player is still
Connecting in these captures, not a decoded-media qualification. Opening/closing
and source-list reachability are separate recorded physical assertions.

The three `*-landscape-display.png` images use **XCUIScreen.main.screenshot**.
Their raw raster is1640×2360 with embedded eXIf TIFF orientation8, displaying as
2360×1640 landscape. The earlier app-bounds capture cropped the already rotated
scene; those invalid landscape images are not retained. The full-display images
show Home's live/upcoming columns, Matchday's two-column grid and Settings' two
columns. No screenshot was edited or resized to conceal an app-layout mismatch.

`jet177-catalog-details.png` is the separate real CatalogEventDetailsView, reached
through the accepted inline More details action, not the player's context sheet.
It uses the same full-display physical177 Debug provenance/landscape orientation.
Its normal medium sheet is scrollable; offscreen save/source controls are not
claimed visible or exercised merely because XCTest can find them in the tree.
