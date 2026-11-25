# Fotty 2.0.0 (99) — internal CS playback batch

2026-09-14. Status: **Tests/archive pass; Apple rejected upload — current Xcode RC required**.
Superseded by the successful official-Xcode internal release 100; build 99 itself
was never distributed. Preserve the failed-gate evidence below as history.
Owner authorized the final release gate and existing internal TestFlight group.
No direct-device install, new testers, role changes, public distribution,
backend deployment or active-repository publication belongs to this gate.

## Candidate

Version-only successor to the owner-tested private build 98. App and extension
remain 2.0.0 and advance together to 99. CS stays opt-in; existing source settings
are retained. Includes exact-match CS alternatives in the ordinary source picker,
shared native/web delivery routing, bounded retry, cancelled-attempt protection,
responsive player/PiP callbacks and private source attribution. The accumulated
post-93 local diagnostics/feedback and reminder corrections are included, not a
claim that the backend or previously stable FPL features changed in this gate.

Build 98's owner acceptance covers CS2 playback, pause/resume, Sources reopening,
return to StreamEx and PiP on Jet iPad. It is not exact TestFlight acceptance or
qualification of every CS option. See release 98 and the 13 September CS audit.

## Preflight

Fresh App Store Connect check shows build 93 as the newest shared build, Internal
and Testing, in Fotty Internal Smoke (11 invitations, 10 installations shown).
Preserve that group and build 93 as fallback. These figures are current display
evidence, not proof of individual tester sessions or crash-free use.

Use installed public Xcode 26.6 (17F113) for qualification and archive. The active
default Xcode 27 beta is not the chosen distribution toolchain. Start with 70 GiB
free; run sequentially without simulators, retain one bounded release directory,
and remove owned build products after upload or failure. Capture exact pre-build
source and compare it again before upload. Qualification results, receipt hashes,
archive identity and Apple distribution status will be recorded after that check.

The first source capture was refused because the generic credential scanner
mistook a synthetic CS attribution digest in a unit fixture for an API key.
Replace only that fixture/expected value with an obvious all-zero synthetic
digest; preserve its shape and test assertions. No scanner exemption or runtime
credential change is involved. Recapture and run the full gate after this edit.

## What to Test — draft

Optional CS sources add more broadcast choices alongside your existing sources.
Enable them in Settings > Broadcast Sources > CS sources. Open a live match,
open Sources and try a CS option when available. CS availability varies by match.

Please check:
- Picture and audio start, and pause/resume remain responsive.
- Sources opens and switches between CS and an existing broadcast without freezing.
- Picture in Picture continues when you open another app; also try lock/unlock.
- Try another CS option, closing/reopening playback, and switching while loading.
- Check on iPhone and iPad. Report the build, sport/match, CS label and what failed;
  do not include private stream URLs or credentials.

Existing interests and source settings should remain unchanged after updating.

## Remaining acceptance

Exact TestFlight installation, retained data and playback on both form factors,
another CS variant, native/web coverage, loading-time changes and a timed live
background/recovery soak remain open until exercised. This release does not
automatically begin or complete the separate seven-day private qualification.

## Qualification and toolchain outcome

- Catalog drift, five identity vectors and live metadata across three provider
  feeds passed. All 236 existing Git-visible web/Worker files match the post-93
  source receipt; no backend deployment is included. A fresh `/health` reports
  `ok: true`, source `2026-09-06.fixture-freshness-1`, matching local source.
- Public Xcode 26.6 passed 581 unit tests, zero failures, two opt-in skips. Its
  generic iOS destination then failed with iOS 26.5 platform unavailable, despite
  installed SDK files. The public GUI is incompatible with this beta macOS.
  No simulator/runtime download, private platform override or toolchain edit was
  attempted. A direct-target archive probe was rejected because archivePath
  requires a scheme; it produced no archive.
- Xcode 27 beta 5 (27A5237l), used for private 98, supports generic iOS locally.
  Apple's dated 11 August notes had admitted this version for TestFlight. Its
  initial test run stopped at a macOS Documents-folder permission prompt while
  a test read source; the process was sampled, cancelled and cleaned up. No
  broader file permission was granted and no test was skipped to conceal this.
- Restore the captured source into the bounded temporary release directory.
  All 657 files/hashes/modes match the receipt. Full Xcode 27 tests there pass
  **581, zero failed, two intentional opt-in skips**. Generic unsigned iOS
  Release and signed optimized archive both pass. The previously recorded
  synchronous audio-session runtime warning remains; no app-wide audio refactor
  was made. No simulator, old installed Mac app or paid Coach request was used.
- App/extension: correct identifiers, 2.0.0 (99), arm64, minimum iOS 26.4,
  iphoneos27.0 SDK and 27A5237l. Strict nested signatures and matching dSYMs pass.
  AppIcon/Assets.car and all three bundled manifests are present; manifests match
  source byte-for-byte, audio background mode remains set, provider keys are empty.
- Both the restored source and original working tree matched the immutable
  receipt immediately before export/upload. Internal-only export, unchanged
  build number and symbol upload options were used.
- Apple validation rejected export/upload with **Unsupported SDK or Xcode
  version**, requiring the latest release candidate. Its current upload decision
  outranks the earlier dated beta-acceptance note. `EXPORT FAILED`; no completed
  TestFlight release, group assignment, notes publication or invitations sent.
  Apple lists Xcode 27 RC (27A266a) as current. Updating the installed toolchain
  requires owner approval before a multi-gigabyte download; do not retry the old
  beta, falsify SDK metadata or weaken validation.

[Apple release notes](https://developer.apple.com/help/app-store-connect/release-notes/)
and [current releases](https://developer.apple.com/news/releases/).

## Approved toolchain update — download handoff

The owner approved updating Xcode without simulators and then repeating the
internal release gate. Apple's authenticated Applications download page now
lists final Xcode 27, released 14 September, build 27A266a (the same build as the
previous RC). The in-app browser blocks the installer download with
`ERR_BLOCKED_BY_CLIENT`; a credential-free CLI request returns HTTP 403. No
installer was saved and no update or new archive was performed. Do not extract
browser credentials or bypass the block. Ask the owner to download Xcode 27
from Apple's page in Safari, then verify the signed installer and installed
build before qualification. New license acceptance remains an owner decision.
Disk remains 68 GiB free. The pre-existing Xcode 27 beta 5 installer and both
installed Xcodes are untouched; build 93 remains the shared fallback.

The owner subsequently downloaded and extracted Xcode 27. Its version is
27A266a; strict deep code-signature verification passes and Gatekeeper accepts
it as Apple System. Move the extracted app (no duplicate copy) from Downloads
to `/Applications/Xcode.app`, preserving the older installed Xcodes. First
launch requests required system-wide components, not simulator runtimes. After
Install, setup waits on macOS SecurityAgent administrator authorization; the
protected prompt requires the owner. No password was read or entered. First
launch is incomplete (status 69), so no candidate-100 build was started and no
default developer-directory change was made. Generic iOS and Catalyst are
listed, but an old shared CoreSimulator-framework warning confirms setup is
unfinished. Do not bypass component setup or download simulator runtimes.
Keep the task's 1.9 GiB `Downloads/Xcode_27.xip` until setup succeeds, then clean
it up; the older beta-5 installer is unrelated and remains untouched. Disk is
63 GiB free. Fresh Apple UI still shows 93 Internal / Testing, 11 invitations,
10 installations, with build 81 available.

## Source receipt and cleanup

Retain `backups/release-source/2.0.0-99/` (17 MB) intentionally as recovery/provenance,
not as a reusable signed artifact. It contains 657 files in one history-free commit:

- Source commit: `1dbfcfebf3060db6b6a09d636f9b6b4baac66941`.
- Source SHA-256: `21aa28b8851f096809e41d202f68b6c513475a02b1075695eca02f5a65b9f8fd`.
- Bundle SHA-256: `b09b1bd1d5eefc6c5b28fa9f7983b5faf091cdb3d0ea07572315148de51b9524`.
- Archived app executable: `620d8bf3dfa7635474a2c89c1526909973fefeb3b2282e6eb7a39575f3824b65`.
- Archived extension executable: `ca1a5379d1a5a305743e709d389178d2adf9883a767d670761db37a375dbaecf`.

The same bounded output directory was reused after failed attempts. Owned 571 MB
public-toolchain output, 520 MB interrupted-test output, final 1.1 GB release
output, two error result bundles and the separate distribution log were removed.
No app remains running from that directory. Disk reads 68 GiB free at completion
(70 GiB at initial preflight); unrelated caches/artifacts were not deleted to
force the measurements to match. No device was updated or data reset. The source
snapshot was not uploaded to GitHub. Later release-note edits mean a retry must
capture a fresh candidate rather than overwrite this immutable receipt.
