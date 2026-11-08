# Stremio → Fotty — 29 October 2026

Read-only study of the current publicly served Web app, prior retained Apple
artifact evidence and the official Apple2.1 announcement. No add-on/service was
installed, no preference/library item was saved, no stream was played and no Fotty
source, device or release was changed. FPL and multi-stream are excluded.

## Exact artifact and actual browsing evidence

The current public HTML advertises a Web build path `f0222603bb8119d8a63958ad8acfd025de973f2e`.
That string is an observed asset namespace, not a verified Git commit or Apple app
version. Its `scripts/main.js` is 10,270,860 bytes, SHA-256
`1ae93a363d2fc81746d90a61231accf3b1849b724350223683841b3325e20469`.
The first acquisition stopped at the 10MB boundary and was not analysed. A fresh
HEAD established the size; the complete asset was then fetched once under an
11MB bound. No source map, worker, addon, media, tracker or authentication bundle
was fetched for local analysis.

An existing Acorn tokenizer selected the exact brace-bounded factory body for
streams component5332 without running its code. The 8,298 bytes are unmodified;
UTF-8 offsets and hashes are in [provenance](stremio-fragment-provenance.json).
The enclosing factory's parameters/import owners are outside the selected block,
so standalone-block analysis does not establish bound module/runtime equivalence.

REA parsed 2,319 AST nodes, zero failures. Application coverage is complete within
that selected block; semantic coverage remains unknown with 554 external/dynamic
unknowns. It retains 1,748 data-flow, 163 closure and 122 call-flow relations as
static candidates. Parent Evidence
`ev_73587f80ab6ca23e5956c137e1959ed6d2bebc28d591c89416197a605ce7ec75`;
[canonical summary](rea-focused-summary.json).

Normal browser observation covered Board, the public-domain The Kid metadata page
and its existing source-list label. The service-not-available prompt was dismissed
with Later, and a promotion was closed; neither installation nor persistent
Don't show again was chosen. The metadata page exposes description, related
attributes and an advertised1080p source. This is not resolution/decoding proof.
No source, torrent, Trailer, Library, profile or install action was selected.

## What the deployed streams component actually does

- It counts Loading resources separately from Ready resources.
- Ready results are grouped by add-on transport identity; the selected group is
  retained if it still exists, otherwise the view returns to All.
- It renders usable list entries and a separate still-loading indication, rather
  than requiring every provider to finish first.
- Selection resets that list's scroll position; the iOS branch requests smooth
  scrolling. The UI code alone does not establish native focus, rendering speed
  or reduced-motion behavior for that Web branch.
- No configured resources and all-Err resources have separate branches. Its
  zero-visible-stream branch renders placeholders. For a valid Ready-but-empty
  result this branch alone does not distinguish finished-empty from still-loading.
  That is a conditional source-level pattern to avoid, not an exercised production
  defect or proof of the deployed core's emitted state in every case.

For Fotty, the positive lesson is incremental independent outcomes with stable
selection. The negative lesson is to explicitly finish the empty state and avoid
turning a persistent placeholder into an apparent ongoing search. Fotty already
has partial discovery and typed source-state work; qualify and refine it instead
of claiming this whole architecture is absent.

## Whole-experience comparison

| Journey | Useful lesson | Fotty adaptation |
| --- | --- | --- |
| Browse | A coherent Board/Discover/details/Library hierarchy and recognisable metadata/actions. | Retain Home/Matchday/Search with distinct purposes; do not add another tab solely to imitate Stremio. |
| Choose a source | Render available results while remaining groups load; keep selected identity coherent. | Already implemented in part. Verify late/error/empty transitions, selection continuity and useful existing metadata. |
| Understand the event | Metadata and actions are grouped before choosing a delivery. | Sports identity must include current teams/squads/date/competition. Film/episode fallbacks are unsuitable for fixtures. |
| Use phone/iPad | The Apple2.1 announcement documents adaptive/native menus, inline Discover previews and task-grouped Settings. | Much is already built in Fotty. Improve current layout consistency and preview fidelity, not another player replacement. |
| Watch | Actual Web service-availability is explicit. Prior published player package analysis has scoped capability/ownership findings. | Keep native controls, same-session ownership and guarded exact source matching; a Web package does not prove native PiP. |
| Return and plan | Library/Calendar are visible; Apple2.1 documents preserving library/navigation state. | Matchday exists. The genuinely new opportunity is a local last-still-live return after cold launch; no stale stream URL/history sync by default. |
| Recover/accessibility | Apple2.1 release notes explicitly address loading/readiness, stale callbacks, errors and accessibility. | Treat these as design/test cases, not proof that Stremio never fails or that a library swap fixes provider faults. |

## Version and evidence limits

The [official Apple2.1 announcement](https://blog.stremio.com/stremio-tech-update-86-stremio-update-for-macos-and-ios/)
is dated22October. It documents Calendar, inline Discover previews, task-grouped
Settings, native menus, adaptive controls, meaningful loading/errors, Dynamic Type
and Reduce Motion work. This pass did not inspect the2.1 native binary or execute
those native flows. Their availability here is documented, not physically tested.

The [24October2.0.7 Apple inventory](../../../testing/rea/stremio-2.0.7-2026-10-24/README.md)
is retained historical evidence of actual Mach-O/import/bundle composition. It is
not2.1 behavior. The [28October study](../../Fotty-Established-Apps-Discovery-REA-2026-10-28.md)
separately covers a published player package and official core source, with its
own hashes/limits; it is not today's deployed Web core version.

Do not reproduce a movie-details split pane as a permanently small sports player.
Do not add arbitrary add-on installation, external player dependence, permissive
origin rules, generic-channel fixture inference, unsupported DVR or a new decoder
based on the brand. No current live PL/UCL/cricket stream, speed, audible audio,
native fullscreen/PiP or all-provider reliability qualification follows here.
