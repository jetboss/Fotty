# Source recovery and release traceability

Updated 2026-10-01. Local snapshots exist for shared111, owner112 and the
isolated native candidate113. The latest verified off-Mac copy is still build93.
Backups are manual; later working-tree changes are not automatically protected.

## Current local native candidate

`backups/release-source/2.0.1-113-candidate/` contains a verified pre-build
receipt assembled from owner112 plus ten reviewed native/config/test paths.
Its [candidate record](../releases/Fotty-2.0.1-113.md) records the source hashes,
qualification and separately deployed backend. The frozen source set is not
the entire dirty primary checkout and its older web/Worker source must not be
deployed as PR36. Restore into a new checkout and use explicit `--root` when
comparing. Do not overwrite the 111/112/113 receipts.

No new off-Mac upload occurred. Uploading and independently verifying this
current bundle in the approved private recovery repository remains a separate
authorized gate; a local receipt does not protect against losing this Mac.

## Verified private GitHub copy

Owner approved creating [jetboss/fotty-recovery](https://github.com/jetboss/fotty-recovery).
GitHub reports Private visibility and GitHub Actions disabled. The new repository
contains only a README with restore instructions and
`snapshots/2.0.0-93/{source.bundle,receipt.json}`. It has no active app workflows,
deployment configuration or inherited source history.

Recovery-repository commit: `f54a314dc03ea24eefd535b9455c9f26f275b64e`.
This outer storage commit is distinct from the source commit inside the bundle.
After upload, a fresh HTTPS clone from GitHub matched the original bundle and
receipt byte-for-byte; another disposable restore verified all 645 source files,
modes, source commit and hashes, and passed the real Gitleaks scan. Private
visibility and disabled Actions were checked again afterwards.

The owned 70 MB upload/download staging root was removed. The original 17 MB
local bundle remains intentionally. The development repository's origin,
index and history, TestFlight, devices and backend were not changed. No periodic
backup automation or new collaborator was configured. This verifies source
restoration, not a build on a replacement Mac or recovery of service credentials.

## Build-93 recovery record

`backups/release-source/2.0.0-93-recovery/` contains a 17 MB `source.bundle`
and `receipt.json`. It was captured before the subsequent field-feedback app
edits, restored into a disposable checkout, compared file-for-file, and scanned
with Gitleaks 8.30.1 before and after restore. The disposable copies were removed.
The retained bundle is an intentional recovery artifact, not a build cache.

- Files: 645 Git-visible working-tree files, including untracked source, current
  edits and executable modes; working-tree deletions remain deleted.
- One independent root commit: `38dfbef60fd6ef3f0f55d8aabbcc773a3890fd2d`.
- Source manifest SHA-256: `b91442774bfc18d057260637ebb70f3dbe8b9072059d418fff4c3931613ad930`.
- Bundle SHA-256: `914a1754055b36bc6a37e26ba1f909d1a6945b5c7e095822e0d35a07ec06d84d`.
- Purpose: `post-release-recovery`. The snapshot also contains the initial
  recovery tooling. No pre-archive source receipt exists for the uploaded 93
  binary, so this is **not proof of its exact historical build inputs**.

The active checkout/index/refs were not changed. The old Git ancestry is not in
the bundle and must not be pushed from this checkout. Do not overwrite this
snapshot with newer app source or claim a later capture is the original release.

## Verify and restore

From the existing checkout, verify without changing it:

```sh
python3 -B tools/release_source_snapshot.py verify backups/release-source/2.0.0-93-recovery
```

For recovery, clone `source.bundle` into a **new, empty directory**, never over
the working project. The `verify` command already performs this restore in a
temporary directory and checks the receipt, one-commit history, file hashes,
modes and secret scan. Preserve the receipt alongside any authorized off-Mac copy;
compare its two SHA-256 values with this independently retained record.

This is source recovery, not a backup of signing credentials, API secrets,
tester/FPL data, ignored inputs or the production Worker configuration. Recover
authorized Xcode signing and service credentials separately. Secret scanning is
defense in depth, not permission to publish private code. On a replacement Mac,
install Git, Python 3, Gitleaks, the recorded public Xcode and project tools, then
run the simulator-free gates before considering any distribution.

## Future release procedure

1. Finish source changes and allocate the next unused app/widget build together.
2. Capture with `python3 -B tools/release_source_snapshot.py capture --label <version-build>
   --purpose pre-build --output backups/release-source/<version-build>`.
   Ignored/generated files needed to build must first be accounted for; this
   tool only covers Git-visible source. Keep secrets out of the source set.
3. Run qualification and archive without source edits. Before upload, run
   `python3 -B tools/release_source_snapshot.py compare backups/release-source/<version-build>`.
   It verifies the saved bundle and rejects additions, edits, deletions or mode
   changes in the current source. Logs and ignored build output are not inputs.
4. Record the receipt hashes, public Xcode version, app executable hash, test
   results and deployed Worker source version in the release note. Add that
   evidence **after** the pre-upload comparison, keeping the source receipt
   immutable. A passing comparison is not a substitute for binary validation.
5. Copy the bundle/receipt to the owner-approved private off-Mac destination and
   verify there. Keep the current and previous qualified recovery copies; retire
   older copies only after explicit, exact-target owner approval.

The private recovery repository is now the owner-approved off-Mac destination.
Future snapshots still require explicit capture/upload; this is not continuous
sync. Recurring automation remains a separate decision. The saved 93 bundle
does not include the subsequent local performance-feedback work.
