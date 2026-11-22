#!/usr/bin/env python3
"""Verify the exported App Store build and its embedded widget on macOS."""

import plistlib
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def verify_profile(bundle, bundle_id):
    profile = bundle / "embedded.mobileprovision"
    decoded = subprocess.check_output(["/usr/bin/security", "cms", "-D", "-i", str(profile)])
    data = plistlib.loads(decoded)
    entitlements = data["Entitlements"]
    team, separator, identifier = entitlements["application-identifier"].partition(".")
    require(separator and team and identifier == bundle_id, f"Incorrect profile identifier for {bundle.name}")
    require(not entitlements.get("get-task-allow", False), f"Development profile for {bundle.name}")
    require("ProvisionedDevices" not in data and not data.get("ProvisionsAllDevices", False),
            f"Expected an App Store profile for {bundle.name}")
    if bundle.suffix == ".app":
        require(entitlements.get("com.apple.developer.weatherkit") is True,
                "The app's App Store profile is missing WeatherKit")


def verify_ipa(ipa_path, bundle_id):
    with TemporaryDirectory() as directory:
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(ipa_path), directory], check=True)

        app = Path(directory) / "Payload" / "Hijri.app"
        widget = app / "PlugIns" / "HijriWidget.appex"
        app_info = plistlib.loads((app / "Info.plist").read_bytes())
        for bundle, expected_id in ((app, bundle_id), (widget, bundle_id + ".widget")):
            info = plistlib.loads((bundle / "Info.plist").read_bytes())
            require(info["CFBundleIdentifier"] == expected_id, f"Incorrect identifier for {bundle.name}")
            require(set(info["UIDeviceFamily"]) == {1, 2}, f"iPhone or iPad support missing for {bundle.name}")
            require(info["MinimumOSVersion"] == "16.0", f"Unexpected deployment target for {bundle.name}")
            for key in ("CFBundleShortVersionString", "CFBundleVersion"):
                require(info[key] == app_info[key], f"{key} differs between the app and widget")
            require((bundle / "ummalqura.bin").is_file(), f"Calendar table missing from {bundle.name}")
            verify_profile(bundle, expected_id)

        require(len(app_info["UISupportedInterfaceOrientations~ipad"]) == 4,
                "iPad orientation configuration is incomplete")
        require((app / "PrivacyInfo.xcprivacy").is_file(), "The app's privacy manifest is missing")
        require((app / "alarm_fallback.wav").is_file(), "The bundled alarm tone is missing")
        require(app_info["BGTaskSchedulerPermittedIdentifiers"] == [bundle_id + ".weather-refresh"],
                "The background refresh identifier does not match the signed app")
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: python3 verify-ipa.py path/to/Hijri.ipa BUNDLE_ID")
    verify_ipa(Path(sys.argv[1]), sys.argv[2])
    print(f"Verified {sys.argv[1]}")
