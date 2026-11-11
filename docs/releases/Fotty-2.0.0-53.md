# Fotty 2.0.0 (53) - private one-tap CPL candidate

Date: 2026-09-03. Status: **installed only on Jelani's iPhone; not uploaded**.
Shared internal TestFlight remains 2.0.0 (51). Private build 52 was immediately
superseded before acceptance because its channel-selection sheet added an
unnecessary second tap and its discovery projection still said Cricket was
tomorrow during a current scheduled CPL match.

## Scope

- A trusted CPL fixture whose listed start has passed now counts as `on now`
  until its bounded T20 window ends. The UI says `On now · listed start`; it does
  not invent an official live score or result. Generic source-less events and
  undated cricket remain excluded.
- A current source-less CPL fixture now displays one `Watch` action. Tapping it
  directly opens the preferred active cricket channel instead of presenting a
  second choice sheet. Fox Cricket is preferred because the owner's current CPL
  observation confirms it carries the match more consistently; Willow remains
  visible as a separate channel row for manual use.
- Exact team-and-kickoff match sources still take precedence whenever the
  provider supplies one. Generic channels are not attached to the fixture and
  their programme is not represented as independently confirmed.

## Evidence

- Focused regressions prove a started source-less CPL fixture contributes
  `1 on now`, while channels, generic source-less fixtures and unknown starts do
  not. They also prove Fox is selected before Willow regardless of provider
  ordering, retired sources are excluded, the two-minute/eight-hour availability
  bounds remain enforced and the obsolete second sheet is absent.
- The complete simulator-free Catalyst unit/policy suite and generic unsigned
  iOS Release build pass under Xcode 26.6 with two jobs.
- The physical gate passes current provider identity across all three reachable
  feeds, strict signing, signed Debug compilation/installation and final signed
  generic-iOS Release compilation under the beta toolchain required by the
  connected beta-OS phone.
- CoreDevice independently reports `com.jelani.Fotty` as 2.0.0 (53), with both
  the normal app and Live Activity extension running after launch.

All cleanup-owned `/private/tmp/FottyCI.*` and
`/private/tmp/FottyPhysicalReleaseGate.*` roots were deleted. Free disk remains
approximately 33 GiB. No simulator, UI-test runner, iPad/other-iPhone change,
TestFlight upload, tester mutation, service deployment, Git commit or publication
occurred.

## Physical acceptance

During the current CPL window, the owner confirmed on build 53 that the corrected
flow works: Cricket no longer advertises tomorrow, and one tap on the current CPL
fixture opens the broadcast without the rejected second selection sheet. This is
exact-build physical acceptance for the discovery and one-tap routing correction.
It remains time-scoped provider evidence, not proof that Fox or Willow always
carries every CPL match or that the rest of the wider-beta entry gate is complete.
