# Adaptive iPad layout — private build 89

## Evidence and intent

The owner reported black side gaps on Jet iPad in landscape. A direct device
screenshot confirmed a full-screen app with centred, width-capped content: Home
920 points, Matchday 820, Settings 680, and FPL workspace 960. The landscape
screen is 1180 points wide. The sports grid also formed nine tiles plus a lone
Tennis tile and broke Motorsport across lines. This was an app layout issue,
not iPhone compatibility mode or video aspect-ratio bars.

## Implementation

- MainTabView publishes a column-width environment at the window boundary.
  It changes only when crossing 1000 points; accessibility text sizes force
  single-column content. No orientation lock, device-model check or catalog
  refresh is tied to resizing. Search measures its own sheet width separately.
- Home, full lineup, Search and Matchday remove their narrow content caps.
  Fixture order and actions stay unchanged; wide layouts group up to two
  fixtures in one stable row. Home/full lineup/Search retain their outer lazy
  scroll structure, with no nested scrolling grid or absolute offset tracking.
- Tablet sport tiles have a larger scaled minimum width and balance columns
  across rows. Ten tiles at the owner's landscape width form two rows of five.
  Compact phones retain the approved three-column maximum and overflow policy.
- Settings groups use side-by-side columns at wide sizes. Notifications keeps
  system permission separate from match-update controls; all existing pushed
  destinations and permission side effects remain unchanged.
- FPL presents the existing manager summary beside the active workspace. Its
  stats stack within the summary rail. Setup uses an introduction/form layout.
  AnyLayout changes the arrangement without replacing the controls' state.
  No confirmation, squad, scoring, chat, paid-access or consent rules change.

The adaptation follows Apple's guidance to use actual available width and keep
resizing non-destructive: [Elevate the design of your iPad app](https://developer.apple.com/videos/play/wwdc2025/208/),
[AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout).

## Validation

The final combined Catalyst run passes all 142 tests in BetaUsabilityTests,
HomeDiscoveryTests and FPLTrustTests, with no failures or skips.
The original lazy-row source assertion expected a single-fixture loop; it now
checks the keyed one/two-fixture projection and retains offset/badge/cache guards.
HomeDiscoveryTests contains dedicated breakpoint, balanced-grid and fixture-order
tests, plus landscape light/dark rendering cases; it must be selected explicitly
because it is a separate test class despite sharing BetaUsabilityTests.swift.
The compact-phone renderer caught a 204-point sports grid against the existing
190-point limit. Reducing only compact vertical padding/spacing restored the
limit without shrinking text or artwork. The corrected HomeDiscovery suite's
34 checks pass, including landscape light/dark renders.

The FPL continuity journey exposed a partially clickable workspace-tab label;
adding `contentShape(Rectangle())` to that label fixed the click affordance, and
the full Captain/comparison/tab-return journey passes. A new real wide-window
journey verifies FPL/Settings column positions and selected-tool preservation
after shrinking. Its first resize attempt used a synthesized touch; Catalyst
requires a mouse drag. The mouse-based journey and saved-draft rejection journey
now pass.

Thirteen distinct Catalyst UI checks pass across this candidate's runs: Home
text-clipping/Dynamic Type/hit-regions/full-lineup navigation, Matchday Dynamic
Type, Settings Dynamic Type/notification grouping/Help and feedback navigation,
non-connecting FPL input, FPL workspace Dynamic Type/context continuity/saved
replacement validation and real wide-window resizing. No simulator or physical
UI-test runner was used. UI summaries still carry the previously recorded
generic main-thread runtime warning; this is not a measured performance fix.

Generated football-catalog consistency, five deterministic provider identity
vectors and `git diff --check` pass. The optimized, signed generic-iOS Release
build and strict nested signature checks pass; app and widget both report 89.

## Physical delivery and remaining acceptance

Owner explicitly authorized Jet iPad installation after validation. CoreDevice
confirms 2.0.0 (89) installed on that iPad Air 4; launch and the 30-second process
hold pass. A direct 2360×1640 landscape screenshot confirms full-width Home
content with normal margins, five-plus-five sports tiles, unbroken Motorsport
and American football labels, and two-column match cards with club badges and
side-aligned Watch. No broad empty side gutters remain.

The screenshot also contains the existing truthful football-fixture verification
warning. This UI batch did not change the data authority or hide that warning;
fixture service availability and decoded playback are not qualified here.

Physical review of Matchday, Settings/Notifications, FPL, narrow iPad windows,
light mode and large text remains the owner's acceptance step. Catalyst checks
are supporting evidence, not screenshots of those screens on Jet iPad. FPL
identity confirmation remains the owner's decision. No data reset, consent or
interest changes, device UI-test runner, iPhone install or TestFlight upload.
See `docs/releases/Fotty-2.0.0-89.md` for the delivery record.
The owned temporary directory and every captured screenshot/result bundle were
removed after verification. Free disk space returned to approximately 48 GiB.
