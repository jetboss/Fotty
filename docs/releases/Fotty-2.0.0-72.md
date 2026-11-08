# Fotty 2.0.0 (72) — priority-led Home private iPad candidate

Date: 2026-09-06. Status: installed and launched on Jet iPad as an optimized
Release build; the Home hierarchy and reviewed-alias deduplication are visually
present, while hands-on expansion/scroll/playback acceptance remains pending.
Jelani's iPhone remains on private build 70 and TestFlight remains build 55.

## Product correction

- Home gives three compact-phone or four iPad positions to the highest-ranked
  live events. Remaining live events stay one disclosure away under a counted
  `More live` control and remain present in Full lineup.
- Audience relevance is explicit and presentation-only: followed Premier
  League/Champions League matches lead, then Premier League, Champions League,
  CPL/explicit follows, the other supported major European leagues, other
  sports and other football. It does not change provider identity, score
  coverage or whether a stream is playable.
- The priority is precomputed once per item before sorting, preserving build
  70's main-thread scroll boundary.
- Exact same-sport/same-kickoff team aliases from Fotty's reviewed team catalog
  collapse into one event and union their real sources. Unknown or similarly
  named reserve teams remain separate; there is no fuzzy matching.

## Verification

- The complete simulator-free Catalyst unit suite and generic iOS Release gate
  pass, including phone/iPad prominence limits, priority tiers, one-time rank
  evaluation and the exact reviewed alias case.
- Build 71 was installed only as the first visual diagnostic. Its iPad capture
  exposed duplicate `Alaves` and `Deportivo Alavés` rows consuming separate
  featured positions, so it was immediately superseded and is not the accepted
  candidate.
- One signed optimized Release artifact installed only on Jet iPad. CoreDevice
  independently reports Fotty Sports Hub 2.0.0 (72), launches the normal app and
  keeps its foreground process alive for 60 seconds.
- A fresh build-72 screenshot shows one Alavés–Osasuna row instead of two and
  the `Featured live` hierarchy. The catalog truthfully reported that it was
  showing earlier listings, so that capture is not evidence of current Premier
  League ordering or provider availability.
- All owned DerivedData and screenshot directories were deleted. No simulator,
  device UI-test runner, TestFlight upload, provider/backend mutation or other
  device installation occurred. Disk returned to approximately 63 GiB free.

## Remaining physical acceptance

On Jet iPad, expand and collapse `More live`, confirm every lower-ranked live
event remains reachable, switch between All sports and Football, rotate, and
scroll cold/warm through Home and Full lineup. During a real Premier League
window, confirm Premier League fixtures occupy the featured positions ahead of
unfollowed lower-priority listings. Playback, PiP, notification, Live Activity
and assistive-technology checks remain their separate physical gates.
