# Fotty Sports Hub 2.0.1 build 117 — measured catalog hot-path repair

4 October 2026. Owner-only optimized Release installed in place on Jet iPad
Air 4 / iPadOS 27.0.1 (24A446). Shared TestFlight 111 is unchanged.

## Confirmed cause and scoped repair

Matched-symbol analysis of 116's 883.536 ms refresh microhang found main-thread
catalog combination, fresh-match publication and Home projection work. Repeated
football alias normalization and ISO8601 formatter construction were material
inclusive costs, not provider lookup latency. Sample weights overlap and are not
function self-time. The independent 116 navigation capture also recorded eight
potential hangs (3,335.807 ms total, 675.028 ms maximum) and 21 app hitches
(716.627 ms total, 299.980 ms maximum).

117 prepares immutable football alias lookup tables once. Ambiguous canonical
IDs, official-name ordering and non-senior-team guards remain unchanged. Fixture
date parsing reuses a private locked formatter pair; existing timezone-required
validation and fractional/whole-second acceptance are preserved. No fixture
identity, admission, freshness, stream, scoring or persistence policy changes.

## Qualification and artifact identity

- 740 Catalyst unit tests pass, two intentional opt-in skips, zero failures.
  Four new tests cover legacy alias equivalence, collision/ordering behavior,
  parser compatibility and concurrent parsing. Six existing Catalyst audio
  warnings are not demonstrated iPad defects.
- Seven offline version tests, generated catalog check and five deterministic
  identity vectors plus three reachable live provider feed checks pass.
- Official Xcode 27; sequential jobs 1; unsigned and signed optimized iOS
  Release, strict nested signatures and three empty embedded provider keys pass.
  App/extension/source versions are coherent at 2.0.1 (117).
- Frozen pre-build receipt: `backups/release-source/2.0.1-117-owner-ipad`;
  989 files, default secret scan, round-trip restore and pre-install compare pass.
  Recovery commit `a4f51f6ffbfa953a1e818b0dd68f5fe4db425d5a`.
  Source SHA256 `699775572cd0a24220496d776b128ad5ad3b1a5f70cd6f371465b75960318fdd`.
  Bundle SHA256 `354ba9d8696f2fe0fe8db24f5ed0b8ece3b1bae75cc3cbc34b010b098c8c78fc`.
  This note and later follow-up repairs are outside that frozen receipt.
- Installed signed executable SHA256
  `e6fa9b0d76afa839fcc23736d95104a5eb310d71cba33623eb6cfd995df175ec`.
  Matched app/dSYM arm64 UUID `2C784E92-5FC0-3192-8197-8DDC5BD066D6`.
- Exact-device install/launch and both CoreDevice identity and visible Settings
  version pass. No uninstall, data reset, simulator or UI-test runner. Typed
  comparisons preserve appearance, home interest mode, local manager connection,
  reminders and one existing local review payload. No private IDs are embedded
  in the build or this note; SwiftData records were not separately compared.

## Actual device findings — not a full responsiveness pass

An app-scoped 45.895150 s SwiftUI/Time Profiler/Hangs/Hitches recording ran from
07:45:30.406 to 07:46:16.301 UTC−04:00, attached to installed PID 2977. Deferred
processing, high-frequency sampling, layout updates off and >250 ms potential
hang threshold match the earlier navigation capture. Real mirrored drag
scrolling and repeated Home/Matchday/Settings navigation visibly worked.

- Home: 23 body updates, 828.892743 ms total, 61.078208 ms maximum.
- Five main-thread Microhangs: 1,628.958875 ms total, 390.266667 ms maximum.
- Sixteen app hitches: 316.647828 ms total, 66.658416 ms maximum.
- Long updates summary: 179 updates, 1.58 s total, 61.08 ms maximum,
  191.54 ms maximum downstream cost.

These are descriptive results, not a controlled percentage improvement: fresh
fixture names and the recovered football verification warning changed between
captures. A transient warning was present earlier and recovered without being
hidden. Residual stalls remain real. Matched-symbol interval analysis found
repeated CPL fixture recognition/team alias normalization during Home ranking
and follows; the next focused repair targets that repeated pure matching work.

Watch Two's compact source labels fit in Focus, and the secondary source menu,
Equal layout, identity/session Swap and Close operated on 117. The two current
motorsport listings did not produce decoded match video in this check; retries
and failure UI remained responsive. This is control/failure-path evidence, not
two-live-match, audible audio, PiP or provider-readiness acceptance. Earlier 116
motocross Source 1/2 decoded and pause/source switching worked; do not transfer
that decoding evidence to 117's different listings.

## Resource and release boundary

One bounded build directory is reused for the ongoing owner repair gate. Raw
traces/exports, preference copies, signed apps and matched symbols are temporary
and must be removed after extracting the redacted gate summary. Immutable source
receipts and unrelated caches remain. No Git publication, backend deployment,
FPL feature work, tester changes, spending or TestFlight upload.
