# Fotty 2.0.0 (66) — private live-first watchdog correction

Date: 2026-09-06. Status: installed, launched and held beyond the scene-create
watchdog window on Jelani's iPhone and Jet iPad; not uploaded to TestFlight.

## Incident and correction

Private build 65 was rejected after both devices opened and closed. Three
symbolicated device reports identify `0x8BADF00D` scene-create watchdog
terminations. The main thread was sorting Home while repeatedly calling full
broadcast selection and football club normalization from inside the comparator.
The iPhone exhausted 10 seconds and the iPad exhausted approximately 20 seconds.
This was app-owned startup work, not memory pressure, thermal pressure or a
provider outage.

Build 66 preserves the live-first behavior but decorates every event with its
presentation rank exactly once before sorting. The comparator now reads only the
precomputed integer key, kickoff and ID. Availability ranking uses the event's
attached supported-source metadata; full broadcast matching remains bounded to
an explicit Watch tap.

## Verification completed

- A regression with 40 events proves the rank closure executes exactly once per
  event and still promotes the intended event.
- The generated competition catalog, five deterministic identity vectors and
  live identity audit across three reachable provider feeds passed.
- The complete simulator-free Mac Catalyst policy suite and generic unsigned
  iOS Release build passed after allocating build 66.
- One automatically signed universal Debug artifact installed and launched on
  Jelani's iPhone 15 Pro Max and Jet iPad. Independent CoreDevice reads report
  `Fotty Sports Hub` 2.0.0 (66) on both devices.
- Both main app processes and both Live Activity extension processes remained
  present after more than 65 seconds. No new Fotty crash report appeared.
- The owned physical build directory and local copied crash reports were
  removed; approximately 64 GiB remained free.

## Remaining boundary

The reproduced startup termination is corrected. Hands-on confirmation of Home
ordering, failed-stream copy and existing iPad playback/PiP behavior remains
separate. TestFlight remains build 55. No backend, provider, tester, production,
paid-Coach or remote Git state changed.
