# Fotty Sports Hub 2.0.1 build 121 qualification and internal release

4 October 2026. Optimized Release 121 is installed on Jelani’s iPhone 15 Pro
Max, iOS 27.0.1. It carries build 120's performance repairs and corrects two
labeling defects found during phone testing. Build 121 is now Internal / Testing
for the existing 11-person Fotty Internal Smoke group; 111 and fallback 100 remain
available. The owner reports the phone runs perfectly and explicitly ends further
phone testing. The separately authorized archive/upload/group gates are complete.
This record
distinguishes phone evidence from the earlier [iPad 120 checks](Fotty-2.0.1-120.md).

## Confirmed repairs

The raw Aston Villa / Crystal Palace listing appeared neutrally on Home but was
promoted to LIVE and Following Premier League in Matchday. The earlier decoded
iPad broadcast showed women's football; bare club names were not evidence of a
men's Premier League fixture. Two separate assumptions caused the mismatch:
elapsed provider timing was accepted as live status, and roster inference was
accepted as league-follow proof.

- Matchday now groups provider-only current listings under Broadcast listed.
  Shared cards use the same status policy for verified LIVE or IN PLAY labels.
  Fresh accepted evidence can still establish live status; elapsed kickoff alone
  cannot. Saved selections and Watch eligibility are preserved.
- League follows reject roster inference alone. Explicit provider markers,
  structured fixtures and supplied official matches retain their existing roles.
  This does not replace the catalog's league-tab classifier.
- The no-score player header uses the same live distinction. The tested provider
  broadcast says Broadcast rather than claiming a confirmed live fixture.

Six new regressions cover the corrected assumptions and retained behavior; two
old tests that expected provider-only LIVE were corrected. The 120-to-121 native
and test receipt comparison contains exactly 11 changed paths: five production
files, four test files and two build-number configuration files. No playback
transport, source switching, FPL, persistence or qualification-support change.

## Automated and signed artifact checks

- 761 Catalyst tests pass, two intentional opt-in skips, zero failures (763
  total). Six existing Catalyst audio-activation warnings are not confirmed
  physical-phone defects.
- Seven version tests, native version coherence, generated catalog, five
  deterministic identity vectors and three reachable provider feeds pass.
- Generic unsigned iOS Release and signed optimized Release pass sequentially
  with official Xcode 27, jobs 1 and no simulator. Strict nested signatures,
  app/extension build 121 and three blank embedded provider keys pass.
- Default secret scan, frozen-source restore and pre/post-build comparison pass.
  The CoreDevice installation command timed out, but device app inventory,
  normal launch, native Settings 2.0.1 (121), and Instruments' installed app path
  independently establish completed installation. No redundant rebuild.

Pre-build receipt: `backups/release-source/2.0.1-121-owner-iphone`, 993 files.

- Recovery commit `9cc2d6226370239d2ca6f4e0d8a5d9961e894443`.
- Source SHA256 `35b75f80039f09f9488c76551cb98cc3750f39bf5a5b9ab56ba2ce1f563fb708`.
- Bundle SHA256 `e8f31bec320fca35e9be7024d456e8b0fca336b9589d54df0ba92f72ecb9ce81`.
- Signed executable SHA256 `562bc2e4bfff5720565cf657a0c7def7f7da9d2795289bd477db2bc5adf353ee`.
- Matched app/dSYM arm64 UUID `468E0C6B-D12B-3840-B984-B16EE8571F43`.

These receipts identify captured build input, not binary identity by themselves.
Signed artifact checks and installed native evidence are recorded separately.
Later documentation edits are outside that frozen build input.

## Actual phone navigation and preferences

Home, Matchday and Settings render and respond at the phone's regular text size
in Dark appearance. The false Villa/Palace LIVE and Premier League follow row
is absent from Matchday, while Home still offers its neutral broadcast Watch.
The old saved Czech Darts entry remains Awaiting confirmation, explicitly no
longer in the current schedule; it was not deleted to make the test pass.

Visible Settings retains Dark, one favorite, four Home interests, notifications
Allowed and kickoff clashes off. Typed preferences were compared on the prior
120 phone installation, not on 121; those disposable baseline copies were
cleaned. No exact 121 manager/SwiftData equality claim or private ID is recorded.

One GUI Instruments recording attaches the installed Release process 604:
10:37:37.135–10:38:44.847 AST, 67.711982 seconds. It exercises real Home and
Settings dragging plus Home / Matchday / Settings navigation. Hangs includes
microhangs over 250 ms and Time Profiler uses 100-microsecond sampling.

- Potential hangs over 250 ms: zero rows, agreeing with the GUI No Data result.
- App hitches: 22; total 229.218618 ms; maximum 20.838041 ms.
- SwiftUI Long Updates GUI summary: 146, total 250.14 ms, average 1.71 ms,
  maximum 11.34 ms, downstream maximum 4.46 ms.

This is a bounded navigation observation, not a cold-launch benchmark, zero-jank
claim or percentage improvement against a different iPad/catalog workload.

## Actual phone playback and remaining checks

On 121, Brighton WFC / Charlton Athletic WFC Watch immediately shows football
loading feedback. Broadcast 1 decodes, and selecting Broadcast 2 produces selected
feedback and decoded video, with its clock advancing from 80:58 to 81:10. Fotty
Pause holds at 81:25 across later observations. Fullscreen is reached; later
foreground video advances to 84:03. The phone's concurrent use of another app
confounds attributing that resumption to a particular tested control.

The owner confirms audible stream playback during this phone round; that reply
does not establish source-by-source or background audio. The owner then reports
the phone runs perfectly and instructs the agent to leave it alone. No further
phone interaction is performed. PiP/background playback, restoration and final
Close were not newly qualified in this round; owner acceptance is distinct from
agent-observed checks. Do not record other-app use as a Fotty crash/PiP failure.

An existing code-level caveat remains outside this repair: the player's early
score-header branch returns cached minute/status before the shared freshness and
terminal check. It can show stale in-play text when that score is unavailable or
old; no such physical failure was reproduced here. Keep it as a focused follow-up,
not proof that every header is now universally truthful.

## Release and resource boundaries

The native UI/performance guidance requires actual installed-device interaction
and bounded measurements. Normal-size phone screens are not large-text, narrow
device, every-provider, ordinary-use soak or full accessibility certification.
The iPad Watch Two evidence belongs to build 120, not an untested iPad 121.

No TestFlight archive/upload, Git publication, backend deployment, tester change,
paid-service change or FPL feature work occurred. Distribution remains a separate
authorized gate with pre-archive receipt and pre-upload source comparison.
Temporary build output was removed automatically after the install timeout.
The compact evidence above replaces the disposable trace/exports. After closing
the recording, 245 MiB of owned trace/export/launch output and the exact temporary
folder were removed; final disk check reports 34 GiB free. Immutable receipts and
unrelated user artifacts/caches remain. No phone action follows the owner's stop.

## Authorized internal upload attempt — 4 October

The owner subsequently authorizes the existing-group TestFlight upload. Fresh
Apple API evidence still lists 111 as the latest build; the only internal group
is Fotty Internal Smoke with 11 testers. No tester or build assignment changed.
Independent source comparison finds only four later documentation differences
from the qualified owner input; every native, test, configuration and
qualification-support input remains identical.

The verified pre-archive receipt is
`backups/release-source/2.0.1-121-testflight`, 994 files:

- Recovery commit `e6a6480255799d6925b27e9ef4836ba2bf7f00a9`.
- Source SHA256 `f1f5fb077c1b1f19c55f17e82e7ab44816a826d09817b4e0eca0b3f22054deae`.
- Bundle SHA256 `8255d02d9a84838d094cd3c2781ddebab295eedcade0c36cd91c6661aab173eb`.

Official Xcode 27 / jobs 1 archives Release successfully. App and extension
remain 2.0.1 (121), arm64/iOS 26.4; strict nested signatures, matching dSYMs,
icons, background audio, three source-matching provider manifests and empty
embedded provider keys pass. No test bundle is packaged. The source and restored
tree match the receipt immediately before each export attempt.

The second archive's app executable SHA256 is
`81bb66ed2c48f14b079c807d0127913b1934dd151dc690803ea906b409bc3621`;
extension SHA256 is
`214ed64844691a337fe5219a1c8ce45f05e4c0a886582c16a249d64a8d94f452`.
Matched app/dSYM UUID: `ABB55CC2-81EE-3B75-A3C0-EBC4644636CE`;
extension: `D45B4754-56E3-3DC1-92D5-3E88AA3AB9A7`.

**First attempt not uploaded.** The existing internal-only export first fails with Failed to
Use Accounts. An existing API-key retry fails because Xcode reports an empty
account role and no distribution signing certificate. Xcode's actual Apple
Accounts screen is signed out. Its sign-in window is opened for the owner;
do not reset credentials, create keys or broaden permissions to bypass this.
The existing API key still reads TestFlight, but that is not distribution-signing
authority. The owner restores the enrolled account; Xcode shows its Admin team.
The GUI is closed before retrying packaging. Opening Xcode had automatically
created a new iPadOS 27.0.1 debug-symbol cache at 11:10:30 AST, temporarily growing
to 13 GiB during copying; the completed 6.3 GiB cache is removed after Xcode exits.
The September iPadOS 27.0 cache and unrelated caches remain. No device app
interaction occurred. First-attempt packaging/logs are removed; receipts stay.
These later notes are not part of the frozen archive input. A fresh receipt and
archive are required for the signed-in retry.

## Signed-in distribution upload

Xcode reports Upload succeeded and EXPORT SUCCEEDED at 11:24:36 AST on
4 October 2026. It uses the existing internal-only export settings, automatic
distribution signing, symbol upload and unchanged build number. This is upload
acceptance, not yet processing/group-availability proof.

Apple's API at 11:27:26 AST confirms VALID, INTERNAL_ONLY, version 2.0.1/build121,
build ID `e8fffe58-a819-4f79-96b8-be9214b41679`, and a processed icon. Internal
state is MISSING_EXPORT_COMPLIANCE; the declaration is null. The API credential
rejects the declaration PATCH with 403; that request changed nothing, and the
notes/group requests were never reached. The App Store Connect browser session
is signed out. Its sign-in page remains open for the owner to finish this gate.

Do not blindly describe this build as HTTPS-only. Private backup uses Apple
CryptoKit AES-GCM, HMAC/SHA-256 and locally composed RFC8018 PBKDF2 iterations.
No third-party crypto dependency/proprietary primitive is found in checked
source/config; PBKDF2 itself is not an Apple-supplied API. Apple's
[encryption guidance](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
distinguishes OS-limited encryption from standard algorithms supplied outside
the OS. This review does not conclusively classify that composition or establish
an export-law exemption; retain the exact implementation facts for the owner's
questionnaire. No declaration or encryption-source change is made here.

Owned archive/DerivedData/distribution logs are removed. Final disk check:
approximately 33 GiB free. Both devices' apps remain untouched.

The fresh pre-archive receipt is
`backups/release-source/2.0.1-121-testflight-signed-in`, 994 files:

- Recovery commit `950a26336c0281a9bf404f054ea4802484ba94f0`.
- Source SHA256 `4148d9b3348c7affdaffe587fba6fb4acec30191ab3a18c430d2ccda1af36912`.
- Bundle SHA256 `3afa7be1054735d74a5182eaecbbfeaff72187d9178808c7a8e4f16941f991f3`.

The successful archive's app executable SHA256 is
`aa908d72816cbc9c15bf33dbe908d3a4a148b5e12950e007da5648106628b621`;
extension SHA256 is
`927a614b4d6240c89524a4aac58c3e59fe6423e4339a132ae87d1e7e2d0ca6dc`.
Matched archive/dSYM UUIDs remain `ABB55CC2-81EE-3B75-A3C0-EBC4644636CE`
and `D45B4754-56E3-3DC1-92D5-3E88AA3AB9A7`. These fingerprints identify the
local signed archive, not a downloaded Apple-processed executable. Root's
immediate source/restore compare and the independent native-input comparison
pass. No feature-source change, simulator or device-app interaction occurred.

## What to test

Build 121 focuses on responsiveness and clearer fixture/broadcast information.

Please check:
• Home and Matchday: scrolling, switching tabs and opening Watch should respond promptly without long freezes.
• Your interests: selected live and upcoming fixtures, team names, kickoff times and status labels should make sense.
• Playback: switch sources, pause/resume, check audio and try Picture in Picture where available while using another app.
• Watch Two on iPad: change each pane’s source independently, use pause/play, switch audio focus, change layout and close.
• Reopen the app and confirm your saved preferences and selections remain.

For feedback, include build 121, device, sport/match, visible source label and what happened. Do not include private stream URLs or credentials.

## Signed-in App Store Connect finalization

The owner signs into the browser. Build121's English (U.K.) notes above are
saved; the UI confirms Saved. Groups remains zero. Add Group opens the missing
compliance questionnaire instead of assigning a group.

The questionnaire's standard-algorithm path is inspected because backup uses
app-composed PBKDF2 over CryptoKit primitives. It asks whether the app will be
distributed in France. No country answer is assumed and no declaration is saved;
the owner is asked for that distribution fact. The pending form remains visible.
This is an unresolved release gate, not a confirmed crypto-code defect or an
export-law classification. No tester/role change, device app action or build.

## Completed internal release — 4 October

On the next live UI check, the pending compliance modal is closed and Add Group
opens the normal group-selection dialog. The agent does not submit an encryption
declaration in this finalization turn; the mechanism that cleared the earlier
gate is not established. The owner confirms all current testers are outside
France. No France distribution setting is enabled or changed.

Only the existing Fotty Internal Smoke group is selected and added. Build details
show Group (1), Internal, 11 testers and Saved testing notes. The iOS build list
then explicitly shows 121 Internal / Testing with that group and 11 invitations.
Apple's read-only API at 13:56:52 AST (17:56:52 UTC) independently confirms:

- Build `e8fffe58-a819-4f79-96b8-be9214b41679`, 2.0.1 (121).
- Processing VALID, audience INTERNAL_ONLY, internal state IN_BETA_TESTING.
- `usesNonExemptEncryption: false`; external state NOT_APPLICABLE.
- Existing automatic notification setting remains true; it is not changed.

This is current tester-group availability, not proof of email delivery,
installation, acceptance of the Apple-processed binary, or a legal classification
of the app-composed PBKDF2 routine. Public Apple guidance does not explicitly
resolve that composition boundary; do not call it an OS-supplied PBKDF2 API or
repeat the France question after the owner has supplied the fact. No support
request, source/crypto edit, new archive, device interaction, tester/role change,
Git publication, public release or backend deployment occurs in this gate.
The small release-status screenshot is retained as handoff proof; packaging
output remains cleaned.
