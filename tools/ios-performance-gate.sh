#!/usr/bin/env bash
# Builds Fotty with Release optimization for one physical iPhone/iPad, installs it,
# and optionally records a bounded SwiftUI Instruments trace. No simulator and
# no UI-test runner are involved; all temporary build/trace data is removed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID=""
TRACE_DEVICE=""
TRACE_SECONDS=30
XCODE_JOBS="${FOTTY_XCODE_JOBS:-1}"
TEMP_ROOT="$(mktemp -d /private/tmp/FottyPerformanceGate.XXXXXX)"

cleanup() {
  case "$TEMP_ROOT" in
    /private/tmp/FottyPerformanceGate.*)
      [[ ! -e "$TEMP_ROOT" ]] || find "$TEMP_ROOT" -depth -delete
      ;;
    *)
      echo "Refusing unexpected performance-gate cleanup target: $TEMP_ROOT" >&2
      return 1
      ;;
  esac
  echo "Free space after bounded cleanup:"
  df -h /System/Volumes/Data | tail -1
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat <<'EOF'
Usage: tools/ios-performance-gate.sh --device <CoreDevice UUID> [options]

Options:
  --device <uuid>         Required physical iPhone/iPad identifier from devicectl
  --trace-device <name>   Also record a SwiftUI trace using this xctrace device name
  --seconds <10-120>      Trace duration; defaults to 30 seconds
  --help                  Show help

Example:
  tools/ios-performance-gate.sh \
    --device BB28E60B-9156-56C3-A5E1-1DBC8CABEC3D \
    --trace-device "Jelani’s iPhone" --seconds 30

Unlock the device before starting. During an optional trace, repeatedly scroll
Home from the top through the catalog. Available trace schemas are listed, then
the trace is deleted. Capture success alone does not qualify performance.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_ID="${2:-}"; shift 2 ;;
    --trace-device) TRACE_DEVICE="${2:-}"; shift 2 ;;
    --seconds) TRACE_SECONDS="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$DEVICE_ID" ]]; then
  echo "--device is required; this gate never guesses a target device." >&2
  exit 2
fi
if ! [[ "$DEVICE_ID" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "--device must be an explicit 36-character physical CoreDevice UUID." >&2
  exit 2
fi
if ! [[ "$TRACE_SECONDS" =~ ^[0-9]+$ ]] || (( TRACE_SECONDS < 10 || TRACE_SECONDS > 120 )); then
  echo "--seconds must be an integer from 10 through 120." >&2
  exit 2
fi
if ! [[ "$XCODE_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "FOTTY_XCODE_JOBS must be a positive integer." >&2
  exit 2
fi
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
[[ -d "$DEVELOPER_DIR" ]] || { echo "Configured Xcode developer directory is unavailable." >&2; exit 2; }

cd "$ROOT_DIR"
echo "Free space before performance build:"
df -h /System/Volumes/Data | tail -1

node tools/generate-football-competition-catalog.mjs --check
node tools/audit-provider-football-identity.mjs

if [[ -n "$TRACE_DEVICE" ]]; then
  # A name is only an acknowledgement, never an independent capture target.
  # Resolve the install device and pass its stable hardware UDID to Instruments.
  DEVICE_DETAILS="$TEMP_ROOT/device-details.json"
  xcrun devicectl device info details --device "$DEVICE_ID" --timeout 20 \
    --json-output "$DEVICE_DETAILS" >/dev/null
  TRACE_UDID="$(plutil -extract result.properties.hardware.udid raw -o - "$DEVICE_DETAILS")"
  RESOLVED_NAME="$(plutil -extract result.properties.state.name raw -o - "$DEVICE_DETAILS")"
  if [[ "$TRACE_DEVICE" != "$RESOLVED_NAME" && "$TRACE_DEVICE" != "$TRACE_UDID" ]]; then
    echo "Trace target does not match the explicitly selected install device." >&2
    exit 2
  fi
fi

echo "Building the signed, optimized Fotty application..."
xcodebuild \
  -quiet \
  -project Fotty.xcodeproj \
  -scheme Fotty \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$TEMP_ROOT/DerivedData" \
  -jobs "$XCODE_JOBS" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  FOOTBALL_DATA_API_KEY= \
  RAPID_API_KEY= \
  API_FOOTBALL_KEY= \
  build

APP_PATH="$TEMP_ROOT/DerivedData/Build/Products/Release-iphoneos/Fotty.app"
[[ -d "$APP_PATH" ]] || { echo "Release app was not produced at $APP_PATH." >&2; exit 1; }
codesign --verify --deep --strict "$APP_PATH"

echo "Installing the optimized app on the requested physical device..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Launching Fotty..."
existing_processes="$({
  xcrun devicectl device info processes --device "$DEVICE_ID" --timeout 20 --search Fotty
} || true)"
existing_pid="$(awk '/\/Fotty\.app\/Fotty$/ { print $1; exit }' <<<"$existing_processes")"
if [[ -n "$existing_pid" ]]; then
  xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$existing_pid"
fi
xcrun devicectl device process launch --device "$DEVICE_ID" com.jelani.Fotty

if [[ -n "$TRACE_DEVICE" ]]; then
  TRACE_PATH="$TEMP_ROOT/Fotty-Home-Scroll.trace"
  TOC_PATH="$TEMP_ROOT/Fotty-Home-Scroll-toc.xml"
  echo "Recording a ${TRACE_SECONDS}s SwiftUI trace; scroll Home now..."
  xcrun xctrace record \
    --quiet \
    --template SwiftUI \
    --device "$TRACE_UDID" \
    --attach Fotty \
    --time-limit "${TRACE_SECONDS}s" \
    --output "$TRACE_PATH"
  xcrun xctrace export "$TRACE_PATH" --toc --output "$TOC_PATH"
  echo "Trace captured successfully. Available schemas:"
  rg -o 'schema="[^"]+"' "$TOC_PATH" | sort -u | head -40 || true
fi

echo "Release build, installation and requested trace capture completed."
echo "Responsiveness is not qualified by build success or a schema listing; compare measured app CPU, memory and hitch samples separately."
echo "Free space before bounded cleanup:"
df -h /System/Volumes/Data | tail -1
