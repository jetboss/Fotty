# Playback controls — CPL report

The owner reported that a centre tap paused a CPL stream but did not resume it,
while the top-right fallback worked and lower-left provider controls did not.

## Findings and changes

- The WebKit adapter had a UIKit tap recognizer with default touch-end delaying,
  despite cancelling being disabled. Remove that competing recognizer. A passive
  document click observer in each frame only reveals Fotty's controls.
- Bound Fotty's fallback toolbar to its actual buttons at the upper-right video
  edge in both orientations. It no longer spans the video or overlaps the
  provider's lower control bar. Keep four-second playing auto-hide and a visible
  Play action when paused; no new central transport or unmute button.
- Report the decoded player's actual pause/resume state, not just its first
  startup. Scope feedback to that document and source attempt. Rejected Play
  commands restore paused UI. Other media and background suspension do not
  masquerade as a foreground user pause.
- Distinguish a deliberate pause from a transient interruption. A deliberate
  pause cancels native handoff and cannot be undone by delayed recovery/handoff
  callbacks. A genuine interrupted stream can still recover in place.
- Prevent default `_blank` navigation without swallowing a provider control's
  JavaScript click handler. Known nuisance clicks, popup windows and top-level
  navigation remain blocked.
- Executing the injected script (rather than only parsing it) exposed a literal
  Swift `Int(...)` expression in its JavaScript startup timer. Correct interpolation
  restores that timer and allows subsequent stall-monitor installation.

Apple documents that touch-end delaying is enabled by default on gesture
recognizers: [UIKit reference](https://developer.apple.com/documentation/uikit/uigesturerecognizer/delaystouchesended).
The media-state observer uses capture because media pause does not bubble:
[MDN pause event](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/pause_event).

## Evidence and limits

The Computer Use skill opened and confirmed decoded Willow video on Catalyst.
The channel was showing cricket footage, not proof of the exact earlier CPL
broadcast. A provider media accessibility action hung and the subsequent state
read timed out; the owned normal Mac app was terminated. Do not claim that
centre/lower-left taps were reproduced or passed on that live session.

The final playback-source suite passes 144 unit tests, one opt-in HLS soak
skipped, zero failures or runtime warnings. Four new regressions execute actual
monitor JavaScript and check pause/resume, failed Play, passive clicks, protected
navigation, paused stall timing, source/attempt freshness, background behavior,
native-handoff cancellation and interruption recovery. One initial regression
found interruption recovery being suppressed; explicit pause intent fixed it.

The owner explicitly requested physical-iPad testing, as an exception to normal
TestFlight-first delivery. `Jet iPad` is the physical iPad Air 4 and was unlocked,
running 2.0.0 (35). The strictly verified normal signed build 36 was installed,
independently reported as 2.0.0 (36) by CoreDevice, launched successfully and
survived a 30-second foreground process hold. Exact centre/lower-left pause and
resume acceptance is still open; a process hold is not a touch test. No simulator or
iPad UI-test helper is used. TestFlight remains build 35 until a separate upload.

The approved Home/cricket changes remain intact. The owner subsequently asked
to complete optional light mode and restore team badges and sport equipment
icons. That follow-up must use a higher build number if installed; it does not
retroactively change the source or acceptance verdict for build 36.
