# Fotty 2.0.0 (70) — private catalog render rebuild

Date: 2026-09-06. Status: installed and launched on Jelani's iPhone as an
optimized Release build; hands-on cold-scroll acceptance remains pending. Jet
iPad and TestFlight build 55 remain unchanged.

## Why another cache patch was not enough

The owner physically rejected builds 68 and 69 for the same first-pass catalog
stutter. Apple documents that a lazy stack estimates unseen geometry and that
absolute offsets, dynamic child counts, layout changes after appearance and
work performed while a row is being prefetched can make scrolling less smooth.
The Home implementation combined all four conditions, so further provider or
badge tuning could not close the visible problem.

## Structural correction

- Home and Full lineup no longer bind or persist absolute pixel offsets. They
  begin at a deterministic top position instead of asking a variable-height
  lazy stack to restore an estimated coordinate.
- Fixture groups no longer contain nested vertical lazy stacks. Each visible
  fixture resolves to one stable outer lazy child, with its divider inside that
  child. Full-lineup date headings and fixtures are flattened before rendering.
- Football competition, score text and badge URLs are projected once when the
  catalog/score snapshot changes. A row no longer queries the live-score owner
  while SwiftUI is evaluating it during a scroll.
- Normal-size team, competition and status lines have bounded line counts and a
  stable information height. Accessibility sizes retain their reflow instead
  of being clipped.
- Catalog rows use the shared once-per-minute discovery clock instead of owning
  independent TimelineViews. Other standalone uses retain precise countdowns.
- The custom side-by-side row layout caches its subview measurements between
  sizing and placement. The compact trailing Watch action remains intact.
- Search removes the same unstable absolute-offset behavior and makes every
  result iteration resolve to one container.

## Verification

- The complete simulator-free Catalyst unit suite passes, including an updated
  structural guard for stable lazy rows, precomputed presentation and removal of
  absolute-offset observation.
- The generic optimized iOS Release build passes.
- One signed optimized Release artifact passed strict signature verification,
  installed only on Jelani's iPhone, and CoreDevice independently reports Fotty
  Sports Hub 2.0.0 (70). The app and Live Activity extension remained alive
  after a 20-second process hold.
- Every owned CI/performance DerivedData root was trap-cleaned. Disk remains at
  approximately 63 GiB free. No simulator, UI-test runner, iPad install,
  TestFlight upload, web deployment or provider mutation occurred.

## Physical acceptance

Force-close build 70, reopen it, and immediately scroll Home through the first
cold catalog pass. Repeat warm, switch sport filters, open Full lineup, and
return to Home. A visible freeze or multi-frame jump fails the candidate. The
intentional tradeoff is that Home and Search no longer restore an exact pixel
position; reliable smooth scrolling wins over an unstable estimated coordinate.
