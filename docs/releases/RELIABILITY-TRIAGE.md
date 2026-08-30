# Small-beta reliability triage

Use alongside [the release process](../RELEASE-PROCESS.md). This is an operator
runbook, not authorization to alter accounts or roll back a healthy deployment.

## First classify the failure

1. Record date, app build, device/OS, task and the expected/actual outcome.
2. Distinguish app crash/control/hidden-audio failures from a provider that cannot
   supply video. A healthy catalog or available source count proves neither.
3. For scoring, capture the gameweek, official/provisional/unknown label and
   evidence time; do not assume a missing player row means zero minutes.
4. Use the smallest opt-in diagnostic export needed. Do not put prompts, manager
   IDs, media URLs, credentials or full broadcast recordings into shared notes.

## Client incident

- If a new build blocks a core task, stop recommending that build. Confirm the
  previous available build is usable for that task before asking a tester to
  select it in TestFlight. Do not delete the app or clear local plans to recover.
- App and Worker versions are independent. Installing an older app does not
  undo a Worker deployment; older app code also lacks newer safety fixes.
- Reproduce and add a focused regression before issuing another build. Allocate
  a new Apple build number; never overwrite a distributed version number.

## Worker incident

The build-43 rollout changes no Durable Object schema, binding or secret.
Current and previous revision IDs are recorded in
[the build-43 release record](Fotty-2.0.0-43.md).

Before a rollback, inspect the actual current deployment and verify that the
recorded previous revision is still the intended target. Never blindly roll
back a later deployment or claim that reverting code restores stored data.
Wrangler's installed `rollback --help` confirms this command shape:

```bash
# Read-only; run from web/workers/playback with the intended account/config.
npx --no-install wrangler deployments list

# Only after incident-specific authorization and target verification:
npx --no-install wrangler rollback <verified-previous-version-id> --message "<incident reason>"
```

Use the already installed Wrangler executable if the repository has no local
binary; do not download a new tool just to run this procedure.

Rolling back this particular patch also restores its known missing-data/request
defects. Prefer a tested narrow forward fix when possible. After any authorized
change, verify the active revision, health, invalid request behavior and a
zero-token scoring smoke; verify model usage only with a separately bounded,
consented model request. Record what changed and what remains unverified.

## Cost and provider maintenance

- Current per-install/IP and capacity request limits are abuse controls, not
  strong tester authentication or a daily/global monetary cap.
- A hard Coach budget, emergency disable and actual spend observation are the
  next operating-design task. No billing setting or new allowance was configured
  by build 43. The owner must choose the acceptable ceiling.
- Recheck CPL league schedule corrections before each in-season release.
  Never attach a channel to a fixture by league name alone.
- Keep Premier League score fallback quotas and cached restrictions intact.
  Do not retry paid feeds globally because one match lacks enrichment.
- Keep one temporary build root, sequential jobs and cleanup. Retain redacted
  evidence, not archives, duplicate apps or per-segment remote logging.
