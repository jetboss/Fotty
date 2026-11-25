# Jet private209 TV result

Sports TV is now a dedicated native TV tab immediately after Home. The previous Home sheet/link is removed. The full-screen station browser uses two columns in wide iPad windows and one in compact/accessibility layouts. English is the default only for an unset saved preference; explicit preferences and Spanish backup channels remain. Local favourites/recents and the existing single-player owner are reused.

## Verification

-90 focused native tests passed, zero failures/skips; see english-core-native-tests.json.
- App and widget209 Release compilation and strict nested signature verification passed. Final general-TV Details copy is “TV channel”; it does not change playback ownership, audio, PiP or fullscreen mechanisms.
- Installed normal209 TV navigation/full-width grid was visually inspected on Jet. Final copy-only replacement install, corrected TV label and Home/TV navigation round trip passed; see209-final-install.json and209-final-ui.json. Test-created recent channels were cleared through the normal UI; favourites preserved.
-43 protected FPL/multi implementation hashes remain unchanged. Phone untouched; no TestFlight or further Git/cloud publication.

## Native station observations

| Station | Actual observation | Limit |
| --- | --- | --- |
| TNT Sports1 |139s advancing picture after an automatic retry; watermark, documentary/UFC footage | Initial readiness timeout retained |
| TNT Sports2 |138s on fresh normal-Watch retry; MotoGP interview/race footage and watermark | First run stalled before90s; retained |
| TNT Sports3 |106s advancing AFLW programme and watermark | Earlier short uncommanded return to TV was not counted as a pass |
| USA Network |102s minimum advancing WNBA postgame programme with USA Sports branding | This is station playback, not a Premier League assignment |
| Sky Sports Cricket | First run had native video/positive90s continuity, then stalled around110s | Fresh retry visibly advanced for147s beyond the prior stall; both receipts retained |
| Sky Sports Football | No decoded picture on initial attempt or fresh bounded retry | Not qualified; no permanent provider-dead claim |
| NBC Sports NOW | Earlier208 normal native hold110s | Historical separate receipt retained |

Actual station playback is not live PL/UCL match/programme qualification or indefinite uptime proof. Device Hub does not relay sound, so audio commentary was not independently heard. Metadata identifies these English channels. Single-quality options remain eligible.

## Source and guide boundaries

The six additional English contracts use two finite reviewed public playlists. Five Sky/TNT stations share one CDN. Different station names or hostnames alone do not prove independent supply. Exact advertised IDs/paths/headers/opaque renewal query and existing destination/expiry restrictions remain; HTTP-only alternatives were not upgraded. New English stations cannot borrow Uruguay ESPN or main-Willow guide assignments. The separate Willow Sports candidate returned media403 and is excluded; main Willow is unchanged.

Two bounded metadata samples found advancing HLS playlists and stable overlapping segment references. This did not establish a cause for the observed native stalls, so no speculative relay/player change was made. Failed runs and successful retries remain separate. PL/UCL normal live Watch acceptance awaits an eligible current match.

## Visual evidence

Current TV capture: tv-tab-209-landscape.png. The older all-screen UI evidence checker correctly reports a stale Home source hash after this tab move. Old captures were not rebound to new code or called current full-app acceptance. This narrow task has its own source/signature and actual-device receipts. Channel/nav-only changes do not repeat PiP/fullscreen suites; see QA-Playbook.
