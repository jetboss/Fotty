# Premier League membership and fixture filtering — 29 August 2026

Status: implemented and automatically qualified locally on top of private iPhone
build 44. No device installation, TestFlight upload or service deployment.

## Verified league state

The official Premier League's 2026/27 club guide lists Coventry City, Hull City
and Ipswich Town as promoted members. Coventry is therefore valid in the current
Premier League filter. Norwich City is not one of the 20 clubs. Burnley, West
Ham United and Wolverhampton Wanderers were relegated after 2025/26.

Primary source checked 29 August 2026:
`https://www.premierleague.com/en/news/4365156/new-to-the-premier-league-heres-all-you-need-to-know`.

## Root cause and correction

Home's catalog fallback used an older Premier League alias list and its
supposed team-pair check actually accepted either team. A Norwich fixture could
therefore enter the Premier League tab merely because its opponent appeared in
that stale list. Other club/news fallback lists had independently drifted.

- One season-labelled 20-club catalog now supplies fixture membership, club
  browsing/bootstrap and Premier League news inference.
- Roster inference requires both teams to be current senior clubs. Historic,
  youth, women's and reserve identity does not imply current senior membership.
- An explicit provider Premier League label cannot override a club-membership
  conflict. Cup, Championship, lower-division, friendly, Europa and Conference
  markers are not inferred as Premier League fixtures even when both clubs are
  current members. Explicit Champions League identity retains precedence.
- Other league roster fallbacks now also require both sides instead of one.

Norwich remains visible under All Football when its broadcast is legitimately
listed; this correction prevents it being mislabeled as a Premier League game.

## Verification and boundaries

Focused `PlaybackPolicyTests`: 70 passed, one existing opt-in HLS soak skipped,
zero failures and zero runtime warnings. New cases cover the exact official 20,
Coventry inclusion, Norwich and former-member exclusion, youth rejection,
provider-label conflict, FA Cup separation, Champions League precedence and
shared news inference. The final full Mac Catalyst unit suite passed 212, with
the same one opt-in soak skipped, zero failures and zero runtime warnings. Both
generic iOS normal Release and `ReviewSafeRelease` compiled unsigned. No UI
layout changed, so no UI automation or physical-appearance result is claimed.

Final source/test/project fingerprint:
`b5bb53465cd1e80c372171972dbe2ee76a0446ccffe84e55012f5db9b0a78e9c`.

The catalog is intentionally season-labelled and must be checked after every
promotion/relegation cycle. This is a local deterministic correction, not a new
API, background updater or claim that provider competition labels are always
accurate. No simulator, physical UI-test helper, paid call or live stream probe.

One bounded DerivedData root was reused sequentially with two Xcode jobs and an
exit/interruption cleanup trap. No owned process remained. The trap removed the
entire 812 MB `FottyPLGate.6uIZNr` root, including apps, results and logs; its
absence was checked afterward. Free space was 56 GiB before and after the gate.
