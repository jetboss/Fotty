# Fotty UI design standard

Established 2026-09-19. Scope: design decisions and acceptance, not a new runtime
implementation or a claim that existing screens have passed this standard.

The owner wants every screen to feel intentional and premium, closely aligned
with Apple's UI guidance. Native behavior and Fotty's sports identity both matter.
This complements [the engineering baseline](APPLE-PLATFORM-BASELINE.md); passing
engineering checks alone does not establish visual quality.

## Design direction

- Put the match, team identity and useful action ahead of navigation furniture.
  Each screen needs a clear purpose; do not repeat FPL promotion outside its
  workspace or create extra destinations to justify existing tabs.
- Keep club badges and recognizable sport-specific equipment artwork. Use native
  symbols for standard actions, not as a blanket replacement for the app's identity.
  An absent badge needs an honest fallback, never a guessed team's crest.
- Preserve calm grouped content, restrained emphasis, readable team names and a
  consistent action vocabulary. More cards, glass, gradients, rounded corners,
  empty space or smaller text do not inherently make an interface premium.
- Preserve working light/dark options and the owner's dark-default preference.
  Appearance belongs in a clearly named Settings group. Diagnose contrast and
  hierarchy in each theme independently.
- Hide routine engineering chatter and successful background-refresh messages from
  everyday screens. Keep actionable failures, consequential uncertainty and safety/
  privacy disclosures visible when relevant; shorter copy must remain truthful.
- Honor the approved three-column phone sports composition at normal text sizes.
  Accessibility reflow may use fewer columns; explain and verify that adaptation.
  Related tiles have coherent dimensions. iPad uses available window width
  purposefully, without phone-width gutters or uncontrolled full-width text.
- Keep Watch beside team names at ordinary widths where it fits. Larger text or
  narrow windows can reflow without shrinking names or touch regions. Preserve
  opt-in future reminders and the distinction between scheduled and watchable.
- Feedback begins when Watch is tapped, not after source lookup. Never add an
  overlay or whole-screen gesture that competes with provider/native playback
  controls. UI polish must preserve source switching and PiP ownership.

These are Fotty decisions informed by owner feedback, not universal Apple rules.

## Work sequence

1. Inspect the current implementation and, when available, an exact-build visual.
   State whether evidence is current or historical. Read the relevant Apple HIG
   pages; do not treat an old screenshot or Mac installation as today's iPhone UI.
2. Establish the screen's job and map the primary/secondary actions. Specify
   hierarchy, typography roles, spacing, artwork and native navigation behavior.
3. For a substantial redesign, translate the proposed/approved reference into a
   native screen contract: visible content, placement, phone grid behavior, iPad
   composition, text expansion and interaction states. Identify sample data as
   sample data. Respect discussion/preview-only requests.
4. Reuse existing tokens and shared components, checking all affected consumers.
   Do not mistake a theme-wide font change for review of all secondary screens.
5. Compare the native result with that contract. List deliberate platform or
   accessibility adaptations and unexplained differences. Review an actual
   journey, including return navigation, keyboard and feedback—not just a picture.
6. Record the evidence below and outstanding gaps. Build, installation, visual
   acceptance and TestFlight distribution remain separately authorized gates.

## Visual and interaction acceptance

Use this compact evidence format for a substantive UI batch:

| Surface/state | Reference and intended hierarchy | Build/device/window/appearance/text size | Observation and remaining gap |
| --- | --- | --- | --- |
| Actual changed surface | Approved concept or explicit local specification | Exact evidence identity, or unavailable | Observed difference, intentional adaptation, or untested |

- Cover the changed screen's normal, loading, empty and recovery states where
  relevant. Include long team names, unavailable badge art and mixed sports.
- Check light/dark, large text and comfortable nonoverlapping touch targets.
  Our standard custom touch region is at least 44 × 44 pt, even with smaller art.
- For iPad-affecting work, review wide landscape and narrow window composition,
  navigation continuity and keyboard/focus behavior. Do not fill space merely to
  eliminate whitespace; secondary columns must help the task.
- Verify visible selected/pressed/disabled states and clear action outcomes.
  Preserve useful data qualifiers, such as official vs projected FPL scores.
- Review all changed shared-component consumers, including sheets and tools in
  Home, Matchday, FPL, Settings, Search and Player as applicable.
- If changing motion/rendering/update frequency, retain bounded work and relevant
  measured responsiveness evidence. No invented frame-rate or latency claims.

Acceptance labels: **concept**, **source checked**, **automated checked**,
**native visually inspected**, **physical interaction checked**, **owner accepted**.
Use only labels supported by actual evidence; they are not interchangeable. If a
device is unavailable, keep its acceptance open. No simulators on this workstation.
Never use a stale Mac app as proof of the current mobile build.

## Apple source routing

- Hierarchy/intent: [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles).
- Responsive composition: [Layout](https://developer.apple.com/design/human-interface-guidelines/layout).
- Text and accessibility: [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
- Visual treatment: [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials).
- Interaction: [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).
- Feedback: [Loading](https://developer.apple.com/design/human-interface-guidelines/loading), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

HIG recommendations inform design; deployment availability and mandatory platform
requirements need their own evidence. Liquid Glass is for an appropriate control/
navigation layer, not every match card. Native does not mean removing Fotty's art.

The reusable personal `apple-ui-design` skill supplies the broader process. This
repository document preserves Fotty-specific decisions even without that skill.

## Reference-backed workflow —25October2026

Use [UI-Reference-Workflow.md](design/UI-Reference-Workflow.md) for the active
Apple-kit/HIG, real-product journey and visual-regression workflow. The checked
six-screen contract in `docs/design/fotty25-ui-reference-contract.json` binds the
approved local concepts, focused source/dependencies and retained evidence hashes.
Run `tools/check-ui-design-evidence.mjs` before claiming a substantive handoff is
complete; inspection success is integrity/coherence, never release acceptance.

Current state25October: the [private178 repair receipt](testing/fotty178-nine-fixes-2026-10-25/README.md)
records the nine approved core fixes, fresh normal Jet captures and manual
navigation/source/native-fullscreen/PiP checks. Normal signed Release178 is left
on Jet; phone177 was untouched in this gate. Older177 root/physical captures
remain historical, with original provenance preserved. The refreshed ledger
binds only fresh178 captures to current focused inputs; integrity is not release
acceptance. Physical XCTest ran zero requested cases after automation activation
timed out, so its result is not a device pass. Hosted phone-width/AX layouts do
not prove phone idiom, real Dynamic Type or VoiceOver. Keep exact scenario,
dimensions/insets, appearance, text size and source/capture provenance; preserve
existing pixel baselines. FPL and multi-stream remain unchanged. Reference
access remains official listings/primary documents and public product guides;
Mobbin/Figma listings are not inspected app journeys or design layers. Popularity
does not justify a dependency, paid access, replacement artwork or acceptance.
