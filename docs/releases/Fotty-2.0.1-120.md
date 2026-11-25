# Fotty Sports Hub 2.0.1 build 120 — owner iPad performance acceptance

4 October 2026. Optimized Release installed normally in place on Jet iPad
Air 4 / iPadOS 27.0.1. Shared TestFlight 111 and fallback 100 are unchanged.
This completes the approved narrow iPad navigation / Watch Two repair gate,
not an all-device, all-provider or shared-release qualification.

## Confirmed work and correctness boundaries

Successive matched-device investigations found repeated Home interest/league
work, CPL normalization, clock-invalidated immutable facts, fixture date parsing,
Matchday league matching and multi-view admission in long main-thread intervals.
The earlier build 116 layout repair also addressed a wrapped Focus source label.
Builds 117–119 removed repeated alias/formatter construction and clock-only
invalidation; build 119 still reported 311.10 / 266.45 ms potential hangs.

Build 120 targets the remaining confirmed pure-computation paths:

- Matchday prepares the complete followed-team/league selection once per
  projection, preserving current official Premier League precedence and saved
  arbitrary selection behavior. Projection invalidation still uses the full
  selection identity; same-count edits do not reuse stale facts.
- Home's Watch Two admission checks supported source presence before time/CPL
  work and visits candidates in one pass, stopping at two. It preserves the
  Boolean eligibility result, ordering and current time-sensitive guards.
- ISO8601 parsing reuses the existing locked formatter pair and memoizes exact
  short strings, including invalid results. NSCache count/cost limits and a
  256-byte input admission bound limit retention; NSCache limits are advisory,
  not a strict allocation ceiling. Eviction simply causes reparsing. Fractional,
  whole-second, offset and malformed parsing semantics remain unchanged.

Only pure parse results and immutable revision/selection-keyed facts are cached.
Fixture freshness, phase, expiry, countdown, source admission and accepted
snapshot validation remain current. No fixture/source/FPL/persistence policy
change was introduced to improve timing.

## Automated and artifact qualification

- 755 Catalyst tests pass, two intentional opt-in skips, zero failures (757
  total). Seven new regressions cover prepared-selection equivalence, source
  admission's single-pass/early-stop behavior, parser equivalence and concurrent
  cache churn/eviction. Six existing Catalyst audio-activation warnings remain;
  they are not confirmed iPad defects.
- Seven version tests, native version verifier, generated catalog, five
  deterministic provider identity vectors and three reachable live feeds pass.
- Sequential unsigned/signed optimized iOS Release, strict nested signatures
  and empty embedded-provider-key checks pass. Official Xcode 27, jobs 1, no
  simulator. No functional source edit follows the pre-build receipt.
- Exact Jet iPad installation and normal launch pass (PID 3171). Visible native
  Settings confirms 2.0.1 (120), Light appearance, one favorite and four Home
  interests. Typed aggregate comparison preserves appearance, Home/user and
  manager review/confirmation preferences, reminder state and the local manager
  ID without exposing values. SwiftData records were not separately compared.

Frozen pre-build receipt: `backups/release-source/2.0.1-120-owner-ipad`, 992 files.
Default secret scan, round-trip restore and pre-install source comparison pass.

- Recovery commit `361f0f94f8dd77faaa5a659db8d7dca0c3cc389b`.
- Source SHA256 `427d65b0aabc25f5e63b12d598b8dd127a31165e193a6857566d9d20b7d12cd6`.
- Bundle SHA256 `8cc2c21f85289a1154272c47e81efe1c50a73797a24322d4739fb2799ee21bf7`.
- Signed executable SHA256 `8283b1bc03e53117d24c3e03e7cdda838d36beb08758b57a6306fca6f4d65222`.
- Matched app/dSYM arm64 UUID `77187DBD-23E4-3B03-BBD8-1FF52E0DD134`.

## Actual installed-iPad navigation measurement

Both bounded GUI Instruments recordings attach Jet iPad's installed Release
process 3171, not the Mac app. Each exercises real Home dragging and repeated
Home / Matchday / Settings navigation. Hangs includes microhangs over 250 ms;
100-microsecond profiling and recording overhead apply. Source receipts, trace
TOC and exported tables were independently checked before cleanup.

| Run | AST interval / duration | Reported >250 ms potential hangs | App hitches | Total / maximum hitch |
| --- | --- | --- | --- | --- |
| 1 | 09:16:31.431–09:17:17.297 / 45.865955 s | 0 | 37 | 699.965573 / 99.994416 ms |
| 2 | 09:19:09.051–09:19:54.766 / 45.714625 s | 0 | 25 | 466.650951 / 49.995000 ms |

SwiftUI Long Updates GUI summaries: run 1, 344 / 1.52 s total / 4.41 ms average /
44.60 ms maximum / 151.03 ms downstream maximum; run 2, 212 / 895.35 ms total /
4.22 ms average / 43.09 ms maximum / 74.88 ms downstream maximum. These are not
Home-only body counts or exact function self-times.

Neither navigation recording reports a >250 ms potential hang. Shorter frame
hitches remain; this is not zero-jank or all-app responsiveness proof. Changing
live catalogs and interaction counts preclude a controlled speedup percentage.
No giant SwiftUI/time-profile export was needed for these no-hang intervals.

## Actual Watch Two interaction, approximately 09:20–09:25 AST

The six-row picker accepts two selections and immediately shows preparation.
Two football broadcasts decode and advance simultaneously: catalog Aston Villa /
Crystal Palace and Brighton WFC / Charlton Athletic WFC. The Villa broadcast is
women's football; this is not evidence of a men's Premier League fixture or
independent fixture/cohort certification. Initial Source 1 stalls are observed,
then Source 2 and subsequent manual Source 1 / 2 choices decode.

- Independent source sheets and selection work for both panes. Changing one
  source does not replace the other match or release its paused state.
- Persistent Pause / Play works for each pane. Brighton holds at 39:48 while
  Villa changes source; Villa holds at 22:06 while Brighton changes source.
  After resuming, both clocks visibly advance over repeated observations.
- Swapping panes preserves each match's selected source and visual audio-focus
  state. Equal / Focus layouts work and Focus source labels remain on one line.
  Layout changes briefly reload video before recovery; no seamless/no-reload
  claim is made. Fit / Fill changes framing and is restored to Fit.
- Close returns to Home; a fresh final native capture confirms full dismissal.

Provider source clocks differ, so advancement does not imply uninterrupted clock
continuity across switches. Audio-focus controls were visually inspected, not
audibly qualified. PiP/background soak, audio teardown, compact iPhone, portrait,
accessibility text and every provider variant remain separate acceptance gates.
No FPL feature work or FPL-tab interaction was performed in this pass.

## Evidence, resources and distribution boundary

Apple UI and staged iOS performance guidance required actual native interaction
and matched-device measurements instead of a build-only claim. Documentation
is outside the frozen build input. Compact results replace disposable raw
recordings and exports; 1.44 GiB of owned temporary builds, preferences, logs and
traces were removed after recording this evidence. Final disk check: 34 GiB free.
Disposable output can be regenerated from the retained source receipt; raw
recordings were not retained. Immutable receipts and unrelated user data/caches
remain. No TestFlight upload, Git publication, backend deploy,
tester changes, simulator or spending change.
