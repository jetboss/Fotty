# Fotty 2.0.0 (52) - private CPL channel-options candidate

Date: 2026-09-03. Status: **installed only on Jelani's iPhone, then immediately superseded by private build 53; not uploaded**.
Shared internal TestFlight remains 2.0.0 (51).

## Scope

Build 52 corrects the CPL broadcast dead end without inventing channel
programme data. Exact team-and-kickoff sources remain the preferred Watch path.
When a current CPL fixture has no exact active source, Home, the full schedule
and Search show `Channel options` from two minutes before kickoff through eight
hours afterward. The sheet contains only recognized Fox Cricket and Willow
Cricket catalog rows with active supported sources and says their current
programme is not confirmed. Choosing one opens that channel through the existing
single playback owner; Fotty does not attach it to the fixture or switch to it
automatically.

## Device and evidence

- Target: Jelani's physical iPhone 15 Pro Max (`iPhone16,2`), explicitly selected
  by its CoreDevice identifier while paired and available.
- The complete simulator-free Catalyst unit/policy suite and generic unsigned
  iOS Release build passed on the exact feature source before the build-number
  allocation. Focused coverage checks CPL identity, supported versus retired
  channel sources, both availability-window edges and truthful option copy.
- Build 52 was allocated across the app, Live Activity extension and project
  source configuration. The physical gate then passed current provider identity
  across all three reachable feeds, strict app signature verification and a
  signed generic Debug build.
- CoreDevice independently reports `com.jelani.Fotty` as 2.0.0 (52), launched
  the normal app and observed its foreground process continuously for 60 seconds.
- A final signed generic-iOS Release compile passed after installation.

The one cleanup-controlled `/private/tmp/FottyPhysicalReleaseGate.*` root was
deleted. Free disk remains approximately 34 GiB. No simulator, UI-test runner,
iPad/other-iPhone change, TestFlight upload, tester mutation, service deployment,
Git commit or publication occurred.

## Acceptance boundary

Installation, version identity, current catalog identity and process health are
proven. During a current CPL match, the owner must still confirm on this exact
build that the fixture shows `Channel options`, the sheet lists the available
Fox/Willow rows with the unconfirmed-programme warning, and each selected channel
reaches its current broadcast. That acceptance is required before this fix is
included in a build-53-or-later TestFlight milestone or more testers are invited.

Build 52 was not accepted: the owner found that Cricket still said tomorrow
during the current CPL match and rejected the extra channel-selection tap.
Private build 53 replaces both behaviors. Do not use build 52 as current
acceptance evidence.
