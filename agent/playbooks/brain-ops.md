# Project Memory Playbook

Use this when changing project memory, agent instructions, or the generated NotebookLM source.

## Read first

- `AGENTS.md`
- `agent/AGENT-START.md`
- `docs/notebooklm/Current-State.md`
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

- Run `bash -n` separately for each touched shell script (multiple filenames to one bash invocation are arguments, not separate syntax checks).
- Run `./tools/notebooklm-refresh.sh`.
- Run `python3 -B -m unittest discover -s tools/tests -p 'test_memory_support.py'` for memory-tool changes.
- Run `./tools/brain-doctor.sh --export` after refreshing the bundle.
- Source checks and export freshness/privacy checks are distinct; neither verifies live app claims.
- Run `./tools/ask-brain.sh "What is the current Fotty product graph?"`.
