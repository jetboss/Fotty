# PlavioLive delivery and registry repair — 4 November 2026

Normal signed Release 241 is installed on Jet iPad. Settings visibly confirmed v3.0.0 (241); Home loaded normally. AS was visibly already enabled alongside the existing sources; no switches were changed. No newly qualified live football or cricket delivery is claimed.

## Changes

- Preserved AS identity/settings while moving its fixed metadata origin and manifest identity to PlavioLive.
- Explicitly dated CNC cricket records can associate with exactly one fresh official ODI/T20 fixture, with identical teams, squads and UTC start. The source does not gain invented format/ordinal facts. Test matches remain excluded from this narrow new association.
- Native AS cricket resolution retains the existing reviewed FanCode HTTPS path and exact public Referer/User-Agent contract, fresh same-ID metadata and guarded relay. Cookie/arbitrary headers, HTTP, unrelated paths/origins and ambiguous fixtures remain rejected.
- Required headers participate in delivery identity. Existing empty-header source identity is unchanged.

## Validation and publication

- 103 native Plavio tests passed; one physical-only case skipped on Catalyst. Release iOS compile passed.
- 148 canonical focused checks passed; 129 isolated publication checks passed. Both Worker bundle checks passed.
- Initial PR CI exposed old runtime mock origin/identity fixtures. Those were corrected; all 16 actual runtime tests then passed and all GitHub checks passed. The first failed run was not represented as a pass.
- PR126 merged through protected checks as 57b4dc72ac9df809adf6fbcfa831dbf4d126ea4f: https://github.com/jetboss/Fotty/pull/126
- Both Workers deployed from that exact protected revision as 2026-11-04.plaviolive-1. Wrangler configurations were byte-identical to the prior protected baseline. Original watchdog activation was explicitly retained with keep-vars; all 155 notices and fixture activation flags retained. For the first migration deployment, real later collector completion was verified at 2026-11-05T02:00:59.511Z. Final revision2 retains all159 notices now present, original activation, flags and matching revisions; its next later normal collector completion is still pending (last completion02:15:59UTC precedes the second deploy). See deployment-verification-final.json. Email remains off; owner chat alerts remain paused/dashboard-only.
- The optional local TOML fingerprint helper could not run because the system Python lacks tomllib. Direct protected configuration equality and live before/after invariant checks were used instead; this was not a fingerprint-helper pass.

## Live gates still open

At 02:10:04 UTC the normal AS collector recovered without state reset: 117 current records, including14 dated rows and3 listed fixture links. See registry-refresh.json. This is discovery recovery, not decoded media proof.

The real refresh exposed a residual WBBL rejection: its official receipt was12minutes old and the new exact-CNC branch mistakenly imposed a separate10minute limit. The existing normalizer admits exact scheduled fixtures for24hours and live fixtures for30minutes, with expiry tied to the original receipt. PR127/cd5edb9 removes only that extra restriction and keeps all existing normalization/expiry, identity, uniqueness and Test/day guards. Regression assertions cover valid scheduled cadence, non-renewal of live expiry and expired official rejection.179 focused checks and both bundles passed, all protected CI passed. The fresh Adelaide–Brisbane sample joins locally as listed; public post-deploy result at02:16:46UTC confirms both Adelaide–Brisbane and SydneyThunder–Perth listed. Conflicting same-pair times remain conflicting, and the untyped Bangladesh–WestIndies Test listing still needs verification. See registry-final.json.

Current cricket entries are upcoming. Bangladesh–West Indies starts 03:30 UTC but is a Test, outside the new limited-overs CNC rule. Adelaide Strikers Women–Brisbane Heat Women starts 04:40 UTC. Its sampled advertised FanCode path returned HTTP404 before kickoff; Tapmad returned403. Neither is decoded playback proof or evidence of a permanent availability failure. Tapmad admission was not added.

The current Brazilian football examples crossed a UTC date boundary while AS supplied an undocumented site-time civil date. That mismatch remains unresolved; no guessed timezone, shifted date or ended UEFA fixture was used to pass playback. Recheck fresh eligible official fixtures and matching original provider metadata in the actual live window, then normal Watch selection and advancing correct-programme video on Jet.

## Other requested sources

Owner has no configured access for PenguPlay, Highfly or StreamNexus. PenguPlay public manifest has no catalogs; Highfly free configuration requires human Turnstile verification; StreamNexus requires a paid/trial token. These remain access-gated, not playback failures or working additions. No signup, payment, message, token invention or challenge bypass occurred. See the prior240 receipt for primary source links.

Phone, FPL, multi-stream and TestFlight were untouched. Jet source preferences/private data were preserved. No additional source was enabled merely because its metadata/URL exists.

Owned temporary build products, logs and publication worktree were removed after installation/deployment checks; free disk recovered to about27GiB. No media/token/private-device material retained in receipts.
