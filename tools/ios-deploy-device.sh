#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Fotty.xcodeproj"
SCHEME="Fotty"
CONFIGURATION="Debug"
BUNDLE_ID="com.jelani.Fotty"
DEVICE_ID=""
SKIP_BUILD=0
NO_LAUNCH=0
LIST_DEVICES=0
APP_PATH_OVERRIDE=""
IOS_ENV_FILE="${IOS_ENV_FILE:-$ROOT_DIR/.env.ios.local}"

if [[ -f "$IOS_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$IOS_ENV_FILE"
  set +a
fi

SECRET_BUILD_SETTINGS=(
  "FOOTBALL_DATA_API_KEY=${FOOTBALL_DATA_API_KEY:-}"
  "RAPID_API_KEY=${RAPID_API_KEY:-}"
  "API_FOOTBALL_KEY=${API_FOOTBALL_KEY:-}"
)

usage() {
  cat <<'EOF'
Usage:
  tools/ios-deploy-device.sh [options]

Options:
  --device <udid>         Deploy to a specific physical iPhone/iPad.
  --scheme <name>         Xcode scheme to build. Default: Fotty
  --configuration <name>  Build configuration. Default: Debug
  --bundle-id <id>        Bundle identifier to launch. Default: com.jelani.Fotty
  --skip-build            Reuse the latest built app instead of rebuilding.
  --app-path <path>       Install this already-built .app bundle without rebuilding.
  --no-launch             Install only; do not launch after install.
  --list-devices          Print available paired devices and exit.
  --help                  Show this help.

Examples:
  tools/ios-deploy-device.sh
  tools/ios-deploy-device.sh --device 00008130-000544A0212A001C
  tools/ios-deploy-device.sh --skip-build --no-launch
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE_ID="${2:-}"
      shift 2
      ;;
    --scheme)
      SCHEME="${2:-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --app-path)
      APP_PATH_OVERRIDE="${2:-}"
      SKIP_BUILD=1
      shift 2
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    --list-devices)
      LIST_DEVICES=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Could not find Xcode project at $PROJECT_PATH" >&2
  exit 1
fi

list_devices() {
  echo "Paired devices:"
  xcrun devicectl list devices
}

resolve_xcode_device() {
  xcodebuild -showdestinations -project "$PROJECT_PATH" -scheme "$SCHEME" 2>/dev/null \
    | sed -n 's/.*platform:iOS, arch:arm64, id:\([^,]*\), name:.*/\1/p' \
    | head -n 1
}

resolve_devicectl_device() {
  xcrun devicectl list devices 2>/dev/null \
    | awk '/available \(paired\)/ {print $3; exit}'
}

build_app() {
  echo "Building $SCHEME ($CONFIGURATION) for device $DEVICE_ID..."
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS,id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    "${SECRET_BUILD_SETTINGS[@]}" \
    build
}

build_settings() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS,id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    "${SECRET_BUILD_SETTINGS[@]}" \
    -showBuildSettings
}

resolve_app_path() {
  local settings
  settings="$(build_settings)"

  local build_dir
  local product_name

  build_dir="$(printf '%s\n' "$settings" | awk -F' = ' '/ TARGET_BUILD_DIR = / {print $2; exit}')"
  product_name="$(printf '%s\n' "$settings" | awk -F' = ' '/ FULL_PRODUCT_NAME = / {print $2; exit}')"

  if [[ -z "${build_dir:-}" || -z "${product_name:-}" ]]; then
    echo "Failed to resolve build output path from Xcode build settings." >&2
    exit 1
  fi

  printf '%s/%s\n' "$build_dir" "$product_name"
}

install_app() {
  local device="$1"
  local app_path="$2"
  local output
  local status

  echo "Installing $app_path on $device..."
  set +e
  output="$(xcrun devicectl device install app --device "$device" "$app_path" 2>&1)"
  status=$?
  set -e

  printf '%s\n' "$output"

  if [[ $status -ne 0 ]]; then
    if grep -qiE "device is locked|could not be unlocked|could not be mounted" <<<"$output"; then
      echo "Install failed because the device is locked. Unlock it and rerun the script." >&2
    fi
    exit $status
  fi
}

launch_app() {
  local device="$1"
  local output
  local status

  echo "Launching $BUNDLE_ID on $device..."
  local existing_processes
  local existing_pid
  existing_processes="$({
    xcrun devicectl device info processes --device "$device" --timeout 20 --search Fotty
  } || true)"
  existing_pid="$(awk '/\/Fotty\.app\/Fotty$/ { print $1; exit }' <<<"$existing_processes")"
  if [[ -n "$existing_pid" ]]; then
    xcrun devicectl device process terminate --device "$device" --pid "$existing_pid"
  fi

  set +e
  output="$(xcrun devicectl device process launch --device "$device" "$BUNDLE_ID" 2>&1)"
  status=$?
  set -e

  printf '%s\n' "$output"

  if [[ $status -ne 0 ]]; then
    if grep -qiE "device was not, or could not be, unlocked|unable to launch .* unlocked|locked" <<<"$output"; then
      echo "Launch failed because the device is locked. Unlock it and rerun the script, or use --no-launch." >&2
    fi
    exit $status
  fi
}

if [[ "$LIST_DEVICES" -eq 1 ]]; then
  list_devices
  exit 0
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(resolve_devicectl_device)"
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(resolve_xcode_device)"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No physical iOS device destination was found. Connect and unlock an iPhone or iPad, then retry with --list-devices." >&2
  exit 1
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  build_app
elif [[ -z "$APP_PATH_OVERRIDE" ]]; then
  echo "Note: --skip-build reuses the last build. If install fails with an expired profile, rerun without --skip-build." >&2
fi

if [[ -n "$APP_PATH_OVERRIDE" ]]; then
  APP_PATH="$APP_PATH_OVERRIDE"
else
  APP_PATH="$(resolve_app_path)"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app bundle not found at $APP_PATH" >&2
  exit 1
fi

install_app "$DEVICE_ID" "$APP_PATH"

if [[ "$NO_LAUNCH" -eq 0 ]]; then
  launch_app "$DEVICE_ID"
fi

echo "Done."
