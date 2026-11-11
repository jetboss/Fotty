# Fotty 2.0.1 (126): private iPad diagnostics

Date: 2026-10-10. Owner-authorized private installation on Jet iPad only.
Shared TestFlight121, other devices and production backend are unchanged.

## Changes

Bounded local watch-session, attempt and source correlation plus typed playback
stages. Failure records include the last observed stage; navigation errors retain
numeric platform codes only. Loaded/ready does not mean decoded playback.
Opaque provider media still limits causal diagnosis. No new telemetry upload,
provider admission, recovery timeout, transport-control or PiP changes.

## Verification

- 862 native unit tests, two skipped, zero failures. No simulator used.
- Football catalog check and five provider identity vectors pass.
- Signed iOS Release app and extension both126; strict signature verification pass.
- Executable SHA256: `78216ad98726528516f4c25f80e33e21ded5bf3d6907068179af4522b81cea22`.
- Jet iPad in-place installation sequence1868; independent installed2.0.1(126)
  readback and launch pass; process8092 observed. No user-data reset.
- New live playback, failure reproduction and visual acceptance are not claimed.
- Owned temporary build/test output removed on exit;33GiB free afterward.

This is not a frozen-source shared-release qualification or TestFlight approval.
