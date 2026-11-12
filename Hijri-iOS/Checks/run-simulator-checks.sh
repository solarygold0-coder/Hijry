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
        python3 -c 'import subprocess, sys; subprocess.run(["xcrun", "simctl", "shutdown", sys.argv[1]], timeout=15)' "$active_simulator" >/dev/null 2>&1 || true
    fi
    if [[ -n "$fresh_simulator" ]]; then
        python3 -c 'import subprocess, sys; subprocess.run(["xcrun", "simctl", "delete", sys.argv[1]], timeout=15)' "$fresh_simulator" >/dev/null 2>&1 || true
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
    python3 - "$simulator" "$state" "$app" "$bundle_id" <<'PYTHON'
import subprocess
import sys
import time

device, state, app, bundle_id = sys.argv[1:]
if state == "Shutdown":
    subprocess.run(["xcrun", "simctl", "boot", device], check=True, timeout=45)

# CoreSimulator may stay in data migration after it can already install and
# launch apps. Retry the operations the smoke check actually needs.
for arguments in (
    ["install", device, app],
    ["launch", "--terminate-running-process", device, bundle_id],
):
    deadline = time.monotonic() + 120
    while True:
        try:
            subprocess.run(["xcrun", "simctl", *arguments], check=True, timeout=20)
            break
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            if time.monotonic() >= deadline:
                raise
            time.sleep(5)
PYTHON
    cleanup
    active_simulator=""
    fresh_simulator=""
done
