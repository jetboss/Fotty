# Fotty 2.0.0 (58) — direct Score808 discovery

Date: 2026-09-04. Status: installed on Jet iPad only; launch blocked by device lock; not TestFlight.

## Change

- Remove build 57's unverified `admin` → `hotel` inference and the extra
  speculative late-family row. The original shared catalog and its explicit
  source families remain separate from the actual Score808 site.
- On an explicit football Watch request from 30 minutes before kickoff,
  discover the website's public calendar and select one visible, nonrecurring
  event with the exact normalized teams and kickoff. Convert the published IANA
  timezone; reject expired, ambiguous, malformed or unsupported event mappings.
- Follow only the published HTTPS Score808 Watch page. Do not hardcode a live
  media URL or attach a reused article to unrelated/historical matches. All
  discovery bodies are capped at 1 MiB; redirects are checked before following.
- Require the observed configured main Video.js player. Preserve its original
  page context, use its controls, and fit that player into the app viewport.
  For this direct-site route, advertising frames/videos cannot own the playback
  monitor or supply unrelated native-handoff media. This is not a universal
  ad-free promise or native/PiP certification.
- Replace the playback monitor before every source/attempt load. SwiftUI can
  reuse the web view; switching either direction between Score808 and shared
  sources must not retain the previous provider's rules.
- Check the direct site independently of the shared catalog. Collect partial
  choices and failures, give both lanes a result/deadline opportunity, and retain
  additional ready choices during a short grace period. A slow lane cannot erase
  an already-found page or concrete trust failure. A deadline is described as a
  timeout, not proof that no stream exists.
- The shared HTML validator now actually reads up to its 8 KiB bound and cancels
  the remaining response. This catches rejection text after byte 256; generic
  HTML reachability still does not prove decoding or arbitrary stub rejection.

## Evidence

- Simulator-free Catalyst compilation passed. The final full unit suite passed
  **273 tests, zero failures, two explicit skips**: the reference-HLS soak and
  the reported match's live probe after its calendar end. The earlier full run
  included a passing live probe (273 passed, one skip, before the new switch test).
- The opt-in live production `Score808SiteResolver` test passed in approximately
  0.53 seconds during the reported fixture. It returned the exact owner-supplied
  Watch page using the real parser, URL allowlist, bounded transport and calendar.
- Deterministic cases cover timezone rollover, stale page reuse, team/venue
  mismatch, ambiguity, unsupported hosts/schema, hidden/recurring events, player
  configuration, late unavailable text, Foundation path normalization, partial
  resolution, fair provider opportunity, cancellation and ad-media exclusion.
- Both provider-switch directions pass on a reused WebKit script controller.
  Final review found and corrected creation-only monitor installation before
  distribution. A duplicate test actor annotation was also caught at compile
  time and removed before the final passing suite.
- Initial qualification caught two new-test failures: a real Foundation trailing
  slash URL-policy bug, and missing browser URL behavior in the JavaScriptCore
  test harness. Both were corrected before the passing run.
- The suite reports an existing Catalyst audio-session main-thread warning;
  it is not a test failure or physical playback acceptance.
- The live provider identity audit passes across three reachable shared feeds;
  `git diff --check` passes. Neither proves decoded stream availability.

## Boundaries and follow-up

The complete simulator-free iOS Release gate and subsequent signed Debug build
passed (exit 0). Strict recursive code-signature validation passed, and app plus
Live Activity extension both report build 58. CoreDevice confirmed successful
installation only on Jet iPad (`34E32922-73D6-54EA-8556-7904EE7804BD`). Launch
was explicitly denied with `Locked`; this is not process or playback acceptance.
TestFlight remains 55. No iPhone, testers, service deployment, App Store
submission or Git publication changed.

CoreDevice independently reads back Fotty Sports Hub 2.0.0 (58). Its process
list contains the Live Activity extension but not the main app after the denied
launch; an extension process must not be presented as a successful app launch.

The single temporary build root, all DerivedData, signed app copies and result
bundles were removed by the owning shell's cleanup trap after installation.
The path was verified absent; available disk returned from approximately 31 GiB
during qualification to 33 GiB. No simulator or UI-test runner was used.

The prior browser investigation proved decoding on the provider page. It did
not prove playback in build 58, iPad controls, recovery or native PiP. Those are
separate physical acceptance checks. The direct adapter resolves already-visible
football fixtures; it does not yet add Score808-only fixtures to Home.

The separate [deep application audit](../audit/Fotty-Deep-App-Audit-2026-09-04.md)
contains 14 ranked findings. Its broader wrong-match fallback, retry lifecycle,
alternative curation, FPL freshness and notification recommendations are not
silently bundled into this focused fix.

Partial sessions and actionable errors survive lane cancellation. Detailed
timeline/attempt logs currently arrive only with a completed lane, so the trace
is not yet complete for interrupted lanes; this is an explicit audit follow-up.
