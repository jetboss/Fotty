# Fotty 2.0.0 (56) - private provider trust diagnostics candidate

Date: 2026-09-04. Status: **installed only on Jet iPad for private testing**.

## Incident and correction

- The live Ipswich Town–Liverpool catalog was not empty. Three current feeds
  exposed the event, and the two StreamEx APIs supplied 12 concrete variants.
- Every variant used `embed.st`, whose Let's Encrypt certificate expired at
  2026-09-04 14:59:58 UTC. Apple networking rejected the real host with
  `NSURLErrorDomain -1202`; safely playing that provider output is therefore
  impossible until its certificate or host changes.
- Fotty now classifies certificate, trust and secure-connection errors as
  `provider_security_failure`, preserves the most actionable candidate failure
  when every source fails, and shows the truthful secure-provider outage from
  Home, Matchday and Match Hub instead of claiming no stream exists.
- Fotty does not bypass ATS, accept an invalid certificate, downgrade the URL
  to HTTP, invent another host or restore a first-party playback proxy. A valid
  replacement URL from the provider can recover normally without rebuilding.

## Verification and installation

- Focused regressions cover the native `URLError` and bridged `NSError` forms,
  ordinary timeouts and failure precedence.
- The complete simulator-free Catalyst unit and generic iOS Release gate passed
  after the final bridge correction. Generated catalog validation and the live
  provider-identity audit passed across all three reachable feeds again during
  the signed-device run.
- Source and both Xcode targets were advanced to 2.0.0 (56) because build 55 is
  already distributed through TestFlight.
- The signed physical-device build installed in place only on the authorized
  `Jet iPad` (`34E32922-73D6-54EA-8556-7904EE7804BD`). CoreDevice independently
  reports `Fotty Sports Hub`, bundle `com.jelani.Fotty`, version 2.0.0 and build
  56. Its process list shows the normal app and `FottyLiveActivityExtension`
  running after launch.
- No simulator ran. The owned temporary Xcode build directory was removed and
  the data volume retained approximately 34 GiB free.

## Distribution and acceptance boundary

This is a private iPad pre-test, not a shared release. TestFlight remains at
build 55; no iPhone, other iPad, tester group, Worker, web service, App Store
submission, Git branch or publication changed. The install did not uninstall or
reset Fotty, but retained preferences were not manually inspected. Physical UI
acceptance still needs the owner to confirm that the new secure-provider message
appears naturally when a trust outage is encountered. The current `embed.st`
certificate was still expired after installation, so build 56 cannot make those
particular variants play until the upstream provider repairs them.
