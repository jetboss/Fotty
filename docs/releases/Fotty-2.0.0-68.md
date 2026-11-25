# Fotty 2.0.0 (68) — private performance foundation

Date: 2026-09-06. Status: physically rejected for remaining Home scroll
stutter and superseded by private build 69. Jet iPad and TestFlight build 55
remain unchanged.

## What changed

Build 68 completes the catalog-scroll correction with system-level controls,
not only view substitutions:

- Home and each catalog group construct rows lazily. Scroll geometry is held in
  a non-observable capture and persisted only when scrolling becomes idle or the
  view disappears.
- badge responses are capped at 2 MB, downsampled off the main actor to a
  256-pixel thumbnail, coalesced by URL and served through bounded 32 MB memory
  and 48 MB disk caches. Dense badge arrivals no longer animate independently.
- team-brand refreshes publish one atomic catalog result instead of republishing
  the complete dictionary after each of roughly two dozen league responses.
  Individual badge rows no longer observe that global service.
- Home's discovery and football-league projection is computed only for a new
  catalog, score revision or minute bucket rather than every unrelated SwiftUI
  body update.
- SwiftData catalog replacement now runs through a dedicated model actor after
  the fresh in-memory catalog is published. Whole-catalog replacement no longer
  carries a global animation.
- stable CatalogProjection and CatalogCacheReplace signposts support SwiftUI/
  Time Profiler diagnosis. MetricKit records only the most recent hitch ratio
  and bounded hang scalars in UserDefaults and Console; no raw payload or trace
  archive is retained or uploaded.
- `tools/ios-performance-gate.sh` builds and installs the actual optimized
  Release graph on one explicit physical iPhone. Its optional SwiftUI trace is
  time-bounded and automatically deleted with its single temporary build root.

## Verification

- Full simulator-free Catalyst unit/policy suite passed.
- Generated competition and five deterministic provider identity checks passed.
- Generic optimized iOS Release compilation passed.
- A separately signed optimized Release build compiled, passed strict signature
  verification, installed and launched on Jelani's iPhone. CoreDevice reports
  Fotty Sports Hub 2.0.0 (68), and the main app/Live Activity processes remained
  present after a 30-second hold.
- The performance build root was removed automatically. Free disk returned to
  approximately 63 GiB; no simulator or UI-test runner was used.

## Acceptance boundary

Compilation, launch and process survival do not prove perceived scroll quality.
On Jelani's iPhone, cold-launch Home and rapidly scroll from the first row
through Full lineup twice. The first pass must remain responsive while badges
arrive, the second must not conceal a first-pass hitch, and returning to Home
must restore a sensible position. If a hitch remains, record the same gesture
with the bounded SwiftUI performance gate before changing more code.

This is a private owner-device candidate. It has not been uploaded to TestFlight
and is not accepted for the wider beta yet.
