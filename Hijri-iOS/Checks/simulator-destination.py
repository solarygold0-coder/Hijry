#!/usr/bin/env python3
"""Choose a compatible iOS runtime and simulator device type from simctl JSON."""

import json
import sys


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return (parts + (0, 0, 0))[:3]


def select(catalog, model, sdk):
    device = next((item for item in catalog["devicetypes"] if item["name"] == model), None)
    if device is None:
        raise ValueError(f"Missing simulator device type: {model}")

    lower = version(device.get("minRuntimeVersionString", "0.0"))
    upper = version(device.get("maxRuntimeVersionString", "99.0"))
    compatible = [
        item for item in catalog["runtimes"]
        if item["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
        and item["isAvailable"]
        and lower <= version(item["version"]) <= min(upper, version(sdk))
    ]
    if not compatible:
        raise ValueError(f"No compatible installed iOS simulator for {model} with SDK {sdk}")
    runtime = max(compatible, key=lambda item: version(item["version"]))
    return device["identifier"], runtime["identifier"]


if __name__ == "__main__":
    try:
        print(*select(json.load(sys.stdin), sys.argv[1], sys.argv[2]))
    except ValueError as error:
        raise SystemExit(str(error)) from error
