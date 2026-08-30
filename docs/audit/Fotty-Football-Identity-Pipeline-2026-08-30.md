# Fotty football identity pipeline — 2026-08-30

## Outcome

The Chelsea–Brighton listing was not a one-off league-filter bug. StreamEx used
`Brighton and Hove Albion`, while the reviewed catalog used
`Brighton & Hove Albion`. Fotty had multiple independent team normalizers, the
Home league filter trusted only provider text plus exact seasonal membership,
and the release gate never replayed current provider metadata. The event
therefore fell through to Other even though its stream metadata and the
official schedule described a Premier League fixture.

The correction is a local, unreleased source change on top of 2.0.0 (46). It is
not a TestFlight upload, device installation, web/Worker deployment or public
monitoring service.

## Implemented boundary

- `shared/reference-data/football-competitions-2026-27.json` remains the single
  reviewed seasonal source. It now includes exact provider aliases for Brighton
  and Deportivo, plus separate historical identities for West Ham and Wolves so
  fixture matching does not pretend they are current league members.
- `tools/generate-football-competition-catalog.mjs` generates the same canonical
  senior-club resolver and deterministic unknown-team key for Swift and
  TypeScript. `FootballDataPolicy` and web team matching consume it instead of
  maintaining private alias dictionaries.
- Recognized stream events resolve by canonical home/away identity before the
  legacy word matcher. Youth, reserve and women's teams remain excluded from
  senior-club resolution.
- Home league filters reconcile a catalog event with the already-loaded
  official schedule using both canonical teams and a six-hour kickoff bound.
  When proven, the official competition ID/code/name is authoritative. Provider
  markers and two-current-club inference remain deterministic fallbacks.
- A rejected provider competition marker now creates a bounded, redacted
  on-device `match_identity` quality event. It stores only a reason code and
  source class—never club names, fixture IDs, URLs or credentials.
- `shared/reference-data/provider-football-identity-vectors.json` contains the
  exact non-URL Chelsea–Brighton metadata shape plus spelling, stale-membership,
  cup and Champions League regressions. Both iOS and the web release checks use
  this corpus.
- `tools/audit-provider-football-identity.mjs --live` inspects only current
  provider metadata from the three catalog mirrors. It fails for reachable
  domestic-league markers with unresolved team identity and fails closed when
  no feed is reachable. It never requests video or prints stream URLs.
- `tools/ios-device-qa.sh` now runs generated-catalog freshness, deterministic
  vectors and the live metadata drift audit before native qualification. Its
  Catalyst test phase uses build-for-testing followed by test-without-building,
  avoiding an observed Xcode 27 beta worker-materialization hang without using a
  simulator or changing test coverage.

The first live audit caught two additional provider cases. `Deportivo de A
Coruña` was added as a valid RC Deportivo alias. `Multiview: Bundesliga 2` is
now recognized as a lower-division/non-domestic marker rather than an unresolved
top-flight fixture. The next live run passed all three reachable feeds.

## Verification

- Generated catalog freshness check: passed.
- Shared provider identity vectors: 5/5 passed.
- Live metadata drift audit: passed across 3 reachable feeds.
- Web/Worker unit suite: 87/87 passed.
- TypeScript `tsc --noEmit`: passed.
- Focused Catalyst identity compilation and complete `PlaybackPolicyTests`:
  passed. One earlier direct `xcodebuild test` launch was interrupted after the
  Xcode 27 test host waited for workers; its temporary output was removed, and
  the split build/run form passed.
- Complete Catalyst policy suite through `tools/ios-device-qa.sh`: passed.
- Single generic-iOS Release compile through the same gate: passed.
- `git diff --check`: passed.
- No simulator, physical device, UI-test helper, paid API call, video probe,
  TestFlight/App Store mutation, server deployment or source publication.
- The one bounded Xcode directory was removed on exit. Disk remained about
  52 GiB free before and after final qualification.

## Remaining acceptance

The code now prevents the known class of silent alias drift at development and
release time, but it cannot make third-party metadata permanently correct.
Before the next shared upload, rerun the live identity audit and install the
result through the selected versioned channel. On a physical device, verify the
same active fixture appears under All Football and its official league tab.
Official reconciliation also depends on the broad schedule being available; if
it is not, the generated resolver and provider drift gate remain the fallback.
Continuous hosted monitoring is not deployed by this work.
