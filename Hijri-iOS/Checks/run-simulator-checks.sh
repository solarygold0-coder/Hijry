#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir="${1:-$PWD/build/simulator}"
if [[ "${HIJRI_SKIP_SIMULATOR_BUILD:-0}" != 1 ]]; then
    xcodebuild -project Hijri.xcodeproj -scheme Hijri -configuration Release \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_dir" \
        CODE_SIGNING_ALLOWED=NO build
fi

app="$build_dir/Build/Products/Release-iphonesimulator/Hijri.app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
active_simulator=""
fresh_simulator=""
cleanup() {
    if [[ -n "$active_simulator" ]]; then
        xcrun simctl shutdown "$active_simulator" >/dev/null 2>&1 || true
    fi
    if [[ -n "$fresh_simulator" ]]; then
        xcrun simctl delete "$fresh_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

sdk="$(xcrun --sdk iphonesimulator --show-sdk-version)"
for model in 'iPhone 18 Pro Max' 'iPad Pro 13-inch (M5)'; do
    selection="$(xcrun simctl list -j | python3 Checks/simulator-destination.py "$model" "$sdk")"
    IFS=' ' read -r simulator runtime state device_type <<<"$selection"
    printf 'Checking %s using %s\n' "$model" "$runtime"
    if [[ "${HIJRI_FRESH_SIMULATORS:-0}" == 1 ]]; then
        fresh_simulator="$(xcrun simctl create "Hijri check - $model" "$device_type" "$runtime")"
        simulator="$fresh_simulator"
        state=Shutdown
    fi
    if [[ "$state" == Shutdown ]]; then
        active_simulator="$simulator"
    fi
    python3 - "$simulator" <<'PYTHON'
import subprocess
import sys

subprocess.run(["xcrun", "simctl", "bootstatus", sys.argv[1], "-b"], check=True, timeout=240)
PYTHON
    xcrun simctl install "$simulator" "$app"
    xcrun simctl launch --terminate-running-process "$simulator" "$bundle_id"
    cleanup
    active_simulator=""
    fresh_simulator=""
done
