# Private build 324 — shared stream acceptance

## Scope

Owner approved shared acceptance across enabled providers, complete rejection accounting and one consolidated normal Watch check on Jet. Phone, FPL, multi-stream, provider settings, cloud publication and TestFlight are excluded. Pre-existing baseline edits are preserved.

## Contract

- `StreamDeliveryPolicy` is a separate shared module. HTTPS/public-destination, nested-media destination, credentials, request-header and actual DRM requirements are checked consistently. Optional null metadata does not declare a requirement. URL suffixes and provider-owned domains do not establish media content.
- HF/PP, CS, AS/Plavio, CNC, Flix and reviewed station deliveries retain each distinct URL/header contract. Malformed rows and notices are local to that entry. Exact fixture, squad, date, conflict, programme and terminal authority remain separate and enforced.
- Native HLS candidates use the guarded relay. Its root/variant roles survive redirects and extensionless URLs; playlist bodies are parsed within existing limits. Segment/key roles override misleading filename suffixes. HTTP provenance headers do not authorize HTTP media destinations.
- One admission ledger per lookup reconciles all observed response rows into candidates, duplicates, explicit policy exclusions, limits, withdrawn or unprocessed entries. Unread responses stay unknown. Partial failures and cancellation keep their observations. No URLs, credentials or programme titles enter these receipts.
- Discovery-cache, registered-binding and final-Watch filters produce separate selection receipts; they never inflate provider offered totals. Owner Status distinguishes candidates and observed first pictures and retains all reason counts in the same build/time scope.
- Score808 exposes a verified web page, not a raw stream list. Its raw counts remain unavailable. Retired StreamViX/StreamEx are not silently reactivated.

Safe candidate admission, HLS response validity, decoded frames and correct-programme observation are separate claims. This change does not make every advertised delivery playable or prove provider independence.

## Validation

The consolidated Mac Catalyst run executed 2,690 tests: 2,678 passed, 12 opt-in checks skipped, zero failures. The visual-regression suite was excluded; no simulator ran. The first failing run and its corrected assertions remain recorded separately in `initial-validation.json`. `local-validation.json` pins the passing source snapshot. Signed iOS Release app and widget 3.0.0 (324) compiled and passed signature verification. One normal app was installed on Jet; no test host or test-launch arguments were used.

Normal Home → Vegas–Nashville → Watch showed immediate discovery/Cancel feedback. The picker reached 26 choices: HF 7/7; CS 6/8 (two nested HTTP destinations); PP 13/14 (one missing URL). CNC timed out: its count remained unknown. Every known retained admission lookup reconciled. Source-selection receipts did not inflate those raw offer counts.

**Physical finding:** the initial HF1 decoded in 4.509 seconds but showed La Rochelle–Bayonne rugby. That is not a successful correct-match Watch result. HF2 showed Vegas–Nashville, corroborated by a fresh in-progress scoreboard, decoded 1.752 seconds after its attempt began, and advanced 92.438 seconds over a 92.439-second hold with zero recorded stalls. The source sheet retained all 26 choices. A later HF1 stall triggered normal automatic recovery through failed PP1 and CS1 attempts to the correct HF2 picture, 15.630 seconds after the source-failure record. This does not prove publisher independence.

Highfly reported one matched listing with seven deliveries. Existing receipts do not retain the selected listing's identity, so they cannot distinguish an upstream programme error from incorrect parsing of conflicting source metadata. Do not add a hostname exclusion or call all seven streams playable from this result. A future diagnosis needs the matched catalog/meta identity and its delivery association, captured without credentials or media URLs. The existing wrong-programme action is local to the fixture/delivery; it was not successfully exercised in this run.

Owner Status was visually verified on build 324: HF 72 offered/72 candidates across 10 retained lookups; CS 16/12 with four unsafe-link exclusions across two; PP 31 observed with three missing-link exclusions and one unread lookup; CNC offered/candidate counts unavailable with one failed read. These include renewal/repeated lookups, not 72 unique Highfly streams. The visible figures agreed with the independently reconciled ledger. Audio is not confirmed by Device Hub. Centre-control gestures did not establish a stable paused state, so no Pause/Play pass is claimed. This gate does not requalify PL, UCL, cricket, PiP or every advertised route.

Eight stable tracked settings, including source opt-ins and FPL preferences, were unchanged; the ninth tracked value was expected playback-health evidence from these tests. Phone, FPL and multi-stream were not operated or changed. No publication, cloud deployment or TestFlight work occurred. Small redacted evidence is in `physical-watch.json`, the two schedule receipts and `admission-summary-redacted.json`.
