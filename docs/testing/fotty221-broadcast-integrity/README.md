# Build 221: broadcast isolation, Watch availability and playback recovery

Private test target: Jet iPad. Evidence below distinguishes a controlled outage, actual playback and production activation.

| User action or failure | Required behavior | Acceptance evidence |
|---|---|---|
| One bad row or one provider exhausting registry capacity | Keep unrelated valid fixtures and fresh TV associations; quarantine ambiguous IDs, protect leases and charge the original request budget. | Controlled Worker collection with real production modules and bounded fake upstreams. |
| An enabled source times out after advertising a current match | Keep Watch available only for the original listing lifetime. Do not reuse expired URLs. A definitive withdrawal, changed fixture or disabled source still vetoes. | Native policy, index and registry tests. |
| A registered source supplies a short-lived URL | Match the exact advertised source ID, validate at completion and enforce declared media expiry independently of metadata freshness. | Registered StreamViX resolver, Flix adapter and collection tests; no arbitrary URL or origin exception. |
| Startup stalls or pauses before a visible frame | Retain one owner through first display; a deliberate pause or terminal failure cannot be undone by a network callback. Only a fresh, admitted alternative may take over. | Native ownership, late discovery and pause/restore regressions. |
| Tap Watch from the Home spotlight or a match row | Acknowledge the tapped match immediately. A local Watch ID joins discovery, player attempts, failures and fallback. A rendered start and a 90-second advancing hold are separate facts. | Coordinator, quality-store and named physical checks. Correct programme requires a separate visual observation. |

No claims of league-wide availability follow from a passing test, a provider catalog count or a single working channel.

## November 2 programme and failover qualification

The private Jet test starts from an official fixture’s Watch action. A current TV programme assignment can add an option; a stale TV assignment, replay or station without a guide cannot. A successful native start proves only that a picture was rendered. Inspect the pictures separately for the teams and programme. Media-clock age is not a live-event delay measurement.

For the controlled outage, hold the primary for 90 seconds, keep that exact delivery unavailable at the AV item boundary, then require an automatically selected, distinct delivery for the same fixture to hold for another 90 seconds. Verify the correct programme before and after. Two deliveries from one publisher establish route recovery only. The separate real Pause/Play check requires a stopped clock and return to advancing video on the original player, item and attempt. Private controls are scoped to one fixture, excluded from ordinary builds, and do not record simulated failures as owner history.

On November 2 in Tobago, Jet reproduced a CS discovery failure on two live NHL fixtures: their original pregame identifiers redirected to newly advertised live identifiers. The corrected registered path verifies the original parent, a unique fresh catalog match and the replacement's own metadata before requesting playback. The redacted [qualification receipt](acceptance.json) distinguishes resolver tests, actual scoreboard pictures, source-level failures, test-runner interruption and a real controlled outage. One CS delivery replacing another is not evidence of independent publisher coverage. The picker now distinguishes recommended choices from the complete inventory.

On the final private package, the measured transport check passed from normal Watch on Florida–Detroit: a deliberate Pause stopped the media clock and Play resumed on the same player, item and attempt. The rendered picker showed **1 recommended · 6 available** with a direct **Show all 6 sources** action. No team or stream identity was inferred from the player clock.

The final automated Detroit–Florida outage drill **passed**. CS1 advanced 90.879 seconds before the fault. With CS1 held unavailable, advancing CS2 video was measured within 12.34 seconds of the fault tap, and CS2 advanced another 90.851 seconds without a measured stall or owner replacement. Both pictures showed Detroit and Florida tied 1–1 with shots 5–12; the two broadcasts were out of sync. Boston’s earlier CS4 interruption is still recorded as a failed hold. Build 221 was returned to a normal launch on Jet. New Worker changes in this pass remain local; the previous PR120 deployment is separate.

## 3 November22:44Tobago — Named New Zealand–India ODI gate blocked

Reused the owner-installed normal3.0.0(230), not historical225/221; no install.
The original ICC schedule verified the senior firstODI at02:00UTC4November,
Play In Progress, first ball bowled, New Zealand34/1 after6.4overs. BCCI separately
reported the same live firstODI. Fotty's public cricket registry still serves
`scheduled` facts observed2November23:56UTC with last-known-good status. Its current
collection reports validation-or-runtime-failure (ICC consecutiveFailures6344).

The broadcast registry has a current dated CS firstODI row with01:30UTC coverage
start, observed02:10UTC, expiring06:10UTC. A second CS row is expired. Neither
establishes decoded media; there are zero registry links to the named ICC fixture.
Normal Jet Search shows Start unconfirmed / No stream listed and no Watch for the
firstODI; the other result is6November and must not substitute. A refresh was
attempted once, then uncommanded typing appeared. Keyboard capture was released
and device interaction stopped; no post-refresh acceptance is claimed.

No90s playback or independent-outage gate ran. This is a confirmed catalog/status
and association blockage, not a proven media failure. Diagnose the official
collector's validation/runtime failure and consequent association before another
playback gate; do not infer LIVE or attach the generic Willow channel. The bounded
one-match follow-up is being closed with this failed acceptance receipt, not
reported complete. Details in acceptance.json/laterNamedWindows.
