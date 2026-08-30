# Fotty Release Process

Fotty uses one public version and one monotonically increasing Apple build number across the app and Live Activity extension.

## Default distribution channel

The owner approved **phone-first validation for small scoped changes** on 2026-08-28. Run relevant regression tests, allocate a unique build number, and install only on the explicitly selected owner device. Preserve the app's data container; do not uninstall/reset it or install a device UI-test helper. These private builds are not uploaded to TestFlight. Never use simulators on this workstation.

Use **internal TestFlight for deliberately batched shared fixes and larger changes**, with the normal `Fotty` scheme and `Release` configuration. Small validated fixes still belong in the next shared release; urgent blocking/data-loss fixes may justify an earlier release. Direct-device acceptance does not certify the later TestFlight artifact. Do not change tester groups, notification settings or other devices as part of a phone-only request. This supersedes the former TestFlight-first rule for owner-approved small fixes.

Keep the existing internal group and tester access unchanged unless separately authorized. Uploading an internal beta is not approval for external testing, App Store submission, or Git publication. Fotty now has one product graph; do not add distribution-dependent labels, substitute feature implementations, or launch-time unlock gates.

`ExportOptions-TestFlightInternal.plist` uses automatic signing, uploads symbols, keeps the source-controlled build number, and marks the upload internal-only. It cannot later be promoted to external TestFlight or the App Store; that would require a separately authorized eligible build. The older `ExportOptions.plist` is for development export, not this workflow.

## Version rules

- `MAJOR.MINOR.PATCH` is the user-facing `MARKETING_VERSION`.
- `CURRENT_PROJECT_VERSION` is the integer build number.
- Patch: fixes only, such as `1.7.1`.
- Minor: user-visible features or meaningful redesigns, such as `1.8.0`.
- Major: a substantial product or compatibility reset, such as `2.0.0`.
- Increase the build number for every build distributed to a physical device for acceptance, TestFlight, or the App Store. Never reuse a distributed build number.
- CoreDevice's installation database sequence is not the Fotty build number.

Check the latest live App Store Connect build first; a local project number can lag an earlier upload. Then set both values together using the selected version and a strictly higher, unused build number:

```bash
./tools/set-version.sh <version> <next-build>
```

## Release lifecycle

1. Add intended changes under `CHANGELOG.md` → `Unreleased`.
2. Check App Store Connect, allocate the next unused build, and run `tools/set-version.sh`. Preserve the current marketing version while iterating the same beta release scope.
3. Run generated football catalog freshness plus `node tools/audit-provider-football-identity.mjs --live`, then the full unit/policy suites on Mac Catalyst and the relevant accessibility/interaction audits on an unlocked Mac. The metadata audit must reach at least one feed and find no unresolved top-flight marker/team pair; it never probes video. Record exact-source recent passing evidence when reusing it; a version-only change does not invalidate it. Run web/Worker tests and the production web build when their code or contract changed.
4. Compile the single generic-iOS Release configuration. Archive that same Release app for `generic/platform=iOS`, with automatic signing and two build jobs.
5. Verify the archive's app/extension versions, bundle identifiers, strict signatures, deployment targets, and production configuration. Validate/upload using `ExportOptions-TestFlightInternal.plist`; no direct device install is part of this step.
6. Distinguish upload accepted, Apple processing complete, and available to the existing internal group. Record the exact version/build and concise What to Test notes; do not call a processing build available.
7. The owner/testers update through TestFlight. Confirm Settings version/build, launch, persisted preferences, iPhone layout/keyboard/Display Zoom and iPad layout/rotation. Earlier direct-device acceptance does not certify a changed interface.
8. During an active independently decoded fixture, exercise startup, provider controls, audible unmute, source retry/switching, interruption, background/foreground and ad containment. Verify Picture in Picture/Live Activity where native handoff is proven.
9. Before widening the beta, confirm one report is actually received in TestFlight feedback and close task-blocking device regressions. Upload readiness and wider-beta acceptance are separate gates.
10. Record upload/distribution status and remaining checks in the changelog, release report and durable memory. Retain small release evidence, not duplicate app bundles. Remove the owned archive, export output and DerivedData after completion or failure, then check disk space.
11. Only when source publication is separately authorized, replay changes onto clean ancestry, review/test that snapshot, commit and tag. Never publish or tag this dirty old-ancestry checkout.

Use one owned temporary root for the entire archive/upload attempt, with an exit/interrupt cleanup trap. Do not create a DerivedData directory per configuration or device. Build sequentially with `-jobs 2`. Do not leave a large archive behind while waiting for account access; resolve sign-in before building. Upload symbols so TestFlight crash reporting can use them.

## Minimum internal-upload gates

- `git diff --check` passes for release-owned files.
- Generated football identity vectors and the current metadata-only provider drift audit pass.
- Normal Mac Catalyst build succeeds.
- Full playback, identity, FPL, Coach, notification, Live Activity, and quality policy tests pass; opt-in soak skips are stated explicitly.
- Web/Worker tests and the production web build pass when those surfaces/contracts changed; the deployed Worker revision is recorded when server code changed.
- Normal generic-iOS Release archive signs and passes Apple's upload validation, with matching app/extension versions.
- Internal-only export is explicit; the existing group's final build status is verified separately from upload success.
- The shared TestFlight release workflow uses no simulator, direct device installation or device UI-test helper. Phone-first private validation is a separate, explicitly scoped path.
- Release notes distinguish fresh evidence from outstanding physical-device checks. Use the previous known-good TestFlight build if the new one blocks a tester's core tasks.

## Acceptance before widening the beta

- The exact TestFlight build installs and launches on at least one supported physical iPhone and iPad, with Settings reporting the expected version/build on both.
- New/changed layouts, retained data, keyboard dismissal, accessibility and key football/FPL journeys pass on those devices.
- One clearly labeled test feedback report is received under the correct build; copying or sharing inside Fotty is not delivery proof.
- A provider-side failure window is recorded honestly but does not substitute for an independently decoded physical playback acceptance.
- `CHANGELOG.md`, Roadmap, Risks, Architecture Map, Project Memory, Decisions Log, and the completion report agree on the release scope and remaining limitations.

TestFlight builds expire after 90 days, and new uploads need Apple processing time. Keep automatic updates enabled in TestFlight where desired; this is a beta channel, not a permanent production distribution substitute. See Apple's [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview) and [internal testing guidance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).

## Credential-exposure response

Build 33's repository-security gate is complete. The tunnel credential was revoked by deleting its retired Cloudflare Tunnel, `cert.json` is deleted in the working tree and ignored, both affected advertised branches were rewritten and independently verified clean, and GitHub closed Support ticket `#4701297` after purging the retained pull-request objects. Independent API, web, PR-ref, and fresh-clone checks confirm that neither obsolete commit remains publicly reachable. Never print, copy into a ticket, or paste any value from the credential file.

### Verified scope and official procedure on 2026-08-26

- A fresh mirror identified two independent first-changed commits: `74c8b1627d24a8b8368b903fee83f8dda94d0a61` and `82f9cc431b5d5e078dd8f4cba4285ed4dfc8e237`.
- The affected advertised branches were `cursor/setup-dev-environment-29ac` and `cursor/docs-world-cup-readiness-audit`. The rewrite also changed retained `refs/pull/1/*` and `refs/pull/2/*`, which cannot be force-pushed by repository owners.
- `origin/main` and the repository's empty tag set do not contain the path and did not move.
- The JSON shape is a tunnel-specific, locally managed Cloudflare Tunnel credential, not the account-wide `cert.pem` certificate. Cloudflare documents tunnel credential files as tunnel-specific and non-expiring.
- The current working tree has hundreds of uncommitted release changes. It remains on the old local feature-branch commit by design; never push, merge, or rebase that tainted local branch back into the cleaned remote history.
- The current Cloudflare documentation still limits dashboard token rotation and forced connection cleanup to remotely managed tunnels. Because this locally managed tunnel was retired, deletion—not replacement—was the appropriate revocation path.
- The GitHub procedure requires credential revocation/rotation first, a reviewed `git-filter-repo` rewrite, collaborator coordination, and GitHub Support for cached or pull-request references.

### Revocation completed on 2026-08-26

- The owner confirmed that the homelab is retired and explicitly authorized removal of every Cloudflare Tunnel.
- The authenticated Cloudflare API reported one non-deleted tunnel across all four accessible accounts: `manga-api`, created 2026-01-21 and already down. It was deleted successfully; every account then reported zero active tunnels.
- A field-limited comparison confirmed that the historical `cert.json` Tunnel ID is the deleted tunnel's ID without printing or retaining its secret.
- The active Fotty playback/Coach Worker remained independent and returned HTTP 200 from `/health` after tunnel deletion. No Worker, zone, domain, or DNS record was modified.

### Advertised-history rewrite completed on 2026-08-26

- Pull requests 1 and 2 were closed before the rewrite. No issue, branch, tag, release, or default-branch deletion occurred.
- `git-filter-repo` 2.47.0 ran in a disposable mirror. The reviewed deterministic branch replacements were:
  - `cursor/docs-world-cup-readiness-audit`: `3855bd53c9dfc543832333924ee21db2175f11bc` → `5912bee72390315de2799d51073f9e72c27b4602`
  - `cursor/setup-dev-environment-29ac`: `74c8b1627d24a8b8368b903fee83f8dda94d0a61` → `8f67a85fe4de2ce3c8e0214f7d3738b7b7f208d8`
- Exactly those two branches were force-updated in one atomic push. `main` remained `c0a7d5b0fcb0b03125721101ba979cedf51062fb`; the empty tag-set fingerprint remained `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- A second fresh bare repository fetched only public heads and tags. Both `git log --all -- cert.json` and an exact-path `rev-list --objects --all` check returned no reachable path.
- The active workspace's two remote-tracking refs were refreshed without changing its branch, commit, or 373 dirty paths. All disposable rewrite and verification directories were deleted.
- A disposable detached worktree based on the cleaned branch then replayed the complete intended release tree without old ancestry: 310 tracked changes and 120 Git-visible untracked files matched the source manifests and file contents exactly, `cert.json` was absent, and `git diff --check` passed. The worktree was removed, leaving the active checkout unchanged. Use this same Git-aware replay boundary for the eventual publish; do not merge the old branch.

### GitHub purge and verification completed on 2026-08-26

1. Pushes from the old local feature branch remained frozen while the dirty release work was preserved.
2. GitHub Support ticket `#4701297` was submitted on 2026-08-26 with repository `jetboss/Fotty`, affected PR count 2, both first-changed commit IDs, confirmation of no LFS objects, and the clean replacement heads. It contained no credential value. GitHub later closed the ticket and reported that the unreferenced commits were cleared.
3. Authenticated repository commit API calls now return `No commit found` for both obsolete IDs, their public commit pages return HTTP 404, and `refs/pull/1/{head,merge}` plus `refs/pull/2/{head,merge}` are absent.
4. A new bare fetch of public heads and tags contains neither obsolete commit nor `cert.json`. The two cleaned branch heads, `main`, and the empty tag-set fingerprint remain exactly as recorded above. Temporary verification directories were deleted.
5. The security incident and Fotty 2.0 release gate are closed. The active dirty checkout intentionally remains on old ancestry; this completion does not authorize pushing it. When source publication is approved, repeat the proven Git-aware replay onto the cleaned branch, inspect and commit there, rerun secret scans and `git diff --check`, then publish only the clean-ancestry commit. The already-green app binaries do not need rebuilding unless app source changes.

References: [GitHub sensitive-data removal](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository), [Cloudflare locally managed tunnel permissions](https://developers.cloudflare.com/tunnel/advanced/local-management/tunnel-permissions/), and [Cloudflare remotely managed token rotation](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens/).

## Branch and tag convention

- Development branches use `codex/<topic>` when a branch is needed.
- Release-preparation branches use `codex/release-MAJOR.MINOR.PATCH`.
- Accepted releases are tagged `vMAJOR.MINOR.PATCH`.
- A tag is created only after the exact tagged commit passes the release gates; do not tag a dirty or differently built snapshot.
