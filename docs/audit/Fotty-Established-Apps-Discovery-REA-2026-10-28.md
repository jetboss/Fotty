# Established-app research: correct catalogs, discovery and playback

28 October 2026. Three task-scoped agents studied Stremio, Nuvio and Jellyfin, with additional published Video.js HTTP Streaming artifact analysis and Apple HLS guidance. This is research and a proposed implementation order. No app, device, provider configuration, backend or TestFlight change was made.

## Owner's intended outcome

Find the correct match and a genuinely usable stream through the existing match/source experience. Discovery and catalog correctness are primary; recovery after a failed tap is only the final part of the chain. Premier League, Champions League and supported cricket are the critical coverage targets. Preserve FPL, multi-stream and the current devices.

The most useful change is a unified fixture-to-source discovery layer with independent provider plans and explicit evidence. More watchdog polling alone cannot establish that a listed match has a playable delivery.

## What was actually examined

| Investigation | Evidence | Boundary |
| --- | --- | --- |
| Stremio | REA on official published `@stremio/stremio-video@0.0.103`, npm integrity verified; four key files byte-match official commit `1b04d4bb4cc49d8b62955c152fd3449ea6a6db63`. Separately inspected official core source at `3417c2e7ed45cdbfd86b3226f69814c2dc4947ad`. | Live `web.stremio.com` code fetch returned 403; no bypass. Playback package analysis does not establish the deployed core/WASM version. Catalog/discovery findings are explicitly core-source evidence. |
| Nuvio | Exact official `0.6.5-beta` released source at `af58a32b05741963beec861255f5b18f7ede69cf`, including add-on manifests, transport, catalog, stream dispatch, refresh and cache admission. | Current app is native Kotlin Multiplatform. The existing REA setup lacks the required JADX MCP JAR; no native decompilation or app execution is claimed, and no engine was installed. |
| Jellyfin | REA on actual official demo Web 12.4.0 main/runtime and the runtime-mapped 46 KB HTML player chunk. Corroborated selected shipped control flow against official v12.4 source at `0a580ce8df89282dfd120b6d5efb8e106da23bd5`. | Version/control-flow agreement is verified; a reproducible-build identity for the exact demo commit is not. No server login, playback or media requests. |
| Separate Video.js comparison | REA on official npm `@videojs/http-streaming@3.17.5` distribution and its published 3.4 KB reload plugin, registry integrity verified. | This is an additional player-library comparison, not a claimed Nuvio dependency. Its default reload callback returns the current URL; fresh provider resolution is a deliberate extension, not an automatic guarantee. |

All REA work was static. Expanded semantic graphs have partial/unknown coverage, documented in retained receipts. A complete JavaScript parse is not proof of runtime behavior. Primary source inspection corroborated the selected mechanisms; none of these apps proves that every outside publisher always supplies a playable sports stream.

## Findings that directly improve discovery

### 1. Separate the catalog provider from the stream providers

Stremio's `AllOfResource` plans requests across installed add-ons whose manifests support the resource, type and ID prefix. Catalog enumeration is a separate plan. Nuvio similarly dispatches each compatible installed add-on independently and publishes source-local results.

**Failure prevented:** a master catalog closes or omits an event, and other sources are never asked even though they could provide it.

**Fotty adaptation:** start with the verified fixture and plan discovery independently for each reviewed eligible adapter. A provider may first need its own catalog/meta lookup to find its advertised ID. Do not send Fotty's canonical fixture ID into an unrelated add-on namespace or require another publisher to validate it. Build indexes from metadata already fetched, so discovery can establish available choices before the user enters match details.

Fotty already has independent optional lanes and append-only partial results in `HybridStreamProvider.swift:307–370` and `StreamDiscoveryCoordinator.swift:30–145`. Build 181 also removed the closed-publisher dependency from AS dating. Preserve those; the remaining work is consistent event binding and discovery freshness across reviewed paths, not replacing functioning parallel orchestration.

Sources: [Stremio request planning](https://github.com/Stremio/stremio-core/blob/3417c2e7ed45cdbfd86b3226f69814c2dc4947ad/src/types/addon/request.rs#L359-L368), [capability admission](https://github.com/Stremio/stremio-core/blob/3417c2e7ed45cdbfd86b3226f69814c2dc4947ad/src/types/addon/manifest.rs#L120-L145), [Nuvio per-provider dispatch](https://github.com/NuvioMedia/NuvioMobile/blob/af58a32b05741963beec861255f5b18f7ede69cf/composeApp/src/commonMain/kotlin/com/nuvio/app/features/player/PlayerStreamsRepository.kt#L260).

### 2. Carry an exact identity chain from fixture to delivery

Stremio preserves catalog/meta/video/stream linkage using advertised IDs and request provenance. Jellyfin's shipped playback manager resolves a programme through its explicit `ChannelId`, obtains source/capability information and opens a live session if required. Its guide joins programmes to known channel IDs, not similar display names.

**Failure prevented:** a listing points to the wrong game, yesterday's fixture, a different squad, or a generic channel with an unconfirmed programme.

**Fotty adaptation:** retain one reviewed binding containing canonical fixture ID, provider instance, provider event ID, advertised stream resource/type/ID, exact date/squad/competition/format evidence, manifest revision, corroboration time and expiry. Keep current ambiguity and security checks. A conflicting refresh must not overwrite an accepted binding. Provider catalog content is source evidence, not an independent official schedule.

Jellyfin owns its server/channel registry and tuner access. Fotty cannot reproduce this by assuming Willow or Fox is carrying a named fixture. A generic channel stays separate until programme evidence establishes that association. Stremio/Nuvio's film-oriented first-video or episode fallbacks are unsuitable sports identity rules.

Sources: [Stremio metadata/stream linkage](https://github.com/Stremio/stremio-core/blob/3417c2e7ed45cdbfd86b3226f69814c2dc4947ad/src/models/meta_details.rs#L603), [Jellyfin programme resolution](https://github.com/jellyfin/jellyfin-web/blob/0a580ce8df89282dfd120b6d5efb8e106da23bd5/src/components/playback/playbackmanager.js#L1824), [Jellyfin guide](https://github.com/jellyfin/jellyfin-web/blob/0a580ce8df89282dfd120b6d5efb8e106da23bd5/src/components/guide/guide.js).

### 3. Recheck late-published streams rather than retaining early emptiness

Nuvio exposes an explicit reload that bypasses cached responses and independently refreshes manifests. Stremio has a `force_request` primitive and separates resource outcomes; its inspected stream updater nevertheless uses `force:false`, so no automatic late-stream guarantee is claimed.

**Failure prevented:** a source checked an hour before kickoff returns empty; the source publishes shortly before the match, but Fotty continues using earlier empty results or a stale capability manifest.

**Fotty adaptation:** assign separate freshness policies to manifests, provider-event catalogs, positive descriptors and empty responses. Near a verified event's known publication window, perform a bounded fresh check for relevant enabled sources. An explicit retry must refresh the resource responsible for the stale result. CS/AS currently retain manifests for 30 minutes (`CommunitySportsAddonClient.swift:398–423`, `PlavioSportsAddonClient.swift:312–320`); a targeted mismatch/refresh path is a concrete improvement.

This does not authorize indefinite polling or multiplying every provider's request inventory. Implementation should begin with the current foreground/owner-relevant fixtures and source-access budgets; any cloud collection expansion remains a separate deployment gate. Unknown publication windows and empty overnight lists remain pending. Do not call a source failed just because the event has not started or a stream is not yet advertised.

Sources: [Nuvio forced stream reload](https://github.com/NuvioMedia/NuvioMobile/blob/af58a32b05741963beec861255f5b18f7ede69cf/composeApp/src/commonMain/kotlin/com/nuvio/app/features/streams/StreamsRepository.kt#L62), [no-cache transport](https://github.com/NuvioMedia/NuvioMobile/blob/af58a32b05741963beec861255f5b18f7ede69cf/composeApp/src/commonMain/kotlin/com/nuvio/app/features/addons/AddonHttpClient.kt#L4), [manifest refresh](https://github.com/NuvioMedia/NuvioMobile/blob/af58a32b05741963beec861255f5b18f7ede69cf/composeApp/src/commonMain/kotlin/com/nuvio/app/features/addons/AddonRepository.kt#L276).

### 4. Preserve independent, meaningful provider outcomes

Nuvio keeps separate loading/success/error groups and distinguishes no compatible add-on, all fetches failed and valid empty responses. Stremio resources likewise retain request-scoped typed state. This is more informative than collapsing every path into one absent stream list.

**Failure prevented:** a provider timeout is interpreted as confirmed absence; a healthy sibling masks an omitted catalog; the owner cannot tell whether the problem is discovery, matching or playback.

**Fotty adaptation:** retain source-local results for each exact fixture: not eligible, waiting for publication, transport failed, catalog conflict, no exact match, descriptor empty, rejected contract, current candidate. Preserve timestamps and reasons internally. User actions should reflect this state through the existing match/source flow, without permanent technical banners. Distinguish a missing catalog entry from a missing descriptor and a rejected delivery.

Define an owner-facing coverage check for reviewed critical live fixtures with no fresh candidate, separately from provider-health incidents. This is a discovery coverage gap, not automatically proof that a publisher is down. Never clear one competition's gap because another has a healthy stream.

Source: [Nuvio stream-result distinctions](https://github.com/NuvioMedia/NuvioMobile/blob/af58a32b05741963beec861255f5b18f7ede69cf/composeApp/src/commonMain/kotlin/com/nuvio/app/features/streams/StreamFetchSupport.kt#L64).

### 5. A remembered source must be revalidated; refresh must preserve playback

Stremio reuses a remembered choice only when it reappears in the current add-on response. Its live-guide refresh is separate from stream state, with tests that preserve streams during refresh. Nuvio avoids storing/reusing links that appear to contain expiring credentials. Jellyfin renegotiates playback information with the selected media-source/live-session identity and device capabilities.

**Failure prevented:** a once-fast source retains an expired URL; refreshing the catalog destroys working video; a late response replaces the owner's newer source.

**Fotty adaptation:** keep stable source preference and decoded-start ranking, but obtain a fresh allowed descriptor when its lease/contract expires or a permitted source-local retry needs it. Preserve the existing playing session during catalog refresh. One source-local refresh must retain exact fixture identity, headers and trust checks and fit the existing retry budget. Auth denial is not permission for unlimited refresh or an access workaround.

The current same-source native retry reloads the captured session URL (`LivePlayerViewModel.swift:1572,1924–1952`). Adding a provider-specific refresh callback is a real incremental mechanism. The separate Video.js plugin offers such an extension point with a cooldown, but its default callback returns the existing URL; Fotty's fresh resolver would be an intentional adaptation.

Sources: [Stremio current-response revalidation](https://github.com/Stremio/stremio-core/blob/3417c2e7ed45cdbfd86b3226f69814c2dc4947ad/src/models/meta_details.rs#L917), [Nuvio link-cache admission](https://github.com/NuvioMedia/NuvioMobile/blob/af58a32b05741963beec861255f5b18f7ede69cf/composeApp/src/commonMain/kotlin/com/nuvio/app/features/streams/StreamLinkCacheRepository.kt#L62), [Jellyfin playback negotiation](https://github.com/jellyfin/jellyfin-web/blob/0a580ce8df89282dfd120b6d5efb8e106da23bd5/src/components/playback/playbackmanager.js#L419), [Video.js reload extension](https://github.com/videojs/http-streaming/blob/v3.17.5/src/reload-source-on-error.js).

## Recommended Fotty experience and evidence model

**Verified fixture → independently eligible providers → exact provider-event bindings → current descriptors → compatible source choices → decoded playback.**

A scheduled event proves the match exists. A catalog event proves a provider listed it. A fresh compatible descriptor establishes a candidate. Decoded advancing correct-programme video establishes observed playback at that time. These are separate facts with separate expiry.

The goal is to populate useful source choices proactively and refresh them at the real event window. Removing Watch or hiding fixtures by itself does not achieve the owner's goal. Do not promise viewing solely from kickoff, a LIVE label, a catalog row, a generic channel or yesterday's successful URL. Outside providers can still withdraw streams; the product must preserve alternate discovery and explain the current outcome accurately.

For this project, keep native AVPlayer/AVKit and the existing 18-second append-only discovery, request/source ownership, manual Pause semantics, decoded-frame checks and direct-stream ranking. Stremio's 30-second manifest timeout, ten manifest retries and 120-second fragment bound are not suitable defaults for fast live sports. Jellyfin server transcoding and Video.js browser-specific error repairs are not substitutes for source discovery.

Apple's HLS guidance describes redundant variants/content steering within a provider's coordinated presentation. Use those capabilities when genuinely advertised by the stream. Do not manufacture one multivariant playlist from unrelated providers with different timelines or assume app-level source switching will be interruption-free. [Apple HLS errors](https://developer.apple.com/videos/play/wwdc2017/514/), [content steering](https://developer.apple.com/videos/play/wwdc2022/10144/).

## Implementation order and acceptance

1. **Provider plans and binding:** inventory reviewed adapter capabilities, remove remaining master-catalog gates, and carry the exact fixture/provider ID chain through discovery and playback. Reuse existing matching safeguards. Test a closed primary catalog while an independent provider still supplies the exact PL/UCL/cricket fixture.
2. **Fresh catalogs and late-stream checks:** add targeted manifest/descriptor refresh and short-lived negative state. Test empty-before-match → newly advertised stream → visible choice without relaunch, plus wrong squad/date/format/conflicting ID rejection and provider-local partial failure.
3. **Availability and coverage:** maintain current per-match candidate evidence and typed provider outcomes before entering match details. Watch must not be a promise inferred from schedule alone. Coverage checks must identify exact supported live fixtures without fresh choices, without treating generic channels as named matches or sibling competitions as recovery.
4. **Fresh descriptor negotiation and typed recovery:** add one eligible source-local refresh inside the current budget, and pass structured HTTP/stage/error facts to the existing policy. An expired descriptor can refresh; an unsupported contract or denied access must not loop. Test stale callbacks, explicit Pause/cancel, and a catalog outage while a healthy stream keeps playing.
5. **Verify the complete path on the approved iPad gate:** normal Home/match/source flow, real current PL, UCL and supported cricket fixtures, correct programme, 90-second decoded progression, basic native controls, and an actual failing-primary/working-secondary case. Missing live windows remain pending. No source qualifies from a working URL or player clock alone.

These are proposed gates, not tests already run in this research. Any app implementation, installation or separately governed backend deployment follows the owner's task authority. No TestFlight gate is implied.

## Retained REA receipts

Small JSON receipts under `docs/testing/rea/established-players-2026-10-28/` preserve versions, artifact hashes, selected source/module locations, evidence IDs and coverage limits:

- `stremio-playback.json`: parent `ev_330c0bc42b6fbf49960765bf3fa4f006eabad693f2fe28f5ae1ba562867be36e`; archive SHA-256 `9e69ad8aeebaf42320906443cdffa08e8d21e9b7b81b9cb4a35d8bbf25ff8b71`. Incoming HTMLVideo trace matched two seeds and retained 15 nodes/26 edges; coverage partial.
- `stremio-discovery.json`: exact source commit/blob identities; explicitly source-backed rather than attributed to the inaccessible deployed core.
- `nuvio-vhs.json`: exact Nuvio source hashes and native-analysis boundary. Separate VHS distribution parent `ev_c0a7bc999fca74b2869f3c95d7ad9ba06dc6a1dbcf2709aa72843e6720bf9712`; focused reload plugin parent `ev_503c6839407e6c4e2d3227156fa1074df34572f262824c421d5c671fb1cbcb11`. Parse coverage and dynamic binding uncertainty are retained.
- `jellyfin.json`: actual demo main SHA-256 `c14f7003a27deb4720dc76472c3147ee7d97a86d8bac0e80c23dad7a9ec40db3`, parent `ev_8c0735f590c9b4963f2eb3c88a87ad3e05da957dff8dc8fade8de9931c82a7d5`; player-chunk SHA-256 `eb20794d5051e092fe39373c8b265fcd60a05f43b61df0b212b3ebe70e52c748`, parent `ev_6f82ec543a0319c7300b896cd939400213fe9efa3ebeb9ff36054c236a1711df`. Shipped programme/channel/source-control locations and corroborating guide-source evidence are included.

Package licenses were checked: Stremio video/core MIT; Stremio Web UI GPL-2.0; Nuvio GPL-3.0; Jellyfin Web GPL-2.0-or-later; VHS Apache-2.0. The recommendations adapt mechanisms independently; no upstream code was imported.

The three owned temporary research gates were removed after small receipts were retained. No caches or unrelated artifacts were deleted, and no generated project-memory export was rewritten for this read-only research.
