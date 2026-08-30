#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="${1:-$(date +%Y-%m-%d)}"
DEST="$ROOT_DIR/backups/web-pre-matchday-dashboard-${STAMP}"

mkdir -p "$ROOT_DIR/backups"
rsync -a --delete \
  --exclude 'node_modules' \
  --exclude '.next' \
  --exclude 'test-results' \
  --exclude '.turbo' \
  "$ROOT_DIR/web/" \
  "$DEST/"

git -C "$ROOT_DIR" rev-parse HEAD >"$DEST/GIT_COMMIT.txt" 2>/dev/null || echo "unknown" >"$DEST/GIT_COMMIT.txt"

cat >"$DEST/RESTORE.md" <<EOF
# Web backup — ${STAMP}

Restore from repo root:

\`\`\`bash
rsync -a --delete \\
  --exclude 'node_modules' \\
  --exclude '.next' \\
  --exclude 'test-results' \\
  backups/web-pre-matchday-dashboard-${STAMP}/ \\
  web/
\`\`\`
EOF

echo "Backup written to $DEST ($(du -sh "$DEST" | awk '{print $1}'))"
