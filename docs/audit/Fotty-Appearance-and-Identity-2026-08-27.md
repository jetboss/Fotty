# Appearance and sports identity

## Product contract

The owner likes the compact all-sports Home but rejected losing team badges and
recognisable sport artwork. Restore those details without returning to oversized
cards. Complete optional light appearance; dark remains the default. Keep Fotty's
name, four tabs, source-gated Watch actions and separate saved/followed Matchday.

## Implementation

- Home's new fixture rows now use the existing cached team badge component beside
  each name, including provider badges and the shared football/NBA/MLB catalog.
  Football schedule crests can enrich matching fixtures. Missing artwork retains
  named initials; channels and unpaired events do not acquire fake opponents.
- Badge images fit their entire artwork instead of cropping it. The component
  observes catalog updates so newly resolved badge URLs can replace initials.
- Shared equipment symbols identify football, basketball, baseball, cricket,
  tennis and other sports in activity tiles and native category menus. Icons are
  decorative for VoiceOver; the full sport/team labels remain the meaning.
- Settings → Preferences → Appearance stores Dark, Light or System. Unknown or
  absent preference values resolve to Dark; changing appearance does not rebuild
  the root navigation/FPL session with a new identity.
- Shared surfaces, text, borders, status colours and shadows adapt. Amber text
  becomes darker ink on light surfaces; gold filled actions retain dark text.
  Forms and FPL sheets no longer force Dark. Pitch artwork and video playback
  keep their intentional dark treatment without darkening the browsing screens.

## Verification

Build 37 passed 148 unit tests with one optional HLS soak skipped and no runtime
warnings. Both-mode text/button contrast, equipment-symbol availability and
Home rendering at iPad/narrow large-Type widths passed; the renderings were
visually inspected. The initial test compile lacked a locally scoped fixture
helper, and one old icon expectation needed updating to the equipment contract.
Normal Release, ReviewSafeRelease and signed normal Debug iOS builds passed.
One mistaken Review Safe scheme invocation was corrected to the existing Fotty
scheme plus ReviewSafeRelease configuration; its 28 KB error bundle was removed.

The strictly verified app and extension both report 2.0.0 (37). The normal app
was installed on the physical iPad Air 4 and independently reported as build 37.
Real-device light Home showed legible surfaces, equipment icons and football/
basketball badges. Real Settings confirmed light rendering but exposed an
unlabelled, poorly positioned menu; the owner explicitly rejected it. A capture
requested after launching FPL actually showed Home, so it is NOT FPL evidence.

## Build 38 follow-up — installed on iPad only

- The owner wants a dedicated Appearance screen, not a floating Light selector.
  Implemented a normal Settings row with the current value and three clearly
  labelled choice rows. Dark stays default. Removed Engineering from normal
  Settings even in Debug; the diagnostics implementation and Report a problem
  remain available to the appropriate development/support workflow.
- Physical Home still showed initials for Yankees/Astros. Inspection found that
  a sparse persisted cache replaced the bundled badge safety net, and the static
  fallback lacked most NBA/MLB teams. Merge valid cached URLs into the seed instead
  of replacing it. Extend the app's existing ESPN artwork fallback using current
  names and actual URLs from its [MLB catalog](https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams?limit=100)
  and [NBA catalog](https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams?limit=100),
  checked on 2026-08-27. There is no new runtime API subscription or catalog call.
- After discussion the owner approved equal sport tiles and more visible sports
  on iPad. A measured layout shares the tallest height and equal width across all
  rows, including partial rows. Titles reserve two lines; a scaled minimum width
  determines column capacity. iPad shows every sport without More sports, even
  in compact Split View; compact phones preserve their bounded overflow policy.

The current source and installed iPad are 38. These checks do not certify
centre/lower-left touch, theme switching/persistence through the new screen,
or FPL daylight/VoiceOver.

Final build-38 source passes 155 unit tests (one optional HLS skip), zero failures
or runtime warnings at 22:31 AST, plus whitespace checks. This includes sparse/
invalid badge-cache preservation, Appearance/no-Engineering, equal multirow
measurement, overflow policy and both-mode rendering. A nonblank snapshot check
caught UIKit-backed offscreen ScrollViews rendering only backgrounds on Catalyst;
the actual Appearance choices were extracted as a reusable component and their
nonblank light/dark renderings were inspected. Size-category renderings are not
proof of physical text scaling or interaction.

Normal Release, ReviewSafeRelease and signed Debug iOS builds passed. Strict app/
extension signatures and both build numbers were checked before install; CoreDevice
then independently reported 2.0.0 (38) on the iPad. Physical portrait Home shows
eight equal columns and the remaining sports in a second equal-height row, without
More sports, and actual Yankees/Astros badges. A requested Settings capture still
showed Home and is NOT Settings evidence. The captured masthead appears under the
status area; recheck scroll/safe-area state separately. An ordinary argument-free
launch passed a 20-second hold. See the build-38 record for the executable hash.

## Next interaction — discussion only

Open broadcast uses the same source lookup as Watch; the label differs by timing,
not verified availability. The owner prefers a small Starts in countdown with a
play affordance about two minutes before scheduled start, without a new screen
that merely repeats the time. Useful Match Center details can remain separate.
An empty lookup should have a truthful inline not-ready/retry state. No countdown
or routing change was implemented and no build 39 was produced during discussion.

## Resource handoff

Before pausing for the requested tile-layout discussion, the cleanup trap removed
the single 1.1 GB owned DerivedData/test/log/capture root. No app bundles, result
bundles or device screenshots from this gate remain in that temporary directory.
Free disk returned to 40 GiB. That was the earlier discussion checkpoint; the
approved build-38 gate reused one new bounded directory for all configurations.

The build-38 gate's 1.3 GB owned build/test/capture directory was subsequently
removed by its cleanup trap, confirmed absent, and free disk returned to 40 GiB.
No temporary artifacts are retained for the proposed countdown discussion.

Build 38 is now installed on Jet iPad. TestFlight remains build 35; no upload, tester access,
Git publication, paid API or server changes are part of this task. Builds reuse
one temporary root with two jobs; no simulator or physical-device UI-test helper.
