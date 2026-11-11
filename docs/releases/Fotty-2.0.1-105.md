# Fotty Sports Hub 2.0.1 (105)

Superseded during physical verification by private build 107; see
`Fotty-2.0.1-107.md` for the corrected root-navigation result.

Prepared and installed privately on 2026-09-20. Status: **Jelani iPhone install
verified; launch and physical visual acceptance pending unlock**. No TestFlight,
iPad, tester, backend, web or Git publication action is part of this build.

## Scope

- Translate the owner-approved Apple-inspired Home concept into native SwiftUI.
  One badge-led glass live panel now leads Home, followed by compact Up Next
  rows and then Browse Sports. Search and iPad Watch Two use restrained material
  chrome; routine business/data owners are unchanged.
- Preserve real team artwork through `TeamBadgeWindow`, including the honest
  initials fallback. Up Next uses paired badges without inventing crests.
- Restore recognizable full-colour Apple equipment artwork for Home sport tiles
  while retaining SF Symbols for standard actions. The three-column phone grid,
  selection state, interests, league filters and all-sports access remain.
- Preserve current stream resolution, direct Watch feedback, countdown/reminder
  policy, sorting, search, Matchday, player, PiP and MultiView ownership.

## Verification

- The first render pass triggered the existing compact-grid height regression.
  The sport tile was tightened without removing its artwork; the focused rendered
  phone test then passed.
- Complete simulator-free `tools/ios-ci.sh` passes, including Catalyst units and
  the unsigned generic-iOS Release build. A regression asserts the approved
  football, cricket, basketball, baseball, tennis, American-football and fight
  artwork mapping.
- The signed optimized Release build passes strict signature verification and
  installs in place on the explicitly selected Jelani iPhone. CoreDevice reports
  `com.jelani.Fotty` as 2.0.1 (105).
- Automatic launch was denied only because the phone re-locked after installation.
  Exact-build launch hold and native screen comparison therefore remain open.
- All owned CI/focused/device-build roots were removed. Free space returned to
  about 59 GiB.

## Acceptance boundary

Build success and installation are not visual proof. On the unlocked iPhone,
compare the actual dark Home screen with the approved concept: Live first, one
prominent real-badge panel, compact Up Next rows, Browse Sports afterward,
full-colour equipment artwork, calm material chrome and no oversized fixture
cards. Also inspect light appearance and larger text before shared promotion.
