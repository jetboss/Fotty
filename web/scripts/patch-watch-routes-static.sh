#!/usr/bin/env bash
# Static FTP export cannot include dynamic API handlers. Patch every API route
# that exports force-dynamic to force-static for that build only.
# Restore with: tools/web-deploy-ftp.sh restore step, or git checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
count=0

while IFS= read -r -d '' file; do
  if grep -q 'export const dynamic = "force-dynamic"' "$file"; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      sed -i '' 's/export const dynamic = "force-dynamic"/export const dynamic = "force-static"/' "$file"
    else
      sed -i 's/export const dynamic = "force-dynamic"/export const dynamic = "force-static"/' "$file"
    fi
    count=$((count + 1))
  fi
done < <(find "$ROOT/src/app/api" -name 'route.ts' -print0)

echo "Patched ${count} API routes to force-static for static export"
