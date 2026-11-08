# CS metadata and registry repair — private 3.0.0 (234)

## Outcome

Three native matching/availability defects repaired. Normal Jet Home Watch reached CS1 for the officially live United Arab Emirates–Oman ODI on 4 November. **Decoded playback did not pass:** the advertised child HLS playlist returned HTTP 403, corroborated outside Fotty with the advertised headers. No compatible independent alternative was returned for that match. Do not report this as a 90-second playback pass, or as all CS deliveries being fixed.

## Confirmed defects and repairs

1. **Generated metadata clock versus source lifetime.** Native CS same-ID validation rejected generated listing timestamps after 600 seconds while the reviewed registry and original publisher accept/cache those listings for 14,400 seconds. Use the existing four-hour source lifetime only for the reviewed dynamic current-listing contract. Keep exact ID/pair/envelope validation and the independent ten-minute official LIVE receipt.
2. **Independent official refresh clocks.** Registry matching compared a newer cloud link expiry against an older but still-current device observation. Reproduction failed at 240/300/599 seconds official age. Validate independent expiry bounds; adapter binding expires at the earliest source, generated-listing, registry, local official or 90-second descriptor boundary.
3. **Cold preflight falsely withdrew a later registry association.** On-device trace showed registeredCount0 during CS preflight, then rawRegistryCount1/eligibleCount0 after the delayed registry arrived. The undated generated-clock catalog miss had become a definitive provider absence. Join the existing shared registry refresh inside the CS lane; the eight-second preflight owner retains cancellation. An unassociated current-cricket catalog miss releases its ticket without withdrawing a separately joined exact ID, including when a cached official receipt is awaiting refresh. This does not grant playback authority to stale metadata. Scoped empty descriptors, conflicts, incompatible contracts and HTTP rejections retain their existing failure handling.

Source locations: `CommunitySportsAddonClient.resolveRegistered/currentCricketListingIdentity`, `BroadcastRegistryMatch.matches`, `LiveStreamResolver.optionalRegistryMatches/isUnassociatedCurrentCricketMiss`.

## Verification

- 230 focused native tests executed: 228 passed, 2 optional external-production-snapshot tests skipped, 0 failed. Covers CS contracts, registry matching/integration, and discovery-index negative evidence. The independent-clock initial failing test is retained as historical evidence in Plan.md.
- Cold-start regression uses a delayed injected registry owner, verifies one fetch, exact returned identity and visible Watch eligibility after the registry arrives. Separate assertions preserve conflicts, scoped negatives, HTTP 403 and expired official-authority rejection.
- Earlier unchanged backend checks: 99 passed. No backend deployment was required for these native defects.
- Signed Release 234 compiled. Final normal Release installed and launched successfully. At 11:05:44UTC Watch was visible immediately after cold launch; it remained visible after background refresh at 11:06:10UTC. All 16 protected preferences and 42 excluded source hashes were unchanged. See checks.json and preservation.json.
- Temporary fixture-specific diagnostics removed. No phone, FPL, multi-stream, opt-in, Git/cloud publication or TestFlight changes.

## Physical evidence

Official ICC: UAE–Oman, ODI, ICC CWC League 2 Match 145, start 2026-11-04T05:30UTC; original fresh schedule said Play In Progress. Registry current-event association and original same-ID CS metadata corroborated the exact pair.

- 10:36:56UTC: normal Match Details Watch found CS1. Both native attempts failed before decoded pictures; master 200, child 403, zero media bytes.
- 10:38:47UTC: original advertised master 200/HLS; original advertised child 403 with the same advertised headers. No media/access workaround applied.
- 10:58:39UTC: normal Release 234 Home displayed Watch after returning from TV.
- 10:58:49UTC: tapped that Home Watch. Exact CS1 discovery succeeded and the native player opened. Attempts at 10:58:58/59 failed on the same child 403; no eligible alternative. This is a successful normal-match routing check and a failed media acceptance check, not successful streaming.

`initial-watch-failure.json` and `release-watch-result.json` retain separate redacted failures. Source-discovery success must not be confused with decoded playback. Unit fault-injection telemetry around 10:51/11:01UTC is test evidence, not a new production provider incident.

Remaining gate: a current compatible provider delivery must show the correct programme and sustain native advancing pictures for 90 seconds through the normal Watch path. Do not substitute a generic channel tune or retry unchanged 403 contracts indefinitely.
