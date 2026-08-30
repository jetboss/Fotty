# Fotty NotebookLM Workspace

This folder contains safe project-memory documents meant to be uploaded into NotebookLM.

Use NotebookLM for:

- summarizing design and engineering decisions
- comparing iOS, web, Android, and server behavior
- turning logs and QA notes into action lists
- creating test checklists before device sessions
- keeping a running “what changed and why” memory

Do not upload:

- passwords
- API keys
- provider tokens
- full private stream URLs
- server credentials
- raw logs that contain secrets

Suggested NotebookLM sources:

1. `Fotty-NotebookLM-Source.md` after running `./tools/notebooklm-refresh.sh`
2. `Project-Memory.md`, `Decisions-Log.md`, `Risks.md`, or `QA-Playbook.md` only when a focused source is preferable
3. Redacted build/test logs when needed
4. Redacted screenshots with a short note describing what you expected vs. what happened

Good prompts to ask NotebookLM:

- “Summarize the current third-party playback architecture and list the highest-risk failure points.”
- “Turn the QA playbook into a 20-minute real-device test script.”
- “Compare the latest bug report against known remaining risks.”
- “Create a release-readiness checklist for the iOS app.”
- “What decisions should be added to the project memory after this test session?”
