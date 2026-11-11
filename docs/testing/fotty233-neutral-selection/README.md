# Build 233 — provider-neutral Watch selection

4 November 2026. Owner reversed the unfinished TV-first proposal: retain CS/AS/TV and rank admitted match deliveries by evidence rather than provider label. Jet iPad only; phone, FPL, multi-stream and TestFlight excluded.

## Implementation

`LiveSourceHealthStore.rankedSingleStreamSessions` retains all candidates. Current same-match failure/wrong-programme evidence revokes older positive holds; sustained exact-delivery evidence beats a fast start alone. Similarly reliable deliveries compare recent measured startup speed. Unknown commentary language no longer automatically pushes CS/AS behind known-language TV before speed; known language mismatch remains respected. Station-language ordering and legacy multi-stream ranking are unchanged.

Removed the unfinished TV-only promotion and extra discovery wait. There is no fixed TV/CS/AS provider preference. Startup speed is not venue-to-picture latency; this change makes no unsupported closest-to-live claim.

## Verification

- 116 focused XCTest passes on Jet, two optional production-network tests skipped, zero failures. Both new neutral-ranking regressions passed, including every CS/AS/TV winner, reversed candidate order, retained alternatives and current failure revoking a previous hold.
- Signed Release 3.0.0(233) compiled, signature verified, installed and launched normally on Jet.
- Normal Sports TV Willow Watch opened TV1. Decoded progress at 09:58:43.844 UTC; moving Willow pictures observed. Source sheet retained TV1 and CS1. Manual CS1 selection at 09:59:22.923 UTC decoded at 09:59:26.914 UTC, with moving same-channel cricket pictures observed. This was a short selection/playback check, not a new 90-second qualification, independent-publisher proof or forced-outage test.
- Picture was women's REN–HUR cricket, not UAE–Oman or the completed NZ–India match. Do not use this station test to claim an exact official-fixture Watch pass. The displayed Willow programme guide still showed NZ–India; existing guide integrity remains a separate issue.
- 42 protected FPL/multi file hashes and 16 protected preferences unchanged. No phone, cloud/Git publication or TestFlight operations.

## Live-match gate remains blocked before ranking

Fresh official ICC status identified UAE–Oman, CWC League 2 Match 145, ODI, 4 November 05:30 UTC, in progress. New Zealand–India was finished and excluded. Registry listed current-event CS coverage for UAE–Oman. Normal Watch at 09:53:56.827 UTC failed discovery: CS conflicting_fixture_match, AS no_exact_fixture_match, Flix catalog_http_failure (HTTP 503).

Fresh CS same-ID metadata retained released=09:31:43.399 UTC at 09:56 UTC. That is outside the native currentCricketListingIdentity freshness range (-300...600 seconds), although a previously accepted registry association still existed. This is evidence of a registry/native freshness disagreement before ranking; no adapter guard was widened. Corroborated title/team/status fields alone do not make this a decoded-match pass. Follow up by aligning current-event evidence leases/refresh semantics across collector and native consumer, with a regression at the freshness boundary; do not label this ranking repair fully live-match-qualified.

Receipts: unit-results.json, official.json, quality-redacted.json. No raw stream URLs, tokens or private identifiers retained.
