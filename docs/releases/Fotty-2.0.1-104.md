# Fotty 2.0.1 (104) — playback-confidence private candidate

Prepared 2026-09-19; device gate updated 2026-09-20. Status: **private Jet iPad
installed and launch-qualified; Watch Two interaction remains open**.
No TestFlight upload, tester change, backend deployment, iPhone install, commit
or Git publication is included.

## Release purpose

This patch release consolidates the accepted video-first Watch Two work from
private build 103 and makes the beta evidence truthful for that workflow. It is
not a new feature batch. The user-facing goal is dependable playback with useful
recovery and enough privacy-safe evidence to distinguish an app failure from a
provider failure during the next tester round.

## Included work

- Advance the app and Live Activity extension together to 2.0.1 (104).
- Keep Watch Two's wide-iPad Focus layout, true 16:9 viewports, one-tap panel
  promotion, Equal option, independent source controls, explicit audio owner and
  no-reload Fit/Fill behavior.
- Record both Watch Two panels in the existing on-device quality system. Attempts,
  decoded starts, in-place recovery, automatic failover, terminal failure and
  startup time now appear under the installed build instead of being absent.
- Use one shared privacy-safe playback context for the normal player and Watch
  Two. It retains only mode, route, provider family, safe provider label, attempt
  identifier, approved failure/recovery codes and validated opaque CS source
  keys; it does not retain fixture names, URLs, headers or free-form errors.
- Add a test that prevents marketing/build drift between every Xcode target,
  `project.yml`, the app plist and the Live Activity extension plist.
- Repair the opt-in playback soak left behind by the dead-code cleanup. It now
  owns its public Apple reference HLS URL directly and does not force that
  header-free stream through Fotty's provider-header proxy. A separate
  20-second diagnostic compile mode remains available; release duration stays
  120 seconds.

## Deterministic verification

- Complete simulator-free `tools/ios-ci.sh`: **passed** on public Xcode with the
  full Catalyst policy suite and generic iOS Release compile.
- Live Premier League / Champions League fixture contract: **passed** with 380
  PL and 144 CL fixtures for 2026/27. No UCL fixture was inside the 72-hour
  provider-readiness window at the time of the check.
- CPL authority comparison: **passed** for all 39 fixtures. The documented
  match-28 verifier disagreement remains; Fotty correctly retains the official
  schedule rather than silently accepting the aggregator's five-hour shift.
- Live provider football identity: **passed** across three reachable feeds.
- Reference native-HLS soak: **passed** for 120 seconds with decoded progress,
  one unchanged request/source/player item and zero automatic failovers. The
  first attempt exposed and then repaired the stale test helper and incorrect
  fake-header route; it is not counted as passing evidence.
- Complete simulator-free `tools/ios-ci.sh` after the soak repair: **passed**.
- Jet iPad Watch Two UI journey: **time-dependent and not run**. Two attempts on
  19 September were blocked when the iPad re-locked. The first unlocked retry on
  20 September reached Apple's runner but timed out enabling automation. After
  the owner enabled UI Automation, XCTest entered Fotty, selected Home and waited
  15 seconds for Watch Two. The control correctly remained absent because the
  live catalog did not contain two qualifying watchable matches. No Watch Two
  layout or source assertion executed; this is non-applicable live availability,
  not a player failure or a completed interaction pass.
- Signed optimized Release build, strict signature check and in-place install:
  **passed**. After the automation attempt, the temporary runner was uninstalled
  and the optimized Release was rebuilt and restored. CoreDevice independently
  reports `com.jelani.Fotty` 2.0.1 (104), launches it, and observes the foreground
  process at every 10-second interval through a complete 60-second hold.
- Crash query before disconnect: only the retired 13 September Fotty report was
  present; no new build-104 crash was observed.
- Cleanup: all bounded UI/performance/diagnostic roots and the UI-test runner
  were removed. The optimized Release was restored, re-read as 2.0.1 (104), and
  passed another 60-second launch hold. Free space remained about 61 GiB.

## Promotion boundary

Build 104 is not ready for TestFlight merely because it compiles, installs and
holds its process. Before promotion, finish the Watch Two interaction gate on
this exact build. Wider confidence still requires the normal
real-match checks for startup, pause/resume, source switching, background/PiP
and a sustained session. TestFlight upload remains a separate owner-approved
gate and would require focused What to Test notes plus exact-artifact acceptance.
