# Agent onboarding — current local project memory

Read this before architecture work, broad refactors, release planning, or unfamiliar debugging.

## Durable sources

| File | Purpose |
|---|---|
| `docs/notebooklm/Project-Memory.md` | Product direction, current state, and non-negotiable decisions. |
| `docs/notebooklm/Architecture-Map.md` | Active module and data-flow ownership. |
| `docs/notebooklm/Decisions-Log.md` | Newest-first technical and product decisions. |
| `docs/notebooklm/Risks.md` | Known sharp edges and guardrails. |
| `docs/notebooklm/QA-Playbook.md` | Regression and physical-device acceptance checks. |
| `docs/notebooklm/Workflow.md` | Team implementation and release process. |
| `agent/OPERATOR.md` | Current deployment and service boundaries. |

`docs/notebooklm/Fotty-NotebookLM-Source.md` is generated. Do not hand-edit it.

Never put secrets, private stream URLs, signing material, or production tokens in project memory.

## Start and finish

From the repository root:

```bash
./tools/agent-start.sh "Describe the task"
```

After significant work:

```bash
./tools/agent-finish.sh "Describe what changed"
```

These commands use only the local repository. The homelab and remote embedding index are retired.

## Retired paths

Do not restore or rely on the Android prototype, homelab, PocketBase account sync, AceStream/P2P services, Tailscale deployment, or Cloudflare Tunnels. Historical references in the decision log are context, not instructions.
