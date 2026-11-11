# Sport loading motion — 2026-09-08

## Scope

Owner requested distinctive premium sport loaders and a Champions League
variation, followed by a private Jet iPad install. No TestFlight upload, backend,
provider, playback transport, FPL, persistence or fixture-classification changes.

## Implementation

- Replace the shared spinning-symbol/glow loader with original native vector
  equipment: football panels, stitched cricket/baseballs, basketball dribble,
  tennis bounce, rugby panels, American-football laces, a hockey puck, racing car
  and glove tap. All sports uses a composed group of three shaded balls.
- Stationary highlights and shading are separate from rotating markings, with
  contact shadows and restrained surface markings. No downloaded media, sound,
  haptics, third-party animation dependency, shader or physics engine.
- `SportMotionPose` is bounded pure loop math. One small `Canvas` draws the active
  loader; a local `TimelineView` requests at most 30 frames per second. No
  identity lookup or catalog projection occurs inside the frame closure.
- `SportLoadingView` pauses offscreen, outside the active scene, in Low Power
  Mode or with Reduce Motion. Low Power Mode changes are observed immediately.
  Static artwork retains sport identity. Artwork is noninteractive and hidden
  from accessibility; the parent exposes one loading label.
- Loading completion remains owned by the existing operation. No minimum
  display duration, fake progress or change to player controls. Home, Match
  Center, resolution and player preparation share the same renderer;
  simultaneous multistream lookup uses All sports.
- Champions League uses blue/silver football panels, a subtle night-stadium
  glow and light glints—not the official UEFA logo/starball. Selection is
  presentation-only: an explicit UCL/UEFA provider marker or a reconciled
  official match is required. Official data must match both whole team
  identities and kickoff within 15 minutes. Conflicted, youth, women's and other
  confederation metadata do not receive this senior UEFA treatment. Merely
  knowing two famous clubs is not evidence. Unknown competition stays football.
- Existing Home sport-tile equipment and selection animation are preserved;
  this work updates loading states, not the whole icon system.

## Apple implementation references

- [Canvas](https://developer.apple.com/documentation/swiftui/canvas) supports
  dynamic, noninteractive drawing. Individual Canvas elements are not separate
  accessibility controls; the loading label remains in SwiftUI.
- [Animation timeline](https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:))
  provides the minimum update interval and paused state.
- [Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
  calls for avoiding large motion, particularly simulated depth. This loader
  becomes fully still, rather than substituting another continuous animation.

## Validation

Focused units cover category distinctions, conservative competition evidence,
official team/kickoff agreement, bounded poses, seamless loop boundaries and
static motion-off frames. Native-rendered dark/light contact sheets sample four
phases of every treatment. Rendering and startup are not proof of physical
playback or device-level hitch/battery measurements.

Execution and installation results are recorded in the corresponding build 92
release note after those gates complete.
