# Fotty Sports Hub 2.0.1 (107)

Superseded by private build 109 after the owner requested that the working
Liquid Glass surface become Fotty's actual tab bar rather than be removed.

Prepared, installed and visually checked privately on 2026-09-20. Status:
**Jelani iPhone install, launch and Home bar correction verified**. No TestFlight,
iPad, tester, backend, web or Git publication action is part of this build.

## Scope

- Retain build 105's owner-approved Apple-inspired Home: one badge-led live
  panel, compact paired-badge Up Next rows, Browse Sports after the schedule,
  recognizable full-colour equipment art and restrained material controls.
- Remove the hidden native `TabView` that iOS 27 exposed as a large empty Liquid
  Glass capsule above Fotty's custom dock. A layered root container now keeps all
  four destinations alive while only the selected destination is visible,
  interactive and exposed to accessibility.
- Remove the redundant sport-tile checkmark; the selected treatment remains
  visually distinct and exposed through the selected accessibility trait.

## Verification

- Complete simulator-free `tools/ios-ci.sh` passes after the root-container
  correction, including Catalyst units and an unsigned generic-iOS Release.
  A source regression rejects reintroducing a hidden selection `TabView` and
  requires inactive layers to disable interaction and accessibility.
- The signed optimized physical-device performance gate passes. CoreDevice reads
  `com.jelani.Fotty` as 2.0.1 (107), and both the app and Live Activity extension
  are running on the explicitly selected Jelani iPhone.
- A fresh 1125-by-2436 physical-device screenshot confirms that Home now meets
  Fotty's custom dock directly: the empty glass capsule is absent and the approved
  live/Up Next hierarchy remains intact.
- Bounded build output was removed and free space remained about 59 GiB.

## Remaining acceptance

Physical light appearance and larger-text inspection remain open. This private
iPhone result is not authority to install on iPad or upload to TestFlight.
