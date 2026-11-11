# App-wide UI completion — 19 September 2026

## Contract and boundary

The owner rejected stopping at the initial small interaction-polish pass and
requested completion of the Apple-aligned UI work. This batch applies the
[Fotty UI design standard](../FOTTY-UI-DESIGN-STANDARD.md) across the production
screens and their secondary destinations. It is not a new visual identity,
navigation architecture, playback engine or release.

Preserve badges and equipment art, three phone sport columns at ordinary text
sizes, compact adjacent Watch actions, full useful iPad width, dark default with
working Light/System options, opt-in reminders and truthful data qualifications.
Retain the selected-tab tree lifetime and FPL session context. No new polling,
whole-screen gesture, continuous animation or provider work is introduced.

## Coverage and changes

| Area | Intended hierarchy and changes | Source review |
| --- | --- | --- |
| Shared navigation and controls | Same four destinations; wrapping labels and two-row accessibility dock; immediate tab replacement. Consistent disabled/pressed state, Increase Contrast tokens and opaque Reduce Transparency backing. | Root and independent cross-review. Shared consumers checked. |
| Home and discovery | Keep artwork/grid/Watch placement. Sport selection also has a checkmark. Long event names and headers reflow. More sports, filters, details, loading, empty and scrollable error states remain reachable. | Discovery lane; independent scope/performance review. |
| Matchday | Saved/followed content, reminder rows, opt-in clash hint and empty state retain distinct purposes. MultiView selection is a semantic Button without nested card actions. | Discovery lane. No projection, timing or eligibility changes. |
| Search | One grouped result surface, readable event/channel identities, native retry action and existing dismissal. | Discovery lane. No search/provider changes. |
| FPL main and workspaces | Semantic workspace navigation and adaptive manager header. Coach setup and conversation scroll together, reachable composer, real prompt hit regions, Reduce Motion-aware scrolling. | FPL lane plus independent cross-review. No paid requests or scoring changes. |
| FPL secondary tools | Squad/picker actions, comparisons, standings, price radar, transfer lab/hub, planner, wildcard, journal, live tracker and rivals adapt labels/metrics/actions. Comparison has numeric VoiceOver information; accessible squad rows expose swap selection. | FPL lane. Captain, fixtures and manager-entry surfaces also inspected. Draft/action logic retained. |
| Settings and onboarding | Coherent row feedback, selected states, reflowing follow/league choices, bounded privacy/backup reading widths, visible password requirement, Help heading semantics. | Secondary lane. Native broadcast/Coach-access controls retained. |
| Match Hub and insights | Measured Close safe-area inset, complete team identities, one vertical scroll owner. Semantic statistics/timeline labels and readable large-text lineups. | Secondary lane plus independent cross-review. No match-data changes. |
| Source picker and recovery | Full source labels, selected/pressed semantics, large-text stacking, retry/close/report remain scrollable. Retry label and handler now agree for an active playback error; VoiceOver no longer calls a failed source playing. | Secondary lane. Same source filtering, original index, selection callback and dismissal; no player lifecycle/PiP changes. |

The existing synchronous audio-session warning is a separate engineering item,
not silently fixed as part of appearance work. Actual stream decoding, cloud
Coach correctness and paid-service behavior are not qualified by UI fixtures.

The root previously ignored keyboard safe areas for every tab. FPL now retains
native keyboard avoidance through the same view identity, without observers or
manual height offsets. Other tabs keep their established behavior. This follows
Apple's documented default layout behavior; docked/floating software-keyboard
interaction remains a physical-device acceptance item.

## Verification ledger

Implementation and local build/unit qualification are complete. A private Jet
iPad installation and primary-tab landscape presentation pass is now recorded in
`docs/releases/Fotty-2.0.0-101.md`; broader interaction acceptance remains open.

- Official Xcode 27 (27A266a), explicitly pinned; no simulator.
- One owned build gate/DerivedData reused sequentially. Other project tests
  are allowed to finish before starting the next heavy run.
- Initial full Catalyst run: 584 passed, two opt-in skips, one stale source-comment
  assertion failed. The replacement checks the dock selection implementation.
- Next full run: the same pass/skip counts; one old Coach Button-initializer
  spelling assertion failed after its label became an explicit accessible region.
  The focus-dismiss-before-send requirement remains checked and unchanged.
- Independent cross-review found and closed Coach scrolling/hit-region, numeric
  chart accessibility, swap selection, failed-source retry and modal Close gaps.
- Final corrected full Catalyst gate: **586 passed, zero failures, two opt-in
  skips** (current-provider discovery and reference-HLS soak). The existing
  synchronous audio-session warning remains. Both new dock/contrast checks and
  the source-row render check execute in this passing run.
- Offscreen current component renders inspected: compact Home rows in dark/light,
  narrow normal/two-row accessibility dock, and CS2 selected/retry/available rows
  at narrow normal/stacked sizes. Identity, adjacent normal actions and distinct
  selected/retry symbols are intact. These are layout-branch evidence, not
  physical iOS Dynamic Type or hit testing.
- Added current-build native navigation/capture journey covering both themes,
  Home, Search, Matchday, Settings/Appearance and all FPL workspaces, plus captures
  for existing wide/narrow, saved-Matchday and accessibility journeys.
- **Integrated UI runner blocked, not passed:** unsigned and locally signed
  launches exit before establishing the test connection. The signed bundle's
  strict deep code-signature verification succeeds, but macOS logs explicitly
  report `AppleSystemPolicy: Security policy would not allow process` for the
  runner. Zero UI journeys executed; this is not an observed application crash.
  Security protections were not disabled or bypassed. No old installed Mac app
  was substituted as evidence. System approval or an authorized physical gate
  is required to close this item.
- Unsigned generic **iOS Release compile passes** on official Xcode 27 after all
  application changes. Owner-authorized private build 101 then passed a signed
  device Release, strict app/extension signature and identity checks, in-place
  installation on Jet iPad, a 60-second launch hold and two zero-result Fotty
  crash-log queries. No TestFlight upload followed.
- Original-resolution screenshots from current physical build 101 verify full
  landscape width and coherent Home, Matchday, disconnected FPL and Settings
  layouts. That journey restored Home with the existing data container retained;
  later connected-FPL acceptance intentionally leaves the FPL workspace open.
  Search, detailed FPL/Coach, source/player, theme and large-text
  interactions are not inferred from these screenshots.
- Subsequent acceptance verifies a valid manager ID and current-season
  confirmation in the same retained container. After a full terminate/relaunch,
  the connected FPL Live workspace opens without ID re-entry and a fresh crash
  query remains empty. The numeric ID is not recorded in project documentation.
- Scoped Swift parsing, shell syntax and whitespace checks pass. The reusable
  Catalyst UI gate now includes the new app-wide journey for the next approved
  native run.
- Removed the single **1.4 GiB** owned build gate, including intermediate failed
  result bundles and exported screenshots, after inspection. No related app or
  test-runner process remains. Final available storage: **63 GiB**. No unrelated
  cache, artifact or user data was removed; temporary products are reproducible.

### Remaining physical acceptance

Private build 101 is installed on Jet iPad; no iPhone or TestFlight action has
been taken. The landscape primary-tab presentation gate is complete. Continue on
that exact build for the still-open interactions:

1. Home → Search → Matchday → Settings → FPL and back; the four primary tab
   layouts have screenshot evidence, but real press/selection, Search, intended
   scroll restoration and Light/System appearance still need hands-on evidence.
2. Wide landscape and narrow window, then accessibility text: no clipped controls,
   unreachable content, unexplained side gutters or obscured Match Hub Close.
3. Connected FPL now survives a terminate/relaunch. Coach still needs a multiline
   draft without sending; the docked keyboard must leave
   input/send reachable. Dismiss/rotate/reopen and verify the draft. Repeat with
   accessibility text and, on iPad, a floating keyboard.
4. Accessible squad swap selection, comparison reading, source switch/retry,
   player recovery Close/Report and return navigation. Normal playback/PiP
   ownership is unchanged but remains part of the physical regression check.

Do not call the whole UI goal owner-accepted or fully visually qualified until
these checks have actual evidence.

## Apple grounding

Current Apple [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
and [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
guidance informed this pass, along with the earlier Buttons review. Structured
documentation was used where the public HTML required JavaScript. The custom
dock is retained for existing lifecycle behavior; the accessibility two-row
adaptation is a Fotty decision, not a claim that Apple prescribes this layout.
Keyboard handling follows the current
[ignoresSafeArea documentation](https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:)).

Evidence labels remain separate: source checked, automated checked, native
visually inspected, physical interaction checked and owner accepted. No old
installed Mac app is used as evidence of this build. Physical installation and
TestFlight distribution require separate task-scoped authority.
