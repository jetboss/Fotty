# Home clock and row continuity — 2026-09-08

## Reported failure

Jet iPad on private build 90 showed Cricket “1 on now” at 19:34 AST,
while the 19:00 fixture still said “Starts in 1h 5m”. An old two-card
landscape row remained under the new Live now heading in an 820-point portrait
window. Tomorrow's fixture appeared again in the updated upcoming list.
The temporary device screenshot was inspected and removed.

The catalog projection already separates channels, current fixtures and future
fixtures. This was retained presentation state, not proof of a bad CPL kickoff
or a second live match. “On now” still means the scheduled current window for
CPL, not independently verified play or a decoded stream.

## Correction

- Flatten Home headings, empty states, More live and fixture rows into one
  identified lazy sequence. Each entry renders one child, instead of changing
  independent conditional row-collection sizes as the first live section appears.
- Identify a display row by section, ordered fixture membership and column
  count. A first fixture ID alone does not identify a two-card layout. Ordinary
  clock/score updates preserve IDs and the scroll container is never reset.
- Home discovery controls use their visible live countdown timeline, not the
  timestamp captured in a cached catalog item. The projection clock runs at a
  minute cadence, wakes at kickoff (including within the same minute), and
  restarts on foreground entry or catalog replacement.
- Foreground catalog refresh shares the existing 90-second attempt throttle.
  Manual retry remains available. Cancellation permits immediate retry; failed
  and replayed checks cannot advance the successful receipt.
- Normal age/cache messages are silent. Real fetch failure, partial catalog,
  invalid future receipt and independently unverified CPL times retain warnings.
  This does not change schedule authority, stream admission or reminder consent.

Apple's [ForEach guidance](https://developer.apple.com/documentation/swiftui/foreach)
and [scrollable-stack guidance](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks)
support stable identified data and a constant child count per entry. This is
not a claim that Apple diagnosed this specific app's defect.

## Verification

The deterministic, network-free Catalyst journey starts with a two-card upcoming
row, advances 100 minutes across kickoff, shrinks the real window, and checks
current status, updated countdowns, uniqueness and navigation continuity.
Early runs failed to enable UI automation. Executable runs passed the kickoff,
resize and uniqueness checks but then found the test's fake clock resetting
when Home was recreated after tab navigation. That test-only clock now survives
for the process lifetime, without changing real preferences. This harness
failure is not evidence that the app fix failed. Direct native inspection also
confirmed the updated current fixture, next countdown and nonduplicated rows.

The width test uses a 600-point Mac window, comfortably below the app's narrow
UIKit layout boundary, and checks that the action reaches the trailing edge.
Do not equate AppKit window points with iPad points: the Catalyst iPad idiom
[scales its interface](https://developer.apple.com/design/human-interface-guidelines/mac-catalyst).
An 820-point Mac window can legitimately remain in the wide UIKit layout; that
initial test assumption was corrected rather than changing the iPad breakpoint.

All 137 focused unit tests pass. Six focused Catalyst UI checks pass; the
strengthened narrow-window transition check also passes on its subsequent run.
Generic unsigned iOS Release compilation, shell syntax and whitespace checks
pass. These are local checks, not verified cricket playback or physical-device
foreground/rotation acceptance.

The delivery boundary is recorded in the current-state summary
and decision log. No physical-device installation or TestFlight upload is part
of this source-only fix. Both owner devices remain on installed build 90 until
a separately authorized deployment. The owned 1.5 GB gate (build products,
results, logs and screenshots) was removed after verification; about 48 GiB
remains free. This output can be regenerated; no user data was removed.
