#!/usr/bin/env bash

# Launches only the normal Fotty app on a real, unlocked CoreDevice target and
# proves that its process survives a bounded foreground hold. No simulator or
# UI-test runner is used.
set -euo pipefail

DEVICE_ID=""
HOLD_SECONDS=60
BUNDLE_ID="com.jelani.Fotty"
COREDEVICE_TIMEOUT=20

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

usage() {
  cat <<'EOF'
Usage: tools/ios-physical-launch-hold.sh --device <coredevice-id> [options]

Options:
  --device <id>         Required physical CoreDevice identifier.
  --hold-seconds <n>    Foreground process hold, default 60 seconds.
  --bundle-id <id>      App bundle identifier, default com.jelani.Fotty.
  --help                Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_ID="${2:-}"; shift 2 ;;
    --hold-seconds) HOLD_SECONDS="${2:-}"; shift 2 ;;
    --bundle-id) BUNDLE_ID="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$DEVICE_ID" ]]; then
  echo "--device is required." >&2
  usage
  exit 1
fi

if ! [[ "$HOLD_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "--hold-seconds must be a positive integer." >&2
  exit 1
fi

device_line=""
for attempt in 1 2 3; do
  device_line="$(xcrun devicectl list devices | grep -F "$DEVICE_ID" || true)"
  if [[ "$device_line" == *'available (paired)'* || "$device_line" == *' connected '* ]]; then
    break
  fi
  if (( attempt < 3 )); then
    sleep 1
  fi
done
if [[ -z "$device_line" ]]; then
  echo "Device $DEVICE_ID is not known to CoreDevice." >&2
  exit 1
fi
if [[ "$device_line" != *physical* ]]; then
  echo "Refusing non-physical target $DEVICE_ID." >&2
  exit 2
fi
if [[ "$device_line" != *'available (paired)'* && "$device_line" != *' connected '* ]]; then
  echo "Physical device $DEVICE_ID is not available and paired." >&2
  exit 2
fi

# CoreDevice reports a directly cabled device as `connected`, whereas a
# wireless/pairing entry can say `available (paired)`. The following protected
# lock-state and installed-app reads must still succeed before any launch.
lock_state="$(xcrun devicectl device info lockState --device "$DEVICE_ID" --timeout "$COREDEVICE_TIMEOUT")"
if grep -q 'passcodeRequired: true' <<<"$lock_state"; then
  echo "Physical device $DEVICE_ID is locked. Unlock it before the launch hold." >&2
  exit 2
fi

installed_app="$(
  xcrun devicectl device info apps \
    --device "$DEVICE_ID" \
    --timeout "$COREDEVICE_TIMEOUT" \
    --filter "bundleIdentifier == '$BUNDLE_ID'" \
    --columns 'Bundle Identifier,Version,Bundle Version,Name'
)"
if ! grep -q "$BUNDLE_ID" <<<"$installed_app"; then
  echo "$BUNDLE_ID is not installed on physical device $DEVICE_ID." >&2
  exit 1
fi

printf '%s\n' "$installed_app"

# `--terminate-existing` is not implemented consistently by the iOS 27
# CoreDevice transport (it can terminate the app and then return error 10004
# without relaunching it). End only the normal Fotty process explicitly, then
# use the broadly supported launch path. The extension process, when present,
# is intentionally left to the system lifecycle.
existing_processes="$({
  xcrun devicectl device info processes \
    --device "$DEVICE_ID" \
    --timeout "$COREDEVICE_TIMEOUT" \
    --search Fotty
} || true)"
existing_pid="$(awk '/\/Fotty\.app\/Fotty$/ { print $1; exit }' <<<"$existing_processes")"
if [[ -n "$existing_pid" ]]; then
  xcrun devicectl device process terminate \
    --device "$DEVICE_ID" \
    --pid "$existing_pid"
fi

xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID"

elapsed=0
while (( elapsed < HOLD_SECONDS )); do
  remaining=$((HOLD_SECONDS - elapsed))
  interval=10
  if (( remaining < interval )); then interval=$remaining; fi
  sleep "$interval"
  elapsed=$((elapsed + interval))

  processes="$(
    xcrun devicectl device info processes \
      --device "$DEVICE_ID" \
      --timeout "$COREDEVICE_TIMEOUT" \
      --search Fotty
  )"
  if ! grep -q 'Fotty' <<<"$processes"; then
    echo "Fotty exited before the ${HOLD_SECONDS}-second hold completed (${elapsed}s observed)." >&2
    exit 3
  fi
  echo "Fotty foreground process present at ${elapsed}s."
done

echo "Fotty survived the ${HOLD_SECONDS}-second physical-device launch hold."
