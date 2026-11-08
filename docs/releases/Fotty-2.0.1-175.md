# Fotty 2.0.1 build175 — private source-testing update

24 October2026. Owner requested deployment to Jet iPad for personal testing.
Signed normal Release175 is installed, read back and launched on Jet iPad Air4,
iPadOS27.0.1. No phone, FPL, multi-stream, backend, Git publication, tester or
TestFlight change. This is installation evidence, not live-source qualification.

## Included changes

- StreamViX's source-local original-GMT/Rome timing reconciliation, with full
  date/weekday/DST, teams/competition, advertised ID and catalog/meta conflict
  checks. SV1–SV6 uses the existing match-source path and guarded native relay.
  Its separately bundled **SV sources** switch remains OFF by default.
- AS cricket's separate advertised catalog/cache and exact UTC/known-format/
  ordinal/squad/day matching. Reviewed T20I and Test Day1 only; later Test days,
  ODI/T10/unknown formats and upcoming placeholders do not establish coverage.
  Cricket uses the existing AS switch, not a second activation toggle.
- Existing player layout, native controls, ranking, FPL and multi-stream logic
  remain unchanged. Implementation/remaining gates are in the dated source audit.

## Verification

The preceding freshly compiled focused Catalyst suite passed297 tests, zero
failures and three intentional physical-only skips. This private gate adds a
signed optimized iOS Release build, strict/deep signature verification, source
membership and app/extension version coherence. No simulator or concurrent heavy
build was used; no repeated unit/UI/playback campaign was run just to install.

CoreDevice confirms the normal `com.jelani.Fotty` app is2.0.1(175), launches and
has one surviving normal process on a subsequent read. No UI-test runner was
installed. Device Hub's preview timed out; it was stopped. No visual Home,
source-picker, new-source decoded playback, programme,90-second hold, controls,
audio or PiP pass is claimed from this install.

All52 protected FPL/multi-stream/player hashes match the prior source baseline.
Fresh before/after binary-plist comparison confirms all four private FPL values
and six existing source switches are unchanged. SV and FS remain OFF. No private
values, signed media URLs or device identifiers are retained in this receipt.
Owner testing can enable **Settings → Broadcast Sources → SV sources**; AS
cricket follows the existing AS choice and appears only for corroborated matches.

## Build provenance and cleanup

Pre-build capture24October21:28:30UTC:1,150 inputs, history-free temporary commit
`8cca1cd8f272ade20acd13cc9693e4f5800635f3`; source SHA256
`b7155df39fdbe91d2692dbd3b07d292d12a794a44269ddc0d10ef62672d6f045`;
bundle SHA256
`dec027ea7974795a0906c0754f5735e505afaf8a578b2ca80c5066b1ac522d5b`.
Frozen-source compare passed before installation and closeout documentation.
Signed normal executable SHA256:
`f650b1e58a76984731f3aa2b7fa16c0454f43e6d51d22360e8f5d3d72c3b7f03`.

The initial preparation shell could not find Homebrew's scanner; it stopped
before building and removed its424KiB gate. The corrected tool path passed the
normal source scan. A JSON-conversion check found NSData in the preferences;
preservation was therefore checked with native binary-plist decoding, not by
discarding those values. After successful install/manual readback, the waiting
supervisor was deliberately interrupted to run its cleanup trap. The385MiB gate,
source bundle, copied private preferences and keep-awake helper are gone; absence
and15GiB free space were verified. Unrelated artifacts/caches were preserved.

Live AS cricket, SV, FS and pending PL/UCL/cricket acceptance remains open under
the bounded scheduled follow-ups. Installation alone does not close those gates.

## Subsequent owner iPhone installation — 24 October

The owner separately requests the same175 update on Jelani's iPhone, intending
to use it for the next day and report findings. This extends the installation
target only; no new feature work, TestFlight, cloud/Git publication or tester
change. The earlier Jet-only scope above is the initial gate, not this later one.

- Fresh CoreDevice inventory first omits the intended phone, then discovers
  **Jelani's iPhone / iPhone15ProMax / iOS27.0.1**. Normal developer pairing succeeds
  without resetting services, unpairing devices or changing OS settings. Use
  fresh live identity rather than the different archived April device identifier.
  Existing installed-app readback is125; no other listed phone is substituted.
- Rebuild current175 runtime source as signed optimized Release, sequentially
  with official Xcode. App and extension profiles are current, match the intended
  phone/team, and pass strict/deep signatures. Source membership/version checks
  and frozen-source comparison pass. No simulator or UI-test runner.
- In-place install/readback proves2.0.1(175); normal argument-free launch succeeds
  and a later process inventory finds one normal Fotty process. The phone had
  auto-locked during compilation, but installation and subsequent launch complete;
  the unlock follow-up is no longer needed. No remote screen or playback test.
- After launch, all **nine** existing private FPL preference values and all
  **three** existing source switches match the phone's own pre-install snapshot.
 52 protected FPL/multi-stream/player source hashes remain unchanged. AS/SV/FS
  remain OFF; existing CS stays ON. No Jet preferences are copied to the phone.
  The owner can opt into AS/SV under Settings → Broadcast Sources when testing.
  These checks do not qualify any live feed, controls, layout, PiP or uptime.

Pre-build capture24October21:39:19UTC:1,151 inputs, temporary history-free commit
`c2ef9b113b160153b5b5cc77ac57a289d5221b72`; source SHA256
`4ea584f991d7eba9ac305bbf46945933ef36b52e7e8851daa54825abeed1355d`;
bundle SHA256
`711ff0e62c326a7b9e5e60283c3e3823d3d2eed3211a462b43c53211015fda08`.
Signed phone executable SHA256:
`0a430bbd178e146de841dbc38a1a30916dc9d7fe035d67fa3287858c4f1c5e69`.

The waiting supervisor is deliberately interrupted after separate successful
install/readback checks to run its cleanup trap. Its371MiB output, copied private
preferences, temporary source bundle and keep-awake helper are removed; the
separate small post-launch verification directory is also cleaned. No build or
awake process remains. Final disk readback is11GiB free; macOS reports about9GiB
used encrypted swap. Swap's contribution to the free-space change is not measured;
no system VM files, unrelated caches or other user artifacts are removed.
Leave the phone to the owner's next-day testing. Jet-only scheduled qualification
does not expand to phone testing because of this installation request.
