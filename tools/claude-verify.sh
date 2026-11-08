#!/usr/bin/env bash
# One-command native verification for agent-assisted work.
# Runs the source-membership guard and the existing simulator-free iOS gate,
# and saves the full output where an agent can read it from the project folder:
#   logs/verify-latest.log   (plus a timestamped copy)
# It never signs, installs, uploads, deploys or pushes anything.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p logs
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
# Match GitHub iOS CI: Catalyst unit tests use a 26.0 deployment target so they
# run on a Mac whose macOS trails the project's mapped target. The iOS Release
# build in ios-ci.sh keeps the real deployment target.
export FOTTY_CATALYST_DEPLOYMENT_TARGET="${FOTTY_CATALYST_DEPLOYMENT_TARGET:-26.0}"
# Prefer the reviewed /Applications/Xcode.app; otherwise use xcode-select's choice.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
LOG="logs/verify-$STAMP.log"
{
  echo "== Fotty verify $STAMP"
  echo "branch: $(git rev-parse --abbrev-ref HEAD)  commit: $(git rev-parse --short HEAD)"
  echo "xcode: ${DEVELOPER_DIR:-$(xcode-select -p)} $(xcodebuild -version 2>&1 | tr '\n' ' ')"
  echo "disk before: $(df -h "$ROOT_DIR" | tail -1)"
  echo
  echo "== source membership"
  python3 -B tools/check_native_source_membership.py
  MEMBERSHIP=$?
  echo "membership exit: $MEMBERSHIP"
  echo
  echo "== ios-ci (Catalyst logic tests + unsigned iOS Release build)"
  FOTTY_XCODE_JOBS=1 ./tools/ios-ci.sh
  CI=$?
  echo "ios-ci exit: $CI"
  echo
  echo "disk after: $(df -h "$ROOT_DIR" | tail -1)"
  echo "== RESULT membership=$MEMBERSHIP ios-ci=$CI"
} 2>&1 | tee "$LOG"
cp "$LOG" logs/verify-latest.log
grep "== RESULT" logs/verify-latest.log
