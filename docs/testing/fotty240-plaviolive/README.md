# PlavioLive migration — 4 November 2026

Status: normal signed Release 240 installed and launched on Jet at approximately 01:43 UTC 5 November. Home and Sports TV rendered correctly. Physical AS football/cricket playback and cloud activation are not passed.

## Confirmed contract change

The maintainer split PlavioHD and PlavioLive on 2 November. The retired AS metadata origin returned `community.plaviohd` 1.9.168 with no catalogs. The new public metadata origin returned `community.plaviohd.private` 2.1.5 with typed TV catalog/meta/stream resources. Native adapter, backend collector and watchdog now use the new fixed metadata origin/identity. Media security restrictions are unchanged; the AS provider code/settings are preserved.

Primary announcement: https://www.reddit.com/r/StremioAddons/comments/1xm1moq/plaviohd_plaviolive_my_addons_are_two_now_one_for/

## Verification

- 108 focused adapter/watchdog checks passed.
- 39 existing registry/cricket matching checks passed.
- Native Plavio suite: 102 passed, one physical-only test skipped on Catalyst. Local macOS deployment-target override 27.0 was required for the host; no app deployment-target change.
- Fresh actual backend collection used four bounded metadata requests and returned 124 observations. This was before the new CNC UTC parser; those original observations were undated. It was not a playback test.
- After the CNC parser change, a fresh four-request collector pass retained 14 dated and 110 undated observations. All scopes remain partial; this is not playback proof.
- New CNC cricket parser retains explicit UTC and exact squads, rejects invalid dates/generic competition names. Native selection is restricted to verified official limited-overs fixtures, with same-ID metadata revalidation. Test-day context is not inferred.

## Remaining gates

At approximately 01:40 UTC 5 November, AS cricket rows were upcoming (earliest 03:30 UTC). The sampled future WBBL descriptor advertises two HTTPS deliveries with Referer/User-Agent requirements. The existing AS media profile does not admit that new transport contract. Those routes are not qualified or enabled as new deliveries. Shared-registry cricket links also still require source format evidence; dated metadata alone is not an admitted playable link.

Football: fresh ESPN showed São Paulo–Corinthians and Botafogo–Atlético-MG in the second half, official UTC start 5 November 00:30. PlavioLive labels those as 4 November with undocumented site time. The existing same-civil-date policy cannot safely bridge that boundary without original timezone evidence. Finished Flamengo/UCL games are not live playback evidence.

## Other requested candidates

- PenguPlay: current public manifest 1.4.0 has no catalogs. Earlier public descriptor was a sign-in placeholder. No account or authentication bypass attempted.
- Highfly: current public configure page requires Turnstile verification for the free configuration. Its maintainer links Papacito status, so independence from existing AS supply is unproven. No challenge bypass or premium purchase.
- StreamNexus: public site works and advertises paid token access; maintainer offers a requested Discord trial. No trial account/token supplied and no message sent. Not omitted; playback remains access-gated.

References: https://pengu.uk/manifest.json ; https://sports.highfly.to/configure ; https://www.reddit.com/r/StremioAddons/comments/1wig8mj/addon_sports_streams_update_domain_change_nba_soc/ ; https://sports.streamnexus.cc.cd ; https://www.reddit.com/r/StremioAddons/comments/1xn62d4/addon_streamnexus_sports_premium_sports_events/

Phone, FPL, multi-stream and TestFlight are excluded. Cloud changes are not deployed. Alerts remain paused/dashboard-only.

The consolidated app also includes the previously staged Home/audio fixes from 239; this run does not independently qualify their live audio behavior. No settings/source toggles were changed. Owned build output was removed after installation and launch verification.
