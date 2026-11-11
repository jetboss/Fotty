# Fotty 2.0.1 (161–162): playback foundations, private Jet qualification

19 October 2026. These are private owner builds, not a TestFlight release.
The owner explicitly prioritizes stable single-stream playback and reliable
sources; Watch Two/multistream work and physical testing are deferred until last.
FPL, phones, shared build 121, remote Git and backend deployments are unchanged.

## Five implemented foundations

1. `tools/testing/playback-lab.mjs` defines eight controlled scenarios using 27
   actual XCTest selectors. Real loopback-relay tests cover delayed/split data,
   typed HTTP failures, an expired segment followed by same-capability recovery,
   range/header scope, cancellation and stale A→B→A attempt ownership. URLProtocol
   supplies bounded upstream fixtures; these are not public-stream uptime tests.
2. `StreamPlaybackContract` separates declared endpoint/container from observed
   MIME and a bounded byte prefix. Probe evidence is ephemeral, not Codable.
   HTML containing a playlist marker is rejected; byte-oriented CR/LF parsing
   handles actual CRLF/BOM without treating declarations as codec/PiP proof.
3. `NativePlaybackPreparation` owns scoped delivery/item factories, not Play,
   audio activation or permission to replace an owner. Single Web-to-native
   preparation now validates the same cookie-scoped relay given to AVPlayer,
   rather than losing WK cookies through a separate direct request. Failed
   candidates preserve the original Web owner and stop their own delivery.
4. Each relay retains at most 32 memory-only request receipts: opaque relay,
   resource and request IDs; finite method/category/phase/status/outcome; monotonic
   duration/age. Completion follows actual content processing; cancellation and
   deadline callbacks are exact-owner fenced. Atomic summaries distinguish an
   older failed resource from later same-resource completion. No private URL,
   headers, cookies, body or per-request persisted log is added. Correlation does
   not prove the newest request caused an AVPlayer failure.
5. Source-health queries reuse a queue-owned decoded snapshot keyed by exact
   UserDefaults bytes. External replacement/removal invalidates it; malformed
   data is retained, not erased. Controlled tests show 20 queries and 64 concurrent
   reads each require one decode. Home adds deduplication/discovery child signposts.
   This is a measured decode reduction, not a physical frame-rate improvement claim.

162 additionally captures the single handoff candidate's actual item status,
bounded native error chain and its own atomic relay snapshot before cleanup.
The failure-time snapshot cannot be overwritten by later defer/relay shutdown.
Two regressions cover exact candidate ownership and explicitly unknown causes.

## Build and local gates

Final 162: **1,529 tests passed, two existing optional skips, zero failures**
(1,531 total), using a freshly built Catalyst unit host, not the old installed
Mac app. Thirty-two native-source tooling tests, 35 playback-lab/performance
verifier Node tests, five provider identity vectors, source membership/version,
generic unsigned native Release, signed Release and strict signature checks pass.
All 42 FPL source hashes equal the task baseline. The existing FocusState test
warning remains. Exact Jet iPad Air 4 / iPadOS 27.0.1 readback shows 2.0.1 (162),
and normal launch succeeds. No simulator was used.

The first 161 run exposed a real CRLF parser error and two obsolete/test-fixture
assertions; these were corrected before the full passing rerun. Corrected 161
passed 1,527 tests plus two optional skips. These failed initial runs are not passes.

Frozen 162 pre-build receipt, 1,117 inputs, verified before installation:

- Source SHA256: `7d9427b00841cefc3dfd09514278b872a9fb5cc9cee034667d69c487004f6a96`
- History-free snapshot commit: `34f5ea8c2b9c7c00a9c1bbeed6d55bc9fda09bcd`
- Temporary bundle SHA256: `09533bc01be0a4fd8fb652ce689ec55a34a34cdf7284ad8db328c59b3fc4b249`
- Signed executable SHA256: `9683ebdd22a0dc4c64b86137c8abeaf7c6309f3ddde847aa12c7f56588169567`

The receipt/bundle is task-owned temporary private-test output, not a retained
shared-distribution snapshot. Subsequent 163 source changes are separate.

## Actual single-player observations on 162

At approximately 18:03 UTC, Monza–Cagliari CS discovery records a stream-metadata
timeout (-1001, 7,204 ms), while the other three broadcasts remain available.
Independent bounded metadata checks subsequently return the exact team pair,
16:30 UTC kickoff and 27 stream descriptors. One fresh in-app lookup at
18:06:54.717 succeeds in 6,206 ms, showing nine total options including six CS
choices. This is intermittent metadata responsiveness, not an identity regression.
Earlier 161 checks at 17:32 found genuinely empty Football/Live catalogs; they
recovered at 17:58. Metadata recovery alone was not counted as decoded playback.

Explicit CS2/native, attempt `18F492A6`, decodes in 7,688 ms. Actual football
advances from 77:42 to 78:07. At 60.4 seconds the native item fails to play to end:
URL -1102 / underlying CoreMedia -12660, accompanied by the exact relay media GET
HTTP 403 aged 78 ms (17 completed, one failed, one in flight). This records a real
upstream response, but does not establish why it denied that request.
Same-source retry `CDD8B49B` decodes in 12,903 ms. Actual Apple fullscreen opens;
Pause holds 80:13 across separate observations, and Play resumes through 81:26.

That retry later stalls at 18:13:11.737, with CoreMedia -12312 / segment URI
changed. Its last relay 403 is then 253,995 ms old, with zero failures in the
retained 32-request window; it is not evidence of a new terminal 403. Failover
CS1 initially reaches ready but times out before decoded progress. These are
real failures, not uninterrupted-playback or provider-only claims.

PiP preparation callbacks occur, but floating decoded video and background
Restore were not verified. During this journey fullscreen can remain attached
while retry/failover mutates its reused AVPlayer. Independent source review
confirms a **real ownership defect**: callback guards reject the old attempt,
but deferred SwiftUI reconciliation does not synchronously detach the old AVKit
controller before item replacement. 163 is a focused repair/qualification for
that defect. Do not mark 162 fullscreen/PiP fully accepted.

161's dated observations include responsive Home/Matchday movement, a committed
Search query with the original Golf query restored, and advancing regular
Broadcast 2 Web video. An explicit native conversion safely rejects readiness
while Web continues; that is not a positive native-conversion pass. No further
multistream tests are authorized in this priority batch.

## Physical automation and tools limits

Physical XCTest repeatedly waits about 60 seconds per touch on system
ScreenshotServicesService/SpringBoard animation completion before useful metric
sampling. A fresh run without Device Hub and one public-coordinate canary repeat
the problem. The canary is reverted; no private event/quiescence/animation bypass
is introduced. These attempts do not qualify CPU/memory/hitches. SwiftUI xctrace
attachment also failed before a usable trace; no before/after speed claim exists.
The task-owned UI runner was removed from Jet and absence verified.

REA is connected but its native Ghidra/Hopper/IDA providers are not configured.
No native decompilation/runtime proof is claimed and no heavy tool was installed.

## Additional-source research, not activation

- Official selected-event YouTube embeds are a useful separate basketball lane:
  [FIBA Europe Cup](https://www.fiba.basketball/en/events/fiba-europe-cup-26-27/news/everything-you-need-to-know-about-fiba-europe-cup-2026-27).
  Follow [YouTube requirements](https://developers.google.com/youtube/terms/required-minimum-functionality),
  including official embedding/identity/attribution. This is not native HLS or
  promised PiP parity, nor a PL/CPL replacement.
- User-owned authorized M3U/Xtream/XMLTV inputs are a separate opt-in design:
  [IPTVnator](https://github.com/4gray/iptvnator),
  [NexoTV](https://github.com/joaosavi/nexotv). Infrastructure supplies no content;
  credentials, transport, EPG identity and privacy need their own review.
- [USATV Next](https://github.com/yowmamasita/usa-tv-next) is not a vetted exact-
  fixture replacement; current metadata/playback issues and delivery/authorization
  questions remain. Do not enable it from this research.

Stremio's core/add-on/video contracts informed incremental boundaries; no engine,
dependency or third-party source code was copied into Fotty. No new provider,
origin/port trust, paid service, server telemetry or cloud deployment was enabled.
