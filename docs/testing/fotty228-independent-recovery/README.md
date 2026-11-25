# Fresh match and independent recovery gate — 3 November

Owner requested fresh live Watch timing, a forced stream failure and an automatically selected independent backup on Jet iPad. No phone, FPL, multi-stream, publishing or TestFlight work.

## Source repairs and checks

CNC's verified NHL path returned sessions without the binding required by the shared-registry resolver. The adapter now carries its exact verified metadata/stream ID through publication, and the existing same-choice resolver renews CNC descriptors after metadata expiry. It re-verifies both teams, NHL, UTC time and the same delivery path, headers and public HTTPS contract.

CNC publishes single-digit dates as `Nov 04`. The old parser required `Nov 4`, so metadata with the current publisher format failed. Both explicit forms now round-trip through the UTC formatter. Invalid days and ambiguous dates remain rejected.

Exact NHL nickname mappings in CNC were limited to four teams. The 3 November NHL scoreboard corroborated the additional nicknames against tonight's official fixtures. Current CNC catalog/meta names such as `Maple Leafs vs Mammoth` and `Devils vs Oilers` now match full NHL fixture names. Unknown extensions, squad qualifiers, different dates, conflicting IDs and unreviewed leagues remain excluded.

64 focused CNC/discovery tests passed on Jet. The regression exercises the real registered resolver for Toronto–Utah, plus its binding and renewal eligibility. A mocked fixture test is not live playback evidence.

The current CNC delivery advertises a new `edgestream2.pro` HTTPS host, changed headers/shape and a full-date metadata entry. Its playlist returned HTTP 403 HTML before kickoff and again after the NHL reported Toronto–Utah live. It remains outside the admitted delivery profile. No header guess, arbitrary domain grant, security exception or access workaround was added.

## Physical results

The outage-only build runs the ordinary selection policy via a private test environment flag. The injected fault affects only the selected AV item. The failed route remains held unavailable while the app chooses its own replacement. Test screenshots and AV ownership must corroborate the actual programme and sustained new item. Different publisher plus different public origin is a lower bound on delivery separation, not proof of ownership or all upstream independence.

Toronto–Utah was live in both NHL and Fotty at 00:10 UTC on 4 November (8:10 p.m. Tobago, 3 November). Normal Watch reached advancing CS1 video in 8.14 seconds, but screenshot review showed TSN's regional-unavailability slate. That is NOT time to the correct game. CS1's 90-second advancing hold does not make that programme playable.

The first cut reported CS2 in 0.87 seconds, but the item changed before its hold. This timing is rejected. The measurement initially accepted an old item under a new attempt token. The physical helper now also requires a different AV item from the cut source before timing a replacement. No passing independent recovery is claimed for this run.


## Final real-game result

The corrected 228 drill passed on Edmonton–New Jersey. TV4 showed the correct NHL game in 7.46 seconds from the normal Watch tap. After an uninterrupted 90-second primary hold, the controlled TV4 loss selected CS4 automatically. A genuinely new AV item showed advancing replacement video in 4.89 seconds. The first replacement picture was an ESPN commercial-break slate. At the end of the uninterrupted 90-second replacement hold, the screenshot showed EDM 1–0 NJ, period 1 at 9:13. Separate provider and public origin assertions passed. This verifies two working delivery paths and automatic recovery from the injected route loss, not immunity from every shared upstream outage. See live.json.

The app's cached NHL fixture still showed scheduled while the fresh original NHL schedule reported LIVE. The test pinned the existing exact Fotty match only after independently checking the same NHL team IDs and UTC start against that schedule. No fixture was altered or status invented. The stale observation is an additional backend freshness finding, not a reason to substitute a different game.

A second timing error was corrected in the measurement layer. Its existing item token included attempt identity and could change before a new AV object arrived. A separate weak AV-item identity now distinguishes a real replacement from an old item under a new attempt label. 24 native measurement tests passed. FPL and multi-stream behavior were not changed. Restore Jet's normal signed 228 after this private drill.
