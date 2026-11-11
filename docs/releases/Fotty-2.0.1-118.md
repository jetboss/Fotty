# Fotty Sports Hub 2.0.1 build 118 — scoped CPL hot-path repair

4 October 2026. Owner-only optimized Release installed normally in place on
Jet iPad Air 4 / iPadOS 27.0.1. Shared TestFlight 111 is unchanged.

## Repair and qualification

Matched 117 navigation stacks identified repeated CPL fixture/team alias
normalization during Home ranking. Build 118 prepares immutable per-team alias
needles once, normalizes the matching text once for all franchises, and stops
after two distinct matches. Category/channel guards, explicit CPL recognition,
alias boundaries, accents and punctuation retain the legacy behavior. No fixture
identity, admission, freshness, stream, scoring or persistence policy changes.

- 742 Catalyst tests pass, two intentional opt-in skips, zero failures. Two new
  bounded tests compare legacy matching/classification across all aliases,
  distinct/same-team pairs, channels, categories, punctuation and repeated calls.
- Seven version tests, generated catalog check, five deterministic identity
  vectors and three reachable live provider feed checks pass.
- Sequential unsigned/signed optimized iOS Release, strict nested signatures
  and empty embedded-provider-key checks pass. Version identity is 2.0.1 (118).
- Exact-device install/normal launch and installed/visible version identity
  pass. No uninstall, data reset, simulator or UI-test runner. Typed preference
  comparisons preserve appearance, Home/user settings, manager confirmation/local
  reviews and reminders in aggregate; SwiftData records were not separately
  compared. No private preference values or record payloads appear here.

## Frozen artifact identity

Final corrected pre-build receipt:
`backups/release-source/2.0.1-118-owner-ipad-verified`.

- Recovery commit `c3dc1eab6b4fd8bd84864220c2ca2aa1b55380c8`.
- Source SHA256 `7076395867741fb24a956d9d8009a570abcb81fec474cbdb82b520c0fa03a174`.
- Bundle SHA256 `a077638c1d79e6ad69fd0a35e709f73b96747b20bb87e1a7fbf8acfff160412f`.
- Installed signed executable SHA256
  `bbce51e9eb8d1191cf9f1a9c9c6308bf4587fd5600816484d18bf3f83774cb5a`.
- Matched app/dSYM arm64 UUID `5ED201B7-32A6-3D4A-8498-350E90E46B20`.

The earlier `2.0.1-118-owner-ipad` receipt is superseded: its tuple-test compile
failure preceded the corrected build and it was not installed. This note and
the subsequent 119 repair are outside the final frozen 118 receipt.

## Actual device findings — residual stalls remain

An app-scoped navigation recording of installed PID 3019 lasted 45.872082 s,
08:14:07.621–08:14:53.493 AST (UTC−04:00), with real Home scrolling and repeated
Home/Matchday/Settings navigation.

- Home: 28 body updates, 621.939448 ms total, 43.731708 ms maximum.
- Three main-thread potential hangs: 889.491083 ms total, 362.438917 ms maximum.
- Twenty-one app hitches: 483.305163 ms total, 83.325 ms maximum.
- Long updates: 192 updates, 1.31 s total, 43.73 ms maximum,
  116.10 ms maximum downstream cost.

Independent reference-aware matched-symbol analysis of all three hang intervals
found 8,782 running main-thread samples / 878.2 ms sampled weight. Disjoint Home
body work accounted for 218.6 ms and Home projection rebuilding for 139.8 ms.
Inclusive follow checks were 134.5 ms (80.2 ms body fallback, 54.3 ms projection);
CPL classification was 114.8 ms (91.1 ms Home body, 19.0 ms projection, 4.7 ms
Matchday). Home body stacks repeated ranking in `matchesContent` and `fullLineup`;
the CPL body cost also includes 25.5 ms from `catalogNotice`. Inclusive costs
overlap and are not function self-time or the complete cause of each hang.

These recordings are descriptive, not controlled percentage comparisons with
116/117. Build 118 is not a zero-stall responsiveness pass. A focused 119 repair
is underway to reuse time-independent facts across clock-only projection changes
while preserving content/score/selection invalidation and live timing updates.

## Watch Two evidence and boundary

The Rally panel decoded video and advanced 1:16.9 → 1:27.7. Pause held; choosing
a source only in the other Bahrain panel left the Rally panel paused. Play
resumed with visible progress 2:07.1 → 2:15.3 → 2:22.5 → 2:51.1. Focus, Equal,
Swap and Close fit, responded and preserved the decoded video behavior.

Bahrain Source 1/2 did not decode. This does not qualify two simultaneous live
matches, audible audio or PiP, nor establish provider readiness for both feeds.

## Resources and release boundary

One bounded build directory serves the ongoing owner repair gate. Temporary
build products, traces/exports, preference copies and symbols are to be removed
after the final repair evidence is recorded; immutable receipts and unrelated
user artifacts remain protected. No Git publication, backend deployment, FPL
feature work, tester changes, spending or TestFlight upload.
