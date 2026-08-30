# Project Memory Playbook

Use this when changing project memory, agent instructions, or the generated NotebookLM source.

## Read first

- `AGENTS.md`
- `agent/AGENT-START.md`
- `agent/AGENTS.md`
- `agent/OPERATOR.md`
- `.cursor/rules/private-knowledge-base.mdc`
- `tools/notebooklm-refresh.sh`
- `tools/agent-start.sh`
- `tools/agent-finish.sh`

## Standing decisions

- Durable memory is Markdown in this repository.
- `docs/notebooklm/Fotty-NotebookLM-Source.md` is the generated sharing bundle.
- Local source files are authoritative; no remote semantic index or homelab is required.
- Current architecture files outrank historical entries when they conflict.
- Memory generation must redact secrets and private URLs.

## Verification

- Run `bash -n tools/*.sh` for touched shell scripts.
- Run `./tools/notebooklm-refresh.sh`.
- Run `./tools/brain-doctor.sh`.
- Run `./tools/ask-brain.sh "What is the current Fotty product graph?"`.
