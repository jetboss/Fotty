# CNC/CS review and native preparation repair — 28 October 2026

Scope: Jet iPad single-stream playback only. Phone, FPL, multi-stream, source
defaults, shared TestFlight, Git publication and cloud deployment are excluded.

## Confirmed app defect and focused repair

During a real CS1 live MLB hold on build 183, native playback reported
CoreMedia -12312 with `segment_uri_changed`. Preparation for its bounded retry
retired the old relay before awaiting a fresh descriptor. Backgrounding could
interrupt that await, leaving the old item apparently ready. Foreground then
resumed that retired item under the new attempt and stalled for about 80 seconds.

Build 184 keeps an owned, single-stream preparation lease. Backgrounding detaches
the retired item and defers preparation; foreground or explicit Play resumes only
the matching request/source. Pause retains the paused intent. Cancellation,
replacement and cleanup revoke the lease. Actual transport expiry and bounded
retry counters remain enforced. Starting preparation while already backgrounded
uses the same deferral path. No relay or global admission rules were changed.

This repairs the confirmed foreground race. It does not assert that Fotty caused
the upstream HLS segment inconsistency or that the repair prevents provider faults.

## Local verification

- CS suite: **117 passed, 0 failed, 0 skipped**. Includes next-day publication,
  corrected same-ID explicit refresh, squad, time-tolerance and conflict cases.
- Native preparation/fullscreen and five focused PiP policy tests: **75 passed,
  0 failed, 0 skipped**, including seven new preparation race regressions.
- The two counts are separate runs, not a deduplicated total. Final native run
  follows the final VM patch. An earlier new-test fixture used an unadmitted
  placeholder label; replacing it with the real CS4 contract yielded the final
  pass without weakening admission or assertions.
- Signed iOS Release 2.0.1(184) compiled successfully. Main app and widget agree;
  strict deep signature passes; all 314 snapshotted inputs and 43 protected FPL/
  multi-stream feature hashes match. One bounded DerivedData directory was used.
- [Independent read-only review](independent-review.md) found no additional defect.

## Source findings

[CNC/CS findings and research](research/source-findings.md) distinguish upstream
evidence from app defects. CNC's newly advertised delivery still returns an empty
25-byte HLS shell with no variants or segments, both with advertised and relay-safe
headers. No new host/header exception was enabled. The disputed CS NHL publication
explicitly dates the official current pairing 24 hours late in both catalog and
same-ID metadata. Its date rejection remains correct; no date shift was added.

## Physical gate

**Build 184 is installed, without a launch or new physical playback test.** After
compilation the owner reclaimed Jet for X, declined the new takeover request and
explicitly requested installation only. The in-place install passed strict
signature/profile checks and normal-app version readback. All 34/34 preference
slots were unchanged before launch (Fotty was not launched). Phone and TestFlight
remain untouched. See [installation receipt](install-verification.json).

The final live playback/fullscreen/PiP round trip for 184 remains pending by owner
instruction. No build 184 source qualification or readiness pass is claimed.

Build 183's earlier normal-app CS1 test did decode the correct World Series
programme for more than 90 seconds and passed fullscreen pause/inline return/
reentry/resume. PiP advanced in another app for more than 60 seconds, but a later
transport failure interrupted the round trip and exposed the repaired race.
That is not a build 184 pass. The current MLB fixture is useful for general native
controls; it does not qualify Premier League, Champions League or cricket coverage.

No audible-output claim, continuous pixel-buffer instrumentation, new CNC
qualification or fully resolved CS publisher-date claim is made.
