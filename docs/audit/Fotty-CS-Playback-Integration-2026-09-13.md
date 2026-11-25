# CS playback/source integration check — 2026-09-13

## Scope

Owner clarified that the recent changes mean the optional CS source lane and
playback, not FPL. CS must join the ordinary match's source list, use Fotty's
existing player/controls, retain CS labels and source attribution, and allow
switching back to an ordinary source. No FPL, fixture-service or UI redesign work
belongs to this check. No install, TestFlight upload or version allocation here.

## Confirmed faults and local corrections

1. **Delivery classification:** a CS `/watch` page containing a nested `.m3u8`
   URL was classified as native media. Classification now examines the endpoint
   path and preserves typed HLS/MP4 sessions. Main playback and MultiView share
   that policy instead of independently guessing from full URLs.
2. **Native recovery ownership:** native failures could invent a web fallback
   for an HLS endpoint. Explicit direct media now gets one native startup retry
   before exhaustion. A genuine captured web-to-native handoff still returns to
   its original page. Legacy unknown-mode fallback now actually releases the
   native player when switching to web, matching the rendered owner.
3. **Late validation:** cancelled native validation could replace an item or
   install observers after a source switch/dismissal. Both players recheck task,
   attempt and source ownership immediately after validation.
4. **Native controls:** build 97's passive callback assignments fixed the
   demonstrated SwiftUI feedback/watchdog loop. PiP requests also needed to leave
   `updateUIView` before invoking callbacks; queued/superseded requests and
   dismantled surfaces are now invalidated. Source reload clears old PiP requests.
5. **Missing CS options:** absence/failure of a sport-specific catalog prevented
   fallback to the advertised Live catalog. Lookup now tries that bounded
   alternative, still requiring the exact sport, team pair and kickoff.
   Cancellation, unsafe responses and conflicts never trigger that fallback.
6. **Conflicting IDs:** filtering before deduplication erased a contradictory
   row sharing the requested stream ID. Consistency now covers all rows for that
   ID before a matching row can be admitted, including differing video IDs.
7. **Attribution:** web-to-native handoff now merges, rather than discards, source
   metadata. Bounded local quality events carry source family, label, attempt ID
   and an opaque CS key; they do not carry URLs, headers or raw upstream hints.

## Label and tracking meaning

- Users continue to see CS1, CS2, etc. alongside ordinary Broadcast options.
- CS numbers remain positions within the returned set, not permanent upstream
  assignments. A hidden `cs_<24 hex>` key survives ordering changes when the
  add-on provides a bounded descriptive source hint. Without one, the key is
  delivery-specific and may change when signed URLs change. Scope is retained in
  session metadata; neither kind is a promise of source uptime.
- Positive health remains coarse provider-family/host history, like ordinary
  variants. One failed match does not globally penalize all CS streams. Retries
  and failed-source exclusion belong to the current player attempt.
- The module remains opt-in. CS catalog rows do not become fixture authority.

## Verification

- First focused gate: 181 tests passed, zero failures, one explicitly opt-in
  reference-HLS soak skipped; unsigned generic iOS Release compilation passed.
- Final gate after sharing routing with MultiView: 181 tests passed, zero
  failures, one intentional reference-HLS soak skip. Generic iOS Release build
  passed. The first MultiView regression compile required an explicit
  `@MainActor` annotation for its event fixture; corrected before this passing run.
- Regressions execute the real player owner with cancellation-insensitive
  validation to prove that late work cannot start an orphan player. Tests also
  exercise PiP callback scheduling/teardown, CS web routing without native I/O,
  bounded native retry and actual adapter URLSession calls intercepted by local
  URLProtocol fixtures. They are not assertions that a remote URL is playable.
- Fresh read-only Jet iPad check: installed version remains 2.0.0 (97). The only
  listed Fotty incident is the already diagnosed build-95 watchdog. An absence
  of newer crashes does not prove that a CS source or controls were exercised.
- Earlier time-scoped public add-on checks returned both HLS and web responses.
  An HTTP 200, HLS signature or HTML shell is not decoded playback proof.
- Catalyst reported warnings for the existing synchronous audio-session
  activation path on the main thread. This gate did not profile or migrate that
  app-wide audio owner. If physical control latency remains, capture the current
  build's stack/timing rather than assuming another provider failure.
- No simulator or old installed Mac app used. Tests build the current source as
  Catalyst. Heavy work is sequential; gate-owned DerivedData/result bundles are
  removed on exit. No production backend or tester changes.
- Final cleanup verified: no active gate output remains; 70 GiB available before
  and after the final gate. Pre-existing user artifacts/caches are untouched.

## Remaining acceptance gate

Allocate a new unique private build and install only on the owner-authorized Jet
iPad in a separate requested device gate. On a currently live match:

1. With CS enabled, confirm its options appear in the existing source picker.
2. Select an admitted native CS option; verify advancing picture and audio.
3. Reveal controls after they hide; pause, resume, open Sources and switch to
   another CS option, then StreamEx. Repeat during loading and after 15 seconds.
4. Where supplied, repeat with a CS web option, retaining provider controls and
   no duplicate audio. Close playback while loading and reopen another match.
5. Exercise native PiP, app switching and lock/unlock for 60 seconds. Confirm the
   same source keeps advancing and system Play/Pause works.
6. Inspect current-build failures and local attribution. Do not declare CS
   reliable merely from successful resolution, unit tests or a launch hold.

## Relevant primary references

- [Apple UIViewRepresentable lifecycle](https://developer.apple.com/documentation/SwiftUI/UIViewRepresentable/)
  defines the creation, update and dismantle boundaries used by the native bridge.
- [Swift cooperative cancellation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
  explains why cancelling a task does not replace checking ownership after an
  awaited operation before performing playback side effects.
