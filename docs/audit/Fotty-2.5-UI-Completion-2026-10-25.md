# Fotty2.5 native UI —25October2026 private candidate

## Scope and implementation

Owner approved finishing the actual core iPhone/iPad UI with the reference-backed
workflow, then lifted the hold on **Jet iPad for this UI gate only**. Jelani's
iPhone stays on175. The source-qualification follow-ups remain metadata-only;
this permission does not authorize their physical source tests. No FPL feature,
Watch Two, provider/admission/ranking/recovery policy, Git/cloud publication or
TestFlight change belongs to this pass.

- Home/Matchday headings measure available width and reflow; the duration menu
  adapts rather than squeezing labels. Preserve sport artwork, crests, readable
  meaningful identities, grouped rows and native navigation.
- A real320pt root capture exposed a compressed Watch capsule. The footer now
  reserves natural action width and keeps Saved/time together when stacking.
  True-empty Home shows its existing recovery before Browse, without a dead
  Up Next/See all section. Use neutral **More broadcasts** rather than asserting
  that every provider-listed event is verified live. No match facts changed.
- Search Recent/Clear, Settings destination accessories and details status/title
  use intrinsic reflow. Existing defaults, bindings, keys and destinations stay
  intact. Preserve the explicit Settings heading because its navigation bar is
  hidden, not a duplicate visible title.
- Single-player compact navigation preserves Sources/Details; tablet context
  remains video-first. The single-source picker pins title/Close while count,
  filters, progress and rows share a scrollable viewport. Multi-stream branch,
  selection callbacks and the retained media/fullscreen owner are unchanged.
- Default-preserving model/store injection lets actual roots render against
  isolated in-memory fixtures without normalizing an owner's saved data. No
  production fixture clock, source freshness or catalog admission was weakened.

## Reference and verification chain

[Workflow](../design/UI-Reference-Workflow.md),
[checked ledger](../design/fotty25-ui-reference-contract.json),
[retained captures](../testing/fotty25-ui-2026-10-25/README.md).

Current Apple Layout/Playing Video and public Apple TV interaction guides were
inspected. Official Figma/Sketch **listing**, not kit layers, was inspected;
Mobbin's public landing pages are a lead, not an operated sports-app journey.
SwiftUIX and SnapshotTesting were evaluated without adding a dependency. Later
owner-approved native video-first iPad behavior supersedes the early concept's
fixed sidebar. The local HTML browser open was blocked; no alternate serving or
browser workaround was used.

- Fresh source-built Catalyst broad gate: **392 passed,0 failures/0 skips**.
  After capture-driven Home fixes: affected **108 passed,0 failures/0 skips**.
  After the neutral heading/build177 change: **11 passed,0 failures/0 skips**.
  These are overlapping runs, not511 unique tests. Evidence tools:60 passes.
- Initial render fixtures were correctly rejected because their receipt predated
  configuration. The harness now fetches after configuration and checks exact
  accepted catalog membership/count before and after capture. Initial failed
  images are not retained as loaded-data evidence. An existing PNG-byte equality
  flake now uses the existing normalized pixel comparator without changing its
  tolerances. Original10October golden PNGs are untouched.
- 35 production-root fixed-viewport captures across six profiles plus sheet/empty
  states; nine PNG/JSON pairs retained. Actual roots, not reconstructed mockups,
  but **Catalyst phone-width still has pad idiom**. Host safe areas, SceneStorage
  defaults and glyph/material behavior cannot establish native phone, keyboard,
  VoiceOver or real large-text acceptance. Relative-time fixtures are not a new
  deterministic golden set. The complete player is not fabricated with media.
- 57 focused source/dependency inputs frozen before capture and checked afterward:
  `d411c01a6cf17b9cc07b950ead476eb2c6625964cf7a21841f2ed5f7f5f72a2c`.
  Fresh Catalyst executable:
  `034af6f7111ade6f2439f5763354704584f3d4abf3bd5ab692a873a50095e745`;
  production debug dylib:
  `0b3ea87cb44d2c82739aad792eaf3e98f37719b98884640c704687910df37c2b`;
  unit test executable:
  `90f42cdde7638fc79c23d2b1395c5e94e9d586890d2735b46b5795c341e7e099`.
  These are operator-recorded fresh build/capture declarations, not independent
  compiler attestation or permission to release.

## Private device gate

Official Xcode27.0(27A266a), not the globally selected beta. Signed normal
Release2.0.1(177), app and extension version coherence, deep/strict signature check,
Jet install/readback/launch succeeded. Release executable:
`8fe685a966274b0dd8633d1f0f289aae8fc13ebdd0229eb8bac5be11131136d1`.
The retained physical Home PNG shows real accepted data, native tab material,
actual crests/fallbacks and readable grouped rows on iPadOS27.0.1. It is not a
playback or touch pass. Device Hub's unreliable coordinate input is not treated
as an application defect or interaction success.

The normal-data Home→Search→Settings/Appearance→Matchday→Home XCTest journey
passes on Jet. Search query entry and Done work with the native input accessory;
the full software keyboard was not visible, so do not claim that occlusion gate.
Earlier attempts exposed harness assumptions: a restored Willow query, focus
after native Clear, and duplicate legacy/modern AX wrappers for native floating
tabs. Correct the test's clearing/refocus and first-match queries, not working
production navigation. The final navigation run passes1/0fail/0skip.

The first single-player UI journey passes1/0fail/0skip: Sources open/Close and
Details/Done preserve the selected-source value. Captures show the web delivery
still Connecting/Starting Web Stream; this is **sheet/interaction proof, not
decoded playback**, a90-second source qualification, or native fullscreen/PiP
transition proof. The final bounded source-list bottom/Close check also passes:
the last current choice is hittable while Close remains pinned; dismissal keeps
the selected-source value. Do not sum the initial/repeated player case as two
unique tests.
No current source choice was changed just to obtain a screenshot.

The separate class avoids old FPL/fixture setup, preference toggles, saved-match
changes and multi-stream actions. Existing physical test mode keeps real feeds
and mutes test audio. The signed normal Release177 app was restored, launched
without test arguments/environment and read back as177; the newly installed
test-runner app was absent before this gate and has been removed afterward.
Physical Debug app executable:
`5bb278738f5b627af786a06ab60a11216d045b656c9520bb6403a7f1232b415c`;
its production debug dylib:
`0301ff9c19131c59feae8cf64b4f84e610e0c8ea34656d507a6e173c8fe4a55f`.

Landscape Home/Matchday/Settings navigation passes1/0fail/0skip and actual full
display captures show two-column composition without clipped names or sidebars.
The first app-bounds screenshot incorrectly cropped the rotated scene; it is
not retained. `XCUIScreen.main.screenshot` preserves the full physical framebuffer
and its embedded eXIf TIFF orientation8: raw1640×2360, displayed2360×1640. This
was a capture defect, not justification to alter working production layout.

The separate standalone CatalogEventDetailsView journey passes1/0fail/0skip:
existing More→inline Match details→More details→native full sheet→Close. The
initial test incorrectly assumed every row's first Details action opened a
sheet immediately; the corrected test follows the accepted inline design and
scrolls the existing More details into view. It never saves/reminds or starts
playback. All six core surfaces now have actual native Jet evidence, not only
component studies. Final unique physical journeys: **four passed,0 failures or
skips**; earlier harness failures and repeated cases are disclosed above.
Final UI test source:
`6452793b016c10060503e132caf043166edc341ada0907fde9321afec2d23676`.

Physical phone-idiom, actual accessibility Dynamic Type/VoiceOver, all detents and
resize/performance stress remain separate acceptance checks. A current provider
skip does not prove playback failure or qualification. The ledger intentionally
retains specific open checks and does not claim release acceptance.

## Preservation and workstation

49 FPL source/test hashes, three multi-stream source/test hashes and the scoped
single-media ownership/transport inputs are protected. Source choices are the
owner's actual seven pre-existing enabled choices, not defaults inferred from
old documentation. Manager identity/confirmation are preserved; two derived FPL
caches refreshed normally during launch/one accidental tab entry. Do not claim
all account caches were byte-identical or restore stale derived caches.
Final readback also confirms Appearance, sport interests, recent-search history
and all seven source choices unchanged. A typed transient Search probe is not
submitted to history. Private preference files/identifiers and automatic Xcode
diagnostic bundles stay only in the owned temporary gate and are not exported.

One owned temporary directory/DerivedData gate, sequential builds, no simulator,
and a task-owned keep-awake process. No broad cache deletion or duplicate archive.
The1.50GiB owned gate, all build/results/scratch screenshots/private preference
copies and automatically collected Xcode diagnostics were deleted after the
redacted receipts were retained. Its keep-awake process stopped; both absences
verified. Disk: about13GiB at start,10GiB before cleanup,12GiB afterward. Do not
attribute unrelated whole-Mac movement or delete pre-existing caches to force a
number. Only the small reviewed evidence pack remains in the repository.

Final checks: all declared57 capture inputs, full177 application input list,
49 FPL and the multi/transport guard hashes match. Evidence integrity passes with
six native-screen surfaces; strict completion remains intentionally false for
the explicit phone/accessibility/media/performance gates. The
[redacted verification record](../testing/fotty25-ui-2026-10-25/verification.json)
preserves phase counts, actual four sequential physical results and binary
identities, without device identifiers, private preferences or media URLs.
