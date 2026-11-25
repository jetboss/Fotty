# Fotty Sports Hub 2.0.1 (109)

Prepared, installed and visually checked privately on 2026-09-20. Status:
**native glass navigation and compact Home identity verified on Jelani iPhone**.
No TestFlight, iPad, tester, backend, web or Git publication action is included.

## Scope

- Replace the custom opaque Home/Matchday/FPL/Settings dock with four genuine
  native `TabView` items. iOS now owns the functional Liquid Glass navigation
  surface, including on-scroll minimization, selection, safe-area behavior and
  accessibility. Stable tab identifiers remain available for UI verification.
- Keep the approved three-column phone sports grid at normal text sizes, but put
  the real sport artwork above its label. The complete tile width now belongs to
  names such as Football and American football instead of being consumed by an
  icon-and-label row.
- Give each scheduled team's name its own line, use the semantic secondary-list
  text style, reduce paired-badge width, and reserve a scaled minimum information
  width before countdown/reminder actions. Larger text reflows instead of forcing
  essential match identity through middle truncation.

## Verification

- Complete simulator-free `tools/ios-ci.sh` passes, including Catalyst units,
  the rendered 361-point compact-phone sports grid and generic-iOS Release.
  The two-row sport control block remains at or below its 190-point contract.
- Source regressions require all four destinations to be real native tab items,
  preserve stable accessibility identifiers and reject a second custom dock.
- The signed optimized device gate passes. CoreDevice reports 2.0.1 (109) and
  both the app and Live Activity extension running on Jelani iPhone.
- Fresh 1125-by-2436 screenshots of exact build 109 in light and dark appearance
  confirm one functional glass tab bar and readable two-line live/Up Next team
  identities. The sports grid is below the captured scroll position, so its
  exact-device visual remains for owner inspection despite the rendered pass.
- The temporary dark launch used a process-only preference override; Fotty was
  relaunched normally afterward. Bounded build output was removed.

## Acceptance boundary

Owner inspection of the on-device sport tiles and tab interaction remains open.
No iPad or TestFlight action is authorized by this private iPhone result.
