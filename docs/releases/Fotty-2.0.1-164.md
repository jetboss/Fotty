# Fotty 2.0.1 (164): single-stream recovery and CS diagnostics

19 October 2026. Private Jet iPad build only. No TestFlight, phone activity,
multistream feature/testing work, FPL changes, remote Git publication, backend
deployment, new source, trust exception or paid change.

## Repaired app defects

- Empty CS catalogs formerly remained cached for 120 seconds. Empty results now
  expire after 15 seconds; populated catalogs retain their existing 120-second
  lifetime. A clock rollback invalidates a cache entry. A late, superseded actor
  response cannot overwrite a newer catalog generation. No polling/retry is added.
- CS diagnostics formerly conflated an absent exact fixture with an exact fixture
  returning no streams. `no_exact_fixture_match`, `stream_entries_empty` and
  `no_admitted_stream_delivery` are now distinct. The last two retain bounded
  counts only; matching, labels, delivery admission and source safety are unchanged.
- A native fatal item event in background was discarded before persistence.
  Single playback now immediately records the exact item's local failure once,
  without background reload/failover/Play. Foreground recovery consumes that exact
  incident once using the existing bounded retry policy. Pause and replacement
  never inherit recovery. Ready displayed progress after the latest fatal
  boundary retires the incident, including after a paused foreground visit; it
  neither cuts recovered video nor hides a later independent failure. `.playing`
  alone and progress before a newer fatal event cannot establish recovery.
- Detached fullscreen markers can report a false background flag. PiP callbacks
  now also respect the model's actual background state. Existing explicit Pause
  and source/item/attempt/presentation ownership remain authoritative.
- Native startup observation can legitimately end after early Pause/Play or
  foreground intent renewal. Those exits now record finite reasons. Existing
  resume/watchdog samples can record the first subsequently displayed progress,
  without adding a timer, transport command, retry, health success or fake latency.
- Repeated Web owner starts within one attempt formerly inflated source-health
  successes and startup latency, despite the existing usage summary grouping by
  attempt. Single playback now admits initial metrics once per source/attempt,
  while retaining every existing recovery/UI effect. A new attempt gets a new
  sample; native adoption gets one separate handoff receipt. A still-Web callback
  during native preparation is not mislabeled as an adopted handoff. Multistream
  bookkeeping remains unchanged.

Native fullscreen now records up to 13 finite presentation edges once per exact
borrowed lease in the existing 250-record local quality store. These cover actual
presentation, PiP start/stop/failure, Restore and finite finish causes. They contain
opaque identities/scalars, not stream URLs, headers, media or an uploader. Repeated
cycles of the same edge within one lease are deliberately deduplicated; this is
not a complete event timeline or proof of decoded playback.

## Verification and provenance

- Final simulator-free gate: **1,569 passed, two existing optional skips, zero
  failures / 1,571 total** in a freshly compiled Catalyst unit host. Generic
  unsigned iOS Release and signed Release pass. Strict app signature, app/extension
  version 164, Jet installation/readback and normal launch pass.
- 32 native-source tooling tests, 13 source-snapshot tooling tests, 35 Node
  lab/performance-verifier tests, five provider identity vectors and native
  membership/version checks pass. The eight-scenario/27-selector lab source check
  is not itself physical execution. Existing FocusState and test-window Catalyst
  deprecation warnings remain. An initial new-test compilation typo was corrected
  before the clean final r4 gate; no production assertion was weakened.
- All 42 FPL hashes and the three captured multistream-specific source hashes are
  unchanged from this task's baseline. Shared121 and phones125 are unchanged.
- All 1,119 frozen inputs compare before installation and after device checks,
  before these documentation-only closeout edits. Temporary private-test source
  receipts are not a retained shared-distribution candidate.

Final r4 source SHA256:
`6fd11fb9342f4eeb4971dadbc01fe4b264018b128fd678863d0272dcf0adc4cf`

History-free temporary snapshot commit:
`1524e8af8cf45a7b3b98ef51c4cdbcfb6cb61b1b`

Temporary bundle SHA256:
`7e7e5a85de1f85c2b4e50791de482e65ac16b02f168cb34431b93f3631ba33fc`

Signed executable SHA256:
`e82f4ea3196e1e95af28e78dc5677a1a8282406b294c9bf529cb056018067988`

## What happened to CS

CS remains enabled in Jet's existing settings. It was not removed. Fresh catalog
checks at 19:41:20/21 UTC contain one exact Tottenham Hotspur–Coventry City fixture
at 19:00 UTC, matching the current official kickoff. Aliases agree; there is no
evidence justifying a wider kickoff window. Earlier populated catalogs, stream
descriptors and bounded HLS MIME/prefix reads were not decoder/continuity proof.

The fresh Jet163 lookup at 20:02:11 UTC reaches the stream-list stage but times out
in 7,983 ms. Jet164 repeats `streams_transport_failure`, URL -1001, at 20:07:43 UTC
in 7,156 ms. A second named match, Parma–Torino, reaches that same stage and times
out at 20:15:05 UTC in 7,106 ms. These are not “no matching fixture” receipts.

A separate, bounded Mac check finishes at 20:10:11 UTC: manifest HTTP200/319 ms,
football catalog HTTP200/49 ms, then the exact Spurs–Coventry stream-list request
times out at 9,005 ms. Exactly three metadata requests; no media downloaded.
This corroborates a current upstream stream-resolution slowdown, not an iPad-only
failure or universal/permanent CS outage. No timeout, matching, trust or HLS
normalization workaround is added. Existing 163 CoreMedia URI-change/stall evidence
remains separately dated; it is not the cause of these discovery timeouts.

## Actual Jet164 single-stream results and remaining gate

Normal source resolution/player feedback and the source sheet work. Initial
regular-provider Web attempts include real 20-second startup failures and bounded
retries/fallback; this is not a clean startup-latency pass. An admin Web attempt
`D512CDB9` records decoded progress at 20:09:01 UTC, then a later startup-classified
failure at 20:09:37 UTC. A legitimate document replacement can rearm that timeout
under the same attempt; current receipts do not prove that replacement occurred.
Review found no confirmed stale-initial-timer defect. Do not claim provider-only
causation, a clean uninterrupted attempt, or silently suppress the failure.

Score808 attempt `65549DE6` decodes at 20:09:57 UTC. Actual football advances from
49:45 through 50:34. Explicit Pause holds the exact visible 50:58 frame for more
than a minute without auto-resuming; Play returns to advancing football at 52:51
and 53:12. Its retained initial decoded receipt remains one. Source selection is
responsive. A manual Parma–Torino source change also returns to video, but the
sample includes buffering and late decoded recovery after a startup failure;
do not call that sustained playback qualification.

No CS native choice is available in these fresh lookups because of the confirmed
stream-list timeouts. The sampled Web menu has no compatible native handoff action;
repeated provider fullscreen taps do not establish an actual AVKit presentation.
**Current native fullscreen, >60-second background PiP, system Pause/Play/Restore,
inline return and audible acceptance remain unqualified.** Controlled tests and
older build160/163 visual evidence do not close those gates. The single-stream
end-to-end qualification is therefore not complete or TestFlight-ready.

Device Hub required a mirroring-app/session reset before useful taps resumed;
transient controls must be exercised before they auto-hide. No-op mirror input
was not treated as an app hang. Physical XCTest/xctrace limitations from162 are
not new performance proof. REA native providers remain unconfigured.

Test media is stopped; Jet is back at All sports/Home in its original Light
landscape configuration, keyboard capture off, CS still enabled and sports sync
off. Owned temporary build/results/source bundles/private preference copies are
removed after this compact evidence is recorded; no user caches or saved FPL
data are removed. The scoped awake process is stopped. No shared release occurs.
