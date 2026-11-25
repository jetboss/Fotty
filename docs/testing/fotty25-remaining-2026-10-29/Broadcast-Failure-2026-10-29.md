# Broadcast discovery failure — 29 October 2026

Read-only diagnosis against protected `main` at `70e8b10` and the current native candidate. No app/source-code changes, new source admissions, publication, deployment, device interactions or provider requests were performed by this investigation. The root agent owns the bounded live receipts below; no raw response bodies, media URLs, credentials or private device identifiers are retained here.

## Current evidence, not an assumed repeat of the previous outage

Root's bounded metadata and private-setting checks at **18:48–18:49 UTC / 14:48–14:49 Tobago** found:

- Worker health returned HTTP200.
- The official sports registry returned HTTP200, `verified`, 132 fixtures. Frosinone–US Lecce was reported LIVE with an18:46 UTC observation. This is a successful official-fixture receipt, not decoded broadcast proof.
- The admitted primary `.net` and mirror `.sh` master-catalog routes both returned302 to the same canonical `https://www.streamex.hn/api/live/matches/all` route.
- The admitted `streamed.pk/api/matches/all` backup returned301 to its root.
- One bounded canonical `.hn` GET returned HTTP200,3455bytes, `application/json`, but its parsed top level was a **scalar string**, not a match array or `{matches:[...]}`. No raw body was retained.
- A19:36:49UTC bounded classification found that scalar contains HTML, not a
  second serialized match-array document. Blind double-JSON decoding is not a
  compatibility repair. [Redacted classification](catalog-scalar-classification.json).
- AS and CS were both enabled on Jet iPad. Their default-OFF registration is therefore not today's demonstrated device-setting cause.

Native's bounded feed client follows redirects by default. A hostname migration alone is not a demonstrated native failure: the **returned catalog contract** is the concrete incompatibility. Native `NexusALiveResponse` requires an array or a `matches` array. HTTP200 and a JSON content type cannot establish that contract or playable supply.

The current evidence supports a primary broadcast-catalog failure while the fixture service remains healthy. It does not establish that every AS/CS descriptor is empty or that every stream fails. It does not justify automatically admitting the new host into delivery/security policies.

## What the existing watchdog actually checks

The watchdog is not limited to AS/CS descriptors. The reviewed inventory in `tools/watchdog/manifest.mjs:14`–16 explicitly checks the **same three master `/matches/all` routes** used by the native family:

| Source | Admitted origin and path | Scope |
| --- | --- | --- |
| Primary | `https://www.streamex.net/api/live/matches/all` | Bounded catalog JSON/row contract |
| Mirror | `https://streamex.sh/api/live/matches/all` | Same |
| Backup | `https://streamed.pk/api/matches/all` | Same |

`tools/watchdog/source-probes.mjs:121` requires an array or `body.matches`, unique bounded IDs, nonempty titles and a bounded source array with valid source/ID strings. It would reject a directly returned HTTP200 JSON scalar as a schema failure. Explicit reviewed closure markers are separately recognized; a generic scalar is not automatically called a published closure.

However, the observer deliberately uses `redirect: "manual"` and rejects all3xx responses (`source-probes.mjs:21`–22). Today's admitted endpoint responses should therefore generate **`redirect-rejected`** observations. The watchdog does not follow or inspect `.hn`, because that origin is outside this reviewed request inventory. This preserves its stated access boundary; it is not proof that `.hn` would play.

Native also tries complementary `/matches/live` and `/matches/upcoming` routes after `/all` fails (`AnalyticalDataEngine.swift:933`). The watchdog does **not** check those complements. It monitors primary-contract availability, not a complete replay of native fallback behaviour.

Additional admitted checks remain bounded:

- CS manifest and `nuvio_sports_live` catalog; at most one exact current supported football fixture's descriptor shape using an already-read verified sports snapshot. No returned media URL is fetched and no decoded playback is certified.
- AS manifest, old `plaviohd-live-sports` catalog and `plaviohd-cricket` catalog. **There is a real contract-parity gap:** native now prefers `plaviohd-football` when advertised (`PlavioSportsAddonClient.swift:127,138`); the watchdog still labels the old Live catalog as its football check (`source-probes.mjs:289`–290,326). A healthy generic Live catalog cannot establish that the dated football catalog works.
- Score808 listing/widget shape and official fixture integrity checks, not match-by-match playable coverage.

The15minute collector, repeat-confirmation rules and separate owner-delivery observer are already active in the reviewed baseline. Source code shows how failures should be classified; **this diagnosis did not poll current incident state or verify alert submission, email/push arrival or human receipt**. Whether today's redirect observations reached Jelani is a separate operational receipt to inspect, not something these code reads prove.

## Why healthy optional sources do not make the lineup resilient yet

1. **Browse inventory still has one family.** `AnalyticalDataEngine.swift:13` registers only `CoreMediaProvider`; its three profiles are primary/mirror/backup variants, not three proven independent deliveries. AS/CS are separately reviewed per-fixture lookup lanes. Their resolver already accepts exact current official fixtures without a primary broadcast descriptor; a new master listing is not technically required to check them.
2. **The route to check is buried.** Home installs its normal Watch action only for an active catalog descriptor or a fresh discovery-index candidate (`CurrentEventBroadcastPolicy.swift:31`–34; `SportsDashboardView.swift:1588`). An eligible source-free official match can be checked from Details (`CatalogEventDetailsView.swift:300`), but that extra route is easy to interpret as “nothing is available.”
3. **Short-lived discovery positives become a disappearing action.** `FixtureStreamDiscoveryIndex.positiveLifetime` is60seconds, whereas `FixtureStreamPreflightSchedule.interval` and per-provider cooldown are90seconds (`StreamDiscoveryCoordinator.swift:142,178`–179,378). One fixture is selected per turn; the resolver checks at most two rotating optional providers (`HybridStreamProvider.swift:417`). Thus even one healthy AS-only fixture can lose Watch between checks; several fixtures increase the gap. Existing96/day and24/hour preflight budgets also mean background-looking discovery is opportunistic, not a complete continuously fresh inventory.
4. **Details can contradict a successful optional lookup.** Its “Broadcast listed” decision checks primary catalog sources only (`CatalogEventDetailsView.swift:23`), even when a fresh optional positive has enabled Watch elsewhere. The text can therefore say “Broadcast not listed” while an AS/CS choice is known.

**Stable source availability is not the same thing as a playable descriptor's TTL.** Keep an honest current fixture/source state (`not checked`, `checking`, `options found`, `recheck needed`, `no options returned`, `source failed`, `disabled/unsupported`) separate from short-lived URLs and headers. An expired URL must never be replayed or labelled current; expiration should prompt a fresh lookup rather than remove the user's ability to check an eligible match. A descriptor-shaped success remains below actual native-decoding proof.

## Ordered repair and acceptance criteria

1. **Expose and unify fixture-first discovery.** Give an eligible current exact official fixture one visible Check streams action, including when the primary family is unavailable. Recheck identity, current status, enabled sources and timing at activation/completion; never turn a schedule row into guaranteed Watch. Make Home, Details and the picker render the same availability decision. Preserve existing choices and explicit source settings.
2. **Separate stable state from transient delivery receipts.** Retain informative discovery state while stale URLs require re-resolution. Fix the60/90second action gap without stretching a URL's expiry, weakening squad/date/conflict matching, increasing request budgets silently or inventing broadcasts. Test one fixture and several rotating fixtures across60/90seconds, app foreground/background and exhausted preflight budgets. Manual checking must remain available where current official authority permits it.
3. **Resolve the primary publisher contract on evidence.** Confirm an actual supported publisher API, its explicit match/source identity schema and maintained route before a source-local adapter repair. Otherwise classify that family unavailable and keep independent lookup usable. A redirect target, valid JSON scalar or public HTML page is not sufficient. No automatic host-trust or security exception is authorized.
4. **Bring monitoring into consumer parity.** Review the current AS football-catalog contract explicitly, then update the finite watchdog check to follow the same reviewed catalog selection as native. Decide whether complementary native fallback routes need bounded observation within the existing request envelope; do not silently add probes. Keep redirection/migration diagnostics separate from actual schema and playback health. Verify normal incident-to-owner delivery independently from a synthetic canary.
5. **Close the separate partial-admission gap through its own tested gate.** Protected main still rejects a whole football collection when one accepted row disappears/conflicts, and its aggregate route returns503 if no cohort is covered. The locally staged per-record isolation/partial-response changes can preserve healthy explicitly admitted siblings while quarantining the disputed row. They are unpublished and are **not** included in the focused cricket/UCL score-context candidate. Today's verified132-fixture response does not demonstrate this503 failure, and publishing scorecards will not repair broadcast discovery.
6. **Qualify independent supply, not more wrapper labels.** For required PL/UCL/cricket coverage, establish actual independent upstream/catalog and delivery ancestry where inspectable, exact fixture matching, maintained compatible contracts, TLS/header/redirect compatibility, and recovery behaviour. Different AS/CS labels or manifests can still share an upstream. A candidate must pass real adapter discovery, correctly observed programme, advancing native decoded frames, basic controls, fullscreen and PiP in the existing picker. Empty overnight catalogs remain pending; generic channels and HTTP200 are not a pass.
7. **Keep outage regressions as release criteria.** Simulate the master family redirecting, returning HTTP200 scalar, returning malformed/empty arrays, and failing while one optional lane succeeds. Healthy alternatives must survive discovery completion and remain reachable; the UI must distinguish untested, unavailable and decoded failures. Keep context authority, exact matching and token expiry strict. Then use the already-approved Jet-only physical gate; no phone/FPL/multi-stream or TestFlight changes.

No application can promise that a third-party publisher never disappears. The durable product requirement is that one family's failure cannot hide healthy alternatives, false health cannot stand in for playback, and actionable catalog-contract failures reach the owner with evidence.

## Operational receipt —29October19:11UTC

A bounded read of the latest two NORMAL observer runs included all statuses,
not only successes. Both were scheduled successes on70e8b10, at14:40:48UTC and
07:42:06UTC, each recording delivered0/pending0. Published schedule is minute
7/22/37/52 each hour. At19:11:25UTC the latest observed completion was4h30m37old,
above the35minute stale bound; the response included no newer queued/in-progress
run. This is a stale delivery-observer receipt, not proof that cloud collection
itself stopped.

[Primary incident96](https://github.com/jetboss/Fotty/issues/96) and
[mirror incident97](https://github.com/jetboss/Fotty/issues/97) remain open and
assigned to the owner. Both record confirmed catalog/metadata-unavailable at
28October22:50:38UTC (18:50Tobago). Matching owner-event bot comments were submitted
29October01:51:23/25UTC, about three hours later. Thus the recorded condition
predates today's check; actual publisher-change onset is unknown. GitHub receipt
submission is verified, while email/chat delivery and human receipt are not.
Latest run: [40893838497](https://github.com/jetboss/Fotty/actions/runs/40893838497).
No acknowledgements, issue changes, job reruns or state writers were used.

## What established systems actually offer

- [Netflix Live Origin](https://netflixtechblog.com/netflix-live-origin-41f1b0ad5371)
  documents independent regional live pipelines and server-side selection of
  valid segments. This depends on control of contribution/encoding/origin assets;
  it does not make arbitrary outside sports links equivalent or synchronized.
- [Apple HLS Content Steering](https://developer.apple.com/videos/play/wwdc2022/10144/)
  supports prioritized equivalent CDN pathways and fallback. The publisher must
  author those alternatives; Fotty cannot manufacture redundant media by rewriting
  hosts or attaching a steering tag to unrelated streams.
- [Disney Media Engineering](https://sites.disney.com/lifeatdisney/work-and-innovation/2024/08/02/how-media-engineers-enable-disneys-streaming-connection-with-audiences/)
  describes managed partner ingest, normalized metadata and readiness checks.
  Fotty's smaller equivalent is an owned normalized catalog contract layered over
  separately reviewed provider adapters and official fixture identities.
- [Stremio's capability planning](https://github.com/Stremio/stremio-core/blob/3417c2e7ed45cdbfd86b3226f69814c2dc4947ad/src/types/addon/request.rs#L359-L368)
  separates catalog and stream resource requests. Retained shipped Web evidence
  independently shows useful results while sibling groups load/fail. This is the
  closest supply model to Fotty; it does not guarantee a withdrawn add-on survives.
- [AWS streaming guidance](https://docs.aws.amazon.com/wellarchitected/latest/streaming-media-lens/smrel03.html)
  recommends independent origins/CDN failure domains, pre-event preparation and
  origin-to-player measurements. Its [API canary guidance](https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html)
  supports testing reviewed adapter changes before broad promotion. These are
  operator practices, not unverified claims about ESPN/DAZN internals.

The practical next milestone is to extend the existing fixture/discovery owners:
first-class independent availability on Home/Details, stable availability state
separate from expiring descriptors, a maintained backend normalization boundary,
proven independent supply, and delivery escalation independent of this Mac and
one best-effort scheduled observer. Preserve current exact matching, supported
scope, source opt-ins, TLS/redirect/header restrictions and bounded request budgets.
The decisive release drill is a broken primary family with a genuinely working
independent candidate: normal fixture selection must still discover and decode
that correct programme on Jet, with native controls/fullscreen/PiP intact.
These are reviewed recommendations; no architecture/deployment changes are made
under this discussion.

## Actual Jet186 check —29October19:38–19:39UTC

The normal UI gate selected a freshly verified exact Frosinone–US Lecce fixture,
opened Match details and invoked the existing Check streams control. No player
opened within the bounded gate. The test therefore skipped before decoded
programme, native fullscreen or PiP, and qualifies none of those stages. It does
not prove all optional providers fail, or establish required PL/UCL/cricket
coverage. The separate complete native-key Cricket Search passed; the original
burst typing acceptance remains unresolved. See [physical gate receipt](physical186-summary.json).
