# Coach conversation ownership — 28 August 2026

Status: implemented and automatically qualified locally, with the UI warnings
below retained. Unreleased changes on top of private iPhone build 44. No device
installation or upload; physical and live strategic-model acceptance remain open.

## Scope and findings

The owner deferred public distribution and authorized continuing product quality.
This is the next bounded part of the accepted data/Coach-confidence phase, not a
new distribution scheme, redesign or paid-model evaluation.

Source inspection found that the view owned an untracked request and checked only
manager-selection ID before adding its reply. Clearing chat or disabling consent
did not invalidate it. Squad/gameweek/profile/rival changes also could not reject
old-context advice. Error recovery bypassed the shared published-fact/freshness
checks and called the generic local explanation layer directly.

A new fallback regression then exposed another real gap: “What is my current
total?” did not match the scoring classifier. An independent offline probe of
the unchanged Worker also returned false for that query, “What are my current
points?” and “Show my live score”. These explicit current-score requests are now
handled by the same bounded extra pattern in Swift and JavaScript. Future
projection/transfer/captain strategy remains on the reasoning path.

## Correction

- The shared workspace owns the cancellable request, identity, loading state and
  status. Clear/disable/disconnect invalidates it; late errors cannot resurrect a
  fallback or stop a newer request. Valid work survives navigation.
- Completion independently checks consent and the manager, selected/published
  squad, actual/current/planning week, phase, source, bank, transfer count,
  profile and rival. Outdated replies ask the user to resubmit, with no automatic
  paid retry.
- Normal facts and recovery share published picks and scoring freshness. General
  strategy still uses DeepSeek with consent, with labeled local error recovery.
- Delayed injected operations exercise real task completion/cancellation without
  networking. Test preferences are isolated; the UI fixture cannot delete a
  persisted real conversation when its synthetic chat is cleared.

## Verification

Final offline and scoped UI checks:

- Focused `FPLTrustTests`: 53 passed, zero failures or runtime warnings.
- Full Mac Catalyst unit suite: 209 passed, one existing opt-in live-HLS soak
  skipped, zero failures or runtime warnings. The focused 53 are included in
  this full suite, not additional tests.
- Both targeted Catalyst UI checks passed: FPL Dynamic Type/accessibility and
  conversation/workspace preservation across tab switches. The first launch
  timed out enabling Xcode automation before any app test began; the existing
  runner's one permitted retry succeeded. Each successful UI result retains
  the main-thread responsiveness warning seen in earlier beta-Mac gates. These
  warnings remain unresolved; neither result is claimed warning-free.
- Web/Worker `npm run test:unit`: 82 passed, including 25 Worker request/scoring
  contract cases. Upstream/model transports are mocked; no paid model calls.
- Generic iOS normal Release and alternate `ReviewSafeRelease` compilations
  both passed unsigned. No Next source changed; no new
  Next production-build or signed distribution-artifact claim is made.
- Source whitespace check passed. Source/test/project fingerprint:
  `82b8e56943673235c165e089b9c9358c7abca6c61260d4e4d7d4f072119a7a92`.
  Worker scoring module SHA-256:
  `fbc721022c82906e54ac0e94189e3aa4c27ba793c03459adf97cd3a53a355b5e`.

Initial test compilation exposed an older session test that directly assigned
the now-owned loading flag; it now starts a real
injected pending request and checks that navigation preserves it. The first
executed focused run passed 51 tests and failed the current-total wording case
above; the classifier fix follows that recorded failure.

New coverage includes clear/reopen, late error after cancellation, revocation
before the view callback, old/new manager requests, changed context, duplicate
submission, follow-up history, published captain versus draft captain, undated
scoring and direct current-score wording. Worker tests prove the new factual
phrases cannot fall through to paid reasoning when the official feed fails.

## Limits

These tests do not evaluate live strategic advice. Cancellation cannot recall
already-sent data or guarantee upstream billing stops. No paid-model calls,
device UI helper, simulator, Worker deployment, tester/role changes, public
submission or Git publication occurred. The Worker change is local, not live.

Private iPhone 44 and shared TestFlight 43 remain unchanged. Existing physical
acceptance remains open. Allocate a new versioned delivery before installing or
uploading these sources; never reuse the already-distributed build 44.

## Storage

61 GiB free before and after work. All Xcode jobs used one bounded temporary
root/DerivedData, sequentially with two jobs and an exit/interruption cleanup
trap. No owned app/test process remained at completion. The trap removed the
entire approximately 1.1 GiB `FottyCoachGate.NEWnGU` root, including all apps,
results and logs; its absence was checked afterward. Only the source, tests and
durable evidence remain. No simulator was started.
