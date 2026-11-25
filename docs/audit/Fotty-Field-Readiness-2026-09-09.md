# Private field-readiness foundations

9 September 2026. Source-only follow-up to internal TestFlight 2.0.0 (93).
No new build number, install, upload, remote publication, backend change, tester
change, paid service or automatic analytics.

## Delivered locally

### Recoverable source

`tools/release_source_snapshot.py` captures Git-visible working source into an
independent one-commit bundle, preserving untracked source and executable modes
without the active checkout's old history. It refuses credential-shaped files,
symlinks, unresolved merges, non-file Git entries, oversized inputs, overwrite
and concurrent source changes. Limits: 32 MiB per file and 256 MiB total source.
Gitleaks scans the copied source and a fresh restore; receipt checks cover file
hashes, modes, commit and bundle hash. `compare` additionally rejects working-tree
drift before a future upload. Source index/refs are not changed.

The retained 17 MB, 645-file build-93 recovery copy is **post-release** evidence,
not proof of the exact original archive inputs. It predates the app changes
below. [Source recovery](../operations/SOURCE-RECOVERY.md) records hashes,
restore procedure and exclusions. An off-Mac copy still needs the owner's
destination and subsequent verification; a second copy on this Mac cannot
protect against losing the Mac.

### Useful opt-in performance evidence

`FottyPerformanceStore` in `FottyLogger.swift` owns the latest two small scalar
summaries, not raw MetricKit payloads. `FottyMetricSubscriber` supplies reporting
windows, receipt dates, Apple's reported build and mixed-version indication.
One summary carries scrolling hitch ratio; the other carries reported hang
count and longest duration. A diagnostic object's count is not a census of all
hangs experienced by every user. Unknown build stays unknown; missing data is
`not_available`, never an invented zero or a smoothness pass.

The existing quality export includes these summaries. Feedback keeps its
off-by-default diagnostic toggle, preview, copy/share and truthful not-sent
behavior. No new Home message or top-level control was added. Data is local,
bounded to two <=2 KiB summaries and pruned after 14 days; the existing 250-event
quality limit is unchanged. Clearing history removes both kinds of evidence and
rejects subsequently delivered windows from before the clear. Invalid, corrupt,
future, too-old or out-of-order data cannot replace usable recent evidence.
Unattributed legacy performance scalars are discarded, not relabeled as build 93.

The implementation was checked against the public Xcode 26.6 MetricKit headers
and Apple's current [metric payload documentation](https://developer.apple.com/documentation/metrickit/mxmetricpayload).
Reporting windows can span app versions. Apple's [scroll hitch metric](https://developer.apple.com/documentation/metrickit/mxanimationmetric/scrollhitchtimeratio)
is specifically a scrolling measure, not a guarantee about every animation or
video frame. Preserve its raw scalar without inventing a percentage conversion.
No physical Apple payload was received or exported during this automated gate.

### Independent testing and report receipt

[Build 93 qualification](../beta/BUILD-93-QUALIFICATION.md) provides exact-build
entry gates, five uncoached tasks, participant aliases, seven-day evidence and a
feedback receipt/triage/retest chain. Existing build-45 evidence is untouched.
The new local export cannot be tested on 93; it awaits a separately authorized
future candidate. No tester was contacted, no report marked received and no
acceptance check was fabricated while preparing the ledger.

## Verification

- Eight isolated Python recovery tests pass, including real Git bundle restore,
  corruption, no-overwrite, input exclusions, source-race cleanup and pre-upload
  drift comparison. Tests mock secret scanning; the retained real snapshot
  separately passed actual Gitleaks 8.30.1 scans and a second fresh verification.
- Full `tools/ios-ci.sh` on public Xcode 26.6 (17F113): generated catalog drift
  and five provider identity vectors pass; **546 Catalyst unit tests pass,
  zero failures, two opt-in live/soak tests skipped**; generic unsigned iOS
  Release compiles. Eight new tests cover timing/build attribution, unavailable
  data, invalid/corrupt/out-of-order payloads, bounds/expiry, clearing and consent.
- Existing missing Metal-toolchain search-path linker warnings remain; no new
  warning correction or playback change is claimed.
- `git diff --check` passes. No simulator or physical UI test runner was used.
- One owned 953 MB gate root was trap-cleaned, including DerivedData, results and
  logs. Free disk space remained approximately 48 GiB. The 17 MB recovery bundle
  remains deliberately; unrelated artifacts/caches and device data are untouched.

## Still open

Off-Mac recovery; exact build-93 TestFlight iPhone/iPad acceptance and real
backup/restore; live/PiP/accessibility/long-session evidence; current deployed
Worker identity; independent daily use and a verified received report. The
known youth/UCL listing-label issue requires separate triage. This foundation
does not certify Coach advice, all providers, every screen or public readiness.

## Follow-up: off-Mac source recovery closed — 2026-09-09

After explicit owner approval, `jetboss/fotty-recovery` was created Private with
Actions disabled. The unchanged 93 bundle/receipt and restoration instructions
were uploaded, downloaded into a fresh checkout and independently restored.
All 645 files/modes/hashes match and Gitleaks passes. The owned 70 MB staging
root was removed. See [source recovery](../operations/SOURCE-RECOVERY.md).
This closes the off-Mac source-copy gap above for that snapshot only. It does
not back up subsequent field-feedback source changes or run automatic backups;
the other physical/independent acceptance gaps remain open.
