# Fotty 2.0.0 (65) — private live-first Home candidate

Date: 2026-09-06. Status: **rejected and superseded by build 66** after both
Jelani's iPhone and Jet iPad hit a scene-create watchdog termination; not
uploaded to TestFlight.

## Rejection evidence

Three symbolicated device reports record `0x8BADF00D` while the main thread was
inside `SportsDashboardView.prioritizedDiscoveryItems`. The comparator repeatedly
ran full broadcast selection and football club normalization for the same
events. iOS terminated the iPhone after 10 seconds and the iPad after about 20
seconds. Successful installation and an initial launch command did not prove
startup survival. Build 66 precomputes each rank once and is the only current
private candidate.

## Candidate scope

Build 65 retains private build 64's accepted iPhone web controls and adds the
owner-approved live discovery correction:

- Home presents every live/listed-now event directly under `Live now`; the
  three-row recommendation cap applies only to upcoming events;
- followed events rank first, followed by Premier League, Champions League and
  the remaining competition tiers; Full lineup uses the same ordering; and
- direct Score808 discovery retains provider identity in diagnostics but uses
  provider-neutral failure copy, so one provider is not presented as Fotty's
  entire combined search.

## Verification completed

- The generated competition catalog, five deterministic identity vectors and
  live identity audit across three reachable provider feeds passed.
- The complete simulator-free Mac Catalyst policy suite passed, including the
  regression that retains five simultaneous live rows while limiting five
  upcoming recommendations to three.
- The focused Home Catalyst interaction journey passed before version
  allocation; the exact build-65 source then passed the complete policy suite
  and generic unsigned iOS Release build.
- One automatically signed universal Debug artifact installed and launched on
  Jelani's iPhone 15 Pro Max and Jet iPad. Independent CoreDevice reads report
  `Fotty Sports Hub` 2.0.0 (65) on both devices.
- The bounded physical build directory was removed. No Fotty physical-gate,
  Catalyst-gate or CI temporary directory remained, and about 64 GiB was free.

## Superseded boundary

Do not use build 65 for testing or distribution. Its successful compile,
installation and launch response did not detect the main-thread scene-create
watchdog. See `Fotty-2.0.0-66.md` for the correction and physical hold evidence.

TestFlight remains build 55. No backend, provider, tester, production, paid-Coach
or remote Git state changed.
