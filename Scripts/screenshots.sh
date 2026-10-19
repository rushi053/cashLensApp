#!/usr/bin/env bash
#
# Scripts/screenshots.sh — run the per-device screenshot suite.
#
# Builds CashLens once for the simulator, then runs
# `CashLensUITests/ScreenshotSuiteUITests` on every device in the matrix
# in portrait and landscape. Screenshots land in a flat PNG folder
# (`<screen>-<device>-<orientation>.png`) and are also attached inside
# each `.xcresult` bundle.
#
# Usage:
#   Scripts/screenshots.sh                       # full matrix
#   Scripts/screenshots.sh --list                # show available simulators
#   Scripts/screenshots.sh --devices "iPhone 18 Pro|iPad mini (A17 Pro)"
#   Scripts/screenshots.sh --orientations portrait
#   Scripts/screenshots.sh --os 27.0             # pin a runtime when names are ambiguous
#   Scripts/screenshots.sh --skip-build          # reuse the last build-for-testing output
#   Scripts/screenshots.sh --out ~/Desktop/cl-shots
#   Scripts/screenshots.sh --seed /tmp/CashLens-Screenshot-Demo.cashlens.json
#                                                # Debug builds replace the store with
#                                                # this backup before the first frame
#
# Requirements: Xcode 27 (release) with the iOS 27 simulator runtime.
# The Duo simulator needs Xcode 27.1; see the Duo notes below.
#
# Demo data: regenerate Marketing/ScreenshotSampleData/generate_screenshot_data.py
# (dates are relative to the day it runs) into a scratch folder and pass the
# JSON with --seed. Without it the suite logs four expenses through the UI.
#
# Simulator names differ between Xcode releases. If a destination fails
# with "Unable to find a device matching", run `--list` (or
# `xcrun simctl list devices available`) and pass the exact names via
# `--devices`.
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/CashLens.xcodeproj"
SCHEME="CashLensScreenshots"          # shared scheme → Screenshots.xctestplan (StoreKit config for paywall prices)
ONLY_TESTING="CashLensUITests/ScreenshotSuiteUITests"
DERIVED_DATA="$ROOT/build/DerivedData"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/build/screenshots/$STAMP"
OS_VERSION=""
SKIP_BUILD=0
CLEAN_STATUS_BAR=1
SEED_FILE=""

# --- Device matrix ---------------------------------------------------------
# iPhone SE (3rd generation) is the smallest supported iPhone; the two 18 Pro
# models cover the common phone sizes; the iPads cover the two ends of the
# iPad range (mini + 13-inch).
DEVICES=(
  "iPhone SE (3rd generation)"
  "iPhone 18 Pro"
  "iPhone 18 Pro Max"
  "iPad mini (A17 Pro)"
  "iPad Pro 13-inch (M5)"
)

# iPhone Duo — one simulator, "iPhone Duo", in the iOS 27.1 runtime. There
# is no simctl pose command: set the pose with the Device Hub window's
# "Closed / Partially Open / Open" buttons, then run this script once per
# pose (`--devices "iPhone Duo" --orientations portrait --os 27.1`). The
# suite writes one PNG per display (`-screen1` is the inner display); the
# inactive display captures black. Inner-display files come out 2006×2852
# portrait with landscape content — rotate 90° and pad one pixel to App
# Store Connect's 2853×2007 before uploading; the outer display is exactly
# 1398×2034. Not in the default matrix because of the manual pose step:
# DEVICES+=( "iPhone Duo" )

ORIENTATIONS=( portrait landscape )

# --- Args ------------------------------------------------------------------
usage() { sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      xcrun simctl list devices available
      exit 0 ;;
    --devices)
      IFS='|' read -r -a DEVICES <<< "$2"; shift 2 ;;
    --orientations)
      IFS=',' read -r -a ORIENTATIONS <<< "$2"; shift 2 ;;
    --os)
      OS_VERSION="$2"; shift 2 ;;
    --out)
      OUT_DIR="$2"; shift 2 ;;
    --skip-build)
      SKIP_BUILD=1; shift ;;
    --seed)
      SEED_FILE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
    --no-status-bar)
      CLEAN_STATUS_BAR=0; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

PNG_DIR="$OUT_DIR/png"
RESULTS_DIR="$OUT_DIR/results"
LOG_DIR="$OUT_DIR/logs"
mkdir -p "$PNG_DIR" "$RESULTS_DIR" "$LOG_DIR"

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Resolve a simulator name to a UDID so simctl commands are unambiguous
# when several runtimes ship the same device. Prints nothing if not found.
udid_for() {
  local name="$1"
  local line
  if [[ -n "$OS_VERSION" ]]; then
    line="$(xcrun simctl list devices "iOS $OS_VERSION" available 2>/dev/null | grep -F "    $name (" | head -n 1 || true)"
  else
    line="$(xcrun simctl list devices available 2>/dev/null | grep -F "    $name (" | head -n 1 || true)"
  fi
  printf '%s' "$line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -n 1 || true
}

destination_for() {
  local name="$1"
  if [[ -n "$OS_VERSION" ]]; then
    printf 'platform=iOS Simulator,name=%s,OS=%s' "$name" "$OS_VERSION"
  else
    printf 'platform=iOS Simulator,name=%s' "$name"
  fi
}

# --- Build once ------------------------------------------------------------
if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "==> build-for-testing ($SCHEME)"
  xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet \
    2>&1 | tee "$LOG_DIR/build.log"
else
  echo "==> skipping build (using $DERIVED_DATA)"
fi

# --- Run matrix ------------------------------------------------------------
FAILED=()
for device in "${DEVICES[@]}"; do
  device_slug="$(slugify "$device")"
  udid="$(udid_for "$device")"
  sim_ref="${udid:-$device}"

  echo "==> booting: $device ${udid:+($udid)}"
  xcrun simctl boot "$sim_ref" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$sim_ref" -b >/dev/null 2>&1 || true

  if [[ "$CLEAN_STATUS_BAR" -eq 1 ]]; then
    # 9:41, full bars, full battery — the App Store screenshot convention.
    xcrun simctl status_bar "$sim_ref" override \
      --time "9:41" \
      --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 \
      --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true
  fi

  for orientation in "${ORIENTATIONS[@]}"; do
    label="$device_slug-$orientation"
    echo "==> test: $device / $orientation"
    if TEST_RUNNER_CL_DEVICE_SLUG="$device_slug" \
       TEST_RUNNER_CL_ORIENTATION="$orientation" \
       TEST_RUNNER_CL_SCREENSHOT_DIR="$PNG_DIR" \
       TEST_RUNNER_CL_SEED_FILE="$SEED_FILE" \
       xcodebuild test-without-building \
         -project "$PROJECT" \
         -scheme "$SCHEME" \
         -destination "$(destination_for "$device")" \
         -derivedDataPath "$DERIVED_DATA" \
         -only-testing:"$ONLY_TESTING" \
         -resultBundlePath "$RESULTS_DIR/$label.xcresult" \
         -quiet \
         2>&1 | tee "$LOG_DIR/$label.log"; then
      echo "    ok: $label"
    else
      echo "    FAILED: $label (see $LOG_DIR/$label.log)"
      FAILED+=( "$label" )
    fi

    # Belt and braces: also pull the attachments out of the result bundle
    # (Xcode 16+ `xcresulttool export attachments`). The suite already
    # writes PNGs straight into $PNG_DIR when CL_SCREENSHOT_DIR is set.
    if [[ -d "$RESULTS_DIR/$label.xcresult" ]]; then
      xcrun xcresulttool export attachments \
        --path "$RESULTS_DIR/$label.xcresult" \
        --output-path "$RESULTS_DIR/$label-attachments" >/dev/null 2>&1 || true
    fi
  done

  if [[ "$CLEAN_STATUS_BAR" -eq 1 ]]; then
    xcrun simctl status_bar "$sim_ref" clear >/dev/null 2>&1 || true
  fi
done

# --- Summary ---------------------------------------------------------------
echo
echo "Screenshots: $PNG_DIR"
ls -1 "$PNG_DIR" 2>/dev/null | sed 's/^/  /' || true
echo "Result bundles: $RESULTS_DIR"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo
  echo "Failed runs (${#FAILED[@]}):"
  printf '  %s\n' "${FAILED[@]}"
  exit 1
fi
echo "All runs passed."
