# CS/Willow matching and cricket TV placement — 1 November 2026

The owner approved the cricket matching repair, its protected backend publication/deployment and Jet iPad acceptance. Phone, FPL, multi-stream and TestFlight remain excluded. Fox delivery and English guide coverage were investigated after the owner reported those related gaps.

## Latest215 qualification and216 rollback

Owner subsequently approved the Fox HTTP chain.276focused transport tests passed, but native SD and independent HD decode showed a subscription-payment card, not Fox Cricket. Advancing HLS/decoder readiness did not qualify the programme. No account, payment or access workaround. CS Fox404 and final Flix Fox369504 remain; SpecialLinks8080 stays unsupported metadata-only and is not included in the payment-card conclusion.

216 removes unqualified TV20 and the unused HTTP/ATS/helper expansion. Preserve the prototype unapplied: [notes](Fox-Transport-Prototype-Notes.md), [native result](fox-215-native-observation.json), [Flix recheck](fox-flix-final-recheck.json). Pending-approval text below is a historical stage superseded by these actual results. Phone215 was installed only at the explicit later request; it was not agent-launched.

## Implemented matching repair

CS's dynamic FanCode catalog uses the observation clock as `released`; treating it as the match kickoff hid a current match. The source-local `current-listing` contract now requires its exact reviewed ID/envelope, fresh same-ID metadata and one uniquely matching fresh official LIVE ODI/T20 fixture. It does not manufacture a kickoff, format or ordinal from the channel. Ordinary dated-source matching, squad/date/conflict fences and delivery restrictions remain.

Official ODI/T20 match numbers are accepted only when the publisher's explicit ordinal fields and format agree. Main Willow accepts the publisher's literal ODI/T20 match programmes alongside Test programmes, using the reviewed station, exact participants/ordinal, unique IANA conversion and bounded current programme interval. A programme start remains distinct from the match kickoff. Replay, repeat, overlapping programmes and ambiguous sibling fixtures cannot supply a convenient association.

Production tests exercise the actual loader and Durable Object path: sibling identities are retained before admission filtering, so a hidden conflicting or finished sibling still prevents an ambiguous join. Runtime-only source clock annotations are stripped on persistence and rehydrated only from the strict original contract, preserving rollback compatibility. Older native clients retain their previous source projection.

Protected [PR116](https://github.com/jetboss/Fotty/pull/116) merged normally as `8298f54`. Worker and existing watchdog source `2026-11-01.cricket-matching-1` are deployed. All existing bindings, variables, source activation and retained incidents compare unchanged; a normal post-rollout collector completion was observed. See [cloud receipt](cloud-deployment.json).

## TV and guide findings

The native candidate groups main Willow, canonical Fox Cricket and Sky Sports Cricket in **Cricket channels** inside Sports TV. Favourites/recent stations retain their existing order without duplication. Fox keeps its existing canonical CS resolver; it is not assigned a fictitious reviewed playlist profile or a different station's programme guide. A regression caught and corrected the new inventory entry being incorrectly required to carry a generic TV binding.

The Spanish mini-guide comes from the reviewed Uruguay ESPN schedule. Most English stations have no equivalent integrated guide source; this is a source-coverage gap, not a language display bug. Fresh accepted main-Willow programme observations already feed its current-programme display. English stations must not borrow ESPN Uruguay times or an unverified timezone. Broad English Now/Next coverage is not claimed by this repair.

## Fox: verified failure and separate collector deliveries

Normal Jet213 Fox Watch selected CS1 and failed at `contract_validation` / `upstream_response` with HTTP404. One explicit Retry encountered a timeout, then the bounded retry returned404 again. No decoded picture was observed. See [retained failure receipt](fox-213-failed-watch.json).

The exact owner-supplied [LiveTVCollector](https://github.com/bugsfreeweb/livetvcollector) repository contains three actual Fox Cricket entries in its Bangladesh aggregate. Their original playlists were inspected: they use public HTTP-only HLS paths or a token-bearing wrapper; the opaque HLS path alone does not establish account credentials. No compatible advertised HTTPS alternative was established. The generic Worldwide “Fox Sports 4k” entry has US/DRM metadata and is not Australian Fox Cricket. Fotty currently uses selected original playlists plus its CS Fox resolver, not every delivery in this aggregate. Our CS404 therefore does **not** establish a global Fox outage or disprove the friend's different delivery. See [exact original-source comparison](fox-collector-contract.json).

The collector drops identity/header/DRM context from original playlists and disables its Worldwide link check. Its publication alone is not playback qualification. No collector scripts, opaque credentials, HTTP upgrades, access workarounds or new security exceptions were used.

## Historical Fox proposal — superseded by215 results

The owner correctly rejected leaving Fox at diagnosis. A fresh bounded inspection of the original time2shine playlist found that its literal SD/HD HTTP HLS manifests both return200, and subsequent SD media sequences advance. One bounded advertised segment contains H.2641080p video; audio and the actual Australian Fox programme remain unverified. The earlier inference that opaque path components established a subscription/account was unsupported and has been corrected. These transport/codec facts are separate from native playback qualification: [transport](fox-public-hls-transport.json), [bounded codec](fox-offline-codec.json).

A focused [unapplied repair proposal](Fox-Repair-Proposal.patch) adds one exact SD TV20 profile to canonical Fox Watch and fresh renewal, with a runtime-only root-bound HTTP grant and only its two advertised public segment addresses. It preserves other sources’ HTTPS policy, public-IP/DNS checks, redirect/header restrictions, source opt-ins and channel/fixture separation. The HD profile is not activated by this proposal. Current Apple documentation explicitly permits IP-address ATS exception entries on iOS/iPadOS17 and later; no global arbitrary-load or subdomain exception is proposed.

The patch applies cleanly, its Swift syntax and plist parse pass, and independent static review found no confirmed integration defect. Nine focused regressions are authored but **not executed**; no app HTTP policy or source edit has been applied and Jet remains on214. The owner’s new Fox-only HTTP decision is pending because current AGENTS.md excludes privacy/security changes from device-test approval. Actual guarded native playback, correct programme, audio and a90second advancing hold must follow approval; this is **not a Fox playback pass**. See [proposal receipt](fox-repair-proposal.json).

## Verification and remaining physical gates

- Protected backend:439/439; existing watchdog:186/186; both bundles pass.
- Native matching gate:189/189; registry validation:30/30; final TV/CS gate:169/169. These selections overlap and must not be summed. Initial failed runs remain distinct from the corrected passes. See [local receipt](local-verification.json).
- Signed iOS Release214, app/widget version/signature verification, Jet installation and fresh launch pass. The cricket TV section was observed in landscape and portrait, with no duplicated channels. Owner favourites/source choices are preserved; owner navigation during the gate was clarified as owner activity, not an app bug. See [installation](install-214.json) and [preservation](preservation.json).
- First214 Willow Watch decoded but later stalled: its upstream manifest request timed out after30seconds; automatic CS fallback also failed. The original publisher's fresh leaf subsequently advanced two sequence positions in18seconds. A later fresh normal TV Watch sustained advancing Willow-branded picture beyond eight minutes and produced a positive90second native continuity sample, with TV1 still selected and no recorded failure in that observation. This is channel playback, not proof of the upcoming third T20I or permanent reliability. Keep [failed run](willow-214-failed-watch.json), [causal relay facts](willow-214-relay-evidence.json), [publisher recheck](willow-publisher-recheck.json) and [fresh Watch](willow-214-fresh-watch.json) and [completed hold](willow-214-completed-hold.json) separately.
- Namibia–Ireland was already finished before this gate; it was not reused as a live playback pin.
- At the reviewed schedule receipt, Afghanistan–Zimbabwe3rdT20I was due at14:30UTC on1November, while main Willow's reviewed programme begins15:30UTC. Neither future time is a live playback pass. Fresh official status and descriptors are required at the actual window.
- New CS/Willow cricket playback through normal match Watch remains pending a current verified match and advancing correct-programme picture. Fox remains unqualified until a compatible delivery passes the actual adapter/relay and native playback.

No universal channel availability, complete English guide, live cricket playback pass or TestFlight readiness is inferred from passing metadata/unit checks.
