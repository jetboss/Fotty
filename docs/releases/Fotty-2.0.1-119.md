# Fotty Sports Hub 2.0.1 build 119 — clock-independent Home facts

4 October 2026. Owner-only optimized Release installed normally in place on
Jet iPad Air 4 / iPadOS 27.0.1. Shared TestFlight 111 is unchanged.

## Repair and qualification

Home follow/major-league/CPL facts now survive clock-only projection changes.
Catalog, official-score and complete saved-selection identity remain cache
keys. Mismatched keys expose no old facts; rebuilding computes missing IDs and
prunes removed IDs. Discovery phases, countdowns and receipt freshness still
use the current clock. CPL notice classification can use the gated facts without
caching or hiding its time-dependent warning. No source, fixture, score, FPL or
persistence policy change.

- 748 Catalyst tests pass, two intentional opt-in skips, zero failures. Six new
  semantic cache tests cover first load, empty/populated catalogs, clock changes,
  same-ID replacements, score changes, same-count selection edits, pruning and
  mismatched-key fallback. Notice tests retain live expiry checks.
- Seven version tests, native version verifier, generated catalog, five
  deterministic provider identity checks and three reachable live feeds pass.
- Sequential unsigned/signed optimized iOS Release, strict nested signatures
  and empty embedded-provider-key checks pass. Six existing Catalyst audio
  activation warnings remain; they are not confirmed iPad defects.
- Exact-device in-place installation, normal launch and visible Settings
  version 2.0.1 (119) pass. No uninstall, reset, simulator or UI-test runner.
  Typed aggregate comparisons preserve appearance, Home/user preferences,
  manager confirmation/reviews, reminders and the local manager ID. No private
  preference values appear here; SwiftData records were not separately compared.

## Frozen artifact identity

Pre-build receipt: `backups/release-source/2.0.1-119-owner-ipad` (991 files).
Secret scan, round-trip restore and pre-install source comparison pass.

- Recovery commit `e83643dd061a4284be8b9a6f8a2126dbc5fb0497`.
- Source SHA256 `f34aea8b901109ffc01fdd2e4110fa4f62edcfea17cbf458617b5f07ce789ebe`.
- Bundle SHA256 `4b9543e506a5ebd7270f697c190d9e5647612ff8ee7d65ab901d2d8d8f381a79`.
- Signed executable SHA256 `cd1854311851c3f5677fe8c0d7ca8d062a203523119f07ad9182416583597666`.
- Matched app/dSYM arm64 UUID `FBAEF211-768E-349E-84F5-960DBF4414D2`.

## Actual native responsiveness — follow-up repair required

Both recordings attached to the installed Jet iPad process 3134, not the old
Mac app. They exercised real Home dragging and Home/Matchday/Settings navigation.

- Run 1: 45.863014 s, 08:42:36.067–08:43:21.930 AST. Seven Home body updates,
  158.539123 ms total, 47.112458 ms maximum. One main-thread microhang,
  311.097041 ms; three app hitches, 49.996957 ms total / 16.665750 ms maximum.
  Long updates: 73, 321.96 ms total, 47.11 ms maximum, 12.93 ms downstream maximum.
- Run 2: 45.701786 s, 08:53:25.738–08:54:11.440 AST. Repeated navigation and
  scroll workload. One main-thread microhang, 266.450083 ms; 27 app hitches,
  633.308615 ms total / 83.328583 ms maximum. Long updates: 184, 1.23 s total,
  49.19 ms maximum, 105.22 ms downstream maximum.

Independent matched-symbol Run 1 analysis covers 3,039 running main-thread
samples / 303.9 ms inside its hang. Inclusive cached fixture decode/validation
was 61.2 ms (35.5 ms parsing); Matchday rebuild 43.8 ms (27.8 ms league matching);
Home multi-view eligibility 16.4 ms. No Home follow fallback or Home projection
rebuild appears there. Framework stacks with only app-entry frames account for
138.0 ms. Inclusive weights overlap and are not exact function self-time.

These are descriptive, not controlled percentage comparisons. Changing live
catalog data and interaction counts preclude a speedup percentage. Neither run
is a zero-stall pass. The approved next focused repair targets pure date parsing,
Matchday selection preparation and single-pass source-first multi-view admission;
time-relative fixture validation must remain unchanged.

Native landscape Home/Matchday/Settings render, scroll and navigate. Light,
one favorite and four Home interests remain visible. At 08:59, imminent Aston
Villa/Crystal Palace becomes Watch-eligible and Watch Two appears alongside the
Rally listing. No two-live playback, audio or PiP acceptance is claimed for 119.

## Boundary and cleanup

Apple UI and staged performance guidance require actual native checks and
matched measurements, not a build-only pass. The 120 source repair and this
documentation are outside the frozen 119 receipt. Remove owned raw traces,
exports, preference copies and build output after the ongoing owner gate;
preserve immutable receipts and unrelated artifacts. No TestFlight, Git
publication, backend deployment, tester changes, spending or FPL feature work.
