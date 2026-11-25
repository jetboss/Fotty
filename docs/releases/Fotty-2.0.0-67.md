# Fotty 2.0.0 (67) — private catalog-scroll performance correction

Date: 2026-09-06. Status: installed on Jelani's iPhone; automatic launch and
hands-on scroll acceptance remain pending because the device was locked. Not
installed on Jet iPad and not uploaded to TestFlight.

## Incident and correction

After build 66 fixed the Home startup watchdog, the owner reported that the
first catalog scroll on iPhone could freeze, stutter and then become smooth.
Inspection found three synchronous/high-frequency costs in that path:

- Home and each discovery group used eager stacks, creating offscreen catalog
  rows and starting their badge work before those rows were visible.
- every geometry update wrote the scroll offset into `SceneStorage`, invalidating
  and persisting state throughout the gesture;
- provider badge data was inflated into full `UIImage` instances from a view
  task, followed by one independent appearance animation per completed image.

Build 67 uses lazy catalog stacks, captures geometry in a non-observable holder
and writes the rounded scene offset only when scrolling becomes idle or the
surface disappears. Badge data is downsampled to a 256-pixel maximum dimension
on a detached utility task. Dense badge loads publish without independent
transitions. Artwork identity, fallback order and scroll restoration remain.

## Verification completed

- A bitmap regression proves 1024×640 input is decoded within the 256-pixel
  bound. A source contract keeps Home lazy and forbids per-pixel scene writes.
- The complete simulator-free Catalyst policy suite passed.
- The generated competition reference, five deterministic identities and live
  identity audit across three reachable feeds passed.
- Signed Debug compilation and installation on Jelani's iPhone succeeded.
  CoreDevice reports Fotty Sports Hub 2.0.0 (67).
- The generic unsigned iOS Release build passed.
- Both bounded build roots were removed. No simulator, physical UI-test runner,
  TestFlight upload, backend/provider mutation or iPad installation occurred.

## Remaining boundary

CoreDevice could not launch build 67 because Jelani's iPhone was locked. Launch,
process hold and hands-on first-scroll comparison remain required before this
private build can be accepted as the correction. TestFlight remains build 55.
