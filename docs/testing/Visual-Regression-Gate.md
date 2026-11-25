# Reviewed component visual regression gate

This is a test-only, no-dependency comparison inspired by Point-Free's
[SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing). It extends
Fotty's existing component captures without adding a package to the application
or requiring a simulator. The PNG set is capped at 8 MiB.

## What it protects

Ten deterministic component renders cover Home at phone/iPad/narrow-iPad widths,
light/dark, large text and long team names; source selected/retry/CS/cooling states;
Watch resting/pressed/disabled feedback; and loaded/missing badge presentation.
The loaded fixture is explicitly synthetic artwork bound to a synthetic team and
an `.invalid` URL preseeded in the existing memory cache. It is not evidence of
real club identity. Existing club-identity tests and actual loaded badge inspection
remain necessary: a golden image can preserve a wrong crest if reviewed carelessly.

Home captures use a bounded, test-owned UIKit window and UIHostingController's
`drawHierarchy` path. SwiftUI ImageRenderer cannot render the UIKit-backed native
Menu and instead displays a placeholder; that placeholder is not an acceptable
baseline or evidence of a native UI defect. The other five surfaces retain
ImageRenderer. Capture methods are fingerprinted in the renderer manifest, so a
method change requires explicit inspection and cannot silently pass old pixels.
The temporary host window is released and its previous key window restored.

Clock, scale, disabled animations, environment locale and time zone are pinned.
Apple's read-only Reduce Motion/Transparency settings are preserved and recorded
in the renderer fingerprint, not overridden or changed on the owner's Mac.
The manifest also records the host OS, SDK, Xcode build and current formatter locale.
A renderer change fails rather than silently accepting changed pixels. Comparison
uses normalized sRGB RGBA rather than PNG compression bytes; dimensions must match,
per-channel rounding tolerance is 1/255, differing pixels are limited to 0.01%, and
mean channel difference is limited to 0.02/255. Both limits must pass. Comparator
tests reject changes to dimensions, position, color, opacity and malformed data.

## Capture, review, then compare

The root operator owns the bounded build/output directory and runs Xcode tests
sequentially. Do not use simulators, install an old Mac app, or run another build
alongside the active gate. Register `VisualRegressionTests.swift` in FottyTests.

1. Create a fresh owned directory with `mktemp -d /private/tmp/FottyVisual.XXXXXX`.
   Pass its absolute path to the Catalyst test runner as
   `FOTTY_VISUAL_CANDIDATE_DIR`. If invoking via xcodebuild, explicitly forward the
   variable to the test runner (for example via the temporary xctestrun environment).
   Run only `FottyTests/VisualRegressionTests/testApprovedComponentVisualBaselines`
   using the project's pinned official Xcode and the active bounded DerivedData.
2. Candidate mode intentionally **fails** after capturing the complete set. This
   is not a passing visual check. Inspect `candidates.json` using:

   `node tools/review-visual-baselines.mjs --candidates ABSOLUTE_CANDIDATE_DIR --inspect`

3. Open and inspect every PNG. Check text wrapping, hierarchy, clipping, truthful
   artwork, layout reflow, primary action and selected/pressed/disabled visibility.
   Record intentional platform differences. Then explicitly promote the reviewed
   images with `--reviewer NAME --reviewed` containing all ten comma-separated IDs
   and `--source-receipt` containing the verified source SHA-256. See the tool's
   `--help`. It refuses to overwrite an existing baseline set, rejects symlinks,
   verifies candidate hashes/dimensions and writes the approval manifest last.
4. Run the same test without `FOTTY_VISUAL_CANDIDATE_DIR`. Missing approval, missing
   PNGs, changed hashes, incompatible renderer or visual differences fail. Failure
   attachments show expected and actual images. Do not update an expected image
   merely to make a failure green; investigate and review the intended change.
5. After results/review are retained, remove only the owned candidate directory
   and active gate's temporary build/result output. Preserve approved PNGs.

The source manifest is a review receipt, not a cryptographic guarantee that the
design is correct. Source-only changes outside these component surfaces can retain
the baseline; approved intentional visual changes require another explicit review.

### Reference and source evidence companion

For the approved2.5 core UI use
[the reference workflow](../design/UI-Reference-Workflow.md) and
`tools/check-ui-design-evidence.mjs` alongside this pixel gate. The companion
checks declared source/dependency, concept and retained image hashes and tracks
six screen roots with specific open checks. It cannot capture, approve or replace
baselines, attest compiler inputs, or grant install/release authority. Historical
component studies do not qualify as complete iPhone/iPad screens. The current
pack intentionally fails its strict completion check while175 remains frozen.

The original promoter's source digest is an operator-supplied declaration, not
an independently verified link from an image to a compiled test host. Keep the
pre-build/post-capture inventory and executable receipt in the next authorized
capture workflow. Do not convert this declaration into stronger evidence merely
because it has a valid hash format.

## Scope and physical-device acceptance

These baselines are pinned Catalyst component captures. On native iOS this one
golden test explicitly skips with its scope stated; comparator unit tests still
run. Do not call that skip a successful iPad screenshot comparison.

[ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer)
does not render all native controls. Hosted captures establish static appearance
of their UIKit-backed controls, not complete native journeys. Neither capture
method establishes WebKit/video rendering, system tab-bar/glass layout,
navigation, focus/VoiceOver, touch targets, PiP, audio or motion performance. The
exact private build must still be inspected and exercised on Jet iPad. A screenshot
test is not frame-time or playback-continuity proof, and none of this authorizes
TestFlight distribution.
