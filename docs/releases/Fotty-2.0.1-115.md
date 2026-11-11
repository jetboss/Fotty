# Fotty Sports Hub 2.0.1 build115 — owner iPad repair checks

3 October2026. Installed only on Jet iPad Air4/iPadOS27.0.1. Shared TestFlight111
is unchanged. The owner explicitly approved continuing known repairs and the
existing device-testing gate without repeated permission requests; this is not
authority for shared distribution or unrelated changes.

## Included repairs

Extends owner114 with measured/scaled Pause and Sources controls, neutral
provider-listed availability rather than unverified LIVE, attempt-keyed single
and two-match WebViews, stale navigation/message/PiP fences, cancellable native
startup deadlines and media teardown. Source-admission and cookie-domain
boundaries, source eligibility, fixture identity and explicit Pause ownership
remain unchanged.
FPL feature work stays paused. Apple UI guidance informed layout and the actual
native visual checks; automated tests do not imply full visual acceptance.

## Identity and qualification

- Coherent source/app/extension2.0.1(115); seven offline version tests pass.
- Functional source before this metadata-only bump passes727 Catalyst tests,
  two intentional opt-in skips, zero failures and unsigned generic iOS Release.
  Eighteen new regressions cover the follow-up repairs. Six Catalyst audio
  warnings are not a demonstrated device defect.
- Official Xcode27, sequential jobs1, signed optimized generic iOS Release,
  empty embedded provider keys and strict nested codesign verification pass.
- Pre-build receipt: `backups/release-source/2.0.1-115-owner-ipad`,987 files.
  Recovery commit `11c4e158463fad38c061e65a027aebc37c1eb226`.
  Source SHA256 `85d899ea6b32db2af3d840703282faef041a6d09ee925931b0e05fb2a9a3e661`.
  Recovery bundle SHA256 `42c3c1ddfc0c5168f0813bc24e1632ef8b49c7116d06138316b5f294c7b0b3f6`.
  Default secret scan/round-trip restore and pre-install current-source compare
  pass. Later workflow/release documentation is not part of this frozen receipt.
- Signed build executable SHA256, from the app installed on the device:
  `6af383ed6b28208f7d977d79294e0d5c63c05c8ed9cc3731a8bcd0b844c50ad5`.
  This identifies the executable, not the entire signed app or recovery bundle.
- Exact-device in-place install, launch and CoreDevice installed115 verification
  pass. No uninstall, app-data reset, simulator or UI-test runner.

## Device evidence and open checks

The reconnected Jet iPad was independently verified as wired, unlocked and
running the installed 2.0.1(115). Home in landscape/Light shows "Broadcast
listed" on provider-only baseball spotlights and "More events", without an
app LIVE badge on those spotlights. Watch shows sport-specific resolution
feedback. This is visual acknowledgement, not measured tap latency.

On the Tampa Bay–New York provider listing, Broadcast 5 was visibly selected
and decoded advancing provider ads. Fotty Pause changed to Play and held the
same decoded frame for a ten-second sample. Opening and dismissing Sources
while paused did not resume playback. Play initially buffered/returned a
paused acknowledgement, then resumed advancing provider video and restored
Pause. Landscape Pause/Sources labels fit on one line and those actions
registered. This qualifies the sampled transport controls, not named-match
availability, audible playback or every provider.

Automatic fallback subsequently showed unrelated channel content and a
"Coverage will begin shortly" card. Retrying Broadcast 5 dismissed the picker;
reopening it confirmed the correct selected row. Reliable decoded recovery
after that retry was not established, so controlled sourceA/B/A recovery stays
open. Provider ads/channel cards are not proof that the selected game is airing.

Earlier screen sharing repeatedly failed with AVC RTCP timeout/CoreDevice 9015;
narrow host logs corroborated that transport failure. Normal Quit/reopen of
only Device Hub temporarily restored interaction. A later black capture also
hid iPad Home; refreshing only the screen share restored Home, with no new
9015 entry in the sampled three-minute logs. Reopening Fotty revealed a black
web-player surface with hidden chrome, not a demonstrated app freeze. Revealing
controls and tapping Close within their auto-hide window returned visibly to
Fotty Home without restarting the app. No visible orphan video/PiP was present
in the subsequent Home capture. Audio-stop, active-PiP dismissal and sustained
hidden-media/resource shutdown remain unverified. Do not turn screenshot
absence or process survival into complete teardown proof.

No app repair was inferred from transient captures. Owner114's control evidence
does not qualify115; actual115 PiP/background, live-match and two-live-match
Watch Two checks still need qualifying sources and stable observation.

After exiting playback, Matchday and Settings each reached their native
destination; Settings visibly identifies v2.0.1(115) and uses the landscape
two-column layout. The empty personalized Matchday is not evidence of a fixture
omission. Tab transition captures are not measured responsiveness/scroll proof.

The preference baseline copy completed before installation, but whole-plist
JSON conversion failed on typed plist objects during comparison. The owned
copies were cleaned, so exact before/after equality cannot be reconstructed or
claimed. A subsequent typed plist inspection confirms the positive local
manager and season-confirmation record, interest-filter preference and reminders
payload are present without printing values. Saved-matches payload is absent;
there is no established pre-install payload to diagnose loss. Follow records in
SwiftData were not compared. Do not turn post-install presence into a blanket
data-preservation guarantee.

Actual live-match decoding, audio continuity, two-live-match Watch Two, iPhone
acceptance, large-text/narrow-window interaction and measured scroll performance
remain open. No new performance or provider-uptime claim.

## Cleanup and boundaries

Local packaging-path/tool-search errors were corrected without weakening gates;
failed/interrupted build products and preference copies were automatically
cleaned before another attempt. All owned temporary build/DerivedData/log output
and the later preference inspection copy are removed.46 GiB remains free;
intentional immutable source backups and unrelated user caches are preserved.
No archive/IPA retained, TestFlight upload, Git publication, backend deployment,
tester change, new service or spending.
