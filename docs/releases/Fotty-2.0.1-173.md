# Fotty 2.0.1 (173): recent single-stream startup ranking

24 October 2026. Private Jet iPad build; no phone, FPL, multi-stream,
backend, Git publication or TestFlight changes.

## Selection repair

Old selection could prefer hundreds of slow historical starts over one recent
fast start. Old successes never expired, and the last-good family bonus could
outweigh several seconds of startup time. That history is positive confidence,
not a measured uptime or success rate.

New single-player destinations explicitly opt into a separate ranking policy:

- Use at most12 recent decoded-start observations, valid for seven days.
  Timestamp and latency are the only added fields in the existing local store.
- Prefer the median measured startup, in500ms buckets. Confidence is capped at
  three observations and can only break a speed-bucket tie. A fresh old-format
  average bootstraps as one weak observation; stale/future/invalid samples do
  not establish measured speed.
- Prefer actual direct-media contracts over webpages when otherwise tied;
  last-good context is a late tie-break, never an AS-specific override.
- Keep every admitted choice available. Exclude the current/exhausted source
  IDs within the active attempt; do not create cross-fixture family bans.
- Apply only before a new single owner starts and during its single-stream
  failover. Never rerank/reload a retained, preparing, playing, manual or retired
  owner. Shared initializer and Watch Two ranking APIs/scoring remain unchanged.

AS is not hard-coded first. A better measured delivery can outrank it. Existing
coarse family-plus-host history does not distinguish every upstream or measure
failure rates. No new media/trust/header/redirect/fixture rule was introduced.

## Local verification

Nine new store regressions and five integration regressions cover fresh fast AS
versus slow legacy history/last-good, median/outlier/bounds, malformed/stale/future
observations, actual native contracts, stable ties, missing latency, retained
manual owners, shared initialization and attempt-local failover exclusions.

The focused Catalyst suite reports **332passed,0failed,1skipped**, with no runtime
warnings. The one skip is the intentionally disabled reference-HLS soak requiring
`FOTTY_PLAYBACK_SOAK`, not a playback pass. Four selected classes: source health,
viewing coordinator, retry lifecycle and playback policy. The initial signed
Catalyst invocation had no Mac provisioning profile; the normal unsigned local
unit path then passed. An Xcode compile diagnostic with exit0 did not correspond
to a failed test; final xcresult is authoritative. No simulator was used.

Provider identity vectors, native source membership, version coherence and
focused diff checks pass. Signed normal Release173 builds and its strict/deep
signature verifies. It was installed in place and independently read back as
2.0.1(173), then launched without test arguments or synthetic production history.

## Jet observation, not blanket playback qualification

At19:03UTC, the independent ESPN Serie A scoreboard reported Lazio–Parma in
progress, dated24October18:45UTC (18′). Normal Home Watch selected AS1 from six
choices without forcing a provider. Discovery's AS success took1,412ms; the
native attempt started19:04:09.182UTC and recorded decoded progress at
19:04:11.116UTC: **1,933ms**. The correct CBS Lazio–Parma programme was visually
observed, and the ordinary picker showed AS1 selected.

The owner subsequently compared AS and web choices on the same iPad. Additional
successful AS records were1,336/1,300/1,435ms, whereas sampled web attempts had
document-loaded/media-observed stages. These are observed starts, not a controlled
head-to-head throughput, uptime or audible-output benchmark. Manual source
changes occurred during the preview checks, so this is **not** an uninterrupted
90-second same-owner hold or native-fullscreen/PiP acceptance pass.

Device Hub supplied stale/black frames during the control check; a device
screenshot also captured a black surface. A later observation showed correct
advancing programme video. Concurrent manual changes and missing lifecycle proof
prevent attributing this to a confirmed presentation defect. No speculative
fullscreen/transport fix was made. Stop remote interaction once owner testing
is apparent. Fullscreen/PiP and the earlier CS PL/UCL gates are not newly closed.

## Additional AS-like leads

See the dated section in the new-source audit. Flix-Streams Free is the strongest
new protocol lead: public no-config manifest, explicit UTC football metadata and
HTTPS HLS descriptors. Actual in-app playback, current coverage and upstream
independence are unverified. No additional source was enabled or declared reliable.

## Preservation and artifact receipt

All52 protected FPL/multi-stream file hashes, four private FPL values and all five
existing source-enable choices compare unchanged. AS remains enabled on Jet.
No UI-test runner was installed in this gate. Phones/shared TestFlight remain
unchanged. No real Git index/refs/remotes changed.

Pre-build receipt:1140 inputs; history-free temporary commit
`6e9d0274052d46b7bb2a5d30f59ebb83ca05f58d`; source SHA256
`ebd941730478354a19b40be7b4608e3de196c4d2ba38a633b6204e55623f0b0a`;
bundle SHA256 `4d3c606fad2fd6a8eeb84075e38ee22bf4a6694a95b45775e45075cd8fe4b653`.
Signed normal executable SHA256:
`9b819c245ae39f8620b4cd78fec377fa8b39cdb8427ec29e5797eb051a02245b`.
Frozen-source comparison passes before closeout documentation edits.

The926MiB owned gate (build/results/source snapshot/copied preferences/device
screenshot) and its keep-awake helper were removed; absence verified. Final disk
readback:18GiB free. Unrelated artifacts/caches were preserved. Local memory
size/reference/export/privacy checks pass. This private build is not a shared
distribution candidate.
