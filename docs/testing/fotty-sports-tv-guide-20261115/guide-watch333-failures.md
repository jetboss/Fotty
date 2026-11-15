# Jet333 normal guide Watch failures — 15 November 2026

These are separate failed outcomes, not a playback acceptance pass. The normal
guide Watch action reached the selected station's existing resolution/player
path. A narrow channel empty-result wording repair was made; playback source,
ranking and transport policy were preserved. The accompanying
`guide-watch333-failures-redacted.json` contains only
typed local diagnostic fields and aggregate facts.

| Station/source | Observed boundary | Supported conclusion |
| --- | --- | --- |
| Willow TV1, first two attempts | CoreMedia -12642 while preparing; one master resource read four times per attempt; four completed relay requests and no failures; no media playlist observed | Startup failed before picture. The exact parser or compatibility cause is unproven. |
| Willow TV1, later attempt | First manifest request returned HTTP 404 | Confirmed upstream delivery failure at that time. |
| Willow CS1, two attempts | First upstream response failed with URL -1011; no HTTP status recorded | Response handling failed before picture. The receipt does not distinguish an invalid response from redirect/response validation. |
| Willow CS2 | App emitted `decoded_progress` at 16:25:53 UTC, then `stall_timeout` at 16:26:29 UTC | Diagnostic decoding occurred, but a stable physical picture hold was not observed. This remains a failed Watch outcome. |
| ESPN South TV2 | First manifest request returned HTTP 403 at 16:29:22 UTC | Confirmed upstream refusal; `accessDenied` classification is supported. |
| Sky Sports Main Event | CS discovery returned no accepted channel choice before player creation at 16:30:50 UTC | No playable descriptor was obtained. The match-specific error text is misleading for a channel; the underlying missing/rejected channel-row cause is unproven. |

TV1 and TV2 use different configured delivery origins. Their shared adapter
family is not evidence of one common outage or an app regression.

## Relay and publisher comparison

The first TV1 failures recorded matching upstream and rewritten master metadata.
`LocalHLSPlaylistProgress.observe` counts samples per resource; four samples with
only four total requests establish repeated reads of one master resource. Its
`latestSnapshot` prefers media observations, so a later master cannot hide an
earlier observed media playlist. The record does not retain the failure-time
playlist bytes or a typed parser complaint sufficient to explain CoreMedia's
numeric error.

A later bounded public recheck at 16:27 UTC returned a single-variant, 185-byte
master and a different 476-byte media child containing six segments. The child
reference differed from its parent. No segments were fetched. This establishes
the later playlist shape only; it does not prove device recovery or explain the
earlier responses. The source rewriter resolves full references against the
upstream base and maps complete URLs to local aliases. No concrete alias
collision or metadata corruption was established.

CS2's last observed upstream and rewritten media windows were both unchanged
for 9.393 seconds, with a six-second target and four segments. The snapshot was
5.631 seconds old at failure. Eighteen relay requests completed, none failed,
and one was in flight. The native access record showed 7,763,648 transferred
bytes, one stall and zero dropped frames. These facts support a nonadvancing
served window; they do not identify which upstream component stopped advancing
or prove that the relay caused it. This is distinct from TV1's startup failure.

## Sky channel boundary

`SportsTVView.watchChannel` passes `station.event` directly. `SportsTVStation`
constructs an undated channel event. `CommunitySportsAddonClient.resolveLookup`
checks its recognized TV-network path before fixture matching. `resolveChannel`
throws `matchNotFound` when no catalog row passes its strict channel identity
contract. Existing coverage includes the exact Sky station and its UK edition.

`HybridStreamProvider.communitySportsFailure` maps this shared error to
“A matching broadcast could not be confirmed for this match.” That wording does
not mean the request was routed as a match. The local admission ledger counts
stream offers, so an unread/zero stream receipt cannot distinguish an absent
channel catalog row from one rejected before stream lookup. No transport failure
was recorded for this Sky lookup.

The implemented small repair passes the existing request to failure presentation
and gives recognized channel requests channel-specific copy for missing choices,
empty stream lists and incompatible streams. Fixture wording, failure category,
retry/fallback behavior and diagnostic metadata are unchanged. The focused
`CommunitySportsAddonTests/testChannelEmptyMessagesPreserveDiscoveryFailureSemantics`
covers Sky and Willow plus unchanged fixture failure behavior. Root owns the
sequential compile and test execution; no competing build ran in this subtask.
`git diff --check` and the artifact privacy check passed locally. There is no
evidence supporting a relaxation of channel identity, added providers, changed
ranking or a speculative relay fix.

## Limits and retained scope

Only recent local quality records, current source and bounded in-memory public
playlist metadata were inspected. No media URLs, tokens, private identifiers,
hashes, response bodies or video are retained here. No further network probes
were made after the bounded investigation ended. Device interaction remained with the root
operator. Phone, accounts, security, cloud and distribution were untouched.
