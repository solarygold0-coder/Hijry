#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null; then
    echo "Run on macOS with Xcode 26 or later." >&2
    exit 2
fi
if [[ $# -ne 2 || ! "$1" =~ ^[A-Z0-9]{10}$ || ! "$2" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    echo "Usage: ./export-ipa.sh TEAM_ID BUNDLE_ID" >&2
    exit 2
fi
version="$(xcodebuild -version | awk 'NR==1 {print $2}' | cut -d. -f1)"
if [[ ! "$version" =~ ^[0-9]+$ ]] || [[ "$version" -lt 26 ]]; then
    echo "Xcode 26 or later is required." >&2
    exit 2
fi
team="$1"
bundle="$2"
if [[ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]]; then
    if [[ ! -s "${ASC_KEY_PATH:-}" || -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
        echo "Provide ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID together for automatic CI signing." >&2
        exit 2
    fi
    set -- -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
else
    set --
fi
mkdir -p build
output="$(mktemp -d "$PWD/build/export.XXXXXX")"
cp ExportOptions.plist "$output/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Add :teamID string $team" "$output/ExportOptions.plist"
xcodebuild -project Hijri.xcodeproj -scheme Hijri -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$output/Hijri.xcarchive" \
    -allowProvisioningUpdates "$@" DEVELOPMENT_TEAM="$team" HIJRI_BUNDLE_ID="$bundle" archive
xcodebuild -exportArchive -archivePath "$output/Hijri.xcarchive" \
    -exportOptionsPlist "$output/ExportOptions.plist" -exportPath "$output/ipa" -allowProvisioningUpdates "$@"
python3 verify-ipa.py "$output/ipa/Hijri.ipa" "$bundle"
printf '%s\n' "$output/ipa/Hijri.ipa"
