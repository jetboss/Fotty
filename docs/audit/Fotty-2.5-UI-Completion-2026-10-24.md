# Fotty2.5 core UI implementation —24October2026

## Scope and evidence

The owner approved finishing the native iPhone/iPad UI against the accepted
full-experience concept, keeping both installed175 builds for25October feedback.
This is the core sports UI implementation, not a new feature/data/backend batch,
a global skill replacement, a signed candidate or a TestFlight release. FPL and
Watch Two remain unchanged. No phone/iPad interaction, install or setting change.

Reference: the approved local `fotty-full-experience.html` concept (Now & next,
planning, watch, source sheet, minimized browsing and continuity), plus the Inline
variant of `fotty-next-level-ui.html`. Both live in the existing22August Codex
visualizations folder. Illustrative scores, match events and EPG are not production
facts or authority to add a data feed. Source implementation preserves the later
approved video-first iPad/native-fullscreen refinement over the concept's original
persistent companion sidebar.

The Apple design skill drove explicit composition and accessibility contracts,
shared-consumer inspection and native component rendering rather than a global
theme/font replacement. Apple Layout, Materials, Typography and official design
resources were retrieved24October. Glass remains native navigation/control
chrome; the existing team-badge identity and all sport equipment art are retained.

## Implemented core presentation

| Surface | Completed implementation | Deliberate adaptation / preservation |
| --- | --- | --- |
|Home|Now & next with visible scope; spotlight, Also live, joined match sections with separators; coherent centered sport artwork; full names wrap rather than middle-truncate. Wide overview gives the live column1.55 times the upcoming/sports column.|Only bounded featured/upcoming arrays enter the overview. Expanded/later rows remain stable flattened lazy children, without nested scrolling. Existing ranking/interest/status and source policies are untouched. Very narrow widths reflow; accessibility sports use one column.|
|Matchday|Quiet heading/Browse; bounded native mode control, menu at accessibility sizes; attached reason footers, grouped personal matches; visible More for existing actions.|Personal plan remains distinct from Home. Changed-start/no-longer-listed evidence stays visible. Native controls manage the same mode/window, saves and reminders.|
|Search|Grouped recent/interests suggestions, real sport-art grid and useful wide columns; empty columns omitted; quieter result spacing and semantic identity type.|Native search, query/history, keyboard dismissal, results ownership and inline Details remain. No new fuzzy playback admission or search request.|
|Settings|Calm16pt groups, semantic labels, measured label/value reflow with RTL placement, compact appearance group, consistent source icons and long-description layout.|Every key/default/action remains. FPL notification shortcut is unchanged. Existing forms/lists and bounded help destinations retained. Follow-more-teams action is native and bounded480pt on iPad.|
|Match details|Badge-led identity on a calm surface, full wrapping, readable720pt explanatory column. Existing Watch/countdown moves directly after identity, before long provenance/help and secondary Save.|No new action or consent path. Conflict/watchability/reminder/check-streams owners remain. Medium-sheet geometry cannot guarantee everything is above the fold; the primary action now has priority.|
|Single player|Compact phone navigation, one badge-led full identity below video, primary Sources and quieter secondary controls. Tablet uses separated slim toolbar/dock around the unchanged fitted video.|Native fullscreen calls the existing player. Media surface/slot/item ownership and recovery are not rewritten. No permanent empty tablet sidebar or overlay competing with provider controls.|
|Source sheet|Single-only joined choice list, selected checkmark, restrained emphasis, semantic type, readable640pt list and aligned header/filter, AX stacking.|Original source indexes and callbacks; opening/filtering does not restart media. Failed/selected/checking/empty states remain distinct. Legacy/multi consumers default to prior styling.|
|Navigation, continuity and loading|Existing native TabView/accessory, Handoff, sports-widget routes and sport-aware Inline feedback retained.|No duplicate custom dock, fabricated live programme, new widget capability or cloud/notification behavior. Unchanged functional components are not counted as newly delivered features.|

No global Theme, player model, coordinator, source adapter, fixture service or
image pipeline changes were made in this UI pass.52 protected FPL/multi-stream
source/test hashes match the start of the pass. Single-only presentation opt-ins
also preserve the passive card/picker consumers used by multi-stream.

## Local checks and render review

- Fresh Debug Catalyst source build and328 selected tests pass,0 failures/skips.
  This is the newly built test host, not the old installed Mac app. Includes16 new
  layout/render checks, existing browsing/Settings/source contracts and retained
  single-owner/native-fullscreen tests. No live-source campaign was run.
- Final unsigned generic iOS Release compile passes for this same source. No
  archive, signing, provisioning, install or upload. Version stays2.0.1(175) in
  working source; these changes are not in either installed175 binary.
-21 native static component compositions rendered and inspected:320/393pt phone,
  650pt narrow and1180pt wide windows; light/dark; accessibility reflow; long
  identities, missing badges, selected/failed/ordinary source rows. Captures use
  current production components through UIHostingController.drawHierarchy.
- The first run found the compact sports group206pt high with a wrapped sport
  name, exceeding the existing190pt limit. Reduced gaps/padding, not text/art/hit
  size; rerun passes the unchanged190pt assertion. Grouping assertions were
  deliberately updated from the superseded transparent-row design; ownership
  and separator checks remain.
- Review also caught a normal320pt phone falling to two sport columns because
  the test had omitted its32pt combined outer insets. Compact tile minimum is
  now88pt; the regression includes288pt actual inner width. No font or artwork
  shrinking, and the explicit accessibility one-column adaptation is retained.
- Synthetic names, sources and badges are clearly test fixtures, never seeded
  into an owner's catalog. Source URIs use `.invalid` and are not played.
- These captures are component/layout studies, NOT full native iPhone/iPad
  screenshots. Host typography/control/material behavior differs from iOS.
  Accessibility branches are exercised, not a physical Dynamic Type/VoiceOver
  certification. Fixture assemblages do not replace whole-screen/keyboard tests.
- Original10October pixel baselines are left intact, not silently regenerated
  or reported passing after an intentional design change. Their reviewed
  replacement remains part of the signed candidate's visual acceptance gate.

Physical whole-screen comparison, actual scroll/press/menu/keyboard behavior,
safe areas, native fullscreen/PiP and device performance remain explicitly
unverified for this source snapshot while175 is frozen. This does not reopen
source engineering work or authorize an install. No arbitrary premium score or
claim that all future content combinations are visually perfect.

## Better design references, not a framework shopping list

The owner asked about products/GitHub resources that could improve design quality.
Reviewed24October:

- [Apple Design Resources](https://developer.apple.com/design/resources/): official
  iOS/iPadOS UI kits in Figma/Sketch and platform assets. Use native proportions,
  not web-component geometry or an imitation glass layer.
- [Mobbin](https://mobbin.com/): shipped-screen and journey references. Useful for
  studying discovery-to-watch, sheets, empty states and navigation continuity.
- [Refero](https://refero.design/): another reference-library lead; its public
  landing page alone is not evidence that a particular sports journey was inspected.
- [MovieSwiftUI](https://github.com/Dimillian/MovieSwiftUI): inspectable media
  browsing example, but older architecture/design is not a current Apple mandate.
- [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX): targeted missing-control lead,
  not a reason to replace Fotty's native theme/navigation.
- [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing): reference
  for regression discipline, not a visual-design generator. Fotty already has a
  bounded native capture/pixel gate, so no dependency was adopted to duplicate it.

Recommended workflow: approved real-product references + official native kits →
small screen contracts → source implementation → inspect actual renders and
interactions. No new paid subscription, account, plugin, dependency, copied
proprietary art or personal/global skill installation was made.

Compile/resource cleanup details: [local UI receipt](../testing/Fotty-2.5-ui-local-gate-2026-10-24.json).
Five small [native component studies](../testing/fotty25-ui-2026-10-24/README.md)
are retained for inspection; build products/results/other captures are temporary.
The owned1.1GiB build/result/log gate and temporary awake helper were removed;
about12GiB free afterward. No pre-existing caches or artifacts were deleted.
