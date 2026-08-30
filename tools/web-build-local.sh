#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/web"

choose_node() {
  local candidate
  for candidate in \
    /opt/homebrew/opt/node@24/bin/node \
    /opt/homebrew/opt/node/bin/node \
    /usr/local/bin/node \
    "$(command -v node 2>/dev/null || true)"
  do
    if [[ -n "$candidate" && -x "$candidate" && "$candidate" != /Applications/Codex.app/* ]]; then
      "$candidate" -e "const major=Number(process.versions.node.split('.')[0]); process.exit(major >= 24 && process.platform === 'darwin' ? 0 : 1)" 2>/dev/null && {
        printf '%s\n' "$candidate"
        return 0
      }
    fi
  done
  return 1
}

NODE_BIN="$(choose_node || true)"
if [[ -z "$NODE_BIN" ]]; then
  cat >&2 <<'EOF'
No suitable local Node 24+ binary found.

Codex's bundled Node is signed with the hardened runtime and cannot load
Next's ad-hoc signed native SWC/lightningcss modules on macOS. Install Node 24
with Homebrew, then rerun:

  brew install node@24
EOF
  exit 1
fi

echo "Using Node: $NODE_BIN ($("$NODE_BIN" -v))"
cd "$WEB_DIR"
export PATH="$(dirname "$NODE_BIN"):$PATH"

if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
  LIGHTNING_FALLBACK="node_modules/lightningcss/lightningcss.darwin-arm64.node"
  LIGHTNING_NATIVE="../lightningcss-darwin-arm64/lightningcss.darwin-arm64.node"
  if [[ ! -e "$LIGHTNING_FALLBACK" && -e "node_modules/lightningcss-darwin-arm64/lightningcss.darwin-arm64.node" ]]; then
    ln -s "$LIGHTNING_NATIVE" "$LIGHTNING_FALLBACK"
  fi
fi

exec "$NODE_BIN" node_modules/next/dist/bin/next build "$@"
