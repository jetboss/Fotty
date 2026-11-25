# Fotty everyday usability and recovery implementation

Date: 5 September 2026  
Status: private build 64 passes focused iPhone web-control acceptance; iPad and
broader hands-on acceptance and distribution pending

## Outcome

Roadmap batch 4 now has a code-level implementation without changing Fotty's
navigation or adding visible product clutter.

- Home remembers the selected sport, football league, cricket filter,
  Following choice and scroll position for the current scene. Search remembers
  its query and position; My Matchday remembers its position. Restoration waits
  for layout before accepting new offsets, so an initial zero cannot erase the
  saved location. FPL retains its existing manager-scoped workspace state.
- Settings rows use scaled Fotty typography and reflow at accessibility sizes.
  Playback Sources inherits Light/Dark/System instead of forcing dark navigation
  chrome. Privacy is a normal pushed destination with one Back path, and the FPL
  deadline card stacks rather than crushing its label.
- Matchday writes are encode/write/verify-before-publish operations. A failed
  save or removal leaves the previous in-memory and stored list intact, reports
  the problem on Home, Search or Matchday, and never cancels the reminder for a
  removal that did not persist. Reminder creation removes its notification again
  if the required Matchday save fails.
- SwiftData's emergency in-memory fallback is visible on every team/league edit
  surface. Those actions are refused with an explanation instead of looking
  successful for the remainder of a session.
- Backup export decrypts and validates its newly encrypted data before opening
  Files, records only a successful verified export, and uses an actual-file
  round-trip regression. Restore still requires preview plus destructive
  confirmation; Matchday persistence is attempted before followed-team
  replacement, and a failed SwiftData replacement rolls Matchday back.
- Feedback now presents an explicit prepare → hand off → finish sending → confirm
  receipt sequence. Copy records a preparation receipt but continues to say that
  neither copy nor the share sheet proves delivery.

## Verification completed locally

- Swift syntax parsing passed for every changed production and test source.
- Debug Mac Catalyst build-for-testing passed with no new Swift concurrency
  warning after the persistence writer was made nonisolated.
- The complete simulator-free gate passed after the desktop was unlocked: 486
  of 488 tests passed and the two intentional live/soak tests skipped. That
  includes all 18 repository-file inspections, 20 focused Matchday/backup/state
  tests, injected failed writes and a real `.fottybackup` temporary-file round trip.
- The unsigned generic iOS Release build passed using two jobs.
- All seven affected Catalyst journeys passed: Settings and Matchday Dynamic
  Type, Home sport retention, rapid navigation, native Help/feedback, cricket
  discovery and Home discovery. The first ordered UI run exposed cross-test
  SceneStorage state; a DEBUG-only once-per-test-process initialization now gives
  automation a clean start without resetting Home when SwiftUI recreates it.
- Every owned CI, diagnosis and UI-gate build root was deleted after its run.

## Acceptance still required

Two existing Catalyst playback tests emitted AVAudioSession's legacy main-thread
activation warning; it was not introduced by this batch and is retained as a
follow-up rather than changing playback timing inside a usability patch.

Use one exact candidate on the owner-selected iPhone and iPad to check
Light/System, large
text, VoiceOver, rotation, keyboard dismissal and hit targets. Complete a real
Files export, wrong-password rejection and reviewed restore, and receive one
actual tester report. A passing local file test or opened share sheet is not
physical/user acceptance.

Private build 64 is installed on Jelani's iPhone and Jet iPad and physically
passes the reproduced web Pause/Play/provider-Play/Sources path on iPhone. The
iPad UI attempt did not reach a player, and the remaining accessibility, Files,
audible-close and received-feedback
checks are not implied by that focused pass; see
`docs/releases/Fotty-2.0.0-64.md`. No simulator, TestFlight upload, backend
deployment, production configuration change or paid Coach request occurred.
