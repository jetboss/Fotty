# Fotty 2.0.0 (79) — Matchday responsiveness and Settings cleanup

Date: 2026-09-06. Status: **Internal / Testing for `Fotty Internal Smoke`;
installed directly on Jelani's iPhone and Jet iPad; hands-on acceptance pending**.

## Outcome

My Matchday no longer performs full-catalog personalization, official-fixture
matching, status checks, playback selection, grouping and live sorting during
each SwiftUI redraw. One revision-keyed projection calculates those values once
and publishes all visible sections without animation. The screen also stops
writing absolute scroll offset to persistent scene storage on every movement,
and root tab selection no longer animates two complete screen trees.

Settings removes explanatory copy that repeated obvious labels, destinations or
toggle behavior. Privacy and network disclosures, backup consequences,
permission recovery, persistence failures, destructive warnings and actionable
errors remain. Playback sources no longer expose built-in implementation version
text to testers.

## Verification and installation

- A source regression check requires the Matchday projection and rejects
  per-frame scroll geometry persistence and body-time live sorting.
- The complete simulator-free Catalyst policy suite passed.
- Current live provider identity checks passed across three reachable feeds.
- The single production graph scan and generic iOS Release compile passed.
- One signed universal Debug app passed strict nested signature verification and
  installed in place on Jelani's iPhone. The same qualified source was rebuilt
  in a bounded clean directory, installed on Jet iPad and launched normally.
- CoreDevice rejected automatic launch on the phone because it was locked, but
  the iPad launched successfully. The owner still needs to confirm immediate
  Matchday entry, smooth Matchday scrolling and the reduced Settings copy.
- The App Store archive was produced and uploaded with public Xcode 26.6. Apple
  accepted and processed it at 22:39 AST. App Store Connect records export
  compliance as none of the listed encryption algorithms and shows build 79 as
  **Testing** for the unchanged seven-person `Fotty Internal Smoke` group.
- No tester, role, external-testing group, uninstall or data-container reset
  occurred. TestFlight install counts were still empty immediately after
  activation; availability does not prove installation or hands-on acceptance.
- The uploaded app executable SHA-256 is
  `b810a6011ca5dabf99128b762b213480d126df6f44642256a3c5b2cadbde24fe`.
- Every owned temporary DerivedData directory was removed by cleanup traps.
