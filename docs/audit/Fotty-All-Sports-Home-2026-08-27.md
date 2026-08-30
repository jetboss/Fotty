# All-sports Home — implementation and acceptance

Date: 27 August 2026. Local, unreleased changes on the build-35 source baseline.

## Approved outcome

Implement the approved interactive Home concept: discover what is on across
sports without visiting each sport separately or turning Home into a long
schedule. Keep Fotty's name, amber identity and four existing tabs. The owner's
question about light mode is a recommendation request, not authorization for an
app-wide appearance conversion or a release upload.

## Implemented

- All sports is Home's initial filter. A compact adaptive selector shows up to
  five sports beside All sports, with current activity, next local start or a
  truthful channel/unknown-time label. More sports exposes every category and
  summarizes hidden current/upcoming activity; a selected overflow sport remains
  visible. Fixed tie-breakers prevent provider array order from shuffling tiles.
- Now & next contains at most three events in the live/listed-now or six-hour
  upcoming window. Different sports receive a first slot before repeat entries
  from one sport. Later today contains at most two remaining future fixtures;
  Coming up is the fallback when the next events fall on another local day.
- See all pushes a full date-grouped lineup on the same Home navigation stack.
  Sport and competition/cricket filters continue to work there. Matchday remains
  the personal saved/followed plan, not a duplicate global schedule.
- Rows have bounded, labeled Watch/Open broadcast/Details and bookmark actions,
  readable wrapping and large-text layout. Non-team events such as wrestling
  cards or race sessions do not acquire a synthetic “vs Away” opponent.
- No new API, model use, background source probes or playback-engine changes.
  All sports reuses the existing football score polling owner; other sport
  filters stop that owner as before. A minute-level local clock updates timing
  even when a catalog refresh fails.

## Data boundaries

`HomeSportsDiscovery` is a presentation projection, not a schema or canonical-ID
migration. It collapses identical IDs or exact sport/start/both-team-name matches,
preserving a real catalog ID and unioning real source descriptors. Different
starts, sports and unknown teams are not fuzzily merged. Provider aliases or
inconsistent names/times can still leave duplicates; this does not claim a
complete upstream identity reconciliation.

Known final/cancelled events leave Home. Current official football status takes
precedence over estimated windows. A source-backed event in its catalog window
says “On now · listed start”; this is not evidence of decoded media. Source-free
and unknown-format listings do not become live merely because a date elapsed.
Channels remain separate from fixtures and never add to an on-now count. CPL
snapshot rows show the checked date even on All sports. No fake scores or
unsupported score-unavailable labels are added.

## Light-mode recommendation

An optional light appearance is worthwhile for daytime browsing, alongside the
current dark appearance and a System option. It is not a one-line toggle:
`FottyApp`, `MainTabView`, several feature/sheet roots and the palette currently
force or assume dark styling. A proper follow-up should convert shared surface,
text, border and accent tokens; check Home, Matchday, every FPL workspace,
Settings, forms and sheets; and deliberately retain dark video/pitch surfaces
where useful. Contrast, large text and actual-device daylight checks belong in
that follow-up. This patch does not expose a nonfunctional appearance setting.

## Verification

The final unit suite passes **140 tests**, with zero failures/runtime warnings
and one intentionally opt-in HLS soak skipped (21:14 AST, final-source run).
All **eight selected Catalyst UI checks** pass in one sequential gate: Home
interaction, cricket discovery, first-use setup, element detection, hit regions,
text clipping, element descriptions and Dynamic Type. Sampled UI result bundles
still contain a main-thread responsiveness runtime warning, so those runs are
not claimed warning-free. Unsigned generic-device **Release** and
**ReviewSafeRelease** builds both pass with no compiler warnings or errors;
both built app plists still report `2.0.0 (35)`. These are compile gates, not
signed distribution artifacts or physical-device acceptance.
Initial source checks caught and corrected a Swift actor-isolation declaration.
The first interaction
check caught sport controls exposed as accessibility containers; native button
semantics were restored instead of weakening the test. Computer Use inspection
also exposed the real-catalog non-team-title fallback and American-football
display label; both were corrected.

The beta-Mac contrast analyzer repeatedly flagged the fixed-palette sport tile
labels, including near-white text. The actual failing Football-region capture
contained white text on a most-common background RGB of 20/23/26. Font/contrast
improvements were retained. A separate unit test verifies both actual tile
color branches, alpha-composited over the page background, plus the page's
primary/secondary/accent text and black-on-amber action pair at >=7:1. A trial
scoped audit exception exposed further flags, including a white section heading
on black and black Watch text on amber. **All newly added exceptions were
removed**; the original contrast/traits audit is not claimed clean. Its apparent
beta-Mac pixel-analysis problem remains a qualification limitation, and actual
iPhone/iPad contrast/daylight acceptance is still required. This is not evidence
of a light-mode pass.

Debug UI fixtures require both automated-testing and Home-specific flags, make
no production feed request and are not written to the catalog cache. Bookmark
interaction uses the existing isolated test preference suite. TestFlight and
physical acceptance remain separate from local Catalyst checks.

## Distribution and resources

Build 35 remains distributed. No version allocation, archive, upload, direct
device install, simulator, server deployment, tester change or Git publication
is part of this change. Preserve the clean-ancestry replay requirement.

One owned temporary gate directory and one DerivedData directory are reused
sequentially with two Xcode jobs. No permanent preview/build cache was
introduced. Cleanup removed the 1.6 GB owned gate tree and the remaining owned
Computer Use screenshots; the gate path was confirmed absent and the data
volume reported 40 GiB available. The durable record retains results, not media
copies.
