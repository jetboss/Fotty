# Fotty Sports Hub 2.0.1 build 124 — private all-sport native repairs

6 October 2026. The owner requests deployment to the phone for testing. Target:
Jelani’s iPhone 15 Pro Max only. No TestFlight, other device, Git publication,
Worker deployment, feed activation, paid-policy or FPL feature work.

## Included native changes

- Preserve fixture cache watermarks and require newer trustworthy receipts for
  corrections/status changes. Held starts cannot create confident countdowns or
  reminders; saved bookmarks remain.
- Use fresh independently matched provider listings for Broadcast listed rather
  than inferring LIVE from kickoff. Details and controls share the certainty
  policy; Cricket Home/Matchday agree on unconfirmed starts.
- Strict unique verified MLB/NHL-to-provider joins, reviewed aliases and explicit
  local provider-ID continuity improve stream lookup, bookmarks and reminders.
  Conflicting competition/squad/date facts and ambiguous doubleheaders reject.
- Upcoming rows give team identity more room and put countdowns below it;
  compact reminders keep 44-point targets. Channel cards retain their right-side
  Watch button without repeated channel/status copy. Badges and artwork remain.

The all-sport registry, pending polling and monitor repairs remain staged.
Production Worker `6399f52d-e0d6-45e8-ba3d-1462a94093e3`, source
`2026-10-06.cricket-isolation-1`, is unchanged. This phone build does not establish
that those undeployed backend fixes have reached production.

## Source and build evidence

- App Store Connect's current visible iOS build list shows latest shared121
  Internal / Testing. Local installed123/source123 advance coherently to124.
- Reuse the just-completed exact native-code source gate:818 Catalyst tests pass,
  two optional skips, zero failures, generic unsigned iOS Release passes. The
  packaging changes afterward are version metadata and release documentation,
  not functional production-code changes. No repeat old installed Mac-app test.
- Fresh generated catalog/version preflights and metadata-only live provider
  identity pass across three reachable feeds.
- Official `/Applications/Xcode.app/Contents/Developer`, Xcode27.0/27A266a,
  jobs1; signed optimized generic-iOS Release succeeds. Strict deep app and
  extension signatures, compiled2.0.1/124 versions, normal bundle identity and
  three blank embedded provider keys pass. No simulator or UI-test helper.
- Pre-build receipt: `backups/release-source/2.0.1-124-owner-iphone`,998 files,
  one history-free commit `b852649f3c7931af83ba1a8e40cd55738a19596b`.
  Source SHA256:
  `883d844366b0909db6b882afaf478f1ca9769b9cf5cf2f2b651295a7a5d24bb5`.
  Source compare passes immediately before installation. Subsequent handoff
  documentation is not part of that frozen pre-build receipt.
- Installed signed executable SHA256:
  `542c471871b89722bf5c9186f7df3358a84aa524ca6f70306fa2b34732254271`.

## Installation and remaining acceptance

Fresh CoreDevice inventory identifies the named connected, unlocked physical
iPhone. In-place installation succeeds, database sequence2504. An independent
installed-app read confirms2.0.1(124); ordinary argument-free launch succeeds and
the normal app process remains present at10/20/30/40/45seconds. No uninstall,
data reset, alternate device, source flag changes or network reconfiguration.
The preserved installation method is not private-account equality proof.

Actual phone layout/large text/reminders, live stream switching, audible playback
and PiP/background acceptance remain for this exact build; a45-second process
hold is not proof of those interactions. The earlier818-test/rendered source gate
also does not substitute for physical verification.

The sole320MiB owned build root (DerivedData/app/log/script) is removed by its
cleanup trap.26GiB free remains. The intentional small19MiB source recovery bundle
is retained, not a temporary build artifact. Shared TestFlight121 and Jet iPad120
remain unchanged; Fotty is left launched on the iPhone for owner testing.
