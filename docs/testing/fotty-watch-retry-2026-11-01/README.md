# Watch acknowledgement, fallback and Retry — 1 November 2026

Owner-approved scope: repair these three paths and test Jet iPad. Leave the
phone, FPL, multi-stream and TestFlight unchanged. No cloud/Git publication.

## Implementation contract

- Normal Watch reserves one visible pending action and yields a feedback frame
  before current-catalog/retained-player validation. The tapped button displays
  Opening; invalid/expired actions reject visibly. Retained paused playback is
  reopened without a stream restart, including while late discovery is pending.
- Initial native startup timeout may try an already-admitted, current exact
  alternative with positive decoded-playback history before repeating the failed
  route. Without an eligible alternative the existing one selected retry stays.
  Positive history is ranking evidence, not proof of the current programme.
- Explicit Retry owns a fresh bounded all-enabled/source-supported discovery,
  bypassing the short-lived descriptor index and the optional adapters' metadata
  caches. Keep the failed pane until fresh choices are admitted, show progress
  and cancellation in that pane, then mount one new owner. Retry resolves fresh descriptors instead of directly
  replaying the stored failed choice; a provider may advertise the same URL
  again. No automatic discovery loop is authorized by a failure.
- Duplicate Retry shares one owner. Cancellation, backgrounding, changed attempt,
  changed user intent, manual replacement and current identity/terminal vetoes
  invalidate late successes and failure-only completions.
- Default adapter caching, registered paths, source opt-ins, request inventory,
  source access limits and transport/identity/expiry guards remain intact.

## Consolidated gate

One owned output directory, sequential Catalyst policy tests then signed iOS
Release220. Four focused test files are registered mechanically in the existing
project; no XcodeGen regeneration that could reset unrelated build settings.
project.yml and the app/widget build numbers agree at220.

Focused suites cover acknowledgement order, retained playback, explicit ownership,
fresh adapter caches, initial fallback and existing startup/retry lifecycle guards.
A passing test/compile is not physical UI or decoded-playback acceptance.

## Physical acceptance

On free Jet only, install normal220 and verify Watch acknowledgement, source
picker/playback, the initial fallback when a real eligible failure occurs, and
Retry's fresh source lookup/cancellation after a real failure. Require actual
correct-programme observation and90second native advancing continuity for any
claimed stable channel/match delivery. Do not manufacture a fixture or relabel a
skip/future listing as a pass. Keep deterministic unit acceptance separate when
current production conditions do not exercise a branch. PiP/fullscreen and
multi-stream are outside this targeted physical gate.

## Automated result

Final selection:166 passed,0failed,0skipped. All26 newly added regression methods
passed, including the repeat-alert Retry ownership/cancellation cases. Catalyst
is policy/adapter evidence, not iPad visual or playback proof. The first compile
caught a test-only missing enum argument; it was corrected. An earlier164-test
pass preceded the final alert-Retry review repair; that166-test result supersedes
it. The initial signed compile was intentionally interrupted before installation
so the final ownership repair could be included. One final device candidate220
was built, signed, installed and launched; no intermediate build was installed
in this gate.

Status: final signed220 compile/signature passed; app/widget220 installed and
normal app launched on Jet. No source settings were changed. Physical checks
are in progress. Home Watch immediately displayed Finding a broadcast with
Cancel and disabled Watch actions; a native picture subsequently appeared. The
hero label itself remained Watch, so Opening was not observed there. This short
feedback check is not a source hold/qualification. A shared Device Hub selection
conflict currently prevents safe further iPad input. A chat-coordination question
is pending; silence is not permission. Phone input/build/install remains excluded.

The device-targeted XCTest helper compiled against the same Release220 product.
Its physical bootstrap timed out waiting for Apple UI Automation approval before
any test methods ran. This is an access gate, not a playback-test failure or pass.
The owner has been asked to approve the iPad prompt. Willow90s/source-picker and
failed-player Retry/Cancel remain unaccepted physically. No phone input occurred.
43protected FPL/multi source files and11stable preferences/source choices match
the pre-install backup. Ordinary health/history changes from approved checks are
preserved. No source toggles, cloud/Git publication or TestFlight actions.
