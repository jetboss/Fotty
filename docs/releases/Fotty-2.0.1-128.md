# Fotty 2.0.1 (128) private iPad status and badge repairs

Date: 2026-10-10. Jet iPad receives the finished-match and shared badge repairs.
The final binary replaces the earlier private 128 iteration. Shared TestFlight121,
owner phones125, production Worker and paid-service/privacy policy are unchanged.
The performance and playback repairs from private127 remain included.

## Finished match status

The deployed schedule already supplied explicit FINISHED facts for Sunderland
versus Brighton (560592) and Chelsea versus Bournemouth (560595). The bounded
10 October check accepted publisher updates around16:01–16:03 UTC, with the
registry receipt at16:04:49.500 UTC. This incident required native reconciliation,
not a Worker deployment or a fabricated full-time result.

- The official PL score adapter now retains recent explicit finished/provisional
  finished fixtures instead of discarding them from its live response.
- Repository snapshots separate accepted source observations from attempted
  refreshes. A cached read, cooldown or failed poll cannot renew live authority.
  Schedule identity remains authoritative; live facts never rewrite the raw
  schedule cache. Empty success revokes active evidence without inventing final.
- The score service publishes with the completion clock and per-fixture receipts.
  Accepted terminal facts survive late active or empty responses within bounded
  dated retention. Failure, expired or future active facts cannot supply LIVE,
  a score or a minute. Details uses the same accepted facts and preserves prior
  enrichment rather than returning an older live hub.
- Home retains verified terminal identities separately from playable rows and
  vetoes exact dated/squad/competition matches before deduplication. Matchday,
  reminders and Watch use the shared terminal policy. Held evidence, unrelated
  competitions, rematches and similarly named squads cannot supply that veto.
- Temporary unknown/empty feeds preserve dated notification history without
  resetting goals or kickoff status. Explicit final still advances the baseline.

## Badge selection

The provider's Manchester United crest at `crests.football-data.org/66.png` was
visually correct. The shared image loader nevertheless searched every fallback
for a warm bitmap and returned before requesting a higher-priority uncached crest.
Its loaded view state also lacked a candidate identity. Those defects permit a
cached fallback to persist or another row's old artwork to appear after reuse.
Prior candidate-order/resource tests did not cover actual warm-cache selection.

The loader now attempts candidates in order, uses only the primary cache entry
immediately, falls back after genuine failure, deduplicates requests and rejects
cancelled loads. Loaded state belongs to the complete current URL list, including
its order. Existing bounded networking and two decoder permits remain unchanged.
This repair applies to all shared image consumers, not a Manchester-only override.

Official PL rows also carry bootstrap stable-code crests. Repository enrichment
preserves schedule names/IDs while retaining matching trusted artwork through
live-to-final transitions. Home gives that route priority only for the same dated,
unconflicted senior PL identity; explicit other competition or squad evidence
cannot borrow it. Tests distinguish stable badge codes from seasonal team IDs.

## Verification

- Current-source Catalyst logic gate:992 total,990 passed,two existing optional
  skips,zero failures. New coverage includes terminal/receipt/detail/notification
  transitions, terminal Home reconciliation, warm fallback priority, reused image
  state, cancellation and guarded official artwork. Catalyst is logic evidence,
  not acceptance of the old Mac app's UI.
- Generated competition catalog, five provider identity vectors, three offline
  football proxy tests, native version coherence and `git diff --check` pass.
- Signed physical iOS Release and strict signature verification pass. App and
  extension are2.0.1(128). Jet iPad in-place install sequence2132 succeeds, and
  independent installed-app readback confirms2.0.1(128).
- Final executable SHA-256:
  `81b1c82e3eb27c8e5f728a22a1623da84995f6180184983a73ba8c9b0bffba55`.
- Physical production-feed Home/Matchday/Search and reported-terminal journeys:
  two passed,zero skips/failures. The known terminal pairs cannot remain in the
  inspected current Home rows; their registry/legacy Matchday routes are checked
  for LIVE. Absence after accepted reconciliation is valid. Deterministic tests,
  rather than a simulated live whistle, exercise the actual state transition.
- The initial physical runner exceeded its allowance while repeatedly querying
  propagated Matchday descendant identifiers. The repaired harness checks bounded
  fixture routes instead. The final run disables optional verbose diagnostics;
  it does not bypass permissions or change app monitoring.
- Actual wide-landscape Jet iPad inspection shows correct Man United/Tottenham
  crests after scores load, plus Hull, Everton, Palace, Forest, Liverpool and City
  in Matchday. Home also shows recognizable Barcelona/Getafe, Inter/Parma,
  Madrid/Villarreal, Raptors/Clippers and Devils/Canucks artwork. A separate
  source-free Parma schedule row retains an honest monogram; this is not a claim
  that every publisher badge or all duplicate fixture aliases are qualified.

No source configuration or app-data reset occurred. This gate does not newly
qualify native PiP, sound, alternate sources, two decoded panes or whole-app FPS;
retain private127's measured limits. No frozen shared-release receipt or
TestFlight qualification is claimed.

An ordinary argument-free launch remained running as process9217. A subsequent
live mirror check still shows the correct Man United/Tottenham pair with scores
loaded, rather than treating the initial launch alone as badge acceptance.

## Cleanup

The owned temporary test runner, physical scheme and sole1.9GiB output directory
were removed after evidence review. Independent app-list and filesystem checks
confirm the runner, gate and scheme are absent; Fotty2.0.1(128) remains installed.
Free disk space is31GiB. Temporary DerivedData, signed copies, result bundles and
captures are rebuildable; no unrelated owner data or caches were removed.
