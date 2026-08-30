# Brain Ops Playbook

Use this when touching project memory, agent instructions, Cursor/Antigravity/Codex flow, Ollama, embeddings, or the homelab brain.

## Read First

- `AGENTS.md`
- `agent/AGENT-START.md`
- `agent/AGENTS.md`
- `agent/OPERATOR.md`
- `.cursor/rules/private-knowledge-base.mdc`
- `tools/brain/README.md`
- `tools/ask-brain.sh`
- `tools/private-kb-sync.sh`
- `tools/brain-doctor.sh`
- `tools/brain/query_brain.py`
- `tools/brain/embed_index.py`
- `server/brain_monitor.py`

## Standing Decisions

- Durable memory is markdown in this repo.
- Generated memory source is `docs/notebooklm/Fotty-NotebookLM-Source.md`.
- The remote semantic index lives at `tools/brain/.cache/knowledge.jsonl` on the homelab.
- Agents should consult the brain before architecture work, broad refactors, release checks, and unfamiliar debugging.
- Brain scripts must stay safe around secrets and private stream URLs.

## Common Failure Points

- Docs referring to commands that do not exist.
- The indexer looking for a different generated source filename than the generator writes.
- Local scripts updated but not pushed to the homelab.
- Agent rules becoming advisory prose without executable checks.
- Empty or stale indexes silently producing weak guidance.

## Verification

- Run `bash -n tools/*.sh` for touched shell scripts.
- Run `python3 -m py_compile tools/brain/*.py server/brain_monitor.py` for touched Python.
- Run `./tools/private-kb-sync.sh`.
- Run `./tools/brain-doctor.sh`.
- Ask a smoke question with `./tools/ask-brain.sh`.

## Brain Prompts

```bash
./tools/ask-brain.sh "What should agents read before working on Fotty?"
./tools/ask-brain.sh "What can make the Fotty Brain stale or misleading?"
```
