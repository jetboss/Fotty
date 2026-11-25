# App-wide visual consistency pass

## Reference and scope

Continue the approved calm Home concept across native browsing. Preserve the
real app's tool destinations, badges, data qualifiers, alerts and playback.
The concept's sample matches/points are never production data requirements.
Owner clarification: every screen must feel intentional and premium. Existing
behaviour is considered stable enough based on owner testing. This milestone is
UI polish, not new features, infrastructure work or functional redesign. Judge
visual hierarchy, spacing, legibility, controls and empty/loading states, not
compactness alone. Functional work is limited to regressions caused by this pass.

## Screen coverage

| Surface | Implemented in this pass | Remaining acceptance |
| --- | --- | --- |
| Home / full sports | Circular All sports symbol; Rugby has distinct equipment; shared colour equipment defaults | Physical light/dark and large text |
| Matchday | Simple title/Browse header, grouped fixtures, quieter date sections, larger shared team rows and unframed badges | Saved/live/rescheduled physical scenarios |
| FPL main | Underlined workspace navigation; calmer manager summary with wrapping deadline; responsive tool rows | Real manager and device layout |
| FPL Coach | Sentence-case title; shared quieter secondary typography | Keyboard and real reply acceptance |
| FPL tools / squad | Retained all destinations, official/projection labels, pitch and local-draft warnings; shared typography | Individual tool layouts and iPad review |
| Search | Grouped results, shared fixture identity and bounded width | Physical keyboard and result navigation |
| Settings / support | Sentence-case accessible section headings and shared type; existing grouped Notifications/backup navigation retained | Large-text and appearance review |
| Match details / player | Shared text styles propagate; video gestures, transport, PiP and provider controls deliberately unchanged | No new playback qualification claimed |

## Verification

Focused Catalyst BetaUsabilityTests and FPLTrustTests pass. Generic-iOS Release
compilation and all four Catalyst large-text surface audits pass: Matchday,
FPL workspaces, Settings and Home. These are not physical-device visual reviews.
This is an app-wide presentation pass, not proof that every secondary screen
has been visually accepted. The initial source batch was subsequently installed
and physically reviewed as build 87; see `docs/releases/Fotty-2.0.0-87.md`.

## Build 87 review follow-up — source-only finishing pass

- Matchday shows identical following/saved reasons once in the section heading,
  retaining per-row reasons when they differ. Kickoff clashes keep a visible
  warning with optional expanded details. Freshness warnings are unchanged.
- Settings uses a compact leading title aligned with the other main screens.
  Destination navigation bars stay visible so back navigation remains available.
- Search rounds only the first/last result edges and keeps individual lazy rows.
- FPL setup leads with the team input/check action. Link instructions expand on
  demand; season confirmation, legacy-data warnings and local-draft limits remain.

Verification: 108 focused BetaUsability/FPLTrust tests and generic iOS Release
compilation pass. Five Catalyst checks pass: Matchday/Settings Dynamic Type,
Notifications grouping, native Help/feedback navigation, and FPL link input
without automatic connection. Test summaries include a generic main-thread
runtime warning; it was not diagnosed in this presentation pass. These checks
do not establish frame-rate improvement or physical visual acceptance.

No follow-up install or TestFlight upload. Owner phone remains build 87 and the
recorded TestFlight baseline remains 81. Temporary build output was trap-cleaned.
Real FPL workspace inspection still needs owner team confirmation; no identity,
preferences, saved squad or notifications were changed. iPad, physical light
mode/large text and individual secondary-tool reviews remain open.

Subsequent owner-requested deployment: private build 88 installed and launched
on Jet iPad with signed Release/signature/version checks passing. No iPhone or
TestFlight update. iPad visual acceptance is pending; see release 88.

## Guardrails

No change to manager identity, FPL computations, fixture classification, catalog
refresh, source admission, reminder side effects, or playback lifecycle. Cached
catalog projections stay intact. Sport-specific artwork stays in a fixed-size
emblem container and selection motion respects Reduce Motion. All sports retains
its accessible name and uses the preview's circular mark, not equipment emoji.
