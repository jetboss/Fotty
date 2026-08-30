# Agent onboarding — private vault & local brain

Read this **before** writing “project memory” or answering architecture questions. This repo uses a **self-hosted Knowledge Base** powered by the Homelab GPU (**NVIDIA 3050 Ti**).

All **agent + homelab onboarding** for this repo lives under **`agent/`** (next to `Fotty/`, `docs/`, etc.)—not under `docs/notebooklm/`.

## 1. Where to **store** durable info (“upload”)

There is no separate upload service. **Storage = markdown in this repo** (committed like any code).

| File | Put here |
|------|-----------|
| `docs/notebooklm/Project-Memory.md` | North star: what the app is, pillars, risks. |
| `docs/notebooklm/Architecture-Map.md` | Where things live in the tree; navigation for agents. |
| `docs/notebooklm/Decisions-Log.md` | Newest-first fixes/decisions (short entries). |
| `docs/notebooklm/QA-Playbook.md` | Regression / smoke expectations. |
| `docs/notebooklm/Workflow.md` | Human–AI loop for the team. |
| `docs/notebooklm/Risks.md` | Known sharp edges, guardrails, and verification checks. |
| `agent/OPERATOR.md` | Homelab: Ollama, Tailscale, Docker Compose (for operators). |

After edits, **`docs/notebooklm/Fotty-NotebookLM-Source.md`** is **generated** — do not hand-edit; run the refresh script (below).

**Never** put API keys, tokens, private stream URLs, or production secrets in these files.

## 2. After you change project memory — refresh the bundle

From the **repo root**:

```bash
./tools/notebooklm-refresh.sh
```

This regenerates **`docs/notebooklm/Fotty-NotebookLM-Source.md`** (redacted snapshot + git info).

## 3. Refresh the **semantic index** (needs Homelab Ollama)

When an agent needs **fuzzy “what did we say about X?”** via CLI, the embeddings must be current.

Use the canonical sync command from the repo root:

```bash
./tools/private-kb-sync.sh
```

This refreshes the generated NotebookLM bundle, pushes safe memory docs to the Homelab, and rebuilds embeddings with `nomic-embed-text` on the **NVIDIA 3050 Ti**.

Before a major task, verify the brain is available:

```bash
./tools/agent-start.sh "Describe the task"
```

## 4. Query the index

```bash
./tools/ask-brain.sh "Your question"
```

For local/manual query work, the lower-level command is:

```bash
export OLLAMA_HOST=http://homelab:11434
python3 tools/brain/query_brain.py "Your question" --synthesize
```

## 5. Repo maintenance standard

Meaningful code passes: bump version as required, append **`Decisions-Log.md`**, update **`Project-Memory.md`** if pillars/risks shift, run **`./tools/private-kb-sync.sh`**, then verify with **`./tools/brain-doctor.sh`**.

For guided completion, run:

```bash
./tools/agent-finish.sh "Describe what changed"
```

## 6. Quick links

- Networking / Tailscale / WebUI (human): **`agent/OPERATOR.md`**
- Index / Antigravity entry: **`agent/AGENTS.md`**
- Cursor always-on rule: **`.cursor/rules/private-knowledge-base.mdc`**
