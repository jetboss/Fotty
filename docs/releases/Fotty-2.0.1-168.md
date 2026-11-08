# Fotty 2.0.1 (168): additional-source qualification, not activation

23 October 2026. Private Jet iPad only. No phone, FPL, multistream, backend,
Git publication or TestFlight work. The additional-source milestone is OPEN.

## Implemented scope

- Add the reviewed Plavio Stremio adapter as an optional, default-OFF AS family.
  AS1–AS6 merge into existing exactly matched football source lists, not new
  fixture listings. No arbitrary add-on installation or automatic live inference.
- Admit only the reviewed manifest/resource contract, explicit English UTC date,
  exact sport/both participants/squad and kickoff within15min. Conflicting IDs,
  malformed identity siblings and effective-target conflicts remain vetoes.
- Initial media delivery requires the exact reviewed HTTPS443 HLS origin/path/
  single signed-query contract and no additional header/authentication contract.
  Preserve URL identity in memory; redact URLs/tokens from diagnostics.
- Keep CS metadata/schema/cache and delivery policy separate. Extract only its
  pure fixture matching into ReviewedSportsFixtureMatcher. Add a separately
  attributed bounded discovery lane, opt-in rechecks and local quality receipts.
- Preserve mandatory guarded-relay intent for headerless AS sessions through
  source copies and Codable. The relay, native player and transport restrictions
  do not gain origin/port/redirect exceptions. No codec/player engine is added.
- Plavio's known sfly/Leaf/Highfly ancestry is NOT proven independent upstream
  supply. Different admitted delivery is not equivalent to independent resilience.

## Research and device evidence

See the dated Stremio/CS audit for candidate details. SportsStreams sampled
dated events returned unavailable placeholders; LIVE-only timing was rejected.
StremVerse samples lacked dates, PPV's advertised API returned HTML, Nebula had
no verified public manifest, and BYO-playlist/self-host/torrent candidates did
not qualify as new native live supply. No paid services or accounts were used.

Plavio's observed manifest1.9.56 advertised103 sports rows/14 football rows.
The sampled Gimnasia y Esgrima de Mendoza–Platense row explicitly dated its
kickoff21:30UTC on23October. Its admitted HLS playlist returned200/840bytes,
EXTINF, no ENDLIST/KEY and advertised standard-HTTPS segment URLs. No media
segment was fetched on the Mac. This was playlist evidence, not a playback pass.

Physical decoder canary on Jet Air4/iPadOS27.0.1:

- The client resolves its actual dated source; the existing guarded relay and
  NativePlaybackPreparation supply the AVPlayer item. This intentionally does
  NOT insert a fixture or test the normal catalog source-picker journey.
- First run fails; a sleeping test watchdog throws CancellationError during
  teardown and obscures reporting. Replace it with a cancellable, nonthrowing
  work item and persist sanitized numeric evidence in XCTest attachments.
- Second run:39.950s, ready item/playing clock66.690s,18 completed media/relay
  requests, zero failures, zero decoded frames. Do not call this source success.
- Final run uses Apple host-time/display-link sampling and a temporary visible
  AVPlayerLayer, cleaned in defer. One initial build catches missing MainActor
  annotations on two nested test functions; fix and execute the physical test.
  It fails after40.095s:2325 display ticks/371 numeric output polls, zero buffer
  signals/frames, black layer/not ready,1920x1080 presentation metadata, ready
  item/playing clock61.640s,17 completed HTTP200 requests and no relay failures.
  HLS asset track loading reports0 while the item reports one enabled video
  track; neither is used to assert audio-only or a codec cause.
- A final one-request diagnostic check of the exact stream resource returns
  HTTP200 JSON136bytes with no admitted HLS. No playlist/segment/ffprobe follows.
  The codec and failure cause remain unresolved; no other fixture is fabricated.
- The sampled fixture is not in the current ordinary Fotty lineup, so a normal
  AS match-source picker test also remains OPEN. No fullscreen/PiP pass claimed;
  accepted165 loops were not needlessly repeated.

AS stays OFF. Do not tell the owner that working new streams were delivered.
Next evidence needed is a currently admitted source with real native decoded
progress, then its ordinary exact-match source selection on Jet. Provider
metadata alone cannot qualify that gate or justify weakening delivery checks.

## Local and installation verification

- Final focused Catalyst gate:239 total,238 passed, one explicit physical-canary
  skip, zero failures. Suites: PlavioSportsAddon, ReviewedSportsFixtureMatcher,
  CommunitySportsAddon, AdditionalSportsIntegration, SettingsUsability,
  OptionalSourceLookupPolicy, StreamDiscoveryCoordinator, LocalStreamProxy and
  FottyQualityStore. No simulator, FPL or multistream tests run in this gate.
-32 membership-tool tests pass; explicit membership187 app/60 unit/5 UI/5
  extension is coherent. Source YAML and four Xcode versions are2.0.1(168).
  Existing test-host Sendable warnings remain; not a warning-free claim.
- Final normal signed Release build passes with empty diagnostic log. App and
  extension168, strict deep signature verification, frozen-source comparison
  before/after installation, exact Jet install/readback and launch pass.
- Native Settings visually shows168. Broadcast Sources shows AS OFF and the
  owner's CS/Score808/StreamEx choices ON. FPL preference values and45 protected
  source hashes match the task baseline. Remaining preference changes are normal
  refreshed fixture snapshots and bounded local quality/source-health records.
  Home is restored; keyboard capture remains OFF. No test video surface remains.
- Stable Device Hub input works after closing its duplicate beta instance.
  This observed recovery is not proof of the original input-failure cause.

## Final-r2 source receipt

1130 frozen inputs compare before/after installation, before documentation-only
closeout. The temporary history-free capture leaves real Git refs/index/remotes
unchanged. No archive/IPA is created or uploaded.

- Source SHA256: `3064caa2a88c357c00205aef338f684f06b4812c94aad4d80848d2915d301fbd`
- Temporary snapshot commit: `a9d708d3659356217d063e23c76258c0e25a9c51`
- Temporary bundle SHA256: `868daae50e899ec395069ceb105bf2249020a2de1adb61b9eae14f1cbf8ed8d4`
- Signed executable SHA256: `ecdcff260975f47325e7779572b551bed40e2b3dce64d81ff35939170f163e7d`

## Resources

One reused temporary gate, sequential jobs2 and no simulators. The owned1.4GiB
gate, including build products, source captures, result bundles and private
preference copies, is removed; its scoped awake helper is stopped. Final free
space15GiB. No unrelated artifacts or caches were removed. Only compact receipts
remain, and local memory/reference/privacy-pattern checks pass.
