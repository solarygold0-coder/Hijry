#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir="${1:-$PWD/build/simulator}"
xcodebuild -project Hijri.xcodeproj -scheme Hijri -configuration Release \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_dir" \
    CODE_SIGNING_ALLOWED=NO build

app="$build_dir/Build/Products/Release-iphonesimulator/Hijri.app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
active_simulator=""
cleanup() {
    if [[ -n "$active_simulator" ]]; then
        xcrun simctl shutdown "$active_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

sdk="$(xcrun --sdk iphonesimulator --show-sdk-version)"
for model in 'iPhone 18 Pro Max' 'iPad Pro 13-inch (M5)'; do
    selection="$(xcrun simctl list -j | python3 Checks/simulator-destination.py "$model" "$sdk")"
    IFS=' ' read -r simulator runtime state <<<"$selection"
    printf 'Checking %s using %s\n' "$model" "$runtime"
    if [[ "$state" == Shutdown ]]; then
        active_simulator="$simulator"
    fi
    xcrun simctl bootstatus "$simulator" -b
    xcrun simctl install "$simulator" "$app"
    xcrun simctl launch --terminate-running-process "$simulator" "$bundle_id"
    cleanup
    active_simulator=""
done
