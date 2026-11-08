# Fotty 2.0.1 (172): restore CS discovery; Premier League playback remains open

24 October 2026. Private Jet iPad repair and live Premier League gate only.
Keep FPL, multi-stream, phones, source enablement/admission policy, backend, publication
and TestFlight unchanged. Premier League and Champions League are required
football qualification targets, not inferred guarantees of every delivery.

## Confirmed cause and focused repair

At14:04–14:14UTC, ordinary CS football/Live catalogs returned100 rows without
Arsenal–Everton. Its advertised team-search endpoint returned the exact senior
fixture, explicitly dated24October14:00UTC, and multiple stream descriptors.
Jet171 had CS enabled, with `no_exact_fixture_match` receipts while AS succeeded.
This was a discovery gap, not proof that the provider had no streams. The separate
LS lane remains NHL-only and does not count as a football-source addition.

CS now reads the manifest's advertised `search` capability. Only after ordinary
catalogs miss, it makes at most two explicit participant-name searches on the
first reviewed searchable catalog. Search hints never establish fixture identity.
The existing shared exact sport/team/squad/date matcher remains authoritative.
Completed ordinary and search rows are combined, retaining metadata-ID/stream-ID
and malformed/conflicting sibling vetoes. Ordinary hits/conflicts do no extra
search. Search results are not persisted into ordinary catalog caches.

The real Home fixture uses Arsenal FC/Everton FC, while the publisher's literal
FC searches return empty. Only football input with FC/AFC/CF and an existing
reviewed canonical club identity gets a reviewed short search hint. Existing
bare aliases such as Brighton stay literal; unknown/women/youth/reserve names
are not stripped. Full original fixture identity still owns final admission.

Fixed same-origin routes, encoded single path values, byte/row/request bounds,
the parent18-second deadline, cancellation, media admission and relay/security
policies remain unchanged. No arbitrary manifest, URL injection, access workaround,
new transport or source-enable default was introduced.

## iPad identifier rejection and working-source comparison

The retained build140 source bundle at commit
`1477a54d5b3deb1f97308916eab0704a6d542b91` uses the same identifier prefix,
240-character limit, Unicode-alphanumeric plus `-_.~` character set and
`defaultVideoId ?? id` handling as the pre-repair adapter. The deleted temporary
171 snapshot could not be recovered; its earlier CS6 Rayo–Elche playback receipt
does not prove every fixture worked. No verified provider schema change explains
this incident, and no newly tightened character policy was found.

Jet's optimized Release172 diagnostic rejected an identifier as
`streams_unsafe_stream_id_characters_unresolved` at15:16:45UTC: the bound-method
predicate rejected the value while the separate explicit character check found
no forbidden scalar. Fresh public Arsenal–Everton metadata repeatedly supplied
an identifier of42 permitted ASCII characters. This is observed application
validation inconsistency, not proof of an Apple, Swift or compiler defect.

Admission and diagnosis now share one explicit scalar walk rather than
`allSatisfy(allowed.contains)`. Prefix, length, permitted characters, ordering of
checks and network/media safeguards are unchanged. Subsequent real iPad requests
report `exact_fixture_match` and show CS rows again in the normal picker. That
closes the observed missing-CS rejection, not sustained source playback.

## Local verification completed

- Thirteen focused new regressions cover the observed100-row Premier League
  omission, a Champions League club pair, unadvertised search/no extra lookup,
  wrong date/sport/squad, conflicts across ordinary/targeted responses, reserved/
  Unicode path encoding, cancellation, fresh search/no cache contamination,
  actual FC-name hints and preservation of unknown/qualified squad names.
- Final focused Catalyst gate after the explicit-walk repair:
  **161passed,0failed/0skipped**, no runtime warnings:105CS adapter tests,
  9shared fixture matcher tests,14discovery coordinator tests and33transport
  resource/safety tests. Added exhaustive independent ASCII expectations,
  retained Unicode behavior and the complete observed Premier League ID through
  both ordinary and advertised-search resolution using official FC names.
  No simulator used. Static Champions League matching is not live UCL playback.
- Source membership and app/extension Debug/Release versions pass. Signed
  Release172 app and focused physical UI runner compile; strict/deep app
  signature verifies. Existing unrelated compile/deprecation warnings remain.
- Independent source review found no blocking defect.

## Physical gate: exercised, not qualified

Real Arsenal–Everton and Coventry City–Fulham Home Watch and existing source
pickers were exercised on Jet. Fresh ESPN Premier League status independently
confirmed both fixtures live, dated24October14:00UTC; the last pre-test check at
15:51:36UTC reported90′+3 and90′+2 respectively. Kickoff alone was not used as
live evidence. See the [dated official-publisher scoreboard](https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=20261024).

Acceptance requires the requested CS row selected, ready native video, correct
programme and advancing media for90seconds (at least80seconds progress), with
the same player/item/attempt. No automatic fallback can qualify the requested
source. These ready-layer samples are not continuous decoded-pixel counts or
audible-output proof. Native Pause/paused return/re-entry/Play/Done are also
required before calling the focused fullscreen gate passed.

The initial four diagnostic attempts and scalar diagnostic rerun all skipped,
not passed. An overly broad intermediate search-hint normalization caused four
existing local tests to fail by expanding Brighton; the narrowed repair retains
their original expectations. Final161-test verification supersedes those earlier
local failures, not the still-open physical gate. Fixed stage/reason diagnostics
never retain IDs, URLs, queries, redirects, credentials or response bodies.

Six subsequent requested-source checks returned0passes/0failures/6skips:

- Arsenal CS2 and CS3, plus a later CS6: selected Streamed-family deliveries
  returned actual upstream media HTTP403 through the guarded relay. Recovered
  non-CS playback was not counted as success for those selected sources.
- Arsenal CS1: one Daddy-family variant hit the five-second contract probe
  deadline while its relay request was pending. A later variant returned HTTP200
  manifests but failed with actual CoreMedia-12312 and `segment_uri_changed`.
  No evidence justified blindly increasing a timeout or broadening the segment
  stabilization profile. A bounded current576p playlist comparison returned
  unchanged overlapping URIs, but was not the exact failed signed variant and
  did not reproduce or resolve that failure. No segment bytes were fetched by
  those diagnostic playlist checks.
- Coventry CS1: the explicitly selected PPV-family option failed with native
  code-11867; fallback CS2 produced brief ready1920×1080 video and time progress.
  That is neither a CS1 pass nor the required90-second selected-CS2 hold.
- Final explicit Coventry CS2 check: the new CS stream-list request timed out
  after11.192s, so the requested row was absent. AS discovery succeeded in1.627s
  in the same attempt. The gate did not substitute that sibling or invent media.

No requested-source90-second hold/native-fullscreen control pass was reached in
this repair gate. Correct-programme screenshots of a fallback do not qualify CS.
Premier League sustained playback therefore remains open. Champions League
lookup support/regressions remain intact; live UCL playback is separately open.
No timeout, playlist-identity, transport, access or security exception was added.

## Preservation, installed artifact and cleanup

Normal signed Release172 was built, strict/deep signature verified, installed
in place, independently read back as2.0.1(172) and launched without test arguments.
All44 protected FPL/multi-stream/approved-layout source hashes, four private FPL
values and all five source-enable states compare unchanged. AS stays enabled on
Jet as it was at this gate's baseline; no source defaults were changed.

Pre-build private source receipt:1140 inputs, temporary history-free commit
`48d97a3eb230b3c104baeb21ad0c7ff2eff4fd6f`, source SHA256
`26399c132e4947c8e7a15a5b3faddbaf63cf90fccb8373bff33038472eedeae7`, bundle SHA256
`86a943f27d0ad1f305d255e2ce00a89760be6c871b854b5058b53a9f4cf9a320`.
Normal executable SHA256:
`84d53db9cebf9d00e9b4ec26922be4d3b1cd6f0d2e49e2cd7b7cbec4a1220004`.
Frozen-source comparisons pass before and after installation, prior to these
documentation-only closeout edits. No real Git refs/index/remotes changed.

The owned UI runner and temporary scheme were removed. The1.1GiB owned gate
(build/results, copied preferences, source snapshots and screenshots) and its
awake helper were removed and absence verified. Disk readback at close:14GiB
free; unrelated artifacts/caches were untouched. Shared TestFlight121 and
phones125 remain unchanged.

## AS selection discussion (no ranking change)

The owner identifies AS as a benchmark for reliable, fast-starting additional
coverage. Current selection uses local successful-start confidence, mean recorded
startup, recency and last-good sport/league family, not a live fastest-start race.
History is coarse provider-family plus host. Equal-score fallback tiers favour
Score808/StreamEx and other legacy web families over AS/CS/LS; AS is not globally
disabled or explicitly made first. Existing healthy playback is not automatically
replaced. Static inspection does not identify the winning score for an individual
Jet choice. Future prioritization must use decoded-start evidence and genuinely
additional delivery coverage rather than label count. No AS adapter or selection
policy changed in this repair.
