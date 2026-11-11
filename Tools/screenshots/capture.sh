#!/bin/bash
# Capture the App Store screenshots in every language of the app.
#
# Usage:
#   Tools/screenshots/capture.sh                 # fr en es it pt
#   Tools/screenshots/capture.sh fr en           # some languages only
#   DEVICE="iPhone 17 Pro Max" Tools/screenshots/capture.sh
#
# Needs Xcode and XcodeGen (`brew install xcodegen`). Builds the app once,
# runs WildCallUITests on a large iPhone simulator for each language and
# writes build/screenshots/<language>/NN-name.png. The app runs in its
# debug-only demo mode (WildCall/Support/ScreenshotFixtures.swift): real
# packs, extensions reported as enabled, a few sample rules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/screenshots"
DERIVED="$ROOT/build/DerivedData"
cd "$ROOT"

if [ "$#" -gt 0 ]; then LANGUAGES=("$@"); else LANGUAGES=(fr en es it pt); fi

region_for() {
    case "$1" in
        fr) echo FR ;; en) echo US ;; es) echo ES ;; it) echo IT ;; pt) echo PT ;;
        *) echo "unknown language: $1" >&2; exit 1 ;;
    esac
}

# The largest iPhone available : App Store Connect scales its screenshots
# down for the smaller sizes.
if [ -z "${DEVICE:-}" ]; then
    DEVICE="$(xcrun simctl list devices available | grep -E '^ +iPhone [0-9]+ Pro Max \(' | tail -1 | sed -E 's/^ +(iPhone [0-9]+ Pro Max) \(.*/\1/')"
fi
if [ -z "$DEVICE" ]; then
    echo "error: no iPhone Pro Max simulator found, set DEVICE" >&2
    exit 1
fi
UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | tail -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')"
echo "simulator: $DEVICE ($UDID)"

# xcodebuild is verbose : keep its output in a log and print the lines
# that matter when a step fails.
LOGS="$ROOT/build/logs"
mkdir -p "$LOGS"
quiet() {
    local log="$LOGS/$1.log"; shift
    if ! "$@" > "$log" 2>&1; then
        grep -E "error:|: error|XCTAssert|failed|Failing tests|\*\* " "$log" | sort -u | head -60 || true
        echo "full log: $log" >&2
        exit 1
    fi
}

xcodegen generate --quiet
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 --operatorName ""

quiet build xcodebuild build-for-testing \
    -project WildCall.xcodeproj -scheme WildCallScreenshots \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" \
    -skipMacroValidation -skipPackagePluginValidation

for language in "${LANGUAGES[@]}"; do
    region="$(region_for "$language")"
    mkdir -p "$OUT/$language"
    echo "capturing $language ($region)"
    TEST_RUNNER_SCREENSHOT_DIR="$OUT/$language" \
    TEST_RUNNER_SCREENSHOT_LANGUAGE="$language" \
    TEST_RUNNER_SCREENSHOT_REGION="$region" \
    quiet "test-$language" xcodebuild test-without-building \
        -project WildCall.xcodeproj -scheme WildCallScreenshots \
        -destination "id=$UDID" -derivedDataPath "$DERIVED" \
        -resultBundlePath "$ROOT/build/results/screenshots-$language.xcresult"
done

xcrun simctl status_bar "$UDID" clear
echo "screenshots in $OUT"
