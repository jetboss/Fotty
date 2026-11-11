# Fotty 2.0.1 (141) private score and CS gate

Installed on Jet iPad 11 October 2026. The owner stopped the earlier gate to
watch the game, then made Jet available to resume CS playback and PiP checks.
The repaired streamedpk gate passes; the timstreams PiP gate remains open.
No TestFlight, phone, backend or Git publication was performed.

## Changes and local verification

Retain139/140's full-name score/freshness repair, squad/date safeguards, finite
native failure diagnostics and signed-wrapper compatibility. The CS adapter
now admits/deduplicates at most100 inputs, reserves one delivery per existing
opaque upstream group within the six-choice cap, fills remaining slots and
emits selections in original response order. URLs, headers, runtime profiles
and CS1–CS6 labels remain intact. Four regressions and independent review pass.

Simulator-free CI passes1174 units:1172 passes, two existing optional skips,
zero failures. The first run failed one existing visual test: its warmed
synthetic NSCache image was absent and six image-dependent snapshots differed.
The unchanged full rerun passes, with no threshold/rebaseline/UI/cache changes.
The transient cache miss's underlying cause is not established.

Unsigned iOS Release, signed UI-only Release build-for-testing, strict deep
signature, frozen1076-file comparison, app/extension141 and independent
installed-app readback pass. Pinned Xcode27A266a; one sequential build directory.

- Capture: `backups/release-source/2.0.1-141-score-cs-fair-selection`.
- Commit: `668d7e64f4feab8382352892d51a6ef9004dbaf8`.
- Source SHA256: `f56bc40e49a556112af153c20331e12f063f253b84a1e18b8e75726785874f89`.
- Bundle SHA256: `223b18c08aa0c0b4315d8d1984e54f7fd0ffc361ae1d72018a10f0e60c455f76`.
- Executable SHA256: `de1e71eb20f8a7e762f56982c08ec8dae15ddbb9d569b464d9c612893498ce7b`.

## Interrupted physical gate

The exact-CS5 Liverpool FC/Manchester City FC native PiP check was interrupted
at the owner's request before a finalized acceptance result. The host test
process stopped; a read-only process receipt finds no Fotty UI test runner
remaining on Jet. Keepalive stopped. No partial execution counts as passing.
No CS6/DaddyLive141 qualification or further device actions follow the stop.

The resumed gate below attributes actual selected upstreams with local opaque
source keys. CS numbers alone cannot qualify the repaired format. Build140's
DaddyLive PiP pass and score screenshot remain dated evidence, not141
acceptance; see release140.

Owned build products, result bundles, screenshots and copied private audit
inputs are removed after recording these facts. Recovery source receipts are
retained. Shared121 and phones125 stay unchanged.

## Resumed Jet acceptance — 11 October 2026

Rebuilt the saved 1076-file source receipt above without production or test
source changes. Strict signing, frozen-source comparison and installed141
readback pass. Fresh executable SHA256:
`9b3373527a0b690169a2b708f287b059425e517958cd29697cf501668af3496a`.
Reuse one bounded build directory; no simulator or parallel heavy build.

The reviewed real Betis–Osasuna catalog/stream metadata at18:22 UTC supplied
all three upstream groups. The private app's ordinary Watch route selected the
requested CS row; no source enablement, fixture injection or preference reset.

| Real choice / upstream | Finalized physical result |
| --- | --- |
| CS5 / streamedpk | Pass: selected source controls, native ready/progress, full60s visible Home PiP, same item/attempt, ordinary Stop, inline progress, Close/Home. |
| CS6 / timstreams | Fail: native setup and changing Home PiP frames observed, but same-item media advance did not exceed30s on return; player was paused. Stop/inline acceptance was not reached. |
| CS1 / DaddyLive | Pass: same-selected-source native progress, responsive source picker, Close/Home. This is a short control gate, not141 DaddyLive PiP or long-soak proof. |
| CS6 repeats / Home and Search | Two exact-fixture-unavailable skips in those launches. Neither erases the first failure or counts as PiP acceptance. |

CS5 local attribution: `cs_b4b96736a09f67b152e3e922`,
attempt `BB443DB0-51CD-48D4-8AB2-622D95DA07B5`, native item
`0B80DD5E-E829-422D-97E1-12A9134983A5`; recorded round-trip advance51.782s.
Independent read-only Device Hub observations show different decoded PiP
frames while SpringBoard remains visible, before Fotty reactivation. This
closes the foreground-only/live-window-seek interpretation gap, but does not
prove uninterrupted frames or audio. Passive buffering intervals1536/6760/
228/6442ms closed as `transport_playing`; no fatal, retry or fallback recorded
for that attempt. Keep the buffering caveat; do not label this flawless QoE.

CS6 attribution: `cs_99f547e542673eb3cf0f65a5`,
attempt `2F723712-1C94-4E2D-A203-4B35E2B9F4B6`, item
`CC70E9D7-D284-4600-BB1E-A3767B849B3D`. Return measurement has itemStatus1,
currentTime25.025s, rate0 and timeControlStatus0. The last observed buffering
interval6165ms ended as `interrupted`, not recovery. No recorded fatal,
replacement or fallback explains the pause. Native PiP-owned inline
readyForDisplay=false is expected, not evidence of failed decoding.

A bounded fresh timstreams metadata/playlist check at18:33:11 UTC returns200,
valid HLS without ENDLIST/VOD, target duration6s and four segments totaling
20.020s. That is a sliding playlist window, not programme length. No redirects,
segments, keys or media were fetched. Earlier-attempt playlist/path equality
was not retained. The evidence establishes neither natural completion nor an
app-side initiating pause; no speculative lifecycle/security fix was applied.

The failed CS6 acceptance remains open. Muted XCTest does not qualify sound,
CS2–CS4 were not individually requalified, and no shared release is authorized.

One final bounded catalog/stream check at18:35:58 UTC finds an advertised-live
San Lorenzo–Deportivo Riestra fixture with one DaddyLive delivery only. It
cannot qualify timstreams. No further candidate crawl or fabricated test route.

After a normal, unmuted launch, the Betis Watch card is visible again. Therefore
the two test skips are availability-at-the-time receipts, not evidence that the
programme ended or the fixture disappeared permanently. Manual Watch activation
did not reach a player in the bounded follow-up; no additional CS6 qualification
is claimed. Do not substitute a cached card or infer source health from it.

Cleanup verified: owned UI runner uninstalled, normal141 launch without test
arguments/environment, and independent app readback141 with runner absent.
Removed the448MB owned build/result/screenshots/private-copy gate and stopped
the temporary keepawake processes. Recovery source receipts and user data stay
intact;27GiB free afterwards. Shared121 and phones125 remain unchanged.
