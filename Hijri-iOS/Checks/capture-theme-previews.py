#!/usr/bin/env python3
"""Capture the five calendar layouts from a running iOS Simulator."""
from pathlib import Path
import subprocess
import sys
import time


device, bundle, directory = sys.argv[1:]
output = Path(directory)
output.mkdir(parents=True, exist_ok=True)
for theme in ["royal", "emerald", "minimal", "lavender", "sky"]:
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", device, bundle,
        "-designTheme", theme, "-appearance", "theme", "-hijri.reference556", "YES",
        "-hijri.permissionGuide556", "YES", "-navigationTop", "NO", "-appLanguage", "ar"], check=True, timeout=45)
    time.sleep(4)
    subprocess.run(["xcrun", "simctl", "io", device, "screenshot", str(output / (theme + ".png"))], check=True, timeout=30)
print("Captured five theme screenshots")
