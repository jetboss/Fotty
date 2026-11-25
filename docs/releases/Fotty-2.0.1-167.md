# Fotty 2.0.1 (167): approved HTTPS CS delivery

23 October 2026. Private Jet iPad gate only. Final signed candidate r3.
No phone, FPL, multistream, cloud deployment, Git publication or TestFlight work.

## Approved change

The owner approved the advertised HTTPS CS route after the bounded playlist
check in release166. Admission now requires the reviewed Nuvio manifest, the
`sktech` source hint, exact `dai-fancode.pages.dev` host on HTTPS443, and the
bounded ASCII `/mumbai/<identifier>/index.m3u8` path. Credentials, query,
fragment, encoded path variants, other hosts/ports and non-HLS routes fail.
The required public headers are exactly the advertised FanCode Referer and
ReactNativeVideo User-Agent. Additional/ambiguous headers are rejected.

Delivery uses the existing guarded native relay, retaining scoped headers and
signed child-playlist queries. LocalStreamProxy, the player and its transport
policy are unchanged. No new port, redirect exemption, origin profile or
rotating-playlist profile is introduced. Public DNS preflight is not address
pinning or complete rebinding protection. Source labels remain CS1, CS2, etc.

Independent review found a headerless same-origin wrapper could hide an HTTP
port2122 target. A reproduced red test admitted three entries instead of two.
The fix validates any wrapped target, including case/encoded API paths and
case-insensitive/duplicate URL parameters. HTTP2122 remains blocked. Only the
existing bound HTTPS8443 exception is retained; it is not expanded.

## Verification

- Fresh focused simulator-free Catalyst run: **144 passed, zero failures or
  skips**, CommunitySportsAddonTests and LocalStreamProxyTests. Eight new tests
  cover this route/header contract, guarded CDN playlist rewriting, signed-query
  preservation, sibling isolation/opaque identity and rejected wrapper variants.
- 32 native-membership tooling tests pass. Membership/version and scoped diff
  checks pass. All42 FPL and three multistream-specific file hashes match the
  task baseline. This is not a new full-suite or broad device qualification.
- Final signed iOS Release passes with an empty diagnostic log. Strict signature
  verification, app+extension167, source comparison, Jet installation/readback
  and launch pass. No archive/IPA is created.
- The Catalyst build-for-testing host emitted the previously observed zero-exit
  SwiftCompile diagnostic and existing Sendable warnings; the fresh144 tests
  actually execute and pass. No warning-free test-host claim is made.
- Jet Air4/iPadOS27.0.1 currently shows Fotty, but Device Hub remote touch/Home
  commands did not take effect. One screen-sharing reconnect and one clean app
  relaunch did not restore input. Keyboard capture was returned to off. No
  source request/decoded-playback pass is claimed from these attempts; the owner
  was asked to open the current exact cricket fixture's Check streams action.
- Final device preference readback contains no167 quality attempt. Source
  opt-in, appearance, interests-filter and sports-sync settings match the
  pre-install baseline. No FPL identifiers or stream URLs are retained here.

CS decoded playback is still OPEN until the installed167 route is exercised.
The prior165 accepted fullscreen/Pause/PiP loops were not repeated. FPL and
multistream were neither changed nor physically tested.

## Final-r3 source receipt

1123 frozen inputs compare before installation and after installation, before
documentation-only closeout changes. The temporary history-free capture does
not modify the real repository index, refs or remotes.

- Source SHA256: `f686464c7b77552c1583b3892606c6d207392cfa5f0ead064f3e9c00f1a642a3`
- Temporary snapshot commit: `26e9c393a639405c9da8a94cdefff94b016bbba6`
- Temporary bundle SHA256: `952b89569d295524098f22e4beeeff71ffcca57f6c29fa2c10a8bce57fa01b95`
- Signed executable SHA256: `59c85bee0b6371bb1acbe366098ab4b816e86ceb80c253f2b174b552c6bf7652`

## Resources

One reused temporary build directory, sequential jobs2, no simulators. The owned
1.1GiB gate, including build/test/source captures and copied device preferences,
was removed and its scoped awake helper stopped. Final free space is16GiB.
Only compact receipts remain; pre-existing artifacts and caches are untouched.
