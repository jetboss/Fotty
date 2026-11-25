# Fotty stream reliability and usability review

## Active milestone: Fotty2.5 — 24 October

The owner now prioritizes a coherent Stremio-inspired2.5 experience with serious
REA evidence. Keep normal175 frozen on the owner iPhone and Jet for next-day
feedback. FPL/multi-stream remain paused. This roadmap does not authorize another
device install, Git/cloud publication or TestFlight. Keep the actual source
version2.0.1(175) until a new candidate is implemented;2.5 is a milestone, not a
marketing-version-only edit. The23October findings below are dated history.

### Actual shipped-artifact evidence

The [official downloads page](https://www.stremio.com/downloads) currently serves
native Mac2.0.7(22), while the
[Apple2.1 announcement](https://blog.stremio.com/stremio-tech-update-86-stremio-update-for-macos-and-ios/)
is dated22October. These are different references. REA6.4.0 actually inventoried
and extracted the advertised package, then parsed its plist and Mach-O; this is
new shipped-artifact evidence, not just a tool-readiness check.

The actual `com.stremio.pal` main image links UIKit via iOSSupport, AVKit,
AVFoundation, VideoToolbox and bundled KSPlayer. Its KSPlayer bundle reports1.0(1),
not a traceable upstream commit. This establishes components, **not** its chosen
decoder, source ranking, buffer settings, runtime speed or superiority to Fotty.
No application launch, native decompilation or2.1 runtime inspection occurred.
Deep native providers remain unconfigured; that evidence gap stays open.

Complete canonical REA records and exact hashes are retained in
[the1.3MB evidence pack](../testing/rea/stremio-2.0.7-2026-10-24/README.md).
The449MiB archive/extraction/analysis gate and awake helper are removed. Secret
scanning passes. No new engine, device interaction or Fotty runtime edit.

The current Web source separately renders ready providers while others load,
keeps an All/provider filter and returns to All if the selected provider vanishes.
[Pinned StreamsList.js](https://github.com/Stremio/stremio-web/blob/7030b128af43afddd05d906025ecd6d99743f554/src/routes/MetaDetails/StreamsList/StreamsList.js).
This is not Apple-native equivalence. Do not copy its completed-empty placeholder
behavior: finished-empty and still-checking must remain distinct. Web's GPL2 and
core's MIT licenses do not license the proprietary Apple UI or artwork.

KSPlayer is an evaluation lead, **not an adopted dependency**. Current
[LICENSE](https://github.com/kingslay/KSPlayer/blob/7d6b4ced6f6b0d3b54cde84c77314a3fa6d927b0/LICENSE),
[README](https://github.com/kingslay/KSPlayer/blob/7d6b4ced6f6b0d3b54cde84c77314a3fa6d927b0/README.md)
and [package](https://github.com/kingslay/KSPlayer/blob/7d6b4ced6f6b0d3b54cde84c77314a3fa6d927b0/Package.swift)
have GPL/binary/platform constraints; stale podspec MIT wording is insufficient.
Consider another decoder only for demonstrated valid-media AVPlayer limitations,
after checking physical-iPad availability, applicable license, app size/memory
and retained fullscreen/PiP/audio/control behavior. HTTP502, expired tokens and
wrong match identity do not justify an engine swap.

### Implementation order and completion contracts

| Order |2.5 workstream | Concrete result and acceptance |
| --- | --- | --- |
|1|Curated modular source engine|One typed reviewed definition owns registration, labels, fixture scopes and dispatch. Retain each adapter's schema/admission, exact identity/conflict vetoes and guarded delivery. A reviewed addition must not require synchronizing unrelated provider lists. No arbitrary add-on installer, trust expansion or enablement migration.|
|2|Complete single-player journey|Show usable alternatives while slower lanes still check, within one bounded owned discovery session. Preserve source/attempt/intent through ordinary renders, menus, fullscreen and PiP. Opening Sources never restarts playback; selecting another feed is explicit replacement, not zero-restart media switching. Distinguish checking, preparing, decoded playback, buffering, finished-empty and actionable failure.|
|3|Intentional browsing/planning|Use compact inline event context only where it removes friction. Home chooses what to watch; Matchday plans ahead. Preserve interests, scroll position, schedule/watchability truth, badges and sport artwork. EPG/NowNext needs a reviewed feed; generic channels cannot manufacture named fixtures.|
|4|One native phone/iPad design language|Task-grouped settings, native menus, clear press/selection feedback, readable long names and useful wide-window composition. Keep171's video-first/native controls. Write screen contracts and show meaningful previews before substantial UI edits. Verify light/dark, Dynamic Type, Reduce Motion, safe areas and anchored menus in real native screens.|
|5|Measured responsiveness and qualification|Measure Home dedup/discovery, cold Search indexing and failed-preferred-badge retries before optimizing. Separate tap feedback, source-list/first-decoded timing and recovery from provider/network delay. Qualify the coherent journey, not just screenshots, URL responses or test totals.|

Orders1–2 are next: define the authoritative source/qualification contract and
regressions while preserving current adapters/APIs, then prototype incremental
resolution. Native screen contracts follow that journey, not an unrelated theme
rewrite.175 owner feedback is baseline evidence, not permission to reinstall.

The [Apple video guidance](https://developer.apple.com/design/human-interface-guidelines/playing-video)
supports expected native controls and unobtrusive useful context;
[materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
places Liquid Glass in controls/navigation rather than every content card.
The apple-ui-design skill governs screen contracts and actual-native comparison.
Stremio is a reference, not a replacement for Fotty's identity or Apple behavior.

### Do not count delivered work again

The original five in release162 are implemented foundations: playback lab, typed
declared/observed contract, scoped native preparation, relay receipts and cached
source health.165 repaired the confirmed discovery/CS/recovery/Search/accessibility
issues;171 added video-first iPad/native presentation;173 improved recent-source
ranking. None is a newly missing2.5 feature.

Remaining gates include CS/FS/SV and AS-cricket live qualification, actual PL/UCL/
cricket coverage, measured physical responsiveness and the complete new source
journey. Metadata watchdogs do not observe decoded video; no new request budget,
paid job or telemetry is approved here. Passing a source requires its actual
delivery, not a renamed duplicate or another wrapper with shared ancestry.

2.5 exit: relevant regressions; deterministic empty/error/late-result/cancellation
cases; reviewed-module integrity; same-owner fullscreen/PiP/control checks;
truthful identity and actual decoded/programme evidence in supported live windows;
native phone/iPad visual acceptance and comparable performance receipts. Leave
unavailable/skipped physical gates open. Enable only passing reviewed deliveries.
Shared TestFlight remains a separately authorized significant batch.

## Original review — 23 October

Reviewed 23 October 2026. Scope: single-stream playback, CS, additional source options and native usability. FPL, Watch Two, source activation and TestFlight are excluded.

The highest-value next step is to repair the existing discovery and retained-playback paths before adding another source. Fotty can currently discard a successful independent provider, lose recovery observation after a background PiP stall, and require fresh discovery to reopen a match that is already playing. These are source-confirmed failure paths, not explanations for every reported provider failure.

## What changed in Stremio

Stremio announced version 2.1 for iOS, iPadOS, tvOS and macOS on 22 October. Relevant changes include clearer player loading states, task-grouped Settings, adaptive player controls, native menus and distinguishing configured copies of an add-on. These are useful design patterns, not a new stream supplier or a drop-in Swift player engine. [Official Apple update](https://blog.stremio.com/stremio-tech-update-86-stremio-update-for-macos-and-ios/)

The separate Web/Desktop update introduced provider-supplied programme guides. An EPG requires actual programme start/end times and resolves playback through channel identity. A generic Willow channel must not become proof that a specific fixture is airing. Keep programme, channel and fixture identities separate. [Web/Desktop update](https://blog.stremio.com/stremio-tech-update-85-stremio-desktop-and-stremio-web-update/), [official EPG contract](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/epg.md)

Stremio's merged Web PR1475 is a useful regression example: unstable lifecycle dependencies caused cleanup during ordinary renders/fullscreen transitions. Learn the ownership lesson; do not transplant a Web/Linux fix into native iOS. [Maintainer PR](https://github.com/Stremio/stremio-web/pull/1475)

## CS is present and one lookup has recovered

Three bounded metadata requests on 23 October returned:

| Check | UTC | Result |
| --- | --- | --- |
| Configured manifest | 15:02:05 | HTTP 200, v3.1.3, 757 ms |
| Football catalog | 15:02:23 | HTTP 200, 100 entries, 520 ms |
| Stream list for a selected Braga U23 and Benfica U23 catalog entry | 15:03:04 | HTTP 200, three entries, 4,740 ms |

Two entries used the reviewed same-origin HLS proxy URL shape. This establishes a successful metadata lookup after the 19 October timeouts, not decoded playback, independently verified live status or all-match availability. No media was requested.

CS remains configured and opt-in. Its exact sport, both teams and kickoff admission still applies. CS1 and CS2 are response-local display labels, not persistent upstream identities.

The maintainer has published fixes for short-lived playback-token caching and required-header delivery. These provide plausible upstream failure mechanisms, but do not establish the cause of Fotty's previous failures or prove which commits the hosted v3.1.3 service currently runs. [Token/cache repair](https://github.com/rajhodedara/live-sport-plugin/commit/6744e45184a892bbce0e98baf7f32d4e9e726e8c), [header-delivery repair](https://github.com/rajhodedara/live-sport-plugin/commit/fb3f1b42bd3940e1e102da6cc308037173d2dafa)

## Recommended repairs

Line references identify the source reviewed today and may move after implementation. The following are control-flow, decoding or layout findings; their physical-device acceptance is a separate gate.

### Preserve independent source choices

`Fotty/Core/Networking/SharedStreamDiscovery.swift:150–221` reserves validation opportunities, but not retained-result capacity. Six fast choices from one family can fill the result cap before another family's successful validation. The later result is discarded. `HybridStreamProvider.swift:960` only publishes accepted partial sessions, so the outer collector cannot recover it.

Reserve result capacity for pending independent families before publishing. Release reservations for empty/failed families; retain exact delivery deduplication and current request limits. Do not simply raise the cap or evict an already-published choice.

Regression: six early same-family successes plus a late independent success must preserve the independent option, including through the outer partial publisher. Cover cancellation, empty families and duplicate deliveries.

### Restore recovery observation after background PiP buffering

`Fotty/Features/Player/LivePlayerViewModel.swift:1089,1239,3213` permits this sequence: native PiP continues in the background; buffering consumes the watchdog; stall validation exits because the app is backgrounded; foreground entry skips resuming because valid PiP deliberately cleared `shouldResumeAfterForeground`. A still-waiting, nonfatal item then has no watchdog unless another status event occurs.

On foreground entry, reconcile observation for the exact eligible single-native owner before the conditional resume branch. Rearm the existing bounded observer without forcing Play, seeking, reloading or changing source in the background. Preserve explicit Pause and source/item/attempt/session fences.

Regression: background soft-stall expiry followed by foreground waiting, with neither fatal notification nor a new KVO event. Include recovered video, explicit Pause and replaced/retired owners.

### Reopen an already playing match immediately

`SportsDashboardView.swift:1962` and `ArenaDiscoveryView.swift:1039` perform fresh lookup before `ViewingSessionCoordinator.open:110` can reuse an existing player. A metadata timeout can therefore block reopening a minimized match that is still playing. The mini-player remains a workaround.

Add an exact retained-single reopen operation before network discovery, after current timing/conflict/admission checks. Preserve model, item, source, attempt and Pause. Do not revive retired/failed sessions or broaden fixture identity.

Regression: Home and Matchday reopen the exact retained match with zero resolver calls. A different date, squad, team pair, competition, conflict or terminal fixture must not take that shortcut.

### Harden CS decoding and cache publication

- `CommunitySportsAddonClient.swift:120`: strict array decoding means one malformed stream entry rejects valid siblings. Decode bounded stream rows independently, rejecting each malformed row in full. Never treat malformed required headers as absent. Keep top-level JSON/body limits and strict catalog conflict handling. Test good/bad/good, all-bad and invalid document cases.
- `CommunitySportsAddonClient.swift:252–272`: overlapping manifest fetches can publish an older response over newer cache state for up to 30 minutes. Apply a latest-request generation fence like the catalog cache already uses. Preserve each caller's result; test out-of-order responses, failure and cancellation.
- `CommunitySportsAddonClient.swift:174–203`: an actual preferred-catalog request/schema failure can be lost when the Live fallback succeeds but lacks the fixture. Preserve incomplete-discovery evidence. An unadvertised optional sport catalog is different from a failed request and must retain the existing legitimate Live fallback behavior. Test both cases separately.

None of these findings proves it caused today's or 19 October's upstream behavior.

### Make validation obey the player's redirect policy

`HybridStreamProvider.swift:160,1039–1120` validates accepted HTML through a URLSession that can follow an unreviewed redirect. The resulting session can be marked validated while the real Web player rejects that top-level destination at `LiveWebEmbedPlayerView.swift:2181`.

Validate every redirect before following it and recheck the final URL under the existing source policy. Do not expand trusted hosts or weaken TLS. Test approved-to-unapproved, approved-to-approved, credentialed, HTTP and nonstandard-port redirects. Apple's redirect delegate supports declining the request. [Apple API](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:))

### Fix small but concrete usability failures

- **Search aliases:** `SearchView.swift:184,266` enriches alias rows with canonical names, but a canonical Manchester United row need not match the reviewed query “Man Utd.” Add exact reviewed canonical-team matching alongside existing raw text search. Preserve literal cross-sport/reserve results; do not replace search with fuzzy fixture admission.
- **Empty-state wording:** `SportsDashboardView.swift:2184` promises “Show everything on Home” while disabling only the interests filter. Rename the action to describe removing that filter; preserve current sport/competition selection. Do not silently broaden all preferences.
- **Accessible controls:** `LivePlayerViewModel.swift:1005` hides controls after four seconds for Web and ten for native, without an assistive-technology/focus exemption. Retain controls when VoiceOver, Switch Control or accessibility focus requires them. Preserve ordinary auto-hide and source cancellation. [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- **Compact loading state:** `LoadingStateOverlay.swift:11` cannot fit its artwork, padding and two labels inside a 288 by 162 point player at a 320 point window. Adapt to available height and text size while retaining readable status and media ownership. Exact cropping requires a native render. Error recovery already has a ScrollView; do not change it based on this finding.

## Additional source candidates

| Candidate | Useful contribution | Decision |
| --- | --- | --- |
| [AIOLiveTV](https://github.com/mrcanelas/aiolivetv), [v1.5.0 released 21 October](https://github.com/mrcanelas/aiolivetv/releases/tag/v1.5.0) | User-supplied playlist/EPG integration, reviewed mapping and preserved alternatives. The release includes provider-failure and mapped-channel repairs. | Strongest small proof-of-concept candidate. It supplies no playlist/account by itself. Review its AGPL obligations and separate hosting needs before copying or adopting code. |
| [MediaFusion](https://github.com/mhdzumair/MediaFusion) | Broader source integration and operational patterns; MIT repository. | Later, narrowly scoped HTTP/HLS investigation only. Do not import its heavier platform or reintroduce P2P/AceStream/debrid paths. |
| [Sportio Live](https://github.com/Sportio-Live/sportio-live) | Sports mapping for a user's own playlist/provider. | Reference only until licensing and fixture identity are resolved. Its documented single-team matching tier is weaker than Fotty's admission policy. |

Several wrappers share upstream channels. Count actual independent origins/families, not add-on names. A new source should survive timeout, expiry, header, identity, decoding, fullscreen and PiP tests before it becomes a fallback. Code availability does not establish broadcast permission or stream uptime.

The existing CS adapter deliberately accepts its reviewed routes and identities; replacing its manifest URL is not a generic add-on integration. Any new provider needs a separate reviewed adapter. Stremio's protocol permits several transports that AVPlayer cannot simply play. [Official stream schema](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md)

## Monitoring and performance boundaries

The existing CS watchdog checks manifest and catalog only. Both can pass while the stream-list endpoint fails. This is a documented coverage gap, not a broken promise of decoded monitoring. A proposed exact-fixture stream-list metadata check must remain separate from playback proof and from generic channel inference.

The current 96-request daily budget is already allocated to 48 two-request windows. A new stream-list check needs an explicit cadence/budget decision, default-off activation, bounded bytes/time, no media requests, stage-specific incidents and no sensitive URL/body retention. Missing eligible fixtures must not become a global outage. This review does not activate that extension.

Performance candidates, not measured speed regressions:

- Home's deduplication/discovery stages still perform synchronous main-actor catalog work. Use the existing child signposts to establish whether either stage actually blocks scrolling before changing isolation. Preserve time-sensitive status recomputation.
- Cold Search preparation is query-keyed, so rapid edits can cancel and repeat query-independent index construction. Give index preparation a catalog-revision owner if measurements confirm repeated work materially delays results.
- A failed preferred badge URL is retried when consumers are recreated, before a cached fallback. A short exact-URL failure cooldown may help; cancellation must not become a cached failure or permanently demote authoritative artwork.

Keep the working foundations: request coalescing, waiter-scoped image cancellation, 32 MB decoded-image budget, off-main image decoders, stable identities, lazy lists, atomic projections, accessible Settings reflow, badges and sport artwork. Neither a new image library nor a new player engine is justified by these findings alone. [Apple responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)

## Implementation and acceptance order

1. Repair result fairness and validation redirect admission.
2. Repair CS parsing, cache publication and incomplete-discovery reporting.
3. Repair foreground PiP observation and immediate retained-match reopening.
4. Apply the small Search, empty-state, accessible-control and loading-layout fixes.
5. Measure the three performance candidates and change only demonstrated bottlenecks.
6. Qualify single playback on Jet iPad before any new source activation: real decoded progress, manual sources, Pause longer than 60 seconds, native fullscreen without replacement, background PiP longer than 60 seconds, system Pause/Play, Restore, inline return and dismissal without duplicate media.
7. Evaluate one additional provider with demonstrated independent delivery. Monitoring activation and TestFlight remain separate gates.

Apple UI guidance informed the native loading, accessibility and layout recommendations; it did not authorize a visual redesign. [Loading](https://developer.apple.com/design/human-interface-guidelines/loading), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

## Completed investigation scope

Ten task-scoped agents ran in waves with no more than three sub-agents active at once:

| Agent | Focus | Result |
| --- | --- | --- |
| 1 | Current Stremio release | Verified Apple 2.1 and separated native, Web and EPG implications. |
| 2 | Current CS health | Three successful metadata checks; current recovery distinguished from dated failures. |
| 3 | Source alternatives | Reviewed five candidates; three retained above, stale/unclear candidates rejected. |
| 4 | Add-on contracts | CS mixed-row decoding and manifest-cache race; optional protocol differences kept separate. |
| 5 | Single-player ownership | Confirmed background PiP soft-stall observation gap. |
| 6 | Source resilience | Confirmed result starvation and redirect-policy mismatch. |
| 7 | Core journeys | Retained reopen, Search aliases and empty-state semantics. |
| 8 | Adaptive UI | Assistive control retention and compact loading overflow; correct existing reflow preserved. |
| 9 | Performance | Three bounded measurement targets, no invented speed improvement. |
| 10 | Independent review | Cross-checked result starvation, PiP, retained reopening, tests and watchdog budget. |

Local verification: 54 existing Node tooling tests passed across playback-lab selection, source metadata probes and performance-evidence validation. This is not XCTest execution or physical playback acceptance. No app source, configuration, device installation, backend, Git publication or TestFlight changed. No build products or downloaded repositories were created; free disk remained approximately 18 GiB. Only this audit report was added.

## Follow-up: additional-source qualification, 23 October 21:50–21:55 UTC

The owner now authorizes Stremio source integration into existing match sources
and Jet iPad testing, leaving FPL, multistream and TestFlight unchanged. The
private167 CS delivery repair does **not** complete that additional-source goal.
No second provider has been integrated or enabled by this qualification pass.

Three task-scoped agents checked provider contracts and the native integration
boundary. Requests were bounded metadata only, with normal TLS, no account
changes, media segments, paid services or new infrastructure.

| Candidate | Observed evidence | Result for an existing-match adapter |
| --- | --- | --- |
| SportsStreams free | Six HTTPS requests. Manifest `community.sports.fly`1.3.0 uses advanced resource objects and type `sport`. Today has35 rows, including20 named `streamed` events and15 generic channels. Dated rows use explicit human UTC releaseInfo. Paris–Valencia's stream response is one unavailable placeholder pointing to a non-media destination. Milwaukee–Chicago's catalog and meta say LIVE but supply no kickoff. | No compatible new delivery verified. A future adapter must reject placeholders and LIVE-only timing; common upstream ancestry alone does not prove a duplicate, but actual URL+header delivery must be compared. [Maintainer](https://www.reddit.com/r/StremioAddons/comments/1wig8mj/) |
| StremVerse | Manifest `com.stremverse.org`3.0.0 advertises genre/search/skip/limit. Sampled live catalogs/meta expose no kickoff; the additional Xtra Cricket request returns an empty catalog. | No safe automatic dated-fixture join verified. Do not infer kickoff from opaque IDs, artwork or the word LIVE. [Public manifest](https://stremverse1.alwaysdata.net/manifest.json), [configuration](https://stremverse1.alwaysdata.net/configure) |
| PPV | The xAle adapter declares category groups with `starts_at` Unix seconds, but a current request to its advertised upstream API returns HTTP200 HTML rather than JSON. | Current endpoint is unusable for this adapter; HTTP200 alone is not a successful source check. [Adapter source](https://github.com/xAle90x/stremio-addon-ppvstreams/blob/master/addon.ts) |

Correct the earlier shortlist's confidence: MediaFusion's current sports spider
is torrent-oriented, while reviewed live-TV code is in its deprecated Python
tree. Its feature documentation alone does not verify a currently usable native
HTTPS live-match lane. Sportio requires an owner's own streams; AIOLiveTV is an
aggregator, not new top-match supply. SportsSphere overlaps Streamed. The
erehhh123 Nuvio add-on requires manually supplied Roxie mappings, empty by
default. These projects are not activated fallback sources.

The native gap is also confirmed: three hardcoded bundled modules, one CS
singleton/manifest identity, fixed provider filters and CS-specific labels/
diagnostics are not a general Stremio installation mechanism. A qualified second
adapter needs its own reviewed schema and delivery policy, default-off state,
bounded concurrent discovery, cache ownership and distinct attribution. Adding
only another manifest file cannot implement that integration.

Jet lists Nuvio0.6.3(146) and Fotty167. Nuvio opens, but remote touch still does
not navigate; an ordinary-length tap also fails. No add-on configuration,
credentials or viewing state is copied or edited. Fotty is returned to the
foreground. The request to identify an already installed, working sports add-on
rested on an unsupported assumption: the owner had not said that such an add-on
was installed. Their request was to research additional source options. Having
Nuvio installed does not establish its configured add-ons or their playback
health; those facts were not verified in this inspection.

**Status at 21:55 UTC:** additional delivery qualification and real Jet decoding
were still open. No app
changes, new build/install, source activation, cloud/Git write or TestFlight
release occurred in this follow-up. No repositories or temporary build outputs
were created; free disk is16GiB. Do not mark this source milestone complete.

## Follow-up: reviewed Plavio adapter, 23 October

Later bounded checks identified an additional delivery-contract candidate.
This is a separate qualification from the earlier shortlist and metadata-only
inspection; it does not turn their unavailable or undated rows into fallbacks.

| Check | Evidence and limit |
| --- | --- |
| Manifest and catalog | Manifest identity `community.plaviohd`, version 1.9.56; sampled sports catalog: 103 rows, including 14 football rows. The adapter reviews resource objects and the advertised `tv` catalog/stream contract, not arbitrary Stremio installations. |
| Fixture join | Only the reviewed football ID shape, `tv` type and Sports genre enter matching. The description must repeat the exact fixture name followed by an explicit English UTC date/time. The shared pure matcher requires sport, both reviewed participant identities and kickoff within 15 minutes, retaining squad distinctions and conflicting metadata/effective-target vetoes. A LIVE label alone is insufficient. |
| Initial delivery admission | Exact `papacito.cfd` HTTPS origin on port 443, no credentials or fragment, three nonempty path components ending in a `.m3u8` leaf, and exactly one nonempty `ft` query item. Signed query values are preserved in memory, never recorded here. Extra origins, ports, query fields, unsupported header contracts and non-HLS placeholders remain rejected. |
| Bounded playlist check | One HTTP 200 HLS response was 840 bytes, contained `EXTINF`, and had neither `EXT-X-ENDLIST` nor `EXT-X-KEY`. It advertised segment URLs on `east.papacito.cfd`. No media segment was fetched from the Mac. This establishes that playlist's shape at that instant, not decoded playback, sustained availability or every future playlist's encryption state. |
| Upstream independence | Known Highfly / `sfly` / Leaf ancestry means this must **not** be marketed or counted as a proven independent upstream. A separately reviewed adapter and different admitted delivery route do not, by themselves, provide independent outage resilience. |

The implemented `PlavioSportsAddonClient` adds optional **AS1–AS6** choices to
existing exactly matched football fixtures. It does not create fixture listings,
infer live status, replace CS or change the existing CS labels. The separate
bundled AS module is **OFF by default**. Enabled discovery uses the existing
bounded resolver, guarded native relay, distinct failure receipt and redacted
source attribution; exact signed delivery identity is retained for deduplication.

The shared `ReviewedSportsFixtureMatcher` extracts the existing CS identity
rules; CS keeps its own schema and released-date admission, transport, cache and
delivery contract. The local offline gate reports **238 tests passed** across
the focused source, matching and integration coverage. Offline tests are not
evidence of current stream uptime or iPad decoding.

**Acceptance remains OPEN:** physical client/relay/decoder checks fail. The
corrected native test uses Apple's display-clock timing and an actual visible
AVPlayerLayer; after40s it observes zero decoded buffers and a black, not-ready
layer despite an advancing player clock, ready item,1080p presentation metadata
and17 successful relay responses. This does not identify a codec or prove an
app transport defect. The earlier unrendered test had18 successful responses
with the same lack of frames; its throwing watchdog originally obscured failure
reporting and was repaired rather than counted as source evidence.

A final bounded check of the exact fixture's stream resource returns HTTP200
JSON136bytes with no admitted HLS. No fresh playlist/segment or offline codec
inspection follows; no alternate fixture is invented. Normal Release168 is
signed, installed and visually verified on Jet. AS remains OFF and existing
source choices/FPL preferences are preserved. No working new fallback, ordinary
AS match-picker playback, fullscreen or PiP pass is claimed. See release168.
FPL and multistream remain unchanged; no TestFlight release occurred.
