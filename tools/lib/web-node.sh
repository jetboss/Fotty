#!/usr/bin/env bash

# Shared by the local build entry point and its process-level selection tests.
# A newer major is not necessarily supported (for example Node 25 is EOL).
fotty_web_node_is_usable() {
  local candidate="$1"
  local required_major="$2"
  [[ "$required_major" =~ ^[0-9]+$ ]] || return 1
  [[ -n "$candidate" && -x "$candidate" && "$candidate" != /Applications/Codex.app/* ]] || return 1
  "$candidate" -e '
    const major = Number(process.versions.node.split(".")[0]);
    const required = Number(process.argv[1]);
    const bundled = process.execPath.startsWith("/Applications/Codex.app/");
    process.exit(major === required && process.platform === "darwin" && !bundled ? 0 : 1);
  ' "$required_major" 2>/dev/null
}

fotty_select_web_node() {
  local required_major="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if fotty_web_node_is_usable "$candidate" "$required_major"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}
