# CNC football discovery on Jet

13 November 2026. The fixture was Grenada v St. Kitts and Nevis, senior men's Concacaf Nations League, official kickoff 19:00 UTC. ESPN fixture 401929713 and Jet's Home card showed first-half play. All times below are UTC.

## Before the repair

At 19:33 the deployed registry had zero links to the fixture. Two older LivXow records named both teams but had been classified as undated NHL listings. The collector assigned hockey to the mixed catalog without consulting the listing metadata. Private build 319 also excluded CNC football. At 19:39:18 Home → Watch on the Grenada card started six discovery lanes. PenguPlay supplied PP1, followed by a network failure at 19:39:57. The iPad showed Connection Lost. This attempt did not produce a verified picture.

## Publisher evidence

At 19:37, advertised team search found one LivXow ID and two PlayZTV IDs. The same-ID metadata identified football, both senior teams, the competition and the exact kickoff. Two listings reported zero servers. The remaining PlayZTV listing returned a support/donation link and an HTTP delivery. No media was requested from those entries. Server count and fixture identity alone do not establish playback.

[Official match](https://www.concacaf.com/competitions/nations-league/matches/9b785c7f11b84923a32fc454244500e3/grenada-vs-st.-kitts-and-nevis) · [ESPN match centre](https://www.espn.com/soccer/match/_/gameId/401929713)

## Private device checks

The repaired collector was run locally against fresh official and CNC data at 19:49:10 UTC. Six metadata requests returned three dated football listings. The registry associated the one positive-server listing as listed and left the two reporting zero servers unverified.

Normal signed build 320 was installed on Jet. Its existing CNC opt-in was on. At 19:51:20 UTC, Grenada's Home card showed 1–1 at halftime. Watch ran seven discovery lanes, including CNC. CNC recovered the fixture from direct lookup while the deployed registry had no link. Its 5,305 ms lookup found two advertised entries and rejected both. PenguPlay then briefly recorded a playing state, switched into recovery, and the screen ultimately showed “No playable stream right now”. The correct programme and sustained playback were not verified in that attempt.

The native regression suite exercised the off-page catalog results, the verified teams and UTC kickoff, mismatched squads and competitions, same-ID conflicts, partial catalog failures, compatible synthetic streams, registry-bound retries, and PlayZTV surviving disappearance of the LivXow catalog or optional search. All 105 selected Catalyst tests passed with zero skips.

## Second-half change

On normal Release 321, Match details → Watch at 20:09:41 checked seven eligible sources. ESPN had the match in the second half, 1–1 at 52′. At 20:09:52 the app showed “No playable stream was found for this match. Some sources couldn’t be checked.” CS found no exact fixture, Highfly returned another opponent, Plavio returned HTTP 429, PenguPlay timed out and CNC reported a fixture conflict.

A fresh check at 20:10 confirmed CNC had added a third PlayZTV ID since halftime. All three identified the correct teams, competition and 19:00 UTC kickoff. Two reported one server each and one reported zero. The two positive IDs advertised the same HTTP delivery and support links. This was a false identity conflict in Fotty. Both matchers treated a limit on how many listings they could inspect as evidence that the fixture was contradictory. No media or private URLs were retained.

The collector now checks distinct offers independently, rotates excess work within its existing budget and isolates individual IDs reused for different teams. At 20:13 UTC a local run against the live publishers used eight requests and returned two linked dated listings plus an unverified one. This verifies catalog discovery. The protected candidate passed 540 playback Worker tests, 225 watchdog tests and both bundle dry runs.

The private app repair checks at most three metadata responses and two stream responses per reviewed catalog on one lookup. If more distinct offers remain, Retry advances through them. A repeated provider ID naming a different opponent is isolated. Distinct verified IDs can contribute streams, and duplicate deliveries count only once. All 109 selected native tests passed without skips, including the nine-offer rotation case.

The [protected backend patch](protected-worker.patch) applies to origin/main at 3c3a2e5. It contains only the five registry source and test files for this change. The isolated bundle verification also used a matching new Worker revision. Publication and deployment are separate.

## Final live Watch on Jet 322

Normal signed Release 3.0.0 (322) was installed and verified on Jet. At 20:19:56 UTC ESPN showed second-half play, 3–1 at 62′. Home → Grenada → Watch at 20:20:09 ran seven eligible lookups. CNC found the match and checked four advertised entries in 2,524 ms. The exact listing no longer became an identity conflict. The two positive IDs carried donation links and the same HTTP-only media delivery. None were admitted. Highfly returned other teams, CS found no exact fixture, Plavio returned 429, and PenguPlay's stream endpoint returned 502. At 20:20:26 Watch displayed “No playable stream was found for this match. Some sources couldn’t be checked.” No match picture or automatic failover was verified. The earlier halftime PP1 admission and later HTTP 502 were separate attempts.
