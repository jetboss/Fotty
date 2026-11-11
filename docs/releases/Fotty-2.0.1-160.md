# Fotty 2.0.1 build 160 private playback qualification

16 October 2026, Tobago. Signed Release 2.0.1 (160) is installed on Jet iPad
Air 4, iPadOS 27.0.1. The approved core experience from 148 remains. Current
native fullscreen, Pause/Play, retained-Done PiP Restore and background PiP
checks pass within the observed journey. The complete playback gate remains
open: a successful Web/Web-to-both-native Watch Two conversion is unqualified,
and a second native source experienced real HLS failures during pair testing.
Phones, FPL, shared TestFlight 121 and backend deployments are unchanged.

## Repairs in 157 through 160

The owner accepted a brief restart for deliberate Watch Two audio conversion.
Both captured native candidates prepare paused, muted and disconnected, without
candidate shared-audio activation. Both actual Web owners must retire and
acknowledge teardown before either candidate starts. Adoption/start authorization
is coordinated as one pair, not two single transfers. Exact model, source,
request, intent epoch, scene, generation, PiP and fullscreen guards are rechecked
after waits. Pause followed by Play renews the intent epoch, invalidating stale
work. Missing or incompatible preflight leaves current viewing unchanged.
After retirement, failure cannot silently revive only one Web sibling.

158 prepares the existing scoped native relay before candidate HLS validation,
so validation and AVPlayer use the same credential-scoped delivery path. Cookie
domain/path, selected origin, TLS, public-address and redirect restrictions stay
intact. Failed candidates pause/disconnect and stop their relay. Typed local
preflight stage/outcome records contain no private stream URL or credentials.

159 adds the candidate item's bounded error chain, Apple HLS error-log category
and that candidate's own relay failure evidence to failed preflight receipts.
It does not substitute the active player's relay or infer HTTP status from a
Foundation error code. A relay's last error may be older than the terminal item
failure; its recorded age matters.

160 fixes a confirmed recovery gap: native AVKit Pause stopped recovery tasks,
but subsequent legitimate Play while the item was still waiting did not rearm
them until a later playing observation. Accepted foreground Play now enters
the existing recovering state, rearms the existing watchdog and eight-second
resume validation, without another Play, seek or reload from the observer.
Pause cancels those tasks. Exact player/item/source/request and presentation
guards remain; background reload policy is unchanged. The timing dependency
preserves the live eight-second deadline and makes its test deterministic.

## Frozen source and verification

Final 160r2 passed 1,489 Catalyst tests, two existing optional skips, zero
failures, 1,491 total. Thirty-two tooling tests, five provider identity vectors,
native source membership, version checks and generic unsigned native Release
passed. Signed native Release compilation, strict signature verification,
Jet installation, actual version readback and normal launch passed.
All 42 FPL source hashes equal 159; earlier 157–159 comparisons also preserved
the paused FPL baseline. Catalyst is a freshly built unit host, not the old
installed Mac app. No simulator or physical XCTest runner was used here.
The existing FocusState test warning remains.

An initial 160 test run was interrupted because the new test gate incorrectly
captured the unrelated control-hide delay as well as resume validation. The
corrected test gate captures only the eight-second wait, checks the pending
count before awaiting and drains on exit. The final clean run above passed.
That interrupted run is not counted as a pass and was never installed.

Final pre-build source receipt, 1,110 files, one history-free local recovery
commit; main repository refs and remotes were not changed:

- Receipt: `backups/release-source/2.0.1-160-native-resume-recovery-r2`
- Commit: `d71ef5c2a6e8626264ba8f75ea37ce15756460e8`
- Source SHA256: `9798e87abbf332ecb350a30395d25b6857983444f6c30b8529a6c396d5ed61ad`
- Bundle SHA256: `541decbcd0ef17e8a743301ad97fc8626ff707c38cbc7a58e0cf3a424f67c12c`
- Signed executable SHA256: `b81939e880dfffe7d626163f3741a686448312bd9c31938718ac2c2fbf98552d`

All inputs compared before build/sign/install and after the physical checks,
before these separate qualification notes. Intermediate 158 and 159 full gates
passed 1,484 and 1,485 tests respectively, each with two optional skips and zero
failures. Their installed media outcomes below remain part of the evidence.

## Observed native results on 160

Current Detroit–Toronto CS1 attempt `1A03370A` decoded at 23:45:11.631 UTC,
2,847 ms after start. Video advanced inline and in actual Apple fullscreen.
Pause held its frame; Play resumed, with transport-playing evidence at
23:46:35.194 after a 628 ms wait. No new playback attempt accompanied fullscreen,
Pause/Play or either PiP Restore.

Native PiP continued after Escape dismissed fullscreen to the retained companion.
PiP Pause/Play worked, with transport-playing evidence at 23:47:43.378, and the
actual system Restore removed the floating window and returned to advancing
native fullscreen. A second PiP run continued on the actual iPad Home screen
from about 23:48:07 through at least 23:49:30. Background Pause/Play resumed
advancing basketball, with transport-playing evidence at 23:49:52.542. System
Restore again returned to fullscreen; Apple Close returned to advancing inline
video, showing 35–35 at 10:52 in the second quarter. These are bounded visual
passes, not exact runtime-object, audible-output or uninterrupted uptime proof.
Lock/unlock was not exercised in this continuation.

Added Orlando–Miami CS1 attempt `0AEEBC53` decoded at 23:56:36.908 UTC.
Both native pictures advanced. Selecting right then left audio changed the
selected-owner UI without replacing Detroit's attempt. Swap retained the correct
match identities and selected owner. After Swap, Orlando's native Pause held
49–42 at 7:21; selecting that paused pane's Audio did not force Play. The right
Detroit picture continued. Device Hub does not relay sound, so this does not
qualify audible exclusivity.

Explicit Orlando Play at 23:59:21 then stalled. At 23:59:48.527, the existing
watchdog recorded `stall_timeout`, an Apple error-log CoreMedia -12312 with
`segment_discontinuity_changed`, and an earlier relay HTTP 404 aged 100,844 ms.
Fallback CS2 `749700F2` decoded at 23:59:51.049, then failed to play to end at
00:00:12.611 UTC on 17 October with CoreMedia -12312 and error-log
`segment_uri_changed`. Same-source retry `B06438F1` decoded at 00:00:15.308;
Orlando visibly advanced again, reaching 52–45 at 6:36. Recovery is a bounded
pass, not an uninterrupted original-source or provider-only failure claim.

Independent source review found no demonstrated relay rewrite cause: sequence,
duration and discontinuity tags are preserved; identical upstream URLs and
reviewed CS aliases keep stable local routes across refreshes. Changed upstream
signatures/provenance can intentionally get different routes. Consecutive
originating playlists would be needed to locate the consistency change. The
older 404 alone is insufficient causal evidence. Do not alter discontinuity
tags, broaden aliases or weaken origin/TLS checks to conceal these errors.

After Swap, right-pane Keep This Match correctly retained Detroit, still on
`1A03370A`; the other pane closed at 00:00:43.716. Stop closed Detroit normally
at 00:01:00.756 UTC. Per-pane Sources opened for the intended match. The lower
source rows did not move through this session's mirror scroll/drag attempts;
no successful manual lower-row selection or app scroll defect is claimed.

## Web conversion remains unqualified

On 159, Detroit Web Broadcast 2 `5C9099AE` and Orlando Web Broadcast 1
`FCF7B78F` both visibly advanced. Selecting the other pane's Audio produced
native candidate isolation request/ack at 23:14:52.123/.148 UTC. Preflight then
failed readiness at 23:14:53.200 after 1,638 ms. The exact candidate reported
URL -1102 with underlying CoreMedia -12660, matching error-log -12660; its own
relay recorded `upstream_response` HTTP 403 only 86 ms earlier. Both Web pictures
continued and the app preserved the original viewing rather than retiring either
owner. This is a passed safe-failure path, not a successful native conversion.
The denial's underlying cause is not established.

158's Golf candidate likewise failed readiness, while the original Web path
continued; a Cancel tap came after its alert and is not a physical Cancel pass.
159's separate native CS2 fullscreen/PiP picture stalled despite control changes;
system Restore UI alone did not qualify resumed video. 160's current CS1 passes
do not erase those dated source failures.

160's available default choices were native CS sources. Its native/native pair
checks cannot replace the missing real Web/Web-to-both-native transaction.
Remaining acceptance requires playable validated candidates for both existing
Web owners, actual retirement before either Play, both pictures advancing, correct
audio behavior, preserved pause and pane actions. Do not invent media, force Play,
relax source safety or claim completion from unit tests or a safe refusal.

## Handoff

Stopped all test media/PiP and returned Jet to Fotty Home, All sports, Light,
landscape; interests, sports-sync OFF and existing empty test search/history were
not changed. Phones and FPL were not opened. Keyboard capture is OFF.
Device Hub was quit normally and its pinned process is absent. Removed the owned
1.0 GB final build gate, including DerivedData, temporary signed app, result
bundles and logs, plus the owned diagnostic-reader directory; raw preference
copies were unlinked immediately after each bounded extraction. The earlier
interrupted 715 MB test gate was also cleaned. Free disk returned from 19 to
20 GiB. Valid source recovery receipts and the installed 160 app remain;
unrelated caches and user artifacts were not deleted. The temporary awake
assertion is limited to this qualification, with no permanent sleep/lock changes.
This is a private qualification build, not a TestFlight release candidate.
