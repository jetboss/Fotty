# Single-stream resume and recovery — private builds 231–232

Scope: CS1 Pause/Play, bounded automatic single-player recovery, Jet iPad. Phone, FPL, multi-stream, TestFlight and cloud configuration excluded.

## Confirmed app defects

Inline Play advertised Playing before advancing video and rearmed the general startup/stall watchdog. Its grace/sample period and a further ten-second validation compounded the observed delay. The general validator also accepted Playing status without media progress. The prior Jet230 CS1 resume failure and approximately 33-second total recovery remain in ../fotty-cricket-overlap-2026-11-03/. These are confirmed app recovery weaknesses; the old provider stall itself was not conclusively attributed.

## Repair

Ranked single-player inline and native-fullscreen resumes retain the player/item/attempt and share an eight-second observer. It checks current item/attempt/intent/context after each asynchronous boundary. Only a finite explicit live seekable window proving that the old position expired permits one catch-up seek; the seek jump cannot count as resumed playback. A ready live item waiting to minimize stalls with buffered media may receive one immediate-play request. Missing/VOD/ambiguous ranges do not authorize seeking. Playing is published on subsequent progress. Stalls use a shorter, non-resetting six-second validation; Playing alone does not clear a frozen clock. Existing multi-player behavior and all admission/relay guards remain unchanged. Finite local resume actions and window relations distinguish expiry, buffering, resumption and timeout without media URLs.

Apple API references: [seekable ranges](https://developer.apple.com/documentation/avfoundation/avplayeritem/seekabletimeranges), [immediate playback](https://developer.apple.com/documentation/avfoundation/avplayer/playimmediately(atrate:)), [stall waiting](https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling). The eight/six-second budgets are Fotty policies, not Apple requirements.

## Verification

130 distinct focused playback/timing unit tests passed on Jet, including ten new resume/window/cancellation/ownership tests. The initial Release unit-test packaging hit existing Debug-only helper dependencies; the corrected Debug test host passed. One pre-existing Home source-inspection test cannot read the Mac source path on an iPad; its same source assertions pass on the Mac. Preserve these harness failures separately from the passing playback tests.

Signed Release 3.0.0(231) compiled, its signature verified, and the normal app installed on Jet; device inventory reports build 231. Sixteen protected preferences and 43 excluded FPL/multi-stream file hashes match the pre-task snapshot.

The fresh official New Zealand–India first ODI status was live at 05:23:02 UTC on 4 November. The physical CS1 test was pinned to that fixture, with a 90-second hold and 30-second pause configured. XCTest timed out enabling automation at 05:35:56 UTC before the test method ran. Device Hub showed Apple’s “Enable UI Automation — Touch ID to continue with XCTest” prompt. The owner was asked to authenticate. This is neither a playback failure nor a pass.

Long CS1 pause/resume, actual native-fullscreen controls and forced source-loss recovery remain pending. Reverify the fixture and source availability before resuming; do not reuse this match if finished. The eight-second resume budget is a detection policy, not a measured end-to-end fallback time. No claim of resolved upstream CS1 behavior or physical recovery improvement is made yet.

## 4 November live follow-up and relay repair

After owner authentication, build231 native fullscreen CS1 Pause/Play reproduced the stall. Detection took8.254seconds; TV1 decoded progress returned14.416seconds after Play. Preserve `build231-native-resume-failed.json`: faster fallback is not a successful CS1 resume. The current programme was rain-interrupted; Willow explicitly displayed the first-ODI interruption banner, while CS1 initially showed TNT branding and advertisements.

Apple’s exact CoreMedia diagnostic was `segment_uri_changed`. Fresh original CS DaddyLive playlists advanced sequence358310→358311 while replacing only the `token` query on three overlapping, same-origin/path segment URLs. A separate bounded comparison fetched both advertised variants of one segment:2,379,328bytes each and full byte equality. No raw URLs or tokens are retained. `playlist-comparison.json` and `segment-comparison.json` preserve the redacted evidence.

The focused build232 repair gives this reviewed CS DaddyLive delivery stable local segment identities for HTTPS `cdn.hdm1.net` MPEG-TS references, scoped to the originating playlist. Every upstream request still uses the full latest advertised token; tokens are not synthesized or removed from requests. Keys, variant URIs, other origins, other query shapes, expired descriptors and existing Worker-wrapper identities are excluded. Normal DNS/public-IP, TLS, redirects, header and capacity checks remain unchanged. Sixteen actual-policy XCTest cases pass on macOS, including two new token/ownership regressions. The physical acceptance is pending build232; no successful CS1 resume is claimed yet.

Maintainer context: [HLS rewrite implementation](https://github.com/rajhodedara/live-sport-plugin/blob/main/src/services/HlsRewriteService.js) and [DaddyLive adapter](https://github.com/rajhodedara/live-sport-plugin/blob/main/src/providers/DaddyLiveProvider.js), inspected4November. Repository source explains token-bearing segment delivery but is not proof of the hosted revision. The fresh byte/playlist comparison above is the runtime evidence for this repair.

## Build 232 physical results — 4 November

The signed normal Release232 was installed on Jet. Apple authentication succeeded, but the XCTest Watch tap did not open the player; that automated attempt failed before playback, not at CS decoding. Manual Device Hub controls then exercised the installed app and its existing local diagnostics. No further build was needed.

- **Inline CS1 resume passed:** paused35.76seconds, resumed1.046seconds after the observer began. The old position was explicitly outside the seekable window; the existing bounded catch-up rejoined it, then subsequent displayed progress proved resumption. No new attempt or source switch occurred during resume.
- **Native fullscreen CS1 resume passed:** paused33.311seconds with Apple controls, resumed0.505seconds on CS1. Native presentation and resume records corroborate the same attempt; no replacement start occurred during resume.
- **Natural recovery passed:** a separate unpaused CS1 stall produced CoreMedia-12888, then TV1 decoded5.251seconds after failure was recorded and held92.455seconds with no stalls. A later post-resume CS1 stall recovered to TV1 in5.130seconds; TV1 held91.896seconds with no stalls. Those timings start at detected failure, not first frozen frame.
- **Forced route-loss acceptance did not pass its hold:** a scoped local failed-to-end injection on CS1 produced another CS1 delivery within the18second screen-sample bound, but that replacement stalled before90seconds. This was a synthetic player-item error, not a provider shutdown. Neither the renewed CS route nor the TV alternative establishes ultimate publisher independence.
- **Remaining delivery limitation:** the current CS DaddyLive Willow route repeatedly stalled with CoreMedia-12888 despite successful HTTP requests and preserved playlist metadata. A fresh three-sample publisher check added20.96seconds of advertised media over49.244seconds of wall time. The bounded evidence supports an upstream pacing problem; the exact Apple numeric error is not decoded into an invented cause. The token-identity error from231 was not observed in these232 failures. Do not hide this limitation by extending player waits, fabricating media or reporting sustained CS acceptance.

Fresh ICC still reported the exact first ODI live at08:56UTC. Pictures showed New Zealand/India on Willow; earlier in this gate Willow explicitly reported rain interruption and replay coverage. Transport checks do not certify contemporaneous on-field action. Current provider metadata now listed Willow before TNT; CS1 is an ordinal and should not be assumed to mean the earlier TNT edition forever.

Receipts: `build232-resume.json`, `build232-natural-recovery.json`, `build232-source-failure.json`. Earlier231 failures remain unchanged. The130 prior focused playback unit passes and16 actual proxy-policy XCTest passes are separate from these physical results. Phone, FPL and multi-stream were not operated; no cloud/Git publication or TestFlight.

Final restoration: device inventory confirmed3.0.0(232); the app was relaunched without test environment or fault injection. All16 protected preference hashes and43 excluded source hashes matched their snapshots.
