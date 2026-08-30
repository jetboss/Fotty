#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/docs/notebooklm"
OUT_FILE="$OUT_DIR/Fotty-NotebookLM-Source.md"

mkdir -p "$OUT_DIR"

redact() {
  sed -E \
    -e 's#(api_password=)[^&[:space:]]+#\1[REDACTED]#g' \
    -e 's#(password=)[^&[:space:]]+#\1[REDACTED]#gi' \
    -e 's#(token=)[^&[:space:]]+#\1[REDACTED]#gi' \
    -e 's#(api[_-]?key=)[^&[:space:]]+#\1[REDACTED]#gi' \
    -e 's#(Authorization: Bearer )[A-Za-z0-9._~+/-]+#\1[REDACTED]#gi' \
    -e 's#(Bearer )[A-Za-z0-9._~+/-]+#\1[REDACTED]#gi' \
    -e 's#(https?://[^/?#[:space:]]+)[^[:space:]]*#\1/[URL_REDACTED]#g'
}

section_file() {
  local title="$1"
  local file="$2"
  if [[ -f "$file" ]]; then
    {
      printf '\n\n# %s\n\n' "$title"
      redact < "$file"
    } >> "$OUT_FILE"
  fi
}

section_command() {
  local title="$1"
  shift
  {
    printf '\n\n# %s\n\n```text\n' "$title"
    (cd "$ROOT" && "$@" 2>&1 | redact || true)
    printf '\n```\n'
  } >> "$OUT_FILE"
}

cat > "$OUT_FILE" <<EOF
# Fotty NotebookLM Master Source

Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')

This file is generated from safe project-memory sources and redacted command output.
Upload this one file to NotebookLM when you want a fresh project snapshot.

Do not paste secrets into this file.

EOF

section_file "Project Memory" "$OUT_DIR/Project-Memory.md"
section_file "Architecture Map" "$OUT_DIR/Architecture-Map.md"
section_file "Decisions Log" "$OUT_DIR/Decisions-Log.md"
section_file "Risk Registry" "$OUT_DIR/Risks.md"
section_file "Workflow" "$OUT_DIR/Workflow.md"
section_file "QA Playbook" "$OUT_DIR/QA-Playbook.md"
section_file "iOS Manual Deploy Notes" "$ROOT/IOS_MANUAL_DEPLOY.md"
section_file "Mac Catalyst Testing Notes" "$ROOT/MAC_CATALYST_TESTING.md"
section_file "TestFlight Readiness Notes" "$ROOT/TESTFLIGHT_READINESS.md"
section_file "P2P Server README" "$ROOT/server/README_P2P_PROXY.md"
section_file "Agent Start" "$ROOT/AGENTS.md"
section_file "Agent Brain Ops Playbook" "$ROOT/agent/playbooks/brain-ops.md"
section_file "Agent Playback Playbook" "$ROOT/agent/playbooks/playback.md"
section_file "Agent P2P Server Playbook" "$ROOT/agent/playbooks/p2p-server.md"

section_command "Git Working Tree Snapshot" git status --short
section_command "Recent iOS Player Files" find Fotty/Features/Player -maxdepth 2 -type f -name '*.swift'
section_command "Recent P2P Server Files" find server -maxdepth 2 -type f \( -name '*p2p*' -o -name '*proxy*' -o -name '*monitor*' \)

if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$OUT_FILE" | pbcopy
  echo "NotebookLM source refreshed: $OUT_FILE"
  echo "Path copied to clipboard."
else
  echo "NotebookLM source refreshed: $OUT_FILE"
fi
