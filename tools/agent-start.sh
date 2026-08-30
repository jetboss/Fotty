#!/usr/bin/env bash
set -euo pipefail

# Build a compact mission brief before an agent starts meaningful Fotty work.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK="${*:-General Fotty task}"
PLAYBOOK_DIR="$ROOT/agent/playbooks"

print_section() {
  printf '\n== %s ==\n' "$1"
}

pick_playbooks() {
  local task_lc
  task_lc="$(printf '%s' "$TASK" | tr '[:upper:]' '[:lower:]')"
  local picks=()

  case "$task_lc" in
    *playback*|*player*|*stream*|*video*|*webview*|*timeout*|*vod*)
      picks+=("$PLAYBOOK_DIR/playback.md")
      ;;
  esac
  case "$task_lc" in
    *p2p*|*proxy*|*broker*|*homelab*|*ollama*|*server*)
      picks+=("$PLAYBOOK_DIR/p2p-server.md")
      ;;
  esac
  case "$task_lc" in
    *brain*|*agent*|*cursor*|*antigravity*|*knowledge*|*memory*|*rag*|*library*)
      picks+=("$PLAYBOOK_DIR/brain-ops.md")
      ;;
  esac

  if [[ ${#picks[@]} -eq 0 ]]; then
    picks+=("$PLAYBOOK_DIR/playback.md" "$PLAYBOOK_DIR/p2p-server.md" "$PLAYBOOK_DIR/brain-ops.md")
  fi

  printf '%s\n' "${picks[@]}" | awk '!seen[$0]++'
}

print_section "Fotty Agent Mission"
printf 'Task: %s\n' "$TASK"
printf 'Root: %s\n' "$ROOT"

print_section "Brain Health"
if "$ROOT/tools/brain-doctor.sh"; then
  printf 'Brain: healthy\n'
else
  printf 'Brain: unavailable or degraded. Continue with local docs and mention this in the handoff.\n'
fi

print_section "Project Memory Files"
for path in \
  "$ROOT/docs/notebooklm/Project-Memory.md" \
  "$ROOT/docs/notebooklm/Decisions-Log.md" \
  "$ROOT/docs/notebooklm/Architecture-Map.md" \
  "$ROOT/docs/notebooklm/Risks.md"; do
  if [[ -f "$path" ]]; then
    printf -- '- %s\n' "${path#$ROOT/}"
  fi
done

print_section "Relevant Playbooks"
selected_playbooks="$(pick_playbooks)"
printf '%s\n' "$selected_playbooks" | while IFS= read -r playbook; do
  if [[ -f "$playbook" ]]; then
    printf '\n--- %s ---\n' "${playbook#$ROOT/}"
    sed -n '1,220p' "$playbook"
  fi
done

print_section "Brain Brief"
"$ROOT/tools/ask-brain.sh" "For this Fotty task: $TASK. Return prior decisions, risks, likely files, and verification checks. Keep it concise."

print_section "Git Working Tree"
(cd "$ROOT" && {
  count="$(git status --short | wc -l | tr -d ' ')"
  printf 'Changed paths: %s\n' "$count"
  git status --short | sed -n '1,80p'
  if [[ "$count" -gt 80 ]]; then
    printf '... truncated; run git status --short for the full list.\n'
  fi
})

print_section "Agent Contract"
cat <<'TEXT'
- Read the relevant files before editing.
- Preserve user changes already in the working tree.
- Keep playback/P2P changes fail-fast and bounded.
- After meaningful work, run ./tools/agent-finish.sh "summary of work".
TEXT
