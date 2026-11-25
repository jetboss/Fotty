# English TV discovery — 1 November 2026

Private Jet iPad build **2.0.1 (212)** adds **beIN SPORTS XTRA** as stable TV17, alongside original TV1–15. English-first presentation remains. The app resolves fresh metadata from the original reviewed iptv-org source at tune/renewal time; no LiveTVCollector service, local scheduled collection, new playlist origin or imported scripts are required.

Four leads were checked as one candidate. Actual native video through the normal TV Watch button, Fotty adapter and guarded relay qualified beIN: its watermark was visible, beach-footvolley action advanced and the score changed16–19 to16–22 during a hold exceeding90seconds. Final212 reopened it successfully; native fullscreen and Pause/Play pass; the picture advances again after Play ([control receipt](physical-212-controls.json)). Device Hub does not relay sound, so this receipt makes no listening claim.

| Candidate | Evidence | Decision |
|---|---|---|
| beIN SPORTS XTRA | Branded native picture and >90s advancing programme | Added TV17 |
| CBS Sports Golazo Network | Master/leaf HLS respond; actual relay media403, no picture | Excluded |
| Fubo Sports Network | Source-file route404; generated-US descriptor/current media examined; media403 | Excluded |
| Willow Sports | Current HD master responds; actual relay media403, no picture; other reviewed Amagi alternatives403 | Excluded; main Willow unchanged |

Fubo also exposed an audio/x-mpegurl descriptor MIME discrepancy. A source-scoped compatibility change passed local checks, but its subsequent bounded media check returned403. The unneeded Fubo origin/MIME change was removed. There is no geographic or access workaround and no unsafe retry campaign.

Initial211 passed333 focused units. After removing unqualified candidates, final212 passed all44 tests for the changed adapter and TV experience. Signed iOS Release, app/widget212, strict signatures and Jet install/fresh launch pass. All43 protected FPL/multi-stream Swift files match the starting hashes. Source choices/favourites and all6 protected preference keys match; test recents cleared back to zero. Jet is left idle in the TV tab. Original source choices remain; no phone, backend/Git publication or TestFlight action.

The current directory is useful for discovery, but is not a better runtime replacement: inspected collectors disable optional HTTP link checks, exports lose identity/header detail, and even a responding manifest can conceal refused media. These channels do not by themselves prove full Premier League/Champions League coverage or provide verified fixture assignments; existing typed programme/market/expiry rules remain.

Receipts: [final tests](final-focused-tests.json), [installed package](install.json), [initial physical observations](physical-211-observations.json), [qualification decisions](qualification-decisions.json), [CBS failure](cbs-failed-run.json), [Willow Sports failure](willow-sports-failed-run.json), [Fubo media](fubo-segment-check.json). Raw media locations, tokens, device identifiers, signing output and temporary products are not retained here.

Original references: [LiveTVCollector](https://github.com/bugsfreeweb/livetvcollector), [iptv-org source](https://github.com/iptv-org/iptv/blob/master/streams/us.m3u), [beIN's description of its free English XTRA channel](https://www.beinsports.com/en-us/soccer/articles/bein-sports-xtra-and-video-on-demand-launched-on-amazon-s-fire-tv-channels-2023-11-13).
