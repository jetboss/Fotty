# Fotty 2.0.1 build 148 private core experience checks

16 October 2026. Signed Release 2.0.1 (148) is installed and read back on
Jet iPad Air 4 running iPadOS 27.0.1. The four approved core improvements are
implemented, but playback acceptance is incomplete: mixed Web/native Watch Two
can pause its sibling. This is not a TestFlight-ready or completed-device-gate claim.
Phones, shared TestFlight 121 and FPL remain unchanged.

## Implemented improvements

- Playback copy follows typed state: Connecting, Reconnecting, Paused and Source
  unavailable no longer appear as Playing. Recovery offers Sources alongside Retry
  when alternatives exist; cancelling Sources preserves the current error.
- Whole-sport interests work alongside teams and competitions in Home, Search,
  Matchday and settings. Sport selections use bounded validated local storage,
  compatible private backup and separately namespaced sports-only sync intents.
  Existing sync consent and account guards remain; FPL is excluded.
- Home has an always-available scope menu, clear filters and direct access to
  interests. Personalized upcoming followed fixtures share availability rank so
  an imminent unlisted cricket fixture is not displaced by tomorrow's listed
  football. Live and broad-catalog source prominence are preserved.
- Matchday defaults to Full Matchday. Its optional anchored Time window has an
  explicit start/end and Show Full Matchday recovery. The constrained iPad sidebar
  uses a native menu so Until midnight is not truncated.
- Watch Two has per-pane Sources, Audio and Change Match actions, a searchable
  full eligible catalog and sport filter. Replacement resolves before retiring
  only the selected pane, with stale-generation, duplicate-fixture, source-safety,
  survivor and native fullscreen/PiP ownership guards. No third playing decoder
  is introduced by pane replacement.
- Sources show listed metadata and the actual selected playback mode, not guessed
  quality or PiP support. Native fullscreen is a direct action; Focus remains a
  distinct presentation of the approved viewing experience.
- Search includes bounded local recent queries, clear history and real followed
  team, competition and sport shortcuts. Match details and Save/Remove are quiet
  native More actions. Saving does not silently enable reminders. Narrow and
  accessibility-size rows reflow their controls without hiding team names.

## Local tests and source receipt

The frozen-source Catalyst suite passed 1,346 tests with two existing optional
skips and zero failures, 1,348 total. Thirty-two tooling tests, five provider
identity vectors, source membership, native version checks and the simulator-free
generic iOS Release gate also pass. Existing FocusState fixture warnings remain.
Signed device app, extension and UI harness compile; strict signature verification,
installation and actual version readback pass. No simulator was used.

All 42 FPL source hashes equal the starting state. Pre-build source receipt
`backups/release-source/2.0.1-148-native-final` captures 1,106 files in one
history-free local recovery commit, without changing remote Git state:

- Commit: `6eb220d74fe15bc0051ae4eab1c464413aa6d764`
- Source SHA256: `1480346810f33003203ae2a8abbef2b0fd007d2de704f546c9a30be22fc25ced`
- Bundle SHA256: `afdc88a04ee7b9aadf1de0506443fa270337b3cf58be43ccbc4340c8337266f8`

All files compare before build/install and again before these acceptance notes.
Later acceptance/memory edits do not change production inputs. Ten reviewed native
component goldens retain their separate approved visual-review receipt under
`2.0.1-147-adaptive-components`. Hosted UIKit capture replaces unsupported
ImageRenderer Menu rendering in the affected tests; it is not native journey proof.

## Observed iPad results

- Home and Matchday use landscape width and reflow in portrait. Badges and sport
  artwork remain. Light/Dark were inspected. These are not phone or full
  large-text journey passes.
- Whole Cricket interest and Only my interests persist through navigation and
  reinstall. Build 148 places India Women versus Zimbabwe Women, nine minutes
  away at inspection, before later cricket fixtures. Tests also exercise caps
  three/four and retained live prominence.
- Full Matchday, anchored Time window, the full Until midnight menu label and
  Show Full Matchday empty-window recovery work on the actual iPad.
- Followed Liverpool search, local recent query/clear and Done work. Match More,
  Details, Save, quiet saved cue and Remove work without requesting notifications.
- Sources, cancellation, switching listed broadcasts, Focus/Companion, Add Match,
  per-pane actions, current-fixture exclusion, changing only the selected pane and
  keeping the right pane as the sole retained match were inspected.
- ONE Inner Circle 35 decoded actual native video. The real AVKit fullscreen and
  Apple Play resumed advancing video. This visual check does not establish exact
  player/item identity or audible output.
- Darts and Golf Web broadcasts decoded video. Tennis displayed video but later
  reconnected. These are bounded observations, not provider uptime guarantees.

## Playback and automation blockers

Adding native ONE beside playing Web Darts paused Darts. Resuming Darts then
paused ONE without an intentional ONE pause. Simultaneous mixed playback fails
this gate. The coordinator review found no explicit retained-sibling pause/load
in the add or replacement path. WebKit iOS VideoAudio concurrency restrictions
support media-session arbitration as a hypothesis, not a proven exact cause on
the shipped OS. There is no verified transparent repair yet.

Do not ignore all Web pause events during native preparation: an existing test
correctly requires deliberate provider Pause to cancel handoff. Do not repeatedly
force Play or apply global mixWithOthers to hide the defect. Apple mixing affects
other apps, not just sibling Fotty panes. The smallest next evidence is a bounded
candidate/validation/preparation/activation/Play/pause timeline for the failing
pair, followed by a focused repair and external-audio, focus, explicit-pause and
background/PiP checks. Current native extraction already attempts validated
decoded-frame handoff; conversion is not a missing toggle.

The final all-native pair and PiP Home/real system Restore/fullscreen Close/inline
progress journey remain unqualified. Later Golf sources stayed Web; the formerly
available native event disappeared from the eligible catalog. No finished event
or invented source was substituted. Earlier build 146 PiP evidence does not
qualify build 148.

Physical XCTest timed out at the device's Touch ID Enable UI Automation prompt
before any method ran. The prompt was cancelled; normal Device Hub touch checks
continued without bypassing authentication. Exact identity/time measurements,
audible confirmation and continuous-frame assertions are not claimed. No current
Fotty or current-day jetsam report was found during a bounded crash-list check;
that is not a crash-free soak result.

Primary references: [WebKit iOS media-session restrictions](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/MediaSessionManagerIOS.mm),
[Apple audio mixing](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers),
[Apple audio-session activation](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/ConfiguringanAudioSession/ConfiguringanAudioSession.html).

## Device and workstation cleanup

Temporary interests, filter changes, saved match and search history are restored
to their starting values; sports sync remains off. Original Light appearance,
landscape orientation and keyboard capture off are restored after checks. Test
playback is stopped. The exact UI test runner is removed; Fotty 148 remains.
Owned build products, result bundles, screenshots and temporary UI-only scheme
were removed after recording these results, reclaiming approximately 1.2 GB;
20 GiB was free afterward. Installed Fotty and source recovery receipts remain.
Device mirroring and the temporary keep-awake process were stopped; their sleep
assertions are absent. Permanent sleep and security settings were not changed.

No shared release, phone install, backend deployment, publication, privacy-policy
expansion or paid-service change occurred. Sync/widget and older acceptance gaps
remain separately scoped; these core checks do not clear them.
