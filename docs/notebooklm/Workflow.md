# Fotty Workflow

## Human–AI loop

1. **Identify**: Capture the user-visible problem and the acceptance behavior.
2. **Inspect**: Read the current project memory and trace the active product graph.
3. **Implement**: Change the smallest authoritative layer; remove obsolete alternatives instead of maintaining parallel behavior.
4. **Verify**: Run focused tests, then the relevant full gate. Never use a simulator on this Mac.
5. **Publish**: Use a protected pull request for shared changes. Use TestFlight for tester-facing releases.
6. **Record**: Update durable memory and refresh the generated NotebookLM source.

## Required gates

Before merge:

- [ ] Focused regression covers the reported failure.
- [ ] Web changes pass unit, TypeScript, lint, Worker, and build checks.
- [ ] iOS changes pass provider identity, Catalyst units, and generic unsigned Release.
- [ ] Workflow changes pass actionlint and gitleaks.
- [ ] Temporary Xcode output is removed and disk space is checked.
- [ ] Physical-only behavior is explicitly left open until exercised on a connected device.

## Agent handoff

All agents read `agent/AGENT-START.md` before broad work. After significant work:

```bash
./tools/agent-finish.sh "Describe what changed"
```

This refreshes the local documentation bundle; it does not contact the retired homelab.
