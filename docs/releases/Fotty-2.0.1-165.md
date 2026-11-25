# Fotty 2.0.1 (165): source selection, CS and single-stream recovery

Historical165 baseline; the subsequently approved official-fixture CS lookup and
current delivery-admission findings are in [release166](Fotty-2.0.1-166.md).

23 October 2026. Private Jet iPad update only. FPL, Watch Two/multistream,
phones, TestFlight, cloud configuration, source activation and Git publication
remain unchanged. No new provider, trust exception, paid service or simulator.

## Repairs in the approved order

1. Shared discovery reserves retained-result capacity for independent pending
   provider families. Validated same-family siblings wait in a bounded buffer;
   empty, failed or exhausted families release reservations. Published choices
   are never evicted. Existing result/concurrency limits and attempt deadlines
   remain. Owning cancellation or grace expiry discards unpublished siblings;
   a six-result maximum is not a promise of six sources.
   Shared embed validation now checks every redirect and rebuilds scoped cookies
   for its destination. Rejected redirects cancel the unfinished response and
   return a typed non-retryable admission error, rather than timing out while
   reading a refused redirect body. HTTPS/origin/port and redirect limits stay.
2. CS decodes stream rows independently within the existing 100-row bound. A
   malformed delivery/header row is rejected without losing valid siblings;
   malformed top-level documents remain failures. Manifest cache publication is
   generation-fenced. Failure of an advertised preferred catalog stays visible
   when optional Live fallback cannot establish a match. Ordinary unadvertised
   empty fallback, conflicts, cancellation and delivery safety retain their policy.
3. A background native PiP observation lease can rearm the existing foreground
   watchdog for the exact player/item/source/request. It issues no Play, reload,
   seek or new retry policy. Pause, replacement, failed ownership and non-single
   routes cannot inherit the observation. Home and Matchday reopening an eligible
   retained single session preserves its source, attempt and paused state instead
   of resolving it again; current identity, timing and conflict checks still apply.
4. Search joins exact reviewed team aliases to the current Home catalog, including
   official football names with legal FC suffixes. This is Search-only canonical
   enrichment, not fuzzy stream matching. Women/youth identities, sport scoping,
   literal search, exact league filtering and ordering remain fenced. Loading
   content adapts between full artwork, compact artwork and readable scrolling;
   redundant loading text and overlapping single-player transport controls are
   removed. VoiceOver/Switch Control keep single-player controls available.
   The empty-interest action now says “Remove interests filter”. Sport artwork
   and club badges remain intact under the Apple UI design guidance.

## Verification and final installed source

- Final simulator-free suite: **1,611 passed, two existing optional skips, zero
  failures / 1,613 total** in a freshly compiled Catalyst test host. Generic
  unsigned iOS Release and signed Release pass. Strict signature, app/extension
  build 165, Jet installation/readback and normal launch pass.
- 32 native-source tooling tests, 13 snapshot-tooling tests, 54 Node tests and
  five provider-identity vectors pass. Native membership/version and scoped diff
  checks pass. All 42 FPL hashes and three captured multistream-specific hashes
  equal the task baseline. Pre-existing FocusState/test-window warnings remain.
- Initial failures exposed the refused-redirect body defect and incorrect test
  fixture assumptions. Those were corrected before the clean gates. An initial
  visual fixture lost synthetic cached artwork; focused and full reruns pass the
  unchanged approved PNGs. Memory pressure is plausible, not established as cause.
- A physical Search failure on the first installed candidate prompted the narrow
  legal-club-suffix follow-up. Its first helper missed `nonisolated`; that compile
  error was fixed before the clean final gate. Only the final candidate below is
  the installed source. All 1,121 frozen inputs compare before installation and
  after physical source checks, before these documentation-only closeout edits.

Final source SHA256:
`7427e0faa7aa84f6a5f467d2325fbe1542a1dcc66d6556640ab491f03ae1df72`

History-free temporary snapshot commit:
`b3d986ae3fc47f85f600362af2bcb8c64bda222a`

Temporary bundle SHA256:
`f4cc1e1374fdec0ce839da67e53abdc9fa3264c1f38a77297a19cf065df300b0`

Signed executable SHA256:
`c6e3ee82b8e1ba1c66a6523597129fe58eb52b237d2948e4889dc41309e43755`

These temporary private-test receipts are not a retained shared-distribution
candidate. The real repository index, refs and remotes are not changed by them.

## Actual final Jet iPad checks

Jet iPad Air 4, iPadOS 27.0.1, Light appearance and portrait. The complete
“Nottm forest” query now returns the same Ipswich–Nottingham Forest fixture as
Home, with badges/countdown and no invented Watch action. Source picker opens
and selecting Broadcast 2 changes the decoded Willow channel video. The compatible
native handoff and actual AVKit fullscreen show advancing video.

Explicit fullscreen Pause remains paused for over a minute. Returning inline,
minimizing, navigating to Home Cricket and tapping that channel’s Watch action
reopens the exact paused picture with the native fullscreen action still present.
No new discovery receipt appears; explicit Play resumes advancing video. The
current attempt is `4D247B43-95F1-4232-ADD2-5F725D90C0B8`, source
`58EDFAB4-3124-4D2B-AC16-6E87CF088319`.

The final candidate continues decoded PiP on Springboard for more than 60 seconds
after backgrounding at 16:54:48 UTC. System PiP Pause visibly shows a Play triangle
and holds the identical umpire picture from 16:56:54 through 16:58:13 UTC. Explicit
system Play resumes changed video; Restore returns to actual AVKit fullscreen.
The `restore_retained` and `pip_did_stop` receipts retain the same source/attempt
and presentation `F40975B7-188D-44E5-962E-659A33AAFEB7`. Returning inline is
exercised before final media cleanup. These are time-scoped single-stream passes,
not a claim about every upstream programme or audible output.
The earlier installed candidate also passed >60-second background PiP and actual
Restore with matching attempt/presentation receipts; it is not substituted for
the final candidate’s acceptance.

## CS coverage and remaining qualification

CS remains enabled on Jet; it was not removed. At 16:37 UTC two bounded metadata
catalog reads return HTTP 200 and explicitly list Afghanistan–Zimbabwe in cricket.
Home’s corresponding official fixture has no primary broadcast descriptor, so
the existing policy offers Details but not Watch and never starts CS discovery.
CS was approved as extra options for already-watchable matches, not a fixture
source. Search finds neither the Orenburg nor Saratov alternative in the current
primary lineup, including after one ordinary refresh. Generic Willow records
`no_exact_fixture_match`, which is correct and not an upstream outage receipt.

Consequently **current CS decoded playback remains open**. Successful metadata,
parser tests and older CS playback cannot close that physical gate. A future
separately scoped “Check streams” action could let verified source-free fixtures
request opt-in discovery, retaining exact sport/team/kickoff/conflict and delivery
admission. This repair does not fabricate primary descriptors or infer programmes
from Willow/Fox. The dated 19 October stream-list timeouts are not presented as
the current cause.

Actual audible output, lock/unlock continuity and physical VoiceOver/Switch
Control acceptance remain open. Device Hub does not relay audio. Injected policy
and layout tests establish the accessibility rules, not a real screen-reader pass.
No global uptime, new latency/FPS claim or TestFlight readiness is inferred.
