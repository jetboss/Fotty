#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/web"

source "$ROOT_DIR/tools/lib/web-node.sh"
NODE_MAJOR="$(tr -d '[:space:]' < "$WEB_DIR/.nvmrc")"
if ! [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]]; then
  echo "web/.nvmrc must name the supported Node major." >&2
  exit 1
fi

NODE_BIN="$(fotty_select_web_node "$NODE_MAJOR" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/fotty/toolchains/node$NODE_MAJOR/bin/node" \
  /opt/homebrew/opt/node@"$NODE_MAJOR"/bin/node \
  /opt/homebrew/opt/node/bin/node \
  /usr/local/bin/node \
  "$(command -v node 2>/dev/null || true)" || true)"
if [[ -z "$NODE_BIN" ]]; then
  cat >&2 <<EOF
No suitable local Node $NODE_MAJOR.x binary found (required by web/.nvmrc).

Codex's bundled Node is signed with the hardened runtime and cannot load
Next's ad-hoc signed native SWC/lightningcss modules on macOS. Install Node $NODE_MAJOR
with Homebrew, then rerun:

  brew install node@$NODE_MAJOR
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
