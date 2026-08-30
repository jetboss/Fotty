#!/usr/bin/env bash
set -euo pipefail

# End-of-task checklist for keeping Fotty project memory and brain state useful.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUMMARY="${*:-Completed Fotty work}"
TODAY="$(date '+%Y-%m-%d')"

print_section() {
  printf '\n== %s ==\n' "$1"
}

print_section "Fotty Agent Finish"
printf 'Summary: %s\n' "$SUMMARY"

print_section "Changed Files"
(cd "$ROOT" && {
  count="$(git status --short | wc -l | tr -d ' ')"
  printf 'Changed paths: %s\n' "$count"
  git status --short | sed -n '1,120p'
  if [[ "$count" -gt 120 ]]; then
    printf '... truncated; run git status --short for the full list.\n'
  fi
})

print_section "Suggested Decisions-Log Entry"
cat <<TEXT
## $TODAY: $SUMMARY
- **Decision**: 
- **Why**: 
- **Implementation**:
  - 
- **Verification**:
  - 
TEXT

print_section "Memory Update Checklist"
cat <<'TEXT'
- Update docs/notebooklm/Decisions-Log.md for durable technical/product decisions.
- Update docs/notebooklm/Project-Memory.md if pillars, priorities, platform scope, or known risks changed.
- Update docs/notebooklm/Architecture-Map.md if files/modules moved or ownership changed.
- Update docs/notebooklm/Risks.md when a new sharp edge or guardrail appears.
- Update the relevant agent/playbooks/*.md if future agents should behave differently.
TEXT

print_section "Verification Suggestions"
"$ROOT/tools/ask-brain.sh" "For this completed Fotty work: $SUMMARY. Suggest the minimum verification checks and memory files to update. Keep it concise."

print_section "Refresh Brain"
if "$ROOT/tools/private-kb-sync.sh"; then
  "$ROOT/tools/brain-doctor.sh"
else
  printf 'Brain sync failed. Run ./tools/private-kb-sync.sh after fixing the issue.\n'
  exit 1
fi

print_section "Done"
printf 'Fotty memory and brain sync flow completed.\n'
