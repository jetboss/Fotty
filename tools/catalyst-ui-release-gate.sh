#!/usr/bin/env bash

# Runs the release-scope UI audits individually on Mac Catalyst. This script
# never starts a simulator and never installs a UI-test runner on iPhone/iPad.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWNS_DERIVED_DATA=0
XCODE_JOBS="${FOTTY_XCODE_JOBS:-2}"
if ! [[ "$XCODE_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "FOTTY_XCODE_JOBS must be a positive integer." >&2
  exit 2
fi
if [[ -n "${FOTTY_CATALYST_UI_DERIVED_DATA:-}" ]]; then
  DERIVED_DATA_PATH="$FOTTY_CATALYST_UI_DERIVED_DATA"
else
  DERIVED_DATA_PATH="$(mktemp -d /private/tmp/FottyCatalystUIReleaseGate.XXXXXX)"
  OWNS_DERIVED_DATA=1
fi

cleanup_derived_data() {
  [[ "$OWNS_DERIVED_DATA" -eq 1 ]] || return 0
  case "$DERIVED_DATA_PATH" in
    /private/tmp/FottyCatalystUIReleaseGate.*)
      if [[ -e "$DERIVED_DATA_PATH" ]]; then
        find "$DERIVED_DATA_PATH" -depth -delete
      fi
      ;;
    *)
      echo "Refusing unexpected Catalyst cleanup target: $DERIVED_DATA_PATH" >&2
      return 1
      ;;
  esac
}

trap cleanup_derived_data EXIT INT TERM

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

mac_lock_state="$(ioreg -n Root -d1)"
if grep -q 'CGSSessionScreenIsLocked"=Yes' <<<"$mac_lock_state"; then
  echo "The Mac is locked. Unlock it before running Catalyst UI automation." >&2
  exit 2
fi

tests=(
  testDashboardHitRegionAccessibilityAudit
  testDashboardTextClippingAccessibilityAudit
  testDashboardElementDescriptionAccessibilityAudit
  testDashboardDynamicTypeAccessibilityAudit
  testFPLWorkspacesDynamicTypeAccessibilityAudit
  testFPLContextSurvivesTabSwitch
  testFPLSavedDraftAndPickerRejection
  testMatchdayDynamicTypeAccessibilityAudit
  testSettingsDynamicTypeAccessibilityAudit
  testMatchCenterDynamicTypeAccessibilityAudit
  testPlayerDynamicTypeAccessibilityAudit
  testDashboardContrastAndTraitsAccessibilityAudit
  testDashboardElementDetectionAccessibilityAudit
  testRapidTabSwitchingAndForegroundRecovery
  testBetaSupportOpensNativeHelpAndFeedback
  testBetaFPLInputAcceptsTeamLinksWithoutAutomaticallyConnecting
  testBetaSetupStaysFocusedOnMatchdayAndCanBeDismissed
  testCricketDiscoverySeparatesChannelsAndSavesWithoutFPL
  testHomeDiscoveryShowsActivityFiltersAndFullLineup
)

if [[ "$#" -gt 0 ]]; then
  for requested_test in "$@"; do
    case " ${tests[*]} " in
      *" $requested_test "*) ;;
      *) echo "Unknown Catalyst check: $requested_test" >&2; exit 2 ;;
    esac
  done
  tests=("$@")
fi

cd "$ROOT_DIR"

run_ui_test() {
  local test_name="$1"
  local attempt
  local output
  local status

  for attempt in 1 2; do
    set +e
    output="$(
      xcodebuild test \
        -quiet \
        -project "$ROOT_DIR/Fotty.xcodeproj" \
        -scheme Fotty \
        -configuration Debug \
        -destination 'platform=macOS,variant=Mac Catalyst' \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -jobs "$XCODE_JOBS" \
        -parallel-testing-enabled NO \
        -allowProvisioningUpdates \
        -only-testing:"FottyUITests/FottyNavigationUITests/$test_name" \
        2>&1
    )"
    status=$?
    set -e

    printf '%s\n' "$output"
    if [[ "$status" -eq 0 ]]; then
      return 0
    fi
    if [[ "$attempt" -eq 1 ]] && grep -q 'Timed out while enabling automation mode' <<<"$output"; then
      echo "Xcode did not enable Catalyst automation before the test began; retrying $test_name once..." >&2
      continue
    fi
    # Extract the useful failure before the owned result bundle is cleaned up.
    local newest_result
    newest_result="$(ls -td "$DERIVED_DATA_PATH"/Logs/Test/*.xcresult 2>/dev/null | head -n 1 || true)"
    if [[ -n "$newest_result" ]]; then
      xcrun xcresulttool get test-results summary --path "$newest_result" --compact || true
    fi
    return "$status"
  done
}

for test_name in "${tests[@]}"; do
  echo "Running FottyNavigationUITests/$test_name on Mac Catalyst..."
  run_ui_test "$test_name"
done

echo "All ${#tests[@]} selected Catalyst checks passed."
