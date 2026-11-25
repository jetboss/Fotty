# AS football compatibility repair — 31 October 2026

Scope: AS football in the existing match-source path, Jet iPad only. Premier League first; Champions League code support retained. Phone, FPL, multi-stream and TestFlight remain untouched.

## Confirmed incompatibilities repaired

AS 1.9.130 now advertises Roxie event rows containing an explicit civil date and an undocumented “site time” clock. The earlier adapter could only associate its older explicitly UTC-dated SFLY/DLHD contracts. Its current same-ID HLS delivery also uses a different exact HTTPS origin than the earlier reviewed papacito contract.

The new source-local association uses the existing fresh accepted official fixture for the teams, competition, kickoff and status. It requires a unique senior-men team pair/date in that official snapshot, matching advertised source civil date, fresh request and snapshot receipts, no identity conflict, one compatible provider ID, and fresh exact same-ID metadata before requesting its stream. It does not convert the undocumented wall clock to UTC, create fixtures, infer LIVE, widen the ordinary football time fence or bypass the scheduled Watch policy. Latest LIVE status must itself remain fresh; a recent fetch alone is insufficient. Catalog channel-count text is cosmetic and may be absent from same-ID metadata.

The exact reviewed HTTPS origin admin2.formaturamaxi.com.br is admitted only on default port443 with one bounded HLS leaf and no query, credentials, fragment or encoded path. TLS/public-IP, redirect and header protections remain. The existing papacito route is unchanged. Stremio’s typed notWebReady boolean is a browser hint, not a native-HLS prohibition; nonempty proxy headers and unsupported transport contracts remain rejected.

## Evidence

The current provider advertised a valid media playlist and bounded MPEG-TS response at16:40UTC. This is contract evidence only, not decoded playback. See source-delivery.json. The current catalog default route and advertised search declare no pagination or required filters; Tottenham search was empty at17:04UTC. Empty provider rows are not a native playback failure.

101 focused tests completed:100pass,1 explicit physical-test skip,0fail. Signed iOS Release203 app and widget verified and installed/launched on Jet. The native UI source picker and decoded-playback acceptance remain pending until a freshly eligible advertised match is observed. No physical or UCL live pass is claimed from the synthetic tests.

## Current deployed-device outcome

At18:49UTC the provider advertised Tottenham–Palace and ESPN reported second-half play at61minutes. The official registry snapshot18:45 likewise reported LIVE, with status updated18:44. At18:53 exact same-ID meta corroborated the source row and two advertised descriptors both matched the reviewed HTTPS443/single-leaf HLS contract. No new media fetch or decoded test was substituted for the physical gate.

Existing build203 device diagnostics independently contain an AS1 decoded-progress receipt at17:17:07UTC, followed by session closure about2seconds later. The agent did not visually observe that playback or its programme, so this is actual decoder evidence but not the intended90second/native-controls acceptance. After the Mac lock cleared, Jet was black and devicectl confirmed passcodeRequired. Manual owner unlock was requested; physical acceptance remains pending.

52FPL/multi source hashes and all source opt-ins are unchanged. Four of six tracked FPL preference values stayed unchanged; existing manager-review/matchday-context cache bytes changed during normal app operation, without FPL source edits or UI testing. No private values were restored or copied into these receipts.
