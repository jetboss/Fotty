# Agent instructions (Fotty)

The `agent/` directory contains onboarding and current playbooks. Durable product memory lives in `docs/notebooklm/`.

- **Start here:** `agent/AGENT-START.md`
- **Current operations:** `agent/OPERATOR.md`
- **Root instructions:** `AGENTS.md`
- **Memory rule:** `.cursor/rules/private-knowledge-base.mdc`

## Reliability standard

Before architecture work, broad refactors, release qualification, or unfamiliar debugging, run:

```bash
./tools/agent-start.sh "Describe the task"
```

Use current repository docs as the authority. The Android prototype, homelab, PocketBase, and P2P/AceStream paths are retired and must not be inferred from historical decision entries.

After significant work:

```bash
./tools/agent-finish.sh "Describe what changed"
```
