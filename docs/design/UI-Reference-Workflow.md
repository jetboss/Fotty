# Native design reference and evidence workflow

Adopted25October2026 for the approved Fotty2.5 core sports UI. This strengthens
the existing Apple design skill and [product design standard](../FOTTY-UI-DESIGN-STANDARD.md);
it does not replace them, redesign working screens or authorize distribution.
The current [private178 repair receipt](../testing/fotty178-nine-fixes-2026-10-25/README.md)
records the approved nine-fix Jet gate, normal Release178 restoration, fresh
native captures and manual source/fullscreen/PiP checks. Phone177 was untouched;
FPL and Watch Two stay unchanged. Physical XCTest executed zero requested cases
because automation activation timed out; manual evidence is stated separately.
The earlier177 UI pass below is historical, with original provenance retained.

## Reference stack and actual access

| Resource | Use in Fotty | Verified access / boundary25October |
| --- | --- | --- |
| [Apple Design Resources](https://developer.apple.com/design/resources/) | Native control vocabulary, proportions and platform assets. Start with the official iOS/iPadOS kit, then use the corresponding real SwiftUI/UIKit control. | Apple currently lists iOS/iPadOS27 Figma and Sketch kits. The official listing was inspected; the Figma file itself was not opened or downloaded. A kit link is not proof of inspecting its layers. No new design-app installation. |
| [Apple Layout HIG](https://developer.apple.com/design/human-interface-guidelines/layout) | Hierarchy, match grouping, safe areas, actual window space and accessible reflow. | Current official Markdown read. Fotty's three-column phone composition and44pt touch convention remain product choices, not quoted Apple certification rules. |
| [Apple Playing Video HIG](https://developer.apple.com/design/human-interface-guidelines/playing-video) | Native controls, original video aspect, unobscured content and useful supplementary context. | Current official Markdown read. Do not transfer tvOS/visionOS-only recommendations into iPad requirements. No new playback owner or source policy. |
| [Mobbin](https://mobbin.com/) | Find complete discovery→selection→watch→return journeys and edge states. | Public landing/discover pages inspected, but no individual authenticated sports-app flow was inspected. Keep it a reference-library lead until actual screens are accessible. No subscription, sign-in or paid connection. |
| [Apple TV navigation](https://support.apple.com/en-ie/guide/tvapp/atvb5e608b5e/1.0/web/1.0), [discovery](https://support.apple.com/en-ie/guide/tvapp/atvbb35c9fc3/1.0/web/1.0), [playback](https://support.apple.com/en-ie/guide/tvapp/atvb5e386e66/1.0/web/1.0), [PiP](https://support.apple.com/en-ie/guide/tvapp/atvb71d09d11/1.0/web/1.0) | Public first-party journey reference: discover content, distinguish destinations/actions, reveal playback controls and return from PiP. | Guides directly inspected. These are documented interactions, not an independently operated Apple TV session or current phone screenshot. Fotty retains its accepted direct Watch path and video-first tablet layout. |
| [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) | Evaluate a particular component only when an actual native-control gap is demonstrated. | Primary repository reviewed. No current gap justifies adding the library. Before any adoption inspect the exact implementation/license, API availability, accessibility, maintenance and build impact. Stars alone are not evidence of fit. |
| [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing) | Regression discipline: deterministic fixtures, explicit review and comparable render conditions. | Primary repository reviewed. Reuse Fotty's existing bounded native capture/pixel comparator; no duplicate application/test dependency was added. |

These references inform judgment. They are not authority to copy third-party
art, fabricate match facts, hide source limitations or claim App Review approval.

## Working sequence

1. Recover the approved local concept and the later native refinements. Record
   the reference hash, screen job, primary action and a few important invariants.
   User-approved concepts outrank a newly discovered effects library. For iPad,
   video-first/native-fullscreen supersedes the concept's original fixed sidebar.
2. Inspect the actual corresponding product journey where access permits. Record
   the app/version/device/steps actually seen. A homepage, marketing image,
   document, component study and operated app are different evidence kinds.
3. Extend existing semantic type, materials, artwork and shared components only
   for a concrete mismatch. Preserve badges, sport equipment, normal-size phone
   sports grid, dark default/light option and native navigation/media controls.
4. Compare equivalent content state, window width **including outer insets**,
   appearance and text size. Record deliberate native/AX adaptations separately
   from unexplained differences. Never shrink meaningful names to imitate CSS.
5. Verify visual integrity and source freshness, then perform the actual journey
   on a separately authorized exact-build device. Touch, keyboard, focus,
   VoiceOver, safe areas, fullscreen/PiP and performance require their own checks.

## Checked core-screen ledger

[fotty25-ui-reference-contract.json](fotty25-ui-reference-contract.json) maps all
six core surfaces to production roots, approved references, invariants and open
checks. It fingerprints the declared focused source/dependencies, approved local
HTML references and retained evidence. Refresh the ledger against the final
reviewed source/capture pack; do not reuse an earlier aggregate after edits.
The [25 October pack](../testing/fotty25-ui-2026-10-25/README.md) contains fresh
production-root static captures. Older 24 October component studies remain
historical/unbound; a new inventory cannot retroactively bind them to a build.

Run the read-only checker from the repo root:

```sh
node tools/check-ui-design-evidence.mjs \
  --contract docs/design/fotty25-ui-reference-contract.json \
  --reference-root /Users/jelani/.codex/visualizations/2026/08/22/01a02a1b-2e70-7270-a309-e701db249c90
```

Omit `--reference-root` on a machine without the approved local artifacts;
reference integrity then remains explicitly pending. The tool performs no
network requests, image generation, builds, approval, installation or release.
It verifies bounded regular-file paths, hashes, image dimensions, reference IDs
and schema. Inspection success means **evidence integrity**, not UI acceptance.
Use `--require-complete` for a completion check; the present pack must fail that
check while native-screen evidence and interaction checks remain open.

The five 24 October studies are `historical-unbound` component assemblies:

- Home: title, spotlight/upcoming rows and sport grid, without the complete
  production scope/Search/native navigation or expanded live sections.
- Settings: illustrative component groups; a study-only Viewing window row is
  not proof that a production setting exists.
- Single player: identity and source-row states, not video/chrome/fullscreen.

The 25 October pass instead hosts the actual Home, Matchday, Search, Settings,
match-details and single-player source-sheet roots. Nine PNGs with JSON sidecars
are retained from 35 captures across viewport widths and appearances. The source
sheet has no mounted media owner; it is not complete player/playback evidence.
Synthetic initials establish missing-art layout, not real club-crest fidelity.
Phone-width Catalyst still has iPad idiom; its glyphs, safe areas and accessibility
traits do not establish native phone or physical Dynamic Type acceptance.

## Capture provenance and baseline discipline

For each authorized native capture:

- Freeze the reviewed source/dependency and reference hashes **before** building;
  verify them unchanged after capture. Include shared Theme/Components, artwork
  and the actual render helper, not only the changed root views. New dependencies
  require extending the declared list; it is a focused pack, not a whole-app seal.
- Record the exact build/OS/platform/renderer and actual test-host executable
  SHA256 with each pack. The checker validates declarations and freshness; it is
  not compiler attestation and cannot prove a binary came from claimed source.
  The operator must verify the fresh build/capture chain independently.
- Use a fresh owned empty output directory and exclusive artifact names. Pin
  clock/locale/time zone/animations; record genuine system accessibility traits.
  `Fotty25DesignRenderTests` now hosts actual production roots with isolated
  catalog/store inputs, fixed viewports and JSON metadata. Its accepted fixture
  receipt must match before capture. Production controls retain a current clock;
  these static captures are not deterministic golden baselines. Record actual
  host idiom and distinguish requested text-size traits from native glyph scaling.
- Retain each image's hash, dimensions, scenario, full-screen/component kind,
  appearance and text size. Add comparison findings and deliberate adaptations.
  A verified capture remains separate from reviewer/owner acceptance.
- Preserve the original10October baseline set. Its existing promoter requires
  explicit image review and refuses overwriting; its64hex source-receipt field
  is an operator declaration, not a checked image→build→source proof. Use this
  ledger alongside it. Do not substitute study PNGs or invent a green pixel run.

See [Visual-Regression-Gate.md](../testing/Visual-Regression-Gate.md) for the
existing pixel comparator/record→review→compare process. A proposed rebaseline
needs deliberate review. Today's fresh captures were reviewed as evidence, not
promoted to baselines; the original accepted pixel set remains untouched.

## Resource and completion boundary

No simulators, large UI-kit downloads, concurrent builds, subscription or new
framework dependency. Reuse one bounded build-output directory and clean owned
temporary artifacts after the active gate. Jet's UI-only owner-device permission
does not authorize phone installation, FPL/multi-stream changes, publication or
TestFlight. Keep remaining checks specific rather than describing an incomplete
pack as “premium,” “fully tested” or release-ready.

## Historical reference/tooling verification

- The initial 25 October checker/baseline-validator gate passed 60 tests with no
  failures or skips. Syntax and whitespace checks passed, and tiny test fixtures
  were cleaned. This was the reference/tooling gate before today's UI edits, not
  a new result for the final application source.
- That initial inspection verified its then-current source/reference inventory
  and five historical studies. Strict completion correctly failed while native
  checks remained open; missing local concepts stayed pending. The checker never
  grants release/install authority. Consult the refreshed ledger and receipt for
  current hashes rather than carrying this earlier inventory forward.
- The 24 October 328 focused tests and unsigned Release pass remain historical
  results. The initial 25 October tooling pass also verified all 10 original
  baseline PNG hashes without replacing them or claiming a new pixel comparison.

## Historical177 UI pass —25 October 2026

- Production repairs cover Home hierarchy, action width/reflow, true-empty recovery
  and the neutral More broadcasts heading; Matchday intrinsic reflow; Search,
  Settings and match-details adaptation; and single-player sheet layout. Existing
  source/playback policy, preference defaults, FPL and multi-stream behavior remain
  outside this visual-change scope.
- Successive fresh-built Catalyst runs passed 392 broad tests, 108 affected tests
  and 11 latest tests. These runs overlap; do not sum them as unique coverage.
- Thirty-five actual production-root static captures were reviewed across widths
  and appearances; [nine PNG/JSON pairs are retained](../testing/fotty25-ui-2026-10-25/README.md).
  The pack documents isolated fixtures, accepted-catalog freshness and actual host
  limitations. It is source-bound review evidence, not a new golden baseline or
  physical iPhone/iPad acceptance.
- Signed normal Release177 is restored on Jet after four passing physical UI
  journeys: normal navigation, source-sheet scroll/player Details, landscape
  composition and standalone catalog details. All six surfaces have actual Jet
  captures. Whole-display landscape capture fixes the test renderer's app-bounds
  cropping; it is not a production layout fix. The source sheet's connecting web
  delivery is not decoded-media/fullscreen/PiP proof. See the
  [candidate receipt](../audit/Fotty-2.5-UI-Completion-2026-10-25.md).
- Native phone verification, VoiceOver, real large text and remaining interaction
  checks stay open. At that earlier gate the iPhone remained175; it later received177 under separate authority. Reference access is unchanged from
  the table above: official listings/primary guidance and public product guides,
  not inspected Figma layers or an authenticated Mobbin sports-app flow.
