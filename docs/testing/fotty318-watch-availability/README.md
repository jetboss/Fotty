# Match Watch availability on Jet

13 November 2026. Private, signed iPadOS Release 3.0.0 builds 318 and 319. The final build installed on Jet is 319.

## Reported symptom

Honduras–United Arab Emirates had an exact CS listing, but CS returned zero stream entries for that listing at the time of investigation. A partial Highfly result named a different opponent and Plavio was rate-limited. Jet 317 displayed “Broadcast information could not be checked just now” with only OK. The fixture had finished by the time the candidate was ready.

## Live Watch

At 16:22 UTC, one tap on Qatar–Australia from Home opened CS1. The live International Friendlies picture showed QAT 0–3 AUS and the clock advanced from 81:24 to 83:02. Jet recorded 16,881 ms from tap to first picture, 93,732 ms of native playback advance in 93,732 ms, zero stalls and zero source switches. Discovery returned two admitted choices. A Plavio 429 and a different opponent in Highfly's results did not interrupt CS1.

At 16:28 UTC, Home → Watch for Arabian Aces–UAE Bulls also opened CS1. The live Fox Cricket picture showed the Abu Dhabi T10, both team badges and Arabian Aces 27–5 after 4.4 overs. Jet recorded 27,673 ms from tap to first picture. Flix returned HTTP 503 and Highfly's teams differed during this lookup. CS1 subsequently stalled. Jet began fresh discovery before the tester closed the player; sustained cricket viewing and recovery were not verified.

## No stream found

At 16:30:33 UTC, tapping Kuwait–Syria in Home's Up next section started six eligible source checks. CS had the exact listing and zero stream entries. Highfly matched only one team, PenguPlay returned a candidate that failed admission, and Plavio returned HTTP 429. At 16:31:00 the app recorded no stream found. Jet displayed “No playable stream was found for this match. Some sources couldn’t be checked.” Tapping Retry started a fresh lookup for Kuwait–Syria on the same screen.

On this Retry PP1 produced advancing video after 21.7 seconds, but the picture showed an &TV HD entertainment promo. The match itself was never identified on PP1. The player subsequently displayed “No playable stream right now” and Retry. Investigation found PenguPlay's exact Kuwait–Syria catalog row and metadata explicitly listed a finished event with a possible replay. Build 318 discarded that field. The source-specific correction withholds that listing, even if another search still returns an older live row for the same ID, and consults current same-ID metadata when the provider advertises it.

On signed 319, tapping the same Kuwait–Syria fixture at 16:39:04 UTC checked six eligible sources and returned the partial no-stream message at 16:39:14. The entertainment channel never opened. Retry remained available on the match card after closing the alert. ESPN still listed this fixture as scheduled at the last pre-check. The contemporaneous football playback evidence was Qatar–Australia.

At 16:39:55 UTC on signed 319, Home → Arabian Aces–UAE Bulls → Watch selected CS1, and the first picture took 29,244 ms. The Fox Cricket live scoreboard showed both team badges and Arabian Aces at 33–6 after 6.2 overs. This run sustained 91,030 ms of native media advance in 91,030 ms with zero stalls.

## Regression checks

The focused Catalyst run passed all 290 tests with zero skips. It covered a listing losing its stream, an expired or mismatched choice, partial and fully unavailable source checks, Retry after a new stream appears, a fixture ending before Retry, and exhausting actual playback alternatives. The local Catalyst tests used the host-compatible 27.0 deployment target override. The Jet app used its normal signed Release configuration.

After the PenguPlay repair, all 188 selected tests passed with zero skips, including the provider tests covering a stale live listing paired with a withdrawn row, an independent live listing for the same game, and fresh metadata withdrawing a stream before it is opened. The two test runs overlap.
