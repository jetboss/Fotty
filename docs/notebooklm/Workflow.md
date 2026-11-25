# Fotty Workflow

## Human–AI loop

Apply the loop only through the stage requested. Discussion and read-only audits
stop at evidence-backed findings. Source-only fixes stop after relevant local
verification. Owner-device installs and shared releases are separate requested
gates; a generic request to finish is not publication authority.

Within an explicitly approved repair and named owner-device gate, carry known
fixes through local verification, rebuilding, installation and testing without
repeat approval. Preserve the approved target and scope. Pause for a material
new UX/architecture, cost, privacy/security or destructive-data decision, new
distribution target, or missing access that the agent cannot safely resolve.
Requesting an unlock is operational access, not renewed permission. Shared
publication and TestFlight remain separately authorized. Owner clarification:
2026-10-03.

1. **Identify**: Capture the user-visible problem and the acceptance behavior.
2. **Inspect**: Read Current-State.md, retrieve relevant topic sections, and trace current source.
3. **Implement**: Change the smallest authoritative layer; remove obsolete alternatives instead of maintaining parallel behavior.
4. **Verify**: Run focused tests, then the relevant full gate. Never use a simulator on this Mac.
5. **Publish when requested**: Use a protected pull request for shared changes. Use TestFlight for tester-facing releases.
6. **Record**: Update durable memory and refresh the generated NotebookLM source.

## Immutable source receipt for distribution

Every TestFlight or other shared binary must have a source receipt captured
before its archive is built. This applies even when the working tree is dirty:

```bash
python3 -B tools/release_source_snapshot.py capture \
  --output backups/release-source/<version-build> \
  --label <version-build> --purpose pre-build
```

Record the generated `receipt.json` commit and source SHA-256 with the build.
Immediately before upload, prove that the working source still matches it:

```bash
python3 -B tools/release_source_snapshot.py compare \
  backups/release-source/<version-build>
```

An archive without both a verified pre-build receipt and the pre-upload compare
is not a distribution candidate. A later recovery capture cannot establish the
source of an already-built binary.

## Required gates

Before merge:

- [ ] Focused regression covers the reported failure.
- [ ] Web changes pass unit, TypeScript, lint, Worker, and build checks.
- [ ] iOS changes pass provider identity, Catalyst units, and generic unsigned Release.
- [ ] Native Swift sources match the explicit Xcode target membership; run `python3 -B tools/check_native_source_membership.py` after file moves.
- [ ] Workflow changes pass actionlint and gitleaks.
- [ ] Temporary Xcode output is removed and disk space is checked.
- [ ] Physical-only behavior is explicitly left open until exercised on a connected device.

For documentation and memory-tool-only changes, run the affected offline tests,
shell syntax/reference checks and export checks; do not invoke Xcode, Worker
deployment or TestFlight. Keep the full gates above for affected production code.

## Agent handoff

All agents read `agent/AGENT-START.md` and `docs/notebooklm/Current-State.md`
before broad work. After significant implementation, prepend a dated decision
(newest first), update the current summary in place if needed, then:

```bash
./tools/agent-finish.sh "Describe what changed"
```

This refreshes the local documentation bundle; it does not contact the retired homelab.
