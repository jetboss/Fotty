# Fotty Sports Hub 2.0.1 build 113 native candidate

Prepared 1 October 2026 for local source qualification. No signed archive,
device installation, TestFlight distribution, development-repository commit,
push or backend deployment
is authorized by this gate. The local build number is 113; availability of that
number must be rechecked in Apple before any upload.

## Candidate scope

The immutable assembly starts from the verified owner112 source receipt and
overlays exactly ten native/config/test paths. All 215 native inputs and thirteen
additional qualification-tool/data inputs match the current primary source in
bytes and executable modes. No native paths were added or removed. All remaining
assembly files retain their owner112 baseline; unrelated dirty primary work is
not folded into the candidate.

- App and extension versions move together to 2.0.1 (113), minimum iOS 26.4 unchanged.
- Broad cricket/sports consumers, accepted UI, playback, FPL and personal recovery
  remain from owner112. No new player or design implementation is introduced.
- Legacy football treats valid empty windows as success, avoids unconfigured
  premium fanout, and preserves upstream, decode and cancellation failures.
- Independently accepted cricket and CPL corrections advance even when a
  provider replays an older catalog receipt. Stale streams cannot be lent to
  those corrected fixtures; unrelated sports retain their own rows and sources.
- Football-Data.org attribution remains in Privacy.

The eight production/test overlays are `FootballDataPolicy.swift`,
`FootballRepository.swift`, `FootballService.swift`, `MatchListViewModel.swift`,
`SettingsPrivacyView.swift`, `BetaUsabilityTests.swift`,
`CricketFixtureCatalogTests.swift` and `SportsCatalogRefreshTests.swift`.
The other two paths are `project.yml` and `Fotty.xcodeproj/project.pbxproj`.
The gate additionally changes `tools/ios-ci.sh` and adds
`tools/verify-native-version.rb` with its offline regression test. No backend
source is overlaid.

## Immutable source receipt

- Baseline: `backups/release-source/2.0.1-112-owner-ipad/`, verified restore,
  commit `93619270c255281529622addec7e8faaf330a1d5`.
- Candidate: `backups/release-source/2.0.1-113-candidate/`, captured before the
  final automated build; 964 files, one history-free commit, full default secret scan
  and verified round-trip restore.
- Candidate commit: `70e32ca0cecafcfad6aa8482767fce882dbbfb92`.
- Source SHA256: `d94562b4df02b756e3797fc341524a92c64a33924eea1d8963ffab1690e4d87c`.
- Bundle SHA256: `206704b790f884157a9186f029280855f7d09c04f1213d892852ca69cacaa296`.

This is local recovery and pre-build provenance, not an off-Mac backup or proof
of a previously distributed binary. Restore the receipt into a new isolated
checkout for future packaging; the primary checkout as a whole does not match
this deliberately isolated source set. Preserve the receipt and perform the
required comparison immediately before any future upload.

## Deployed companion backend

Fresh read-only checks at 20:57 UTC report source
`2026-10-01.cricket-corrections-1`; cricket has 67 rows/three lanes and sports
70 rows/31 manifest scopes, both verified with 20:40:53 UTC receipts. All three
reviewed ICC kickoff corrections remain present.

The independently deployed companion is [PR36](https://github.com/jetboss/Fotty/pull/36),
protected commit `0416690f66019657dea4c299d51546b5b3b3c7a6`, Worker version
`87b347ed-0b0c-4df1-b0ec-9c755f06fc5d`. Its qualified deployment is recorded
[separately](https://github.com/jetboss/Fotty/pull/36#issuecomment-5939284827).
The native assembly's retained web/Worker source and dependency lock are older
owner112 files, **not** a deployable substitute for that protected backend tree.
No new feeds, flags, paid calls, secrets or service configuration changed here.

## Qualification and remaining gates

The official Xcode 27 (27A266a) simulator-free gate passes against the final frozen
assembly: 657 Catalyst tests passed, two opt-in skips, zero failures; unsigned
generic iOS Release passed. The full receipt comparison passes after the build.
Five offline provider identity vectors and source catalog generation pass;
recovery-tool regressions pass 13 tests and native version checks pass seven.
Independent review found no blocker in the focused CPL replay repair or parsed
version preflight. CPL tests cover forward/backward kickoff changes and reject
older or unverified schedule snapshots.

The tests use freshly compiled Catalyst source, not an older installed Mac app.
Four pre-existing Mac audio-session activation runtime warnings are recorded in
the test result; no new playback implementation was changed to suppress them.
This is not measured iPhone/iPad responsiveness or background-playback proof.

An initial mechanical overlay failed byte-parity checking before any build.
The ten paths were replaced with their exact reviewed contents. Independent
review subsequently caught a malformed YAML indentation introduced in version
allocation: the generated Xcode project could still build while its source
configuration could not parse. This was corrected, a parsed version preflight
and seven regressions were added, and parity was verified over all 228 inputs.
The final receipt above was captured before rerunning the complete native gate.
Both rejected temporary receipts are not this candidate and are removed with
owned temporary output.

Owned DerivedData, result bundles, build logs, assembly and rejected receipts
are removed. Only the intentional 19 MiB candidate source bundle/receipt remains;
approximately 44 GiB is free. Pre-existing caches and other tasks' artifacts are
preserved. No signed application or archive is retained.

No physical acceptance or release is implied. Follow the
[build113 qualification ledger](../beta/BUILD-113-QUALIFICATION.md) for exact
iPhone/iPad installation, retained data, real playback/PiP and Watch Two,
actual reminders, Files recovery, accessibility and independently received
feedback. The seven-day round has not started. Shared TestFlight111 and owner
iPad112 remain unchanged; neither qualifies these later repairs.
