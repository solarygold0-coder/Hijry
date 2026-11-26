#!/usr/bin/env python3
"""Choose an available simulator for the requested model and Xcode SDK."""

import json
import sys


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return (parts + (0, 0, 0))[:3]


def select(catalog, model, sdk):
    device_info = next(
        (item for item in catalog["devicetypes"] if item["name"] == model),
        None,
    )
    if device_info is None:
        raise ValueError(f"Missing simulator device type: {model}")

    device_type = device_info["identifier"]
    runtimes = sorted(
        (
            runtime for runtime in catalog["runtimes"]
            if runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and runtime["isAvailable"] and version(runtime["version"]) <= version(sdk)
        ),
        key=lambda runtime: version(runtime["version"]),
        reverse=True,
    )
    for runtime in runtimes:
        devices = catalog["devices"].get(runtime["identifier"], [])
        for device in devices:
            if device["name"] == model and device["isAvailable"]:
                return device["udid"], runtime["identifier"], device["state"], device_type
    # Hosted runners do not pre-create every supported model. Create the exact
    # requested device with a runtime inside its declared compatibility range.
    for runtime in runtimes:
        major, minor, patch = version(runtime["version"])
        encoded = (major << 16) | (minor << 8) | patch
        if device_info.get("minRuntimeVersion", 0) <= encoded <= device_info.get("maxRuntimeVersion", 0xFFFFFFFF):
            return "uncreated", runtime["identifier"], "Shutdown", device_type
    raise ValueError(f"No compatible runtime for {model} with SDK {sdk}")


if __name__ == "__main__":
    try:
        print(*select(json.load(sys.stdin), sys.argv[1], sys.argv[2]))
    except ValueError as error:
        raise SystemExit(str(error)) from error
