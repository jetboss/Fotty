# Fotty 2.0.1 (139) private score and CS investigation

Jet iPad received this private candidate on 11 October 2026. The approved work
is official football score matching and remaining CS single-player playback,
including PiP. Shared TestFlight121 and owner phones125 remain unchanged.
Build139 does not qualify sustained CS playback or PiP.

## Repairs and source receipt

Official football scores, minutes and freshness use the full nonblank club name
instead of the short display label. This corrects the CRY/NFO versus Crystal
Palace/Nottingham Forest mismatch. Display labels remain unchanged. Competition,
date, opponent, orientation, stale-receipt and squad safeguards retain their
existing boundaries; the fuzzy fallback now requires matching squad qualifiers.
Five regressions cover the real official mapper through the service and Home.

The native relay stabilizes the first admitted CS segment wrapper when only its
reviewed Worker host rotates and the entire encoded query remains unchanged.
It never drops nested signatures or changes media bytes. Runtime profiles bind
the exact reviewed manifest delivery and headers, including headerless native
sources; they cannot be serialized. Existing destination, DNS preflight, TLS,
redirect and capacity controls remain unchanged. Finite HLS error classifications
retain actual NSError versus earlier AVPlayer error-log provenance separately;
descriptions, headers, URLs and tokens are not recorded.

- Capture: `backups/release-source/2.0.1-139-score-cs-stable-segments`.
- Commit: `13e93bb6a73bd789f40646826779e2af5a5eeb2b`.
- Source SHA256: `e107c0a1148b5d4c6384c9acfd21403ed6c564c57472a2d2a526457c5e27683e`.
- Bundle SHA256: `9de3a9000eb1203044317198446c6278eb6569219fd75cd0b270e31d32bb264b`.
- Signed executable SHA256: `d6ac36d1fec1e5a47c0848aadcfa300f063ebdf4e3b08a7f11dc9a637d8f82f6`.

The frozen1075-file comparison, strict deep signature, app/extension139 and
independent installed-app readback pass. Pinned Xcode27A266a completes1168
Catalyst tests:1166 passes, two existing optional skips and zero failures.
Offline membership tests32, version/catalog/provider checks, generic unsigned
iOS Release and signed UI-only Release build-for-testing pass. Earlier builds
while files were being edited are not coherent qualification evidence.

## Physical results

Fresh public add-on3.1.3 metadata supplies Real Sociedad versus Deportivo de A
Coruña at14:15UTC. Its first six admitted options contain five DaddyLive choices
and a sixth streamedpk delivery. CS labels are response-local, not permanent
provider identities. The physical gate explicitly requires that CS6 option;
fallback progress cannot qualify it. Muted tests do not qualify audio.

- Native CS6/control gate passes48.505 seconds. The exact selected source has
  ready inline video,1280×720 presentation and media-time progress. Sources,
  Close and return Home respond. This brief pass does not prove continuity.
- First PiP gate fails35.465 seconds before CS selection: the fresh stream-list
  request reports `streams_transport_failure` with `provider_timeout`. The
  other-provider fallback is not a CS or PiP result. No timer changes follow
  from this isolated timeout.
- Retry fails57.118 seconds before PiP. CS6 decodes, then fails at15:19:15UTC,
  roughly22 seconds after decoded start. The private ring records actual
  CoreMedia-12312 at failed-to-end and the distinct earlier log classification
  `segment_uri_changed`. Item/attempt replacement is correctly rejected by the
  continuity assertion. No background PiP receipt is claimed.

An independent bounded playlist reload at15:20:49UTC finds three overlapping
segments whose outer Worker origin changes while path and exact encoded query,
including the nested URL and signatures, remain identical. The nested segment
is `.image` on the exact `p16-common-sign.tiktokcdn.com` host. Build139's profile
excludes that host. The maintainer's pinned rewriter at
`700fad8343a057797eb37b30709b7be5f6dae599` documents TikTok-CDN image wrappers
and randomly chooses from the same reviewed seven Workers. This confirmed
predicate gap is repaired and tested separately in build140; no new destination
permission is required.

The original screen-recording test was interrupted before qualification and
replaced with screenshot-only XCTest capture. No incomplete runner is counted
as passing. Physical score rendering and the complete PiP background, Stop and
inline-return acceptance remain separate gates for the next private candidate.

## Official score facts

The official feed at15:17:07UTC reports Palace–Forest3–1 and Hull–Everton2–2,
both90 minutes with `finished_provisional=true`. Those terminal receipts should
remove finished matches from live Home; they must not be confused with missing
live scores. The earlier observed Palace score2–1 was a time-scoped receipt,
not the final result. No fixture data, stream enablement, backend deployment or
TestFlight release occurs in this gate.
